=begin
sequence.rb
Copyright (c) 2007-2023 University of British Columbia

Adds a complement method to string and array
=end

class String
  def complement!
    self.tr!('ATGCatgc', 'TACGtacg')
    self.reverse!
  end

  def complement
    tmp = self.clone
    tmp.complement!
    return tmp
  end
end

class Array
  def complement!
    self.map! {|v| v.tr!('ATGCatgc', 'TACGtacg'); v }
    self.reverse!
  end

  def complement
    tmp = self.clone
    tmp.complement!
    return tmp
  end
end
