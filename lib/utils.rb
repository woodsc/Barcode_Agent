=begin
util.rb
Copyright (c) 2007-2023 University of British Columbia

Various minor method calls that are helpful throughout the codebase.
=end

require 'fileutils'

#escapes a string for use in a Dir[] method.
def d_esc(str)
  return str.gsub(/([\*\?\[\]])/, '\\\\\1') # escape *, ?, [] by adding \\
end

def safe_copy(src, dest)
    tries = 0
    dest_fullname = dest
    if(dest[-1,1] == '/')
        src =~ /([^\/]+)$/
        dest_fullname = dest + $1
    end
    x = nil
    begin
        x = FileUtils.cp(src, dest)
        if(File.exist?(dest_fullname) and File.size(src) == File.size(dest_fullname))
        else
            raise "Error"
        end
    rescue
        puts "Error copying file #{src} to #{dest_fullname}, trying again..."
        tries += 1
        if(tries > 10)
          puts "Giving up"
        else
          retry
        end
    end
    return x
end


class Array
	#Turns an array of integers and ranges and turns any sequences into ranges.
	#Example:
	# [1,2,3,6,8,20,21,22,23,47].compact_ranges #=> [1 .. 3, 6, 8, 20..23, 47]

	def compact_ranges
		#Sort and turn any existing ranges into numbers
		self.map! {|v| v.class == Range ? v.to_a  : v }
		self.flatten!
		self.uniq!
		self.sort!


		c = [] #The array to be returned
		fi = -1 #first index
		li = -1 #last index
		0.upto(self.size) do |i|
			if(fi == -1) #first iteration
				fi = i
				li = i
			elsif(i != self.size and self[i] == self[li] + 1)
				li = i #This is part of the sequence, so increment li
			else #Time to break
				if(fi == li) #Single element, by itself
					c.push(self[fi])
				else #Turn into range
					c.push(self[fi] .. self[li])
				end
				fi = i
				li = i
			end
		end
		return c
	end
end


def score_alignment(standard, assembled)
	score = 0
	0.upto(standard.size - 1) do |i|
		if(standard[i] == '-' or assembled[i] == '-')

		elsif(standard[i] == assembled[i])
			score += 2
		end

	end
	return score
end

#takes an alignment and counts the area that overlaps
def count_align_overlap(seq1, seq2)
	cnt = 0
	0.upto(seq1.size - 1) do |i|
		if(seq1[i] != '-' and seq2[i] != '-')
			cnt += 1
		end
	end
	return cnt
end
