#deploy script for a ready to go Barcode_Agent download.

require '../lib/version.rb'
require 'tmpdir'
require 'fileutils'

#$VERSION $RELEASE_DATE

#create temp folder
dir = Dir.mktmpdir
FileUtils.mkdir("#{dir}/barcode_agent")

#Set up folders
FileUtils.mkdir("#{dir}/barcode_agent/bin")
FileUtils.mkdir("#{dir}/barcode_agent/config")
FileUtils.mkdir("#{dir}/barcode_agent/data")
FileUtils.mkdir("#{dir}/barcode_agent/data/approved")
FileUtils.mkdir("#{dir}/barcode_agent/data/logs")
FileUtils.mkdir("#{dir}/barcode_agent/data/svg_reports")
FileUtils.mkdir("#{dir}/barcode_agent/data/users")

#copy files
FileUtils.cp_r("../lib", "#{dir}/barcode_agent/lib")
FileUtils.cp_r("../images", "#{dir}/barcode_agent/images")

FileUtils.cp("../config/default.txt", "#{dir}/barcode_agent/config")
FileUtils.cp("../config/create_checksum.rb", "#{dir}/barcode_agent/config")
FileUtils.cp("../config/primers.txt", "#{dir}/barcode_agent/config")
FileUtils.cp("../config/standards.txt", "#{dir}/barcode_agent/config")
FileUtils.cp("../config/ulist.txt", "#{dir}/barcode_agent/config")
FileUtils.cp("../config/proj_co1.txt", "#{dir}/barcode_agent/config")
FileUtils.cp("../config/proj_co1_example1.txt", "#{dir}/barcode_agent/config")
FileUtils.cp("../config/proj_co1_example2.txt", "#{dir}/barcode_agent/config")
FileUtils.cp("../config/proj_co1_example3.txt", "#{dir}/barcode_agent/config")
FileUtils.cp("../config/proj_no_reference.txt", "#{dir}/barcode_agent/config")
FileUtils.cp("../config/proj_tufa_example.txt", "#{dir}/barcode_agent/config")

FileUtils.cp("../bin/alignment_ext-0.0.0.gem", "#{dir}/barcode_agent/bin")
FileUtils.cp("../bin/gzip.exe", "#{dir}/barcode_agent/bin")
FileUtils.cp("../bin/tar.exe", "#{dir}/barcode_agent/bin")
Dir.glob("../bin/*.dll") do |file|
  FileUtils.cp(file, "#{dir}/barcode_agent/bin")
end

Dir.glob("../*.rb") do |file|
  FileUtils.cp(file, "#{dir}/barcode_agent/")
end

FileUtils.cp("../terms_of_use.txt", "#{dir}/barcode_agent/")
FileUtils.cp("../README.md", "#{dir}/barcode_agent/")
FileUtils.cp("../phredpar.dat", "#{dir}/barcode_agent/")

#create checksums
FileUtils.cd("#{dir}/barcode_agent") do
  system("ruby create_code_checksum.rb")
end

FileUtils.cd("#{dir}/barcode_agent/config") do
  system("ruby create_checksum.rb")
end

#tar gz
#system("tar cvzf ../downloads/barcode_agent_v#{$VERSION}_#{$RELEASE_DATE}.tar.gz #{dir}")
FileUtils.cd("#{dir}") do
  system("pwd")
  system("ls")
  system("zip -r barcode_agent_v#{$VERSION}_#{$RELEASE_DATE}.zip barcode_agent/")
end
FileUtils.cp("#{dir}/barcode_agent_v#{$VERSION}_#{$RELEASE_DATE}.zip", "../downloads/")


#Remove temp folder.
puts dir
FileUtils.remove_entry_secure dir
