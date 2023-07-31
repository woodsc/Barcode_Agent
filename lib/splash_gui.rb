=begin
splash_gui.rb
Copyright (c) 2007-2023 University of British Columbia

A GUI that asks for the users initials and provides any appropriate warnings.
=end

require 'lib/recall_config'
require 'lib/version'

#returns user initials
def splash_gui()
  #initials will be returned after the dialog exits.
  initials = ''
  #probably doesn't matter, but lets set it now in case it propagates.
  Gtk::Settings.default.gtk_dnd_drag_threshold = 100000

  #Gtk.init
  window = Gtk::Window.new

  #set up a dialog.
  dialog = Gtk::Dialog.new(title: "Barcode Agent - version #{$VERSION}",
    parent: window, #parent
    flags: :modal,
    buttons: [
      [Gtk::Stock::QUIT, :reject],
      [Gtk::Stock::OK, :ok]
    ])

  logo = Gtk::Image.new(file: "images/barcode_agent_logo.png")
  dialog.child.pack_start(logo, expand: false, fill: false, padding: 10)

  warnings = []

  #check if phred is available.
  phredloc = nil
  if(RUBY_PLATFORM =~ /(win|w)32$/ or RUBY_PLATFORM =~ /x64-mingw-ucrt$/)
    #phredloc = "./bin/phred.exe"
    phred_exe = Dir["bin/phred.exe"].first
    phred_exe = Dir["bin/phred_win32.exe"].first if(phred_exe.nil?)
    phred_exe = Dir["bin/workstation_phred.exe"].first if(phred_exe.nil?)
    phred_exe = Dir["bin/*phred*.exe"].first if(phred_exe.nil?)
    phredloc = phred_exe
  elsif(RUBY_PLATFORM =~ /x86_64-linux/)
    phredloc = "./bin/phred_linux_x86_64"
  elsif(RUBY_PLATFORM =~ /i686-darwin10/)
    phredloc = "./bin/phred_darwin"
  else #probably 32 bit linux
    phredloc = "./bin/phred_linux_i686"
  end

  if(!File.exist?(phredloc))
    warnings << "Phred not found!
    Recall will not be able to process files without phred,
    Phred can be obtained at http://www.phrap.com/phred/ .
    Phred needs to be placed at #{phredloc}.\n"
  end

  #run checksums
  warnings += checksum_warnings()

  warnings.each do |warning|
    label = Gtk::Label.new(warning)
    provider = Gtk::CssProvider.new
    provider.load(data: "* { color: red; }")
    label.style_context.add_provider(provider, GLib::MAXUINT)

    dialog.child.pack_start(label, :expand => false, :fill => false, :padding => 0)
  end

  dialog.child.pack_start(Gtk::Label.new("Please enter your user initials:"), :expand => false, :fill => false, :padding => 0)

  entry = Gtk::Entry.new
  dialog.child.pack_start(entry, :expand => false, :fill => false, :padding => 0)

  entry.signal_connect("activate") do
    dialog.response(Gtk::ResponseType::OK)
  end

  dialog.signal_connect("response") do |widget, response|
    case response
    when Gtk::ResponseType::OK
      initials = entry.text
    when Gtk::ResponseType::REJECT
      initials = nil
    end
    dialog.destroy()
  end
  dialog.show_all()

  #start the dialog, will block until dialog.destroy is called.
  dialog.run()

  return initials
end


#Check to see if the code checksum and config checksum are valid.
def checksum_warnings()
  warnings = []

  files = Dir[RecallConfig.dir + '*.txt']
  files.delete_if {|s| s =~ /user_/ }
  checksum = 0

  files.each do |file|
    i = 0
    File.open(file) do |f|
      i += 1
      f.each_byte {|b| checksum += ((i % 2 == 0) ? b : (256 - b)) }
    end
  end

  newchecksum = nil
  File.open(RecallConfig.dir + 'CHECKSUM') do |f|
    newchecksum = f.gets('\n').strip.to_i
  end

  if(newchecksum != checksum)
    puts "Checksums do not match"

    warnings << "Configuration file checksum failed!
    Configuration files have been changed without approval.
    Please check with the administrator before proceeding.\n"
  end

  #-------------code checksum
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

  newchecksum = nil
  File.open('./lib/CHECKSUM') do |f|
    newchecksum = f.gets('\n').strip.to_i
  end

  if(newchecksum != checksum)
    puts "Checksums do not match"
    warnings << "Code checksum failed!
      Code files have been changed without approval.
      Please check with the administrator before proceeding.\n"
  end

  return warnings
end
