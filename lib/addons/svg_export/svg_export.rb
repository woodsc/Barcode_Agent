=begin
addons/svg_export/svg_export.rb
Copyright (c) 2007-2023 University of British Columbia

This will export one svg file per base.

=end

module SvgExport
=begin
    def create_svgs(path, samp, width = 160)
        clrhash = {'A' => 'green', 'C' => 'blue', 'T' => 'red', 'G' =>'black', 'N'=>'purple'}
        clrhash.default = 'brown'
        raise "Can not handle null path" if(path == nil)
        raise "Can not handle null sample data" if(samp == nil)

        start_dex = samp.start_dex.to_i
        end_dex = samp.end_dex.to_i
        dex_list = samp.get_dex_list(true)
        marks = samp.get_marks_hash(true)

        0.upto(end_dex - start_dex) do |index|
#            puts index
            text = ""
#            text += '<?xml version="1.0" standalone="no"?>'
#            text += '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">'

            primers = samp.primers.find_all { |p| (index + start_dex >= p.primer_start(true) and index + start_dex <= p.primer_end(true)) }

            text += "<svg width='#{width}' height='#{ 200 * primers.size}' version='1.1' xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink'>"

            text += "<rect x='#{(width / 2) - 15}' y='0' width='30' height='#{200 * primers.size}' stroke='none' fill='#ffffc8'/>"

            primers.each_with_index do |p, pi|
                mypatha = ''
                mypathc = ''
                mypathg = ''
                mypatht = ''
                mod = 0
                mod -=1 while(p.loc[index + start_dex + mod] == '-')

                first_loc = p.loc[index + start_dex + mod] - (width / 4)
                last_loc = p.loc[index + start_dex + mod] + (width / 4)

                #Draw recall calls
                (index - 10).upto(index + 10) do |i|
                    if(i >= 0 and i <= (end_dex - start_dex) and
                        p.loc[i + start_dex] != '-' and
                        p.loc[i + start_dex] > first_loc and
                        p.loc[i + start_dex] < last_loc)

                        if(marks[i + start_dex] == true)
                            text += "<rect x='#{(((p.loc[i + start_dex]) - first_loc) * 2) - 6}' y='#{(200 * pi) + 18}' width='14' height='15' stroke='none' fill='yellow'/>"
                        end

                        text += "<text x='#{(((p.loc[i + start_dex]) - first_loc) * 2) - 3}' y='#{(200 * pi) + 30}' fill='#{clrhash[samp.assembled[i + start_dex,1][0]]}' >#{samp.assembled[i + start_dex,1][0]}</text>"
                    end
                end

                #Draw quality (Green for good, yellow for med, red for bad?)

                (index - 10).upto(index + 10) do |i|
                    if(i >= 0 and i <= (end_dex - start_dex) and
                        p.loc[i + start_dex] != '-' and
                        p.loc[i + start_dex] > first_loc and
                        p.loc[i + start_dex] < last_loc and
                        p.ignore[i + start_dex,1][0] == 'L')
                        text += "<text x='#{(((p.loc[i + start_dex]) - first_loc) * 2) - 3}' y='#{(200 * pi) + 45}' fill='red' >!</text>"
                    end
                end

                #Draw Chromatograms
                0.upto(width / 2) do |i|
                    mypatha += "#{i * 2} #{(200 * (pi + 1)) - p.abi.atrace[first_loc + i] / 14} "
                    mypathc += "#{i * 2} #{(200 * (pi + 1)) - p.abi.ctrace[first_loc + i] / 14} "
                    mypathg += "#{i * 2} #{(200 * (pi + 1)) - p.abi.gtrace[first_loc + i] / 14} "
                    mypatht += "#{i * 2} #{(200 * (pi + 1)) - p.abi.ttrace[first_loc + i] / 14} "
                end

                text += "<path d='M 0 #{200 * (pi + 1)} L #{mypatha}' fill='none' stroke='green' stroke-width='1'/>"
                text += "<path d='M 0 #{200 * (pi + 1)} L #{mypathc}' fill='none' stroke='blue' stroke-width='1'/>"
                text += "<path d='M 0 #{200 * (pi + 1)} L #{mypathg}' fill='none' stroke='black' stroke-width='1'/>"
                text += "<path d='M 0 #{200 * (pi + 1)} L #{mypatht}' fill='none' stroke='red' stroke-width='1'/>"

                #Draw primer id Label
                text += "<text x='5' y='#{200 * (pi) + 15}' fill='black' >#{p.primerid}</text>"

            end

            text += "</svg>"

            File.open("#{path}/#{index}.svg",'w') do |file|
                file.puts text
            end
        end
    end
=end

    def create_svg(samp, bases, labels, title)
        width = (bases.last - bases.first + 0) * 25 #This will need to be dynamic?
        clrhash = {'A' => 'green', 'C' => 'blue', 'T' => 'red', 'G' =>'black', 'N'=>'purple'}
        clrhash.default = 'brown'

        start_dex = samp.start_dex.to_i
        end_dex = samp.end_dex.to_i
        dex_list = samp.get_dex_list(true)
        marks = samp.get_marks_hash(true)

        primers = samp.primers.find_all { |p| (bases.first + start_dex >= p.primer_start(true) and bases.last + start_dex <= p.primer_end(true)) }
        width = primers.map {|p|
            mod = 0
            mod -=1 while(p.loc[bases.first + start_dex + mod] == '-')
            p.loc[bases.last + start_dex + mod + 1] - first_loc = p.loc[bases.first + start_dex + mod - 1]
        }.max * 2 + 10
        width = 300 if(width < 300)
        text = ''

        text += "<svg width='#{width}' height='#{45 + (150 * primers.size)}' version='1.1' xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink'>"
        text += "<text x='10' y='20' font-weight='bold' fill='black'>#{title}</text>" if(title != nil)

        bases.each do |b|
#            text += "<text x='#{(b - bases.first) * 26 + 10}' y='17' fill='black' >#{b}</text>"
            tmpp = samp.primers.find { |p| (b + start_dex >= p.primer_start(true) and b + start_dex <= p.primer_end(true)) }
            mod = 0
            mod -=1 while(tmpp.loc[bases.first + start_dex + mod] == '-')
            firstloc = tmpp.loc[bases.first + start_dex + mod - 1]
            loc = (((tmpp.loc[b + start_dex]) - firstloc) * 2) - 3
            #assembled
            #text += "<text x='#{loc}' y='40' fill='#{clrhash[samp.assembled[b + start_dex,1][0]]}' >#{samp.assembled[b + start_dex,1][0]}</text>"
            #labels
            text += "<text x='#{loc}' y='40' font-weight='bold' fill='#{clrhash[labels[b - bases.first]]}' >#{labels[b - bases.first]}</text>" if(labels != nil)
        end

        primers.each_with_index do |p, pi|
#            index = bases.first + (bases.last - bases.first / 2).to_i
            mypatha = ''
            mypathc = ''
            mypathg = ''
            mypatht = ''
            mod = 0
            mod -=1 while(p.loc[bases.first + start_dex + mod] == '-')

            first_loc = p.loc[bases.first + start_dex + mod - 1]# - (width / 4)
            last_loc = p.loc[bases.last + start_dex + mod + 1]# + (width / 4)

            #Draw recall calls
            bases.each do |i|
                if(i >= 0 and i <= (end_dex - start_dex) and
                    p.loc[i + start_dex] != '-' and
                    p.loc[i + start_dex] > first_loc and
                    p.loc[i + start_dex] < last_loc)

                    if(marks[i + start_dex] == true)
                        text += "<rect x='#{(((p.loc[i + start_dex]) - first_loc) * 2) - 6}' y='#{(150 * pi) + 18 + 45}' width='14' height='15' stroke='none' fill='yellow'/>"
                    end

                    text += "<text x='#{(((p.loc[i + start_dex]) - first_loc) * 2) - 3}' y='#{(150 * pi) + 30 + 45}' fill='#{clrhash[samp.assembled[i + start_dex,1][0]]}' >#{samp.assembled[i + start_dex,1][0]}</text>"
                end
            end

                #Draw quality (Green for good, yellow for med, red for bad?)

            bases.each do |i|
                if(i >= 0 and i <= (end_dex - start_dex) and
                    p.loc[i + start_dex] != '-' and
                    p.loc[i + start_dex] > first_loc and
                    p.loc[i + start_dex] < last_loc and
                    p.ignore[i + start_dex,1][0] == 'L')
                    text += "<text x='#{(((p.loc[i + start_dex]) - first_loc) * 2) - 3}' y='#{(150 * pi) + 45 + 45}' fill='red' >!</text>"
                end
            end

            #Draw Chromatograms
            0.upto(width / 2) do |i|
                mypatha += "#{i * 2} #{(150 * (pi + 1)) - p.abi.atrace[first_loc + i] / 16 + 45} " if(p.abi.atrace[first_loc + i])
                mypathc += "#{i * 2} #{(150 * (pi + 1)) - p.abi.ctrace[first_loc + i] / 16 + 45} " if(p.abi.ctrace[first_loc + i])
                mypathg += "#{i * 2} #{(150 * (pi + 1)) - p.abi.gtrace[first_loc + i] / 16 + 45} " if(p.abi.gtrace[first_loc + i])
                mypatht += "#{i * 2} #{(150 * (pi + 1)) - p.abi.ttrace[first_loc + i] / 16 + 45} " if(p.abi.ttrace[first_loc + i])
            end

            text += "<path d='M 0 #{150 * (pi + 1) + 45} L #{mypatha}' fill='none' stroke='green' stroke-width='1'/>"
            text += "<path d='M 0 #{150 * (pi + 1) + 45} L #{mypathc}' fill='none' stroke='blue' stroke-width='1'/>"
            text += "<path d='M 0 #{150 * (pi + 1) + 45} L #{mypathg}' fill='none' stroke='black' stroke-width='1'/>"
            text += "<path d='M 0 #{150 * (pi + 1) + 45} L #{mypatht}' fill='none' stroke='red' stroke-width='1'/>"

                #Draw primer id Label
            text += "<text x='5' y='#{150 * (pi) + 15 + 45}' fill='black' >#{p.primerid}</text>"

        end
        text += "</svg>"
        return text
    end

end
