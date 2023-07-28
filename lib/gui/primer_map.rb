=begin
primer_map.rb
Copyright (c) 2007-2023 University of British Columbia

Lets users see the primer coverage.

=end

require 'gtk3'
require 'lib/gui/globals'

class PrimerMap < Gtk::Expander
  attr_accessor :picture

  def initialize(rd)
    super('Primer Map')
    set_rd(rd)

    @index = 0
    if($conf['show_primermap'])
      self.set_expanded(true)
    else
      self.set_expanded(false)
    end
    @picture = Gtk::DrawingArea.new
    self.add(@picture)
    @picture.set_size_request(-1, @rd.primers.size * 25 + 30)

    @picture.signal_connect("draw") do |window, context|
      draw_map(context)
    end
  end

  def set_rd(rd)
    @rd = rd
  end

  def set_index(i)
    @index = i
  end

  #called via a draw event
  def draw_map(context)
    win_width = @picture.window.width
    win_height = @picture.window.height

    context.set_source_rgb(*$colours['white'])
    context.rectangle(0, 0, win_width, win_height)
    context.fill

    s_start = @rd.start_dex
    s_end = @rd.end_dex
    s_size = s_end - s_start

    context.set_line_width(2)
    context.set_line_cap(:round)
    context.set_line_join(:miter)

    #draw the standard
    context.set_source_rgb(*$colours['blue'])
    context.move_to(10, 20)
    context.line_to(10 + (win_width - 20), 20)
    context.stroke

    #Draw the label "standard"
    context.set_source_rgb(*$colours['black'])
    context.move_to(17, 2)
    context.show_pango_layout(get_layout("Standard"))

    @rd.primers.each_with_index do |p, i|
      p_start = p.primer_start(true) < s_start ? 0 : p.primer_start(true) - s_start
      p_end = p.primer_end(true) > s_end ? s_size : p.primer_end(true) - s_start
      p_size = p_end - p_start
      dir = p.direction
      stretch = win_width - 20

      s = (p_start.to_f / s_size.to_f) * stretch.to_f
      e = (p_end.to_f / s_size.to_f) * stretch.to_f

      if(dir == 'forward')
        #draw a green line with arrow forward primer
        context.set_source_rgb(*$colours['green'])
        context.move_to(10 + s, i * 25 + 40)
        context.line_to(10 + e, i * 25 + 40)
        context.stroke
        context.move_to(10 + e, i * 25 + 40)
        context.line_to(5 + e, i * 25 + 35)
        context.stroke
        context.move_to(10 + e, i * 25 + 40)
        context.line_to(5 + e, i * 25 + 45)
        context.stroke

        #draw the label "primerid (forward)"
        context.set_source_rgb(*$colours['black'])
        context.move_to(22 + s, i * 25 + 21)
        context.show_pango_layout(get_layout("#{p.name}  (forward)", :left))
      else
        #draw a red line with arrow reverse primer
        context.set_source_rgb(*$colours['red'])
        context.move_to(10 + s, i * 25 + 40)
        context.line_to(10 + e, i * 25 + 40)
        context.stroke
        context.move_to(10 + s, i * 25 + 40)
        context.line_to(15 + s, i * 25 + 35)
        context.stroke
        context.move_to(10 + s, i * 25 + 40)
        context.line_to(15 + s, i * 25 + 45)
        context.stroke

        #draw the label "primerid (reverse)"
        layout = get_layout("#{p.name}  (reverse)")
        #Get the pixel offset so we can right-justify
        right_edge = e - layout.pixel_size[0]
        context.set_source_rgb(*$colours['black'])
        context.move_to(right_edge - 22, i * 25 + 21)
        context.show_pango_layout(layout)
      end
    end

    context.set_source_rgb(*$colours['black'])
    context.set_line_width(1)
    context.set_line_cap(:round)
    context.set_line_join(:miter)
    i = 10 + ((@index.to_f / s_size.to_f) * (win_width - 20))
    context.move_to(i, 0)
    context.line_to(i, win_height)
    context.stroke
  end

  def get_layout(str, align=:center)
    layout = @picture.create_pango_layout(str)
    layout.alignment = align #This is NOT a right justify if you use :right
    return layout
  end

  def redraw
    if(self.expanded? and @picture.window)
      x, y, width, height = @picture.window.visible_region.extents
      @picture.queue_draw_area(x, y, width, height)
    end
  end


end
