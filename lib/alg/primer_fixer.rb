=begin
lib/alg/primer_fixer.rb
Copyright (c) 2007-2023 University of British Columbia

Fixes up primers
=end

require 'lib/recall_config'

class PrimerFixer
	#Smelts together identical phred calls.
	#On rare occasions, we should combine two calls of the same location, but different calls.
	def PrimerFixer.smelt(data)
		data.primers.each do |p|
			0.upto(p.edit.length - 2) do |i|
				if(p.edit[i] == p.edit[i + 1] and
				(p.loc[i].to_i - p.loc[i+1].to_i).abs < 10 and
				(p.called_area[i].to_i - p.called_area[i+1].to_i).abs < 2.0)
					p.ignore[i] = 'D' #kill it for being a duplicate
				elsif(p.edit[i] != p.edit[i + 1] and
					p.edit[i] != 'N' and p.edit[i+1] != 'N' and
					(p.loc[i].to_i - p.loc[i+1].to_i).abs < 2)
				#Combine different calls.
					if(p.called_area[i] > p.called_area[i+1])
						p.ignore[i + 1] = 'D' #kill the smaller one
						p.uncalled[i] = p.called[i + 1]
						p.uncalled_area[i] = p.called_area[i + 1]
					else
						p.ignore[i] = 'D' #kill the smaller one
						p.uncalled[i + 1] = p.called[i]
						p.uncalled_area[i + 1] = p.called_area[i]
					end
        elsif(p.edit[i] == 'N' and p.called_area[i] == -1)
          #Stupid phred put in a N for no reason.  Kill it!
          p.ignore[i] = 'D'
				end
			end

			while(i = p.ignore.index('D'))
				p.called.delete_at(i)
				p.uncalled.delete_at(i)
				p.called_area.delete_at(i)
				p.uncalled_area.delete_at(i)
				p.loc.delete_at(i)
				p.qual.delete_at(i)
				p.ignore.delete_at(i)
				p.edit.delete_at(i)
        p.amp_a.delete_at(i)
        p.amp_c.delete_at(i)
        p.amp_g.delete_at(i)
        p.amp_t.delete_at(i)
			end
		end
	end


	#perhaps it should also scan for messiness(lots of uncalled bases in a region)
  #I wonder if we should do the same as the trim.  Keep bases with quality above 50.
	def PrimerFixer.scan_quality(data)
		minQualityForCall = RecallConfig['primer_fixer.basecall_quality_cutoff'].to_i
    foreground_peak_percent  = RecallConfig['primer_fixer.foreground_peak_percent'].to_i
    #blankout_messy_data = RecallConfig['primer_fixer.blankout_messy_data'] == 'true'

		data.primers.each do |p|
			0.upto(p.qual.size - 1) do |i|
				if(p.qual[i] != '-' and p.qual[[i - 2, 0].max, 5].any? {|q| q != '-' and q.to_i < minQualityForCall } )
					p.ignore[i] = 'L' if(p.qual[i] < 50) #L for LOW QUALITY
				end

        if(i > 5 and i < p.qual.size - 6 and p.ignore[i] != 'L' and p.qual[i] != '-' )
          tmp = []
          (i - 5).upto(i+5) do |j|
            tmp.push((([p.amp_a[j], p.amp_c[j], p.amp_g[j], p.amp_t[j]].max.to_f / (p.amp_a[j] + p.amp_c[j] + p.amp_g[j] + p.amp_t[j]).to_f) * 100).to_i)  if(p.amp_a[j] != '-' and p.amp_a[j] != nil and [p.amp_a[j], p.amp_c[j], p.amp_g[j], p.amp_t[j]] != [0,0,0,0])
          end
          if(tmp.find_all {|u| u  < foreground_peak_percent }.size >= 8)
            p.ignore[i] = 'L' if(p.qual[i] < 50) #L for LOW QUALITY
          end
        end

        #Low amplitudes (I kinda like this)
#        if([p.amp_a[i],p.amp_c[i],p.amp_g[i],p.amp_t[i]].max < 3000)
#          p.ignore[i] = 'L'
#        end

        # You could check to see if things are REALLY messy by using the percent of area under the peak or something...
#				if(i > 15 and i < p.qual.size - 16 and p.ignore[i] != 'L' and p.qual[i] != '-' and p.uncalled[i] =~ /[ATGC]/  and p.uncalled[i - 15, 30].find_all {|u| u =~ /[ATGC]/ }.size.to_f / 30.0 > 0.40 )
#					p.ignore[i] = 'M' #M for MESSY
#        end
			end
		end
	end

	#Trims low quality junk off the end of the primers
	def PrimerFixer.trim(data)
		qualityCutoff = RecallConfig['primer_fixer.trim_quality_cutoff'].to_i
		scanWindow = RecallConfig['primer_fixer.trim_scan_window'].to_i

		data.primers.each do |p|
			cut = -1
			#cut off low qual at start
			0.upto(p.length - scanWindow) do |i|
#				if((p.qual[i, scanWindow].inject(0) {|sum, v| sum + v.to_i } / scanWindow) >= qualityCutoff and (p.called[i, scanWindow].grep('N').size.to_f / scanWindow.to_f) < 0.1 and p.ignore[i] != 'L' and p.ignore[i + 1] != 'L' and p.ignore[i + 2] != 'L' and p.ignore[i + 3] != 'L'  and p.ignore[i + 4] != 'L')

      #and (p.qual[i, scanWindow].inject(0) {|sum, v| sum + v.to_i } / scanWindow) >= qualityCutoff

        #Might be good for rejecting stuff, but didn't seem to help basecalling.
        #maxpeaks = []
        #i.upto(i + scanWindow - 1) do |j|
        #  maxpeaks << [p.amp_a[j],p.amp_c[j],p.amp_g[j],p.amp_t[j]].max
        #end
        #avgpeak = maxpeaks.inject(0){|sum,x| sum + x } / maxpeaks.size


#				if(p.qual[i] >= qualityCutoff and (p.qual[i, scanWindow].inject(0) {|sum, v| sum + v.to_i } / scanWindow) >= qualityCutoff and (p.called[i, scanWindow].grep('N').size.to_f / scanWindow.to_f) < 0.1 and p.ignore[i] != 'L' and p.ignore[i + 1] != 'L' and p.ignore[i + 2] != 'L' and avgpeak > 3000)
				if(p.qual[i] >= qualityCutoff and (p.qual[i, scanWindow].inject(0) {|sum, v| sum + v.to_i } / scanWindow) >= qualityCutoff and (p.called[i, scanWindow].grep('N').size.to_f / scanWindow.to_f) < 0.1 and p.ignore[i] != 'L' and p.ignore[i + 1] != 'L' and p.ignore[i + 2] != 'L')
					cut = i
					break
				end
			end

      cutabs = cut
      if(cut != -1 and cut != 0 and cut - 10 > 0)
        cutabs = cut - 10
      else
        cutabs = 0
      end
    cutabs = cut
=begin
      if(cut != -1 and cut != 0)
        0.upto(cut - 1) do |i|
          p.ignore[i] = 'L' #if(p.qual[i] < 50)  #Need to do this more cleverly
        end
      end
=end
#=begin
			if(cutabs != 0 and cutabs != -1)
				p.called = p.called[cutabs .. -1]
				p.uncalled = p.uncalled[cutabs .. -1]
				p.called_area = p.called_area[cutabs .. -1]
				p.uncalled_area = p.uncalled_area[cutabs .. -1]
				p.loc = p.loc[cutabs .. -1]
				p.qual = p.qual[cutabs .. -1]
				p.ignore = p.ignore[cutabs .. -1]
				p.edit = p.edit[cutabs .. -1]
        p.amp_a = p.amp_a[cutabs .. -1]
        p.amp_c = p.amp_c[cutabs .. -1]
        p.amp_g = p.amp_g[cutabs .. -1]
        p.amp_t = p.amp_t[cutabs .. -1]
			end
#=end
			#cut off low qual at end
			cut = -1
			(p.length - 1).downto(scanWindow) do |i|
				#if((p.qual[i - scanWindow, scanWindow].inject(0) {|sum, v| sum = sum + v.to_i } / scanWindow) >= qualityCutoff and (p.called[i, scanWindow].grep('N').size.to_f / scanWindow.to_f) < 0.1  and p.ignore[i] != 'L' and p.ignore[i - 1] != 'L' and p.ignore[i - 2] != 'L' and p.ignore[i - 3] != 'L' and p.ignore[i - 4] != 'L')

        maxpeaks = []
        (i - scanWindow).upto(i - 1) do |j|
          maxpeaks << [p.amp_a[j],p.amp_c[j],p.amp_g[j],p.amp_t[j]].max
        end
        avgpeak = maxpeaks.inject(0){|sum,x| sum + x } / maxpeaks.size

#				if(p.qual[i] >= qualityCutoff and (p.qual[i - scanWindow, scanWindow].inject(0) {|sum, v| sum = sum + v.to_i } / scanWindow) >= qualityCutoff and (p.called[i, scanWindow].grep('N').size.to_f / scanWindow.to_f) < 0.1  and p.ignore[i] != 'L' and p.ignore[i - 1] != 'L' and p.ignore[i - 2] != 'L' and avgpeak > 3000)
        if(p.qual[i] >= qualityCutoff and (p.qual[i - scanWindow, scanWindow].inject(0) {|sum, v| sum = sum + v.to_i } / scanWindow) >= qualityCutoff and (p.called[i, scanWindow].grep('N').size.to_f / scanWindow.to_f) < 0.1  and p.ignore[i] != 'L' and p.ignore[i - 1] != 'L' and p.ignore[i - 2] != 'L')
					cut = i # - scanWindow
					break
				end
			end

      cutabs = cut
      if(cut != -1 and cut != 0 and cut + 10 < p.length - 1)
        cutabs = cut + 10
      else
        cutabs = 0
      end
    cutabs = cut
=begin
      if(cut != -1)
        (cut + 1).upto(p.called.size - 1) do |i|
          #p.ignore[i] = 'L' if(p.qual[i] < 50) #Need to do this more cleverly
          p.ignore[i] = 'L' # if(p.qual[i] < 50) #Need to do this more cleverly
        end
      end
=end

#=begin
			if(cutabs != 0 and cutabs != -1)
				p.called = p.called[0 .. cutabs]
				p.uncalled = p.uncalled[0 .. cutabs]
				p.called_area = p.called_area[0 .. cutabs]
				p.uncalled_area = p.uncalled_area[0 .. cutabs]
				p.loc = p.loc[0 .. cutabs]
				p.qual = p.qual[0 .. cutabs]
				p.ignore = p.ignore[0 .. cutabs]
				p.edit = p.edit[0 .. cutabs]
        p.amp_a = p.amp_a[0 .. cutabs]
        p.amp_c = p.amp_c[0 .. cutabs]
        p.amp_g = p.amp_g[0 .. cutabs]
        p.amp_t = p.amp_t[0 .. cutabs]
			end
#=end
		end
	end

	def PrimerFixer.reject_primers(data, isweb=false)
		data.primers.delete_if do |p|
			good = 0
			0.upto(p.edit.size - 1) do |i|
				good += 1 if(p.edit[i] != '-' and p.ignore[i] != 'L')
			end
			if(good < RecallConfig['primer_fixer.primer_min_good'].to_i)
				data.errors.push("Failing primer #{isweb ? p.name : p.primerid}; only #{good} acceptable bases")
				true
			else
				false
			end
		end
	end
end
