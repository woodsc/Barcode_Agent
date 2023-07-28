=begin
lib/alg/abi_fixer.rb
Copyright (c) 2007-2023 University of British Columbia

Fixes up abi traces, replaces them with patterns.
010101010101010101:  removed dyeblob
=end

require 'lib/recall_config'

class ABIFixer
  #Removes dyeblobs
  #Creates a .clean.abi file.  Does not accept filse already named .cleaned.abi
	def ABIFixer.remove_dyeblobs(abi_filename)
		return if(abi_filename =~ /\.clean\.ab[1i]$/i)

    dyeblob_count = 0

    dyeblob_peak_percentile = RecallConfig['abi_fixer.dyeblob_peak_percentile'].to_f
    dyeblob_peak_cutoff_mult = RecallConfig['abi_fixer.dyeblob_peak_cutoff_mult'].to_f
    dyeblob_clear_extra_pixels = RecallConfig['abi_fixer.dyeblob_clear_extra_pixels'].to_i

    return if(!RecallConfig['abi_fixer.dyeblob_peak_percentile'])
    return if(!RecallConfig['abi_fixer.dyeblob_peak_cutoff_mult'])
    return if(!RecallConfig['abi_fixer.dyeblob_clear_extra_pixels'])
    return if(!RecallConfig['abi_fixer.dyeblob_enabled'])

    atrace = []
    ctrace = []
    gtrace = []
    ttrace = []
    atrace_seek = nil
    ctrace_seek = nil
    gtrace_seek = nil
    ttrace_seek = nil

    bytes = []

    File.open(abi_filename, 'rb') do |file|
      bytes = file.gets(nil)
      file.rewind()
      file.seek(26)
      index_offset = file.read(4).unpack("N")[0]
      order_ind_offset = 0
      trace_ind_offset = [0,0,0,0]
      file.seek(index_offset)
      i = index_offset
      st = 0
      trace_count = 0
      data_count = 0
      while(order_ind_offset == 0 or trace_count != 4)
        buf = file.read(4)
        file.seek(24, IO::SEEK_CUR)
        if(buf == "DATA")
          data_count += 1
          if(data_count >= 9 and data_count <= 12)
            trace_ind_offset[trace_count] = i
            trace_count += 1
          end
          st += 1
        elsif(buf == "FWO_") #Field order, this might actually be important
          order_ind_offset = i
          st += 1
        end
        i += 28
      end

      file.seek(order_ind_offset + 20)
      order = file.read(4).split('')

      j = 0
      order.each do |letter|
        file.seek(trace_ind_offset[j] + 12, 0)
        len, nothing, offset = file.read(12).unpack("NNN")
        file.seek(offset)
        if(letter == 'A')
          atrace_seek = offset #fix
          atrace = file.read(2 * len).unpack("n" * len)
        elsif(letter == 'C')
          ctrace_seek = offset
          ctrace = file.read(2 * len).unpack("n" * len)
        elsif(letter == 'G')
          gtrace_seek = offset
          gtrace = file.read(2 * len).unpack("n" * len)
        elsif(letter == 'T')
          ttrace_seek = offset
          ttrace = file.read(2 * len).unpack("n" * len)
        end
        j += 1
      end
    end

    #Not exactly efficient.
    acutoff = atrace.sort()[(atrace.size() * dyeblob_peak_percentile).to_i] * dyeblob_peak_cutoff_mult
    ccutoff = ctrace.sort()[(ctrace.size() * dyeblob_peak_percentile).to_i] * dyeblob_peak_cutoff_mult
    gcutoff = gtrace.sort()[(gtrace.size() * dyeblob_peak_percentile).to_i] * dyeblob_peak_cutoff_mult
    tcutoff = ttrace.sort()[(ttrace.size() * dyeblob_peak_percentile).to_i] * dyeblob_peak_cutoff_mult

    changes = []

    add_changes = lambda { |v|
      changes << atrace_seek + (v * 2)
      changes << ctrace_seek + (v * 2)
      changes << gtrace_seek + (v * 2)
      changes << ttrace_seek + (v * 2)
    }

    [ [atrace, acutoff], [ctrace, ccutoff], [gtrace, gcutoff], [ttrace, tcutoff], ].each do |d|
      trace = d[0]
      cutoff = d[1]

      state = 0
      0.upto((trace.size() / 2).to_i - 1) do |i| #we divide by two because dye blobs only happen in the first half of the trace data.
        if(trace[i] > cutoff)
          if(state == 0)
            dyeblob_count += 1
            [0, i - dyeblob_clear_extra_pixels].max().upto(i) do |j| #clear pixels
              add_changes.call(j)
            end
          end
          state = 1
          add_changes.call(i)
        else
          if(state == 1)
            i.upto([i + dyeblob_clear_extra_pixels, trace.size()].min()) do |j| #clear pixels
              add_changes.call(j)
            end
          end
          state = 0
        end
      end
    end

    changes.uniq().sort().each_with_index do |chg, dex|
      pck = [(dex % 2)].pack('n') #1,0,1,0,1,0,1,0
      bytes[chg] = pck[0]
      bytes[chg + 1] = pck[1]
    end

    if(dyeblob_count > 0)
      File.open(abi_filename.gsub(/\.ab[1i]$/,'.clean.ab1'), 'wb') do |file|
        file.write(bytes)
      end
    end

    #puts "Dyeblobs found in #{abi_filename.gsub(/.+\//,'')}: #{dyeblob_count}"
  end

  #can we do this?  Might need to double check.
  def ABIFixer.remove_dyeblobs_scf(scf_filename)
		return if(abi_filename =~ /\.clean\.scf$/i)
  end

end
