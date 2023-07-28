=begin
lib/alg/quality_checker.rb
Copyright (c) 2007-2023 University of British Columbia

Checks to see if quality is OK
=end

require 'lib/conversions'
require 'lib/recall_config'
require 'lib/utils'
require 'lib/version'

#How to record errors?
class QualityChecker
  include SeqConversions

	def QualityChecker.reset(data)
		data.errors = []
		data.qa = QaData.new
	end

	def QualityChecker.check(data)

    #Make sure L's are properly added to missing primer data.
    data.primers.each do |primer| #pre-cache
      primer.primer_start(false)
      primer.primer_end(false)
    end
    data.start_dex.upto(data.end_dex) do |i|
      data.primers.each do |primer|
        ps = primer.primer_start(true)
        pe = primer.primer_end(true)
        if(data.assembled[i] != '-' and primer.edit[i] == '-' and i >= ps and i <= pe)
          primer.ignore[i] = 'L'
        end
      end
    end

		#check for stop codons?
    seq_no_insert = nil
		seq = data.export_seq #we don't use this?
		dex_list = data.get_dex_list
    dex_list_no_ins = data.get_dex_list_minus_inserts
    seq_no_insert = ''

    noqc_locs = []
    #if(RecallConfig['standard.noqc_locs'] and RecallConfig['standard.noqc_locs'].is_a?(Array))
    noqc_locs = RecallConfig['standard.noqc_locs'].split(',').map{|a| a.to_i} if(RecallConfig['standard.noqc_locs'])

    0.upto(data.standard.length - 1) do |i|
      if(data.assembled[i] != '-' and data.standard[i] != '-')
        seq_no_insert += data.assembled[i]
      end
    end
   #Do a quick mark of insertions and deleltions
    0.upto(data.assembled.size - 1) do |i|
      if(data.assembled[i] == '+') #get rid of fake masking
        data.assembled[i] = '-'
      elsif(data.assembled[i] != '-' and data.standard[i] == '-')
        data.marks.push(i)
      elsif(data.assembled[i] == '-' and data.standard[i] != '-' and data.standard[i] != 'X')
        data.marks.push(i)
      end
      if(data.assembled[i] == '-' and (data.standard[i] == '-' or data.standard[i] == 'X')) #Remove these marks, as they should never have been marked.
        data.marks.delete_if(){|a| a == i }
      end
    end

    data.marks.uniq!
    data.marks.sort!
    stopmix_cnt = 0
		if(RecallConfig['quality_checker.check_stop_codons'] == 'true')

			0.upto((seq_no_insert.size / 3) - 1) do |i|
				nuc = seq_no_insert[i * 3, 3]
				if(nuc == 'TGA' or nuc == 'TAA' or nuc == 'TAG' or nuc == 'TRA' or nuc == 'TAR')
					#record error
					data.qa.stop_codons=true
					data.errors.push("Stop codon at nucleotide #{(i * 3) + 1}: #{nuc} (#{i + 1})")
				end
        if(nuc =~ /[RYKMSWBDHVN]/ and translate(nuc).include?('*') and nuc != 'NNN')
          stopmix_cnt += 1
        end
			end
		end

    #puts "Stop Mixes: #{stopmix_cnt}"
    if(stopmix_cnt > RecallConfig['quality_checker.max_stop_codon_mixtures'].to_i)
      data.qa.failed = true
      data.errors.push("#{stopmix_cnt} mixtures containing stop codons found.")
    end

		if(RecallConfig['quality_checker.check_manymixtures'] == 'true')
			mixture_cnt = data.mixture_cnt
      #no_qc_mix = Array.new(data.mixtures).delete_if{|i| noqc_locs.include?(dex_list_no_ins.index(i) - 1)  }.size()
      no_qc_mixes = 0
      0.upto(data.standard.size() - 1) do |i|
        if(data.standard[i] != '-' and data.assembled[i] =~  /[BDHVRYKMSWN]/  and noqc_locs.include?((dex_list_no_ins.index(i) ? dex_list_no_ins.index(i) : 99999) + 1))
          no_qc_mixes += 1
        end
      end

			if((mixture_cnt - no_qc_mixes) > RecallConfig['quality_checker.max_mixtures'].to_i)
				data.qa.manymixtures=true
				data.errors.push("Too many mixtures: #{mixture_cnt}")
			end
		end

		if(RecallConfig['quality_checker.check_manyns'] == 'true')
			n_cnt = data.n_cnt
			if(n_cnt > RecallConfig['quality_checker.max_ns'].to_i)
				data.qa.manyns=true
				data.errors.push("Too many N's: #{n_cnt}")
			end
		end

		if(RecallConfig['quality_checker.check_manymarks'] == 'true')
			mark_cnt = data.mark_cnt
      no_qc_marks = Array.new(data.marks).delete_if{|i| no_qc_marks == [] or !noqc_locs.include?((dex_list_no_ins.index(i) ? dex_list_no_ins.index(i) : 99999) + 1)  }.size()
      #puts "#{data.sample} #{mark_cnt} #{no_qc_marks}"
			if((mark_cnt - no_qc_marks) > RecallConfig['quality_checker.max_marks'].to_i)
				data.qa.manymarks=true
				data.errors.push("Too many marks: #{mark_cnt}")
			end
		end


		lowcov=0
		lowcov_list = []
		qlowcov=0
		qlowcov_list = []
		data.start_dex.upto(data.end_dex) do |i|
			if(data.assembled[i] != '-')
        next if(dex_list_no_ins.index(i) and noqc_locs.include?(dex_list_no_ins.index(i) + 1))

				primers = data.primers.find_all {|p| p.primer_start(true) <= i and p.primer_end(true) >= i}
				qprimers = data.primers.find_all {|p| p.ignore[i] != 'L' and p.primer_start(true) <= i and p.primer_end(true) >= i and p.edit[i] != '-'}
				cov = primers.size
				qcov = qprimers.size

        qual = primers[0].qual[i] if(primers[0] != nil)
        qual = 0 if(qual.nil? or qual == '-')
				lowcov += 1 if(cov < 2 and qual < 40)
				qlowcov += 1 if(qcov == 0)

				lowcov_list.push(dex_list.index(i)) if(cov < 2  and qual < 40) #TODO: MAY NEED TO ADD ONE
				qlowcov_list.push(dex_list.index(i)) if(qcov == 0) #TODO: MAY NEED TO ADD ONE
			end
		end

		qlowcov_list = qlowcov_list - lowcov_list if(lowcov > RecallConfig['quality_checker.max_single_coverage'].to_i)
		qlowcov = qlowcov_list.size

		lowcov_list = lowcov_list.uniq.sort.compact_ranges
		qlowcov_list = qlowcov_list.uniq.sort.compact_ranges

		if(RecallConfig['quality_checker.check_manysinglecov'] == 'true')
			if(lowcov > RecallConfig['quality_checker.max_single_coverage'].to_i)
				data.qa.manysinglecov=true
				data.errors.push("Too much single coverage: #{lowcov} bases of single coverage at bases #{lowcov_list.join('; ')}")
			end
		end
		if(RecallConfig['quality_checker.check_badqualsection'] == 'true')
			if(qlowcov > 0)
				data.qa.badqualsection=true
				data.errors.push("Bad quality area in sequence at bases #{qlowcov_list.join('; ')}")
			end
		end

		if(RecallConfig['quality_checker.check_hasinserts'] == 'true')
			inserts = []
			common_points = nil
			if(RecallConfig['insert_detector.common_insert_points'] == '*')
                common_points = (3 .. data.standard.size - 4).to_a
                common_points.delete_if {|a| a % 3 != 0}
            else
                common_points = RecallConfig['insert_detector.common_insert_points'].split(',').map {|a| a.to_i }
            end
			0.upto(dex_list.size - 1) do |i|
				if(data.assembled[dex_list[i]] != '-' and data.standard[dex_list[i]] == '-')
					inserts.push(i)
                    data.qa.hasinserts=true
				end
			end
			inserts = inserts.compact_ranges
			inserts.map! {|a| a.class != Range ? (a .. a) : a}

			shift = 0

			inserts.each do |ins|
#				puts ins.inspect
				txt = ''
				dex = ins
				closest = common_points.inject(20000) {|mem, v| mem = (((v + shift) - dex.begin).abs > (mem - dex.begin).abs ? mem : (v + shift)) }
				if(ins.to_a.size % 3 != 0)
          #data.errors.push("Stop codon at nucleotide #{(i * 3) + 1}: #{nuc} (#{i + 1})")
					data.errors.push("Bad insert at #{ins.begin} (#{((ins.begin + 2) / 3).to_i}) of size #{(ins.end - ins.begin) + 1}: #{(data.assembled[dex_list[ins.begin] .. dex_list[ins.end]] - ['-']).join('')}")
          data.qa.hasbadinserts=true
				elsif((closest - dex.begin).abs != 0) #shouldn't this be != 0?
					data.errors.push("Bad insertion location at #{dex.begin} (#{((dex.begin + 2) / 3).to_i}) of size #{(dex.end - dex.begin) + 1}")
          data.qa.hasbadinserts=true
        else
          data.errors.push("OK insert at #{dex.begin} (#{((dex.begin + 2) / 3).to_i}) of size #{(dex.end - dex.begin) + 1}")
				end
				shift += ins.to_a.size
			end
		end

		if(RecallConfig['quality_checker.check_hasdeletions'] == 'true')
			deletes = []
			data.start_dex.upto(data.end_dex) do |i|
				if(data.assembled[i] == '-' and data.standard[i] != '-')
          data.qa.hasdeletions=true
					deletes.push(dex_list.index(i))
				end
			end

			deletes = deletes.compact_ranges
			deletes.each do |i|
				if(i.class != Range or i.to_a.size % 3 != 0 or (i.begin % 3 != 0 and RecallConfig['insert_detector.frame_align_deletions'] == 'true'))
					data.errors.push("Bad deletion at #{i.class == Range ? i.begin : i } (#{(((i.class == Range ? i.begin : i) + 3) / 3).to_i}) of size #{i.class == Range ? (i.end - i.begin) + 1 : 1 }")
          data.qa.hasbaddeletions=true
				end
			end
		end


    keylocs = keyloc_nuc_hash(RecallConfig['standard.keylocs']).keys

    invariantlocs = []
    if(RecallConfig['standard.invariantlocs'] and RecallConfig['standard.invariantlocs'].is_a?(Array))
      invariantlocs = RecallConfig['standard.invariantlocs'].split(',').map{|a| a.to_i}
    elsif(RecallConfig['standard.invariantlocs'])
      invariantlocs = [RecallConfig['standard.invariantlocs'].to_i]
    end


    nucdex = 1
    0.upto(data.standard.size - 1) do |i|
      if(data.standard[i] != '-')
        #If IS a mark within keylocs
        if((keylocs.include?(nucdex) or invariantlocs.include?((nucdex / 3).to_i + 1)) and data.keylocmarks.include?(i))
        #if(data.keylocmarks.include?(i))
          data.qa.hasmarkedkeylocs = true
        end
        nucdex += 1
      end
    end

    #Check for atypical mutations.
    #Orange and warn if atypical mut found, red if it passes the threshold(if there is a threshold)
    if(RecallConfig['standard.typical_mutations'] and RecallConfig['standard.typical_mutations'] != '')
      typical_mutations = RecallConfig['standard.typical_mutations'].split(',')
      cnt = 0

      seq = data.export_seq_no_inserts()
      0.upto((seq.size() / 3) - 1) do |i|
        next if(seq[i * 3, 3] == nil or seq[i * 3, 3].include?('N'))
        aas = translate(seq[i * 3, 3])
        typical = true
        aas.each do |aa|
          next if(aa == nil)
          if(!typical_mutations[i].include?(aa) and !['X','-','*'].include?(aa))
            typical = false
            data.errors.push("Suspicious atypical mutation #{aa} at codon (#{i + 1}) found.")
            data.marks.push(dex_list_no_ins[i * 3])
            data.marks.push(dex_list_no_ins[i * 3 + 1])
            data.marks.push(dex_list_no_ins[i * 3 + 2])
          end
        end

        if(!typical) #Make orange
          cnt += 1
          data.qa.suspicious = true
        end

      end

      if(RecallConfig['quality_checker.max_atypical_mutations'] and cnt > RecallConfig['quality_checker.max_atypical_mutations'].to_i)
        data.errors.push("Too many atypical mutations found")
        data.qa.failed = true
      end

    end

    #SPECIAL APOBEC CODE.  DRT AND INT ONLY.
    if(RecallConfig['quality_checker.check_apobec'] == 'true')
      limit = RecallConfig['quality_checker.apobec_limit'].to_i
      phase1 = RecallConfig['standard.apobec_phase1'].split(',').map(){|a| [a.split(':')[0].to_i, a.split(':')[1].split('') ]  }
      phase2 = RecallConfig['standard.apobec_phase2'].split(',').map(){|a| [a.split(':')[0].to_i, a.split(':')[1].split('') ]  }
      #apobec phases look like [3, ['A','T']], [6, ['A']]
      seq = data.export_seq_no_inserts()
      cnt = 0
      goto_phase2 = false
      #If we match any phase one mutation, procede to phase 2.
      phase1.each do |p1|
        break if(goto_phase2)
        next if(seq[ (p1[0] - 1) * 3, 3 ] == nil or seq[(p1[0] - 1) * 3, 3].include?('N'))
        aas = translate(seq[ (p1[0] - 1) * 3, 3 ])
        aas.each do |aa|
          next if(aa == nil)
          if(p1[1].include?(aa))
            #FOUND THE PHASE 1 MUTATION.  PROCEDE TO PHASE 2
            #puts "TTRIGGGEREDD #{data.sample}"
            goto_phase2 = true
          end
        end
      end

      if(goto_phase2)
        phase2.each do |p2|
          next if(seq[ (p2[0] - 1) * 3, 3 ] == nil or seq[ (p2[0] - 1) * 3, 3 ] == "" or seq[(p2[0] - 1) * 3, 3].include?('N'))
          aas = translate(seq[ (p2[0] - 1) * 3, 3 ])
          aas.each do |aa|
            next if(aa == nil)
            if(p2[1].include?(aa))
              #FOUND THE PHASE 1 MUTATION.  PROCEDE TO PHASE 2
              #puts "APOBEC MUT DETECTED #{p2[0]},#{aa}"
              cnt += 1
            end
          end
        end
      end

      #If we match more than LIMIT phase 2 mutations, then fail.
      if(cnt > limit)
        data.qa.failed = true
        data.errors.push("#{limit}+ APOBEC mutations detected, failing sequence.")
      end

    end

    data.marks.uniq!
    data.marks.sort!
    data.qa.autogood = true if(!data.qa.hasmarkedkeylocs and data.qa.mostly_good and RecallConfig['common.autoapprove'] == 'true' and !data.qa.suspicious)
    data.qa.terrible = true if(data.mark_cnt > seq_no_insert.size.to_f * RecallConfig['quality_checker.terrible_mark_perc'].to_f)
    data.aligned=true
    #set version info
    data.recall_version = $VERSION
    data.recall_version_date = $RELEASE_DATE
	end

  #This is going to need a lot of testing to make sure it doesn't crash when weird stuff is run.
  #Mapping is an optional thing(used for webrecall) to rename the samples in the error message..
  def QualityChecker.check_set(rd_set, mapping={}) #array of recall data objects
    if(RecallConfig['quality_checker.check_genetic_distance'] == 'true')
      dist_cutoff = RecallConfig['quality_checker.genetic_distance_cutoff'].to_f #In percent
      #Call the QA code to check the genetic distance?
      rd_set.each_with_index do |rd, i|
        changed = false
        #Compare to each other rd
        seq = rd.export_seq_no_inserts
        next if(seq =~ /^N+$/) #Skip the ones with no data
        #Now compare against the others.
        rd_set.each_with_index do |o_rd, j|
          next if(i == j)
          o_seq = o_rd.export_seq_no_inserts
          dist = 0
          #compare genetic distance.  Maybe we should do it by amino...
          0.upto([seq.size(), o_seq.size()].min() - 1) do |k|
          #0.upto([seq.size() / 3, o_seq.size() / 3].min() - 1) do |k|
            aaloc = (k / 3)
            begin
              if(seq[k, 1] != o_seq[k, 1] and translate(seq[aaloc * 3, 3]) != translate(o_seq[aaloc * 3, 3])) #eh, maybe we shouldn't include compatible mixtures?  #Or only include changes that don't result in an AA change?
                #Check to see if compatible difference?
                dist += 1
              end
            rescue
              #pass
            end
          end

          #puts "Dist of #{rd.sample} -> #{o_rd.sample}:  #{dist}, or #{(dist.to_f / (seq.size().to_f)) * 100}%"
          if(dist.to_f / (seq.size().to_f) < dist_cutoff)
            rd.qa.suspicious = true
            rd.qa.autogood = false #I think this is right.

            rd.errors.push("Genetic distance is within #{dist_cutoff * 100}% of #{mapping[o_rd.sample] ? mapping[o_rd.sample] : o_rd.sample}.  Possible contamination detected.")
            changed = true
          end
        end
        rd.save() if(changed)
      end
    end

  end

end
