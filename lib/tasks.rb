=begin
tasks.rb
Copyright (c) 2007-2023 University of British Columbia

Does various common tasks (Can be accessed from multiple modules).  The
bulk of the work is done here.
=end

require 'fileutils'
require 'tempfile'
require 'lib/recall_info'
require 'lib/recall_data'
require 'lib/recall_config'
require 'lib/conversions.rb'
require 'lib/utils'
require 'lib/alg/abi_fixer'
require 'lib/pipelines/default_alignment.rb'
require 'lib/pipelines/no_ref.rb'

class Tasks
	attr_accessor :maindir, :user, :mgr, :message_receiver, :pipelines
  include SeqConversions

	def initialize(manager)
    @mgr = manager
    @maindir = @mgr.maindir
		@user = @mgr.user
    @message_receiver = nil

    @load_scf = RecallConfig['common.load_scf']
    @load_abi = RecallConfig['common.load_abi']

		self.extend(DefaultAlignmentPipeline)
		self.extend(NoRefPipeline)

		@pipelines = {
			default_alignment: {
				process_sample: ->(sample, project, label, msg) {
					default_alignment_process_sample(sample, project, label, msg)
				},
			},
			no_ref: {
				process_sample: ->(sample, project, label, msg) {
					no_ref_process_sample(sample, project, label, msg)
				},
			},
		}
	end

  def message(str)
    @message_receiver.set_text(str) if(@message_receiver)
  end

	def move_samples(label, newlabel, samples)
		samples.each do |samp|
			FileUtils.mv("#{@maindir}/users/#{@user}/#{label}/#{samp}.recall", "#{@maindir}/users/#{@user}/#{newlabel}/#{samp}.recall")
			Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/abi/*#{d_esc(samp)}*"].each do |file|
				FileUtils.mv(file, "#{@maindir}/users/#{@user}/#{newlabel}/abi/")
			end
			Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/qual/*#{d_esc(samp)}*"].each do |file|
				FileUtils.mv(file, "#{@maindir}/users/#{@user}/#{newlabel}/qual/")
			end
		end
	end

	def rename_label(label, newlabel)
		FileUtils.mv("#{@maindir}/users/#{@user}/#{label}/", "#{@maindir}/users/#{@user}/#{newlabel}/")
	end

	def delete_label(label)
    apath = "#{@maindir}users/#{@user}/#{label}"
    bpath = "#{@maindir}users/#{@user}/#{label}".gsub(/^.:/,'')
    cpath = "#{@maindir}users/#{@user}/"
		begin
			if(RUBY_PLATFORM =~ /(win|w)32$/ or RUBY_PLATFORM =~ /x64-mingw-ucrt$/)
		    system("bin\\tar.exe fcv \"#{bpath}.tar\" -C \"#{cpath}\"  \"#{label}/\"")
				system("bin\\gzip.exe -f \"#{apath}.tar\"")
			else
				system("tar fcv \"#{bpath}.tar\" -C \"#{cpath}\"  \"#{label}/\"")
				system("gzip -f \"#{apath}.tar\"")
			end
		rescue
			puts $!
		end
		FileUtils.rm_r(Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/"])
	end

	def delete_primer(label, sample, primer)
		#rd = @mgr.get_recall_data(label, sample)
		#rd.primers.delete_if {|p| p.primerid == primer}
		#rd.save
    files = Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/abi/*"] + Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/qual/*"]
    files.each do |fn|
      s, p, fnp = *(@mgr.file_syntax_get_info(fn))
      FileUtils.rm(fn) if(primer == fnp)
    end

    info = @mgr.get_info(label, sample)
    self.align_samples_custom([[sample, info.project, label, []]], false)
    self.view_log_custom([[sample, info.project, label, []]])
	end

	def delete_sample(label, sample)
    files = Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/abi/*"] + Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/qual/*"]
    files.each do |fn|
      s, p = *(@mgr.file_syntax_get_info(fn))
      FileUtils.rm(fn) if(s == sample)
    end

		FileUtils.rm(Dir["#{d_esc(@maindir)}/users/#{d_esc(@user)}/#{d_esc(label)}/#{d_esc(sample)}.recall"])
	end

	def create_label(label)
		begin
      FileUtils.mkdir("#{@maindir}/users/#{@user}/") if(!File.exist?("#{@maindir}/users/#{@user}/"))
      FileUtils.mkdir("#{@maindir}/users/#{@user}/#{label}/") if(!File.exist?("#{@maindir}/users/#{@user}/#{label}/"))
      FileUtils.mkdir("#{@maindir}/users/#{@user}/#{label}/abi") if(!File.exist?("#{@maindir}/users/#{@user}/#{label}/abi/"))
      FileUtils.mkdir("#{@maindir}/users/#{@user}/#{label}/qual") if(!File.exist?("#{@maindir}/users/#{@user}/#{label}/qual/"))
			FileUtils.mkdir("#{@maindir}/users/#{@user}/#{label}/apr") if(!File.exist?("#{@maindir}/users/#{@user}/#{label}/apr/"))  if(RecallConfig['common.peakcaller'] == 'apr')
		rescue
      puts "Could not create label: #{@maindir}/users/#{@user}/#{label}/"
      retry
		end
	end

  #add variable to disable scf files
  #Looks like this isn't actually used?
	def add_files(label, files)
		files.each do |file|
#			if((file =~ /\.poly/ or file =~ /\.qual/) and @load_phred == 'true')
#        safe_copy(file, "#{@maindir}users/#{@user}/#{label}/qual/")
			if(file =~ /\.ab1/ and @load_abi == 'true')
        safe_copy(file, "#{@maindir}users/#{@user}/#{label}/abi/")
      elsif(file =~ /\.scf/ and @load_scf == 'true')
        safe_copy(file, "#{@maindir}users/#{@user}/#{label}/abi/")
      elsif(file =~ /\.recall/)
				safe_copy(file, "#{@maindir}users/#{@user}/#{label}/")
			end
		end
	end

  def change_comment(label, samp, comment)
    rd = @mgr.get_recall_data(label, samp)
    info = @mgr.get_info(label, samp)
    rd.comments = comment
    rd.save

    if(info.qa.all_good and rd.qa.userexported)
      FileUtils.mkdir("#{@maindir}/approved/#{@user}/#{label}/") if(!File.exist?("#{@maindir}/approved/#{@user}/#{label}/"))
      safe_copy("#{@maindir}/users/#{@user}/#{label}/#{samp}.recall","#{@maindir}/approved/#{@user}/#{label}/#{samp}.recall" )
    end
  end

  #This should cause a approve_samples(label, [sample]) if(recall_data.qa.autogood) right?
  def user_exported(label, samps)
    samps.each do |samp|
      rd = @mgr.get_recall_data(label, samp)
      rd.qa.userexported=true
      rd.save
    end
  end

    #need to make a project hook
  def approve_samples(label, samps, replace = false)
    samps.each do |samp|
      message("Approving #{samp}")
      if(replace == false)
        rd = @mgr.get_recall_data(label, samp)
        rd.qa.userfailed=false
        rd.qa.userunchecked=false
#        rd.qa.userexported=false
        rd.save
      end

      begin
        FileUtils.mkdir("#{@maindir}/approved/") if(!File.exist?("#{@maindir}/approved/"))
        FileUtils.mkdir("#{@maindir}/approved/#{@user}/") if(!File.exist?("#{@maindir}/approved/#{@user}/"))
        FileUtils.mkdir("#{@maindir}/approved/#{@user}/#{label}") if(!File.exist?("#{@maindir}/approved/#{@user}/#{label}"))
      rescue

      end

      safe_copy("#{@maindir}/users/#{@user}/#{label}/#{samp}.recall","#{@maindir}/approved/#{@user}/#{label}/#{samp}.recall" )

      #Do this one at a time like this?:
      rd = @mgr.get_recall_data(label, samp)
      RecallConfig.set_context(rd.project, @user)
      ProjectMethods.approve_samples_post(label, [samp]) #Project custom code
    end
    #Do this one at a time like this?:
    #sample = samp[0]
    #project = samp[1]
    #label = samp[2]
    #recall_data = @mgr.get_recall_data(label, sample)
    #RecallConfig.set_context(recall_data.project, @user)
    #ProjectMethods.approve_samples_post(label, samps) #Project custom code
    self.export_samples(label, samps, "#{@maindir}/approved/#{@user}/#{label}/" )
  end

  def fail_samples(label, samps)
    samps.each do |samp|
      message("Failing #{samp}")
      rd = @mgr.get_recall_data(label, samp)
      rd.qa.userfailed=true
      rd.qa.userunchecked=true
      rd.save
    end
  end


  #Takes an array [[sample, project, label, files]]
  #HLA must be dealt with
  def align_samples_custom(samps, import_recall=false)
    ProjectMethods.align_samples_custom_pre(samps) #Project custom code

    #Project splits
    newsamps = []
    samps.each do |s|
      if(RecallConfig.proj_redirect[s[1]] and RecallConfig.proj_redirect[s[1]] != [])
        #delete the current one.
        redirect = RecallConfig.proj_redirect[s[1]]
        redirect.each do |re|
          a = [s[0] + re[1], re[0], s[2], s[3].find_all {|f| re[2].any?{|p|  @mgr.file_syntax_get_info(f) == [s[0], p] } }]

          0.upto(a[3].size() - 1) do |j| #complicated code for renaming the files.
            f = a[3][j]
            #replace
            i = 0
            new = ''
            done = false
            while(!done) #i THINK this works...  Needs testing...
              x = f.index(s[0], i)
              raise "Could not split file properly:  #{s[0]}" if(x == nil)
              new = f[0 .. x - 1] + s[0] + re[1] + f[x + s[0].size() .. -1]
              i = x + 1
              begin
                tmp = @mgr.file_syntax_get_info(new)
                tmp2 = @mgr.file_syntax_get_info(f)
                if(tmp[0] == s[0] + re[1] and tmp[1] == tmp2[1])
                #if(tmp[0] == s[0] + re[1] and re[2].include?(tmp[1]))

                  a[3][j] = [f, new[new.rindex('/') + 1 .. -1]]
                  done = true
                end
              rescue
              end
            end
          end

          newsamps.push(a) if(a[3] != [])
        end
        s[1] = nil
      end
    end
    samps.delete_if {|s| s[1] == nil }
    newsamps.each {|s| samps.push(s) }

    #Project chooses!
    #Check to see if its part of a choose
    samps.each do |s|
      RecallConfig.proj_chooses.each do |projchoose|
        if(s[1] == projchoose[0]) #Okay, we got a bad case of free will here.
          message("Choosing standard for #{s[0]}")
          bestfit = [nil, -1.0]
          projchoose[1].each do |pc|
#            puts pc.inspect
            #Do a custom basic align, using just the ABI calls, multiple alignment then consensus?
            std = StandardInfo.sequence(pc[0])
            alignment = []
            consensus = ''
            s[3].each do |ab_fn|
              sampid, primer = *(@mgr.file_syntax_get_info(ab_fn)) #get the sample
              abi = Abi.new(ab_fn, sampid, primer)
              #abi = Abi.new(ab_fn, false, @sample_primer_delimiter)
              alignment << [Array.new(std), abi.seq.split('')]
              alignment << [Array.new(std), abi.seq.split('').complement()]
            end

            alignment.each {|a| Aligner.run_alignment(a) }
            Aligner.run_alignment_merge(alignment)
            Aligner.correct_alignment(alignment)

            0.upto(alignment[0][0].size() - 1) do |i|
              next if(alignment[0][0][i] == '-')
              cur = ['-',0]
              ['A','C','T','G','N'].each do |letter|
                cnt = 0
                alignment.each do |elem|
                  cnt += 1 if(elem[1][i] == letter)
                end
                cur = [letter, cnt] if(cnt > cur[1])
              end
              consensus += cur[0]
            end
            #done, now we need to figure out the percentage match
            cnt = 0
            0.upto(std.size() - 1) do |i|
              cnt += 1 if( consensus[i,1] == std[i] )
            end
						#puts "#{s[0]} - #{pc}: #{(cnt.to_f / std.size().to_f)}"
            bestfit = [pc, (cnt.to_f / std.size().to_f)] if((cnt.to_f / std.size().to_f) > bestfit[1])
          end

          #Set the new project
          bestfit[0][1] = '' if(bestfit[0][1] == nil)
          s[1] = bestfit[0][0]

          0.upto(s[3].size() - 1) do |j| #complicated code for renaming the files.
            f = s[3][j]
            #replace
            i = 0
            new = ''
            done = false
            while(!done) #i THINK this works...  Needs testing...
              x = f.index(s[0], i)
              raise "Could not choose file properly:  #{s[0]}" if(x == nil)
              new = f[0 .. x - 1] + s[0] + bestfit[0][1] + f[x + s[0].size() .. -1]
              i = x + 1
              begin
                tmp = @mgr.file_syntax_get_info(new)
                tmp2 = @mgr.file_syntax_get_info(f)
                if(tmp[0] == s[0] + bestfit[0][1] and tmp[1] == tmp2[1])
                 	s[3][j] = [f, new[new.rindex('/') + 1 .. -1]]
                  done = true
                end
              rescue
              end
            end
          end

          s[0] += bestfit[0][1]
        end
      end
    end  #Woo, seems to work.

    samps.uniq!
    samps.sort!(){|a,b| b[0] <=> a[0]}

    message("Adding files")
    samps.each_with_index do |s, i|
			sample = s[0]
      project = s[1]
      label = s[2]
      files = s[3]
      x = "(#{i + 1} / #{samps.size}) #{sample}: "
      has_recall=false

      create_label(label) #add label if it exists

      #add Files
      message("#{x}Adding files")

      files.each do |file|
        origfile = file
        newfile = ''

        if(file.class == Array)
          origfile = file[0]
          newfile = file[1]
        end

        if(origfile =~ /\.recall$/ and import_recall) #import
          safe_copy(origfile, "#{@maindir}users/#{@user}/#{label}/#{newfile}")
          has_recall = true
        elsif(origfile =~ /\.ab1$/ and @load_abi == 'true')
          safe_copy(origfile, "#{@maindir}users/#{@user}/#{label}/abi/#{newfile}")

          #Remove dyeblobs(experimental)
          fixpath = "#{@maindir}users/#{@user}/#{label}/abi/#{newfile}"
          fixpath += origfile.gsub(/.+\//,'') if(newfile == '' or newfile == nil)
          ABIFixer.remove_dyeblobs(fixpath) if(RecallConfig['abi_fixer.dyeblob_enabled'] == 'true')
        elsif(origfile =~ /\.scf$/ and @load_scf == 'true')
          safe_copy(origfile, "#{@maindir}users/#{@user}/#{label}/abi/#{newfile}")
#        elsif((origfile =~ /\.poly$/ or origfile =~ /\.qual$/) and @load_phred == 'true')
#          safe_copy(origfile, "#{@maindir}users/#{@user}/#{label}/qual/#{newfile}")
        end
      end

      #check to see if .recall file has same project as we chose
      if(has_recall and @mgr.get_info(label,sample).project != project)
        has_recall = false
      end

      #create_sample
			if(RecallConfig['common.peakcaller'] == 'apr')
				#apr_sample_raw(s, x)
        phred_sample_raw(s, x)
			else
				phred_sample_raw(s, x)
			end

      sample = s[0]
      project = s[1]
      label = s[2]
      files = s[3]
      x = "(#{i + 1} / #{samps.size}) #{sample}: "
      has_recall=false

      #check to see if .recall file has same project as we chose
      if(has_recall and @mgr.get_info(label,sample).project != project)
        has_recall = false
      end

      create_sample_raw(s, x) if(!has_recall)
      align_sample_raw(s, x) if(!has_recall)
    end


    #Extra final QC code if enabled.
    #Call the QA code to check the genetic distance?
    message("Final QC check")
    rd_set = []
    samps.each_with_index do |s, i|
      sample = s[0]
      label = s[2]
      rd_set << @mgr.get_recall_data(label, sample)
    end

    QualityChecker.check_set(rd_set) #FINAL CHECK OF SET.

    #Approve samples that are auto-good
    samps.each_with_index do |s, i|
      sample = s[0]
      label = s[2]
      approve_samples(label, [sample]) if(rd_set[i].qa.autogood)
    end
  end


  def phred_sample_raw(samp, msg)
    sample = samp[0]
    project = samp[1]
    label = samp[2]
    files = @mgr.get_sample_files(label,sample)
    files.find_all {|s| s =~ /.ab1$/ or s =~ /.scf$/}.each do |f|
      name = f.gsub(/^.+\//,'')
      poly = "#{@maindir}/users/#{@user}/#{label}/qual/#{name}.poly"
      qual = "#{@maindir}/users/#{@user}/#{label}/qual/#{name}.qual"

      if(!File.exist?(poly) or !File.exist?(qual))
        message("#{msg}Phreding")
        #message("Phreding")
        if(RUBY_PLATFORM =~ /(win|w)32$/ or RUBY_PLATFORM =~ /x64-mingw-ucrt$/)
          ENV['PHRED_PARAMETER_FILE'] = './phredpar.dat'
					phred_exe = Dir["bin/phred.exe"].first
					phred_exe = Dir["bin/phred_win32.exe"].first if(phred_exe.nil?)
					phred_exe = Dir["bin/workstation_phred.exe"].first if(phred_exe.nil?)
					phred_exe = Dir["bin/*phred*.exe"].first if(phred_exe.nil?)
					system("#{phred_exe} \"#{f}\" -q \"#{qual}\" -d \"#{poly}\"")
          raise "phred_error"  if(!File.exist?(phred_exe))
        elsif(RUBY_PLATFORM =~ /x86_64-linux/)
          ENV['PHRED_PARAMETER_FILE'] = './phredpar.dat'
          system("bin/phred_linux_x86_64 \"#{f}\" -q \"#{qual}\" -d \"#{poly}\"")
          raise "phred_error"  if(!File.exist?("bin/phred_linux_x86_64"))
        elsif(RUBY_PLATFORM =~ /i686-darwin10/)
          ENV['PHRED_PARAMETER_FILE'] = './phredpar.dat'
          system("bin/phred_darwin \"#{f}\" -q \"#{qual}\" -d \"#{poly}\"") #doesn't actually exist yet
          raise "phred_error"  if(!File.exist?("bin/phred_darwin"))
        else #probably 32 bit linux
          ENV['PHRED_PARAMETER_FILE'] = './phredpar.dat'
          system("bin/phred_linux_i686 \"#{f}\" -q \"#{qual}\" -d \"#{poly}\"")
          raise "phred_error"  if(!File.exist?("bin/phred_linux_i686"))
        end
        #Now we can get rid of this, but I think something more needs to be done. #TODO
        #raise "phred_error" if(!File.exist?(poly) or !File.exist?(qual)) #should determine if phred error or corrupted ABI.
      end
    end
  end

	def apr_sample_raw(label)
		folder = "#{@maindir}/users/#{@user}/#{label}/abi/"
		apr = "#{@maindir}/users/#{@user}/#{label}/apr/"
		message("Running ABI Peak Reporter")
		system("bin/ab1peakreporter-cli.exe \"#{folder}\" \"#{apr}\"")
	end

    #[sample, project, label]
    #Must add HLA special case
  def create_sample_raw(samp, msg)
    sample = samp[0]
    project = samp[1]
    label = samp[2]

		rd = RecallData.new()
    rd.project = project

    message("#{msg}Loading poly and qual files")
    files = @mgr.get_sample_files(label, sample).find_all(){|a| a =~ /(\.poly|\.qual|_Alldata\.csv)$/i }
    #puts files
    pfiles = files.find_all {|s| s.include?('.poly')}.sort()
    qfiles = files.find_all {|s| s.include?('.qual')}.sort()
#    afiles = files.find_all {|s| s.include?('_Alldata.csv')}.sort()

    if(RecallConfig['abi_fixer.dyeblob_enabled'] == 'true')
      #If a cleaned version exists, use that.
      pfiles.find_all(){|a| (a =~ /\.clean\./) }.each do |clean_file|
        pfiles.delete_if(){|a| a == clean_file.gsub('.clean.','.')}
      end
      qfiles.find_all(){|a| (a =~ /\.clean\./) }.each do |clean_file|
        qfiles.delete_if(){|a| a == clean_file.gsub('.clean.','.')}
      end
    else
      #If a cleaned version exists, do not use it.
      pfiles = pfiles.find_all(){|a| !(a =~ /\.clean\./) }
      qfiles = qfiles.find_all(){|a| !(a =~ /\.clean\./) }
    end

    polys = []
    pfiles.each do |pfile|
      sampid, primer = *(@mgr.file_syntax_get_info(pfile))
			qfile = qfiles.find(){|a| a.include?(pfile.gsub('.poly','').gsub(/^.+\//,''))}
			polys <<  Poly.new([pfile, qfile], sampid, primer)
    end


=begin no good
    files.map() {|s| @mgr.file_syntax_get_info(s) }.uniq().sort().each do |info|
      sampid, primer = *info
      pfiles = files.find_all() {|s| info == @mgr.file_syntax_get_info(s)}.sort() #kinda awkward way to do this.
      #Pretty sure this is where my bug is coming in... How to fix?
      polys <<  Poly.new(pfiles, sampid, primer)
    end
=end

    #report corrupted or unphredable files
    files.map() {|s| @mgr.file_syntax_get_info(s) }.uniq().sort().inspect
    abi_files = @mgr.get_sample_files(label, sample).find_all(){|a| a =~ /(\.ab1|\.abi)$/i }.map() {|s| @mgr.file_syntax_get_info(s) }.uniq()
    (abi_files - files.map(){|s| @mgr.file_syntax_get_info(s) }.uniq()).each do |info|
      rd.errors << "Skipped #{info[1]}: primer may be corrupted."
    end

    #This was the previous way.
=begin
    0.upto(pfiles.size - 1) do |j|
      if(File.size(pfiles[j]) != 0 and File.size(qfiles[j]) != 0)
        sampid, primer = *(@mgr.file_syntax_get_info(pfiles[j])) #get the sample
        polys << Poly.new(pfiles[j], qfiles[j], sampid, primer)
      end
    end
=end
    rd.standard = StandardInfo.sequence(rd.project)
		rd.long_standard = StandardInfo.long_sequence(rd.project)
    rd.load_polys(polys)
    rd.save("#{@maindir}/users/#{@user}/#{label}/#{sample}.recall")
  end

  def align_sample_raw(samp, msg)
		sample = samp[0]
    project = samp[1]
    label = samp[2]

		#call the pipeline in the configuration.
		RecallConfig.set_context(project, @user)
		pipeline = RecallConfig['common.pipeline']
		if(pipeline && @pipelines[pipeline.to_sym()])
			@pipelines[pipeline.to_sym()][:process_sample].call(sample, project, label, msg)
		else
			#otherwise, call the default alignment
			@pipelines[:default_alignment][:process_sample].call(sample, project, label, msg)
		end
	end

  #Function to allow the export of a set of samples into a fastafile.
  def export_samples_to_fasta(label, samples, dir)
    #Open the file the sequences will be exported to
    File.open("#{dir}/#{label}.fas", 'w') do |f|
      #present each sample 's' in the list 'samples' for export ...
      samples.each do |s|
        rd = nil
        join = (s.class == Array)
        txt = nil
        #message("Exporting #{s}")
        message("Exporting #{join ? s[0] : s}")
        #get the info from the sample manager
        if(join)
          tmp = []
          s[1 .. -1].each do |sp|
            if(sp[0,1] == '*')
              tmp.push('N' * StandardInfo.sequence(sp[1 .. -1]).size)
            else
              rd = @mgr.get_info(label, sp)
              tmp.push(rd.export_seq)
            end
          end
          txt = tmp.join('XXX')
        else
          rd = @mgr.get_info(label, s)
          txt = rd.export_seq
        end

        RecallConfig.set_context(rd.project, @user)
        if(RecallConfig['tasks.export_lc_edits'] == 'true' and rd)
          rd.human_edits.each do |he|
            loc = he[0].to_i - rd.start_dex
            txt[loc,1] = txt[loc,1].downcase  #maye works?
          end
        end

        # as per the config settings, remove dashes as needed.
        txt.gsub!(/-/,'') if(RecallConfig['tasks.export_with_dashes'] == 'false')

        #apply the fasta sequence header
        f.puts ">#{s[0]}"
        #export the sequence
        f.puts txt
		  end #end each s in samples
    end #end file.open as f
  end #end def E_S_T_F

  def export_samples_to_aa(label, samples, dir)
    samples.each do |s|
      join = (s.class == Array)
      txt = nil
      message("Exporting #{join ? s[0] : s}")
      rd = nil
      if(join)
        tmp = []
        s[1 .. -1].each do |sp|
          if(sp[0,1] == '*')
            tmp.push('N' * StandardInfo.sequence(sp[1 .. -1]).size)
          else
            rd = @mgr.get_info(label, sp)
            tmp.push(rd.export_seq)
          end
        end
        txt = tmp.join('XXX')
      else
        rd = @mgr.get_info(label, s)
        txt = rd.export_seq
      end

      RecallConfig.set_context(rd.project, @user)
      if(RecallConfig['tasks.export_with_dashes'] == 'false')
        txt.gsub!(/-/,'')
      end

      #translate here
      aatxt = ''
      0.upto((txt.size() / 3) - 1) do |i|
        begin
          aa = translate(txt[i * 3, 3].upcase)
          aatxt += aa.size > 1 ? '(' + aa.join('') + ')' : aa[0]
        rescue
          aatxt += 'X'
        end
      end

      File.open("#{dir}/#{join ? s[0] : s}.aa.txt", 'w') do |f|
        f.print aatxt
      end
    end
  end

  #Need to expand to handle "joined" sequences.
  #Probably if a sample is an array instead of a string, they are combined and seperated by XXX, root name is the first element.
  def export_samples(label, samples, dir)
    samples.each do |s|
      join = (s.class == Array)
      txt = nil
      message("Exporting #{join ? s[0] : s}")
      rd = nil

      if(join)
        tmp = []
        s[1 .. -1].each do |sp|
          if(sp[0,1] == '*')
            tmp.push('N' * StandardInfo.sequence(sp[1 .. -1]).size)
          else
            rd = @mgr.get_info(label, sp)
            tmp.push(rd.export_seq)
          end
        end
        txt = tmp.join('XXX')
      else
        rd = @mgr.get_info(label, s)
        txt = rd.export_seq
      end

      RecallConfig.set_context(rd.project, @user)

      if(RecallConfig['tasks.export_lc_edits'] == 'true')
        rd.human_edits.each do |he|
          loc = he[0].to_i - rd.start_dex
          txt[loc,1] = txt[loc,1].downcase  #maye works?
        end
      end

      if(RecallConfig['tasks.export_with_dashes'] == 'false')
        txt.gsub!(/-/,'')
      end

      File.open("#{dir}/#{join ? s[0] : s}.txt", 'w') do |f|
        f.print txt
      end
    end
  end

  def export_samples_quest(label, samples, dir, types)
    return if(types == nil or types == 'false')
    types = types.split(',')

    samples.each do |s|
      message("Exporting #{s}")
      rd = @mgr.get_info(label, s)
#     txt = rd.export_seq
      std = ''
      asm = ''
      std_trans = []
      asm_trans = []

      0.upto(rd.standard.size - 1) do |i|
        if(!(rd.standard[i] == '-' and rd.assembled[i] == '-'))
          std += rd.standard[i]
          asm += rd.assembled[i]
          if(std.size % 3 == 0)
            if(std[-3, 3].include?('-'))
              std_trans << ['-']
            else
              std_trans << translate(std[-3, 3].split(''))
            end
            if(asm[-3, 3].include?('-'))
              asm_trans << ['-']
            else
              asm_trans << translate(asm[-3, 3].split(''))
            end
          end
        end
      end

      if(types.include?('fasta'))
        File.open("#{dir}/#{s}_aligned.fas", 'w') do |f|
          f.print ">#{rd.project}\n#{std}\n>#{rd.sample}\n#{asm}\n"
        end
      end
      if(types.include?('nucpos'))
        File.open("#{dir}/#{s}_nucpos.txt", 'w') do |f|
          f.print "Pos\trefseq\tconsensus\n"
          0.upto(std.size - 1) do |i|
            #a = asm[i] #need to unmix
            next if(std[i,1] == asm[i,1])
            f.print "#{i + 1}\t#{std[i,1]}\t#{asm[i,1]}\n"
          end
        end
      end
      if(types.include?('aapos'))
        File.open("#{dir}/#{s}_aapos.txt", 'w') do |f|
          f.print "Pos\trefseq\tconsensus\n"
          0.upto(std_trans.size - 1) do |i|
            next if(std_trans[i].sort().join('') == asm_trans[i].sort().join(''))
            f.print "#{i + 1}\t#{std_trans[i].sort().join('')}\t#{asm_trans[i].sort().join('')}\n"
          end
        end
      end
    end
  end

  def view_log_custom(samps)
    path = ''
    Tempfile.open("recall.log") do |f|
      path = f.path
      samps.each do |s|
        sample = s[0]
        label = s[2]
        info = @mgr.get_info(label, sample)
        f.puts "#{info.sample} [#{info.project}]: "
        f.puts "\t#{info.mixture_cnt} mixtures, #{info.mark_cnt} marks"
        if(info.errors.size == 0)
          f.puts "\tNo errors"
        else
          f.puts "Errors: "
          info.errors.each do |e|
            f.puts "\t#{e}"
          end
        end
        f.puts
      end
      f.puts
      f.puts "    **PLEASE CLOSE THIS WINDOW TO CONTINUE**"
      f.puts
      f.puts
    end

    begin
      FileUtils.mkdir("#{@maindir}/logs/") if(!File.exist?("#{@maindir}/logs/"))
      FileUtils.mkdir("#{@maindir}/logs/#{@user}/") if(!File.exist?("#{@maindir}/logs/#{@user}/"))
    rescue

    end

    #safe_copy(path, "#{@maindir}/logs/#{@user}/#{Time.now.to_i.to_s}.log") #change to YYYY-MM-DD-HH24-MM-SS-MS.log
    safe_copy(path, "#{@maindir}/logs/#{@user}/#{Time.now.strftime("%Y-%m-%d-%H-%M-%S")}.log") #change to YYYY-MM-DD-HH24-MM-SS-MS.log
    system("notepad #{path}") if(RUBY_PLATFORM =~ /(win|w)32$/)
  end

end
