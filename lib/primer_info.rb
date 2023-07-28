=begin
primer_info.rb
Copyright (c) 2007-2023 University of British Columbia

Gives basic info on primers.
=end

require 'lib/alg/_alignment' #c-extension

class PrimerInfo
#	@@path = 'data/primers.txt'
	@@_dir = Hash.new
  @@_genes = Hash.new
  @@_seq = Hash.new

	def PrimerInfo.direction(primer)
#		if(@@_dir.empty?)
#			PrimerInfo.Load()
#		end

		return @@_dir[primer]
	end

  #How will this perform near edges.... Maybe you should get the
  #extended standard thing going soon...
  def PrimerInfo.direction_guess(primer, standard)
    forward_aln = align_it(standard.join(''), primer.called_base.join('').gsub('N', '-'), 3, 1)
    reverse_aln = align_it(standard.join(''), primer.called_base.join('').gsub('N', '-').complement, 3, 1)

    fcnt = 0
    rcnt = 0

    fbase = 0
    lbase = 0
    0.upto(forward_aln[0].length - 1) do |i|
      fbase = i
      break if(forward_aln[0][i,1] != '-' and forward_aln[1][i,1] != '-')
    end
    (forward_aln[0].length - 1).downto(0) do |i|
      lbase = i
      break if(forward_aln[0][i,1] != '-' and forward_aln[1][i,1] != '-')
    end
    fbase.upto(lbase) do |i|
      if(forward_aln[0][i,1] == forward_aln[1][i,1] and forward_aln[0][i,1] != '-'  and forward_aln[1][i,1] != '-')
        fcnt += 1
      else
        fcnt -= 1
      end
    end

    0.upto(reverse_aln[0].length - 1) do |i|
      fbase = i
      break if(reverse_aln[0][i,1] != '-' and reverse_aln[1][i,1] != '-')
    end
    (reverse_aln[0].length - 1).downto(0) do |i|
      lbase = i
      break if(reverse_aln[0][i,1] != '-' and reverse_aln[1][i,1] != '-')
    end
    fbase.upto(lbase) do |i|
      if(reverse_aln[0][i,1] == reverse_aln[1][i,1] and reverse_aln[0][i,1] != '-'  and reverse_aln[1][i,1] != '-')
        rcnt += 1
      else
        rcnt -= 1
      end
    end

    if(rcnt > fcnt)
      return 'reverse'
    elsif(fcnt > rcnt)
      return 'forward'
    else
      return nil
    end
  end

  def PrimerInfo.genes(primer)
    if(@@_dir.empty?)
      PrimerInfo.Load()
    end
    return nil if(@@_genes[primer] == nil)
    return @@_genes[primer].split(',')
  end

  def PrimerInfo.seq(primer)
    if(@@_dir.empty?)
      PrimerInfo.Load()
		end

		return @@_seq[primer]
  end

	def PrimerInfo.Load(path)
		File.open(path) do |file|
			v = []
			file.each do |line|
				v = line.strip.split("\t")
				@@_dir[v[0]] = v[1] if(v[1] != nil)
        @@_genes[v[0]] = v[2] if(v[2] != nil)
        @@_seq[v[0]] = v[3] if(v[3] != nil)
			end
		end
	end
end
