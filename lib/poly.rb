=begin
poly.rb
Copyright (c) 2007-2023 University of British Columbia

Loads a Poly file.

Notes:
I noticed that sometimes(expecially the first base) has crazy relative areas.
Probably best not to use those.

#need to modify this to accept apr csv files.
=end

require 'lib/sequence'

class Poly
	attr_accessor :primerid, :sampid
	attr_accessor :amp_norm_a, :amp_norm_c, :amp_norm_g, :amp_norm_t

	attr_accessor :called_base, :called_loc, :called_area, :called_area_rel
	attr_accessor :uncalled_base, :uncalled_loc, :uncalled_area, :uncalled_area_rel
	attr_accessor :amp_a, :amp_c, :amp_g, :amp_t
	attr_accessor :size,  :quality, :name

    #Set full_primerid to full if you want to use the filename as the primerid
    #(Recommended if the filename doesn't follow the sampid+primerid_blah.abi)
	#def initialize(poly_filename, qual_filename, full_id = false, delimiter='+')
=begin
  def initialize(poly_filename, qual_filename, sampid='', primerid='') #Maybe just pass in a set of files, and go by filename?  [blah.ab1, blah.poly, blah.qual, blah.apr]
    poly_filename =~ /\/([^\/]+)\.(ab1|scf)\.poly/
    @name = $1
    @sampid = sampid
    @primerid = primerid
		@called_base = []
		@called_loc = []
		@called_area = []
		@called_area_rel = []
		@uncalled_base = []
		@uncalled_loc = []
		@uncalled_area = []
		@uncalled_area_rel = []
		@amp_a = []
		@amp_c = []
		@amp_g = []
		@amp_t = []

    load_poly_file(poly_filename)
		load_qual_file(qual_filename)

	end
=end

  def initialize(files, sampid='', primerid='') #Maybe just pass in a set of files, and go by filename?  [blah.ab1, blah.poly, blah.qual, blah.apr]
    @sampid = sampid
    @primerid = primerid
		@called_base = []
		@called_loc = []
		@called_area = []
		@called_area_rel = []
		@uncalled_base = []
		@uncalled_loc = []
		@uncalled_area = []
		@uncalled_area_rel = []
		@amp_a = []
		@amp_c = []
		@amp_g = []
		@amp_t = []
    @quality = []

    poly_filename = files.find(){|a| a =~ /\.poly$/}
    qual_filename = files.find(){|a| a =~ /\.qual$/}
    apr_filename = files.find(){|a| a =~ /\_Alldata.csv$/}

    if(poly_filename)
      poly_filename =~ /\/([^\/]+)\.(ab1|scf)\.poly/
      @name = $1
      load_poly_file(poly_filename)
      load_qual_file(qual_filename)
    elsif(apr_filename)
      apr_filename =~ /\/([^\/]+)\.(ab1|scf)_Alldata.csv/
      @name = $1
      load_apr_file(apr_filename)
    else
      raise "Could not find poly or abipeakreporter file."
    end

	end


  def load_poly_file(filename)
    File.open(filename) do |file|
			line_num = 0
			file.each_line do |line|
				if(line_num == 0)
					val = line.split(' ')
					#@sampid, @primerid = val[0].split('_')[0].split('+') #Is this even needed?  We take it later from the filename.
          #@sampid = val[0].split(delimiter)[0]
          #@primerid = val[0].split(delimiter)[1].split('_')[0]
					@amp_norm_a = val[2]
					@amp_norm_c = val[3]
					@amp_norm_g = val[4]
					@amp_norm_t = val[5]
				else
					#val = line.split(/\s+/)
					val = line.split(/\s+/)

					@called_base.push val[0]
					@called_loc.push val[1].to_i
					@called_area.push val[2].to_f
					@called_area_rel.push val[3].to_f

					@uncalled_base.push val[4]
					@uncalled_loc.push val[5].to_i
					@uncalled_area.push val[6].to_f
					@uncalled_area_rel.push val[7].to_f

					@amp_a.push val[8].to_f
					@amp_c.push val[9].to_f
					@amp_g.push val[10].to_f
					@amp_t.push val[11].to_f

				end
				line_num += 1
			end
		end
  end

  def load_qual_file(filename)
    File.open(filename, 'r') do |file|
			file.gets("\n")
			data = file.gets(nil).strip
			@quality = data[0 .. -1].split(/\s+/).map {|v| v.to_i }
		end
  end

  #Doesn't seem very good.
  def load_apr_file(filename)
    start = false
    last_line = nil
    @amp_norm_a = '1.0'
		@amp_norm_c = '1.0'
		@amp_norm_g = '1.0'
    @amp_norm_t = '1.0'
    File.open(filename, 'r') do |file|
      file.each_line do |line|
        row = line.split(',')
        last_line = row.clone()
        if(start)
          #Okay, lets see what we need.
          if(row[1] != '-')
            @called_loc << row[0].to_i()
            @amp_g << row[2].to_f()
            @amp_a << row[3].to_f()
            @amp_t << row[4].to_f()
            @amp_c << row[5].to_f()
            @quality << row[6].to_i()

            @called_base << row[1]
            @called_area << 10000.0
            @called_area_rel << 10000.0

            if(row[7] != nil and row[7] != '') #Get uncalled
              ratios_7scan = [['G', row[7].to_f],  ['A', row[8].to_f], ['T', row[9].to_f], ['C', row[10].to_f]].sort(){|a, b| b[1] <=> a[1]}
              ratios_atpeak = [['G', row[11].to_f],  ['A', row[12].to_f], ['T', row[13].to_f], ['C', row[14].to_f]].sort(){|a, b| b[1] <=> a[1]}

              called_ratios_atpeak = ratios_atpeak.find(){|a| a[0] == row[1]}
              called_ratios_7scan = ratios_7scan.find(){|a| a[0] == row[1]}

              #if(((ratios_atpeak - [called_ratios_atpeak])[0][1] * 10000.0).to_i == 0)
              if(((ratios_7scan - [called_ratios_7scan])[0][1] * 10000.0).to_i == 0) #defaults.
                @uncalled_loc << -1
                @uncalled_base << 'N'
                @uncalled_area << -1.0
                @uncalled_area_rel << -1.0
              else
                @uncalled_loc << row[0].to_i()
                #@uncalled_base << (ratios_atpeak - [called_ratios_atpeak])[0][0]
                #@uncalled_area << (ratios_atpeak - [called_ratios_atpeak])[0][1] * 10000.0
                #@uncalled_area_rel << (ratios_atpeak - [called_ratios_atpeak])[0][1] * 10000.0
                @uncalled_base << (ratios_7scan - [called_ratios_7scan])[0][0]
                @uncalled_area << (ratios_7scan - [called_ratios_7scan])[0][1] * 10000.0
                @uncalled_area_rel << (ratios_7scan - [called_ratios_7scan])[0][1] * 10000.0
              end

            else #defaults.
              @uncalled_loc << -1
              @uncalled_base << 'N'
              @uncalled_area << -1.0
              @uncalled_area_rel << -1.0
            end
          end

        elsif(row[0] =~ /ScanNumber/)
          start = true
        end
      end

    end
  end


	def complement
		poly = self.clone
		poly.complement!
		return poly
	end

	#In theory this works...
	def complement!
		@called_base.complement!
		@uncalled_base.complement!
		@called_area.reverse!
		@uncalled_area.reverse!
		@called_area_rel.reverse!
		@uncalled_area_rel.reverse!
		@quality.reverse!

		max = [@called_loc.max, @uncalled_loc.max].max
		@called_loc = @called_loc.map do |v|
			v = max - v
		end
		@called_loc.reverse!

		@uncalled_loc = @uncalled_loc.map do |v|
			v = max - v
		end
		@uncalled_loc.reverse!

		tmp = @amp_a
		@amp_a = @amp_t.reverse
		@amp_t = tmp.reverse

		tmp = @amp_c
		@amp_c = @amp_g.reverse
		@amp_g = tmp.reverse
	end



end
