=begin
hla.rb
Copyright (c) 2007-2023 University of British Columbia
=end

require 'lib/project_methods'
require 'lib/addons/svg_export/svg_export.rb'

include SvgExport

class HLAMethods
    @@hla_a_primers = ['AS1F','AS2R','AS3F','AS5F','AS6F','AS7R','AS8R','AS4R']
    @@hla_ba_primers = ['BS10F','BS11R','BS13R','BS2R','BS1F','NEWBF','BNEWF','BS4R','B18R','B18F'] + ['BS10FAB','BS11RA','BS13RAB','BS2RA','BS1FAB']
    @@hla_bb_primers = ['BS10F','BS12F','BS13R','BS3F', 'BS1F', 'BS4R','BNEWF','B18R','B18F'] + ['BS10FAB','BS12FB','BS13RAB','BS3FB','BS1FAB']
    @@hla_ca_primers = ['CS2R','CS9R','CS7R','CS8F','CS1F'] + ['CS2RA','CS9RA','CS7RAB','CS8FAB']
    @@hla_cb_primers = ['CS4R','CS7R','CS8F','CS10F','CS11F'] + ['CS7RAB','CS8FAB','CS10FB','CS11FB']



    def HLAMethods.align_samples_custom_pre(samps)
=begin
        hlasamps = samps.find_all {|s| s[1] == 'HLA' }
        samps.delete_if {|s| s[1] == 'HLA' }

        hlasamps.each do |s|
            a = [s[0] + ".A",'HLA_A',s[2], s[3].find_all {|f| @@hla_a_primers.any?{|p| f.include?("#{s[0]}+#{p}_") } }]
            b = [s[0] + ".BA",'HLA_BA',s[2], s[3].find_all {|f| @@hla_ba_primers.any?{|p| f.include?("#{s[0]}+#{p}_") } }]
            c = [s[0] + ".BB",'HLA_BB',s[2], s[3].find_all {|f| @@hla_bb_primers.any?{|p| f.include?("#{s[0]}+#{p}_") } }]
            d = [s[0] + ".CA",'HLA_CA',s[2], s[3].find_all {|f| @@hla_ca_primers.any?{|p| f.include?("#{s[0]}+#{p}_") } }]
            e = [s[0] + ".CB",'HLA_CB',s[2], s[3].find_all {|f| @@hla_cb_primers.any?{|p| f.include?("#{s[0]}+#{p}_") } }]

            #Fix file names
            a[3].map! {|v| [v, v[v.rindex('/') + 1 .. -1].gsub(/\+/,  ".A+")]  }
            b[3].map! {|v| [v, v[v.rindex('/') + 1 .. -1].gsub(/\+/,  ".BA+")]  }
            c[3].map! {|v| [v, v[v.rindex('/') + 1 .. -1].gsub(/\+/,  ".BB+")]  }
            d[3].map! {|v| [v, v[v.rindex('/') + 1 .. -1].gsub(/\+/,  ".CA+")]  }
            e[3].map! {|v| [v, v[v.rindex('/') + 1 .. -1].gsub(/\+/,  ".CB+")]  }

            samps.push(a) if(a[3] != [])
            samps.push(b) if(b[3] != [])
            samps.push(c) if(c[3] != [])
            samps.push(d) if(d[3] != [])
            samps.push(e) if(e[3] != [])
        end
=end
    end

    def HLAMethods.approve_samples_post(label, samps)
        mgr = Manager.get_manager
        samps.each do |samp|
        #Must create an SVG and put it somewhere.
#            message("Producing HLA B*5701 printouts #{samp}")
            rd = mgr.get_recall_data(label, samp)
            rd.add_abis(mgr.get_abis(label, samp))

            if(rd.project == 'HLA_BA')
                #HLA_BA bases 180 to 215
                hla_labels = Array.new((181 .. 212).to_a.size)
                hla_labels[1] = 'G'
                hla_labels[11] = 'G'
                hla_labels[14] = 'A'
                hla_labels[16] = 'A'
                hla_labels[18] = 'G'
                hla_labels[25] = 'T'
                hla_labels[26] = 'C'
                hla_labels[30] = 'G'

                text = SvgExport.create_svg(rd, 181 .. 212, hla_labels, "#{mgr.user}: #{samp} HLA B*5701 specific locations")

                File.open("#{mgr.maindir}/svg_reports/#{mgr.user}.#{samp}.svg", 'w') do |file|
                    file.puts(text)
                end
            elsif(rd.project == 'HLA_BB')
                #HLA_BB bases 15 to 23?
                hla_labels = Array.new((15 .. 22).to_a.size)
                hla_labels[2] = 'G'
                hla_labels[3] = 'T'

                text = SvgExport.create_svg(rd, 15 .. 22, hla_labels, "#{mgr.user}: #{samp} HLA B*5701 specific locations")

                File.open("#{mgr.maindir}/svg_reports/#{mgr.user}.#{samp}.svg", 'w') do |file|
                    file.puts(text)
                end
            end
        end
    end

    def HLAMethods.custom_marks(data)
        s_first = data.start_dex
        s_last = data.end_dex
        if(data.project == 'HLA_BA')
            data.marks.push(s_first + 130)
            data.marks.push(s_first + 131)
            data.marks.push(s_first + 132)
            data.marks.push(s_first + 135)
        elsif(data.project == 'HLA_BB')
            data.marks.push(s_first + 18)
            data.marks.push(s_first + 35)
            data.marks.push(s_first + 43)
            data.marks.push(s_first + 142)
        end
    end

end

ProjectMethods.classes['HLA'] = HLAMethods
ProjectMethods.classes['HLA_A'] = HLAMethods
ProjectMethods.classes['HLA_BA'] = HLAMethods
ProjectMethods.classes['HLA_BB'] = HLAMethods
ProjectMethods.classes['HLA_CA'] = HLAMethods
ProjectMethods.classes['HLA_CB'] = HLAMethods
