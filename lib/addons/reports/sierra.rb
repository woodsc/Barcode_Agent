=begin
sierra.rb
Copyright (c) 2007-2023 University of British Columbia

Ruby interface to the siera lib for the CFE.
Give it an array of sequences and it'll give you an array
of objects with the data returned by sierra.
=end

if(RUBY_VERSION =~ /^1\.8/)
  require 'soap/wsdlDriver'
else
  require 'savon'
end
require 'rexml/document'

#HACK cause ruby sucks
module WSDL
  module SOAP
    module ClassDefCreatorSupport
      def basetype_mapped_class(name)
        # I MAY GO TO HELL FOR THIS HACK
        return name if name == XSD::AnyTypeName
        # END HACK
        ::SOAP::TypeMap[name]
      end
    end
  end
end

class SierraResult
    attr_accessor :label, :alg_version, :success, :nuc_seq
    attr_accessor :has_pr, :has_rt, :has_int
    attr_accessor :pr_subtype, :rt_subtype, :int_subtype
    attr_accessor :pr_muts, :rt_muts, :int_muts
    attr_accessor :pr_other_muts, :rt_other_muts, :int_other_muts
    attr_accessor :drugs, :comments, :error_message, :xml_txt, :alg

    #algorithm is either HIVDB or ANRS

    @@sierra_client = nil
    @@key = 'N9ER-GRK5-QPKG-9S5U'
    @@sierra_res_hash = {
        '1' => 'Susceptible',
        '2' => 'Susceptible',
        '3' => 'Low-level resistance',
        '4' => 'Intermediate resistance',
        '5' => 'High-level resistance'}

    @@anrs_res_hash = {
        '1' => 'Susceptible',
        '2' => 'Possible resistance',
        '3' => 'Resistance'}

    #This is what you call to get your results.  Really its all you need.
    #alg can be ANRS
    def SierraResult.analyze(seq_arr, alg='HIVDB')
        if(!@@sierra_client)
            #puts "Loading"
            if(RUBY_VERSION =~ /^1\.8/)
              @@sierra_client = SOAP::WSDLDriverFactory.new( 'http://db-webservices.stanford.edu:5440/axis/services/StanfordAlgorithm?wsdl' ).create_rpc_driver
            else
              @@sierra_client = Savon.client(:wsdl => 'http://db-webservices.stanford.edu:5440/axis/services/StanfordAlgorithm?wsdl')
            end
        end
        results = []
        alg_version = ''
        xml_txt = ''

        if(alg == 'ANRS')
          tmp = ''
          0.upto(seq_arr.size-1) do |i| #build the fasta
            tmp += ">#{i}\n#{seq_arr[i]}\n"
          end

          if(RUBY_VERSION =~ /^1\.8/) #WSDL DRIVER
            xml_txt = @@sierra_client.processSequencesInFasta_ANRS(@@key, 1, tmp)
          else  #SAVON
            response = @@sierra_client.call(:process_sequences_in_fasta_anrs, :message => {:key => @@key, :report_type_int => 1, :sequences_in_fasta => tmp})
            xml_txt = response.body[:process_sequences_in_fasta_anrs_response][:process_sequences_in_fasta_anrs_return]
          end

        else #HIVDB
          if(RUBY_VERSION =~ /^1\.8/) #WSDL DRIVER
            xml_txt = @@sierra_client.processSequences(@@key, 1, seq_arr)
          else #SAVON
            response = @@sierra_client.call(:process_sequences, :message => {:key => @@key, :report_type_int => 1, :sequence  => { "ArrayOf_xsd_string" => seq_arr }})
            xml_txt = response.body[:process_sequences_response][:process_sequences_return]
          end
        end

        xml = REXML::Document.new(xml_txt, { :compress_whitespace => :all})

        root = xml.elements['Stanford_Algorithm_Interpretation']
        alg_version = root.elements['algorithmVersion'].text
        root.elements.each("success|failure") do |elem|
            res = SierraResult.new
            if(alg == 'ANRS')
              res.alg = 'ANRS'
            else
              res.alg = 'HIVDB'
            end
            res.xml_txt = xml_txt
            res.alg_version = alg_version
            res.success = true if(elem.name == 'success')
            res.nuc_seq = elem.elements['sequence'].text

            if(res.success)
                res.pr_subtype = elem.elements['summary/PR/subtype'].attributes['type'] if(elem.elements['summary/PR/subtype'])
                res.rt_subtype = elem.elements['summary/RT/subtype'].attributes['type'] if(elem.elements['summary/RT/subtype'])
                res.int_subtype = elem.elements['summary/IN/subtype'].attributes['type'] if(elem.elements['summary/IN/subtype'])

                res.has_pr = (elem.elements['summary/PR/present'].text == 'true') ? true : false
                res.has_rt = (elem.elements['summary/RT/present'].text == 'true') ? true : false
                res.has_int = (elem.elements['summary/IN/present'].text == 'true') ? true : false

                #hopefully this works even if there are no mutations.  Check this
                res.pr_muts = elem.elements['PR_mutations/'].map {|e| (e.class.to_s == 'REXML::Text' or e.attributes['classification'] == 'OTHER') ? nil : e.text} if(elem.elements['PR_mutations'])
                res.rt_muts = elem.elements['RT_mutations/'].map {|e| (e.class.to_s == 'REXML::Text' or e.attributes['classification'] == 'OTHER') ? nil : e.text} if(elem.elements['RT_mutations'])
                res.int_muts = elem.elements['IN_mutations/'].map {|e| (e.class.to_s == 'REXML::Text' or e.attributes['classification'] == 'OTHER') ? nil : e.text} if(elem.elements['IN_mutations'])


                res.pr_muts.delete(nil)
                res.rt_muts.delete(nil)
                res.int_muts.delete(nil)

                res.pr_other_muts = elem.elements['PR_mutations/'].map {|e| (e.class.to_s == 'REXML::Text' or e.attributes['classification'] != 'OTHER') ? nil : e.text} if(elem.elements['PR_mutations'])
                res.rt_other_muts = elem.elements['RT_mutations/'].map {|e| (e.class.to_s == 'REXML::Text' or e.attributes['classification'] != 'OTHER') ? nil : e.text} if(elem.elements['RT_mutations'])
                res.int_other_muts = elem.elements['IN_mutations/'].map {|e| (e.class.to_s == 'REXML::Text' or e.attributes['classification'] != 'OTHER') ? nil : e.text} if(elem.elements['IN_mutations'])

                res.pr_other_muts.delete(nil)
                res.rt_other_muts.delete(nil)
                res.int_other_muts.delete(nil)

                res.comments = []
                res.comments = elem.elements['comments/'].map{|e| (e.class.to_s == 'REXML::Text') ? nil : e.text} if(elem.elements['comments/'])
                res.comments.delete(nil)
                drug_order = {'NRTI' => 1,'NNRTI' => 2,'PI' => 3, 'INI' => 4}
                pr_extra = []
                rt_extra = []
                int_extra = []
                res.drugs = elem.elements['drugScores/'].map do |drug|
                    next if(drug.class.to_s == 'REXML::Text')
                    sd = SierraDrug.new
                    sd.code = drug.attributes['code']
                    sd.name = drug.attributes['genericName']
                    sd.cls = drug.attributes['type']
                    sd.level = drug.attributes['levelStanford']
                    sd.res = drug.attributes['levelSIR']
                    if(alg == 'ANRS')
                      sd.res_text = @@anrs_res_hash[sd.level]
                    else
                      sd.res_text = @@sierra_res_hash[sd.level]
                    end

                    if(sd.cls == 'PI')
                      drug.elements.each{|e| pr_extra += e.attributes['mutation'].split(',') } if(drug.elements)
                    elsif(sd.cls == 'NRTI' or sd.cls == 'NNRTI')
                      drug.elements.each{|e| rt_extra += e.attributes['mutation'].split(',') } if(drug.elements)
                    elsif(sd.cls == 'INI')
                      drug.elements.each{|e| int_extra += e.attributes['mutation'].split(',') } if(drug.elements)
                    end
                    #sd.res_text = @@sierra_res_hash[sd.level]
                    sd
                  end

                pr_extra.uniq!
                rt_extra.uniq!
                int_extra.uniq!

                pr_extra.delete_if {|a| res.pr_muts.include?(a)}
                rt_extra.delete_if {|a| res.rt_muts.include?(a)}
                int_extra.delete_if {|a| res.int_muts.include?(a)}

                res.pr_muts += pr_extra
                res.rt_muts += rt_extra
                res.int_muts += int_extra

                res.drugs.delete(nil)
                res.drugs.sort! {|a,b| ( (a.cls != b.cls) ? (drug_order[a.cls] <=> drug_order[b.cls]) : (a.code <=> b.code) )}
            else
                res.error_message = elem.elements['errorMessage'].text
            end
            results.push << res
        end

        return results
    end

    def initialize()
        @label, @alg_version, @success, @nuc_seq = nil, nil, false, nil
        @has_pr, @has_rt, @has_int = nil, nil, nil
        @pr_subtype, @rt_subtype, @int_subtype = nil, nil, nil
        @pr_muts, @rt_muts, @int_muts = [], [], []
        @pr_other_muts, @rt_other_muts, @int_other_muts = [], [], []
        @drugs, @comments, @error_message = nil, nil
        @xml_txt = ''
        @alg = nil
    end

    def to_s()
        str = ''
        str += "Label:  #{@label}\n"
        str += "Algorithm version:  #{@alg_version}\n"
        str += "Success? #{@success}\n"
        if(@success)
            str += "RT?:  #{@has_rt},  PR?:  #{@has_pr}, INT?:  #{@has_int}\n"
            str += "Subtype:  RT:#{@rt_subtype} PR:#{@pr_subtype} INT:#{@int_subtype}\n"
            str += "PR Muts:  #{@pr_muts.join(', ')}\n"
            str += "RT Muts:  #{@rt_muts.join(', ')}\n"
            str += "INT Muts:  #{@int_muts.join(', ')}\n"
            str += "comments:\n  #{@comments.map{|e| "\t#{e}"}.join("\n")}\n"
            str += "Drugs: \n"
            @drugs.each do |d|
                str += "\t#{d.code}\t#{d.name}\t#{d.cls}\t#{d.level}\t#{d.res}\t#{d.res_text}\n"
            end
        else
            str += "Error:  #{@error_message}\n"
        end
        return str
    end
end

class SierraDrug
    attr_accessor :code, :name, :cls, :level, :res, :res_text
end
