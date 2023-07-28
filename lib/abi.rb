=begin
abi.rb
Copyright (c) 2007-2023 University of British Columbia, Conan K Woods

Loads an ABI chromatogram file fully.  Provides some options for saving as well.
=end

require 'lib/sequence'

class String
	def complement
		return self.reverse.tr('ATGCNRYKMSWBVDH','TACGNYRMKSWVBHD')
	end
end

class Abi
  attr_accessor :primerid, :sampid, :name
  attr_accessor :seq, :peak_locs, :seq2
  attr_accessor :atrace, :ctrace, :gtrace, :ttrace
  attr_accessor :raw_atrace, :raw_ctrace, :raw_gtrace, :raw_ttrace
  attr_accessor :voltage, :current, :power, :temperature
  attr_accessor :amax, :cmax, :gmax, :tmax
  attr_accessor :title, :num_peaks, :comment
#    attr_accessor :seq2, :peak_locs2
  attr_accessor :abi_version, :filesig, :dirname, :direlements, :diroffset
  attr_accessor :signal_level_a, :signal_level_c, :signal_level_g, :signal_level_t
  attr_accessor :dyeset_name, :mobility_file

    #other fun random facts from the machines
    attr_accessor :gel_file, :gel_path, :lanes, :machine_name, :model
    attr_accessor :average_chan, :num_chan, :num_lanes, :primer, :primer2
    attr_accessor :primer_pos, :primer2_pos, :date_start, :date_end
    attr_accessor :time_start, :time_end

#is the sample before primer disadvantage okay?  Hrm.  I suppose we could have another variable to control the order...
#delimiter = /^([^\+]+)\+([^_]+)_.+$/
#sample_before_primer = true

  def save(filename)
    #Okay, we need to figure out indexes and where the data is written.  Its a bit tricky!
    #Data starts at 128
    bytestr_data = ''
    bytestr_dirs = ''
    bytestr_header = ''
    i = 128

    dirs = []
    #Write data as we go?
    dirs << ['FWO_',1,2,1,4,4,['GATC'].pack("A4").unpack("N")[0], 0]

#=begin
    dirs << ['DATA',1,4,2,@raw_gtrace.size(), @raw_gtrace.size() * 2, i, 0]
    bytestr_data += @raw_gtrace.pack("n#{@raw_gtrace.size()}")
    i += dirs.last[5]
    dirs << ['DATA',2,4,2,@raw_atrace.size(), @raw_atrace.size() * 2, i, 0]
    bytestr_data += @raw_atrace.pack("n#{@raw_atrace.size()}")
    i += dirs.last[5]
    dirs << ['DATA',3,4,2,@raw_ttrace.size(), @raw_ttrace.size() * 2, i, 0]
    bytestr_data += @raw_ttrace.pack("n#{@raw_ttrace.size()}")
    i += dirs.last[5]
    dirs << ['DATA',4,4,2,@raw_ctrace.size(), @raw_ctrace.size() * 2, i, 0]
    bytestr_data += @raw_ctrace.pack("n#{@raw_ctrace.size()}")
    i += dirs.last[5]

    dirs << ['DATA',5,4,2,@voltage.size(), @voltage.size() * 2, i, 0]
    bytestr_data += @voltage.pack("n#{@voltage.size()}")
    i += dirs.last[5]
    dirs << ['DATA',6,4,2,@current.size(), @current.size() * 2, i, 0]
    bytestr_data += @current.pack("n#{@current.size()}")
    i += dirs.last[5]
    dirs << ['DATA',7,4,2,@power.size(), @power.size() * 2, i, 0]
    bytestr_data += @power.pack("n#{@power.size()}")
    i += dirs.last[5]
    dirs << ['DATA',8,4,2,@temperature.size(), @temperature.size() * 2, i, 0]
    bytestr_data += @temperature.pack("n#{@temperature.size()}")
    i += dirs.last[5]
#=end
    dirs << ['DATA',9,4,2,@gtrace.size(), @gtrace.size() * 2, i, 0]
    bytestr_data += @gtrace.pack("n#{@gtrace.size()}")
    i += dirs.last[5]
    dirs << ['DATA',10,4,2,@atrace.size(), @atrace.size() * 2, i, 0]
    bytestr_data += @atrace.pack("n#{@atrace.size()}")
    i += dirs.last[5]
    dirs << ['DATA',11,4,2,@ttrace.size(), @ttrace.size() * 2, i, 0]
    bytestr_data += @ttrace.pack("n#{@ttrace.size()}")
    i += dirs.last[5]
    dirs << ['DATA',12,4,2,@ctrace.size(), @ctrace.size() * 2, i, 0]
    bytestr_data += @ctrace.pack("n#{@ctrace.size()}")
    i += dirs.last[5]

    dirs << ['PBAS',1,2,1,@seq.size(), @seq.size(), i, 0]
    bytestr_data += [@seq].pack("A#{@seq.size()}")
    i += dirs.last[5]

    dirs << ['PLOC',1,4,2,@peak_locs.size(), @peak_locs.size() * 2, i, 0]
    bytestr_data += @peak_locs.pack("n#{@peak_locs.size()}")
    i += dirs.last[5]
    if(@title.size() < 4)
      dirs << ['SMPL',1,18,1, 4, 4, [@title.size(), @title.ljust(3,' ')].pack("C1A#{@title.size()}").unpack('N')[0] , 0]
    else
      dirs << ['SMPL',1,18,1,@title.size() + 1, @title.size() + 1, i, 0]
      bytestr_data += [@title.size(),@title].pack("C1A#{@title.size()}")
      i += dirs.last[5]
    end
    if(@comment.size() < 4)
      dirs << ['CTTL',1,18,1, 4, 4, [@comment.size(), @comment.ljust(3,' ')].pack("C1A#{@comment.size()}").unpack('N')[0] , 0]
    else
      dirs << ['CTTL',1,18,1,@comment.size() + 1, @comment.size() + 1, i, 0]
      bytestr_data += [@comment.size(),@comment].pack("C1A#{@comment.size()}")
      i += dirs.last[5]
    end
    if(@dyeset_name.size() < 4)
      dirs << ['DySN',1,18,1, 4, 4, [@dyeset_name.size(), @dyeset_name.ljust(3,' ')].pack("C1A#{@dyeset_name.size()}").unpack('N')[0] , 0]
    else
      dirs << ['DySN',1,18,1,@dyeset_name.size() + 1, @dyeset_name.size() + 1, i, 0]
      bytestr_data += [@dyeset_name.size(),@dyeset_name].pack("C1A#{@dyeset_name.size()}")
      i += dirs.last[5]
    end
    if(@mobility_file.size() < 4)
      dirs << ['PDMF',1,18,1, 4, 4, [@mobility_file.size(), @mobility_file.ljust(3,' ')].pack("C1A#{@mobility_file.size()}").unpack('N')[0] , 0]
    else
      dirs << ['PDMF',1,18,1,@mobility_file.size() + 1, @mobility_file.size() + 1, i, 0]
      bytestr_data += [@mobility_file.size(),@mobility_file].pack("C1A#{@mobility_file.size()}")
      i += dirs.last[5]
    end



    dirs << ['LANE',1,4,2,1, 2, [@num_lanes,0].pack("n2").unpack("N")[0], 0]

    dirs << ['S/N%', 1, 4, 2, 4, 8, i, 0]
    bytestr_data += [@signal_level_g, @signal_level_a, @signal_level_t, @signal_level_c].pack("n4")
    i += dirs.last[5]


    #write dirs
    dirs.each do |dir|
#      puts dir.inspect
      bytestr_dirs += dir.pack("A4N1n1n1N1N1N1N1")
    end

    #write header
    bytestr_header += ['ABIF', @abi_version, @dirname, 1, 1023,28,dirs.size(), dirs.size() * 28, i, 0].pack("A4n1A4N1n1n1N1N1N1N1")
    bytestr_header += ([0] * 47).pack("n47") #padding

    File.open(filename, 'wb') do |file|
      file.write(bytestr_header)
      file.write(bytestr_data)
      file.write(bytestr_dirs)
    end
  end


  def initialize(filename, sampid='', primerid='')
    filename =~ /\/([^\/]+)\.ab1/
    @name = $1
    @sampid = sampid
    @primerid = primerid
    @title = ''
    @peak_locs = []
    @seq = ''
    @atrace = []
    @ctrace = []
    @gtrace = []
    @ttrace = []
    @amax = 10
    @gmax = 10
    @cmax = 10
    @tmax = 10
    @filesig = nil
    @num_peaks = 0
    #@signal_to_noise = []

    File.open(filename) do |file|
      file.binmode #for windoze systems (Win-Doh!)
      @filesig = file.read(4).unpack("A4")[0] #This should ALWAYS be ABIF.
      @abi_version = file.read(2).unpack("n")[0] #usually should be 101
      #Next 28 bytes is the file directory  (Can have multiple directories?
      directory_index = file.read(28).unpack("A4N1n1n1N1N1N1N1")
      @dirname = directory_index[0]
      @direlements = directory_index[4]
      index_offset = directory_index[6]
      @diroffset = index_offset
      #next 47 * 2 bytes are ignored.
      #garbage = file.read(47 * 2).unpack("n47")

      #Now we read the 28 bite directories
      file.seek(index_offset)
      dirs = []
      0.upto(@direlements - 1) do |di|
        dir = file.read(28).unpack("A4N1n1n1N1N1N1N1")
#        puts dir.inspect #Pretty sweet, this is where all the data is hiding.
        dirs << dir
      end

      #We are interested in:
      #DATA, PLOC, SMPL, FWO_, PBAS
      #DATA  1 to 4 is our unanalyzed traces   (Not sure if used by phred)
      #DATA  9 to 12 is our analyzed traces
      #PLOC 1:  Base locations
      #PBAS 1:  Bases
      #SMPL 1: Sample Name
      #FWO_:  Field order (ATGC)

      #If datasize is 4 or less, then the offset actually contains the data

      #FWO_     #Essential
      dir = dirs.find{|a| a[0] == 'FWO_' and a[1] == 1}
      order = [dir[6]].pack('N1').unpack('A4')[0].split('')


      #Data 1 - 4 #raw traces
      #We don't need these for phred, but if we want to open them in bioedit they are needed
      j = 1
      order.each do |letter|
=begin
        dir = dirs.find{|a| a[0] == 'DATA' and a[1] == j}
        next if(!dir)
        file.seek(dir[6])
        if(letter == 'A')
          @raw_atrace = file.read(dir[4] * 2).unpack("n#{dir[4]}")
        elsif(letter == 'C')
          @raw_ctrace = file.read(dir[4] * 2).unpack("n#{dir[4]}")
        elsif(letter == 'G')
          @raw_gtrace = file.read(dir[4] * 2).unpack("n#{dir[4]}")
        elsif(letter == 'T')
          @raw_ttrace = file.read(dir[4] * 2).unpack("n#{dir[4]}")
        end
=end
        j += 1
      end

      #data 5 to 8 #Power, temperature, etc
      #We don't need these for phred, but if we want to open them in bioedit they are needed
      order.each do |letter| #letter doesn't really matter here.  :)
=begin
        dir = dirs.find{|a| a[0] == 'DATA' and a[1] == j}
        next if(!dir)
        file.seek(dir[6])
        if(j == 5)
          @voltage = file.read(dir[4] * 2).unpack("n#{dir[4]}")
        elsif(j == 6)
          @current = file.read(dir[4] * 2).unpack("n#{dir[4]}")
        elsif(j == 7)
          @power = file.read(dir[4] * 2).unpack("n#{dir[4]}")
        elsif(j == 8)
          @temperature = file.read(dir[4] * 2).unpack("n#{dir[4]}")
        end
=end
        j += 1
      end

      #DATA 9 - 12   #Essential
      j = 9
      order.each do |letter|
        dir = dirs.find{|a| a[0] == 'DATA' and a[1] == j}
        file.seek(dir[6])
        if(letter == 'A')
          @atrace = file.read(dir[4] * 2).unpack("n#{dir[4]}")
        elsif(letter == 'C')
          @ctrace = file.read(dir[4] * 2).unpack("n#{dir[4]}")
        elsif(letter == 'G')
          @gtrace = file.read(dir[4] * 2).unpack("n#{dir[4]}")
        elsif(letter == 'T')
          @ttrace = file.read(dir[4] * 2).unpack("n#{dir[4]}")
        end
        j += 1
      end

      #PLOC 1   #Essential
      dir = dirs.find{|a| a[0] == 'PLOC' and a[1] == 1}
      file.seek(dir[6])
      @peak_locs = file.read(dir[4] * 2).unpack("n#{dir[4]}")

      #PBAS 1   #Essential
      dir = dirs.find{|a| a[0] == 'PBAS' and a[1] == 1}
      file.seek(dir[6])
      @seq = file.read(dir[4]).unpack("A#{dir[4]}")[0]

      #SMPL (first character is the number of characters
      dir = dirs.find{|a| a[0] == 'SMPL' and a[1] == 1}
      if(dir[5] <= 4)
        tmp = [dir[6]].pack("N").unpack('C1A3')
        @title = tmp[1][0,tmp[0]]
      else
        file.seek(dir[6])
        @title = file.read(dir[5])[1 .. -1]
      end

      #LANE 1
      dir = dirs.find{|a| a[0] == 'LANE' and a[1] == 1}
      @num_lanes = [dir[6]].pack("N").unpack("n2")[0]

      #CTTL #comment
      dir = dirs.find{|a| a[0] == 'CTTL' and a[1] == 1}
      if(dir == nil)
        @comment = ''
      elsif(dir[5] <= 4)
        tmp = [dir[6]].pack("N").unpack('C1A3')
        @comment = tmp[1][0,tmp[0]]
      else
        file.seek(dir[6])
        @comment = file.read(dir[5])[1 .. -1]
      end

      #S/N%   #signal_level
      dir = dirs.find{|a| a[0] == 'S/N%' and a[1] == 1}
      file.seek(dir[6])
      signal_level = file.read(dir[4] * 2).unpack("n4")

      j = 1
      order.each do |letter|
        if(letter == 'A')
          @signal_level_a = signal_level[j - 1]
        elsif(letter == 'C')
          @signal_level_c = signal_level[j - 1]
        elsif(letter == 'G')
          @signal_level_g = signal_level[j - 1]
        elsif(letter == 'T')
          @signal_level_t = signal_level[j - 1]
        end
        j += 1
      end

      #DySN     #Dyeset Name
      dir = dirs.find{|a| a[0] == 'DySN' and a[1] == 1}
      if(dir == nil)
        @dyeset_name = ''
      elsif(dir[5] <= 4)
        tmp = [dir[6]].pack("N").unpack('C1A3')
        @dyeset_name = tmp[1][0,tmp[0]]
      else
        file.seek(dir[6])
        @dyeset_name = file.read(dir[5])[1 .. -1]
      end
      #PDMF  1     #mobility file
      dir = dirs.find{|a| a[0] == 'PDMF' and a[1] == 1}
      if(dir[5] <= 4)
        tmp = [dir[6]].pack("N").unpack('C1A3')
        @mobility_file = tmp[1][0,tmp[0]]
      else
        file.seek(dir[6])
        @mobility_file = file.read(dir[5])[1 .. -1]
      end




    end

=begin
      st = 0

      data_count = 0
      trace_count = 0

      trace_ind_offset = []

      first_PBAS = true
      first_PLOC = true

      seq_ind_offset = 0
#        seq2_ind_offset = 0
      order_ind_offset = 0
      sample_ind_offset = 0
      peaks_ind_offset = 0
 #       peaks_ind_offset2 = 0

      file.seek(index_offset)
      i = index_offset

      while(st < 18)
        buf = file.read(4)
        file.seek(24, IO::SEEK_CUR)
        if(buf == "DATA")
        #other interesting things we can get from the DATA Fields
        #Raw trace ATGC, Voltage, Current, Power, Temperature
          data_count += 1
          if(data_count >= 9 and data_count <= 12)
            trace_ind_offset[trace_count] = i
            trace_count += 1
          end
          st += 1
        elsif(buf == "PBAS")
          if(first_PBAS) #sequence 1
            first_PBAS = false
            seq_ind_offset = i
 #           else #sequence 2(Is this ever different from sequence 1?)
 #             seq2_ind_offset = i
          end
          st += 1
        elsif(buf == "FWO_") #Field order, this might actually be important
          order_ind_offset = i
          st += 1
        elsif(buf == "SMPL")
          sample_ind_offset = i
          st += 1
        elsif(buf == "PLOC")
          if(first_PLOC)
            first_PLOC = false
            peaks_ind_offset = i
#          else
#            peaks_ind_offset2 = i #is this ever different from the first one?
          end
          st += 1
        end
        i += 28
      end

      file.seek(order_ind_offset + 20)
      order = file.read(4).split('')

      file.seek(seq_ind_offset + 16)
      seq_length = file.read(4).unpack("N")[0]

#      file.seek(seq2_ind_offset + 20)
#        seq2_offset = file.read(4).unpack("N")[0]

      file.seek(seq_ind_offset + 20)
      seq_offset = file.read(4).unpack("N")[0]

      file.seek(seq_offset)
      @seq = String.new(file.read(seq_length))

 #       file.seek(seq2_offset)
 #       @seq2 = Bio::Sequence::NA.new(file.read(seq_length))

      #OK, for most of these obtained by the above tags, if the number of elements is 4 or less, it doesn't offset.
      file.seek(sample_ind_offset + 16)
      sample_elements = file.read(4).unpack("N")[0]
      if(sample_elements > 4)
        file.seek(sample_ind_offset + 20)
        sample_offset = file.read(4).unpack("N")[0]
      else
        sample_offset = sample_ind_offset + 20
      end


      file.seek(sample_offset)
      title_length = file.read(1).unpack("c")[0]

      file.seek(sample_offset + 1)
      @title = file.read(title_length)
      @num_peaks = seq.length

      file.seek(peaks_ind_offset + 20)
      peaks_offset = file.read(4).unpack("N")[0]
      file.seek(peaks_offset)
      @peak_locs = file.read(@num_peaks * 2).unpack("n" * @num_peaks)

 #       file.seek(peaks_ind_offset2 + 20)
 #       peaks_offset2 = file.read(4).unpack("N")[0]
 #       file.seek(peaks_offset2)
 #       @peak_locs2 = file.read(@num_peaks * 2).unpack("n" * @num_peaks)

=end

    @num_peaks = seq.length
    @gmax = @gtrace.max
    @amax = @atrace.max
    @tmax = @ttrace.max
    @cmax = @ctrace.max

=begin
    if(full_id == false)
        @sampid = filename[filename.rindex('/') + 1 .. -1].split(delimiter)[0]
        @primerid = filename[filename.rindex('/') + 1 .. -1].split(delimiter)[1].split('_')[0]
    else
        @sampid = filename[filename.rindex('/') + 1 .. -1].gsub(/\.ab[i1]/i,'')
        @primerid = filename[filename.rindex('/') + 1 .. -1].gsub(/\.ab[i1]/i,'')
    end
=end

    #Normally, this is correct, but since we sometimes rename files that we
    #have incorrectly assigned a wrong name, we shouldn't do this.
    #@sampid, @primerid = @title.split('_')[0].split('+')
#    if(full_id == false)
#        @sampid = filename[filename.rindex('/') + 1 .. -1].split(delimiter)[0]
#        @primerid = filename[filename.rindex('/') + 1 .. -1].split(delimiter)[1].split('_')[0]
#    else
#        @sampid = filename[filename.rindex('/') + 1 .. -1].gsub(/\.ab[i1]/i,'')
#        @primerid = filename[filename.rindex('/') + 1 .. -1].gsub(/\.ab[i1]/i,'')
#    end
  end

  def each
    0.upto(@peak_locs.size - 1) do |i|
      yield @seq[i, 1], @peak_locs[i]
    end
  end

  def complement
    abi = self.clone
    abi.complement!
    return abi
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
end #class Abi


=begin

= Bio::Abi

Reads the data from an ABI chromatogram file and makes it available.

--- Bio::Abi.new(filename)

      Loads the abi file 'filename'

      Example:

      abi = Abi.new('sample.abi');

--- Bio::Abi#complement

      Returns a complemented copy of the Abi object.

--- Bio::Abi#complement!

      Complements the Abi objects traces, peak_locs, and sequences


--- Bio::Abi#seq -> Bio::Sequence::NA

      Returns the sequence.

--- Bio::Abi#peak_locs -> Array

      Returns the locations of the peaks along the traces.  One peak per
      called base in the edit sequence.  This is an array of Integers.

--- Bio::Abi#title -> String

      Returns the title of the sample.

--- Bio::Abi#num_peaks -> Integer

      Returns the number of peaks.

--- Bio::Abi#atrace -> Array

      Returns an array of Integers representing the A trace.

--- Bio::Abi#ctrace -> Array

      Returns an array of Integers representing the C trace.

--- Bio::Abi#gtrace -> Array

      Returns an array of Integers representing the G trace.

--- Bio::Abi#ttrace -> Array

      Returns an array of Integers representing the T trace.
=end
