=begin
recall_config.rb
Copyright (c) 2007-2023 University of British Columbia

Reads config files and hosts the properties
=end


class RecallConfig
  @@default = Hash.new
	@@secondary = Hash.new #hashes of hashes
	@@primary = Hash.new #hashes of hashes
  @@dir = ''
	@@user_list = []
	@@proj_context = nil
	@@user_context = nil
  @@proj_redirect = Hash.new
  @@proj_joins=[]
  @@proj_chooses=[]

  def RecallConfig.user_context
    return @@user_context
  end

  def RecallConfig.proj_context
    return @@proj_context
  end

  def RecallConfig.dir
    return @@dir
  end

  def RecallConfig.proj_redirect
    return @@proj_redirect
  end

  def RecallConfig.proj_joins
    return @@proj_joins
  end

  def RecallConfig.proj_chooses
    return @@proj_chooses
  end

  def RecallConfig.reload
    RecallConfig.load(@@dir)
  end

  def RecallConfig.clear()
    @@default = Hash.new
    @@secondary = Hash.new #hashes of hashes
    @@primary = Hash.new #hashes of hashes
    @@dir = ''
    @@user_list = []
    @@proj_context = nil
    @@user_context = nil
    @@proj_redirect = Hash.new
    @@proj_joins=[]
    @@proj_chooses=[]
  end

	def RecallConfig.load(dir)
    @@dir = dir
		default_file = Dir[dir + 'default.txt'][0]
		proj_files = Dir[dir + 'proj_*.txt']
		user_files = Dir[dir + 'user_*.txt']
    userlist_files = Dir[dir + 'ulist.txt']

		File.open(default_file) do |file|
			file.each_line do |line|
				next if(line =~ /^\s*$/ or line =~ /^#/ or line == nil or line.strip() == nil)

				prop = line.strip.split('=')
        if(!prop[1])
          prop[1] = ''
				elsif(prop[1].strip =~ /^\d+\.\d+$/)
					prop[1] = prop[1].strip.to_f
				elsif(prop[1].strip =~ /^\d+$/)
					prop[1] = prop[1].strip.to_i
				else
					prop[1] = prop[1].strip
				end
				@@default[prop[0].strip().downcase()] = prop[1]
			end
		end

		proj_files.each do |filename|
			filename =~ /\/proj_(.+)\.txt$/i
      #puts filename
      #next if(!$1)
			name = $1.downcase()
			@@secondary[name] = Hash.new

			File.open(filename) do |file|
				file.each_line do |line|
					next if(line =~ /^\s*$/ or line =~ /^#/ or line.strip == nil)
					prop = line.strip.split('=')
					if(prop[1].strip =~ /^\d+\.\d+$/)
						prop[1] = prop[1].strip.to_f
					elsif(prop[1].strip =~ /^\d+$/)
						prop[1] = prop[1].strip.to_i
					else
						prop[1] = prop[1].strip
					end
					@@secondary[name][prop[0].strip().downcase()] = prop[1]

          #stuff
          if(prop[0].strip =~ /common.split/i)
            @@proj_redirect[name.upcase] = [] if(!@@proj_redirect[name.upcase])
            halves = prop[1].split(':')
            tmp = halves[0].split(',')
            @@proj_redirect[name.upcase] << [tmp[0], tmp[1], halves[1].split(',')]
          end

          if(prop[0].strip =~ /common.join/i)
            @@proj_joins.push(name.upcase)
          end

          if(prop[0].strip =~ /common.choose/i)  #I don't remember what this does?!?!
            tmp = prop[1].split(',').map{|a| a.split(':')}
            @@proj_chooses.push([name.upcase, tmp])  #[PROJNAME, [ [SUBPROJ,SUFFIX], [SUBPROJ,SUFFIX], ...] ]
          end
				end
			end
		end

		user_files.each do |filename|
			filename =~ /\/user_([^\.]+)\.txt/i
			name = $1.downcase()
			@@primary[name] = Hash.new

			File.open(filename) do |file|
				file.each_line do |line|
					next if(line =~ /^\s*$/ or line =~ /^#/)
					prop = line.strip!.split('=')
          if(prop[1] == nil)
            next
					elsif(prop[1].strip =~ /^\d+\.\d+$/)
						prop[1] = prop[1].strip.to_f
					elsif(prop[1].strip =~ /^\d+$/)
						prop[1] = prop[1].strip.to_i
					else
						prop[1] = prop[1].strip
					end
					@@primary[name][prop[0].strip.downcase()] = prop[1]
				end
			end
		end

    File.open(userlist_files[0]) do |file|
      file.each_line do |line|
        @@user_list.push(line.strip)
      end
    end

	end

  # Added for recallweb - Everything goes into @@default
  # Unlike regular recall, there's only one set of properties
  # @param default_file => path to default config file
  def RecallConfig.load_web(default_file)
		# Load default config file
		File.open(default_file) do |file|
			file.each_line do |line|
				next if(line =~ /^\s*$/ or line =~ /^#/ or line.strip==nil)
				prop = line.strip.split('=')
				if(prop[1].strip =~ /^\d+\.\d+$/)
					prop[1] = prop[1].strip.to_f
				elsif(prop[1].strip =~ /^\d+$/)
					prop[1] = prop[1].strip.to_i
				else
					prop[1] = prop[1].strip
				end
				@@default[prop[0].strip.downcase()] = prop[1]
			end
		end
	end

	def RecallConfig.set_context(proj = nil, user = nil)
		@@proj_context = proj.downcase() if(proj)
		@@user_context = user.downcase() if(user)
	end

	def RecallConfig.[](prop)
		if(@@user_context != nil and
		@@primary[@@user_context] != nil and
		@@primary[@@user_context][prop.downcase()] != nil)
			return @@primary[@@user_context][prop.downcase()]
		elsif(@@proj_context != nil and
		@@secondary[@@proj_context] != nil and
		@@secondary[@@proj_context][prop.downcase()] != nil)
			return @@secondary[@@proj_context][prop.downcase()]
		else
			return @@default[prop.downcase()]
		end
	end

  def RecallConfig.[]=(prop, value)
    if(@@user_context != nil and
      @@primary[@@user_context] != nil)
      @@primary[@@user_context][prop.downcase()] = value
		elsif(@@proj_context != nil and
      @@secondary[@@proj_context] != nil)
      @@secondary[@@proj_context][prop.downcase()] = value
		else
			@@default[prop.downcase()] = value
		end
  end

  def RecallConfig.is_user?(usr)
    return (@@user_list.include?(usr) or RecallConfig['common.userlist_disabled'] == 'true')
  end

end
