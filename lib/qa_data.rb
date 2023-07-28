=begin
qa_data.rb
Copyright (c) 2007-2023 University of British Columbia

Contains quality metrics for samples.
=end


require 'lib/recall_config'
require 'lib/primer_info'

class QaData
	attr_accessor :stop_codons, :bad_sequence, :manymixtures, :manyns
	attr_accessor :manymarks, :badqualsection, :manysinglecov
	attr_accessor :userunchecked, :userunviewed, :hasinserts
	attr_accessor :hasdeletions, :hasbaddeletions, :hasbadinserts
  attr_accessor :userfailed, :userexported, :autogood, :terrible
	attr_accessor :hasmarkedkeylocs, :suspicious, :failed

	def initialize(str = nil)
		@stop_codons = false
		@bad_sequence = false
		@manymixtures = false
		@manyns = false
		@manymarks= false
		@badqualsection = false
		@manysinglecov = false
		@userunchecked = true
		@userunviewed = true
    @userfailed = false
		@hasinserts = false
		@hasdeletions = false
    @hasbadinserts = false
		@hasbaddeletions = false
		@hasmarkedkeylocs = false
    @userexported = false
    @autogood = false
    @terrible = false

    @suspicous = false #Makes orange.
    @failed = false  #Makes red

		return if(str == nil)
		items = str.split(',')[1 .. -1]
		items.each do |a|
			a = a.split(':')
			self.send(a[0] + "=", a[1] == '1' ?  true : false )
		end
	end

	def all_good
		#return ![@userunchecked, @userfailed].any?
    #return (![@userunchecked, @userfailed].any?)
    return ((@autogood or !@userunchecked) and !@userfailed)
	end

  def mostly_good
    return ![@stop_codons, @bad_sequence, @manymixtures, @manyns,
    @manymarks, @badqualsection, @manysinglecov, @hasbadinserts, @hasbaddeletions, @userfailed, @terrible, @failed].any?
	end

  def is_terrible?
    return (@terrible and @userunchecked)
  end

	# Requires human revision if a specified key location is marked
	def needs_review
		return @hasmarkedkeylocs
	end

	def to_s()
		str = 'qa'
		str += ",stop_codons:#{@stop_codons ? 1 : 0 }"
		str += ",bad_sequence:#{@bad_sequence ? 1 : 0 }"
		str += ",manymixtures:#{@manymixtures ? 1 : 0 }"
		str += ",manyns:#{@manyns ? 1 : 0 }"
		str += ",manymarks:#{@manymarks ? 1 : 0 }"
		str += ",badqualsection:#{@badqualsection ? 1 : 0 }"
		str += ",manysinglecov:#{@manysinglecov ? 1 : 0 }"
		str += ",userunchecked:#{@userunchecked ? 1 : 0 }"
		str += ",userunviewed:#{@userunviewed ? 1 : 0 }"
    str += ",userfailed:#{@userfailed ? 1 : 0 }"
		str += ",hasdeletions:#{@hasdeletions ? 1 : 0 }"
		str += ",hasinserts:#{@hasinserts ? 1 : 0 }"
    str += ",hasbaddeletions:#{@hasbaddeletions ? 1 : 0 }"
		str += ",hasbadinserts:#{@hasbadinserts ? 1 : 0 }"
		str += ",hasmarkedkeylocs:#{@hasmarkedkeylocs ? 1 : 0}"
    str += ",userexported:#{@userexported ? 1 : 0}"
    str += ",suspicious:#{@suspicious ? 1 : 0}"
    str += ",failed:#{@failed ? 1 : 0}"
    str += ",autogood:#{@autogood ? 1 : 0}"
    str += ",terrible:#{@terrible ? 1 : 0}"
		return str
	end

end
