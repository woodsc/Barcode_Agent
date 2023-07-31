=begin
manager.rb
Copyright (c) 2007-2023 University of British Columbia

Keeps track of information about samples

=end

require 'fileutils'
require 'lib/recall_info'
require 'lib/recall_data'
require 'lib/abi'
require 'lib/scf'
require 'lib/recall_config'
require 'lib/utils.rb'


class Manager
	attr_accessor :maindir, :user
	attr_accessor :labels
	attr_accessor :sample_hash
	@@manager = nil
	def initialize(maindir, user)
		@maindir = maindir
		@user = user
		@labels = []
		@sample_hash = Hash.new
    @sample_primer_delimiter = RecallConfig['common.sample_primer_delimiter']
    @sample_primer_syntax = RecallConfig['common.sample_primer_syntax']
		@sample_primer_regexp = RecallConfig['common.sample_primer_regexp']
		if(@sample_primer_regexp)
			@sample_primer_method = :regexp
		elsif(@sample_primer_syntax)
			@sample_primer_method = :flexible
		else
			@sample_primer_method = :delimiter
		end
    #@sample_primer_method = (@sample_primer_syntax and @sample_primer_syntax.size() > 1) ? (:flexible) : (:delimiter)
    @@manager = self
	end

  def Manager.get_manager
    return @@manager
  end

	def refresh
		@labels = Dir["#{@maindir}/users/#{@user}/*/"].map {|a| a[(a.index(@user) + @user.size + 1) .. -2]}
	end

	def get_labels(match = nil)
		if(match)
			return @labels.grep(Regexp.new(match))
		else
			return @labels
		end
	end

	def get_label_moddate(label)
		begin
			return File.lstat("#{@maindir}/users/#{@user}/#{label}/").mtime
		rescue
			return nil
		end
	end

  def get_recent_labels(i = 10)
    return @labels.sort {|a, b| File.lstat("#{@maindir}/users/#{@user}/#{b}/").mtime <=> File.lstat("#{@maindir}/users/#{@user}/#{a}/").mtime }[0, i]
  end

	def get_samples(label)
		return [] if(label == nil or @user == nil)
		return Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/*.recall"].map {|a| a[a.rindex('/') + 1 .. a.rindex('.recall') - 1]}
	end

	def get_infos(label)
		infos = []
		get_samples(label).each do |samp|
			info = get_info(label,samp)
			infos.push(info)
		end
		return infos
	end
=begin
  #doesn't seem to be used.
  def get_infos_threaded(label)
    @thread = Thread.start do
      get_samples(label).each do |samp|
        info = get_info(label,samp)
      end
    end
  end
=end
	#This is carbon dated, so if the .recall file is updated the info SHOULD reload.
	def get_info(label, samp)
		if(@sample_hash[samp] != nil and File.exist?("#{@maindir}/users/#{@user}/#{label}/#{samp}.recall") and File.mtime("#{@maindir}/users/#{@user}/#{label}/#{samp}.recall") == @sample_hash[samp].read_time)
			return @sample_hash[samp]
		else
			info = RecallInfo.new("#{@maindir}/users/#{@user}/#{label}/#{samp}.recall")
			@sample_hash[samp] = info
			return info
		end
	end

  def get_abis(label, samp)
    files = Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/abi/*#{d_esc(samp)}*"]
    files = files.map do |f|
      sampid, primer, x = nil, nil, nil
      begin
        sampid, primer = *(file_syntax_get_info(f)) #get the sample
      rescue
      end
      if(sampid != samp or primer == nil)
        x = nil
      elsif(f =~ /\.ab1/i)
        begin
          x = Abi.new(f, sampid, primer)
        rescue
          x = nil
        end
      elsif(f =~ /\.scf/i)
        begin
          x = Scf.new(f, sampid, primer)
        rescue
          x = nil
        end
      end
      x
    end
    files.delete(nil)
    return files
  end

  def get_abi_files(label, sample)
    files = Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/abi/*#{d_esc(sample)}*.ab1"] + Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/abi/*#{d_esc(sample)}*.scf"]
    files = files.map do |f|
      sampid, primer, x = nil, nil, nil
      begin
        sampid, primer = *(file_syntax_get_info(f)) #get the sample
      rescue
      end
      if(sampid != sample or primer == nil)
        x = nil
      else
        x = f
      end
      x
    end
    files.delete(nil)
    return files
	end

  def get_polys(label, sample)
    files = Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/qual/*#{d_esc(sample)}*.poly"]
    files = files.map do |f|
      sampid, primer, x = nil, nil, nil
      begin
        sampid, primer = *(file_syntax_get_info(f)) #get the sample
      rescue
      end
      if(sampid != sample or primer == nil)
        x = nil
      else
        x = f
      end
      x
    end
    files.delete(nil)
    return files
	end

  def get_quals(label, sample)
    files = Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/qual/*#{d_esc(sample)}*.qual"]
    files = files.map do |f|
      sampid, primer, x = nil, nil, nil
      begin
        sampid, primer = *(file_syntax_get_info(f)) #get the sample
      rescue
      end
      if(sampid != sample or primer == nil)
        x = nil
      else
        x = f
      end
      x
    end
    files.delete(nil)
    return files
  end

  def get_aprs(label, sample)
    files = Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/apr/*#{d_esc(sample)}*_Alldata.csv"]
    files = files.map do |f|
      sampid, primer, x = nil, nil, nil
      begin
        sampid, primer = *(file_syntax_get_info(f)) #get the sample
      rescue
      end
      if(sampid != sample or primer == nil)
        x = nil
      else
        x = f
      end
      x
    end
    files.delete(nil)
    return files
  end

	def get_recall_data(label, samp)
		return RecallData.new("#{@maindir}/users/#{@user}/#{label}/#{samp}.recall")
	end

  #Returns any files associated with a sample & label.
	def get_sample_files(label, sample)
		return Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/#{d_esc(sample)}.recall"] + get_abi_files(label, sample) + get_polys(label, sample) + get_quals(label, sample) + get_aprs(label, sample)
	end

  #Looks for samples in a directory, returns sample names
	def scan_dir_for_samps(dir)
    @cached_files = []
    @cached_files += Dir["#{d_esc(dir)}/*.ab1"] if(RecallConfig['common.load_abi'] == 'true')
    @cached_files += Dir["#{d_esc(dir)}/*.scf"] if(RecallConfig['common.load_scf'] == 'true')

		#@cached_files.delete_if do |f|
		#	f.include?(',')
		#end

		#return @cached_files.map {|a| a[(a.rindex('/') + 1) .. a.index(@sample_primer_delimiter, (a.rindex('/') + 1)) - 1]}.uniq.sort
    tmp = @cached_files.map do |f|
      sampid, primer = nil, nil
      begin
        sampid, primer = *(file_syntax_get_info(f)) #get the sample
      rescue
				nil
				next
      end
      x = nil
      if(sampid == nil or primer == nil)
        x = nil
      else
        x = sampid
      end
      x
    end
    tmp.delete(nil)
    return tmp.uniq.sort
	end

  #Same as above, but uses cached files from above and returns primers associated with a sample.
  def scan_dir_for_primers(dir, samp, cached = false)
    if(cached and @cached_files != nil)
		  tmp_files = @cached_files.find_all {|a| a =~ /#{Regexp.escape(samp)}/ }
    else
      tmp_files = Dir["#{d_esc(dir)}/*#{d_esc(samp)}*.ab1"] + Dir["#{d_esc(dir)}/*#{d_esc(samp)}*.scf"]
    end

    tmp = tmp_files.map do |f|
      sampid, primer = nil, nil
      begin
        sampid, primer = *(file_syntax_get_info(f)) #get the sample
      rescue
				nil
				next
      end
      x = nil
      if(sampid != samp or primer == nil)
        x = nil
      else
        x = primer
      end
      x
    end
    tmp.delete(nil)
    return tmp.sort
	end

  #Takes a filename and returns a sample/primer.  Also takes an optional :method and :syntax parameter
  def file_syntax_get_info(filename, method = @sample_primer_method, syntax=@sample_primer_syntax)
    sampid = ''
    primer = ''

		filename_pruned = filename.gsub(/^.+\//, '').gsub(/\.(ab1\.poly|ab1\.qual|scf\.poly|scf\.qual|ab1|scf|poly|qual|ab1_Alldata\.csv)/, '')
		if(method == :regexp)
			filename_pruned =~ /#{@sample_primer_regexp}/
			sampid = $1
			primer = $2
			#puts filename
			#puts $1
			#puts $2
		elsif(method == :flexible) #originally used by webrecall
      #build the regexp
      regex = ""
      sample_p = primer_p = next_p = 0
      syntax_arr = nil
      last_char = nil
      begin
        syntax_arr = syntax.split(%r{\s*})

        syntax_arr.each{ |x|
          if last_char=="%" and (x=="s" or x=="p" or x=="o")
            regex+= "(.+?)"
            sample_p = next_p if x=="s"
            primer_p = next_p if x=="p"
            next_p = next_p + 1
          elsif x!="%"
            regex +="["+x+"]"
          end
          last_char = x
        }
        regex += "\.(ab1\.poly|ab1\.qual|scf\.poly|scf\.qual|ab1|scf|poly|qual|ab1_Alldata\.csv)"
      rescue
        raise "ERROR:  Something is wrong with the primer syntax #{regex.inspect}"
      end

      # Check if syntax works for the file name
      #grps = filename.scan(/#{regex}/i).flatten
      grps = filename[filename.rindex('/') + 1 .. -1].scan(/#{regex}/i).flatten

      begin
        if (!grps[sample_p] or !grps[primer_p])
          err = ""
          last_group_tag = false # true if last section of syntax is a tag (%s, %p, etc). Set to '%' if we're partway through reading a group tag (i.e. only % sign is read)
          syntax_arr.each{|x|
            if last_group_tag=="%" and (x=="s" or x=="p" or x=="o")
              err+= ((x == "s" or x == "p") ? " then the " : " then ") if err != ""
              err+= "<b>SAMPLE</b>" if x=="s"
              err+= "<b>PRIMER</b>" if x=="p"
              err+= "<b>OTHER INFO</b>" if x=="o"
              last_group_tag = true
            elsif x=="%"
              last_group_tag = "%"
            elsif last_group_tag
              # beginning of delimiter
              last_group_tag = false
              err += " then <b>#{x}</b>"
            else
              # continuation of delimiter
              err += "<b>#{x}</b>"
            end
          }
          err = "ERROR:  A file does not match the naming convention set by your administrator."
          raise err
        end
      rescue
        if(err != "")
          raise err
        else
          raise "ERROR:  Unexpected error in the syntax checking code."
        end
      end
      #Set the values
      sampid = grps[sample_p]
      primer = grps[primer_p]

    elsif(method == :delimiter)
      sampid = filename[filename.rindex('/') + 1 .. -1].split(@sample_primer_delimiter)[0]
      primer = filename[filename.rindex('/') + 1 .. -1].split(@sample_primer_delimiter)[1].split('_')[0]
      if(!primer)
        primer = filename[filename.rindex('/') + 1 .. -1].gsub(/\.poly$/i,'').gsub(/\.qual$/i,'').gsub(/_Alldata\.csv$/,'').gsub(/\.scf$/i,'').gsub(/\.ab[i1]$/i,'')
      end
    end

    return [sampid, primer, filename_pruned]
  end

end
