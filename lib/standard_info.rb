=begin
standard_info.rb
Copyright (c) 2007-2023 University of British Columbia

Gives basic info on standards.
=end

class StandardInfo
	@@hash = Hash.new
  @@long = Hash.new #for extended standards that will be trimmed
  @@types = Hash.new

	def StandardInfo.sequence(standard)
		if(@@hash.empty?)
			StandardInfo.Load()
		end

		return @@hash[standard.upcase]
	end

  def StandardInfo.long_sequence(standard)
		if(@@hash.empty?)
			StandardInfo.Load()
		end
		return @@long[standard.upcase]
	end

	def StandardInfo.list(type = nil)
    if(type == nil)
      return @@hash.keys.sort
    else
      return @@types.keys.find_all{|a| @@types[a] == type}.sort
    end
	end

	def StandardInfo.Load(path)
		File.open(path) do |file|
      v = ''
      type = ''
			st = 0
			file.each do |line|
				if(st == 0)
					v = line.strip[1 .. -1].split(',')
          if(v.size == 1)
              type = nil
          else
              type = v[1]
          end
          v = v[0]
					st = 1
				else
					seqs = line.strip.split(',')
          if(seqs.size == 1)
              @@long[v.upcase] = nil
          else
              @@long[v.upcase] = seqs[1].split('')
          end
          @@hash[v.upcase] = seqs[0].split('')

          @@types[v.upcase] = type
					st = 0
				end
			end
		end

	end
end
