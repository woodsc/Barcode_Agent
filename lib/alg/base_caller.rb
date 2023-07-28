=begin
lib/alg/base_caller.rb
Copyright (c) 2007-2023 University of British Columbia

Calls bases and mixtures

=end

require 'lib/recall_config'
require 'lib/conversions'

class BaseCaller
	extend SeqConversions

	def BaseCaller.call_bases(data, range = nil)
    #Get configuration data
    mixture_area_percent = RecallConfig['base_caller.mixture_area_percent'].to_f
    mark_area_percent = RecallConfig['base_caller.mark_area_percent'].to_f
    mark_50_percent = RecallConfig['base_caller.mark_50_percent']

		mark_avg_qual_cutoff = RecallConfig['base_caller.mark_average_quality_cutoff']
		remove_single_cov_inserts = RecallConfig['base_caller.remove_single_cov_inserts']

    mark_on_single_cov = RecallConfig['base_caller.mark_on_single_cov']
    num_bases = RecallConfig['base_caller.mark_after_single_cov_num'].to_i
    single_cov_limit = num_bases > 0 ? num_bases : nil

    use_background_subtraction = RecallConfig['base_caller.use_background_subtraction']
    #Turns synonymous mixture marking on/off
    mark_synonymous_mixtures = RecallConfig['base_caller.mark_synonymous_mixtures']

    secondary_cutoff_mod = RecallConfig['base_caller.mixture_secondary_cutoff_mod'].to_f
    mark_secondary_cutoff_mod = RecallConfig['base_caller.mark_secondary_cutoff_mod'].to_f

    mark_keylocs_permissive = RecallConfig['base_caller.mark_keylocs_permissive']
    mark_keylocs_cutoff = RecallConfig['base_caller.mark_keylocs_cutoff'].to_f
    keylocs_hash = keyloc_nuc_hash(RecallConfig['standard.keylocs'])
    invariant_list = []
    if(RecallConfig['standard.invariantlocs'] and RecallConfig['standard.invariantlocs'].is_a?(Array))
      invariant_list = RecallConfig['standard.invariantlocs'].split(',').map{|a| a.to_i}
    elsif(RecallConfig['standard.invariantlocs'])
      invariant_list = [RecallConfig['standard.invariantlocs'].to_i]
    end
    noqc_locs = []
    #if(RecallConfig['standard.noqc_locs'] and RecallConfig['standard.noqc_locs'].is_a?(Array))
    noqc_locs = RecallConfig['standard.noqc_locs'].split(',').map{|a| a.to_i} if(RecallConfig['standard.noqc_locs'])
    #elsif(RecallConfig['standard.noqc_locs'])
    #  noqc_locs = [RecallConfig['standard.noqc_locs'].to_i]
    #end

    alwaysmark_list = []
    if(RecallConfig['standard.alwaysmark_nuclocs'] and RecallConfig['standard.alwaysmark_nuclocs'].is_a?(Array))
      alwaysmark_list = RecallConfig['standard.alwaysmark_nuclocs'].split(',').map{|a| a.to_i}
    else
      alwaysmark_list = [RecallConfig['standard.alwaysmark_nuclocs'].to_i]
    end

    nuc_mismatches = 0

		data.assembled = ['-'] * data.standard.size if(range == nil)
    #put each ratio (well, technically percentage?) into their slots.  At the end, we'll normalize.
    mix_ratios = data.phred_mix_perc
    mix_ratios = Array.new(data.standard.size){ { 'A' => [], 'C' => [], 'G' => [], 'T' => [] } } if(range == nil)

    s_first = data.start_dex
    s_last = data.end_dex
    codon_pos = 0 #position 1, 2 or 3 of a nucleotide in a codon
    codon_pos_index = Array.new(3) #index in data.assembled that corresponds to each codon position
    nuc = Array.new(3) #Array of nucleotides for each codon position

    if(range != nil)
      s_first = range.begin if(range.begin >= data.start_dex)
      s_last = range.end if(range.end <= data.end_dex)
      #Remove human edits.
      data.human_edits.delete_if {|he| range.include?(he[0].to_i) }
      data.marks.delete_if {|mark| range.include?(mark.to_i) }
    end

    #for each base, do ....
		s_first.upto(s_last) do |i|
    #determine codon position of base
      if(data.standard[i] != '-')
        codon_pos_index[codon_pos] = i
        codon_pos = (codon_pos+1) % 3
		  end
      dex_list = data.get_dex_list_minus_inserts()

      #dex_list.index(i)
      if(dex_list.index(i) and noqc_locs.include?(dex_list.index(i) + 1)) #TMP  #Wait, how does this work with respect to inserts?
        data.primers.each() {|p| p.ignore[i] = 'Q' }
      end

      mix_ratios[i] = { 'A' => [], 'C' => [], 'G' => [], 'T' => [] }
      complete_calls = "" #test
      clean_calls = [] #[call, direction]


			#find relevant primers for this location (Primer coverage includes this location and quality is not low.
			primers = data.primers.find_all {|p| p.ignore[i] != 'L' and p.primer_start(true) <= i and p.primer_end(true) >= i}
      #get the coverage
			cov = primers.size
      #get the average quality at this location
			avg_qual = (primers.inject(0.0) {|sum, v|  sum += v.qual[i].to_i}) / cov
      #num will be used count each primers called and uncalled bases via some criteria
			num = {'A' => 0.0, 'T' => 0.0,'C' => 0.0,'G' => 0.0, 'N' => 0.0, '-' => 0.0}
      numstrict = {'A' => 0.0, 'T' => 0.0,'C' => 0.0,'G' => 0.0, 'N' => 0.0, '-' => 0.0}
      #num_marked will be used count each primers called and uncalled bases via some criteria
			num_marked = {'A' => 0.0, 'T' => 0.0,'C' => 0.0,'G' => 0.0, 'N' => 0.0, '-' => 0.0}
      #ms is the number of primers whos coverage is messy.
			ms = 0

      maxqual = ['-', 0]
      hasmix = false
      has_one_clean_nomix = false
      has_one_clean_mix = false

=begin
#Possible future changes.  A bit more indepth background subtraction method:
      #background correction skip criteria
      #If 1 primer is "Clean" and has an uncalled base above the threshold (threshold * 2) AND all primers have the same uncalled base THEN:  Skip(or reduce) correction.
      correction_hascleanmix = false
      correction_skip = true
      correction_uc = nil
      correction_skip_cnt = 0
      primers.each do |p|
        next if(!i.between?(p.primer_start(true), p.primer_end(true)))
        correction_skip = false if(p.uncalled[i] == '-')
        if(correction_uc == nil)
          correction_uc = p.uncalled[i]
        elsif(correction_uc != p.uncalled[i])
          correction_skip = false
        end

        #perhaps mixture_area_percent + 10%?
        if(p.uncalled[i] == correction_uc and p.uncalled_area[i].to_f > (mixture_area_percent * p.called_area[i].to_f) )
          #and CLEAN
          rng = BaseCaller.get_range(p, i, 10)
          if(rng.inject(0) {|sum, v| (v == i) ? sum : (sum + (p.uncalled_area[v].to_f > 0.0 ? 1 : 0)) } <= 7 )
            correction_hascleanmix = true
          end
        end

        correction_skip_cnt += 1
      end

      correction_skip = false if(correction_skip_cnt == 1 or correction_hascleanmix == false)
=end

      #The real game begins here.
			primers.each do |p|
        next if(!i.between?(p.primer_start(true), p.primer_end(true)))

        cutoff_a = (mixture_area_percent)
        cutoff_b = (mixture_area_percent - secondary_cutoff_mod)
        mark_cutoff_a = (mark_area_percent)
        mark_cutoff_b = (mark_area_percent - mark_secondary_cutoff_mod)

        if(p.uncalled[i] == 'N' and p.called[i] != '-' and p.called[i] != 'N' and p.qual[i].to_i >= 20)
          clean_calls << [p.called[i], p.direction]
        end

        #background subtraction
        correction = 0
        if(use_background_subtraction == 'true')
          rng = (i - 10 > p.primer_start(true) ? i - 10 : p.primer_start(true) + 1) .. (i + 10 < p.primer_end(true) ? i + 10 : p.primer_end(true) - 1)
          #rng = BaseCaller.get_range(p, i, 10)

=begin
#Possible future changes.  A bit more indepth background subtraction method:
          correction_multiplier = 1.5
          correction_multiplier /= 2.0 if(correction_skip)
=end
          #correction = rng.inject(0.0) {|sum, v| (v == i) ? sum : (sum + p.uncalled_area[v].to_f) }
          #correction_cnt = rng.inject(0) {|sum, v| (v == i) ? sum : (sum + (p.uncalled_area[v].to_f > 0.0 ? 1 : 0)) }
          correction = rng.inject(0.0) {|sum, v| (sum + p.uncalled_area[v].to_f) }
          correction_cnt = rng.inject(0) {|sum, v|  (sum + (p.uncalled_area[v].to_f > 0.0 ? 1 : 0)) }
=begin
#Possible future changes.  A bit more indepth background subtraction method:
          all_cnt = rng.inject(0) {|sum, v| (v == i) ? sum : (sum + 1) }
=end
          correction = (correction_cnt > 7 ? correction / correction_cnt.to_f : 0 ) * 1.0 #Subtract X percent
=begin
#Possible future changes.  A bit more indepth background subtraction method:
          correction = (correction / all_cnt.to_f)  * correction_multiplier #Subtract X percent
          correction = 0 if(correction_cnt <= 7)
=end

        end

        if(p.qual[i].to_i > maxqual[1])
          maxqual = [p.called[i], p.qual[i].to_i]
        end

#=begin
#Experimental, but seems helpful!
        is_clean = false
        rng = BaseCaller.get_range(p, i, 10)
        if(rng.inject(0) {|sum, v| (v == i) ? sum : (sum + (p.uncalled_area[v].to_f > 0.0 ? 1 : 0)) } <= 7 )
          is_clean = true
        end
        #puts [i, is_clean, p.uncalled[i] , p.qual[i].to_i, p.ignore[i]].inspect
        if(is_clean and p.uncalled[i] == 'N' and p.qual[i].to_i > 35 and p.ignore[i] != 'L')  #And qual should be higher than 30, 35?
          has_one_clean_nomix = true
        end
        if(is_clean and p.uncalled[i] != 'N' and p.ignore[i] != 'L' and p.uncalled_area[i].to_f - correction > (cutoff_a) * p.called_area[i].to_f )
          has_one_clean_mix = true #(or maybe it should be a count?)
        end

#=end

        #puts correction
        numstrict[p.called[i]] += 1
				num[p.called[i]] += 1 #add phreds call to the count.
				num_marked[p.called[i]] += 1 #add phreds call to the count.(for marks)

        #add the uncalled base to the count if the area under the curve is sufficient and its not messy here.
#				num[p.uncalled[i]] += 1 if(p.uncalled_area[i].to_f > mixture_area_percent.to_f * p.called_area[i].to_f and (p.ignore[i] != 'M'  or p.uncalled_area[i].to_f > mixture_messy_area_percent.to_f * p.called_area[i].to_f))
#          puts "#{p.primerid} #{num.inspect}" if(i - s_first >= 53 and i - s_first <= 53)

        #mix ratios
        if(p.called[i] != '-' and p.uncalled[i] != '-'  and p.uncalled[i] != p.called[i] and p.uncalled[i]  != 'N')
          mix_ratios[i][p.uncalled[i]] << [(p.uncalled_area[i].to_f) / (p.called_area[i].to_f), 0.0].max
          mix_ratios[i][p.called[i]] << 1.0
        elsif(p.called[i] != '-' and p.called[i] != 'N' )
          mix_ratios[i][p.called[i]] << 1.0
        end


        #Maybe have the custom code replace this entire section.  Would probably be the most elegant.
        # if(ProjectMethods.custom_basecalls(data, p, i, correction, cutoff_a, cutoff_b, mark_cutoff_a, mark_cutoff_b, num, num_marked)) #Project custom code
        if(p.uncalled_area[i].to_f - correction > (cutoff_a) * p.called_area[i].to_f and p.uncalled[i] != '-' and p.uncalled[i] != p.called[i] and p.uncalled[i]  != 'N')
        #if(p.uncalled_area[i].to_f - correction > (mixture_area_percent.to_f) * p.called_area[i].to_f and p.uncalled[i] != '-' and p.uncalled[i] != p.called[i])
          num[p.uncalled[i]] += 1.0
        elsif(p.uncalled_area[i].to_f - correction > (cutoff_b) * p.called_area[i].to_f and p.uncalled[i] != '-' and p.uncalled[i] != p.called[i] and p.uncalled[i]  != 'N')
        #elsif(p.uncalled_area[i].to_f - correction > (mark_area_percent.to_f) * p.called_area[i].to_f and p.uncalled[i] != '-' and p.uncalled[i] != p.called[i])
          num[p.uncalled[i]] += 0.5
        end
        #add the uncalled base to the count if the area under the curve is sufficient and its not messy here.
        #Maybe we shouldn't subtract messy calls from the marks???
#	    			num_marked[p.uncalled[i]] += 1 if(p.uncalled_area[i].to_f > mark_area_percent.to_f * p.called_area[i].to_f and (p.ignore[i] != 'M' or p.uncalled_area[i].to_f > mark_messy_area_percent.to_f * p.called_area[i].to_f))

        if(p.uncalled_area[i].to_f - (correction / 2) > (mark_cutoff_a.to_f) * p.called_area[i].to_f and p.uncalled[i]  != 'N')
          num_marked[p.uncalled[i]] += 1.0
        elsif(p.uncalled_area[i].to_f - (correction / 2) > (mark_cutoff_b.to_f) * p.called_area[i].to_f and p.uncalled[i]  != 'N')
          num_marked[p.uncalled[i]] += 0.5
        end
#sensitive marking based on key_loc position
#        if(mark_keylocs_permissive == 'true') #test
#          dex = dex_list.index(i)
#          if(dex != nil and keylocs_hash[dex + 1] != nil and keylocs_hash[dex + 1].include?(p.uncalled[i]))
#            num_marked[p.uncalled[i]] += 1.0
#          end
#        end

        #end
        #Turning samples orange if there is a incompatible mixture

        if(p.uncalled_area[i].to_f  > (cutoff_b) * p.called_area[i].to_f and p.uncalled[i] != '-' and p.uncalled[i] != p.called[i] and p.uncalled[i]  != 'N')
          #puts "mix #{i}: #{p.called[i]} #{p.uncalled[i]}"
          #don't add to compete calls
          hasmix = true
        elsif(p.called[i] != '-' and p.called[i] != 'N' and i > p.primer_start(true) + 6 and i < p.primer_end(true) - 6 and p.qual[i] > 20)
          #puts "?#{i}: #{p.primerid} #{p.called[i]}/#{p.uncalled[i]}" if(complete_calls != '' and !(complete_calls =~ /#{p.called[i]}/))
          complete_calls += p.called[i]  #test
        end

        ms += 1 if(p.ignore[i] == 'M') #add to messiness count if messy
#                puts "#{p.primerid} #{num.inspect}" if(i - s_first >= 53 and i - s_first <= 53)
      end



      #clean_calls << [p.called[i], p.direction]
      if(clean_calls.map(){|a| a[0] }.uniq.size() > 1)
        nuc_mismatches += 1
      end

      #orange and mark?  Should it be setting controlled?
      if(complete_calls.split('').uniq.size() > 1 and not hasmix)
        #This looks like it would work.....  Need to find a situation with it though.
        data.marks.push(i)
        data.keylocmarks.push(i)
        #puts "Discordance #{i} prev[#{data.assembled[i - 6, 6]}]: #{data.sample}: #{complete_calls}"
      end
      #normalize (sum, find the max, divide everything by that)

      #puts mix_ratios[i].inspect
      mix_ratios[i].each do |key, val|
        mix_ratios[i][key] = val.inject(0) {|sum, n| sum + n}
      end
      #puts mix_ratios[i].inspect
      tmp = [ mix_ratios[i]['A'], mix_ratios[i]['C'], mix_ratios[i]['G'], mix_ratios[i]['T'] ].max
      if(tmp != 0)
        mix_ratios[i]['A'] = mix_ratios[i]['A'] / tmp
        mix_ratios[i]['C'] = mix_ratios[i]['C'] / tmp
        mix_ratios[i]['G'] = mix_ratios[i]['G'] / tmp
        mix_ratios[i]['T'] = mix_ratios[i]['T'] / tmp
      else
        #puts data.sample
        mix_ratios[i] = {}
      end
      #puts "#{i - s_first}: \tA: #{mix_ratios[i]['A']} \tC: #{mix_ratios[i]['C']} \tG: #{mix_ratios[i]['G']} \tT: #{mix_ratios[i]['T']}"

#      printf "%d: A:%.2f C:%.2f G:%.2f T:%.2f\n", (i - s_first), mix_ratios[i]['A'], mix_ratios[i]['C'], mix_ratios[i]['G'], mix_ratios[i]['T']


			max = num.sort {|a, b| b[1] == a[1] ? b[0] <=> a[0] : b[1] <=> a[1]}[0][0] #find the most called base
			max_n = num.sort {|a, b| b[1] == a[1] ? b[0] <=> a[0] : b[1] <=> a[1]}[0][1] #most called count
			second = num.sort {|a, b| b[1] == a[1] ? b[0] <=> a[0] : b[1] <=> a[1]}[1][0] #find the second most called base
			second_n = num.sort {|a, b| b[1] == a[1] ? b[0] <=> a[0] : b[1] <=> a[1]}[1][1] #second most called count
      third = num.sort {|a, b| b[1] == a[1] ? b[0] <=> a[0] : b[1] <=> a[1]}[2][0] #find the third most called base
			third_n = num.sort {|a, b| b[1] == a[1] ? b[0] <=> a[0] : b[1] <=> a[1]}[2][1] #third most called count
#Sometimes we get ties of 3, in which case we should do something more complex, right?

      if( false and i - s_first > 920 and i - s_first < 960)
        puts (i - s_first).to_s + ":   " + [cov, max, max_n, second, second_n, third, third_n, data.standard[i]].join(", ")
      end





      if(false and ProjectMethods.custom_basecall_mix_criteria(data, i, cov, data.standard[i], max, max_n, second, second_n, third, third_n))
        data.assembled[i] = get_mix([max, second])
				data.marks.push(i) if (mark_synonymous_mixtures == 'true')
      elsif(cov == 0 and data.standard[i] == '-') #no coverage
        data.assembled[i] = '-'
        data.marks.push(i)
			elsif(cov == 1 and data.standard[i] == '-' and remove_single_cov_inserts == 'true')
				#This handles fake single base insertions(I hope!)
        #Hopefully removes fake single base insertions...  So far hasn't really come up.
				data.assembled[i] = '-'
        data.marks.push(i)
			elsif(cov == 0) #no coverage where their should be some...  Make an N.
				data.assembled[i] = 'N'
				data.marks.push(i)
      elsif(cov > 1 and data.standard[i] == '-' and ((max_n == 1 and [max, second, third].include?('-')) or max == '-'))
#        puts "KABOOM!"
        data.assembled[i] = '-'
      elsif(cov > 1 and data.standard[i] == '-' and numstrict['-'] >= (0.5 * cov.to_f))
        #puts "KABOOM"
        data.assembled[i] = '-'
			elsif(max == '-' and max_n == second_n)
        #if the number of deletions match the number of non-deletions, choose the non-deletions
				data.assembled[i] = second
        data.marks.push(i)
			elsif(max == '-' and max_n != second_n)
        #Seems to be a real deletion(or from the opposite point of view, a fake insertion)
				data.assembled[i] = '-'  #Kaboom must be happening here?
        data.marks.push(i)
			#elsif(second_n.to_f > (max_n.to_f / 2.0) and max_n >= 3 and second != '-')
      elsif(second_n.to_f > (max_n.to_f / 2.0) and max_n >= 2 and second != '-')
				#MIXTURE
				data.assembled[i] = get_mix([max, second])
				data.marks.push(i) if (mark_synonymous_mixtures == 'true')
			#elsif(second_n == max_n and max_n < 3  and second != '-')
				#MIXTURE
			#	data.assembled[i] = get_mix([max, second])
      #    data.marks.push(i) if (mark_synonymous_mixtures == 'true')
      elsif(second_n + third_n == max_n and max_n >= 3 and second !='-' and third !='-')
        data.assembled[i] = max
        data.marks.push(i) #Should be pretty rare!  Can't handle three way mixtures, so it marks it instead.
      elsif(cov == 1 and max_n == second_n and max != '-' and second != '-')
        data.assembled[i] = get_mix([max, second])
				data.marks.push(i) if (mark_synonymous_mixtures == 'true')
			elsif(cov == 2 and max != second and max_n == second_n and max != '-' and second != '-' and maxqual[0] != '-')
        data.assembled[i] = maxqual[0]
        data.marks.push(i)
      else
				#Just use max
				data.assembled[i] = max
			end

      #EXPERIMENTAL
      #Possible future changes.
#      if(has_one_clean_nomix and !has_one_clean_mix and data.assembled[i] == get_mix([max, second]) and max_n != second_n)
#        data.assembled[i] = max
#        data.marks.push(i)
#      end

=begin
            if(i - s_first >= 839 and i - s_first <= 840)
                puts "#{i}"
                puts "Max #{max} #{max_n}"
                puts "Second #{second} #{second_n}"
                puts "Num #{num.inspect}, Cov: #{cov}"
                puts "Final: '#{data.assembled[i]}'"
            end
=end
			#Add the nucleotide at this position (could be overwritten with a mixture value if a mark is made below)
			nuc[codon_pos-1] = data.assembled[i,1] if (mark_synonymous_mixtures == 'false')

			#Check for marks
			max = num_marked.sort {|a, b| b[1] <=> a[1]}[0][0]
			second = num_marked.sort {|a, b| b[1] <=> a[1]}[1][0]
			max_n = num_marked.sort {|a, b| b[1] <=> a[1]}[0][1]
			second_n = num_marked.sort {|a, b| b[1] <=> a[1]}[1][1]

			if(cov == 0)
				data.marks.push(i)
      elsif(dex_list.index(i) and alwaysmark_list.include?(dex_list.index(i) + 1))   #hmmm  will this die on inserts?
        data.marks.push(i)
      elsif(cov == 1 and (mark_on_single_cov == 'true' or single_cov_limit))
        data.marks.push(i) if((mark_on_single_cov == 'true' or single_cov_limit <= 0) and (!noqc_locs.include?((dex_list.index(i) ? dex_list.index(i) : 99999) - 1)))
        # Decrement single_cov_limit count
        single_cov_limit -=1 if single_cov_limit
			elsif(max == '-' and max_n == second_n)
				data.marks.push(i)
			elsif(max == '-' and max_n != second_n)
				data.marks.push(i)
			elsif(second_n.to_f >= (max_n.to_f / 2.0) + (mark_50_percent == 'true' ? 0 : 0.01) and max_n >= 3 and second != '-')
        #If we're not marking synonymous mixtures, add the nucleotide (which could be a mixture) at this position
        (mark_synonymous_mixtures == 'true')? data.marks.push(i): nuc[codon_pos-1]=get_mix([max, second])
			elsif(second_n == max_n and max_n < 3  and second != '-')
        #If we're not marking synonymous mixtures, add the nucleotide (which could be a mixture) at this position
        (mark_synonymous_mixtures == 'true')? data.marks.push(i): nuc[codon_pos-1]=get_mix([max, second])
			elsif(avg_qual < mark_avg_qual_cutoff)
				data.marks.push(i)
#			elsif(cov - ms == 0) #Mark if the messiness makes 0 coverage
#				data.marks.push(i)
			end

      if(dex_list.index(i) and noqc_locs.include?(dex_list.index(i) + 1))
        data.primers.each() {|p| p.ignore[i] = 'Q' }
      end

			#At 3rd base position in codon, look back and see if any mixtures or marks cause a change in amino acid
      mark_non_synonymous(codon_pos_index, nuc, data) if (codon_pos == 0 and mark_synonymous_mixtures == 'false')
		end

    data.phred_mix_perc = mix_ratios

    ProjectMethods.custom_marks(data) #Project custom code

    #SECOND LOOP
    dex_list = data.get_dex_list_minus_inserts()
    keylocs_hash = keyloc_aa_hash(RecallConfig['standard.keylocs'])

    0.upto((dex_list.size / 3) - 1) do |i|
      if(mark_keylocs_permissive == 'true') #test
        nuc = [data.assembled[dex_list[i * 3]], data.assembled[dex_list[i * 3 + 1]], data.assembled[dex_list[i * 3 + 2]]]
        std = [data.standard[dex_list[i * 3]], data.standard[dex_list[i * 3 + 1]], data.standard[dex_list[i * 3 + 2]]]
        aa = translate(nuc)
        stdaa = translate(std)
        #check the invariants
        if(invariant_list.include?(i + 1) and aa != stdaa)
          [dex_list[i * 3], dex_list[i * 3 + 1], dex_list[i * 3 + 2]].each do |pi|
            data.marks.push(pi)
            data.keylocmarks.push(pi)
          end
        end


        next if(keylocs_hash[i + 1] == nil or aa.any? {|a| keylocs_hash[i + 1].include?(a)}) #If the amino is ALREADY the mutation, then don't worry about it.
        #Now, we see if we have any uncalled bases that lead to mutation.
        [dex_list[i * 3], dex_list[i * 3 + 1], dex_list[i * 3 + 2]].each_with_index do |pi, j|
          primers = data.primers.find_all {|p| p.ignore[pi] != 'L' and p.primer_start(true) <= pi and p.primer_end(true) >= pi}
          cov = primers.size
          num_marked = {'A' => 0.0, 'T' => 0.0,'C' => 0.0,'G' => 0.0, 'N' => 0.0, '-' => 0.0}
          text_check = []
          primers.each do |p|
            next if(!pi.between?(p.primer_start(true), p.primer_end(true)))

            correction = 0.0
            if(use_background_subtraction == 'true')
              rng = (pi - 10 > p.primer_start(true) ? pi - 10 : p.primer_start(true) + 1 ) .. (pi + 10 < p.primer_end(true) ? pi + 10 : p.primer_end(true) - 1)
              correction = rng.inject(0.0) {|sum, v| sum + p.uncalled_area[v].to_f }
              correction_cnt = rng.inject(0.0) {|sum, v| sum += p.uncalled_area[v].to_f > 0.0 ? 1.0 : 0.0 }
              correction = (correction_cnt > 7 ? correction / correction_cnt : 0 ) * 1.0 #Subtract X percent
            end
            text_check.push(p.called[pi])
            text_check.push(p.uncalled[pi])
            num_marked[p.uncalled[pi]] += 1.0 if(p.uncalled[pi] != 'N' and p.uncalled_area[pi].to_f - correction > mark_keylocs_cutoff * p.called_area[pi].to_f) #if(p.uncalled_area[pi].to_f > 0.1 * p.called_area[pi].to_f)
          end
          max = num_marked.sort {|a, b| b[1] == a[1] ? b[0] <=> a[0] : b[1] <=> a[1]}[0][0] #find the most called base
          max_n = num_marked.sort {|a, b| b[1] == a[1] ? b[0] <=> a[0] : b[1] <=> a[1]}[0][1] #most called count
=begin
          if(i == 279 or i == 280 or i== 281)
            puts max
            puts max_n
            puts cov
            puts text_check.inspect
          end
=end
          text_check.uniq!
          text_check.delete_if {|a| !['A','T','G','C'].include?(a) }


          next if(max == 'N' or max == '-' or (max_n.to_f / cov.to_f < 0.5 and max_n < 2) or max_n < 1)
          #next if(max == 'N' or max == '-' or (max_n.to_f / cov.to_f < 0.5) or max_n < 1)
          text_check.each do |tc|
            copynuc = Array.new(nuc)
            copynuc[j] = tc
            copyaa = translate(copynuc)
            if(copyaa.any? {|a| keylocs_hash[i + 1].include?(a)}) #Add a mark
#            puts max
#            puts max_n
#            puts cov
#            puts nuc
#            puts copynuc
#            puts aa
#            puts copyaa
              data.marks.push(pi)
              data.keylocmarks.push(pi)
              break
#            puts data.sample
#            puts "marked at amino #{i + 1}, #{num_marked.inspect}"
#            puts "\t#{copynuc.join('')} #{copyaa.inspect}, #{keylocs_hash[i + 1].inspect}"
            end
          end

        end

      end
    end

    #Mask start and end bits
    begin
      st_mask_cnt = RecallConfig['base_caller.mask_ns_start'].to_i
      en_mask_cnt = RecallConfig['base_caller.mask_ns_end'].to_i
      mod = 0
      i = 0
      while(i < data.standard.size() - 1)
        if(data.standard[i] != '-') #found the start of the sequence
          j = i
          break if(!(data.assembled[i] == 'N' or data.assembled[i] == '-'))
          while(j - mod <= i + st_mask_cnt - 1)
            if(data.standard[j] == '-') #Gappy thing, don't include it
              mod += 1
            elsif(data.assembled[j] == 'N' or data.assembled[j] == '-')  #An N, remove it!
              data.assembled[j] = '+'
              data.marks.delete(j)
              #puts "removing N from start"
            elsif((j - mod - i) % 3 != 0 ) #Something reasonable, but we are out of frame.  Remove it!
              data.assembled[j] = '+'
              data.marks.delete(j)
              #puts "removing X from start"
            else
              break #Done!
            end
            j += 1
          end
          break #okay, we are done here.
        end
        i += 1
      end

      mod = 0
      i = data.standard.size() - 1
      while(i > 0)
        if(data.standard[i] != '-') #found the start of the sequence
          j = i
          break if(!(data.assembled[i] == 'N' or data.assembled[i] == '-'))
          while(j + mod >= i - en_mask_cnt + 1)
            #puts  "#{i} #{j} #{mod}"
            if(data.standard[j] == '-') #Gappy thing, don't include it
              mod += 1
              #puts "Adding mod"
            elsif(data.assembled[j] == 'N' or data.assembled[j] == '-')  #An N, remove it!
              data.assembled[j] = '+'
              data.marks.delete(j)
              #puts "removing N from end"
            elsif((j - mod - i) % 3 != 0 ) #Something reasonable, but we are out of frame.  Remove it!
              data.assembled[j] = '+'
              data.marks.delete(j)
              #puts "removing X from end"
            else
              #puts "Breaking"
              break #Done!
            end
            j -= 1
          end
          break #okay, we are done here.
        end
        i -= 1
      end

    end


    data.keylocmarks.uniq!
    data.keylocmarks.sort!
    data.marks.uniq! #Get rid of multiple marks at same location.
    data.marks.sort!
    data.nuc_mismatches = nuc_mismatches

    if(range == nil)
      data.remove_double_dashes()
    end


	end

  #returns a range in context of a primer
  def BaseCaller.get_range(primer, i, size)
    a = i
    b = i
    n = size
    while(a > primer.primer_start(true) and n > 0)
      a -= 1
      n -= 1 if(primer.loc[a] != '-')
    end
    n = size
    while(b < primer.primer_end(true) and n > 0)
      b += 1
      n -= 1 if(primer.loc[b] != '-')
    end
    rng = (a .. b)
  end

	# Marks all the mixtures that cause an amino acid variation
	def BaseCaller.mark_non_synonymous(codon_pos_index, nuc, data)

	  #puts "Pos: #{codon_pos_index[0]},#{codon_pos_index[1]},#{codon_pos_index[2]}: #{nuc}"
	  aa = translate(nuc).join('')

	  # Check if codon produces amino acid variation. If not, we're done!
	  return if(aa.length==1)

	  # Otherwise...Go through each mixture and check if it affects the amino acid outcome while holding the other bases constant
	  posa = get_mix_contents([nuc[0,1]].flatten()[0])
	  posb = get_mix_contents([nuc[1,1]].flatten()[0])
	  posc = get_mix_contents([nuc[2,1]].flatten()[0])
#    puts "#{codon_pos_index}\t#{nuc.inspect}\t#{posa.inspect} #{posb.inspect} #{posc.inspect}"

	  # These loops are ugly...Is there a better way?

	  if(posa.length>1)
    #First base position
      catch :LOOP_A do
        posc.each do |c|
            posb.each do |b|
              aa = nil
              posa.each do |a|
                nuc = [a+b+c]
                aa = translate(nuc) if aa == nil
                #puts "#{nuc} => #{translate(nuc)}"
                if(aa!= translate(nuc))
                  data.marks.push(codon_pos_index[0])
                  #puts "Pos #{codon_pos_index[0]} Changes AA"
                  throw :LOOP_A
                end
              end #posa
            end #posb
        end #posc
      end #LOOP_A
    end

    if(posb.length>1)
    #Second base position
      catch :LOOP_B do
        posc.each do |c|
          posa.each do |a|
            aa = nil
            posb.each do |b|
              nuc = [a+b+c]
              aa = translate(nuc) if aa == nil
              #puts "#{nuc} => #{translate(nuc)}"
              if(aa!= translate(nuc))
                data.marks.push(codon_pos_index[1])
                #puts "Pos #{codon_pos_index[1]} Changes AA"
                throw :LOOP_B
              end
            end #posb
          end #posa
        end #posc
      end #LOOP_B
    end

    if(posc.length>1)
      #Third base position
      catch :LOOP_C do
        posa.each do |a|
          posb.each do |b|
            aa = nil
            posc.each do |c|
              nuc = [a+b+c]
              aa = translate(nuc) if aa == nil
              #puts "#{nuc} => #{translate(nuc)}"
              if(aa!= translate(nuc))
                data.marks.push(codon_pos_index[2])
                #puts "Pos #{codon_pos_index[2]} Changes AA"
                throw :LOOP_C
              end
            end #posc
          end #posb
        end #posa
      end #LOOP_C
    end

  end
end
