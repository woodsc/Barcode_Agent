=begin
finisher.rb
Copyright (c) 2007-2023 University of British Columbia

Lets users view and edit samples.

=end
#require 'profiler'
require 'lib/conversions'
require 'lib/manager'
require 'lib/recall_config'
require 'lib/primer_info'
require 'lib/recall_data'

require 'lib/alg/aligner'
require 'lib/alg/primer_fixer'
require 'lib/alg/base_caller'
require 'lib/alg/quality_checker'
require 'lib/alg/insert_detector'

require 'lib/gui/gui_config'
require 'lib/gui/primer_map'
require 'lib/gui/sequence_editor'
require 'lib/gui/chromatograms'

if(RUBY_VERSION =~ /^2/)
  module GdkPixbuf #gah, gdk is so buggy.
    class Pixbuf
      def save(filename, type, options={})
        savev_utf8(filename, type, '', '') #Probably will only work in windows.
      end
    end
  end
end

class Finisher
  attr_accessor :label, :sample, :window, :parent, :magic_mode
  def initialize(label, sample, gui)
    @debug = false
    @gui = gui
    @sample = sample
    @label = label
    @sh_dir = ''

    @hide_aa = RecallConfig['guiconfig.hide_aa'] == 'true'
    @hide_ref = RecallConfig['guiconfig.hide_ref'] == 'true'
    @use_base_num = RecallConfig['guiconfig.use_base_num'] == 'true'

    restart()
  end

  def restart()
    @rd = @gui.mgr.get_recall_data(@label, @sample)
    @rd.add_abis(@gui.mgr.get_abis(@label, @sample))

    @magic_mode=false
    RecallConfig.set_context(@rd.project, @gui.mgr.user)
    $conf = GuiConfig.new
    @sh_dir = $conf['sh_dir']
    if(@window != nil)
      @restarting = true
      @window.hide
      @editor.destroy
      @primermap.destroy
      @chromatograms.destroy
      @window.destroy
    end

    @window = Gtk::Window.new()
    @window.title="Barcode Agent - Sequence Finisher - #{@sample}"

    @window.set_default_size($conf['win_width'], $conf['win_height'])
    @window.maximize() if($conf['win_maximized'])

    @restarting = false

    @primermap = PrimerMap.new(@rd)

    #set up menu buttons
    save_btn = Gtk::ToolButton.new(:label => "Save or Exit      ")
    save_btn.signal_connect("clicked") {|args| bp_exit(args) }
    del_primer_btn = Gtk::ToolButton.new(:label => "Delete Primer")
    del_primer_btn.signal_connect("clicked") {|args| bp_delete_primer() }
    change_proj_btn = Gtk::ToolButton.new(:label => "Change Project")
    change_proj_btn.signal_connect("clicked") {|args| bp_change_project() }
    mark_bad_btn = Gtk::ToolButton.new(:label => "Mark Selection as bad")
    mark_bad_btn.signal_connect("clicked") {|args| bp_mark_as_bad() }
    help_btn = Gtk::ToolButton.new(:label => "Help")
    help_btn.signal_connect("clicked") {|args| help() }

    @button_bar = Gtk::Toolbar.new()
    @button_bar.insert(save_btn, -1)
    @button_bar.insert(Gtk::SeparatorToolItem.new, -1)
    @button_bar.insert(del_primer_btn, -1)
    @button_bar.insert(change_proj_btn, -1)
    @button_bar.insert(mark_bad_btn, -1)
    @button_bar.insert(help_btn, -1)


    @status_bar = Gtk::Statusbar.new()
    @status_bar.push(0, "Viewing #{@sample}")

    @editor = SequenceEditor.new(@rd)

    @chromatograms = Chromatograms.new(@rd)
    @chromatograms.bw = $conf['editor_bw']
    @start_dex = @rd.start_dex
    @end_dex = @rd.end_dex
    @hadjust = Gtk::Adjustment.new(0, 0, @end_dex - @start_dex, 10, 500, 500)

    @index = 0
    hbox_bar = Gtk::Box.new(:horizontal)

    vbox = Gtk::Box.new(:vertical)
    vbox.pack_start(@button_bar, expand: false)
    vbox.pack_start(@primermap, expand: false)
    vbox.pack_start(Gtk::Separator.new(:horizontal), expand: false)
    vbox.pack_start(@editor, expand: false)

    vbox.pack_start(@chromatograms, expand: true, fill: true)
    vbox.pack_start(@status_bar, expand: false)

    @window.add(vbox)

    @hadj_signal_id = @hadjust.signal_connect('value-changed') { |adj| scroll(adj) }
    @editor.signal_connect('size-allocate') {|widget,alloc| fix_scroll(alloc)}
    @window.signal_connect('delete-event') {|widget, args| bp_exit(args); true}

    @dex_list = @rd.get_dex_list(true)
    @dex_hash = @rd.get_dex_hash(true)

    @dex_hash_minus_inserts = @rd.get_dex_hash_minus_inserts(false)

    @window.add_events(:key_press_mask)
    @window.signal_connect('key-press-event') {|window, event| bp_key_press(event) }

    @editor.assembled_draw.add_events(:button_press_mask)
    @editor.assembled_draw.signal_connect("button-press-event") do |widget, event|
      tmp = @editor.sindex
      tmp += (event.x - 5) / @editor.char_width
      self.set_index(tmp.to_i)
    end

    @editor.standard_draw.add_events(:button_press_mask)
    @editor.standard_draw.signal_connect("button-press-event") do |widget, event|
      tmp = @editor.sindex
      tmp += (event.x - 5) / @editor.char_width
      self.set_index(tmp.to_i)
    end

    @primermap.picture.add_events(:button_press_mask)
    @primermap.picture.signal_connect("button-press-event") do |widget, event|
      tmp = ((event.x - 10) / (widget.window.width - 20)) * (@end_dex - @start_dex)
      tmp = 0 if(tmp < 0)
      tmp = (@end_dex - @start_dex) if(tmp >= @end_dex - @start_dex)
      self.set_index(tmp.to_i)
    end

    #only execute once
    handler_id = @window.signal_connect_after("draw") do |window, event|
      redraw()
      window.signal_handler_disconnect(handler_id) if(handler_id)
      false
    end

    @window.show_all()

    set_index(0)
    @aa_pos = keyloc_aa_hash(RecallConfig['standard.keylocs']).to_a.map{|v| v[0].to_i}.sort
  end

  def bp_mark_as_bad()
    max = -1000000
    min = 1000000

    @chromatograms.windows.each do |win|
      primer = win[0]
      selected_bases = @chromatograms.selected_bases[primer.name]
      if(selected_bases != nil)
        min = (selected_bases.first < min  ? selected_bases.first : min)
        max = (selected_bases.last > max  ? selected_bases.last : max)

        selected_bases.to_a.each do |i|
          primer.ignore[i] = 'L'
        end
      end
    end

    pcd = Gtk::Dialog.new(
      title: "Are you sure?  The bases in the selections will be rebasecalled.",
      parent: @window,
      flags: [:destroy_with_parent],
      buttons: [['Continue', :accept], [Gtk::Stock::CANCEL, :cancel]])
    pcd.child.add(Gtk::Label.new("Are you sure?  The bases in the selections will be rebasecalled."))
    box = Gtk::Box.new(:vertical)
    pcd.child.show_all

    if(pcd.run == Gtk::ResponseType::ACCEPT)
      if(max != -1000000)
        #Rebasecall this part
        BaseCaller.call_bases(@rd, min .. max)
      end

      @chromatograms.windows.each do |win|
        primer = win[0]
        @chromatograms.selected_bases[primer.name] = nil
        @chromatograms.selection[primer.name] = nil
      end
      @rd.get_marks_hash(false) #refresh the marks hash
    end
    pcd.destroy
  end

  def bp_key_press(event) #EventKey
    key = Gdk::Keyval.to_name(event.keyval)

    dex = nil
    if(key == 'Right' and !event.state.control_mask?)
      dex = @index + 1
    elsif(key == 'Left' and !event.state.control_mask?)
      dex = @index - 1
    elsif((key == 'q') and event.state.control_mask?  and event.state.mod1_mask?)
      @magic_mode=!@magic_mode
      @editor.magic_mode = @magic_mode
      @chromatograms.magic_mode = @magic_mode
      dex = @index
    elsif(key == 'End')
      dex = @end_dex - @start_dex
    elsif(key == 'Home')
      dex = 0
    elsif(key == 'Right' and event.state.control_mask?)
      page_size = (@editor.window.width / @editor.char_width)
      dex = @index + ((page_size - 1) - 2)
    elsif(key == 'Left'  and event.state.control_mask?)
      page_size = (@editor.window.width / @editor.char_width)
      dex = @index - ((page_size - 1) - 2)
    elsif((key == 'r' or key == 'R') and event.state.control_mask?) #jump to next marked key location
      #Only include locations from keylocs aminos.  (Need to compenstate for insertions too).
      dex = @index

      while(true)
        dex = @rd.marks.find {|v| v > @start_dex + dex }
        dex = dex - @start_dex if(dex != nil)
        if(dex == nil or (@dex_hash_minus_inserts[dex + @start_dex] != nil and @aa_pos.include?(((@dex_hash_minus_inserts[dex + @start_dex] + 3) / 3.0).to_i)))
          break
        end
      end
      dex = @end_dex - @start_dex if(dex == nil)
    elsif((key == 's' or key == 'S') and event.state.control_mask?) #jump to next marked key location
      @new_aa_pos = @aa_pos.map do |pos|
        [@dex_hash_minus_inserts[(pos * 3) - 3 + @start_dex],
        @dex_hash_minus_inserts[(pos * 3) - 2 + @start_dex],
        @dex_hash_minus_inserts[(pos * 3) - 1 + @start_dex]]
      end
      @new_aa_pos.flatten!
      dex = @dex_hash_minus_inserts[@index + @start_dex]
      dex = @new_aa_pos.find {|v| v > dex }
      dex = @end_dex - @start_dex if(dex == nil)
    elsif((key == 'n' or key == 'N') and event.state.control_mask?) #next mark
      dex = @rd.marks.find {|v| v > @start_dex + @index }
      dex = dex - @start_dex if(dex != nil)
      dex = @end_dex - @start_dex if(dex == nil)
    elsif((key == 'p' or key == 'P') and event.state.control_mask?) #previous mark
      dex = @rd.marks.reverse.find {|v| v < @start_dex + @index }
      dex = dex - @start_dex if(dex != nil)
      dex = 0 if(dex == nil)
    elsif((key == 'e' or key == 'E') and event.state.control_mask?) #find next human edit
      dex = @rd.human_edits.sort{|a,b| a[0].to_i <=> b[0].to_i}.find {|v| v[0].to_i > @start_dex + @index }
      dex = @rd.human_edits.sort{|a,b| a[0].to_i <=> b[0].to_i}.find {|v| true } if(dex == nil)
      dex = dex[0].to_i - @start_dex if(dex != nil)
      dex = @index if(dex == nil)
    elsif((key == 'x' or key == 'X') and event.state.control_mask?) #find next N or stop codon
      i = @start_dex + @index + 1
      i.upto(@end_dex) do |j|
        if(@rd.assembled[j] == 'N' or (@rd.assembled[j] == '-' and @rd.standard[j] != '-') or (@rd.assembled[j] != '-' and @rd.standard[j] == '-'))
          dex = j - @start_dex
          break
        end
      end
    elsif((key == 'm' or key == 'M') and event.state.control_mask?) #find next mixture
      i = @start_dex + @index + 1
      i.upto(@end_dex) do |j|
        if("RYKMSWBDHVN".include?(@rd.assembled[j]))
          dex = j - @start_dex
          break
        end
      end
    elsif(key =~ /^[atgcrykmswbdhvnATGCRYKMSWBDHVN]$/  and !event.state.control_mask?)
      change_base(key.to_s.upcase)
      dex = @index
    elsif(key == 'minus')
      change_base('-')
      dex = @index
    elsif(key == '1' and event.state.control_mask?  and event.state.mod1_mask?)
      screenshot()
    elsif(key == 'F1')
      help()
    else
      #puts key.inspect
    end

    if(dex != nil)
      if(dex < 0)
        set_index(0)
      elsif(dex > @end_dex - @start_dex)
        set_index(@end_dex - @start_dex)
      else
        set_index(dex)
      end
    end

  end

  def change_base(key)
    @rd.add_human_edit(@start_dex + @index, @rd.assembled[@start_dex + @index], key)
    @rd.assembled[@start_dex + @index] = key
  end

  def set_index(i)
    if(i < 0)
      i = 0
    elsif(i > @end_dex - @start_dex)
      i = @end_dex - @start_dex
    end

    dir = nil
    if(@index + 1 == i)
      dir = :forward
    elsif(@index - 1 == i)
      dir = :backward
    end

    @index = i
    @primermap.set_index(i)

    @editor.set_index(i)
    @editor.sindex = @index - ((@editor.window.width / @editor.char_width).floor / 2)

    @chromatograms.set_index(i)
    @chromatograms.set_sindex(i)

    #We block the value-changed signal so we don't repeat the redraws when changing
    #the value
    @hadjust.signal_handler_block(@hadj_signal_id) do
      @hadjust.value = i - ((@editor.window.width / @editor.char_width).floor / 2)
    end

    #Update statusbar
    j = @dex_hash[i + @start_dex]
    avg_qual = @rd.primers.inject(0) {|sum, p| sum += (p.qual[i + @start_dex] != 0) ? p.qual[i + @start_dex] : 0 }
    cov = @rd.primers.inject(0) {|sum, p| sum += (p.qual[i + @start_dex] != 0 ? 1 : 0)}
    if(cov == 0)
      avg_qual = 0
    else
      avg_qual /= cov
    end
    nuc = '' if(!j)
    nuc = @rd.assembled[@dex_list[j - j % 3],1] + @rd.assembled[@dex_list[j - j % 3 + 1],1] + @rd.assembled[@dex_list[j - j % 3 + 2],1] if(j and @dex_list[j - j % 3 + 2] != nil)

    aminos = translate(nuc).join('') if(nuc != '' and nuc != nil)
    percs = ''
    if(@rd.phred_mix_perc and @rd.phred_mix_perc[i + @start_dex] and @rd.phred_mix_perc[i + @start_dex]['A'] != nil)
      percs = "A: #{(@rd.phred_mix_perc[i + @start_dex]['A'] * 100).to_i}%  C: #{(@rd.phred_mix_perc[i + @start_dex]['C'] * 100).to_i}%  G: #{(@rd.phred_mix_perc[i + @start_dex]['G'] * 100).to_i}%  T: #{(@rd.phred_mix_perc[i + @start_dex]['T'] * 100).to_i}%"
    end

    if(@magic_mode)
      message("Base: #{j + 1}\t Absolute Codon: (#{(j / 3) + 1})\tAverage Quality: #{avg_qual}\tCoverage #{cov}\tAmino Acids:  #{aminos}\tMixture Percentages:  #{percs}") if(j != nil)
    else
      if(@hide_aa)
        message("Base: #{j + 1}\t Average Quality: #{avg_qual}\tCoverage #{cov}\t") if(j != nil)
      else
        message("Base: #{j + 1}\t Absolute Codon: (#{(j / 3) + 1})\tAverage Quality: #{avg_qual}\tCoverage #{cov}\tAmino Acids:  #{aminos}") if(j != nil)
      end
    end
    queue_draw()
  end

  def queue_draw()
    @window.queue_draw()
  end

  def scroll(adj)
    @editor.sindex = adj.value.to_i
    @chromatograms.sindex = @editor.sindex +  ((@editor.window.width / @editor.char_width).floor / 2)#?
    queue_draw()
  end

  def fix_scroll(alloc)
    @hadjust.page_size = (alloc.width / @editor.char_width).floor
    @hadjust.lower = -((alloc.width / @editor.char_width).floor / 2)
    @hadjust.upper = @end_dex - @start_dex + 1 + ((alloc.width / @editor.char_width).floor / 2)
    @hadjust.step_increment = 1
    @hadjust.page_increment = @hadjust.page_size - 4
    if(@editor.assembled_draw.realized?)
      set_index(@index)
      queue_draw()
    end
  end


  def message(text)
    @status_bar.pop(0)
    @status_bar.push(0, text)
  end

  def threaded(processing = false)
    if(block_given?)
      #@_w_events = @window.events
      #@window.events = 0
      @window.sensitive = false

      message("Please wait for data to be processed...")
      dlg = nil
      if(processing)
        dlg = Gtk::Dialog.new(
          title: "Processing",
          parent: @window)
        dlg.child.add(Gtk::Image.new(file: "images/" + RecallConfig['gui.processingimage']))
        dlg.show_all
      end

      Thread.new do
        begin
          yield
        rescue
          error($!)
        end

        if(processing and dlg)
          begin
            GLib::Idle.add do
              dlg.destroy()
              false
            end
          rescue

          end
        end

        message("Done")
        #@window.events = @_w_events
        #@window.sensitive = true
      end
    end
  end

  def run()
    while(!@window.destroyed? and not @restarting)
      sleep(0.2)
    end
    $conf.save
  end

  def save_conf
    $conf['editor_bw'] = @editor.bw
    $conf['show_standard'] =  @editor.standard_expander.expanded?
    $conf['show_amino'] = @editor.amino_expander.expanded?
    $conf['show_primermap'] = @primermap.expanded?

    $conf['win_height'] = @window.window.height
    $conf['win_width'] = @window.window.width
    $conf['sh_dir'] = @sh_dir

    if(@window.maximized?)
      $conf['win_maximized'] = true
    else
      $conf['win_maximized'] = false
    end

    $conf.save
  end

  def bp_exit(args)
    seq = @rd.export_seq #Why do we do this, it doesn't look like we use it?
    dex_hash = @rd.get_dex_hash(true)
    stop_codons = []
    if(RecallConfig['quality_checker.check_stop_codons'] == 'true')
      seq_no_insert = ''
      0.upto(@rd.standard.length - 1) do |i|
        if(@rd.assembled[i] != '-' and @rd.standard[i] != '-')
          seq_no_insert += @rd.assembled[i]
        end
      end

      0.upto((seq_no_insert.size / 3) - 1) do |i|
        nuc = seq_no_insert[i * 3, 3]
        if(nuc == 'TGA' or nuc == 'TAA' or nuc == 'TAG' or nuc == 'TRA' or nuc == 'TAR')
          stop_codons.push([i, nuc])
        end
      end
    end

    suspicious = @rd.get_suspicious_human_edits

    save_text = (@rd.qa.mostly_good) ? "Save & Approve" : "Save & Approve (Failed QA checks)"
    pcd = Gtk::Dialog.new(
      title: "Are you sure you wish to exit?",
      parent: @window,
      flags: [:destroy_with_parent],
      buttons: [[save_text, 0], ["Fail Sample", 2], ["Exit without saving", 1], ["Do not Exit", 3]])

    label = Gtk::Label.new("")
    label.set_markup("Current number of mixtures: <span size='large'>#{@rd.mixture_cnt}</span>")
    pcd.child.add(label)

    label = Gtk::Label.new("")
    label.set_markup("Number of changes:  <span size='large'>#{@rd.human_edit_cnt}</span>")
    pcd.child.add(label)

    #Putting the errors into a scrollbox
    scroll_err_win = Gtk::ScrolledWindow.new
    scroll_err_win.hscrollbar_policy = :never
    scroll_err_win.set_size_request(-1, 150)
    vbox_err = Gtk::Box.new(:vertical)
    scroll_err_win.add_with_viewport(vbox_err)
    pcd.child.add(scroll_err_win)
    issues = false

    stop_codons.each do |cod|
      label = Gtk::Label.new("")
      label.set_markup("<span foreground='red' size='large'>There is a stop codon at nucleotide #{(cod[0] * 3) + 1}: #{cod[1]} (#{cod[0] + 1})</span>")
      vbox_err.pack_start(label)
      issues = true
    end

    suspicious.each do |sus|
      if(dex_hash[sus[0].to_i])
        loc = dex_hash[sus[0].to_i] + 1
        label = Gtk::Label.new("")
        label.set_markup("<span foreground='red' size='large'>Suspicious edit at base #{loc} (codon #{((loc - 1) / 3) + 1}), please double check</span>")
        vbox_err.pack_start(label)
        issues = true
      end
    end

    #Show errors:
    if(!@rd.remind_errors.empty?())
      label = Gtk::Label.new("")
      label.set_markup("<span foreground='red' size='large'>Keep in mind that Barcode Agent had found the following errors:</span>")
      vbox_err.pack_start(label, expand: false)
      @rd.remind_errors.each do |e|
        label = Gtk::Label.new("")
        label.set_markup(e)
        vbox_err.pack_start(label, expand: false)
        issues = true
      end
    end

    if(!issues)
      label = Gtk::Label.new("No issues or problems")
      vbox_err.pack_start(label, expand: false)
    end


    pcd.show_all
    response = pcd.run
    pcd.destroy
    if(response == 0)
      if((!@rd.qa.mostly_good and !@rd.remind_errors.empty?()) or !suspicious.empty? )
        #if(@rd.remind_errors.empty?() or suspicious.empty?()) #skip

        xpcd = Gtk::Dialog.new(
          title: "Are you sure?",
          parent: @window,
          flags: [:destroy_with_parent],
          buttons: [['Yes', 0], ["No", 1]])
        xpcd.child.add(Gtk::Label.new("Are you sure?\n"))

        #Putting the errors into a scrollbox
        scroll_err_win = Gtk::ScrolledWindow.new
        scroll_err_win.hscrollbar_policy = :never
        scroll_err_win.set_size_request(-1, 150)
        vbox_err = Gtk::Box.new(:vertical)
        scroll_err_win.add_with_viewport(vbox_err)
        xpcd.child.add(scroll_err_win)

        suspicious.each do |sus|
          if(dex_hash[sus[0].to_i])
            loc = dex_hash[sus[0].to_i] + 1
            label = Gtk::Label.new("")
            label.set_markup("<span foreground='red' size='large'>Suspicious edit at base #{loc} (codon #{((loc - 1) / 3) + 1}), please double check</span>")
            vbox_err.pack_start(label, expand: false)
          end
        end

        #Show errors:
        if(!@rd.remind_errors.empty?())
          @rd.remind_errors.each do |e|
            label = Gtk::Label.new("")
            label.set_markup(e)
            vbox_err.pack_start(label, expand: false)
          end
        end
        xpcd.show_all
        response = xpcd.run
        xpcd.destroy
        if(response == 1)
          return
        end
      end
      @rd.qa.userunviewed=false
      @rd.save
      @gui.tasks.approve_samples(@label, [@sample])
      save_conf()
      @window.destroy
    elsif(response == 1)
      save_conf()
      @window.destroy
    elsif(response == 2) #Fail sample
      @gui.tasks.fail_samples(@label, [@sample])
      save_conf()
      @window.destroy
    elsif(response == 3)
      return
    end
  end

  def bp_delete_primer
    pcd = Gtk::Dialog.new(
      title: "Delete Primers",
      parent: @self,
      flags: [:destroy_with_parent],
      buttons: [['Continue', :accept], [Gtk::Stock::CANCEL, :cancel]])

    pcd.child.add(Gtk::Label.new("Choose a primer to delete"))

    select = Gtk::ComboBoxText.new()
    select.append_text("Delete None")
    @rd.primers.each { |p| select.append_text(p.name) }
    select.active=0

    pcd.child.add(select)
    pcd.show_all
    dp = nil
    if(pcd.run == Gtk::ResponseType::ACCEPT)
      dp = select.active_text
    end
    pcd.destroy

    if(dp)
      threaded(true) do
        @gui.tasks.delete_primer(@label, @sample, dp)
        GLib::Idle.add do
          restart
          false
        end
      end
    end

    @chromatograms.reset_stretch
    queue_draw()
  end

  def bp_change_project
    pcd = Gtk::Dialog.new(
      title: "Choose a project for your sample",
      parent: @window,
      flags: [:destroy_with_parent],
      buttons: [ ['Continue', :accept], [Gtk::Stock::CANCEL, :cancel] ] )

    pcd.child.add(Gtk::Label.new("Choose a project"))

    box = Gtk::Box.new(:horizontal)
    select = Gtk::ComboBoxText.new()
    box.add(Gtk::Label.new(@sample))
    box.add(select)
    type = nil
    type = 'clinical' if($conf['clinical'] == 'true')
    projs = StandardInfo.list(type)

    projs.each do |p|
      select.append_text(p)
    end
    select.append_text("Keep the same")
    select.active=projs.size

    pcd.child.add(box)
    pcd.child.show_all
    if(pcd.run == Gtk::ResponseType::ACCEPT)
      dp = select.active_text
    end
    return if(dp == 'Keep the same')
    @rd.project = dp
    pcd.destroy

    if(dp)
      threaded(true) do
        begin
          @gui.tasks.align_samples_custom([[@sample, dp, @label, []]], false)
        rescue
          puts $!.to_s
          puts $!.backtrace
        end
        @gui.tasks.view_log_custom([[@sample, dp, @label, []]])
        GLib::Idle.add do
          restart
          false
        end
      end
    end
    @chromatograms.reset_stretch

    queue_draw()
  end

  def redraw()
    @primermap.redraw()
    @editor.redraw()
    @chromatograms.redraw()
  end

  def screenshot()
    x, y, width, height, depth = @window.window.geometry()
    pixbuf = nil

    if(RUBY_VERSION =~ /^2/)
      pixbuf = GdkPixbuf::Pixbuf.new(
        colorspace => GdkPixbuf::Colorspace::RGB,
        has_alpha => false,
        bits_per_sample => 8,
        width => width,
        height => height)
      GdkPixbuf::Pixbuf.from_drawable(nil, @window.window, 0, 0, width, height, pixbuf)
    else
      pixbuf = Gdk::Pixbuf.new(Gdk::Pixbuf::ColorSpace::RGB, 0, 8, width, height)
      Gdk::Pixbuf.from_drawable(nil, @window.window, 0, 0, width, height, pixbuf)
    end

    fcd = Gtk::FileChooserDialog.new(
      title: "Save a screenshot",
      parent: @window,
      action: :select_folder,
      buttons: [['Save', :accept], [Gtk::Stock::CANCEL, :cancel]])
    fcd.set_size_request(700, -1)

    if(@sh_dir and @sh_dir != '' and File.exist?(@sh_dir))
      fcd.set_current_folder(@sh_dir)
      fcd.set_filename(@sh_dir)
    end
    dir = ''
    if(fcd.run == Gtk::ResponseType::ACCEPT)
      dir = fcd.filename
      fcd.destroy
    else
      fcd.destroy
      return
    end
    @sh_dir = dir
    #Filename should look like 'sample_loc_time.png'
    dir += "\\#{@sample}_#{@index}_#{Time.now.to_i}.png"

    pixbuf.save(dir, 'png')
  end

  def help()
    pcd = Gtk::Dialog.new(
      title: "Help:",
      parent: @window,
      flags: [:destroy_with_parent],
      buttons: [['Done', :accept]] )
    pcd.child.add(Gtk::Label.new("List of keyboard shortcuts:"))
    pcd.child.add(Gtk::Label.new(""))
    pcd.child.add(Gtk::Label.new("Right Arrow:  Move cursor ahead one base."))
    pcd.child.add(Gtk::Label.new("Left Arrow:  Move cursor back one base."))
    pcd.child.add(Gtk::Label.new("Ctrl-Right:  Move cursor forward one page."))
    pcd.child.add(Gtk::Label.new("Ctrl-Left:  Move cursor back one page."))
    pcd.child.add(Gtk::Label.new("Home:  Move cursor to start of the sequence."))
    pcd.child.add(Gtk::Label.new("End:  Move cursor to end of the sequence."))
    pcd.child.add(Gtk::Label.new("Ctrl-N:  Jump to the next marked base."))
    pcd.child.add(Gtk::Label.new("Ctrl-P:  Jump to the previous marked base."))
    pcd.child.add(Gtk::Label.new("Ctrl-R:  Jump to the next marked key location. (only for supported sequences)"))
    pcd.child.add(Gtk::Label.new("Ctrl-M:  Jump to the next mixture."))
    pcd.child.add(Gtk::Label.new("Ctrl-E:  Cycle between human edits."))
    pcd.child.add(Gtk::Label.new("ATGCRYKMSWBDHVN-:  Edit the base."))
    pcd.child.add(Gtk::Label.new("Ctrl-Shift-1:  Take a screenshot."))

    pcd.child.each { |lab| lab.xalign = 0 if(lab.is_a?(Gtk::Label)) }

    pcd.show_all
    pcd.run
    pcd.destroy
  end

end
