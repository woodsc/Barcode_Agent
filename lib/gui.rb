=begin
gui.rb
Copyright (c) 2007-2023 University of British Columbia

Barcode Agent GUI
=end

require 'lib/tasks'
require 'lib/manager'
require 'lib/recall_config'
require 'lib/primer_info'
require 'lib/recall_data'

require 'lib/gui/finisher'
require 'lib/gui/gui_config'
require 'lib/utils.rb'

require 'gtk3'

require 'lib/alg/aligner'
require 'lib/alg/primer_fixer'
require 'lib/alg/base_caller'
require 'lib/alg/quality_checker'
require 'lib/alg/insert_detector'

$mutex = Mutex.new

=begin
if(RUBY_VERSION =~ /^1\.8/)
  def Thread.exclusive
    Thread.critical=true
    yield
    Thread.critical=false
  end
end
=end

class Gtk::Statusbar
    def set_text(str)
        self.pop(0)
        self.push(0, str)
    end
end

class Time
	def to_s
		return strftime('%d-%b-%Y,  %I:%M %p')
	end
end

class Gtk::ListStore
	include Enumerable
end

class Gui
	attr_accessor :mgr, :tasks, :user
	attr_accessor :window
	attr_accessor :current_sample, :current_primer, :current_label
	attr_accessor :primer_box, :primer_model
	attr_accessor :sample_box, :sample_model
	attr_accessor :label_box, :label_model
	attr_accessor :button_bar, :status_bar, :progress_bar, :info_box

	#Runs the GUI
	def initialize(mgr, usr)
    Gtk::Settings.default.gtk_dnd_drag_threshold = 100000

    @debug = false
    @add_samples_dir = RecallConfig['common.add_samples_dir']
    @export_dir = RecallConfig['common.export_dir']
    @gui_config = GuiConfig.new
    @mgr = mgr
    @tasks = Tasks.new(@mgr)
		@user = usr
		@current_sample = nil
		@current_primer = nil
		@current_label = nil

		@window = Gtk::Window.new

		@window.set_title("Barcode Agent - Sample Manager")
		@window.set_default_size(1000, 550)

		t_render = Gtk::CellRendererText.new
    st_render = Gtk::CellRendererText.new
    e_render = Gtk::CellRendererText.new
    e_render.editable=true

		#Name, Direction
		@primer_model = Gtk::ListStore.new(String, String, String)
		@primer_box = Gtk::TreeView.new(@primer_model)
		columns = [
			Gtk::TreeViewColumn.new("Primer", t_render, :text => 0),
			Gtk::TreeViewColumn.new("Direction", t_render, :text => 1),
      Gtk::TreeViewColumn.new("Name", t_render, :text => 2),
		]
		columns.each_with_index do |col, i|
			col.sort_column_id = i
			@primer_box.append_column(col)
		end

		#Name, moddate
		@label_model = Gtk::ListStore.new(String, String, Integer, String)
		@label_box = Gtk::TreeView.new(@label_model)

		columns = [
			[Gtk::TreeViewColumn.new("Sample Batch", t_render, :text => 0, :cell_background => 3), 0],
			[Gtk::TreeViewColumn.new("Modification Date", t_render, :text => 1, :cell_background => 3), 2]
		]

		columns.each_with_index do |col, i|
			col[0].sort_column_id = col[1]
			@label_box.append_column(col[0])
		end
		@label_model.set_sort_column_id(2, :descending)

    @set_button_box = Gtk::Box.new(:horizontal, 1)
  	@exportapproved_button = Gtk::Button.new(label: 'Approve and Export')
    @set_button_box.pack_start(@exportapproved_button)
    @set_button_box.pack_start(Gtk::Label.new(''))
    @set_button_box.pack_start(Gtk::Label.new(''))

    @exportapproved_button.signal_connect("clicked") do |args|
			#bp_approve(args) #Special extra approve
			bp_export(args, true)
		end

    #sample_model_block temporarily prevents @sample_models signals from doing anything to prevent strange behaviour during refresh()
    @sample_model_block = false
		@sample_model = Gtk::ListStore.new(GLib::Type::STRING, GLib::Type::STRING, GLib::Type::STRING, GLib::Type::STRING, GLib::Type::STRING, GLib::Type::STRING, GLib::Type::STRING)
		@sample_box = Gtk::TreeView.new(@sample_model)

		columns = [
			Gtk::TreeViewColumn.new("Sample", st_render, :text => 0, :cell_background => 4, :foreground => 5),
			Gtk::TreeViewColumn.new("Project", st_render, :text => 1) ,
      Gtk::TreeViewColumn.new("?", st_render, :text => 6),
			Gtk::TreeViewColumn.new("Comments", e_render, :text => 3)
		]
		columns.each_with_index do |col, i|
			col.sort_column_id = i if(i != 2)
			@sample_box.append_column(col)
		end

    @sample_model.set_sort_func(0){|a, b| a[0] == b[0] ? a[1] <=> b[1] : a[0] <=> b[0] } #works!
    @sample_model.set_sort_func(1){|a, b| a[1] == b[1] ? a[0] <=> b[0] : a[1] <=> b[1] }
    @sample_box.set_size_request(350, -1)

		@button_bar = Gtk::Toolbar.new()

    @add_samples_button = Gtk::ToolButton.new(:label => "Add Samples")
    @add_samples_button.signal_connect("clicked") {|args| bp_add_samples(args)}

    @change_project_button = Gtk::ToolButton.new(:label => "Change Projects")
    @change_project_button.signal_connect("clicked") {|args| bp_change_projects(args) }

		@delete_sample_button = Gtk::ToolButton.new(label: "Delete Sample")
    @delete_sample_button.signal_connect("clicked") do |args|
      pcd = Gtk::Dialog.new(
        title: "Are you sure?",
        parent: @window,
        flags: [:destroy_with_parent],
        buttons: [['Yes delete this sample', 0], ["No, not really", 1]])

      pcd.child.add(Gtk::Label.new("Are you sure you want to delete this sample?"))
      pcd.show_all
      response = pcd.run
      pcd.destroy
      if(response == 0)
        threaded do
          @tasks.delete_sample(@current_label, @current_sample)
          @current_primer = nil
          @current_sample = nil
          @mgr.refresh
          refresh
        end
      end
		end

    @button_bar.insert(@add_samples_button, -1)
    @button_bar.insert(Gtk::SeparatorToolItem.new, -1)
    @button_bar.insert(@change_project_button, -1)
    @button_bar.insert(Gtk::SeparatorToolItem.new, -1)
    @button_bar.insert(@delete_sample_button, -1)
		@button_bar.insert(Gtk::SeparatorToolItem.new, -1)

    research_menu = Gtk::MenuBar.new
    @rmen = Gtk::MenuItem.new(label: "Research only")
    @rmen.submenu = Gtk::Menu.new
    research_menu.insert(@rmen, -1)

    @menu_export = Gtk::MenuItem.new(label: "Export")
    @menu_realign = Gtk::MenuItem.new(label: "Realign")
    @menu_deleteset = Gtk::MenuItem.new(label: "Delete Batch")

    @rmen.submenu.insert(@menu_export, -1)
    @rmen.submenu.insert(@menu_realign, -1)
    @rmen.submenu.insert(@menu_deleteset, -1)

    @menu_export.signal_connect("activate") {|args|  bp_export(args) }
    @menu_realign.signal_connect("activate") {|args| bp_realign(args) }
    @menu_deleteset.signal_connect("activate") do |args|
      pcd = Gtk::Dialog.new(
        title: "Are you sure?",
        parent: @window,
        flags: [:destroy_with_parent],
        buttons: [['Yes delete this batch', 0], ["No, not really", 1]])
      pcd.child.add(Gtk::Label.new("Are you sure you want to delete this batch?"))
      pcd.show_all
      response = pcd.run
      pcd.destroy
      if(response == 0)
        #unsolved itermitant crash when running this in a thread unfortunately,
        #so we are NOT going to run it in a thread
        #threaded do
          @tasks.delete_label(@current_label)
          @current_primer = nil
          @current_sample = nil
          @current_label = nil

          @mgr.refresh
          refresh
        #end
      end
    end

    tool_item = Gtk::ToolItem.new
    tool_item.add(research_menu)
    @button_bar.insert(tool_item, -1)
    @button_bar.insert(Gtk::SeparatorToolItem.new, -1)

    @quit_button = Gtk::ToolButton.new(:label => "Quit")
    @quit_button.signal_connect("clicked") {|args| puts "Closing..."; Gtk.main_quit}

    @button_bar.insert(Gtk::SeparatorToolItem.new, -1)

    @clinical_check = Gtk::CheckButton.new("Research Mode")

    if(@gui_config['clinical'] == 'true')
      @clinical_check.active=false
    else
      @gui_config['clinical'] = 'false'
      @clinical_check.active=true
    end

    @clinical_check.signal_connect("toggled") do |args|
      if(@clinical_check.active?())
        #warning
        @gui_config['clinical'] = 'false'
        pcd = Gtk::Dialog.new(
          title: "Are you sure?",
          parent: @window,
          flags: [:destroy_with_parent],
          buttons: [['I am warned', 0]])
        pcd.child.add(Gtk::Label.new("Warning:  Research mode enabled, please do not process clinical samples"))
        pcd.show_all
        response = pcd.run
        pcd.destroy
      else
        @gui_config['clinical'] = 'true'
      end
      @gui_config.save
      refresh()
    end

    tool_item = Gtk::ToolItem.new
    tool_item.add(@clinical_check)
    @clinical_check.show()
    tool_item.show()
    @button_bar.insert(tool_item, -1)

		@status_bar = Gtk::Statusbar.new()
		@status_bar.push(0, "Barcode Agent started")

    @tasks.message_receiver = @status_bar
		#Put everything together

		@info_box = Gtk::Table.new(14, 3)

		a = Gtk::Box.new(:vertical)
    b = Gtk::Paned.new(:horizontal)
		c = Gtk::Box.new(:vertical) #Left Half
    c.margin_start = c.margin_end = 10
    c.margin_top = c.margin_bottom = 4
    d = Gtk::Box.new(:vertical) #Right Half
    d.margin_start = d.margin_end = 10
    d.margin_top = d.margin_bottom = 4

    a.pack_start(@button_bar, expand: false)
		a.pack_start(b, expand: true, fill: true)
		a.pack_end(@status_bar, expand: false, fill: false)

		b.add(c)
		b.add(d)

		label_box_sb = Gtk::ScrolledWindow.new
		label_box_sb.hscrollbar_policy = :never
		label_box_sb.set_size_request(-1, 150)
		label_box_sb.add(@label_box)

		sample_box_sb = Gtk::ScrolledWindow.new
		sample_box_sb.hscrollbar_policy = :never
		sample_box_sb.set_size_request(-1, 200)
		sample_box_sb.add(@sample_box)

		primer_box_sb = Gtk::ScrolledWindow.new
		primer_box_sb.hscrollbar_policy = :never
		primer_box_sb.set_size_request(-1, 200)
		primer_box_sb.add(@primer_box)

		#Left Half
		c.pack_start(label_box_sb, expand: true, fill: true)
    c.pack_start(@set_button_box, expand: false)
		c.pack_start(sample_box_sb, expand: true, fill: true)

		#Right Half
		d.pack_start(@info_box, expand: false, fill: true)
		d.pack_start(primer_box_sb, expand: true, fill: true)

		@info_box.row_spacings=5

		text_info =
		[
		[Gtk::Label.new('Sample: '), @text_sample=Gtk::Label.new('')],
		[Gtk::Label.new('Project: '), @text_project=Gtk::Label.new('')],
    [Gtk::Label.new('Marks: '), @text_marks=Gtk::Label.new('')],
    [Gtk::Label.new('Mixtures: '), @text_mixes=Gtk::Label.new('')],
    [Gtk::Label.new('Human Edits: '), @text_hedits=Gtk::Label.new('')],
		[],
		[Gtk::Label.new('Stop codon check: '), @text_stopcodon=Gtk::Label.new('')],
		[Gtk::Label.new('Sequence quality check: '), @text_seqqual=Gtk::Label.new('')],
		[Gtk::Label.new('Mixtures count check: '), @text_mixcnt=Gtk::Label.new('')],
		[Gtk::Label.new('Marks count check: '), @text_markcnt=Gtk::Label.new('')],
		[Gtk::Label.new('Ns count check: '), @text_ncnt=Gtk::Label.new('')],
		[Gtk::Label.new('Bad quality section check: '), @text_badsection=Gtk::Label.new('')],
		[Gtk::Label.new('Single coverage check: '), @text_singlecov=Gtk::Label.new('')],
    [Gtk::Label.new('Has inserts check: '), @text_inserts=Gtk::Label.new('')],
    [Gtk::Label.new('Has deletions check: '), @text_deletions=Gtk::Label.new('')],
		[Gtk::Label.new('Bad inserts check: '), @text_bad_inserts=Gtk::Label.new('')],
    [Gtk::Label.new('Bad deletions check: '), @text_bad_deletions=Gtk::Label.new('')],
#		[Gtk::Label.new('Unviewed check: '), @text_unviewed=Gtk::Label.new('')],
		#[Gtk::Label.new('Approved check: '), @text_approved=Gtk::Label.new(''), @approve_button],
    [Gtk::Label.new('Approved check: '), @text_approved=Gtk::Label.new('')],
    [Gtk::Label.new('Errors: ')]
		]

		text_info.each_with_index do |v, i|
			v.each_with_index do |e, j|
				next if(e == nil)
				e.xalign=0
				@info_box.attach(e, j, j + 1, i, i + 1)
			end
		end
		@error_label = Gtk::TextView.new()
    @error_label.editable = false
    sc = Gtk::ScrolledWindow.new()
    sc.add(@error_label)
    sc.set_size_request(-1, 100)
    @info_box.attach(sc, 0, 3, text_info.size, text_info.size + 1)

		@window.add(a)

		#Set up signals
		@window.signal_connect("destroy") do
			puts "Goodbye..."
			Gtk.main_quit
		end

		@label_box.signal_connect("cursor-changed") do |treeview|
      @current_label = treeview.selection.selected
			@current_label = @current_label[0] if(@current_label != nil)
			@current_sample = nil
			@current_primer = nil

      threaded do
				@mgr.get_infos(@current_label)
        @sample_model_block = true
				refresh()
        @sample_model_block = false
			end
      false
    end

    @sample_box.signal_connect("cursor-changed") do |treeview|
      if(@sample_model_block)
        #skip or now
      elsif(treeview.selection.selected != nil and @current_sample != treeview.selection.selected[0])
        @current_sample = treeview.selection.selected[0] if(treeview.selection.selected != nil)
        #@current_sample.gsub!((' ' + 226.chr + 136.chr + 154.chr), '')
        @current_primer = nil
        refresh(true) #don't refresh the samples
      end
      false
    end


    @sample_box.signal_connect("button-press-event") do |treeview, event|
      if(event.event_type == Gdk::EventType::BUTTON2_PRESS and event.button == 1)
        rect = treeview.get_cell_area(nil, treeview.get_column(2))
        view() if(!(event.x > rect.x and event.x < rect.x + rect.width))
      end
      false
		end



    @primer_box.signal_connect("cursor-changed") do |treeview|
      @current_primer = treeview.selection.selected
      @current_primer = @current_primer[0] if(@current_primer != nil)
      refresh
		end

    e_render.signal_connect("edited") do |renderer,row,new_text|
      iter = @sample_model.get_iter(row)

      if(new_text != iter[3])
        @tasks.change_comment(@current_label, iter[0], new_text)
        iter[3] = new_text
        refresh
      end
    end

	end

  #Does block in background while disabling the window and catching exceptions.
  def threaded(processing = false)
    if(block_given?)
      #@_w_events = @window.events
      #@window.set_events(0)
      @window.sensitive = false

      #I've removed this 2023 in case it's not a problem any more
      #Stupid fix for weird gtk bugs
      #@sample_model.each do |model,path, iter|
      # iter[5] = nil
      #end

      #@window.window.cursor=Gdk::Cursor.new(Gdk::Cursor::WATCH)
      @status_bar.set_text("Please wait for data to be processed...")

      dlg = nil
      if(processing)
        dlg = Gtk::Dialog.new(title: "Processing", parent: @window)
        dlg.child.add(Gtk::Image.new(file: "images/" + RecallConfig['gui.processingimage'])) #We should only do this if the file exists.
        dlg.show_all
      end
      Thread.new do
        begin
          yield
        rescue
          puts $!
          puts $!.backtrace
          err = $!
          GLib::Idle.add do
            error(err) #maybe we should try to exit the thread first?
            false
          end
        end
        if(processing and dlg)
          begin
            #seems to freeze here.
            GLib::Idle.add do
              dlg.destroy()
              false
            end
          rescue
            puts $!
            puts $!.backtrace
          end
        end
        GLib::Idle.add do
          @status_bar.set_text("Done")

          @window.sensitive = true
          #@window.events = @_w_events

          #Retreiving colors
          @sample_model.each do |model,path, iter|
            iter[5] = 'white' if(iter[4] == 'black')
          end
          false
        end
      end

    end
  end

	def view
#    puts "View START" if(@debug)
    @status_bar.set_text("Viewing sample #{@current_sample}")
    f = Finisher.new(@current_label, @current_sample, self)
    threaded do
      f.run()
      refresh()
    end
	end

  def refresh_labels()
    m_labels = Array.new(@mgr.get_labels)
    d_labels = []
    @label_model.each do |model,path, iter|
      if(!m_labels.include?(iter[0].to_s))
        d_labels.push(iter[0].to_s) #delete the label later
      else
        #edit the label
        iter[1] = @mgr.get_label_moddate(iter[0]).to_s
        iter[2] = @mgr.get_label_moddate(iter[0]).to_i
        iter[3] = "white"
        #remove from m_labels so we don't add it later
        m_labels.delete_if {|a| a == iter[0] }
      end
    end

    d_labels.each do |l|
      i = @label_model.find {|m,p,iter| iter[0] == l}
      @label_model.remove(i[2])
    end

    #Add new labels
  	m_labels.each do |l|
  		iter = @label_model.append
  		iter[0] = l
  		iter[1] = @mgr.get_label_moddate(l).to_s
      iter[2] = @mgr.get_label_moddate(l).to_i
      iter[3] = "white"
	  end

    if(@current_label)
	    i = @label_model.find {|m,p,iter| iter[0] == @current_label}
      @label_box.selection.select_iter(i[2]) if(i !=nil)
    end
  end


  def refresh_samps()
    m_samps = Array.new(@mgr.get_samples(@current_label)).sort()
    d_samps = []
    x_samps = []

    $mutex.synchronize do
    #Thread.exclusive {
      @sample_model.each do |model,path, iter|
        if(!m_samps.include?(iter[0].to_s))
          d_samps.push(iter[0].to_s) #delete the sample later
        else
          #edit the label
          x_samps << iter[0].to_s
          info = @mgr.get_info(@current_label, iter[0].to_s)

          iter[1] = info.project
          iter[3] = info.comments
          iter[5] = 'black'
          iter[6] = ''
          iter[6] = 'A' if(!info.qa.userunviewed or info.qa.userfailed)
          iter[6] = (' ' + 226.chr + 136.chr + 154.chr) if(info.qa.userexported)
          if(info.qa.all_good)
            iter[4] = "light green"
          elsif(info.qa.mostly_good)
            iter[4] = "orange"
          elsif(info.qa.is_terrible?)
            iter[4] = 'black'
            iter[5] = 'white'
          else#bad
            iter[4] = "red"
          end

          #remove from m_samps so we don't add it later
          #m_samps.delete_if {|a| a == iter[0].to_s }
        end
      end
      m_samps -= x_samps

      d_samps.uniq.each do |l|
        i = @sample_model.find {|m,p,iter| iter[0].to_s == l }
        @sample_model.remove(i[2])
      end

      #Add new labels
      m_samps.each do |l|
        next if(l == nil)
        iter = @sample_model.append
        info = @mgr.get_info(@current_label, l)

        iter[0] = l
        iter[1] = info.project
        iter[2] = ''
        iter[3] = info.comments
        iter[5] = 'black'
        iter[6] = ''
        iter[6] = 'A' if(!info.qa.userunviewed or info.qa.userfailed)
        iter[6] = (' ' + 226.chr + 136.chr + 154.chr) if(info.qa.userexported) #gotta make this sensitive to something?
        if(info.qa.all_good)
          iter[4] = "light green"
        elsif(info.qa.mostly_good)
          iter[4] = "orange"
        elsif(info.qa.is_terrible?)
          iter[4] = 'black'
          iter[5] = 'white'
        else#bad
          iter[4] = "red"
        end
      end

    end #end mutex lock

  end

	#Refreshing the screen
	def refresh(samp_click = false)
    refresh_labels()
    if(samp_click)
      #do nothing
    elsif(@current_label)
      refresh_samps()
    else
      @sample_model.clear()
    end

    #Refresh the primer list (I didn't put the speedup in here, its never big...)
		@primer_model.clear()
		if(@current_sample and @current_label)
			@mgr.get_info(@current_label, @current_sample).primers.each do |l|
        iter = @primer_model.append
				iter[0] = l[0] #primer id
				iter[1] = l[2] #primer direction
        iter[2] = l[1] #primer full name
			end

			if(@current_primer)
				i = @primer_model.find {|m,p,iter| iter[0] == @current_primer}
				@primer_box.selection.select_iter(i[2]) if(i !=nil)
			end
		end
	#Refresh the labels

		if(@current_sample == nil)
			@text_sample.text = ''
			@text_project.text = ''
      @text_marks.text=''
      @text_mixes.text=''
      @text_hedits.text=''
			@text_stopcodon.text = ''
			@text_seqqual.text = ''
			@text_mixcnt.text = ''
			@text_markcnt.text = ''
			@text_ncnt.text = ''
			@text_badsection.text = ''
			@text_singlecov.text = ''
			@text_inserts.text = ''
      @text_deletions.text = ''
      @text_bad_inserts.text = ''
      @text_bad_deletions.text = ''
#			@text_unviewed.text = ''
			@text_approved.text = ''
#			@approve_button.label = 'Approve'
      @error_label.buffer.text = ''
		else
			info = @mgr.get_info(@current_label, @current_sample)
			@text_sample.text = @current_sample
			@text_project.text = info.project
      @text_marks.text=info.mark_cnt
      @text_mixes.text=info.mixture_cnt
      @text_hedits.text=info.human_edit_cnt
			@text_stopcodon.set_markup(info.qa.stop_codons  ? "<span foreground='red'>Failed</span>" : 'Ok' )
			@text_seqqual.set_markup(info.qa.bad_sequence  ? "<span foreground='red'>Failed</span>" : 'Ok' )
			@text_mixcnt.set_markup(info.qa.manymixtures  ? "<span foreground='red'>Failed</span>" : 'Ok' )
			@text_markcnt.set_markup(info.qa.manymarks  ? "<span foreground='red'>Failed</span>" : 'Ok' )
			@text_ncnt.set_markup(info.qa.manyns ? "<span foreground='red'>Failed</span>" : 'Ok' )
			@text_badsection.set_markup(info.qa.badqualsection  ? "<span foreground='red'>Failed</span>" : 'Ok' )
			@text_singlecov.set_markup(info.qa.manysinglecov  ? "<span foreground='red'>Failed</span>" : 'Ok' )
			@text_inserts.set_markup(info.qa.hasinserts  ? "<span foreground='red'>True</span>" : 'False' )
      @text_deletions.set_markup(info.qa.hasdeletions  ? "<span foreground='red'>True</span>" : 'False' )
      @text_bad_inserts.set_markup(info.qa.hasbadinserts  ? "<span foreground='red'>Failed</span>" : 'Ok' )
      @text_bad_deletions.set_markup(info.qa.hasbaddeletions  ? "<span foreground='red'>Failed</span>" : 'Ok' )
#			@text_unviewed.set_markup(info.qa.userunviewed  ? "<span foreground='red'>Failed</span>" : 'Ok' )
			@text_approved.set_markup(info.qa.userfailed ? "<span foreground='red'>Failed</span>" : (info.qa.userunchecked ? "<span foreground='red'>Unchecked</span>" : 'Ok') )
#			@approve_button.label = info.qa.userunchecked ? "Approve" : "Reject "
      @error_label.buffer.text = info.errors.empty?() ? 'No Errors' : "#{info.errors.join("\n")}"
		end

		#Set button sensitivities
		#@menu_export.sensitive=@current_label ? true : false
		@change_project_button.sensitive=@current_label ? true : false
    #@autoapprove_button.sensitive=@current_label ? true : false
    @exportapproved_button.sensitive=@current_label ? true : false
		@delete_sample_button.sensitive=@current_sample ? true : false
		#@menu_deleteset.sensitive=@current_label ? true : false
		#@menu_realign.sensitive=@current_label ? true : false

    if(@gui_config['clinical']=='true')
      #Clinical == not research
      @menu_export.sensitive=false
      @menu_realign.sensitive=false
      @menu_deleteset.sensitive=false
      @rmen.sensitive=false
    else
      @menu_export.sensitive=true
      @menu_realign.sensitive=true
      @menu_deleteset.sensitive=true
      @rmen.sensitive=true
    end

		@refreshed = true
	end

  def bp_change_projects(args)
  	samps = @mgr.get_samples(@current_label).map {|s| [s]}
    label = nil
    type = nil
    type = 'clinical' if(@gui_config['clinical'] == 'true')
		projs = StandardInfo.list(type)
		#Step 2, choose projects for files
		pcd = Gtk::Dialog.new(
      title: "Choose projects for your samples",
      parent: @window,
      flags: [:destroy_with_parent],
      buttons: [['Continue', :accept], [Gtk::Stock::CANCEL, :cancel]])
		sb = Gtk::ScrolledWindow.new
		sb.hscrollbar_policy = :never
		sb.set_size_request(-1, 400)
		pcd.child.add(sb)
		box = Gtk::Box.new(:vertical)
		sb.add_with_viewport(box)
		sb = box

		samps.each do |s|
			box = Gtk::Box.new(:horizontal)
			select = Gtk::ComboBoxText.new()
			box.add(Gtk::Label.new(s[0]))
			box.add(select)
			sb.pack_start(box, expand: false)
			s.push(select)

			projs.each do |p|
				select.append_text(p)
			end
			select.append_text("Keep the same")
			select.active=projs.size
		end
		sb.add(Gtk::Box.new(:vertical))
		pcd.child.pack_start(Gtk::Separator.new(:horizontal), expand: false)
		box = Gtk::Box.new(:horizontal)
		select_all = Gtk::ComboBoxText.new()

		projs.each do |p|
			select_all.append_text(p)
		end
		select_all.append_text("Keep the same")
		box.add(Gtk::Label.new("Change All"))
		box.add(select_all)

		select_all.signal_connect('changed') do |combobox|
			samps.each do |s|
				s[1].set_active(combobox.active)
			end
		end

		pcd.child.pack_start(box, expand: false)
		pcd.child.show_all

		if(pcd.run == Gtk::ResponseType::ACCEPT)
			#Get values of samples/projects
			samps.each do |s|
				s[1] = s[1].active_text
                s.push(@current_label)
                s.push([])
			end
			samps.delete_if {|s| s[1] == 'Keep the same'}
			pcd.destroy
		else
			pcd.destroy
			return
		end

		#Ok, if you got this far, then you can change the projects
    threaded(true) do
      @tasks.align_samples_custom(samps, false)
      @tasks.view_log_custom(samps)
      #refresh_samps()  #I don't understand why we need this.  Something strange is going on.  Its like the model chokes.
      @sample_model.clear()  #for some reason it buggers up, this might fix it.
			refresh
		end
  end

  def bp_realign(args)
  	samps = @mgr.get_samples(@current_label).map {|s| [s]}
		label = nil
		#Step 2, choose projects for files
		pcd = Gtk::Dialog.new(
      title: "Choose which samples to realign",
      parent: @window,
      flags: [:destroy_with_parent],
      buttons: [['Continue', :accept], [Gtk::Stock::CANCEL, :cancel]])

		sb = Gtk::ScrolledWindow.new
		sb.hscrollbar_policy = :never
		sb.set_size_request(-1, 400)
		pcd.child.add(sb)
		box = Gtk::Box.new(:vertical)
		sb.add_with_viewport(box)
		sb = box

		samps.sort{|a,b| a[0] <=> b[0] }.each do |s|
			box = Gtk::Box.new(:horizontal)
			select = Gtk::ComboBoxText.new()
			box.add(Gtk::Label.new(s[0]))
			box.add(select)
			sb.pack_start(box, expand: false)
			s.push(select)
      info = @mgr.get_info(@current_label, s[0])
      s.push(info.project)
			select.append_text("Realign")
			select.append_text("Skip")
			select.active=1
		end

		sb.add(Gtk::Box.new(:vertical))
		pcd.child.pack_start(Gtk::Separator.new(:horizontal), expand: false)
		box = Gtk::Box.new(:horizontal)
		select_all = Gtk::ComboBoxText.new()

    select_all.append_text("Realign")
		select_all.append_text("Skip")
    select_all.append_text("Realign Bad")
		box.add(Gtk::Label.new("Change All"))
		box.add(select_all)

		select_all.signal_connect('changed') do |combobox|
			samps.each do |s|
        if(combobox.active == 2)
          info = @mgr.get_info(@current_label, s[0])
          if(info.qa.mostly_good == false)
            s[1].set_active(0)
          else
            s[1].set_active(1)
          end
        else
          s[1].set_active(combobox.active)
        end
			end
		end

		pcd.child.pack_start(box, expand: false)
		pcd.child.show_all

		if(pcd.run == Gtk::ResponseType::ACCEPT)
			#Get values of samples/projects
			samps.each do |s|
				s[1] = s[1].active_text
        s.push(@current_label)
        s.push([])
			end
			samps.delete_if {|s| s[1] == 'Skip'}
			pcd.destroy
		else
			pcd.destroy
			return
		end

    samps.each {|s| s.delete_at(1) }

		#Ok, if you got this far, then you can change the projects

		threaded(true) do
      @tasks.align_samples_custom(samps, false)
      @tasks.view_log_custom(samps)
			refresh
		end
  end

	#Exports text files(Will pop up a window asking which samples to export)
	#And will only give the option to export ones that aren't ok(but can force)
	def bp_export(args, default=false)
		pcd = Gtk::Dialog.new(
      title: "Choose which samples to export",
      parent: @window,
      flags: [:destroy_with_parent],
      buttons: [['Continue', :accept], [Gtk::Stock::CANCEL, :cancel]])

		sb = Gtk::ScrolledWindow.new
		sb.hscrollbar_policy = :never
		sb.set_size_request(-1, 400)
		pcd.child.add(sb)
		box = Gtk::Box.new(:vertical)
		sb.add_with_viewport(box)
		sb = box


    #Change it so that the samp list is just an array and the rest of the info is in a hash or something?
    #need to combine samps or something...
    #puts samps.inspect
    pjs = []
    #[project,]
    RecallConfig.proj_joins.each do |proj|
      tmp = RecallConfig.proj_redirect[proj]
      tmp.each do |t|
        pjs.push([proj, t[0], t[1]])
      end
    end

    #[sampid, [subsampids], project, info.qa, select.active]
    #info.qa we use the following.  0 == all good, 1 == mostly good, 2 == fail.
    samps = @mgr.get_samples(@current_label).map{|a| [a, [], @mgr.get_info(@current_label, a).project, @mgr.get_info(@current_label, a).qa, nil] }
    #Lets merge/join samps and such
    newsamps = []
    samps.each do |samp|
      #puts samp[0]
      if(samp[3].all_good)
        samp[3] = 0  #green
      elsif(samp[3].mostly_good)
        samp[3] = 1 #orange
      elsif(samp[3].is_terrible?)
        samp[3] = 3 #black
      else
        samp[3] = 2 #red
      end

      pj = pjs.find {|a| a[1] == samp[2]}
      if(pj == nil)
        samp[1] = [samp[0]]
        next
      end
      #now, check to see if a newsamps entry already exists for this.
      ns = newsamps.find {|a| a[0] + pj[2] == samp[0] }
      #add to ns
      if(ns != nil)
        ns[1].push(samp[0])
        ns[3] = [ns[3], samp[3]].max
        samp[1] = 'KILLME'
        next
      end

      ns = [samp[0].gsub(/#{Regexp.escape(pj[2])}$/,''), [samp[0]], pj[0], samp[3], nil]
      samp[1] = 'KILLME'
      newsamps.push(ns)
    end

    #check to see if newsamps is missing any chunks and sort the chunks.
    newsamps.each do |ns|
      pr = RecallConfig.proj_redirect[ns[2]]
      new_order = []
      pr.each do |pr_chunk|
        tmp = ns[1].find {|a| a == ns[0] + pr_chunk[1]}
        tmp = '*' + pr_chunk[0] if(tmp == nil)
        new_order << tmp
      end
      ns[3] = 3 if(new_order.include?(nil)) #Missing chunks, uberfail!
      ns[1] = new_order #put the sorted version in
    end

    samps += newsamps

    samps.delete_if {|s| s[1] == 'KILLME' }
    samps.delete_if {|s| s[3] != 0 } if(default) #never export if default is enabled and the sequence isn't perfect

		samps.sort{|a,b| a[0] <=> b[0] }.each do |s|
			box = Gtk::Box.new(:horizontal)
			select = Gtk::ComboBoxText.new()
			box.add(Gtk::Label.new(s[0]))
			box.add(select)
			sb.pack_start(box, expand: false)
			s[4] = select

      if(s[3] == 2)
        select.append_text("Skip Failed Sample             ")
        select.append_text("Export Failed Sample           ")
        select.active=0
      elsif(s[3] == 1)
        select.append_text("Skip Sample                    ")
        select.append_text("Export unapproved Sample")
        select.active=0
      elsif(s[3] == 0)
        select.append_text("Skip Sample                    ")
        select.append_text("Export Sample                  ")
        select.active=1
      elsif(s[3] == 3)
        select.append_text("Skip Sample (Failure)          ")
        select.active=0
      end
		end
		to_fasta = nil

    box = Gtk::Box.new(:horizontal)
    select_all = Gtk::ComboBoxText.new()

    select_all.append_text("Skip All       ")
    select_all.append_text("Export All     ")
    select_all.append_text("Export good only")
    box.add(Gtk::Label.new("Change All "))
    box.add(select_all)

    select_all.signal_connect('changed') do |combobox|
      samps.each do |s|
        if(s[3] == 3)
          s[4].set_active(0)
        elsif(combobox.active == 0)
          s[4].set_active(0)
        elsif(combobox.active == 1)
          s[4].set_active(1)
        elsif(combobox.active == 2)
          if(s[3] == 0 or s[3] == 1)
            s[4].set_active(1)
          else
            s[4].set_active(0)
          end
        end
      end
    end

    # Create a new box to store export-type choices
    box2 = Gtk::Box.new(:horizontal)
    export_type = Gtk::ComboBoxText.new()

    # export options are text and fasta
    export_type.append_text("Export as fasta")
    export_type.append_text("Export as text ")
    export_type.append_text("Export as text (amino acids)")
    export_type.set_active(1)

    #add a label to the box so we know what its for.
    box2.add(Gtk::Label.new("Export Type"))
    box2.add(export_type)

    #Pack the activity options and export options boxes into the popup
    pcd.child.pack_start(box, expand: false)
    pcd.child.pack_start(box2, expand: false)
    #end

		#if(!default)
			pcd.child.show_all

			if(pcd.run == Gtk::ResponseType::ACCEPT)
			#Get values of samples/projects
				samps.each do |s|
					s[4] = s[4].active_text
				end

				to_fasta = export_type.active_text.include?('fasta')
        to_aa = export_type.active_text.include?('amino acids')
				samps.delete_if {|s| !s[4].include?('Export')}
				pcd.destroy
			else
				pcd.destroy
				return
			end
		#else
		#	to_fasta = false
		#	samps.delete_if do |s|
		#		info = @mgr.get_info(@current_label, s[0])
		#		!info.qa.all_good
		#	end
		#end
		#Ask for a path
    #@_w_events = @window.events
    #@window.events = 0
    @window.sensitive = false

    if(@export_dir and @export_dir != '' and File.exist?(@export_dir))
      Dir[@export_dir]
    else
      Dir['./']
    end

		fcd = Gtk::FileChooserDialog.new(
      title: "Choose a directory to export to",
      parent: @window,
      action: :select_folder,
      buttons: [['Continue', :accept], [Gtk::Stock::CANCEL, :cancel]])

    fcd.set_size_request(700, -1)
		fcd.set_current_folder(@export_dir) if(@export_dir and @export_dir != '' and File.exist?(@export_dir))
		dir = ''
		if(fcd.run == Gtk::ResponseType::ACCEPT)
			dir = fcd.filename
			fcd.destroy
		else
			fcd.destroy

      #@window.events = @_w_events
      @window.sensitive = true
			return
		end
  #@window.events = @_w_events
  @window.sensitive = true

        # If we are exporting to fasta, dont worry about overwriting. go straight to exportation.
    if to_fasta
    #Now export the samples in their own thread.
      threaded(true) do
        @tasks.export_samples_to_fasta(@current_label, samps.map{|s| [s[0]] + s[1]}, dir)
      end
      return
    end #endif we are exporting to fasta.

    if to_aa
    #Now export the samples in their own thread.
      threaded(true) do
        @tasks.export_samples_to_aa(@current_label, samps.map{|s| [s[0]] + s[1]}, dir)
      end
      return
    end #endif we are exporting to aa

    # Exporting to text files requires that we check for existing files.
    no_overwrite_samps = samps.find_all {|s| File.exist?(dir + "/#{s[0]}.txt")}.map{|s| [s[0]]}

    if(no_overwrite_samps.size > 0)
      pcd = Gtk::Dialog.new(title: "These samples already exist here, overwrite?",
        parent: @window,
        flags: [:destroy_with_parent],
        buttons: [['Continue', :accept], [Gtk::Stock::CANCEL, :cancel]])

      sb = Gtk::ScrolledWindow.new
      sb.hscrollbar_policy = :never
      sb.set_size_request(-1, 400)
      pcd.child.add(Gtk::Label.new("These samples already exist here, overwrite?"))
      pcd.child.add(sb)
      box = Gtk::Box.new(:vertical)
      sb.add_with_viewport(box)
      sb = box

      no_overwrite_samps.each do |s|
        box = Gtk::Box.new(:horizontal)
        select = Gtk::ComboBoxText.new()
        box.add(Gtk::Label.new(s[0]))
        box.add(select)
        sb.pack_start(box, expand: false)
        s.push(select)

        select.append_text("Overwrite this previously exported file")
        select.append_text("Do not re-export this file")

        select.active=1
      end

      pcd.child.show_all

      if(pcd.run == Gtk::ResponseType::ACCEPT)
        #Get values of samples/projects
        no_overwrite_samps.each do |s|
          s[1] = s[1].active_text
        end
        no_overwrite_samps.delete_if {|s| !s[1].include?('Do not re-export')}
        pcd.destroy
      else
        pcd.destroy
        return
      end
      no_overwrite_samps.map! {|s| s[0]}
      samps.delete_if {|s| no_overwrite_samps.include?(s[0]) }
    end


    raw_samps = []
    samps.each do |s|
      s[1].each do |x|
        raw_samps << x if(x[0,1] != '*')
      end
    end

    #Now export the samples
    threaded(true) do
			@tasks.export_samples(@current_label, samps.map{|s| [s[0]] + s[1]}, dir)
      @tasks.export_samples_quest(@current_label, raw_samps, dir, RecallConfig['common.quest_exports']) #hmm?
			@tasks.user_exported(@current_label, raw_samps) #hmm?
      @tasks.approve_samples(@current_label, raw_samps, true) #test
			refresh
		end

	end

	#Approves the selected sample(Probably will get rid of this button and
	#put it into the sequence finisher screen)
	def bp_approve(args)
		threaded do
			@tasks.approve_samples(@current_label, [@current_sample])
			refresh
		end
	end

  #maybe if I queue the error as an event?
	def error(exception)
    if(exception.message == 'phred_error')
      puts exception.to_s
      puts exception.backtrace
      puts "Phred Error:  Could not find generated poly or qual files"
      pcd = Gtk::Dialog.new(
        title: "Phred error!",
        parent: @window,
        flags: [:destroy_with_parent],
        buttons: [[Gtk::Stock::OK, :accept]])

      pcd.child.add(Gtk::Label.new("Could not find generated phred files."))
      error_box = Gtk::TextView.new()
      error_box.buffer.text = "Possible reasons for this are:\n  1: phred is not installed correctly\n  2:  phred attempted to process a corrupted chromatogram file\n  3:  Data files were moved or changed while in the middle of processing.  \n\nApplication can not proceed and will now shutdown\n\n"
      pcd.child.add(error_box)
      pcd.show_all
      pcd.run
      pcd.destroy
      exit()
    else
      puts exception
      puts exception.backtrace

      pcd = Gtk::Dialog.new(
        title: "An unexpected error occured!",
        parent: @window,
        flags: [:destroy_with_parent],
        buttons: [[Gtk::Stock::OK, :accept]])

      pcd.child.add(Gtk::Label.new("Error log:"))
      error_box = Gtk::TextView.new()
      error_box.buffer.text=exception.to_s + "\n\n" + exception.backtrace.join("\n")
      pcd.child.add(error_box)
      pcd.show_all
      pcd.run
      pcd.destroy
      exit()
    end
	end

	def run
		@window.show_all
    @window.set_icon("images/icon.png")

		begin
			Gtk.main()
		rescue
			puts $!
			puts $!.backtrace
			retry
		end
	end

#Bring up a  to add samples, create recall files
	def bp_add_samples(args)
    samps_final = []
		label = nil

		#Step 1, select files
    #@_w_events = @window.events
    #@window.events = 0
    @window.sensitive = false
    if(@add_samples_dir)
      Dir[@add_samples_dir]
    else
      Dir['./']
    end
		fcd = Gtk::FileChooserDialog.new(
      title: "Select your samples",
      parent: @window,
      action: :select_folder,
      buttons: [['Continue', :accept], [Gtk::Stock::CANCEL, :cancel]])
    fcd.select_multiple = true

		fcd.set_current_folder(@add_samples_dir) if(File.exist?(@add_samples_dir))
    dirs = []
		if(fcd.run == Gtk::ResponseType::ACCEPT)
			dirs = fcd.filenames
			fcd.destroy
		else
			fcd.destroy
      @window.sensitive = true
			return
		end
    @window.sensitive = true

    dirs.each do |dir|
      samps = []
      dir.gsub!(/\\/, '/')
      #Get sample list

      samps = @mgr.scan_dir_for_samps(dir).map{|a| [a]}

      #If clinical, only show clinical
      type = nil
      type = 'clinical' if(@gui_config['clinical'] == 'true')
      projs = StandardInfo.list(type)
      RecallConfig.proj_redirect.each do |proj, res|
        accept = false
        next if(res == nil)
        res.each do |re|
          if(re and re != [])
            accept = true if(re[0] and projs.include?(re[0].upcase))
            projs.delete_if {|a| a.upcase == re[0].upcase}
          end
        end
        projs.push(proj.upcase) if(res != [] and accept)
      end
      RecallConfig.proj_chooses.each do |pc|
        accept = false
        pc[1].each do |sub|
          accept = true if(sub[0] and projs.include?(sub[0].upcase))
          projs.delete_if {|a| a.upcase == sub[0].upcase} if(sub[0])
        end
        projs.push(pc[0].upcase) if(accept)
        #I should probably delete the subproj's as well.
      end
      projs.uniq!
      projs.sort!

      #projs.delete_if {|a| a.include?('HLA')}
      #projs.push('HLA')
      labels_txt = ['New Batch'] + @mgr.get_recent_labels(10)

      files = []
      files += Dir[d_esc(dir) + '/*.ab1'] if(RecallConfig['common.load_abi'] == 'true')
      files += Dir[d_esc(dir) + '/*.scf'] if(RecallConfig['common.load_scf'] == 'true')



      #Step 2, choose projects for files
      #Ideally guess project based on the primers
      pcd = Gtk::Dialog.new(
        title: "Choose projects for your samples",
        parent: @window,
        flags: :destroy_with_parent,
        buttons: [['Continue', :accept], [Gtk::Stock::CANCEL, :cancel]])

      sb = Gtk::ScrolledWindow.new
      sb.hscrollbar_policy = :never
      sb.set_size_request(-1, 400)
      pcd.child.add(sb)

      box = Gtk::Table.new(3, samps.size - 1)
      sb.add_with_viewport(box)
      sb = box

      ["Sample", "Project", "Batch "].each_with_index do |v, i|
        lab = Gtk::Label.new()
        lab.set_markup("<b>#{v}</b>")
        lab.hexpand = true
        lab.vexpand = true
        lab.halign = :fill
        lab.valign = :fill
        lab.margin_top = 2
        lab.margin_bottom = 4
        sb.attach(lab, i, i + 1, 0, 1)
      end

      i = 1


      samps.each do |s|
        primers = @mgr.scan_dir_for_primers(dir, s[0], true).map{|a| a}

        predicted_proj = nil
        #do stuff here
        #PrimerInfo.genes(primer)

        predicted_proj = primers.map{|p| PrimerInfo.genes(p) }
        predicted_proj.delete_if {|p| p == nil}
        predicted_proj.map! {|p| p[0] }
        tmp = Hash.new
        predicted_proj.each do |p|
          tmp[p] = 0 if(tmp[p] == nil)
          tmp[p] += 1
        end
        predicted_proj = tmp.to_a.max {|p,q| p[1] <=> q[1] }[0] if(tmp != nil and tmp != {})

        select_proj = Gtk::ComboBoxText.new()
        select_proj.hexpand = true
        select_proj.vexpand = true
        select_proj.halign = :fill
        select_proj.valign = :fill
        select_proj.margin_top = 2
        select_proj.margin_bottom = 2

        select_label = Gtk::ComboBoxText.new()
        select_label.hexpand = true
        select_label.vexpand = true
        select_label.halign = :fill
        select_label.valign = :fill
        select_label.margin_top = 2
        select_label.margin_bottom = 2

        samp_label = Gtk::Label.new("#{s[0]} (#{primers.size} primers)")
        samp_label.hexpand = true
        samp_label.vexpand = true
        samp_label.halign = :fill
        samp_label.valign = :fill
        samp_label.margin_top = 2
        samp_label.margin_bottom = 2

        sb.attach(samp_label, 0, 1, i, i + 1)
        sb.attach(select_proj, 1, 2, i, i + 1)
        sb.attach(select_label, 2, 3, i, i + 1)

        s.push(select_proj)
        s.push(select_label)

        ix = -1
        projs.each_with_index do |p, ii|
          select_proj.append_text(p)
          ix = ii if(p == predicted_proj)
        end

        labels_txt.each do |l|
          if(@mgr.get_samples(l).include?(s[0]))
            select_label.append_text('* ' + l) #remember to filter this later
          else
            select_label.append_text(l)
          end
        end

        tmp = files.find_all {|a| a =~ /#{Regexp.escape(s[0])}/}.map {|a| a.gsub(/#{Regexp.escape(dir)}\//, '').gsub(/_.*/, '')}

        select_proj.append_text("Custom")
        select_proj.append_text("Skip Sample")
        select_proj.active=ix if(ix > -1)
        select_proj.active=projs.size + 1 if(ix == -1)
        select_proj.active=projs.size if(tmp.size != tmp.uniq.size)

        select_label.active=0
        i += 1
      end

      sb.attach(Gtk::Label.new(""), 0, 1, i, i + 1)
      sb.attach(Gtk::Label.new(""), 1, 2, i, i + 1)
      sb.attach(Gtk::Label.new(""), 2, 3, i, i + 1)

      pcd.child.pack_start(Gtk::Separator.new(:horizontal), expand: false)
      box = Gtk::Box.new(:horizontal)
      select_all_proj = Gtk::ComboBoxText.new()
      select_all_label = Gtk::ComboBoxText.new()

      projs.each do |p|
        select_all_proj.append_text(p)
      end

      labels_txt.each do |l|
        select_all_label.append_text(l)
      end

      select_all_proj.append_text("Custom")
      select_all_proj.append_text("Skip Sample")

      box.add(Gtk::Label.new("Change All"))
      box.add(select_all_proj)
      box.add(select_all_label)

      select_all_proj.signal_connect('changed') do |combobox|
        samps.each do |s|
          s[1].set_active(combobox.active)
        end
      end

      select_all_label.signal_connect('changed') do |combobox|
        samps.each do |s|
          s[2].set_active(combobox.active)
        end
      end

      pcd.child.pack_start(box, expand: false)
      pcd.child.show_all
      no_recall = false

      if(pcd.run == Gtk::ResponseType::ACCEPT)
			#Get values of samples/projects
        samps.each do |s|
          s[1] = s[1].active_text
          no_recall = true if(s[2].active_text.include?('*'))
          s[2] = s[2].active_text.gsub(/^\* /,'') #remove the * if it exists
        end
        samps.delete_if {|s| s[1] == 'Skip Sample'}
        pcd.destroy
      else
        pcd.destroy
        return
      end

      spec_files = []

      samps.each do |s|
        if(s[1] == 'Custom')
#         tmp = (Dir[dir + "/#{s[0]}*.ab1"] + Dir[dir + "/#{s[0]}*.scf"]).map {|a| [a, a[(a.rindex('/') + 1) .. a.index(@sample_primer_delimiter, (a.rindex('/') + 1)) - 1]] }
          tmp = (Dir[dir + "/*#{d_esc(s[0])}*.ab1"] + Dir[dir + "/*#{d_esc(s[0])}*.scf"]).map do |a|
            info = nil
            begin
              info = [a, @mgr.file_syntax_get_info(a)[0]]
            rescue
              info = nil
            end
            info
          end
          tmp.delete_if(){|a| a == nil }

          spec_files += tmp
        end
      end

      spec_files.uniq!
      return if(samps.size == 0)
      samps.delete_if { |s| s[1] == 'Custom' }

      #Step 3, choose label for files with "New"
      lcd = Gtk::Dialog.new(
        title: "Choose a label for this batch of samples",
        parent: @window,
        flags: :destroy_with_parent,
        buttons: [["Continue", :accept], [Gtk::Stock::CANCEL, :cancel]])

      lcd.child.add(Gtk::Label.new("Name of this batch of samples?"))
      entry = Gtk::Entry.new
      lcd.child.add(entry)
      entry.text = dir[dir.rindex("/") + 1 .. -1]
      lcd.child.set_size_request(300, -1)
      lcd.child.show_all
      newlabel = ''
      if(lcd.run == Gtk::ResponseType::ACCEPT)
			#Get values of samples/projects
        newlabel = entry.text
        samps.each do |s|
          s[2] = newlabel if(s[2] == 'New Batch')
        end
        lcd.destroy
      else
        lcd.destroy
        return
      end

      #add files
      samps.each do |s|
        if(s[2] == newlabel and !no_recall)
          files = Dir["#{d_esc(dir)}/#{d_esc(s[0])}.recall"]
          files += Dir["#{d_esc(dir)}/*#{d_esc(s[0])}*.ab1"] if(RecallConfig['common.load_abi'] == 'true') #naw man.  naw.
          files += Dir["#{d_esc(dir)}/*#{d_esc(s[0])}*.scf"] if(RecallConfig['common.load_scf'] == 'true')
          #Filter
          files.delete_if do |f|
            del = false
            begin
              tmp = @mgr.file_syntax_get_info(f)
              if(tmp[0] == s[0] and tmp[1] != nil)
                del = false
              else
                del = true
              end
            rescue
              del = true
            end
            del
          end

          s.push(files)
        else #This way we don't take .recall files for repeats
          files = []
          files += Dir["#{d_esc(dir)}/*#{d_esc(s[0])}*.ab1"] if(RecallConfig['common.load_abi'] == 'true')
          files += Dir["#{d_esc(dir)}/*#{d_esc(s[0])}*.scf"] if(RecallConfig['common.load_scf'] == 'true')

          #Filter
          files.delete_if do |f|
            del = false
            begin
              tmp = @mgr.file_syntax_get_info(f)
              if(tmp[0] == s[0] and tmp[1] != nil)
                del = false
              else
                del = true
              end
            rescue
              del = true
            end
            del
          end

          s.push(files)
        end

      end



      #If any wierd entries exist, this is where we pop up the dialog to resolve them.
      if(spec_files.size > 0)
        pcd = Gtk::Dialog.new(
          title: "Choose projects for your samples",
          parent: @window,
          flags: [:destroy_with_parent],
          buttons: [['Continue', :accept], [Gtk::Stock::CANCEL, :cancel]])

        sb = Gtk::ScrolledWindow.new
        sb.hscrollbar_policy = :never
        sb.set_size_request(-1, 400)
        pcd.child.add(sb)
        box = Gtk::Table.new(3, samps.size)
        sb.add_with_viewport(box)
        sb = box

        labels_txt = [newlabel] + @mgr.get_recent_labels(6)

        ["File", "Project", "Batch"].each_with_index do |v, i|
          lab = Gtk::Label.new()
          lab.set_markup("<b>#{v}</b>")
          lab.hexpand = true
          lab.vexpand = true
          lab.halign = :fill
          lab.valign = :fill
          lab.margin_top = 2
          lab.margin_bottom = 4
          sb.attach(lab, i, i + 1, 0, 1)
        end

        i = 1

        spec_files.each do |s|
          select_proj = Gtk::ComboBoxText.new()
          select_proj.hexpand = true
          select_proj.vexpand = true
          select_proj.halign = :fill
          select_proj.valign = :fill
          select_proj.margin_top = 2
          select_proj.margin_bottom = 2

          select_label = Gtk::ComboBoxEntry.new()
          select_label.set_size_request(325, -1)
          select_label.hexpand = true
          select_label.vexpand = true
          select_label.halign = :fill
          select_label.valign = :fill
          select_label.margin_top = 2
          select_label.margin_bottom = 2

          file_label = Gtk::Label.new("#{s[0].gsub(/#{Regexp.escape(dir)}\//, '').gsub(/\.ab1/, '').gsub(/\.scf/, '')}")
          file_label.set_alignment(0,0)
          file_label.hexpand = true
          file_label.vexpand = true
          file_label.halign = :fill
          file_label.valign = :fill
          file_label.margin_top = 2
          file_label.margin_bottom = 2

          sb.attach(file_label, 0, 1, i, i + 1)
          sb.attach(select_proj, 1, 2, i, i + 1)
          sb.attach(select_label, 2, 3, i, i + 1)

          s.push(select_proj)
          s.push(select_label)

          projs.each do |p|
            select_proj.append_text(p)
          end

          labels_txt.each do |l|
            if(@mgr.get_samples(l).include?(s[1]))
              select_label.append_text('* ' + l) #remember to filter this later
            else
              select_label.append_text(l)
            end
          end

          select_proj.append_text("Skip File")
          select_proj.active=projs.size

          select_label.active=0
          i += 1
        end

        sb.attach(Gtk::Label.new(""), 0, 1, i, i + 1)
        sb.attach(Gtk::Label.new(""), 1, 2, i, i + 1)
        sb.attach(Gtk::Label.new(""), 2, 3, i, i + 1)

        pcd.child.pack_start(Gtk::Separator.new(:horizontal), false)
        box = Gtk::Box.new(:horizontal)
        select_all_proj = Gtk::ComboBoxText.new()
        select_all_label = Gtk::ComboBoxText.new()

        projs.each do |p|
          select_all_proj.append_text(p)
        end

        labels_txt.each do |l|
          select_all_label.append_text(l)
        end

        select_all_proj.append_text("Skip File")
        box.add(Gtk::Label.new("Change All"))
        box.add(select_all_proj)
        box.add(select_all_label)

        select_all_proj.signal_connect('changed') do |combobox|
          spec_files.each do |s|
            s[2].set_active(combobox.active)
          end
        end

        select_all_label.signal_connect('changed') do |combobox|
          spec_files.each do |s|
            s[3].set_active(combobox.active)
          end
        end

        pcd.child.pack_start(box, false)
        pcd.child.show_all

        if(pcd.run == Gtk::ResponseType::ACCEPT)
          #Get values of samples/projects
          spec_files.each do |s|
            s[2] = s[2].active_text
            s[3] = s[3].active_text.gsub(/^\* /,'') #remove the * if it exists
          end
          spec_files.delete_if {|s| s[2] == 'Skip File'}
          pcd.destroy
        else
          pcd.destroy
          return
        end
      end

      #convert back to samp form.
      newsamps = []

      spec_files.each do |f|
        s = newsamps.find {|a| a[0] == f[1] and a[1] == f[2] and a[2] == f[3] }
        if(s == nil)
          newsamps.push([f[1], f[2], f[3], [f[0]]])
        else
          s[3].push(f[0])
        end
      end

      newsamps.each do |s|
        newfiles = []
        s[3].each do |f|
          file_pat = f.gsub(/#{Regexp.escape(dir)}\//, '').gsub(/\.ab1/, '').gsub(/\.scf/, '')
          files = Dir["#{d_esc(dir)}/qual/#{d_esc(file_pat)}*.poly"] + Dir["#{d_esc(dir)}/qual/#{d_esc(file_pat)}*.qual"]
          newfiles += files
        end
        s[3] += newfiles
      end

      samps += newsamps
      samps_final += samps
    end #Stuff

    #Ok, if you got this far, then you can create the samples
    threaded(true) do
      @tasks.align_samples_custom(samps_final, true)
      @tasks.view_log_custom(samps_final)

      @mgr.refresh
      @current_label = samps_final[0][2]
      @current_sample = nil
      @current_primer = nil
      refresh
    end

	end

  def bp_autoapprove(args)
    puts "This button was pressed, woot"
  end

end
