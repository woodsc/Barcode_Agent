puts "Creating the checksum, which is essentially approving changes to the configuration files.  Do NOT do this unless you know what you are doing."
puts "Are you sure you want to do this (Y/N)?"
yn = gets
exit if(yn.strip.upcase != 'Y')

files = Dir['./lib/**/*.rb'] + Dir['./lib/*.rb']
files.uniq!
checksum = 0

files.each do |file|
  i = 0
  File.open(file) do |f|
    i += 1
    f.each_byte {|b| checksum += ((i % 2 == 0) ? b : (256 - b)) }
  end
end

File.open('./lib/CHECKSUM','w') do |f|
    f.puts(checksum.to_s)
end
puts checksum
puts "DONE"
gets