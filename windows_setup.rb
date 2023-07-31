#Still testing.

#install our alignment gem.
FileUtils.cd("bin/") do
  system("gem install --local alignment_ext-0.0.0.gem")
end


#seems to work.
system("ridk exec pacman -Syu --noconfirm")
system("ridk exec pacman -S mingw-w64-x86_64-gtk3 --noconfirm")
system("gem install gtk3")
