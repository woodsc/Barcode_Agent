=begin
recall_info.rb
Copyright (c) 2007-2023 University of British Columbia

Loads a partial .recall data file.

Notes:
This is a mini-version of the full .recall data file.  It just does a partial load
of the data.
=end


require 'lib/primer_info'
require 'lib/qa_data'

def escape_commas(str)
  return nil if(str.nil?)
  return str.gsub(",", "&#44;")
end

def unescape_commas(str)
  return nil if(str.nil?)
  return str.gsub("&#44;", ",")
end

class RecallInfo
	attr_accessor :sample, :primers, :project
	attr_accessor :marks
	attr_accessor :qa, :errors, :human_edits, :comments
  attr_accessor :n_cnt, :mark_cnt, :mixture_cnt, :human_edit_cnt
	attr_accessor :aligned #boolean, true or false
  attr_accessor :recall_version, :recall_version_date
	attr_accessor :read_time, :standard, :assembled

	def initialize(filename = nil)
		@sample = ''
		@project = ''
		@primers = []
		@standard = []
		@assembled = []
		@human_calls = [] #Hmmm, How's this work.
		@marks = []
		@qa = QaData.new()
		@aligned = false
		@human_edits = []
		@errors = []
		@comments = ''
    @mark_cnt = ''
    @mixture_cnt = ''
    @human_edit_cnt = ''
    @n_cnt = ''
    @recall_version = ''
    @recall_version_date = ''

		if(filename)
			File.open(filename) do |file|
				p = nil
				file.each_line do |line|
					row = line
					row = line.strip
					row = row.split(',')
					if(row[0] == 'sample')
						@sample = unescape_commas(row[1])
						@project = row[2]
						@aligned = row[3] == 'true' ? true : false
#					elsif(row[0] == 'marks')
#						@marks = row[2 .. -1].map{|v| v.to_i} if(row.size > 2)
					elsif(row[0] == 'standard')
						@standard = row[2 .. -1]
					elsif(row[0] == 'assembled')
						@assembled = row[2 .. -1]
          elsif(row[0] == 'mixture_cnt')
            @mixture_cnt = row[1]
          elsif(row[0] == 'n_cnt')
            @n_cnt = row[1]
          elsif(row[0] == 'mark_cnt')
            @mark_cnt = row[1]
          elsif(row[0] == 'recall_version')
            @recall_version = row[1]
          elsif(row[0] == 'recall_version_date')
            @recall_version_date = row[1]
          elsif(row[0] == 'human_edit_cnt')
            @human_edit_cnt = row[1]
          elsif(row[0] == 'primer_list') #doesn't work right yet.
            ps = row[1 .. -1]

            ps.each_slice(3) do |slice|
              p = []
              p.push(unescape_commas(slice[0])) #primerid
              p.push(unescape_commas(slice[1])) #primer name
              p.push(slice[2]) #direction
              @primers.push(p)
            end
					elsif(row[0] == 'primer_data')
						break #cut out early so we don't have to load rest of file.
#						p = []
#						p.push(row[1])
#						p.push(row[2])
#						@primers.push(p)
#					elsif(row[0] == 'primer_edit')
#						p.edit = row[2 .. -1]
#					elsif(row[0] == 'primer_called')
#						p.called = row[2 .. -1]
#					elsif(row[0] == 'primer_uncalled')
#						p.uncalled = row[2 .. -1]
#					elsif(row[0] == 'primer_called_area')
#						p.called_area = row[2 .. -1].map{|v| v.to_f}
#					elsif(row[0] == 'primer_uncalled_area')
#						p.uncalled_area = row[2 .. -1].map{|v| v.to_f}
#					elsif(row[0] == 'primer_qual')
#						p.qual = row[2 .. -1].map{|v| v.to_i}
#					elsif(row[0] == 'primer_loc')
#						p.loc = row[2 .. -1].map{|v| v.to_i}
#					elsif(row[0] == 'primer_ignore')
#						p.ignore = row[2 .. -1]
					elsif(row[0] == 'qa')
						@qa = QaData.new(row.join(','))
					elsif(row[0] == 'comments')
						@comments = row[1 .. -1].join(',')
					elsif(row[0] == 'human_edits')
						@human_edits = row[1 .. -1]
						@human_edits.map! {|a| a.split(/\:|\-\>/) }
					elsif(row[0] == 'errors')
						@errors = row[1 .. -1]
					end
				end

			end
		end
		@read_time = File.mtime(filename)
	end

	def export_seq
		txt = ''
		0.upto(@standard.length - 1) do |i|
			if(@assembled[i] != '-' or @standard[i] != '-')
        if(RecallConfig['common.export_edits_lowercase'] == 'true' and (@human_edits.map{|a| a[0].to_i}).include?(i))
          txt += @assembled[i].downcase
        else
          txt += @assembled[i]
        end
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


end
