=begin
conversions.rb
Copyright (c) 2007-2023 University of British Columbia

Include it in your class to get access to mixture conversions
=end

module SeqConversions
	@@ambig_nucs = {
		'A'=> ['A'],
		'G'=> ['G'],
		'T'=> ['T'],
		'C'=> ['C'],
		'R' => ['A', 'G'].sort,
		'Y' => ['C', 'T'].sort,
		'K' => ['G', 'T'].sort,
		'M' => ['A', 'C'].sort,
		'S' => ['G', 'C'].sort,
		'W' => ['A', 'T'].sort,
		'B' => ['C', 'G', 'T'].sort,
		'D' => ['A', 'G', 'T'].sort,
		'H' => ['A', 'C', 'T'].sort,
		'V' => ['A', 'C', 'G'].sort,
		'N' => ['A', 'C', 'T', 'G'].sort,
    'X' => ['X']}
    @@ambig_nucs.default = ['X']

	def get_mix(bases) #Expects an array
    return @@ambig_nucs.key(bases.sort)
	end

  #Turns the standard.keyloc config string into an amino acid hash
  def keyloc_aa_hash(str)
    hash = {}
    return hash if(str == nil)
    tmp = str.split(',')
    tmp.each do |t|
      l = t.split(':')
      hash[l[0].to_i] = l[1].split('')
    end

    return hash
  end

  #Turns the standard.keyloc config string into a nucleotide hash
  def keyloc_nuc_hash(str)
    hash = {}
    return hash if(str == nil)
    tmp = str.split(',')
    tmp.each do |t|
      l = t.split(':')
      aas = l[1].split('')
      aaloc = l[0].to_i
      #need to convert amino's into a list of nucs
      nucs = [[],[],[]]
      aas.each do |aa|
        if(aa == 'Z')
          nucs = [['A','T','C','G'],['A','T','C','G'],['A','T','C','G']]
          next
        end
        trans = @@aa_hash.select {|k,v| v == aa}
        trans.each do |tr|
          nucs[0] << tr[0][0,1].upcase
          nucs[1] << tr[0][1,1].upcase
          nucs[2] << tr[0][2,1].upcase
        end
      end
      hash[aaloc * 3 - 2] = nucs[0].uniq
      hash[aaloc * 3 - 1] = nucs[1].uniq
      hash[aaloc * 3 - 0] = nucs[2].uniq
    end

    return hash
  end

  # Takes in a mixture and returns an array of bases that the mixture represents
	def get_mix_contents(mix)
	  return @@ambig_nucs[mix.to_s]
	end

  def generate(nuc)
        posa = @@ambig_nucs[nuc[0,1]]
        posb = @@ambig_nucs[nuc[1,1]]
        posc = @@ambig_nucs[nuc[2,1]]

        #if(nuc =~ /[X-]/)
        if(nuc == 'XXX')
            return ['X']
        end
        nuclist = []
        posa.each do |a|
            posb.each do |b|
                posc.each do |c|
                    nuclist.push(a + b + c)
                end
            end
        end
        return nuclist
    rescue StandardError => error
        puts error
        puts nuc
        return nil
    end

    def translate(nuc)
      if(nuc.kind_of?(String))
        return generate(nuc).map{|n| @@aa_hash[n.downcase] }.uniq
      else
        return generate(nuc.join('')).map{|n| @@aa_hash[n.downcase] }.uniq
      end
    end

    #new
    def transition?(nuc1, nuc2)
      return nuc2 == @@nuc_transition[nuc1]
    end



    @@aa_hash = {
      'ttt' => 'F', 'tct' => 'S', 'tat' => 'Y', 'tgt' => 'C',
      'ttc' => 'F', 'tcc' => 'S', 'tac' => 'Y', 'tgc' => 'C',
      'tta' => 'L', 'tca' => 'S', 'taa' => '*', 'tga' => '*',
      'ttg' => 'L', 'tcg' => 'S', 'tag' => '*', 'tgg' => 'W',

      'ctt' => 'L', 'cct' => 'P', 'cat' => 'H', 'cgt' => 'R',
      'ctc' => 'L', 'ccc' => 'P', 'cac' => 'H', 'cgc' => 'R',
      'cta' => 'L', 'cca' => 'P', 'caa' => 'Q', 'cga' => 'R',
      'ctg' => 'L', 'ccg' => 'P', 'cag' => 'Q', 'cgg' => 'R',

      'att' => 'I', 'act' => 'T', 'aat' => 'N', 'agt' => 'S',
      'atc' => 'I', 'acc' => 'T', 'aac' => 'N', 'agc' => 'S',
      'ata' => 'I', 'aca' => 'T', 'aaa' => 'K', 'aga' => 'R',
      'atg' => 'M', 'acg' => 'T', 'aag' => 'K', 'agg' => 'R',

      'gtt' => 'V', 'gct' => 'A', 'gat' => 'D', 'ggt' => 'G',
      'gtc' => 'V', 'gcc' => 'A', 'gac' => 'D', 'ggc' => 'G',
      'gta' => 'V', 'gca' => 'A', 'gaa' => 'E', 'gga' => 'G',
      'gtg' => 'V', 'gcg' => 'A', 'gag' => 'E', 'ggg' => 'G',
    }

    #new
    @@nuc_transition = {
      'A' => 'G',
      'C' => 'T',
      'G' => 'A',
      'T' => 'C'
    }

end
