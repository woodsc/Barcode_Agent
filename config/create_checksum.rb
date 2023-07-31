require 'optparse'

options = {}
OptionParser.new do |opts|
  opts.on("--auto", "Run in auto mode") do |a|
    options[:auto] = a
  end
end.parse!

if !options[:auto]
  puts "Creating the checksum, which is essentially approving changes to the configuration files.  Do NOT do this unless you know what you are doing."
  puts "Are you sure you want to do this (Y/N)?"
  yn = gets
  exit if(yn.strip.upcase != 'Y')
end


files = Dir['*.txt']
files.delete_if {|s| s =~ /user_/ }
checksum = 0
files.each do |file|
  i = 0
  File.open(file) do |f|
    i += 1
    f.each_byte {|b| checksum += ((i % 2 == 0) ? b : (256 - b)) }
  end
end

File.open('CHECKSUM','w') do |f|
    f.puts(checksum.to_s)
end

if !options[:auto]
  puts checksum
  puts "DONE"
  gets
end
