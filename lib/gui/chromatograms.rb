=begin
chromatograms.rb
Copyright (c) 2007-2023 University of British Columbia

Shows the chromatogram of a primer

=end

class Gtk::Widget
  def create_layout(text, colour='black')
    l = self.create_pango_layout("")
    l.markup="<markup><span font_desc='Sans 10.5' foreground='#{colour}'>#{text}</span></markup>"
    return l
  end
end

include SeqConversions

class Chromatograms < Gtk::ScrolledWindow
  attr_accessor :sindex, :width_mult, :height_mult, :height
  attr_accessor :windows, :magic_mode, :vbox
  attr_accessor :bw, :showd, :selected_bases, :selection
  attr_accessor :win_primer_hash

  def initialize(rd)
    super()
    @vbox = Gtk::Box.new(:vertical)
    set_rd(rd)
    @magic_mode = false
    #@selection = nil
    @selecting = false
    @selection = {}
    @selected_bases = {}
    @windows = [] #[[primer, widget, [selection, selected_bases]], ...]
    @sindex = 0
    @index = 0
    @width_mult = $conf['w_stretch']
    @height_mult = $conf['h_stretch']
    @height = 145
    @char_width = 23 #13
    @primer_heights = Hash.new
    @primer_stretches = Hash.new
    @primer_hide_curves = Hash.new
    @bw = false
    @showd = true
    @win_primer_hash = {}
    @saved_paths = {}  #[primer.id, widget, NUC] = path

    @rd.primers.each do |p|
      win = Gtk::DrawingArea.new()
      win.set_size_request(-1, @height)
      #win.double_buffered=false
      @win_primer_hash[win] = p
      @windows.push([p, win])
      @vbox.pack_start(win, expand: false)
      max = 0
      i = 0

      p.primer_start.upto(p.primer_end) do |i|
        next if(p.ignore[i] == 'L')
        max = p.abi.atrace[p.loc[i]] if(p.abi.atrace[p.loc[i]] > max)
        max = p.abi.ctrace[p.loc[i]] if(p.abi.ctrace[p.loc[i]] > max)
        max = p.abi.ttrace[p.loc[i]] if(p.abi.ttrace[p.loc[i]] > max)
        max = p.abi.gtrace[p.loc[i]] if(p.abi.gtrace[p.loc[i]] > max)
      end

      @primer_heights[p.name] = max
      @primer_hide_curves[p.name] = {'A' => true, 'T' => true, 'G' => true, 'C' => true}

      reset_stretch()

      win.signal_connect("draw") do |widget, context|
        if(@showd)
          draw_chromatogram(widget, context)
        end
      end

      win.add_events(:button_press_mask)
      win.add_events(:button_release_mask)
      win.add_events(:pointer_motion_mask)

      win.signal_connect("button-press-event") do |widget, event|
        next if(event.button != 1)
        if(event.x < 24 and event.y < 24)
          btn_chromatogram_info(p, widget)
        else
          @selection[p.name] = [p, event.x,event.y,event.x,event.y]
          @selecting = true
          widget.queue_draw_area(0, 0, widget.window.width, widget.window.height)
        end
      end

      win.signal_connect("motion-notify-event") do |widget, event|
        if(@selecting and @selection[p.name])
          @selection[p.name][3] = event.x
          @selection[p.name][4] = event.y
          widget.queue_draw_area(0, 0, widget.window.width, widget.window.height)
        end
      end

      win.signal_connect("button-release-event") do |widget, event|
        if(@selecting and @selection[p.name])
          @selection[p.name][3] = event.x
          @selection[p.name][4] = event.y
          @selecting = false

          @selection[p.name][2] = 0
          @selection[p.name][4] = @height
          if(@selection[p.name][3] < @selection[p.name][1])
            tmp = @selection[p.name][1]
            @selection[p.name][1] = @selection[p.name][3]
            @selection[p.name][3] = tmp
          end

          drift = 0
          while(p.loc[@sindex + @start_dex - drift] == 0)
            drift += 1
          end

          size = [widget.window.width, widget.window.height]

          #Define the selected bases..
          findex = first_elem(p, size)

          center_px = get_loc(:center, size)
          center_loc = (p.loc[@sindex + @start_dex - drift] * @width_mult)

          #Now, from the first index, find out what was selected.
          floc = ((center_loc - center_px) / @width_mult) + (@selection[p.name][1]/@width_mult) - (@char_width / 4)# + mod_loc
          eloc = ((center_loc - center_px) / @width_mult) + (@selection[p.name][3]/@width_mult) - (@char_width / 4)# + mod_loc

          sindex = -1
          eindex = -1
          findex.upto(p.called.size - 1) do |i|
            sindex = i if(p.loc[i] > floc and sindex == -1)
            eindex = i if(p.loc[i] > eloc and eindex == -1)
            break if(eindex != -1)
          end

          @selection[p.name][1] = ((p.loc[sindex] - ((center_loc - center_px) / @width_mult)) * @width_mult) - (@char_width / 4)
          @selection[p.name][3] = ((p.loc[eindex] - ((center_loc - center_px) / @width_mult)) * @width_mult) + (@char_width / 2)

          @selected_bases[p.name] = sindex .. eindex

          widget.queue_draw_area(0, 0, widget.window.width, widget.window.height)
        end
      end #end selection event

    end #end primer loop

    @cached_layouts = {}
    '-ATGCRYKMSWNBDHV'.split('').each do |lc|
      @cached_layouts[[lc,lc]] = @windows[0][1].create_layout(lc, $text_colours[lc]) if(@windows[0] != nil)
      @cached_layouts[[lc,'-']] = @windows[0][1].create_layout(lc, $text_colours['-'])  if(@windows[0] != nil)
    end

    # Assuming @vbox is your existing Gtk::Box
    spacer = Gtk::Box.new(:vertical)
    spacer.expand = true
    @vbox.pack_end(spacer, expand: true)

    self.set_policy(:never, :always)
    self.add(@vbox)

    self.show_all
  end

  def set_rd(rd)
    @rd = rd
    @start_dex = @rd.start_dex
    @end_dex = @rd.end_dex
    @dex_list = @rd.get_dex_list(true)
  end


  def btn_chromatogram_info(p, widget)
    pcd = Gtk::Dialog.new(
      title: "#{p.name}",
      parent: @self,
      flags: [:destroy_with_parent],
      buttons: [['Done', :accept]])

    outerbox = Gtk::Box.new(:vertical, 20)
    outerbox.set_border_width(10)
    hbox = Gtk::Box.new(:horizontal, 20)
    vbox = Gtk::Box.new(:vertical, 5)

    vscale = Gtk::Scale.new(:vertical, 1.0, 5.0, 0.5)
    vscale.value = @primer_stretches[p.name][1]
    vscale.inverted = true

    label = Gtk::Label.new()
    label.markup = "<span font='Arial 12'>Stretch Factor</span>"

    outerbox.pack_start(label, expand: false)
    hbox.pack_start(vscale)
    hbox.pack_start(vbox)
    outerbox.pack_start(hbox, expand: true)

    pcd.child.pack_start(outerbox)

    vscale.signal_connect('value-changed', p) do |scale, primer|
      value = scale.value
      @primer_stretches[primer.name][1] = value
      widget.queue_draw_area(0, 0, widget.window.width, widget.window.height)
    end

    acheck = Gtk::CheckButton.new('Hide A curve')
    ccheck = Gtk::CheckButton.new('Hide C curve')
    tcheck = Gtk::CheckButton.new('Hide T curve')
    gcheck = Gtk::CheckButton.new('Hide G curve')

    acheck.active = false if(@primer_hide_curves[p.name]['A'])
    ccheck.active = false if(@primer_hide_curves[p.name]['C'])
    tcheck.active = false if(@primer_hide_curves[p.name]['T'])
    gcheck.active = false if(@primer_hide_curves[p.name]['G'])

    acheck.signal_connect('toggled', p) do |tog, primer|
      @primer_hide_curves[primer.name]['A'] = !tog.active?
      widget.queue_draw_area(0, 0, widget.window.width, widget.window.height)
    end
    ccheck.signal_connect('toggled', p) do |tog, primer|
      @primer_hide_curves[primer.name]['C'] = !tog.active?
      widget.queue_draw_area(0, 0, widget.window.width, widget.window.height)
    end
    tcheck.signal_connect('toggled', p) do |tog, primer|
      @primer_hide_curves[primer.name]['T'] = !tog.active?
      widget.queue_draw_area(0, 0, widget.window.width, widget.window.height)
    end
    gcheck.signal_connect('toggled', p) do |tog, primer|
      @primer_hide_curves[primer.name]['G'] = !tog.active?
      widget.queue_draw_area(0, 0, widget.window.width, widget.window.height)
    end

    vbox.pack_start(acheck)
    vbox.pack_start(ccheck)
    vbox.pack_start(tcheck)
    vbox.pack_start(gcheck)

    pcd.signal_connect('response') { pcd.destroy }
    pcd.show_all
  end

  def set_index(i)
    @index = i

    @windows.each do |win|
      @selection[win[0].name] = nil
      @selected_bases[win[0].name] = nil
    end
    @selecting = false
    redraw()
  end

  def set_sindex(i)
    @sindex = i
    @windows.each do |win|
      @selection[win[0].name] = nil
      @selected_bases[win[0].name] = nil
    end
    @selecting = false
    redraw()
  end

  #:start loc, :center
  def get_loc(type, size)
    center = (size[0] / 2) - (@char_width / 2)

    if(type == :center)
      return center
    elsif(type == :start) #always negative or 0
      first = 0
      return first.to_i
    elsif(type == :last)
      last =  (size[0] - (center % @char_width)) + (@char_width)
      return last.to_i
    end
  end

  def first_elem(primer, size)
    drift = 0

    while(primer.loc[@sindex + @start_dex - drift] == 0)
      drift += 1
    end

    start_px = get_loc(:start, size)
    center_px = get_loc(:center, size)
    center_loc = (primer.loc[@sindex + @start_dex - drift] * @width_mult).to_i
    first_loc = center_loc - center_px + start_px

    elems = (center_px / 14) / @width_mult

    findex = (@index + @start_dex - drift - elems).to_i

    while((primer.loc[findex] * @width_mult > first_loc or primer.loc[findex] == 0) and findex > primer.primer_start(true))
      findex -= 1
    end

    return findex
  end

  def last_elem(primer, size)
    drift = 0
    while(primer.loc[@sindex + @start_dex - drift] == 0)
      drift += 1
    end

    last_px = get_loc(:last, size)
    center_px = get_loc(:center, size)
    center_loc = (primer.loc[@sindex + @start_dex - drift] * @width_mult).to_i
    last_loc = center_loc + center_px + @char_width

    elems = ((center_px / 14) / @width_mult).to_i

    lindex = @index + @start_dex - drift + elems

    while(lindex < primer.primer_end(true) and primer.loc[lindex] * @width_mult < last_loc)
      lindex += 1
    end

    return lindex
  end

  def reset_stretch
    @rd.primers.each do |p|
      @primer_stretches[p.name] = [$conf['w_stretch'], $conf['h_stretch']]
    end
  end


  def draw_chromatogram(widget, context)
    window = widget.window
    primer = @win_primer_hash[widget]

    size = [window.width, window.height]
    win_width = window.width
    win_height = window.height

    @width_mult, @height_mult = @primer_stretches[primer.name]

    #not sure this is working...
    context.set_source_rgb(*$conf['background_colour'])
    context.rectangle(0, 0, win_width, win_height)
    context.fill

    #sindex is center, find first element you can display
    drift = 0
    while(primer.loc[@sindex + @start_dex - drift] == 0)
      drift += 1
    end

    start_px = get_loc(:start, size)
    center_px = get_loc(:center, size)
    last_px = get_loc(:last, size)
    center_loc = (primer.loc[@sindex + @start_dex - drift] * @width_mult)
    first_loc = center_loc - center_px
    last_loc = center_loc + center_px + @char_width

    findex = first_elem(primer, size)
    lindex = last_elem(primer, size)
    draw_loc = nil
    loc = 0

    #Find trim locations go from there.
    start_trim = primer.primer_start(true) > @start_dex ? primer.loc[primer.primer_start(true)] : primer.loc[@start_dex]
    end_trim = primer.primer_end(true) < @end_dex ? primer.loc[primer.primer_end(true)] : primer.loc[@end_dex]

    start_trim = ((start_trim * @width_mult) - first_loc) - 5
    end_trim = ((end_trim * @width_mult) - first_loc) + 5

    #draw grey background where the trim cuts off.
    context.set_source_rgb(*$colours['light grey'])
    if(start_trim > 0)
      context.rectangle(0, 0, start_trim, win_height)
      context.fill
    end
    if(end_trim < size[0])
#      window.draw_rectangle(gc, true, end_trim, 0, size[0], size[1])
      context.rectangle(end_trim, 0, win_width, win_height)
      context.fill
    end

    ignores = []
    primer.ignore[findex .. lindex].each_with_index do |a, i|
      ignores.push(findex + i) if(a == 'L')
    end

    #draw grey backgrounds for ignore/low quality locations
    ignores.compact_ranges.each do |range|
      if(range.class != Range)
        st = 0
        range.downto(0) do |i| #goes backwards if the location isn't valid
          st = (primer.loc[i] * @width_mult) - first_loc
          break if(primer.loc[i] != 0)
        end

        if(primer.loc[range + 1] != 0)
          ed = ((primer.loc[range + 1] * @width_mult) - first_loc) - st
        else
          ed = 10
        end
        if(range <= findex)
          ed += st - 5
          st = 5
        end
        if(range >= lindex)
          ed = size[0]
        end
        next if(ed - 5 < 0)

        context.set_source_rgb(*$colours['light grey'])
        context.rectangle(st - 5, 0, ed - 5, win_height)
        context.fill
      elsif(range.class == Range)
        st = (primer.loc[range.begin] * @width_mult) - first_loc
        ed = ((primer.loc[range.end] * @width_mult) - first_loc)  - st
        if(range.begin <= findex)
          ed += st - 5
          st = 5
        end

        if(range.end >= lindex)
          ed = size[0]
        end
        next if(ed + 10 < 0)

        context.set_source_rgb(*$colours['light grey'])
        context.rectangle(st - 5, 0, ed + 10, win_height)
        context.fill
      end
    end

    #highlight current locatoin
    if(primer.loc[@index] != nil)
      loc = (primer.loc[@index + @start_dex] * @width_mult) - first_loc - 5

      context.set_source_rgb(*$colours['off white'])
      context.rectangle(loc - 10, 0, @char_width + 10, win_height)
      context.fill

      #gc.rgb_fg_color=$colours['off white']
      #gc.function=Gdk::GC::AND
      #window.draw_rectangle(gc, true, loc - 10, 0, @char_width + 10, size[1])
    end
    #gc.function=Gdk::GC::COPY

    #scan region for 010101010 patterns to know if you should label it as dyeblobs?
    #1 pass, just interate, marking when a pattern starts and when a pattern ends.  Store patterns(size > 7) in a list.
    #Then just mark the list.  Technically the list could be built on load, then just display the non-list.
    #Lets do it in place first, then optimize later.
    dyeblob_list = []
    pattern_state = false
    pattern_prev = 0
    pattern_start = -1

    first_loc_m = (first_loc / @width_mult).to_i
    last_loc_m = (last_loc / @width_mult).to_i

    first_loc_m.upto(last_loc_m - 1) do |i|
      if(pattern_state and primer.abi.atrace[i] == (1 - pattern_prev))
        pattern_prev = primer.abi.atrace[i]
      elsif(pattern_state)
        pattern_state = false
        dyeblob_list << [pattern_start, i - 1] if( (i - pattern_start) > 7)
      elsif([0,1].include?(primer.abi.atrace[i]))
        pattern_state = true
        pattern_prev = primer.abi.atrace[i]
        pattern_start = i
      end
    end
    if(pattern_state) #close last one.
      pattern_state = false
      dyeblob_list << [pattern_start, last_loc_m] if( (last_loc_m - pattern_start) > 7)
    end

    #draw our dyeblob markers
    if(dyeblob_list.size() > 0)
      context.set_source_rgb(*$colours['lightblue'])
      dyeblob_list.each do |dyeblob|
        cx = ((dyeblob[0] - first_loc_m) * @width_mult) + (((dyeblob[1] - dyeblob[0]) * @width_mult) / 2) - (@char_width * (7 / 4))
        context.rectangle(((dyeblob[0] - first_loc_m) * @width_mult), 70, ((dyeblob[1] - dyeblob[0]) * @width_mult ), 2)
        context.fill
        #window.draw_rectangle(gc, true, ((dyeblob[0] - first_loc_m) * @width_mult), 70, ((dyeblob[1] - dyeblob[0]) * @width_mult ), 2) #size[1]
        c = widget.create_layout("Dyeblob", $colours['lightblue'])
        context.move_to(cx, 50)
        context.show_pango_layout(c)
        #window.draw_layout(gc, ((dyeblob[0] - first_loc_m) * @width_mult) + (((dyeblob[1] - dyeblob[0]) * @width_mult) / 2) - (@char_width * (7 / 4)), 50, c)
        c = widget.create_layout("Removed", $colours['lightblue'])
        context.move_to(cx, 70)
        context.show_pango_layout(c)
        #window.draw_layout(gc, ((dyeblob[0] - first_loc_m) * @width_mult) + (((dyeblob[1] - dyeblob[0]) * @width_mult) / 2) - (@char_width * (7 / 4)), 70, c)
      end
    end

    #END DYEBLOB CODE.

    0.upto(lindex - findex) do |i|
      dex = i + findex

      if(primer.loc[dex] == 0 or dex > @end_dex or dex < @start_dex)
        next
      else
        loc = (primer.loc[dex] * @width_mult) - first_loc
      end

      if(dex - @start_dex == @index)
        draw_loc = loc - 5
      end

      if(@rd.get_marks_hash(true)[dex] == true) #Maybe slow here
        context.set_source_rgb(*$colours['yellow'])
        context.rectangle(loc - 5, 12, 19, 19)
        context.fill
      end

      if(tmp = @rd.human_edits.find{|v| v[0].to_i == dex})
        context.set_source_rgb(*$colours['red'])
        context.rectangle(loc - 5, 29, 19, 3)
        context.fill
      end

      l = @rd.assembled[dex]
      lc = @bw ? '-' : l

      c = @cached_layouts[[l,lc]]
      context.move_to(loc - 3, 15)
      context.show_pango_layout(c)

      if(@magic_mode)
        l = '-'
        l = primer.qual[dex].to_i.to_s if(primer.qual[dex])
        #c = widget.create_layout(l, $text_colours[l])
        c = self.create_pango_layout("")
        c.markup="<markup><span font_desc='Sans 8' foreground='#{$text_colours['black']}'>#{l}</span></markup>"

        context.move_to(loc - 6, 32)
        context.show_pango_layout(c)

        l = '-'
        l = ((primer.uncalled_area[dex].to_f / primer.called_area[dex].to_f) * 100.0).to_i if(primer.uncalled[dex] != '-' and primer.uncalled[dex] != primer.called[dex])
        #c = widget.create_layout(l, $text_colours[l])
        c = self.create_pango_layout("")
        c.markup="<markup><span font_desc='Sans 8' foreground='#{$text_colours['black']}'>#{l}</span></markup>"
        context.move_to(loc - 6, 45)
        context.show_pango_layout(c)
      end

    end

    #Draw out lines
    max = @primer_heights[primer.name]
    mult = (120.0 / max) * @height_mult

    ofs = 0
    if(first_loc < 0)
      ofs = -first_loc
      first_loc = 0
    end

    first_loc_m = first_loc / @width_mult
    last_loc_m = last_loc / @width_mult

    context.set_line_width(1)

    if(@primer_hide_curves[primer.name]['A'])
      x = -@width_mult + (ofs)
      lines = primer.abi.atrace[first_loc_m .. last_loc_m ].map! {|v| [(x += @width_mult), 146 - (v * mult)] }
      lines = [[0,146], [ofs * @width_mult,146]] + lines if(ofs != 0)

      context.set_source_rgb(*$colours['green'])
      context.move_to(0, 146)
      lines.each do |line|
        context.line_to(line[0], line[1])
      end
      context.stroke()
    end

    if(@primer_hide_curves[primer.name]['T'])
      x = -@width_mult + (ofs)
      lines = primer.abi.ttrace[first_loc_m  .. last_loc_m ].map! {|v| [x += @width_mult, 146 - (v * mult)] }
      lines = [[0,146], [ofs * @width_mult,146]] + lines if(ofs != 0)

      context.set_source_rgb(*$colours['red'])
      context.move_to(0, 146)
      lines.each do |line|
        context.line_to(line[0], line[1])
      end
      context.stroke()
    end

    if(@primer_hide_curves[primer.name]['C'])
      x = -@width_mult + (ofs)
      lines = primer.abi.ctrace[first_loc_m  .. last_loc_m ].map! {|v| [x += @width_mult, 146 - (v * mult)] }
      lines = [[0,146], [ofs * @width_mult,146]] + lines if(ofs != 0)

      context.set_source_rgb(*$colours['blue'])
      context.move_to(0, 146)
      lines.each do |line|
        context.line_to(line[0], line[1])
      end
      context.stroke()
    end

    if(@primer_hide_curves[primer.name]['G'])
      x = -@width_mult + (ofs)
      lines = primer.abi.gtrace[first_loc_m .. last_loc_m ].map! {|v| [x += @width_mult, 146 - (v * mult)] }
      lines = [[0,146], [ofs * @width_mult,146]] + lines if(ofs != 0)

      context.set_source_rgb(*$colours['black'])
      context.move_to(0, 146)
      lines.each do |line|
        context.line_to(line[0], line[1])
      end
      context.stroke()
    end

    context.set_line_width(2)

    context.set_source_rgb(*$colours['black'])
    context.move_to(0, 0)
    context.line_to(win_width, 0)

    #Draw cursor
    if(draw_loc != nil)
      context.rectangle(draw_loc - 2, 16, 22, 19)
      context.stroke
    end

    #Primer label
    label = widget.create_pango_layout("")
    label.markup="<markup><span size='small'>#{primer.name} - #{primer.orig_direction.upcase}</span></markup>"
    context.move_to((win_width / 2) - (label.pixel_size[0] / 2), 0)
    context.show_pango_layout(label)

    #Draw Icon
    #New code, but may be different between windows/linux

    $icon_theme = Gtk::IconTheme.default if(!$icon_theme)

    if($icon_theme.has_icon?("preferences-system"))
      $icon_pixbuf = $icon_theme.load_icon("preferences-system", 24, :force_size) if(!$icon_pixbuf)
    else
      $icon_pixbuf = nil
    end

    if(context != nil and $icon_pixbuf != nil)
      context.set_source_pixbuf($icon_pixbuf, 0, 0)
      context.paint
    end

    #draw selection inverted colors
    if(@selection[primer.name])
      x = @selection[primer.name][1] > @selection[primer.name][3] ? @selection[primer.name][3] : @selection[primer.name][1]
      y = @selection[primer.name][2] > @selection[primer.name][4] ? @selection[primer.name][4] : @selection[primer.name][2]
      width = (@selection[primer.name][1] - @selection[primer.name][3]).abs
      height = (@selection[primer.name][2] - @selection[primer.name][4]).abs

      context.set_operator(Cairo::OPERATOR_DIFFERENCE) #invert
      context.set_source_rgb(1, 1, 1) # set source color to white
      context.rectangle(x, y, width, height)
      context.fill
      context.set_operator(Cairo::OPERATOR_OVER) #done invert
    end

  end

  #Hide all un-needed chromatograms, show all needed chromatograms, queue some draws.
  def redraw()
    @showd = false

    @windows.each do |wind|
      primer = wind[0]
      widget = wind[1]
      if(@index + @start_dex >= primer.primer_start(true) and @index + @start_dex <= primer.primer_end(true))
        #if(!widget.visible?)
          widget.show()
          @showd = true
        #end
      end
    end

    @windows.each do |wind|
      primer = wind[0]
      widget = wind[1]

      if(@index + @start_dex >= primer.primer_start(true) and @index + @start_dex <= primer.primer_end(true))
        widget.queue_draw_area(0, 0, widget.window.width, widget.window.height)
      else
        widget.hide
      end
    end
  end

end
