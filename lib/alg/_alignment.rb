=begin
_alignment.rb
Copyright (c) 2007-2023 University of British Columbia

Loads the appropriate alignment library for the current platform.
=end
load_dir = File.dirname(__FILE__)

#puts RUBY_PLATFORM

if(RUBY_PLATFORM =~ /mswin|(win|w)32|cygwin|mingw/)
	if(RUBY_VERSION =~ /^2\.1/)
		require "#{load_dir}/alignment.windows.r21.so"
	elsif(RUBY_VERSION =~ /^2\.2/)
		require "#{load_dir}/alignment.windows.r22.so"
	elsif(RUBY_PLATFORM =~ /ucrt/)
		require 'alignment_ext'
	else
		require 'alignment_ext'
	end
=begin
  if(RUBY_VERSION =~ /^2\.1/)
    require "#{load_dir}/alignment.windows.r21.so"
  elsif(RUBY_VERSION =~ /^2\.[23456789]/)
    require "#{load_dir}/alignment.windows.r22.so"
  elsif(RUBY_VERSION =~ /^3\.[123456789]/)
    require "#{load_dir}/alignment.windows.r22.so"
  else
    require "#{load_dir}/alignment.windows.so"
  end
=end
elsif(RUBY_PLATFORM =~ /x86_64-linux/)
  if(RUBY_VERSION =~ /^2\.[23456789]/)
    require "#{load_dir}/alignment.linux64.r2.so"
  elsif(RUBY_VERSION =~ /^3\.[123456789]/)
    require "#{load_dir}/alignment.linux64.r2.so"
  else
    require "#{load_dir}/alignment.linux64.so"
  end
elsif(RUBY_PLATFORM =~ /i686-darwin10/)
    require "#{load_dir}/alignment.macosx.so"
else
	puts "Unknown platform #{RUBY_PLATFORM}, defaulting to linux"
  if(RUBY_VERSION =~ /^2\.[23456789]/)
    require "#{load_dir}/alignment.linux32.r2.so"
  elsif(RUBY_VERSION =~ /^3\.[123456789]/)
    require "#{load_dir}/alignment.linux32.r2.so"
  else
    require "#{load_dir}/alignment.linux32.so"
  end
end
