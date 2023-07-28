=begin
scf.rb
Copyright (c) 2007-2023 University of British Columbia

Loads an SCF chromatogram file
=end


class String
	def complement
		return self.reverse.tr('ATGCNRYKMSWBVDH','TACGNYRMKSWVBHD')
	end
end

class Scf
  attr_accessor :primerid, :sampid, :name

  attr_accessor :seq, :peak_locs
  attr_accessor :atrace, :ctrace, :gtrace, :ttrace
  attr_accessor :amax, :cmax, :gmax, :tmax
  attr_accessor :title, :num_peaks


  attr_accessor :version, :comments

  #def initialize(filename, full_id=false, delimiter='+')
  def initialize(filename, sampid='', primerid='')
    filename =~ /\/([^\/]+)\.scf/i
    @name = $1
    @sampid = sampid
    @primerid = primerid
    @title = ''
    @peak_locs = [] #done
    @seq = '' #done
    @atrace = []
    @ctrace = []
    @gtrace = []
    @ttrace = []
    @amax = 10
    @gmax = 10
    @cmax = 10
    @tmax = 10

    @prob_a = []
    @prob_c = []
    @prob_g = []
    @prob_t = []

    @num_peaks = 0 #done
    @comments = Hash.new

    File.open(filename) do |file|
      file.binmode #for windoze systems (Win-Doh!)

      file.seek(4)
      samples_cnt = file.read(4).unpack("N")[0]
      samples_offset = file.read(4).unpack("N")[0]
      bases_cnt = file.read(4).unpack("N")[0]
      @num_peaks = bases_cnt
      file.seek(24)
      bases_offset = file.read(4).unpack("N")[0]
      comments_size = file.read(4).unpack("N")[0]
      comments_offset = file.read(4).unpack("N")[0]
      @version = file.read(4)
      sample_size = file.read(4).unpack("N")[0] #1 = 8bits, 2 = 16 bits
      garbage = file.read(4) #code_set, not used
      private_size = file.read(4).unpack("N")[0]
      private_offset = file.read(4).unpack("N")[0]

      #puts "Sample count: #{samples_cnt}"
      #puts "Bases count: #{bases_cnt}"
      #puts "Comments Size: #{comments_size}"
      #puts "Version: #{version}"
      #puts "Sample byte-size: #{sample_size}"
      #puts "private_size: #{private_size}"

      file.seek(samples_offset)
      value = nil
      if(@version.to_f >= 3.0)
        if(sample_size == 2)
          0.upto(samples_cnt - 1) do |i|
            @atrace.push(file.read(2).unpack("n")[0])
            #puts @atrace[i]
          end
          0.upto(samples_cnt - 1) do |i|
            @ctrace.push(file.read(2).unpack("n")[0])
          end
          0.upto(samples_cnt - 1) do |i|
            @gtrace.push(file.read(2).unpack("n")[0])
          end
          0.upto(samples_cnt - 1) do |i|
            @ttrace.push(file.read(2).unpack("n")[0])
          end
          #convert to proper

          [@atrace,@ctrace,@gtrace,@ttrace].each do |trace|
            p_sample = 0
            0.upto(trace.size - 1) do |i|
              trace[i] = (trace[i] + p_sample) % 65536
              p_sample = trace[i]
            end
            p_sample = 0
            0.upto(trace.size - 1) do |i|
              trace[i] = (trace[i] + p_sample) % 65536
              p_sample = trace[i]
            end
          end

        elsif(sample_size == 1)
          0.upto(samples_cnt - 1) do |i|
            @atrace.push(file.read(1).unpack("C")[0])
          end
          0.upto(samples_cnt - 1) do |i|
            @ctrace.push(file.read(1).unpack("C")[0])
          end
          0.upto(samples_cnt - 1) do |i|
            @gtrace.push(file.read(1).unpack("C")[0])
          end
          0.upto(samples_cnt - 1) do |i|
            @ttrace.push(file.read(1).unpack("C")[0])
          end
          [@atrace,@ctrace,@gtrace,@ttrace].each do |trace|
            p_sample = 0
            0.upto(trace.size - 1) do |i|
              trace[i] = (trace[i] + p_sample) % 256
              p_sample = trace[i]
            end
            p_sample = 0
            0.upto(trace.size - 1) do |i|
              trace[i] = (trace[i] + p_sample) % 256
              p_sample = trace[i]
            end
          end
        else
          throw "Incorrect sample byte size #{sample_size}, corrupted file?"
        end
      else
        if(sample_size == 2)
          0.upto(samples_cnt - 1) do |i|
            @atrace.push(file.read(2).unpack("n")[0])
            @ctrace.push(file.read(2).unpack("n")[0])
            @gtrace.push(file.read(2).unpack("n")[0])
            @ttrace.push(file.read(2).unpack("n")[0])
          end
        elsif(sample_size == 1)
          0.upto(samples_cnt - 1) do |i|
            @atrace.push(file.read(1).unpack("C")[0])
            @ctrace.push(file.read(1).unpack("C")[0])
            @gtrace.push(file.read(1).unpack("C")[0])
            @ttrace.push(file.read(1).unpack("C")[0])
          end
        else
          throw "Incorrect sample byte size #{sample_size}, corrupted file?"
        end
      end

      if(@version.to_f >= 3.0)
        file.seek(bases_offset)
        0.upto(bases_cnt - 1) do |i|
          @peak_locs.push(file.read(4).unpack("N")[0])
        end
        0.upto(bases_cnt - 1) do |i|
          @prob_a = file.read(1).unpack("C")[0]
        end
        0.upto(bases_cnt - 1) do |i|
          @prob_c = file.read(1).unpack("C")[0]
        end
        0.upto(bases_cnt - 1) do |i|
          @prob_g = file.read(1).unpack("C")[0]
        end
        0.upto(bases_cnt - 1) do |i|
          @prob_t = file.read(1).unpack("C")[0]
        end
        0.upto(bases_cnt - 1) do |i|
          @seq += file.read(1)
        end
      else

        file.seek(bases_offset)
        0.upto(bases_cnt - 1) do |i|
          @peak_locs.push(file.read(4).unpack("N")[0])
          @prob_a = file.read(1).unpack("C")[0]
          @prob_c = file.read(1).unpack("C")[0]
          @prob_g = file.read(1).unpack("C")[0]
          @prob_t = file.read(1).unpack("C")[0]
          @seq += file.read(1)
          file.read(3)
        end
      end

      file.seek(comments_offset)
      if(comments_size != 0)
        cmts = file.read(comments_size - 1)
        cmts = cmts.split("\n")
        cmts.each do |l|
          dex = l.index('=')
          @comments[l[0 .. dex - 1]] = l[dex + 1 .. -1]
        end
      end
    end

    @title = @comments['NAME'] if(@comments['NAME'])
    @gmax = @gtrace.max
    @amax = @atrace.max
    @tmax = @ttrace.max
    @cmax = @ctrace.max

    #Normally, this is correct, but since we sometimes rename files that we
    #have incorrectly assigned a wrong name, we shouldn't do this.
    #@sampid, @primerid = @title.split('_')[0].split('+')
    slashpos = filename.rindex('/')
    slashpos = 0 if(!slashpos)
=begin
    if(full_id == false)
        #@sampid, @primerid = filename[filename.rindex('/') + 1 .. -1].split('_')[0].split('+')
        @sampid = filename[slashpos + 1 .. -1].split(delimiter)[0]
        @primerid = filename[slashpos + 1 .. -1].split(delimiter)[1].split('_')[0]
    else
        @sampid = filename[slashpos + 1 .. -1].gsub(/\.scf/i,'')
        @primerid = filename[slashpos + 1 .. -1].gsub(/\.scf/i,'')
    end
=end
  end

  def each
    0.upto(@peak_locs.size - 1) do |i|
      yield @seq[i, 1], @peak_locs[i]
    end
  end

  def complement
    scf = self.clone
    scf.complement!
    return scf
  end

#This is my attempt to complement an entire chromatogram.  Since I haven't
#written any visualization code for this yet, I haven't confirmed that it works.
#In theory it should be fine though!
  def complement!
    @seq = @seq.complement
 #     @seq2.complement!
#    max = @atrace.size # I think this makes sense, but could I be off by one?
    max = @peak_locs.max
    @peak_locs = @peak_locs.map do |v|
      v = max - v
    end
#      @peak_locs2 = @peak_locs2.map do |v|
#        v = max - v
#      end

    @peak_locs.reverse!
#      @peak_locs2.reverse!

    tmp = @atrace
    @atrace = @ttrace.reverse
    @ttrace = tmp.reverse
    tmp = @ctrace
    @ctrace = @gtrace.reverse
    @gtrace = tmp.reverse
  end
end
