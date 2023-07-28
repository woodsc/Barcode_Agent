#deploy script for a ready to go Barcode_Agent download.

require '../lib/version.rb'
require 'tmpdir'
require 'fileutils'

#$VERSION $RELEASE_DATE

#create temp folder
dir = Dir.mktmpdir

#Set up folders
FileUtils.mkdir("#{dir}/bin")
FileUtils.mkdir("#{dir}/config")
FileUtils.mkdir("#{dir}/data")
FileUtils.mkdir("#{dir}/data/approved")
FileUtils.mkdir("#{dir}/data/logs")
FileUtils.mkdir("#{dir}/data/svg_reports")
FileUtils.mkdir("#{dir}/data/users")

#copy files
FileUtils.cp_r("../lib", "#{dir}/lib")
FileUtils.cp_r("../images", "#{dir}/images")

FileUtils.cp("../config/default.txt", "#{dir}/config")
FileUtils.cp("../config/create_checksum.rb", "#{dir}/config")
FileUtils.cp("../config/primers.txt", "#{dir}/config")
FileUtils.cp("../config/standards.txt", "#{dir}/config")
FileUtils.cp("../config/ulist.txt", "#{dir}/config")
FileUtils.cp("../config/proj_co1.txt", "#{dir}/config")
FileUtils.cp("../config/proj_co1_example1.txt", "#{dir}/config")
FileUtils.cp("../config/proj_co1_example2.txt", "#{dir}/config")
FileUtils.cp("../config/proj_co1_example3.txt", "#{dir}/config")
FileUtils.cp("../config/proj_no_reference.txt", "#{dir}/config")
FileUtils.cp("../config/proj_tufa_example.txt", "#{dir}/config")

FileUtils.cp("../bin/alignment_ext-0.0.0.gem", "#{dir}/bin")
FileUtils.cp("../bin/gzip.exe", "#{dir}/bin")
FileUtils.cp("../bin/tar.exe", "#{dir}/bin")
Dir.glob("../bin/*.dll") do |file|
  FileUtils.cp(file, "#{dir}/bin")
end

Dir.glob("../*.rb") do |file|
  FileUtils.cp(file, "#{dir}/")
end

FileUtils.cp("../terms_of_use.txt", "#{dir}/")
FileUtils.cp("../README.md", "#{dir}/")
FileUtils.cp("../phredpar.dat", "#{dir}/")

#create checksums
FileUtils.cd(dir) do
  system("ruby create_code_checksum.rb")
end

FileUtils.cd("#{dir}/config") do
  system("ruby create_checksum.rb")
end

#tar gz
system("tar cvzf ../downloads/barcode_agent_v#{$VERSION}_#{$RELEASE_DATE}.tar.gz #{dir}")


#Remove temp folder.
puts dir
FileUtils.remove_entry_secure dir
