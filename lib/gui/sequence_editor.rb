=begin
sequence_editor.rb
Copyright (c) 2007-2023 University of British Columbia

=end

require 'gtk3'
require 'lib/gui/globals'
require 'lib/conversions'

class Gtk::Widget
  def create_layout(text, colour='black')
    l = self.create_pango_layout("")
    l.markup="<markup><span font_desc='Sans 10.5' foreground='#{colour}'>#{text}</span></markup>"
    l.alignment = :left
    return l
  end

end

include SeqConversions

class SequenceEditor < Gtk::Box
  attr_accessor :char_width, :sindex, :assembled_draw, :standard_draw
  attr_accessor :standard_expander, :amino_expander, :magic_mode, :bw

  def initialize(rd)
    super(:vertical)
    set_rd(rd)

    @hide_aa = RecallConfig['guiconfig.hide_aa'] == 'true'
    @hide_ref = RecallConfig['guiconfig.hide_ref'] == 'true'
    @use_base_num = RecallConfig['guiconfig.use_base_num'] == 'true'

    @sindex = 0
    @magic_mode = false
    @standard_draw = Gtk::DrawingArea.new()
    @standard_draw.set_size_request(-1, 25)
    @standard_sep = Gtk::Separator.new(:horizontal)
    @standard_expander = Gtk::Expander.new("Standard")
    @assembled_draw = Gtk::DrawingArea.new()
    @assembled_draw.set_size_request(-1, 35)
    @amino_draw = Gtk::DrawingArea.new()
    if(@hide_aa)
      @amino_draw.set_size_request(-1, 25)
    else
      @amino_draw.set_size_request(-1, 40)
    end
    @amino_sep = Gtk::Separator.new(:horizontal)
    @amino_expander = nil
    if(@use_base_num)
      @amino_expander = Gtk::Expander.new("Base #")
    else
      @amino_expander = Gtk::Expander.new("Codon #")
    end
    @char_width = 23 #23 orig
    @index = 0
    @bw = false

    @standard_expander.add(@standard_draw)
    @amino_expander.add(@amino_draw)

    self.pack_start(@amino_expander, expand: false)
    self.pack_start(@amino_sep, expand: false)
    if(!@hide_ref)
      self.pack_start(@standard_expander, expand: false)
      self.pack_start(@standard_sep, expand: false)
    end
    self.pack_start(@assembled_draw, expand: false)

    @amino_labels = RecallConfig['finisher.amino_labels']
    @amino_labels = @amino_labels.split(',') if(@amino_labels != nil)

    @amino_expander.expanded = $conf['show_amino']
    @standard_expander.expanded = $conf['show_standard']

    @standard_draw.signal_connect("draw") do |window, context|
      draw_standard(context)
    end

    @assembled_draw.signal_connect("draw") do |window, context|
      draw_assembled(context)
    end

    @amino_draw.signal_connect("draw") do |window, context|
      draw_amino(context)
    end

    self.show_all
  end

  def set_rd(rd)
    @rd = rd
    @start_dex = @rd.start_dex
    @end_dex = @rd.end_dex

    @dex_list = @rd.get_dex_list(true)
    @dex_hash = @rd.get_dex_hash_minus_inserts(true)
    @dex_hash_abs = @rd.get_dex_hash(true)
  end

  def set_index(i)
    @index = i
  end

  def set_sindex(i)
    @sindex = i
  end

  #:start loc, :center
  def get_loc(type)
    win_width = @assembled_draw.window.width
    center = (win_width / 2) - (@char_width / 2)
    first = ((center % @char_width) - @char_width)
    first = -(@char_width - first) if(first.to_i >= -(@char_width/2).to_i)
    if(type == :center)
      return center.to_i
    elsif(type == :start) #always negative or 0
      return first.to_i
    end
  end

  def draw_standard(context)
    return if(@hide_ref)
    widget = @standard_draw
    window = widget.window
    win_width = window.width
    win_height = window.height

    #draw white background
    context.set_source_rgb(*$colours['white'])
    context.rectangle(0, 0, win_width, win_height)
    context.fill

    start_px = get_loc(:start) + 21  #+12

    #draw cursor rectangle
    loc = (@index - @sindex) * @char_width + start_px - 2
    context.set_source_rgb(*$colours['off white'])
    context.rectangle(loc - 11, 0, @char_width + 10, win_height)
    context.fill

    #Draw each standard nucleotide
    0.upto((win_width / @char_width).to_i) do |i|
      dex = i + @sindex + @start_dex
      next if(dex < @start_dex or dex > @end_dex)
      l = dex > @end_dex ? ' ' : @rd.standard[dex]
      lc = @bw ? '-' : l
      c = widget.create_layout(l, $text_colours[lc])
      context.move_to(i * @char_width + start_px - 1, 2)
      context.show_pango_layout(c)
    end
  end

  def draw_assembled(context)
    widget = @assembled_draw
    window = widget.window
    win_width = window.width
    win_height = window.height

    #draw white background
    context.set_source_rgb(*$colours['white'])
    context.rectangle(0, 0, win_width, win_height)
    context.fill

    #draw cursor rectange
    start_px = get_loc(:start) + 21  #+12
    loc = (@index - @sindex) * @char_width + start_px - 2
    context.set_source_rgb(*$colours['off white'])
    context.rectangle(loc - 11, 0, @char_width + 10, win_height)
    context.fill

    #Draw "Assembled" label
    context.set_source_rgb(*$colours['black'])
    label = widget.create_pango_layout("")
    label.markup="<markup><span font_desc='Sans 10.5'>Assembled - #{@rd.sample}</span></markup>"
    context.move_to((win_width / 2) - (label.pixel_size[0] / 2), 0)
    context.show_pango_layout(label)

    draw_index = nil

    #Each assembled nucleotide
    0.upto((win_width / @char_width).to_i) do |i|
      dex = i + @sindex + @start_dex

      next if(dex < @start_dex or dex > @end_dex)

      #yellow mark highlights
      if(@rd.get_marks_hash(true)[dex] == true)
        context.set_source_rgb(*$colours['yellow'])
        context.rectangle(i * @char_width + start_px - 3, 13, 19, 19)
        context.fill
      end

      #red error highlights
      if(tmp = @rd.human_edits.find{|v| v[0].to_i == dex})
        context.set_source_rgb(*$colours['red'])
        context.rectangle(i * @char_width + start_px - 3, 31, 19, 3)
        context.fill
      end

      #indel highlights
      if(@rd.assembled[dex] != '-' and @rd.standard[dex] == '-')
        context.set_source_rgb(*$colours['lightblue'])
        context.rectangle(i * @char_width + start_px - 2, 10, @char_width + 1, 3)
        context.fill
      end

      #Draw assembled nucleotide
      l = dex > @end_dex ? ' ' : @rd.assembled[dex]
      lc = @bw ? '-' : l
      c = widget.create_layout(l, $text_colours[lc])

      context.move_to(i * @char_width + start_px - 1, 14)
      context.show_pango_layout(c)

      if(dex - @start_dex == @index)
        draw_index = i
      end
    end

    #current position box
    if(draw_index != nil)
      context.set_source_rgb(*$colours['black'])
      context.rectangle(draw_index * @char_width + start_px - 5, 15, 22, 19)
      context.stroke
    end
  end

  def draw_amino(context)
    widget = @amino_draw
    window = widget.window
    win_width = window.width
    win_height = window.height

    #draw white background
    context.set_source_rgb(*$colours['white'])
    context.rectangle(0, 0, win_width, win_height)
    context.fill

    start_px = get_loc(:start) + 21 #+ 12
    loc = (@index - @sindex) * @char_width + start_px - 2

    #off white "cursor" rectangle
    context.set_source_rgb(*$colours['off white'])
    context.rectangle(loc - 11, 0, @char_width + 10, win_height)
    context.fill

    context.set_source_rgb(*$colours['black'])

    if(@use_base_num)  #show nucleotide guidelines

      #draw each nucleotide num
      0.upto((win_width / @char_width).to_i) do |i|
        dex = i + @sindex + @start_dex

        r_dex = @dex_hash[dex]

        if(r_dex != nil) #not an indel?
          clabel = (r_dex.to_i + 1).to_s
          c = widget.create_layout('', $text_colours['black'])
          c.set_markup("<span font_desc='Sans 6'>#{clabel}</span>")
          spot = (@char_width / 2)
          #draw nucleotide index
          if(clabel.size() >= 3) #triple digits need more offset
            context.move_to(i * @char_width + spot + start_px - 17, 1)
          else
            context.move_to(i * @char_width + spot + start_px - 13, 1)
          end
          context.show_pango_layout(c)

          #draw seperator line
          context.move_to(i * @char_width + start_px - 7, 1)
          context.line_to(i * @char_width + start_px - 7, win_height)
          context.stroke
        end
      end


    else #Show amino acid guidelines
      #draw each amino
      0.upto((win_width / @char_width).to_i) do |i|
        dex = i + @sindex + @start_dex

        r_dex = @dex_hash[dex]
        #If frame aligned & not an indel?
        if(r_dex != nil and r_dex % 3 == 0)
          if(@amino_labels == nil)
            c = widget.create_layout(((r_dex / 3).to_i + 1).to_s, $text_colours['black'])
            spot = (@char_width / 2)
            #draw amino acid index
            context.move_to(i * @char_width + spot + start_px - 7, 1)
            context.show_pango_layout(c)
          else
            c = widget.create_layout('', $text_colours['black'])
            c.set_markup("<span font_desc='Sans 10.5'>" + @amino_labels[(r_dex / 3).to_i].to_s + " (#{(r_dex / 3).to_i + 1})</span>" )
            spot = ((@char_width * 3) / 2)
            #draw amino acid label
            context.move_to(i * @char_width + spot + start_px - 7, 1)
            context.show_pango_layout(c)
          end

          #draw amino seperator line
          context.move_to(i * @char_width + start_px - 7, 1)
          context.line_to(i * @char_width + start_px - 7, win_height)
          context.stroke

          r_dex = @dex_hash_abs[dex]
          if(!@hide_aa)
            if(@dex_list[r_dex, 3].size == 3)
              nuc = @rd.assembled[@dex_list[r_dex],1] + @rd.assembled[@dex_list[r_dex + 1],1] + @rd.assembled[@dex_list[r_dex + 2],1]
              aa = translate(nuc).join('')
              aa = aa.length > 6 ? '*' : aa
              c = widget.create_layout(aa, $text_colours['black'])
              #draw amino acid
              context.move_to(i * @char_width + start_px + 2, 20)
              context.show_pango_layout(c)
            end
          end
        #elsif Indel or something
        elsif(r_dex == nil and @dex_hash_abs[dex] != nil and @dex_hash_abs[dex] % 3 == 0)
          r_dex_abs = @dex_hash_abs[dex]
          if(!@hide_aa)
            nuc = @rd.assembled[@dex_list[r_dex_abs - r_dex_abs % 3],1] + @rd.assembled[@dex_list[r_dex_abs - r_dex_abs % 3 + 1],1] + @rd.assembled[@dex_list[r_dex_abs - r_dex_abs % 3 + 2],1]
            aa = translate(nuc).join('')
            aa = aa.length > 6 ? '*' : aa
            c = widget.create_layout(aa, $text_colours['black'])
            context.move_to(i * @char_width + start_px + 2, 20)
            context.show_pango_layout(c)
          end
        end
      end
    end


    #bottom line
    context.move_to(0, 0)
    context.line_to(win_width, 0)
    context.stroke
  end

  def redraw()
    if(@standard_draw.window)
      x, y, width, height = @standard_draw.window.visible_region.extents
      @standard_draw.queue_draw_area(x, y, width, height)
    end
    if(@amino_draw.window)
      x, y, width, height = @amino_draw.window.visible_region.extents
      @amino_draw.queue_draw_area(x, y, width, height)
    end
    if(@assembled_draw.window)
      x, y, width, height = @assembled_draw.window.visible_region.extents
      @assembled_draw.queue_draw_area(x, y, width, height)
    end
  end

end
