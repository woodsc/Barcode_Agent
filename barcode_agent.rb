=begin
barcode_agent.rb
Copyright (c) 2007-2023 University of British Columbia

Barcode Agent main code
=end

puts "Loading..."


$: <<  '.'

require 'gtk3'
require 'lib/recall_config'
require 'lib/abi'
require 'lib/poly'
require 'lib/sequence'
require 'lib/recall_data'
require 'lib/standard_info'
require 'lib/primer_info'
require 'lib/gui'
require 'lib/splash_gui'
require 'lib/manager'
require 'lib/tasks'
require 'lib/project_methods'
require 'lib/alg/aligner'
require 'lib/alg/primer_fixer'
require 'lib/alg/base_caller'
require 'lib/alg/quality_checker'
require 'lib/alg/insert_detector'
require 'lib/addons/svg_export/svg_export.rb'


RecallConfig.load('./config/')

user = splash_gui()
exit() if(user.nil? or user.strip() == '')

RecallConfig.set_context(nil, user)
PrimerInfo.Load("./config/primers.txt")
StandardInfo.Load("./config/standards.txt")
mgr = Manager.new("./data/", user)
mgr.refresh

gui = Gui.new(mgr, user)
gui.refresh
gui.run
puts "Done"
