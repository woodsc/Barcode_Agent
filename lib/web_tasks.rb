=begin
web_tasks.rb
Copyright (c) 2007-2023 University of British Columbia

This is to make the UI a little easier to program.  Seperates a
lot of the actual work out of the controllers.

=end
require 'pp'

class WebTasks
  include SeqConversions
	$QUAL_SCORE = 20 #Minimum score in a qual file for acceptable quality
	$MAX_AA_DISPLAYED = 4 #Maximum number of amino acids that can be displayed in an amino acid cell

  if(defined?(Merb)) #Fix in case we are running the old version.
    if(!defined?($settings))
      class TmpSettings
        attr_accessor :root
      end
      $settings = TmpSettings.new
    end
    $settings.root = Merb.root
  end

  # Uploads files to $settings.root/uploads/#{job_id}/*
  # @param jobid => job id
  # @param file => archived file (*.zip, *.tar, *.tar.gz)
  def WebTasks.upload_files(jobid, file)
    # Make /upload and /data directories if they don't exist yet
    upload_dir = $settings.root+"/uploads/#{jobid}/"
    data_dir = $settings.root+"/data/#{jobid}/"
    FileUtils.mkdir(upload_dir) if(!File.exist?(upload_dir))
    FileUtils.mkdir(data_dir) if(!File.exist?(data_dir))

    newfile = file[:filename]

=begin
    File.open('debug.txt','w') do |fx|
      fx.puts upload_dir.inspect
      fx.puts data_dir.inspect
      begin
        fx.puts file[:tempfile].path.inspect #Yeah, this
      rescue
        fx.puts "Path error"
      end
      fx.puts file.inspect
      fx.puts $settings.root.inspect
      fx.puts jobid.inspect
    end
=end

    FileUtils.cp file[:tempfile].path, upload_dir+newfile, :preserve=>false
    errors = "" #Keeps track of files that can't be processed
    # Need to change directory because tar can't take paths with spaces in it

    #newfile = "\"#{newfile}\"" #In case there are special characters

    #Extract files from archive
#    FileUtils.cd(upload_dir) do
    if(newfile =~ /\.zip/i)
      #system("unzip -j -o #{newfile}", :chdir => upload_dir)
      system("unzip", '-j', '-o', newfile, {:chdir => upload_dir})
    elsif(newfile =~ /\.tar\.gz/i)
      #system("tar fxvz #{newfile} --overwrite", :chdir => upload_dir)
      system("tar", "fxvz", newfile, "--overwrite", {:chdir => upload_dir})
    elsif(newfile =~ /\.tar/i)
      #system("tar fxv #{newfile} --overwrite ", {:chdir => upload_dir})
      system("tar", "fxv", newfile, "--overwrite", {:chdir => upload_dir})
    end
#    end

    #If a tar file made subdirectories, copy everything into the main dir.
    Dir[$settings.root + "/uploads/#{jobid}/**/*"].each do |fn|
      begin
        FileUtils.cp(fn, "#{$settings.root}/uploads/#{jobid}/")
      rescue
      end
    end

    #Delete all subdirs
    Dir[$settings.root + "/uploads/#{jobid}/*/"].each do |fn|
        FileUtils.rm_rf(fn)
    end

    #Delete anything thats not an .ab1 file.
    Dir[$settings.root + "/uploads/#{jobid}/*"].each do |fn|
      if(!(fn =~ /\.ab1$/i or fn =~ /\.scf$/i))
        errors += "#{fn}; " if !(fn =~ /\.zip$/i or fn =~ /\.tar$/i or fn =~ /\.tar\.gz$/i)
        FileUtils.rm(fn)
      end
    end

    return errors == "" ? nil : "Could not process unknown files: "+errors
  end

  # Gets files from $settings.root/uploads/#{job_id}/*
  # @param jobid => job id
  def WebTasks.get_uploaded_files(jobid)
      return Dir[$settings.root+"/uploads/#{jobid}/*"].map {|f| f.gsub(/^.+\//,'')}.sort
  end

  # Deletes all files associated with a job
  # @param jobid => job id
  def WebTasks.delete_job(jobid)
    # Check if /uploads and /data folders exist
    return if !(File.exist?("#{$settings.root}/uploads/#{jobid}/") and File.exist?("#{$settings.root}/data/#{jobid}/"))

    # Remove files from /uploads and /data
    FileUtils.rm_rf("#{$settings.root}/uploads/#{jobid}/")
    FileUtils.rm_rf("#{$settings.root}/data/#{jobid}/")
  end

  # Deletes all files associated with a job
  # @param jobid => job id
  # @param sampid => sample id
  def WebTasks.delete_sample(jobid, sampid)
    # Check if /uploads and /data folders exist
    puts "######{$settings.root}/data/#{jobid}/#{sampid}/"
    return false if !(File.exist?("#{$settings.root}/uploads/#{jobid}/") and File.exist?("#{$settings.root}/data/#{jobid}/#{sampid}/"))

    # Remove files from /data
    FileUtils.rm_rf("#{$settings.root}/data/#{jobid}/#{sampid}/")

    # Remove appropriate files from /upload
    all_files = WebTasks.get_uploaded_files(jobid)
    primers = Primer.all(:sample_id => sampid) # Files belonging to these primer samples will be deleted
    primers.each{|p|
      FileUtils.rm("#{$settings.root}/uploads/#{jobid}/#{p.file}") if all_files.include?(p.file)
    }
    return true
  end

  # Deletes files associated with a primer
  # @param jobid => job id
  # @param sampid => sample id
  # @param pfile => name of primer file
  def WebTasks.delete_primer(jobid, sampid, pfile)
    # Check if /uploads and /data folders exist
    return false if !(File.exist?("#{$settings.root}/uploads/#{jobid}/") and File.exist?("#{$settings.root}/data/#{jobid}/#{sampid}/"))

    # Remove primer file from /data
    pfile.scan(/(.+)\.+/)
    FileUtils.rm_rf("#{$settings.root}/data/#{jobid}/#{sampid}/#{$1}.*")

    # Remove appropriate file from /upload
    FileUtils.rm("#{$settings.root}/uploads/#{jobid}/#{pfile}")
    return true
  end

  # Makes sample folder $settings.root/data/#{jobid}/#{sampid}
  # @param jobid => job id
  # @param sampid => sample id
  def WebTasks.create_sample(jobid, sampid)
      FileUtils.mkdir($settings.root+"/data/#{jobid}/") if(!File.exist?($settings.root+"/data/#{jobid}/"))
      FileUtils.mkdir($settings.root+"/data/#{jobid}/#{sampid}/") if(!File.exist?($settings.root+"/data/#{jobid}/#{sampid}/"))
  end

  # Phreds a file
  # @param uid => user id
  # @param file => sample file
  def WebTasks.phred(uid, file, path)
    if(!File.exist?("#{path}#{file}.poly") or !File.exist?("#{path}#{file}.qual"))
      # Convert from SCF3 to SCF2 if necessary
      if file[file.length-3,3].downcase=="scf"
        # create directory to house converted files
        FileUtils.mkdir("#{$settings.root}/config/recall/#{uid}")
        # do conversion
#        FileUtils.cd(path) do
          #system("phred \"#{file}\" -cd \"#{$settings.root}/config/recall/#{uid}\" -cv 2", :chdir => path)
          system("phred", file, '-cd', "#{$settings.root}/config/recall/#{uid}", "-cv", "2", {:chdir => path})
#        end
        # replace original files
        FileUtils.mv("#{$settings.root}/config/recall/#{uid}/#{file}", "#{path}#{file}", :force => true)
        # remove temporary files
        FileUtils.rm_rf("#{$settings.root}/config/recall/#{uid}")
      end
      # Create qual and poly files
#      FileUtils.cd(path) do
        #system("phred \"#{file}\" -q \"#{file}.qual\" -d \"#{file}.poly\" -process_nomatch", :chdir => path)
        system("phred", file, "-q", "#{file}.qual", "-d", "#{file}.poly", "-process_nomatch", {:chdir => path})
#      end

      raise "phrederror" if(!File.exist?("#{path}#{file}.poly")) #Let us know if phred is choking.
    end
  end

  # Links (linux) or copies (windows) files from /data to /uploads
  def WebTasks.assign_sample(jobid, filename, sampid)
      #Skip if its already there
      return if(File.exist?($settings.root+"/data/#{jobid}/#{sampid}/#{filename}"))
      #delete it from other directories
      files = Dir[$settings.root+"/data/#{jobid}/*/#{filename}"]
      files.each {|f| FileUtils.rm(f) }

      #copy it to new directory - method based on OS
      if (RUBY_PLATFORM =~ /mswin/)
        # Windows
        FileUtils.cp("#{$settings.root}/uploads/#{jobid}/#{filename}", "#{$settings.root}/data/#{jobid}/#{sampid}/#{filename}") if(!File.exist?($settings.root+"/data/#{jobid}/#{sampid}/#{filename}"))
      else
        #Speed optimization if on a unix filesystem.  (removed, so I can delete the uploads directory periodically)  Hrm...
        FileUtils.cp("#{$settings.root}/uploads/#{jobid}/#{filename}", "#{$settings.root}/data/#{jobid}/#{sampid}/#{filename}") if(!File.exist?($settings.root+"/data/#{jobid}/#{sampid}/#{filename}"))
        #FileUtils.ln_s("#{$settings.root}/uploads/#{jobid}/#{filename}", "#{$settings.root}/data/#{jobid}/#{sampid}/#{filename}") if(!File.exist?($settings.root+"/data/#{jobid}/#{sampid}/#{filename}"))
      end
    end

  # Retrieves .recall file for sample
  # @param jobid => job id
  # @param sampid => sample id
  def WebTasks.get_recall_data(jobid, sampid)
      rd = RecallData.new("#{$settings.root}/data/#{jobid}/#{sampid}/#{sampid}.recall", true)
  end

  # Exports an array of samples in fasta format to job folder
  # @param jobid => job id
  # @param sampid_arr => array of sample ids for export
  # @param dash => export sequences with dashes in them? (boolean)
  def WebTasks.export_fasta(jobid, sampid_arr, dash=false)
    # Determine filename for fasta file based on the number of samples there are
    filename = nil
    if (sampid_arr.size > 1)
      # More than one sample, so name file after job # (job_#.fas)
      filename = $ARCHIVE_PREFIX + jobid.to_s
    else
      # Only one sample, so name file after sample (sample_name.fas)
      s = Sample.get(sampid_arr[0])
      return "Samples no longer exist or all failed" if !s
      filename = s.name if s
    end
    # Make export file
    export_file = File.new("#{$settings.root}/data/#{jobid}/#{filename}.fas", 'w')

    sampid_arr.each{ |sid|
      # Get sample name
      s = Sample.get(sid)
      return "Sample no longer exists" if !s
      sample_name = s.name
      # Get Recall data from .recall file
      ri = RecallInfo.new("#{$settings.root}/data/#{jobid}/#{sid}/#{sid}.recall")
      return "Could not load job:#{jobid}, sample:#{sid} .recall file" if !ri
      # Get assembled sequence
      seq = ri.export_seq
      # Get rid of dashes if necessary
      seq.gsub!(/-/,'') if !dash
      # Export fasta-style
      export_file.puts ">#{sample_name}"
      export_file.puts seq
    }

    export_file.close
    return nil # No errors!
  end

  # Exports an array of samples in text format to job folder
  # @param jobid => job id
  # @param sampid_arr => array of sample ids for export
  # @param dash => export sequences with dashes in them? (boolean)
  def WebTasks.export_text(jobid, sampid_arr, dash=false)
    sampid_arr.each{|sid|
      # Find the name of the sample
      s = Sample.get(sid)
      return "Sample no longer exists" if !s
      sample_name = s.name
      # Get Recall data from .recall file
      ri = RecallInfo.new("#{$settings.root}/data/#{jobid}/#{sid}/#{sid}.recall")
      return "Could not load job:#{jobid}, sample:#{sid} .recall file" if !ri
      # Get assembled sequence
      seq = ri.export_seq
      # Get rid of dashes if necessary
      seq.gsub!(/-/,'') if !dash

      # Make an export text file
      export_file = File.new("#{$settings.root}/data/#{jobid}/#{sample_name}.txt", 'w')
      export_file.puts seq
      export_file.close
    }
    return nil
  end

  # Exports job summary as an .xls file
  # @param jobid => job id
  # @param rds => hash: {sample_name}=>RecallData obj.
  # @param qual => hash: {[sample_name, primer_name, file_name]}=>quality_score
  def WebTasks.export_summary(jobid, rds, qual)
    book = Spreadsheet::Workbook.new
    # Get objects
    j = Job.get(jobid)
    label_offset = StandardPref.get(j.standard_id).label_offset
    return "Job no longer exists" if !j
    # Set up spreadsheet headers
    # 1) Job/Sample summary
    pg1 = book.create_worksheet
    pg1.name = "Job Summary"
    pg1[0,0] = "Recall: #{$settings.version}"
    pg1[1,0] = "Process date: #{j.created_at}"
    pg1.row(3).replace(["SAMPLE", "STATUS", "MARK COUNT",  "MIXTURE COUNT", "N COUNT", "EDIT COUNT", "ERRORS"])
    # 2) Quality
    pg2 = book.create_worksheet
    pg2.name = "Quality"
    pg2.row(0).replace(["SAMPLE", "PRIMER", "FILE", "QUALITY"])

    # Convert hashes to arrays by sorting results
    rds = rds.sort
    qual = qual.sort

    # Fill in the spreadsheet
    # 1) Job/Sample summary
    rds.each_with_index{|rd,i|
      # row: sample_name, status (passed/failed), mark_count, mixture_count, n_count, edit_count, errors
      pg1.row(4+i).replace([rd[0], (!rd[1].qa.mostly_good and !rd[1].qa.all_good) ? "Failed" : (!rd[1].qa.all_good and (rd[1].qa.needs_review or rd[1].qa.mostly_good)) ? "Manual review" : "Passed", rd[1].mark_cnt, rd[1].mixture_cnt, rd[1].n_cnt, rd[1].human_edit_cnt, rd[1].errors.join(',')])
    }
    # 2) Quality
    # Sample-Primer-File quality
    qual.each_with_index{|f,i|
      # row: sample_name, primer_name, file_name, quality_score
      pg2.row(1+i).replace([f[0][0], f[0][1], f[0][2], f[1]])
    }

    #+--------------------------------------QC sequence comparison and tree--------------------------------------
    #First, we need to find the closest sequences to these ones.
    seq_list_cur = Sequence.all(:user_id => j.user_id, :standard_id  => j.standard_id, :job_id => jobid)
    seq_list = Sequence.all(:user_id => j.user_id, :standard_id  => j.standard_id)
    #I suppose this is going to be slow potentially...
    diff_cutoff = 0.015 #2.5%
    match_list = []
    fails = []

    seq_list_cur.each do |seqa|
      seqa_rd = rds.find() {|rd| rd[0] == seqa.name}
      if(seqa_rd == nil)
        puts "Could not find RD for #{seqa.name}"
        next
      end

      seqa_status = (!seqa_rd[1].qa.mostly_good and !seqa_rd[1].qa.all_good) ? "Failed" : ((!seqa_rd[1].qa.all_good and seqa_rd[1].qa.needs_review) ? "Manual review" : "Passed")
      if(seqa_status == 'Failed')
        fails << seqa.name
        next
      end
    end

    seq_list_cur.delete_if(){|a| fails.include?(a.name)} #get rid of failures from this set.
    seq_list.delete_if(){|a| fails.include?(a.name) and a.job == jobid} #get rid of failures from this set.

    seq_list_cur.each do |seqa|
      seq_list.each do |seqb|
        next if(seqa.name == seqb.name or seqb.job == nil)
        df = 0
        0.upto(seqa.nuc.size() - 1) do |i|
          df += 1 if(seqa.nuc[i,1] != seqb.nuc[i,1])
          break if(df > diff_cutoff * seqa.nuc.size())
        end
        match_list << [seqa, seqb, df, (((df.to_f / seqa.nuc.size().to_f) * 10000.0).to_i.to_f / 100.0).to_s + '%' ] if(df < diff_cutoff * seqa.nuc.size().to_f)
      end
    end
    match_list.sort!{|a,b| a[0].name == b[0].name ? a[0].name <=> b[0].name : a[1].name <=> b[1].name }

    #Add the excel sheet entry
    pg5 = book.create_worksheet

    pg5.name = "Similarity Check"
    row = 1
    pg5[0,0]= "Sample A"
    pg5[0,1]= "Sample B"
    pg5[0,2]= "Differences"
    pg5[0,3]= "Percent Different" #should test this yo

    treedata = (seq_list_cur + [])
    match_list.each do |match|
      pg5[row, 0] = match[0].name + " #{match[0].job.name}(#{match[0].job.id})"
      pg5[row, 1] = match[1].name + " #{match[1].job.name}(#{match[1].job.id})"
      pg5[row, 2] = match[2].to_s
      pg5[row, 3] = match[3]
      row += 1

      treedata << match[1] #add to tree data if needed
    end

    #Now for the trees
    treedata.uniq!()

	ref_tree = []
	cs = nil
	begin
		cs = Sample.all(:job_id => jobid).map(){|a| StandardPref.get(a.standard_pref_id) }
	rescue
		puts $!
		puts $!.backtrace
	end

	if(cs)
		cs.each do |c|
			if(c.annotations and c.annotations.include?("region=NS3"))
				$settings.reference_tree_standards['NS3'].each do |ref|
					ref_tree << ["REF_" + ref[0], ref[1]]
				end
			elsif(c.annotations and c.annotations.include?("region=NS5A"))
				$settings.reference_tree_standards['NS5A'].each do |ref|
					ref_tree << ["REF_" + ref[0], ref[1]]
				end
			elsif(c.annotations and c.annotations.include?("region=NS5B"))
				$settings.reference_tree_standards['NS5B'].each do |ref|
					ref_tree << ["REF_" + ref[0], ref[1]]
				end
			end
		end
	end
	ref_tree.uniq!()

	#Then we build a reference fasta(if we are using a guessset).
	if(cs)
		File.open("#{$settings.root}/data/#{jobid}/#{$ARCHIVE_PREFIX}#{jobid}_references.fas", 'w') do |file|
			cs.uniq.sort(){|a,b| a.name <=> b.name }.each do |c|
				standard = Standard.get(c.standard_id)
				file.puts ">#{c.name}\n#{standard.sequence}"
			end
		end
	end



    tmppath = "#{$settings.root}/data/#{jobid}/#{jobid}_tree"
    #then we build a fasta
    File.open("#{tmppath}.fas", 'w') do |file|
		ref_tree.each do |dat|
			file.puts ">#{dat[0]}\n#{dat[1]}"
		end
		treedata.each do |dat|
			file.puts ">#{dat.name.gsub(' ', '_')}_job-#{dat.job.id}\n#{dat.nuc}"
		end
	end


    #Then we turn it into a treefile
    #system("/usr/local/bin/FastTree -nt #{tmppath}.fas > #{tmppath}.tre")
	system("fasttree -nt #{tmppath}.fas > #{tmppath}.tre")

	#Reroot to clade 6
	if(ref_tree.size() > 0)
		system("nw_reroot #{tmppath}.tre REF_6 > #{tmppath}.tre2") #something like this
	else
		FileUtils.cp("#{tmppath}.tre", "#{tmppath}.tre2")
	end

    #Then we turn it into a SVG
    #system("java -jar /usr/local/bin/TreeVector.jar #{tmppath}.tre -phylo -out #{tmppath}.svg")
	system("java -jar TreeVector.jar #{tmppath}.tre2 -phylo -out #{tmppath}.svg")
    #Then we turn it into a PDF
    system("inkscape -f \"#{tmppath}.svg\" -A #{tmppath}.pdf")

    #Then cleanup
    begin
      FileUtils.rm(tmppath + '.fas')
      FileUtils.rm(tmppath + '.tre')
	  FileUtils.rm(tmppath + '.tre2')
      FileUtils.rm(tmppath + '.svg')
    rescue

    end


    #+------------------------------------added by Shabnam------------------------------------



    # 3) Mutation List
    # row: reference number, 3 char set
    pg3 = book.create_worksheet
    pg3.name = "Mutation List"
    #pg3[0,0] = "Process date: #{j.created_at}"
    row = 1
    pg3[0,0]="Sample"
    pg3[0,1]= "Amino acid Position"
    pg3[0,2]= "Reference"
    pg3[0,3]= "Protein";
    pg3[0,4]= "Standard"
    pg3[0,5]= "Assembled"
    pg3[0,6]= "Status"
    #require '/home/lab/recall_test/lib/getData.rb'
    #gd = GetData.new
    rds.each do |rd|
      sample_id = rd[1].sample
      sample_name = rd[0]
      status = (!rd[1].qa.mostly_good and !rd[1].qa.all_good) ? "Failed" : (!rd[1].qa.all_good and rd[1].qa.needs_review) ? "Manual review" : "Passed"
      asm = rd[1].assembled.join('')[rd[1].start_dex() .. rd[1].end_dex()] #double check that this doesn't need a +1 or -1
      std = rd[1].standard.join('')[rd[1].start_dex() .. rd[1].end_dex()]
      asm = asm.scan(/.../) #split into 3 base chunks
      std = std.scan(/.../) #split into 3 base chunks

      #Making the AA list
      asm_aa = asm.map do |nuc|
        res = ''
        aa = translate(nuc)
        if(aa == [nil])
          res = '-'
        elsif(aa.size > 2)
          res = 'X'
        elsif(aa.size == 1)
          res = aa.join('')
        else
          res = '[' + aa.sort.join('/') + ']'
        end
        res
      end

      #Making the AA list
      std_aa = std.map do |nuc|
        res = ''
        aa = translate(nuc)
        if(aa == [nil])
          res = '-'
        elsif(aa.size > 2)
          res = 'X'
        elsif(aa.size == 1)
          res = aa.join('')
        else
          res = '[' + aa.sort.join('/') + ']'
        end
        res
      end

      #draw to excel
#        row += 1
      for i in 0 .. (std_aa.length-1)
        if(std_aa[i] != asm_aa[i])
          pg3[row,0] = sample_name
          pg3[row,1] = i + label_offset # start the indeces from 1 instead of zero
          pg3[row,2] = std_aa[i]
          pg3[row,3] = asm_aa[i]
          pg3[row,4] = std[i]
          pg3[row,5] = asm[i]
          pg3[row,6] = status
          row += 1
        end
      end

    end


    if(rds.any?{ |rd| rd[1].phred_mix_perc and rd[1].phred_mix_perc.size > 0 })
      pg4 = book.create_worksheet
      pg4.name = "Mixture relative peak heights"
      row = 1
      pg4[0,0]= "Sample"
      pg4[0,1]= "Nucleotide Position"
      pg4[0,2]= "Wildtype"
      pg4[0,3]= "Mixture"
      pg4[0,4]= "Percentage"
      pg4[0,5]= "Percentage of Total"

      rds.each do |rd|
        sample_id = rd[1].sample
        sample_name = rd[0]
        dex = 1
        0.upto(rd[1].assembled.size() - 1) do |i|

          if(['R','Y','K','M','S','W','B','D','H','V'].include?(rd[1].assembled[i]))
            asm = rd[1].assembled[i]
            std = rd[1].standard[i]
            mix = rd[1].phred_mix_perc[i]
            tmix = 0.0
            ['A','T','G','C'].each {|a| tmix += mix[a] } if(mix)
            mixstr = ''
            mixstr2 = ''
            mixstr = @@ambig_nucs[asm].map {|a| "#{a}: #{(mix[a] * 100).to_i}%" }.join('; ') if(mix)
            mixstr2 = @@ambig_nucs[asm].map {|a| "#{a}: #{ (mix[a] / tmix).nan? ? 0 : ((mix[a] / tmix) * 100).to_i}%" }.join('; ') if(mix)
            pg4[row,0] = sample_name
            pg4[row,1] = dex #loc
            pg4[row,2] = std
            pg4[row,3] = asm
            pg4[row,4] = mixstr
            pg4[row,5] = mixstr2
            row += 1
          end
          dex += 1 if(rd[1].assembled[i] != '-')
        end

#          row += 1
      end
      book.write("#{$settings.root}/data/#{jobid}/job_#{jobid}_summary.xls")
    end
  end



  #Actually, we should consider putting this in tasks as well?  Well, wait for now...
  #Need to somehow generate based on virco alg as well.
  #Man, this code is crap, I should reorganize some of it...
  #Like...
  #1)  Figure out settings
  #2)  Generate Genotypes with extra useful info. (hashes?)
  #3)  Make Resistance Summary
  def WebTasks.generate_reports(jid, sids)
    j = Job.get(jid)
    g = j.user.group
    pref = g.report_pref
    return "Job no longer exists" if !j
    rd_hash = {} # Hash: key => sample_name, value => RecallData obj

    valg = VircoAlgorithm.new() #This probably be somewhere more global.
    hcv_alg = HCVAlgorithm.new() #So should this. #old
	hcv_rules = HCVRules.new('config/recall/hcv_rules.1.8.yaml') #new

    sierra_hash = {}
    virco_hash = {}
    hcv_hash = {}

    tmp_seqs = []
    lm_seqs = []
    # Collect the RecallData objects
    sids.each do |sid|
      s = Sample.get(sid)
      rd_hash[[s.name, s.id]] = RecallInfo.new("#{$settings.root}/data/#{jid}/#{s.id}/#{s.id}.recall")
      seq = rd_hash[[s.name, s.id]].export_seq
      seq_no_inserts = rd_hash[[s.name, s.id]].export_seq_no_inserts
      spref = StandardPref.last(:id => rd_hash[[s.name, s.id]].project)

      if(spref and spref.report_type == :prrt and pref.report_algorithm == 'LM')
        rd = rd_hash[[s.name, s.id]]
        #We also need the inserts
        ins = []
        newins = nil
        pos = 1
        0.upto(rd.standard.length() - 1) do |i|
          prot = (pos <= 297 ? 'P' : 'R')
          if(rd.assembled[i] != '-' and rd.standard[i] == '-')
            #Insert, start recording or something?
            if(newins == nil)
              newins = [prot, (prot == 'P' ? ((pos - 1) / 3) : ((pos -  298) / 3)), '']
            end
            newins[2] += rd.assembled[i]
          elsif(newins != nil)
#              newins[2] = translate_complete_to_array(newins[2])[0]
            ins << newins
            newins = nil
          end
          pos += 1 if(rd.standard[i] != '-')
        end
        #$stderr.puts ins.inspect
        virco_hash[[s.name, s.id]] = valg.interpret(seq_no_inserts, ins)
      elsif(spref and [:prrt, :integrase].include?(spref.report_type))
        tmp_seqs << seq
	elsif(spref and [:hcv].include?(spref.report_type))
		rd = rd_hash[[s.name, s.id]] #recall data

		#First, we need grab the geno and region from the sample annotations
		genotype = nil
		region = nil
		if(s.annotations)
			anno = s.annotations.split(';').map(){|a| a.split('=')}
			genotype = anno.find(){|a| a[0] == 'genotype' }[1]
			region = anno.find(){|a| a[0] == 'region' }[1]
		end

		alg_std = hcv_rules.standards[[region, genotype]]

		#Next, we make sure the recall standard aligns to our reference standard.  This is so we can use shorter standards without breaking the resistance calls.
		seq_std = rd.standard.join('')
		seq_nuc = rd.assembled.join('')
		if(seq_std =~ /^(-+)/) #trim off the dashes at the start, they ain't needed
			seq_std = seq_std[$1.size() .. -1]
			seq_nuc = seq_nuc[$1.size() .. -1]
		end
		if(seq_std =~ /(-+)$/) #trim off the dashes at the end, they ain't needed
			seq_std = seq_std[0 .. -($1.size() + 1)]
			seq_nuc = seq_nuc[0 .. -($1.size() + 1)]
		end

		next if(alg_std == nil or seq_std == nil or alg_std == '' or seq_std == '')
		std_elem = align_it(alg_std, seq_std, 24, 1) #ridiculously high gap init penalty to keep things behaved.


		#slice up the sequences to match the reference standard.
		offset = 0
		if(std_elem[0] =~ /^(\-+)/)
			offset = ($1 ? $1.size() : 0)
		end
		if(std_elem[1] =~ /^(\-+)/)
			offset = ($1 ? -$1.size() : 0)
		end

		if(offset < 0)
			seq_std = ('-' * -offset) + seq_std
			seq_nuc = ('-' * -offset) + seq_nuc
		else
			seq_std = seq_std[offset .. -1]
			seq_nuc = seq_nuc[offset .. -1]
		end

		#Okay, now we can find insertions now that we have most of a properly aligned sequence.(in theory)
		final_inserts = []
		scan_dex = 0
		while(scan_dex = seq_std.index(/(-+)/, scan_dex))
#					STDERR.puts "Found:  #{scan_dex}: #{$1},  #{seq[scan_dex, $1.size()]}" if(scan_dex != 0)
			final_inserts << [scan_dex, seq_nuc[scan_dex, $1.size()]] if(scan_dex != 0)
			scan_dex += $1.size()
		end

		#I guess we also need to strip them out.
		final_seq = seq_nuc
		final_inserts.reverse.each do |ins| #easier to do backwards
			final_seq[ins[0], ins[1].size() ] = ''
		end

		#Replace N's with dashes.(or X's?)
		if(final_seq =~ /^(N+)/)
			final_seq = ('-' * $1.size()) + final_seq[$1.size() .. -1]
		end
		if(final_seq =~ /(N+)$/)
			final_seq = final_seq[0 .. -($1.size() + 1)] + ('-' * $1.size())
		end
		aa_seq = translate_complete_to_array(final_seq)
		0.upto(aa_seq.size() - 1) do |i|
			if(aa_seq[i] != ['X'])
				break
			else
				aa_seq[i] = []
			end
		end
		(aa_seq.size() - 1).downto(0) do |i|
			if(aa_seq[i] != ['X'])
				break
			else
				aa_seq[i] = []
			end
		end
		aa_seq.each do |aa|
			0.upto(aa.size() - 1) do |aa_i|
				aa[aa_i] = 'd' if(aa[aa_i] == 'X' or aa[aa_i] == '-')
			end
		end

		#Add inserts to amino string
		final_inserts.each do |ins|
			aa_seq[(ins[0] / 3)] << 'i'
		end

		#NICE, seems to be working up to here as far as I can tell
		begin
          hcv_hash[[s.name, s.id]] = hcv_rules.interpret(genotype, region, aa_seq)
        rescue
          hcv_hash[[s.name, s.id]] = {:fail => true}
        end


      elsif(false and spref and [:hcv_ns3_1a, :hcv_ns5a_1a,:hcv_ns5b_1a].include?(spref.report_type)) #kill?
        region = {:hcv_ns3_1a => 'NS3', :hcv_ns5a_1a => 'NS5A', :hcv_ns5b_1a => 'NS5B'}[spref.report_type]
        geno = '1A'
        #DO HCV ALG.
        rd = rd_hash[[s.name, s.id]]
        ins = []
        newins = nil
        pos = 1
        0.upto(rd.standard.length() - 1) do |i|
          if(rd.assembled[i] != '-' and rd.standard[i] == '-')
            #Insert, start recording or something?
            if(newins == nil)
              newins = [((pos - 1) / 3), '']
            end
            newins[1] += rd.assembled[i]
          elsif(newins != nil)
            ins << newins
            newins = nil
          end
          pos += 1 if(rd.standard[i] != '-')
        end
        begin
          hcv_hash[[s.name, s.id]] = hcv_alg.interpret(seq_no_inserts, region, geno, ins)
        rescue
          hcv_hash[[s.name, s.id]] = {:fail => true}
        end
      end
    end

    sierras = []
    sierra_error = false
	if(tmp_seqs.size() > 0)
		begin
		  sierras = SierraResult.analyze(tmp_seqs, pref.report_algorithm == 'LM' ? 'HIVDB' : pref.report_algorithm)
		rescue Exception => e
		  sierra_error = true
	  end
	end
    sierras.each {|s| sierra_hash[s.nuc_seq] = s }
    genos = []
    projs = []

    #Lets fill these if empty!
    s_nrti_drugs = []
    s_nnrti_drugs = []
    s_pi_drugs = []
    s_int_drugs = []

    s_hcv_drugs = []

    rd_hash.each do |key, rd|
      #something!
      sample_state = (!rd.qa.all_good and !rd.qa.mostly_good) ? 'failed' : (!rd.qa.all_good and rd.qa.needs_review) ? 'needsreview' : 'approved'
      #next if sample_state == 'approved'
      #'failed'
      begin
        seq = rd.export_seq
        geno = GenotypeReport.new(key[0])
        if(pref.logo_img == false)
          geno.logo_path = nil
        else
          filename = Dir["#{$settings.root}/public/images/logos/#{g.id}_logo.*"]
          geno.logo_path = filename[0]
        end
        spref = StandardPref.last(:id => rd.project)
        next if(spref == nil)

        if(spref.report_type == :none)
          next #no report for you
        elsif(spref.report_type == :integrase)
          geno.int_seq = seq
          projs << :integrase
          geno.int_bad = true if(sample_state == 'failed')

          aa = seq.scan(/.../).map{|n|
            a = translate(n)
            res = ''
            if(a == [nil])
              res = '-'
            elsif(a.size > 2)
              res = 'X'
            elsif(a.size == 1)
              res = a.join('')
            else
              res = '[' + a.sort.join('/') + ']'
            end
            res
          }.join('')

          geno.front_page_seq = "Inferred Amino Acid Sequence:  " + aa #translate yo!
          geno.footer_text = pref.footer + geno.footer_text
        elsif(spref.report_type == :prrt)
          geno.prrt_seq = seq
          projs << :prrt
          geno.rt_bad = true if(sample_state == 'failed')
          geno.pr_bad = true if(sample_state == 'failed')
          aa = seq.scan(/.../).map{|n|
            a = translate(n)
            res = ''
            if(a == [nil])
              res = '-'
            elsif(a.size > 2)
              res = 'X'
            elsif(a.size == 1)
              res = a.join('')
            else
              res = '[' + a.sort.join('/') + ']'
            end
            res
          }.join('')

          geno.front_page_seq = "Inferred Amino Acid Sequence:  " + aa #translate yo!
          geno.footer_text = pref.footer + geno.footer_text
        elsif(spref.report_type == :v3)
          geno.v3_seq = seq
          projs << :v3
          geno.v3_bad = true if(sample_state == 'failed')
          aa = seq.scan(/.../).map{|n|
            a = translate(n)
            res = ''
            if(a == [nil])
              res = '-'
            elsif(a.size > 2)
              res = 'X'
            elsif(a.size == 1)
              res = a.join('')
            else
              res = '[' + a.sort.join('/') + ']'
            end
            res
          }.join('')
          geno.front_page_seq = "Inferred Amino Acid Sequence:  " + aa #translate yo!
          geno.footer_text = pref.footer + geno.footer_text
        elsif(spref.report_type == :gp41)
          seq = rd.export_seq_no_inserts
          geno.gp41_seq = seq
          projs << :gp41
          geno.gp41_bad = true if(sample_state == 'failed')
          aa = seq.scan(/.../).map{|n|
            a = translate(n)
            res = ''
            if(a == [nil])
              res = '-'
            elsif(a.size > 2)
              res = 'X'
            elsif(a.size == 1)
              res = a.join('')
            else
              res = '[' + a.sort.join('/') + ']'
            end
            res
          }.join('')
          geno.front_page_seq = "Inferred Amino Acid Sequence:  " + aa #translate yo!
          geno.footer_text = pref.footer + geno.footer_text
		elsif(hcv_hash[key])
			projs << :hcv

			res = hcv_hash[key]
			#geno.hcv_seq = seq
			geno.hcv_region = res[:region]
			geno.hcv_geno = res[:genotype]
			geno.hcv_bad = true if(hcv_hash[key][:fail])
			geno.front_page_seq = nil
			geno.footer_text = pref.footer + "\nThe genotyping assay was developed and its performance characteristics determined by the testing laboratory. The sequence results were generated by the testing laboratory, and sequence interpretation performed via an automated service.  We cannot be held responsible for the quality, integrity and correctness of the sequence results, or for the correctness of the patient demographic data added to this report. For US clients, this report has not been cleared or approved by the U.S. Food and Drug Administration.  "

        elsif(false and [:hcv_ns3_1a, :hcv_ns5a_1a, :hcv_ns5b_1a].include?(spref.report_type)) #old, kill?
          region = {:hcv_ns3_1a => 'NS3', :hcv_ns5a_1a => 'NS5A', :hcv_ns5b_1a => 'NS5B'}[spref.report_type]
          seq = rd.export_seq_no_inserts
          geno.hcv_seq = seq
          geno.hcv_region = 'NS3'
          geno.hcv_geno = '1A'
          projs << :hcv
          geno.hcv_bad = true if(sample_state == 'failed' or hcv_hash[key][:fail])
          aa = seq.scan(/.../).map{|n|
            a = translate(n)
            res = ''
            if(a == [nil])
              res = '-'
            elsif(a.size > 2)
              res = 'X'
            elsif(a.size == 1)
              res = a.join('')
            else
              res = '[' + a.sort.join('/') + ']'
            end
            res
          }.join('')
          geno.front_page_seq = "Inferred Amino Acid Sequence:  " + aa #translate yo!
          geno.footer_text = pref.footer + geno.hcv_footer_text
        end

        geno.demo_sampid = key[0]
        geno.v3_fpr_cutoff = pref.v3_fpr_cutoff
        geno.header_text = pref.contact_header
        #geno.footer_text = pref.footer + geno.footer_text
        geno.format_hints << pref.report_language
        #geno.alg = pref.report_algorithm

        #Hmmm!  How does HCV fit in here?

        if(hcv_hash[key])
          geno.make_report(nil, nil, hcv_hash[key])
        elsif(virco_hash[key] == nil and !sierra_error)
          geno.make_report(sierra_hash[seq], nil)
        else
          geno.make_report(nil, virco_hash[key])
        end

        if(geno.hcv)
          s_hcv_drugs = geno.hcv[:drugs]
        end

        if(geno.sierra and geno.sierra.drugs and !sierra_error)
          s_nrti_drugs = geno.sierra.drugs.find_all{|d| d.cls == 'NRTI'}.sort{|a,b| a.code <=> b.code} if(s_nrti_drugs == [])
          s_nnrti_drugs = geno.sierra.drugs.find_all{|d| d.cls == 'NNRTI'}.sort{|a,b| a.code <=> b.code} if(s_nnrti_drugs == [])
          s_pi_drugs = geno.sierra.drugs.find_all{|d| d.cls == 'PI'}.sort{|a,b| a.code <=> b.code} if(s_pi_drugs == [])
          s_int_drugs = geno.sierra.drugs.find_all{|d| d.cls == 'INI'}.sort{|a,b| a.code <=> b.code} if(s_int_drugs == [])
        end
        if(geno.virco and geno.virco.drugs)
          s_nrti_drugs = geno.virco.drugs.find_all{|d| d.drug_class == 'NRTI'}.sort{|a,b| a.code <=> b.code} if(s_nrti_drugs == [])
          s_nnrti_drugs = geno.virco.drugs.find_all{|d| d.drug_class == 'NNRTI'}.sort{|a,b| a.code <=> b.code} if(s_nnrti_drugs == [])
          s_pi_drugs = geno.virco.drugs.find_all{|d| d.drug_class == 'PI'}.sort{|a,b| a.code <=> b.code} if(s_pi_drugs == [])
        end

        genos.push(geno) if((geno.sierra and geno.sierra.drugs and !sierra_error) or (geno.virco and geno.virco.drugs) or (geno.hcv))
        geno.save_pdf("#{$settings.root}/data/#{jid}/#{key[0].gsub(' ','_')}.pdf", pref.report_language)
        #genos.push(geno) if((geno.sierra and geno.sierra.drugs and !sierra_error) or (geno.virco and geno.virco.drugs) or (geno.hcv))
      rescue
        File.open("#{$settings.root}/data/#{jid}/#{key[0]}.error.txt", 'w') do |file|
          file.puts "Could not generate report:"
          file.puts $!.message
        end
        puts $!
        puts $!.backtrace
      end
    end

    if(sierra_error)
      File.open("#{$settings.root}/data/#{jid}/sierra_error.txt", 'w') do |file|
        file.puts "Could not retrieve stanford resistance calls.  The sierra system may be currently offline.  Please try to redownload at another time."
      end
    end

    #Generate a csv report
    File.open("#{$settings.root}/data/#{jid}/job_#{jid}_resistance_summary.csv", 'w') do |file|
      #draw header (using projs)
      str = "SAMPLE,STATUS,ALGORITHM"
      if(projs.include?(:prrt))
        str += ",PR_CLADE,RT_CLADE" if(!genos.any?(){|g| g.virco })
        str += "," + (s_nrti_drugs.map{|d| d.name.upcase } + s_nnrti_drugs.map{|d| d.name.upcase } + s_pi_drugs.map{|d| d.name.upcase } ).join(',')

      end
      if(projs.include?(:integrase))
        str += ",INT_CLADE" if(!genos.any?(){|g| g.virco })
        str += "," + s_int_drugs.map{|d| d.name.upcase }.join(',')
      end
      if(projs.include?(:gp41))
        str += ",ENFUVIRTIDE"
      end
      if(projs.include?(:v3))
        str += ",TROPISM FPR,MARAVIROC"
      end
      if(projs.include?(:hcv))
        str += ",REGION,GENOTYPE," + s_hcv_drugs.sort{|a,b| a[:code] <=> b[:code]}.map{|d| d[:name].upcase }.join(',')
		str += ',MUTATIONS'
      end
      file.puts str

      #For each geno
      genos.sort{|a,b| a.demo_sampid <=> b.demo_sampid}.each do |geno|
        str = geno.demo_sampid
        #I guess if just rt/pr is submitted then INT goes bad, so make these semi-specific yo!
        str += ',' + (( ((geno.rt_bad or geno.pr_bad) and projs.include?(:prrt)) or
          (geno.int_bad and projs.include?(:integrase)) or
          (geno.hcv_bad and projs.include?(:hcv)) or
          (geno.gp41_bad and projs.include?(:gp41)) or (geno.v3_bad and projs.include?(:v3))) ? 'Fail' : 'Good' )
        str += ",#{geno.alg} #{geno.alg_version}"
        if(projs.include?(:prrt) and geno.virco)
          if(!geno.pr_bad)
            str += "," + (geno.virco.drugs.find_all{|d| d.drug_class == 'PI'}.sort{|a,b| a.code <=> b.code}).map{|d| {'S' => "Susceptible", 'I' => "Reduced Response", 'R' => "Resistant"}[d.interp] }.join(',')
          end
          if(!geno.rt_bad)
            str += "," + (geno.virco.drugs.find_all{|d| d.drug_class == 'NRTI'}.sort{|a,b| a.code <=> b.code}).map{|d| {'S' => "Susceptible", 'I' => "Reduced Response", 'R' => "Resistant"}[d.interp] }.join(',')
            str += "," + (geno.virco.drugs.find_all{|d| d.drug_class == 'NNRTI'}.sort{|a,b| a.code <=> b.code}).map{|d| {'S' => "Susceptible", 'I' => "Reduced Response", 'R' => "Resistant"}[d.interp] }.join(',')
          end
        elsif(projs.include?(:prrt) and !geno.virco)
          if(!geno.rt_bad and geno.sierra.rt_subtype)#:pr_subtype, :rt_subtype, :int_subtype
            str += "," + geno.sierra.rt_subtype
          else
            str += ","
          end
          if(!geno.pr_bad and geno.sierra.pr_subtype)
            str += "," + geno.sierra.pr_subtype
          else
            str += ","
          end

          if(!geno.rt_bad)
            str += "," + (geno.sierra.drugs.find_all{|d| d.cls == 'NRTI'}.sort{|a,b| a.code <=> b.code}).map{|d| d.res_text }.join(',')
            str += "," + (geno.sierra.drugs.find_all{|d| d.cls == 'NNRTI'}.sort{|a,b| a.code <=> b.code}).map{|d| d.res_text }.join(',')
          end
          if(!geno.pr_bad)
            str += "," + (geno.sierra.drugs.find_all{|d| d.cls == 'PI'}.sort{|a,b| a.code <=> b.code}).map{|d| d.res_text }.join(',')
          end
        end
        if(projs.include?(:integrase))
          if(!geno.int_bad and geno.sierra.int_subtype)#:pr_subtype, :rt_subtype, :int_subtype
            str += "," + geno.sierra.int_subtype
          else
            str += ","
          end
          if(!geno.int_bad)
            str += "," + (geno.sierra.drugs.find_all{|d| d.cls == 'INI'}.sort{|a,b| a.code <=> b.code}).map{|d| d.res_text }.join(',')
          end
        end
        if(projs.include?(:gp41))
          if(!geno.gp41_bad)
            str += ",#{geno.gp41_muts.size == 0 ? 'Susceptible' : 'Resistant'}"
          end
        end
        if(projs.include?(:v3))
          if(!geno.v3_bad)
            str += ",#{geno.v3_fpr},#{(geno.v3_fpr > geno.v3_fpr_cutoff ? 'Susceptible' : 'Not Susceptible')}"
          end
        end
        if(projs.include?(:hcv))
          if(!geno.hcv_bad)
			str += "," + geno.hcv_region + "," + geno.hcv_geno
            str += "," + (geno.hcv[:drugs].sort{|a,b| a[:code] <=> b[:code]}).map{|d| d[:interp] }.join(',')
			str += "," + geno.hcv[:mutations].map(){|a| a[0] + a[1].to_s + a[2].join('/')}.join(' ')
          end
        end
        file.puts str
      end
    end
  end


  # Deletes the temporary export files from a job folder
  # @param jobid => job id
  def WebTasks.delete_export_files(jobid)
    Dir["#{$settings.root}/data/#{jobid}/*.*"].each do |f|
      FileUtils.rm_f(f) if !(f=~ /xls$/) #only keep the job summary file
    end
  end

  # Archives export files
  # TODO: Option for archive type (!just zip)
  # @param jobid => job id
  # @param sid_arr => array of sids
  def WebTasks.archive(jobid, sid_arr=nil)
    # Determine the filename
    #filename = $ARCHIVE_PREFIX + jobid.to_s
    j=Job.get(jobid)
    #seqname = StandardPref.first(:id => j.standard_id).name
#      filename = $ARCHIVE_PREFIX + jobid.to_s + j.created_at.to_s
    #filename = $ARCHIVE_PREFIX + jobid.to_s + "-" + j.created_at.to_s + "-" + seqname
    filename = $ARCHIVE_PREFIX + jobid.to_s + "_" + j.name
    # Need to change directory because tar can't take paths with spaces in it


    FileUtils.cd("#{$settings.root}/data/#{jobid}/")  do
      #system("zip \"#{filename}.zip\" *.* -x *.zip", :chdir=>"#{$settings.root}/data/#{jobid}/")
      system("zip", "#{filename}.zip", *Dir['*.*'], '-x', '*.zip')
      #system("zip \"e.#{filename}.zip\" *.* -x *.pdf -x *.zip", :chdir=>"#{$settings.root}/data/#{jobid}/")
      system("zip", "e.#{filename}.zip", *Dir['*.*'], '-x', '*.pdf', '*.zip')
    end
  end

  # Retrieves the file in #{$settings.root}/config/recall/#{uid}.process which contains the current processing status
  # @param uid => user id
  def WebTasks.get_process_status(uid)
    return "DONE" if !File.exist?("#{$settings.root}/config/recall/#{uid}.process")
    file = File.new("#{$settings.root}/config/recall/#{uid}.process",'r')
	file.flock(File::LOCK_EX)
    status = file.gets
    file.close
    return status
  end

  # Retrieves the file in #{$settings.root}/config/recall/#{uid}.download which contains the current file download status
  # @param uid => user id
  def WebTasks.get_download_status(uid)
    return "DONE" if !File.exist?("#{$settings.root}/config/recall/#{uid}.download")
    file = File.new("#{$settings.root}/config/recall/#{uid}.download", 'r')
    status = file.gets
    file.close
    return status
  end

  # Updates the file in #{$settings.root}/config/recall/#{uid}.process with the current processing status
  # @param uid => user id
  # @param status => status description [string]
  def WebTasks.update_process_status(uid, status)
#	puts status
    file = File.new("#{$settings.root}/config/recall/#{uid}.process",'w')
	file.flock(File::LOCK_EX)
    file.puts status
    file.close
  end

  def WebTasks.get_error_message(uid) #and removes the file.
    return nil if !File.exist?("#{$settings.root}/config/recall/#{uid}.err")
    file = File.new("#{$settings.root}/config/recall/#{uid}.err", 'r')
    status = file.gets
    file.close
    FileUtils.rm("#{$settings.root}/config/recall/#{uid}.err")
    return status
  end

  def WebTasks.set_error_message(uid, status)
    file = File.new("#{$settings.root}/config/recall/#{uid}.err",'w')
    file.puts status
    file.close
  end


  # Updates the file in #{$settings.root}/config/recall/#{uid}.download with the current file download status
  # @param uid => user id
  # @param status => status description [string]
  def WebTasks.update_download_status(uid, status)
    file = File.new("#{$settings.root}/config/recall/#{uid}.download", 'w')
    file.puts status
    file.close
  end

  # Deletes the processing status file: #{$settings.root}/config/recall/#{uid}.process
  # @param uid => user id
  def WebTasks.delete_process_status(uid)
	FileUtils.rm("#{$settings.root}/config/recall/#{uid}.process")
  end

  # Deletes the download status file: #{$settings.root}/config/recall/#{uid}.download
  # @param uid => user id
  def WebTasks.delete_download_status(uid)
    FileUtils.rm("#{$settings.root}/config/recall/#{uid}.download")
  end

  #saves or updates the database record for a seqeunce
  # @param rd => recall data object
  # @param jobid => job id
  # @param userid => user id
  def WebTasks.save_db(rd, jobid, userid, name)
    #Make sure this updates appropriately.
    begin #Save seqeunce to the database
      job = Job.get(jobid)
      #first, check to see if it already exists
      seq = Sequence.first(:name => name, :job_id => jobid, :user_id => userid, :standard_id => job.standard_id) #This is where it died.
      if(!seq)
        seq = Sequence.new(:name => name, :job_id => jobid, :user_id => userid, :human_edits => rd.human_edits.size(), :mix_cnt => rd.mixture_cnt(), :n_cnt => rd.n_cnt(), :mark_cnt=> rd.mark_cnt(), :created_at => DateTime.now(), :nuc => rd.export_seq_no_inserts(), :standard_id => job.standard_id)
      else
        seq.human_edits = rd.human_edits.size()
        seq.mix_cnt = rd.mixture_cnt()
        seq.n_cnt = rd.n_cnt()
        seq.mark_cnt = rd.mark_cnt()
        seq.created_at = DateTime.now()
        seq.nuc = rd.export_seq_no_inserts()
      end
      if(!seq.save())
        raise seq.errors.to_a[0].to_s
      end
    rescue
      puts "Could not save recall data to database!"
      puts $!
      puts $!.backtrace
    end
  end


  # Saves chromatogram viewing data for a sample
  # @param rd => recall data object
  # @param jobid => job id
  # @param sampid => sample id
  # @param key_locs => key locations
  def WebTasks.save_chromatograms(rd, jobid, sampid, key_locs)
    outfile = File.new("#{$settings.root}/data/#{jobid}/#{sampid}/#{sampid}.chrom", 'w')
    offset = $OFFSET # no. of bases before and after standard that we would like to keep
    padding = ['-'] * offset # padding of '-'s before and after assembled and standard sequences
    start_dex = rd.start_dex
    end_dex = rd.end_dex

    aa_list = [] # amino acid sequence
    std_list = [] #standard AA
    insert_list = [] # indices of inserts
    # Translate nucletoides into amino acids
    # Ignore inserts that push sequence out of frame (i.e. inserts of size 1 or 2)
    std_seq = rd.standard
    nuc_seq = rd.assembled
    i = rd.start_dex.to_i
    dash_cnt = 0 # keeps track of dashes in a row

    # Extract amino acid positions from key_locs
    # original format => amino_acid_pos : amino_acids
    # final format => amino_acid_pos_1, amino_acid_pos_2...
    key_locs_list = []
    key_locs.split(',').each{|x|
      key_locs_list.push(x.split(':') [0])
    }

    # Amino acid translation
    while i < rd.end_dex.to_i
      nuc = []
      stdx = []
      ignore_insert = false # pretend that an insert does not exist?
      while (nuc.size<3 and nuc_seq[i])
        if std_seq[i] == '-'
          #insert detected
          dash_cnt += 1 #increment dash count
          insert_list.push(i-start_dex+offset) # add index to list of insert positions
          nuc = nuc_seq[i-2,3] if (dash_cnt == 3 and nuc.size==0) # complete codon set of inserts => set for translation
          stdx = std_seq[i-2,3] if (dash_cnt == 3 and nuc.size==0)
          ignore_insert = true if (dash_cnt == 1 and nuc.size == 0) # starting off with an insert in the codon, actually belongs to previous codon
        else
          #non-insert detected
          nuc += nuc_seq[i,1] # add current base to codon
          stdx += std_seq[i,1]
        end #if std_seq[i] == '-'
        i+=1
      end #while (nuc.size<3 and nuc_seq[i])

      # push a blank amino acid in if codon contains bad insert; otherwise, translate it
      if (dash_cnt > 0 and dash_cnt%3!=0 and !ignore_insert)
        aa_list.push("")
        std_list.push("")
      else
        aa = translate(nuc).flatten
        aa_list.push(aa.size > $MAX_AA_DISPLAYED ? "X" : aa.join('.'))
        aa = (stdx != [] ? translate(stdx).flatten : ['-'])
        std_list.push(aa.size > $MAX_AA_DISPLAYED ? "X" : aa.join('.'))
      end
      dash_cnt = 0 #reset dash count
    end

    # Output to file
    outfile.puts "marks_hash,#{rd.marks.map{|x| x-start_dex+offset}.join(',')}"
    outfile.puts "key_locs,#{key_locs_list.join(',')}"
    outfile.puts "assembled,#{(padding + rd.assembled[start_dex .. end_dex] + padding).join(',')}"
    outfile.puts "standard,#{(padding + rd.standard[start_dex .. end_dex] + padding).join(',')}"
    outfile.puts "inserts,#{insert_list.join(',')}"
    outfile.puts "amino_acid,#{aa_list.join(',')}"
    outfile.puts "std_aa,#{std_list.join(',')}"

    # Primers
    rd.primers.each do |p|
      p_start_dex = p.primer_start(false)
      p_end_dex = p.primer_end(false)
      next if p_start_dex >= end_dex or p_end_dex <= start_dex #Ignore this primer if it's out of range

=begin
      if(p.name == 'D')
        puts "*****DEBUG MODE ON, PRIMER D*********"

        puts "p_start_dex:    #{p_start_dex}"
        puts "p.primer_start: #{p.primer_start(true)}"
        puts "p.primer_start: #{p.primer_start(false)}"
        puts "p_end_dex:      #{p_end_dex}"
        puts "offset:         #{offset}"
        puts "start_dex:      #{start_dex}"
        puts p.edit[0 .. 20].join('')
        puts p.ignore[0 .. 20].join('')

        puts "*****DEBUG MODE OFF, PRIMER D*********"
      end
=end

      # Subsection of primer_loc that we should keep.  Do the same for primer_ignore.
      sub_loc = nil
      if (start_dex < offset and p_start_dex < start_dex)
        # 1) standard begins before buffer region ends and primer starts before standard -> pad with '-'
        spacer = ['-'] * (offset - start_dex)
        sub_loc = spacer + p.loc[0 .. end_dex + offset]
        sub_ignore = spacer + p.ignore[0 .. end_dex + offset]
      elsif (start_dex < offset)
        # 2) primer starts after standard, but standard begins before buffer -> pad with '-'
        sub_loc = padding + p.loc[start_dex .. end_dex + offset]
        sub_ignore = padding + p.ignore[start_dex .. end_dex + offset]
      else
        # 3) enough buffer space
        sub_loc = p.loc[start_dex-offset .. end_dex + offset]
        sub_ignore = p.ignore[start_dex-offset .. end_dex + offset]
      end

      # Re-index primer_loc (because it has been shortened, first non '-' location will be callibrated to 0)
      start_loc = end_loc = nil
      sub_loc.each{|x| (start_loc=x; break) if x!= '-'} # Find first trace location
      sub_loc.reverse_each{|x| (end_loc=x; break) if x!= '-'} # Find last trace location
      sub_loc.map!{|x| x=='-' ? x : x-start_loc} # Re-index

      outfile.puts "primer_name,#{p.primerid},#{p.name}"
      outfile.puts "primer_direction,#{p.primerid},#{p.direction}"
      outfile.puts "primer_start,#{p.primerid},#{p_start_dex-start_dex+offset}"
      outfile.puts "primer_end,#{p.primerid},#{p_end_dex-start_dex+offset}"
      outfile.puts "primer_loc,#{p.primerid},#{sub_loc.join(',')}"
      outfile.puts "primer_ignore,#{p.primerid},#{sub_ignore.join(',')}"

      # Primer chromatogram trace data
      scale = p.abi.class.to_s == "Abi" ? 14 : 20 #Could be ABI or SCF - set scale accordingly: Magic numbers!
      #Some SCF files are breaking here.  We need to rescale SCF's specifically.
      if(scale == 20) #scf
        scale = [p.abi.atrace[start_loc .. end_loc].max, p.abi.ctrace[start_loc .. end_loc].max,
          p.abi.gtrace[start_loc .. end_loc].max, p.abi.ttrace[start_loc .. end_loc].max].max / 92.0
      end

      trace = {}
      trace['atrace'] = p.abi.atrace[start_loc .. end_loc].map {|v| (v / scale).to_i}
      trace['ctrace'] = p.abi.ctrace[start_loc .. end_loc].map {|v| (v / scale).to_i}
      trace['gtrace'] = p.abi.gtrace[start_loc .. end_loc].map {|v| (v / scale).to_i}
      trace['ttrace'] = p.abi.ttrace[start_loc .. end_loc].map {|v| (v / scale).to_i}
      # Remove redundant points
      trace.each{|name, points|
        p_pnt = c_pnt = n_pnt = points[0]
        (1 ... points.size-1).each{|i|
          c_pnt = points[i] #current point
          n_pnt = points[i+1] #next point
          points[i] = '-1' if c_pnt == p_pnt and c_pnt == n_pnt # Remove point (by marking it with '-1') if previous and next points are the same
          p_pnt = c_pnt # previous point
        }
      }
      outfile.puts "primer_atrace,#{p.primerid},#{trace['atrace'].join(',')}"
      outfile.puts "primer_ctrace,#{p.primerid},#{trace['ctrace'].join(',')}"
      outfile.puts "primer_gtrace,#{p.primerid},#{trace['gtrace'].join(',')}"
      outfile.puts "primer_ttrace,#{p.primerid},#{trace['ttrace'].join(',')}"

      #DYEBLOBS
      dyeblob_list = []
      pattern_state = 0;
      pattern_prev = 0
      pattern_start = -1

      p.abi.atrace[start_loc .. end_loc].each_with_index do |val, i|
        if(pattern_state == 1 and val == (1 - pattern_prev))
          pattern_prev = val
        elsif(pattern_state == 1)
          pattern_state = 0
          dyeblob_list.push([pattern_start, i - 1] ) if( (i - pattern_start) > 7)
        elsif(val == 0 or val == 1)
          pattern_state = 1
          pattern_prev = val
          pattern_start = i
        end
      end

      if(pattern_state == 1)
        pattern_state = 0
        dyeblob_list.push([pattern_start, end_loc] ) if( (i - pattern_start) > 7)
      end


      #END DYEBLOBS
      outfile.puts "primer_dyeblob,#{p.primerid},#{dyeblob_list.map(){|a| "#{a[0]}-#{a[1]}" }.join(',')}"
    end
    outfile.close
  end

  # Rewrites the chromatogram file with updated assembled and protein sequences
  # @param assembled => assembled sequence (includes '-' padding)
  # @param protein => amino acid sequence
  # @param jobid => job id
  # @param sampid => sample id
  def WebTasks.update_chromatograms(assembled, protein, jobid, sampid)
    FileUtils.mv("#{$settings.root}/data/#{jobid}/#{sampid}/#{sampid}.chrom", "#{$settings.root}/data/#{jobid}/#{sampid}/#{sampid}.chrom_old") # Rename old file to make way for replacement
    infile_old = File.new("#{$settings.root}/data/#{jobid}/#{sampid}/#{sampid}.chrom_old", 'r') # Read from old file
    infile_new = File.new("#{$settings.root}/data/#{jobid}/#{sampid}/#{sampid}.chrom", 'w') # Make new file
    while(line = infile_old.gets)
      row = line.strip.split(',')
      if(row[0] == 'assembled')
        line = "assembled,#{assembled}"
      elsif(row[0] == 'amino_acid')
        line = "amino_acid,#{protein}"
      end
      infile_new.puts line
    end
    infile_new.close
    infile_old.close
    FileUtils.rm("#{$settings.root}/data/#{jobid}/#{sampid}/#{sampid}.chrom_old") # Delete old file
  end

  # Returns a hash of data for drawing chromatograms for a sample
  # @param jobid => job id
  # @param sampid => sample id
  # @param is_simple => is user using simple view mode? (boolean)
  def WebTasks.get_chromatograms(jobid, sampid, is_simple)
    infile = File.new("#{$settings.root}/data/#{jobid}/#{sampid}/#{sampid}.chrom", 'r')
    hash = Hash.new #hash of chromatogram info
    p_hash = nil #primer-level hash
    hash['primers'] = [] #Array of primer hashes

    while(line = infile.gets)
      row = line.strip.split(',')
      if(row[0] == 'marks_hash')
        hash['marks_hash'] = row[1 .. -1].map{|x| x.to_i}
      elsif(row[0] == 'key_locs')
        hash['key_locs'] = row[1 .. -1].map{|x| x.to_i}
      elsif(row[0] == 'assembled')
        hash['assembled'] = row[1 .. -1]
      elsif(row[0] == 'standard')
        hash['standard'] = row[1 .. -1]
      elsif(row[0] == 'inserts')
        hash['inserts'] = row[1 .. -1]
      elsif(row[0] == 'amino_acid')
        hash['amino_acid'] = row[1 .. -1]
      elsif(row[0] == 'std_aa')
        hash['std_aa'] = row[1 .. -1]
      elsif(row[0] == 'primer_name')
        p_hash = Hash.new
        p_hash['name'] = row[2]
      elsif(row[0] == 'primer_direction')
        p_hash['direction'] = row[2]
      elsif(row[0] == 'primer_start')
        p_hash['primer_start'] = row[2].to_i
      elsif(row[0] == 'primer_end')
        p_hash['primer_end'] = row[2].to_i
      elsif(!is_simple) # Full view
        if(row[0] == 'primer_loc')
          p_hash['loc'] = row[2 .. -1].map{|x| x.to_i}
        elsif(row[0] == 'primer_dyeblob')
          p_hash['dyeblobs'] = row[2 .. -1].map{|x| x.split('-').map(){|b| b.to_i } }
        elsif(row[0] == 'primer_ignore')
          p_hash['ignore'] = row[2 .. -1]
        elsif(row[0] == 'primer_atrace')
          p_hash['atrace'] = row[2 .. -1].map{|x| x.to_i}
        elsif(row[0] == 'primer_ctrace')
          p_hash['ctrace'] = row[2 .. -1].map{|x| x.to_i}
        elsif(row[0] == 'primer_gtrace')
          p_hash['gtrace'] = row[2 .. -1].map{|x| x.to_i}
        elsif(row[0] == 'primer_ttrace')
          p_hash['ttrace'] = row[2 .. -1].map{|x| x.to_i}
          hash['primers'].push(p_hash)
        end #if(row[0] == 'primer_loc')
      elsif(hash['marks_hash'].any?{|m| p_hash['primer_start'].upto(p_hash['primer_end']).include?(m)}) #Simple view with data points for at least one mark
        if(row[0] == 'primer_loc')
          p_hash['loc'] = row[2 .. -1]
        elsif(row[0] == 'primer_ignore')
          p_hash['ignore'] = row[2 .. -1]
          p_ignore = row[2 .. -1]
        elsif(row[0] == 'primer_dyeblob')
          p_hash['dyeblobs'] = row[2 .. -1].map{|x| x.split('-').map(){|b| b.to_i } }
        elsif(row[0] == 'primer_atrace')
          p_hash['atrace'] = row[2 .. -1].map{|x| x.to_i}
        elsif(row[0] == 'primer_ctrace')
          p_hash['ctrace'] = row[2 .. -1].map{|x| x.to_i}
        elsif(row[0] == 'primer_gtrace')
          p_hash['gtrace'] = row[2 .. -1].map{|x| x.to_i}
        elsif(row[0] == 'primer_ttrace')
          p_hash['ttrace'] = row[2 .. -1].map{|x| x.to_i}
          # Store up the original data before chopping it up
          p_loc = p_hash['loc']
          p_ignore = p_hash['ignore']
          p_atrace = p_hash['atrace']
          p_ctrace = p_hash['ctrace']
          p_gtrace = p_hash['gtrace']
          p_ttrace = p_hash['ttrace']
          # Reset the hash indices so we can store new stuff in there
          p_hash['loc'] = p_hash['ignore'] = p_hash['atrace'] = p_hash['ctrace'] = p_hash['gtrace'] = p_hash['ttrace'] = []
          # Cycle through each mark and chop all the data arrays, only keeping data related to the mark with a margin of OFFSET
          last_index = nil # Keep track of the last loc position listed as the indices build
          hash['marks_hash'].each{|x|
            # Add the loc indices.  Each set of indices start off where the last one ended (to minimize space).
            # If indices start off with a non-zero (or non '-') value, reindex the array so that we start from 0.
            curr_loc = p_loc[x-$OFFSET-1 .. x+$OFFSET+1]
            curr_first_loc = curr_loc.find{|y| y!='-'}
            if curr_first_loc and curr_first_loc!='0'
              if !last_index
                # Reindex necessary
                p_hash['loc'] += curr_loc.map{|y|  y!='-' ? y.to_i - curr_first_loc.to_i : y='-'}
              else
                # Indices already exist; start off from the last index
                diff = curr_first_loc.to_i - last_index - 1
                p_hash['loc'] += curr_loc.map{|y| y!='-' ? y.to_i - diff : y = '-'}
              end
            else
              # Keep as is
              p_hash['loc'] += curr_loc.map{|y| y!='-' ? y.to_i : y = '-'}
            end
            # Update last_index if possible
            last_index = p_hash['loc'].reverse.find{|y| y!='-'}
            # Ignore marks
            p_hash['ignore'] += p_ignore[x-$OFFSET-1 .. x+$OFFSET+1]
            # Trace
            start_loc = curr_loc.find{|y| y!='-'}.to_i
            end_loc = curr_loc.reverse.find{|y| y= '-'}.to_i
            if start_loc!=end_loc # It's not just dashes - add in the data points
              p_hash['atrace'] += p_atrace[start_loc .. end_loc]
              p_hash['ctrace'] += p_ctrace[start_loc .. end_loc]
              p_hash['gtrace'] += p_gtrace[start_loc .. end_loc]
              p_hash['ttrace'] += p_ttrace[start_loc .. end_loc]
            end
          }

          hash['primers'].push(p_hash)
        end #if(row[0] == 'primer_loc')
      end #if(row[0] == 'marks_hash')
    end #while(line = infile.gets)

    #if std_aa is missing, fill it in here:

    if(!hash['std_aa'])
      i = 0
      dash_cnt = 0
      std_list = []
      #puts hash['amino_acid'].inspect
      #puts hash['assembled'].join('')
      #puts hash['standard'].join('')
      skip = true
      while i < hash['assembled'].size - 1
        if(skip and hash['assembled'][i] == '-')
          i+=1
          next
        elsif(skip)
          skip = false
        end
        nuc = []
        stdx = []
        ignore_insert = false # pretend that an insert does not exist?
        while (nuc.size < 3 and hash['assembled'][i])
          if hash['standard'][i] == '-'
            #insert detected
            dash_cnt += 1 #increment dash count
            nuc = hash['assembled'][i-2,3] if (dash_cnt == 3 and nuc.size==0) # complete codon set of inserts => set for translation
            stdx = hash['standard'][i-2,3] if (dash_cnt == 3 and nuc.size==0)
            ignore_insert = true if (dash_cnt == 1 and nuc.size == 0) # starting off with an insert in the codon, actually belongs to previous codon
          else
            #non-insert detected
            nuc += hash['assembled'][i,1] # add current base to codon
            stdx += hash['standard'][i,1]
          end #if std_seq[i] == '-'
          i+=1
        end #while (nuc.size<3 and nuc_seq[i])
        # push a blank amino acid in if codon contains bad insert; otherwise, translate it
        if (dash_cnt > 0 and dash_cnt%3!=0 and !ignore_insert or stdx == [])
          std_list.push("")
        else
          aa = translate(stdx).flatten
          std_list.push(aa.size > $MAX_AA_DISPLAYED ? "X" : aa.join('.'))
        end
        dash_cnt = 0 #reset dash count
      end
      hash['std_aa'] = std_list
      #puts hash['std_aa'].inspect
    end

    infile.close

    return hash
  end

  # Calculates the quality score of a qual file
  # @param file => path to qual file
  def WebTasks.qual(file)
    f = File.new(file,'r')
    # The fasta description line contains information in the following order:
    # >[filename] [num_of_bases_in_seq] [first_good_base_pos] [num_of_good_bases] [file_type]
    desc = f.gets.strip.split(/\s+/).reverse
    start_pos = desc[2].to_i
    good_total = desc[1].to_i
    seq = "" #string of quality scores in file
    score = 0 #quality score total

    # Read in the sequence of quality scores
    while(line = f.gets)
      seq += line
    end
    f.close

    # Convert the scores to integers
    qual = seq.split(/\s+/).map{|x| x.to_i}
    # Calculate the quality score
    (start_pos).upto(start_pos+good_total-1){|x|
      score+=1 if qual[x]>$QUAL_SCORE
    }
    return score
  end

end
