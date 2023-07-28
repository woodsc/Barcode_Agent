=begin
globals.rb
Copyright (c) 2007-2023 University of British Columbia

GUI globals
=end
require 'gtk3'

=begin
$colours = {
  'white' => Gdk::Color.new(65535, 65535, 65535),
  'black' => Gdk::Color.new(0, 0, 0),
  'green' => Gdk::Color.new(256 * 0, 256 * 190, 256 * 0),
  'blue' => Gdk::Color.new(256 * 1, 256 * 1, 256 * 255),
  'lightblue' => Gdk::Color.new(256 * 90, 256 * 210, 256 * 255),
  'red' => Gdk::Color.new(256 * 255, 256 * 1, 256 * 1),
  'orange' => Gdk::Color.new(256 * 255, 256 * 200, 256 * 1),
  'yellow' => Gdk::Color.new(256 * 255, 256 * 255, 256 * 1),
  'off white' => Gdk::Color.new(256 * 255, 256 * 255, 256 * 200),
  'grey' => Gdk::Color.new(256 * 128, 256 * 128, 256 * 128),
  'light grey' => Gdk::Color.new(256 * 230, 256 * 230, 256 * 230),
  'purple' => Gdk::Color.new(256 * 250, 256 * 0, 256 * 250)
}
=end

$colours = {
  'white' => [1, 1, 1],
  'black' => [0,0,0],
  'green' => [0, 0.742, 0],
  'blue' => [0, 0, 1 ],
  'lightblue' => [0.351, 0.820, 1],
  'red' => [1, 0, 0],
  'orange' => [1, 0.781, 0],
  'yellow' => [1, 1, 0],
  'off white' => [1, 1, 0.781],
  'grey' => [0.5, 0.5, 0.5],
  'light grey' => [0.898, 0.898, 0.898],
  'purple' => [0.976, 0, 0.976]
}

$text_colours = {
  'A' => 'forest green',
  'T' => 'red',
  'G' => 'black',
  'C' => 'blue',
  'R' => 'brown',
  'Y' => 'brown',
  'K' => 'brown',
  'M' => 'brown',
  'S' => 'brown',
  'W' => 'brown',
  'B' => 'brown',
  'D' => 'brown',
  'H' => 'brown',
  'V' => 'brown',
  'N' => 'purple',
  'black' => 'black'
}

$text_colours.default = 'black'
