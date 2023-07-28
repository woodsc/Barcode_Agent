=begin
lib/alg/insertion_detector.rb
Copyright (c) 2007-2023 University of British Columbia

Tidy's up insertions
=end

require 'lib/recall_config'
require 'lib/utils'


class InsertDetector
#This does two things.
#1) Tries to put all the inserts in groups of three
#2) Tries to align the inserts to a group of "Common" insertions

	def InsertDetector.fix_inserts(data)
		good = true
        common_points = nil
        if(RecallConfig['insert_detector.common_insert_points'] == '*')
            common_points = (3 .. data.standard.size - 4).to_a
            common_points.delete_if {|a| a % 3 != 0}
        else
            common_points = RecallConfig['insert_detector.common_insert_points'].split(',').map {|a| a.to_i }
        end
		dex_list = data.get_dex_list
		bad_inserts = []
		shift = 0

		insert_list = []

		0.upto(dex_list.size - 1) do |i|
			if(data.assembled[dex_list[i]] != '-' and data.standard[dex_list[i]] == '-')
				insert_list.push(i)
			end
		end

		if(insert_list.size % 3 != 0)
			#Oh dear, we have a problem with this sequence
#			puts "Bad inserts in this sequence, failing"
			good = false
			return false
		end

		insert_list = insert_list.compact_ranges

		insert_list.map! {|a| a.class != Range ? (a .. a) : a}
		insert_list.sort! {|a,b| a.to_a.size <=> b.to_a.size }

		i = 0
		while(i < insert_list.size)
#			puts insert_list.inspect
			dex = insert_list[i]

			if(dex.to_a.size % 3 != 0)
				match_loc = insert_list.find do |v|
					v != dex and ( (v.end - dex.begin).abs < 13 or (v.begin - dex.end).abs < 13)
				end

				if(match_loc == nil)
					good = false
					return false
				else
#					puts "Combining insert #{dex} and #{match_loc}"
#					puts data.standard[dex_list[match_loc.begin] - 30, 60].join('')
#					puts data.assembled[dex_list[match_loc.begin] - 30, 60].join('')

					if(dex.begin > match_loc.begin)
						gdiff = (dex.begin - match_loc.end).abs - 1
						dex.to_a.each do |j|
							diff = gdiff
							while(diff != 0)
								data.standard[dex_list[j]] = data.standard[dex_list[j - 1]]
								data.standard[dex_list[j - 1]] = '-'
								diff -= 1
								j -= 1
							end
						end
						insert_list[i] = (insert_list[i].begin - gdiff) .. (insert_list[i].end - gdiff)
					elsif(dex.begin < match_loc.begin)
						gdiff = (dex.end - match_loc.begin).abs - 1
						dex.to_a.reverse.each do |j|
							diff = gdiff
							while(diff != 0)
								data.standard[dex_list[j]] = data.standard[dex_list[j + 1]]
								data.standard[dex_list[j + 1]] = '-'
								diff -= 1
								j += 1
							end
						end
						insert_list[i] = (insert_list[i].begin + gdiff) .. (insert_list[i].end + gdiff)
					end
#					puts data.standard[dex_list[match_loc.begin] - 30, 60].join('')
#					puts data.assembled[dex_list[match_loc.begin] - 30, 60].join('')

					i = 0 #To reset i
					insert_list = insert_list.compact_ranges
					insert_list.map! {|a| a.class != Range ? (a .. a) : a}
					insert_list.sort! {|a,b| a.to_a.size <=> b.to_a.size }
				end
			end
			i += 1
		end

		insert_list = []

		0.upto(dex_list.size - 1) do |i|
			if(data.assembled[dex_list[i]] != '-' and data.standard[dex_list[i]] == '-')
				insert_list.push(i)
			end
		end
		insert_list = insert_list.compact_ranges
		insert_list.map! {|a| a.class != Range ? (a .. a) : a}

		i = 0
		while(i < insert_list.size)
			dex = insert_list[i]
			size = insert_list[i].to_a.size
#			puts "Found insertion of size #{dex.to_a.size}"

			closest = common_points.inject(20000) {|mem, v| mem = (((v + shift) - dex.begin).abs > (mem - dex.begin).abs ? mem : (v + shift)) }
			closestb = common_points.find {|v| ((v + shift) - dex.begin).abs == (closest - dex.begin).abs and closest != (v + shift) ? true : false }

			if(size % 3 != 0)
#				puts "Invalid size #{size}"
				good = false
			elsif(closest == dex.begin)
#				puts "Right on the money"
			elsif((closest - dex.begin).abs > 15) #give up
#				puts "Unusual insert at #{dex}"

				good = false
				bad_inserts.push(dex)
				#shift += size
			else #shift
				score = 0
				val = nil
				tmpinsert = nil

#				puts "Shifting insert"
#				puts data.standard[dex_list[dex.begin + ((dex.end - dex.begin) / 2)] - 30, 60].join('')
#				puts data.assembled[dex_list[dex.begin + ((dex.end - dex.begin) / 2)] - 30, 60].join('')
				[closest,closestb].each do |clos|
					next if(clos == nil)
					newstandard = Array.new(data.standard)
					loc = dex.begin
					gdiff = (clos - loc).abs # -1?

					if(loc > clos)
						dex.to_a.each do |j|
							diff = gdiff
							while(diff != 0)
								newstandard[dex_list[j]] = newstandard[dex_list[j - 1]]
								newstandard[dex_list[j - 1]] = '-'
								diff -= 1
								j -= 1
							end
						end
					end
					if(loc < clos)
						dex.to_a.reverse.each do |j|
							diff = gdiff
							while(diff != 0)
								newstandard[dex_list[j]] = newstandard[dex_list[j + 1]]
								newstandard[dex_list[j + 1]] = '-'
								diff -= 1
								j += 1
							end
						end
					end

					#shift += size

					tmp = score_alignment(newstandard, data.assembled)
					if(tmp > score)
						score = tmp
						val = newstandard
						if(loc > clos)
							tmpinsert = (insert_list[i].begin - gdiff) .. (insert_list[i].end - gdiff)
						elsif(loc < clos)
							tmpinsert = (insert_list[i].begin + gdiff) .. (insert_list[i].end + gdiff)
						end
					end
				end

				data.standard = val
				insert_list[i] = tmpinsert
#				puts data.standard[dex_list[dex.begin + ((dex.end - dex.begin) / 2)] - 30, 60].join('')
#				puts data.assembled[dex_list[dex.begin + ((dex.end - dex.begin) / 2)] - 30, 60].join('')
			end
			shift += size
			i += 1
		end

		#Here we should probably add bad inserts to the errors list or something
		if(good)
			return true
		else
			return false
		end
	end

	#1) Group small deletions together
	#2) If set, align deletions to frame
	def InsertDetector.fix_deletions(data)
		good = true
		dex_list = data.get_dex_list
		bad_deletes = []
		shift = 0

		delete_list = []

		0.upto(dex_list.size - 1) do |i|
			if(data.assembled[dex_list[i]] == '-' and data.standard[dex_list[i]] != '-')
				delete_list.push(i)
			end
		end

		if(delete_list.size % 3 != 0)
			#Oh dear, we have a problem with this sequence
#			puts "Bad deletions in this sequence, failing"
			good = false
			return false
		end

		delete_list = delete_list.compact_ranges

		delete_list.map! {|a| a.class != Range ? (a .. a) : a}
		delete_list.sort! {|a,b| a.to_a.size <=> b.to_a.size }

		i = 0
		while(i < delete_list.size)
			dex = delete_list[i]

			if(dex.to_a.size % 3 != 0)
				match_loc = delete_list.find do |v|
					v != dex and ( (v.end - dex.begin).abs < 13 or (v.begin - dex.end).abs < 13)
				end

				if(match_loc == nil)
#					puts "Could not align deletion"
					good = false
					return false
				else
#					puts "Combining deletion at #{dex} and #{match_loc}"
#					puts data.assembled[dex_list[match_loc.begin] - 30, 60].join('')
#					puts data.standard[dex_list[match_loc.begin] - 30, 60].join('')

					if(dex.begin > match_loc.begin)
						gdiff = (dex.begin - match_loc.end).abs - 1
						dex.to_a.each do |j|
							data.shift_assembled(j, -gdiff)
						end
						delete_list[i] = (delete_list[i].begin - gdiff) .. (delete_list[i].end - gdiff)
					elsif(dex.begin < match_loc.begin)
						gdiff = (dex.end - match_loc.begin).abs - 1
						dex.to_a.reverse.each do |j|
							data.shift_assembled(j, gdiff)
						end
						delete_list[i] = (delete_list[i].begin + gdiff) .. (delete_list[i].end + gdiff)
					end

#					puts data.assembled[dex_list[match_loc.begin] - 30, 60].join('')
#					puts data.standard[dex_list[match_loc.begin] - 30, 60].join('')


					i = 0 #To reset i
					delete_list = delete_list.compact_ranges
					delete_list.map! {|a| a.class != Range ? (a .. a) : a}
					delete_list.sort! {|a,b| a.to_a.size <=> b.to_a.size }
				end
			end
			i += 1
		end

		#Ok, now frame align deletion
		if(RecallConfig['insert_detector.frame_align_deletions'] == 'true')
			delete_list = []

			0.upto(dex_list.size - 1) do |i|
				if(data.assembled[dex_list[i]] == '-' and data.standard[dex_list[i]] != '-')
					delete_list.push(i)
				end
			end

			delete_list = delete_list.compact_ranges

			delete_list.map! {|a| a.class != Range ? (a .. a) : a}
			delete_list.sort! {|a,b| a.to_a.size <=> b.to_a.size }

			i = 0
			while(i < delete_list.size)
				dex = delete_list[i]

#				puts data.assembled[dex_list[dex.begin] - 30, 60].join('')
#				puts data.standard[dex_list[dex.begin] - 30, 60].join('')
				if(dex.begin % 3 == 1)
					dex.to_a.each do |j|
						data.shift_assembled(j, -1)
					end
				elsif(dex.begin % 3 == 2)
					dex.to_a.reverse.each do |j|
						data.shift_assembled(j, 1)
					end
				end
#				puts data.assembled[dex_list[dex.begin] - 30, 60].join('')
#				puts data.standard[dex_list[dex.begin] - 30, 60].join('')
				i += 1
			end
		end
	end
end
