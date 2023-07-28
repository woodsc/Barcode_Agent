=begin
recall_data.rb
Copyright (c) 2007-2023 University of British Columbia

Loads/saves a r.ecall data file.

Notes:
This handles files of a .recall extension.  These files hold alignments and
information combined from quality data, sequence data, peak data, and
more, in an easy to read/manipulate/moveable format.  The only important
thing it doesn't contain are the actual chromatograms(those really should
be packaged along with it).

Handles IO and such as well.
=end

require 'forwardable'
require 'lib/poly'
require 'lib/primer_info'
require 'lib/standard_info'
require 'lib/qa_data'
require 'lib/conversions'

def escape_commas(str)
  str.gsub(",", "&#44;")
end

def unescape_commas(str)
  str.gsub("&#44;", ",")
end

class RecallData
	attr_accessor :sample, :primers, :standard, :assembled, :project
	attr_accessor :marks, :keylocmarks, :long_standard
  attr_accessor :phred_mix_perc, :nuc_mismatches
	attr_accessor :qa, :errors, :human_edits, :comments
	attr_accessor :aligned #boolean, true or false
  attr_accessor :recall_version, :recall_version_date
	attr_accessor :filename
  attr_accessor :abis

  extend SeqConversions

	def initialize(filename = nil, is_web = false)
		@sample = ''
		@project = ''
		@primers = []
		@standard = []
    @long_standard = []
		@assembled = []
		@human_calls = [] #Hmmm, How's this work.
		@marks = []
    @keylocmarks = []
		@qa = QaData.new()
		@aligned = false
		@human_edits = []
		@errors = []
    @phred_mix_perc = []
		@comments = ''
    @recall_version = ''
    @recall_version_date = ''

		if(filename)
			@filename = filename
			File.open(filename) do |file|
				p = nil
				file.each_line do |line|
					row = line.strip.split(',')
					if(row[0] == 'sample')
						@sample = unescape_commas(row[1])
						@project = row[2]
            @long_standard = StandardInfo.long_sequence(@project) if !is_web
						@aligned = row[3] == 'true' ? true : false
					elsif(row[0] == 'marks')
						@marks = row[2 .. -1].map{|v| v.to_i} if(row.size > 2)
          elsif(row[0] == 'keylocmarks')
						@keylocmarks = row[2 .. -1].map{|v| v.to_i} if(row.size > 2)
					elsif(row[0] == 'standard')
						@standard = row[2 .. -1]
					elsif(row[0] == 'assembled')
						@assembled = row[2 .. -1]
					elsif(row[0] == 'primer_data')
						p = RecallPrimer.new
						p.primerid = unescape_commas(row[1])
						p.orig_direction = row[2]
            p.direction = row[2]
            p.p_loc_max = row[3].to_i if(row[3] != nil)
            p.name = unescape_commas(row[4])
						@primers.push(p)
					elsif(row[0] == 'primer_edit')
						p.edit = row[2 .. -1]
					elsif(row[0] == 'primer_called')
						p.called = row[2 .. -1]
					elsif(row[0] == 'primer_uncalled')
						p.uncalled = row[2 .. -1]
					elsif(row[0] == 'primer_called_area')
						p.called_area = row[2 .. -1].map{|v| v.to_i}
					elsif(row[0] == 'primer_uncalled_area')
						p.uncalled_area = row[2 .. -1].map{|v| v.to_i}
					elsif(row[0] == 'primer_qual')
						p.qual = row[2 .. -1].map{|v| v.to_i}
					elsif(row[0] == 'primer_loc')
						p.loc = row[2 .. -1].map{|v| v.to_i}
					elsif(row[0] == 'primer_ignore')
						p.ignore = row[2 .. -1]
          elsif(row[0] == 'primer_amp_a')
						p.amp_a = row[2 .. -1].map{|v| v.to_i}
          elsif(row[0] == 'primer_amp_c')
						p.amp_c = row[2 .. -1].map{|v| v.to_i}
          elsif(row[0] == 'primer_amp_g')
						p.amp_g = row[2 .. -1].map{|v| v.to_i}
          elsif(row[0] == 'primer_amp_t')
						p.amp_t = row[2 .. -1].map{|v| v.to_i}
          elsif(row[0] == 'phred_mix_perc' and row.size > 2)
            @phred_mix_perc = row[2 .. -1].map{|v| foo = v.split(';');{'A' => foo[0].to_f, 'C' => foo[1].to_f, 'G' => foo[2].to_f, 'T' => foo[3].to_f} }
					elsif(row[0] == 'qa')
						@qa = QaData.new(row.join(','))
					elsif(row[0] == 'comments')
						@comments = row[1 .. -1].join(',')
					elsif(row[0] == 'human_edits')
						@human_edits = row[1 .. -1]
						@human_edits.map! {|a| a.split(/\:|\-\>/) }
          elsif(row[0] == 'nuc_mismatches')
						@nuc_mismatches = row[1].to_i
					elsif(row[0] == 'errors')
						@errors = row[1 .. -1]
          elsif(row[0] == 'recall_version')
            @recall_version = row[1]
          elsif(row[0] == 'recall_version_date')
            @recall_version_date = row[1]
					end
				end

			end
		end
	end

  #Moves the stop codon errors to the back.
  def sort_errors()
    tmp_errors = []

    @errors.each_with_index do |err, i|
      if(err =~ /^Stop codon at /)
        tmp_errors << err
        @errors[i] = ''
      end
    end

    @errors.delete('')
    @errors += tmp_errors
  end

	#saves the .recall file
	def save(filename = nil)
		filename = @filename if(filename == nil)
		normalize()
    sort_errors()
		File.open(filename,'w') do |file|
			file.puts "sample,#{escape_commas(@sample)},#{@project},#{@aligned.to_s}"
      file.puts "recall_version,#{@recall_version}"
      file.puts "recall_version_date,#{@recall_version_date}"
			file.puts "marks,," + @marks.join(',')
      file.puts "keylocmarks,," + @keylocmarks.join(',')
			file.puts "primer_list,#{@primers.map {|p| "#{escape_commas(p.primerid)},#{escape_commas(p.name)},#{p.orig_direction}"}.join(',')}"
			file.puts "mixture_cnt,#{mixture_cnt}"
			file.puts "n_cnt,#{n_cnt}"
			file.puts "mark_cnt,#{mark_cnt}"
      file.puts "nuc_mismatches,#{@nuc_mismatches}"
			file.puts "human_edit_cnt,#{human_edit_cnt}"
			file.puts "comments,#{@comments}"
			file.puts "errors,#{@errors.join(',')}"
			file.puts "human_edits,#{@human_edits.map{|v| v[0].to_s + ':' + v[1] + '->' + v[2]}.join(',')}"
			file.puts @qa.to_s
			file.puts
			file.puts "standard,," + @standard.join(',')
			file.puts "assembled,," + @assembled.join(',')
			file.puts
      file.puts "phred_mix_perc,," + @phred_mix_perc.map{|foo| (foo['A'] == [] or foo['A'] == nil) ? '' : sprintf("%.2f;%.2f;%.2f;%.2f", foo['A'], foo['C'], foo['G'], foo['T'])}.join(',')
      file.puts
			@primers.each do |p|
				esc_primerid = escape_commas(p.primerid)
				file.puts "primer_data,#{esc_primerid},#{p.orig_direction},#{p.p_loc_max},#{p.has_name? ? escape_commas(p.name) : '' }"
				file.puts "primer_edit,#{esc_primerid},#{p.edit.join(',')}"
				file.puts "primer_called,#{esc_primerid},#{p.called.join(',')}"
				file.puts "primer_uncalled,#{esc_primerid},#{p.uncalled.join(',')}"
				file.puts "primer_called_area,#{esc_primerid},#{p.called_area.join(',')}"
				file.puts "primer_uncalled_area,#{esc_primerid},#{p.uncalled_area.join(',')}"
				file.puts "primer_qual,#{esc_primerid},#{p.qual.join(',')}"
				file.puts "primer_loc,#{esc_primerid},#{p.loc.join(',')}"
				file.puts "primer_ignore,#{esc_primerid},#{p.ignore.join(',')}"
        file.puts "primer_amp_a,#{esc_primerid},#{p.amp_a.join(',')}"
        file.puts "primer_amp_c,#{esc_primerid},#{p.amp_c.join(',')}"
        file.puts "primer_amp_g,#{esc_primerid},#{p.amp_g.join(',')}"
        file.puts "primer_amp_t,#{esc_primerid},#{p.amp_t.join(',')}"
				file.puts
			end
		end
	end

  def add_human_edit(loc, orig, edit)
    origbase = @human_edits.find {|he| he[0].to_i == loc.to_i }
    @human_edits.delete_if {|he| he[0].to_i == loc.to_i}
    orig = origbase[1] if(origbase != nil)
    @human_edits.push([loc, orig, edit])
  end

  def get_suspicious_human_edits
    sus = []
    @human_edits.each do |he|
      loc = he[0].to_i
      hcall = he[2]
      bases = []
      primers.each do |p|
        bases.push p.called[loc]
        bases.push p.uncalled[loc]
      end
      bases.uniq!
      newbases = []

      @@ambig_nucs.each do |key, val|
        newbases.push(key) if(val.all? {|v| bases.include?(v) } or (val.find_all {|v| bases.include?(v)}.size == 2 and bases.size == 2))
      end

      sus.push(he) if(!newbases.include?(hcall))
    end
    return sus
  end

  def remind_errors
    return @errors.find_all do |err|
      !err.include?("Failing primer") and !err.include?("Stop codon")
    end
  end

	#load recall data from poly files
	def load_polys(polys, sampleid=nil) #Set sampleid manually if you so choose
		@aligned = false
    @sample = sampleid ? sampleid : polys[0].sampid

		polys.each do |poly|
      p = RecallPrimer.new
      dir = PrimerInfo.direction(poly.primerid)
      dir = PrimerInfo.direction_guess(poly, @standard) if(dir == nil)
      p.load_poly(poly, dir)
			@primers.push(p)
		end
	end

  #optional
  def add_abis(abis)
  #@abis = abis
    @primers.each do |p|
      #p.add_poly(polys.find {|a| a.primerid == p.primerid})
      p.add_abi(abis.find{|a| p.has_name? ? a.name == p.name : a.primerid == p.primerid})
    end
  end


	#Removes superfluous dashes and adds needed dashes to make things equal in size
	def normalize
		#get rid of extra dashes at the start
		del = -1
		offset = 0
		offset += 1 if(@standard != [])
		offset += 1 if(@assembled != [])
		return if(@primers.size == 0)

    #find out how many bases to remove at the start
		0.upto(@primers[0].edit.size - 1) do |i|
			cnt = 0
			@primers.each do |p|
				cnt += 1 if(p.edit[i] == '-')
			end
			cnt +=1 if(@standard != [] and @standard[i] == '-')
			cnt +=1 if(@assembled != [] and @assembled[i] == '-')
			if(cnt == @primers.size + offset)
				del = i
			else
				break
			end
		end

    #remove those extra bases at start
		if(del != -1)
			@primers.each do |p|
				p.called = p.called[del + 1 .. -1]
				p.uncalled = p.uncalled[del + 1 .. -1]
				p.called_area = p.called_area[del + 1 .. -1]
				p.uncalled_area = p.uncalled_area[del + 1 .. -1]
				p.loc = p.loc[del + 1 .. -1]
				p.qual = p.qual[del + 1 .. -1]
				p.ignore = p.ignore[del + 1 .. -1]
				p.edit = p.edit[del + 1 .. -1]
        p.amp_a = p.amp_a[del + 1 .. -1]
        p.amp_c = p.amp_c[del + 1 .. -1]
        p.amp_g = p.amp_g[del + 1 .. -1]
        p.amp_t = p.amp_t[del + 1 .. -1]
			end
			@standard = @standard[del + 1 .. -1] if(@standard != [])
			@assembled = @assembled[del + 1 .. -1] if(@assembled != [])
      @phred_mix_perc = @phred_mix_perc[del + 1 .. -1] if(@phred_mix_perc != [])
      @marks.map! {|m| m - (del + 1)}
      @keylocmarks.map! {|m| m - (del + 1)}

		end

		#add dashes at end to make everything the same length
		max = @primers.max {|a,b| a.edit.length <=> b.edit.length }.edit.length
		max = @standard.length if(@standard != [] and @standard.length > max)
		max = @assembled.length if(@assembled != [] and @assembled.length > max)

    #Add bases at the end
		@primers.each do |p|
			if(p.edit.size != max)
				tmp = ['-'] * (max - p.edit.size)
				p.called = p.called + tmp
				p.uncalled = p.uncalled + tmp
				p.called_area = p.called_area + tmp
				p.uncalled_area = p.uncalled_area + tmp
				p.loc = p.loc + tmp
				p.qual = p.qual + tmp
				p.ignore = p.ignore + tmp
				p.edit = p.edit + tmp
        p.amp_a = p.amp_a + tmp
        p.amp_c = p.amp_c + tmp
        p.amp_g = p.amp_g + tmp
        p.amp_t = p.amp_t + tmp
			end
		end
		@standard = @standard + (['-'] * (max - @standard.size)) if(@standard != [] and @standard.size != max)
		@assembled = @assembled + (['-'] * (max - @assembled.size)) if(@assembled != [] and @assembled.size != max)
		@phred_mix_perc = @phred_mix_perc  + ([{ }] * (max - @phred_mix_perc.size)) if(@phred_mix_perc != [] and @phred_mix_perc.size != max)
		#get rid of extra dashes at the end
		del = -1
		(max - 1).downto(0) do |i|
			cnt = 0
			@primers.each do |p|
				cnt += 1 if(p.edit[i] == '-')
			end
			cnt +=1 if(@standard != [] and @standard[i] == '-')
			cnt +=1 if(@assembled != [] and @assembled[i] == '-')
			if(cnt == @primers.size + offset)
				del = i
			else
				break
			end
		end

		if(del != -1)
			@primers.each do |p|
				p.called = p.called[0, del + 1]
				p.uncalled = p.uncalled[0, del + 1]
				p.called_area = p.called_area[0, del + 1]
				p.uncalled_area = p.uncalled_area[0, del + 1]
				p.loc = p.loc[0, del + 1]
				p.qual = p.qual[0, del + 1]
				p.ignore = p.ignore[0, del + 1]
				p.edit = p.edit[0, del + 1]
        p.amp_a = p.amp_a[0, del + 1]
        p.amp_c = p.amp_c[0, del + 1]
        p.amp_g = p.amp_g[0, del + 1]
        p.amp_t = p.amp_t[0, del + 1]
			end
			@standard = @standard[0, del + 1] if(@standard != [])
			@assembled = @assembled[0, del + 1] if(@assembled != [])
      @phred_mix_perc = @phred_mix_perc[0, del + 1] if(@phred_mix_perc != [])
		end
	end

  def remove_double_dashes
    end_dex().downto(start_dex()) do |i|
      if(@standard[i] == '-' and @assembled[i] == '-')
        #Increment the marks
        @marks.delete_if {|v| v == i }
        0.upto(@marks.size - 1) do |j|
          @marks[j] -= 1 if(@marks[j] > i)
        end

        @keylocmarks.delete_if {|v| v == i }
        0.upto(@keylocmarks.size - 1) do |j|
          @keylocmarks[j] -= 1 if(@keylocmarks[j] > i)
        end

        @standard.delete_at(i)
        @assembled.delete_at(i)
        @phred_mix_perc.delete_at(i)
        @primers.each do |p|
          p.called.delete_at(i)
          p.uncalled.delete_at(i)
          p.called_area.delete_at(i)
          p.uncalled_area.delete_at(i)
          p.loc.delete_at(i)
          p.qual.delete_at(i)
          p.ignore.delete_at(i)
          p.edit.delete_at(i)
          p.amp_a.delete_at(i)
          p.amp_c.delete_at(i)
          p.amp_g.delete_at(i)
          p.amp_t.delete_at(i)
        end
      end
    end
  end

	def export_seq
		txt = ''
		0.upto(@standard.length - 1) do |i|
			if(@assembled[i] != '-' or @standard[i] != '-')
				txt += @assembled[i]
			end
		end
		return txt
	end

  def export_seq_no_inserts
		txt = ''
		0.upto(@standard.length - 1) do |i|
			if(@standard[i] != '-')
				txt += @assembled[i]
			end
		end
		return txt
	end

	def start_dex
		s_first = 0
		0.upto(@standard.size - 1) do |i|
			if(@standard[i] != '-' or @assembled[i] != '-')
				s_first = i; break
			end
		end
		return s_first
	end

	def end_dex
		s_last = @standard.size - 1
		s_last.downto(0) do |i|
			if(@standard[i] != '-' or @assembled[i] != '-')
				s_last = i; break
			end
		end
		return s_last
	end

	#Example to_dex(0) # => 432
	def to_dex(i, cached=false)
		if(!cached or @cached_dex == nil)
			@cached_dex = Array.new
			0.upto(standard.length - 1) do |j|
				@cached_dex.push(j) if(assembled[j] != '-' or standard[j] != '-')
			end
		end
		return @cached_dex[i]
	end

	def get_dex_list(cached=false)
		if(!cached or @cached_dex == nil)
			@cached_dex = Array.new
			0.upto(standard.length - 1) do |j|
				@cached_dex.push(j) if(assembled[j] != '-' or standard[j] != '-')
			end
		end
		return @cached_dex
	end

	def get_dex_list_minus_inserts(cached=false)
		if(!cached or @cached_dex_minus_inserts == nil)
			@cached_dex_minus_inserts = Array.new
			0.upto(standard.length - 1) do |j|
				@cached_dex_minus_inserts.push(j) if(standard[j] != '-')
			end
		end
		return @cached_dex_minus_inserts
	end


  def get_dex_hash(cached=false)
		if(!cached or @cached_dex_hash == nil)
			@cached_dex_hash = Hash.new
      dex_list = get_dex_list(cached)
      dex_list.each_with_index do |v, j|
        @cached_dex_hash[v] = j
      end
    end
    return @cached_dex_hash
	end

  def get_dex_hash_minus_inserts(cached=false)
		if(!cached or @cached_dex_hash_minus_inserts == nil)
			@cached_dex_hash_minus_inserts = Hash.new
      dex_list = get_dex_list_minus_inserts(cached)
      dex_list.each_with_index do |v, j|
        @cached_dex_hash_minus_inserts[v] = j
      end
		end
		return @cached_dex_hash_minus_inserts
	end

  def get_marks_hash(cached = false)
    if(!cached or @cached_marks_hash == nil)
      @cached_marks_hash = Hash.new
      marks.each do |v|
        @cached_marks_hash[v] = true
      end
		end
		return @cached_marks_hash
  end

	# Retrieve list of inserts
	def get_inserts
		insert_arr = []
		0.upto(@standard.length - 1) do |i|
			insert_arr.push(i) if (@standard[i]=='-' and @assembled[i]!='-')
		end
		return insert_arr
	end

	def human_edit_cnt
    #Don't include things like C->C
    tmp = @human_edits.find_all {|a| a[1] != a[2]}
		return tmp.size
	end

	def mark_cnt
		return @marks.size
	end

	def n_cnt
		return @assembled.find_all {|a| a == 'N'}.size
	end

	def mixture_cnt
		return @assembled.find_all{|a| a =~ /[BDHVRYKMSWN]/}.size
	end

	def shift_assembled(pos, n)
		dex_list = get_dex_list(true) #possibly this should be false??
		pdone = []
		if(n < 0)
			while(n != 0)
				@assembled[dex_list[pos]] = @assembled[dex_list[pos - 1]]
				@assembled[dex_list[pos - 1]] = '-'
        @phred_mix_perc[dex_list[pos]] = @phred_mix_perc[dex_list[pos - 1]]
        @phred_mix_perc[dex_list[pos - 1]] = {}
				@primers.each do |p|
					if(p.called[dex_list[pos]] != '-' or pdone.include?(p.primerid))
						pdone.push(p.primerid) if(!pdone.include?(p.primerid))
						next
					else
						p.edit[dex_list[pos]] = p.edit[dex_list[pos - 1]]
						p.called[dex_list[pos]] = p.called[dex_list[pos - 1]]
						p.uncalled[dex_list[pos]] = p.uncalled[dex_list[pos - 1]]
						p.called_area[dex_list[pos]] = p.called_area[dex_list[pos - 1]]
						p.uncalled_area[dex_list[pos]] = p.uncalled_area[dex_list[pos - 1]]
						p.qual[dex_list[pos]] = p.qual[dex_list[pos - 1]]
						p.loc[dex_list[pos]] = p.loc[dex_list[pos - 1]]
						p.ignore[dex_list[pos]] = p.ignore[dex_list[pos - 1]]
            p.amp_a[dex_list[pos]] = p.amp_a[dex_list[pos - 1]]
            p.amp_g[dex_list[pos]] = p.amp_g[dex_list[pos - 1]]
            p.amp_t[dex_list[pos]] = p.amp_t[dex_list[pos - 1]]
            p.amp_c[dex_list[pos]] = p.amp_c[dex_list[pos - 1]]

						p.edit[dex_list[pos - 1]] = '-'
						p.called[dex_list[pos - 1]] = '-'
						p.uncalled[dex_list[pos - 1]] = '-'
						p.called_area[dex_list[pos - 1]] = '-'
						p.uncalled_area[dex_list[pos - 1]] = '-'
						p.qual[dex_list[pos - 1]] = '-'
						p.loc[dex_list[pos - 1]] = '-'
						p.ignore[dex_list[pos - 1]] = '-'
            p.amp_a[dex_list[pos - 1]] = '-'
            p.amp_c[dex_list[pos - 1]] = '-'
            p.amp_t[dex_list[pos - 1]] = '-'
            p.amp_g[dex_list[pos - 1]] = '-'
					end
				end
				n += 1
				pos -= 1
			end
		elsif(n > 0)
			while(n != 0)
				@assembled[dex_list[pos]] = @assembled[dex_list[pos + 1]]
				@assembled[dex_list[pos + 1]] = '-'
        @phred_mix_perc[dex_list[pos]] = @phred_mix_perc[dex_list[pos + 1]]
				@phred_mix_perc[dex_list[pos + 1]] = {}

				@primers.each do |p|
					if(p.called[dex_list[pos]] != '-' or pdone.include?(p.primerid))
						pdone.push(p.primerid) if(!pdone.include?(p.primerid))
						next
					else
						p.edit[dex_list[pos]] = p.edit[dex_list[pos + 1]]
						p.called[dex_list[pos]] = p.called[dex_list[pos + 1]]
						p.uncalled[dex_list[pos]] = p.uncalled[dex_list[pos + 1]]
						p.called_area[dex_list[pos]] = p.called_area[dex_list[pos + 1]]
						p.uncalled_area[dex_list[pos]] = p.uncalled_area[dex_list[pos + 1]]
						p.qual[dex_list[pos]] = p.qual[dex_list[pos + 1]]
						p.loc[dex_list[pos]] = p.loc[dex_list[pos + 1]]
						p.ignore[dex_list[pos]] = p.ignore[dex_list[pos + 1]]
            p.amp_a[dex_list[pos]] = p.amp_a[dex_list[pos + 1]]
            p.amp_c[dex_list[pos]] = p.amp_c[dex_list[pos + 1]]
            p.amp_g[dex_list[pos]] = p.amp_g[dex_list[pos + 1]]
            p.amp_t[dex_list[pos]] = p.amp_t[dex_list[pos + 1]]

						p.edit[dex_list[pos + 1]] = '-'
						p.called[dex_list[pos + 1]] = '-'
						p.uncalled[dex_list[pos + 1]] = '-'
						p.called_area[dex_list[pos + 1]] = '-'
						p.uncalled_area[dex_list[pos + 1]] = '-'
						p.qual[dex_list[pos + 1]] = '-'
						p.loc[dex_list[pos + 1]] = '-'
						p.ignore[dex_list[pos + 1]] = '-'
            p.amp_a[dex_list[pos + 1]] = '-'
            p.amp_t[dex_list[pos + 1]] = '-'
            p.amp_g[dex_list[pos + 1]] = '-'
            p.amp_c[dex_list[pos + 1]] = '-'
					end
				end

				n -= 1
				pos += 1
			end
		end
	end

end

#Represents a primer sequence(has quality, locations and sequences and stuff).
#This is supposed to make it so we don't need to load the poly file from
#scratch whenever we look at the sequence.

class RecallPrimer
	extend Forwardable
	attr_accessor :primerid, :orig_direction, :direction
	attr_accessor :called, :uncalled, :called_area, :uncalled_area
	attr_accessor :loc, :qual, :ignore, :edit, :fix_loc
  attr_accessor :amp_a, :amp_t, :amp_c, :amp_g
  attr_accessor :abi
  attr_accessor :poly, :p_loc_max, :name

	def_delegators("@edit", "clear", "[]","[]=", "length", "each", "index")

	def initialize()
    @name = ''
		@primerid = ''
		@called = []
		@uncalled = []
		@called_area = []
		@uncalled_area = []
		@loc = []
		@qual = []
		@ignore = [] #L for low qual, I for ignore?
		@orig_direction = nil
    @direction = nil
		@edit = []
    @amp_a = []
    @amp_c = []
    @amp_t = []
    @amp_g = []
    @abi = nil
    @fix_loc = nil
	end


  def name
    if(@name == nil or @name == '')
      return @primerid
    else
      return @name
    end
  end

  def has_name?
    return !(@name == nil or @name == '')
  end

  def amp(nuc, i)
    if(nuc == 'A')
      return @amp_a[i]
    elsif(nuc == 'C')
      return @amp_c[i]
    elsif(nuc == 'G')
      return @amp_g[i]
    elsif(nuc == 'T')
      return @amp_t[i]
    end
  end

  def amp_list(i)
    return [['A', @amp_a[i].to_f], ['C', @amp_c[i].to_f], ['G', @amp_g[i].to_f], ['T', @amp_t[i].to_f]].sort{|a,b| b[1] <=> a[1]}
  end

	def primer_start(cached = false)
		if(!cached or @primer_start_cached == nil)
			@primer_start_cached = @edit.index(@edit.find {|c| c != '-'})
      @primer_start_cached += 1 while(@ignore[@primer_start_cached] == 'L')
		end
		return @primer_start_cached
	end

    #Slow?
	def primer_end(cached = false)
		if(!cached or @primer_end_cached == nil)
			@primer_end_cached = @edit.rindex(@edit.reverse.find {|c| c != '-'})
      @primer_end_cached -= 1 while(@ignore[@primer_end_cached] == 'L')
		end
		return @primer_end_cached
	end


	#Loads primer data fresh from a poly file  (pass in primer id? and sample?)
	def load_poly(poly, direction)
		#grab all data from poly
    @name = poly.name
		@primerid = poly.primerid
		@orig_direction = direction
    @direction = direction
		poly.complement! if(@orig_direction == 'reverse')
		#stuff
		@qual = poly.quality.map {|a| a.to_i}
		@loc = poly.called_loc.map {|a| a.to_i}
		@called = poly.called_base
		@uncalled = poly.uncalled_base
		@called_area = poly.called_area.map {|a| a.to_i}
		@uncalled_area = poly.uncalled_area.map {|a| a.to_i}
		@edit = @called.to_a
    @amp_a = poly.amp_a.map {|a| a.to_i}
    @amp_c = poly.amp_c.map {|a| a.to_i}
    @amp_t = poly.amp_t.map {|a| a.to_i}
    @amp_g = poly.amp_g.map {|a| a.to_i}
		@ignore = Array.new(@called.size) { '-' }
    @p_loc_max = [poly.called_loc.map {|a| a.to_i}.max, poly.uncalled_loc.map {|a| a.to_i}.max].max
	end


  def add_abi(abi)
    @abi = abi
    if(@orig_direction == 'reverse')
      @abi.complement!
      offset = (@abi.atrace.size - @p_loc_max) - 2 #why minus 2 specifically?
      #puts "#{@primerid}:\ttrace(a:#{@abi.atrace.size} c:#{@abi.ctrace.size} g:#{@abi.gtrace.size} t:#{@abi.ttrace.size})  p_loc_max(#{@p_loc_max}) offset(#{offset})"
      offset = 0 if(offset < 0)

      #Cut off a bit so it lines up with the locs obtained from the poly file.
      @abi.atrace = @abi.atrace[offset .. -1]
      @abi.ctrace = @abi.ctrace[offset .. -1]
      @abi.gtrace = @abi.gtrace[offset .. -1]
      @abi.ttrace = @abi.ttrace[offset .. -1]
    end
  end

  def fallback_to_abi()
    #@name = po
    #I don't think this is actually going to work...  We need quality scores at least.
  end

end
