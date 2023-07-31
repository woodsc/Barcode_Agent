require 'fileutils'

#updating msys/gems I think
system("ridk exec pacman -Syu --noconfirm")
system("ridk exec pacman -S mingw-w64-x86_64-gtk3 --noconfirm")

#install our alignment gem.
FileUtils.cd("bin/") do
  system("gem install --local alignment_ext-1.0.0.gem")
end

#Installing gtk3
system("gem install gtk3")

#running checksums
system("ruby create_code_checksum.rb --auto")

FileUtils.cd("config/") do
  system("ruby create_checksum.rb --auto")
end

puts "Windows setup finished"
STDIN.gets
