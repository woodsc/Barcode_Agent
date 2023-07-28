#Still testing.

#install our alignment gem.
system("gem install --local bin/alignment_ext-0.0.0.gem")

#seems to work.
system("ridk exec pacman -Syu --noconfirm")
system("ridk exec pacman -S mingw-w64-x86_64-gtk3 --noconfirm")
system("gem install gtk3")
