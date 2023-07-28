=begin
lib/pipelines/co1_barcode.rb
Copyright (c) 2007-2023 University of British Columbia

Pipeline for the no reference processing.
=end

module NoRefPipeline
  def no_ref_process_sample(sample, project, label, msg)
    recall_data = @mgr.get_recall_data(label, sample)

    RecallConfig.set_context(recall_data.project, @user)
    recall_data.qa = QaData.new
    message("#{msg}Cleaning up the primers")
    PrimerFixer.scan_quality(recall_data)
    PrimerFixer.trim(recall_data)
    PrimerFixer.smelt(recall_data)
    PrimerFixer.reject_primers(recall_data)


    message("#{msg}Aligning")

    if(recall_data.primers.size() > 0)
      #align each other primer to the reference, and then merge the result into
      #the reference iteratively to create a final reference sequence.

      #reference starts as primer 0's called nucleotide sequence
      reference = recall_data.primers[0].called.join('')

      #a place to keep the temporarily aligned data so we can adjust for insertions later.
      aligned_data = []

      #merged_flags is a list of which primers have been merged into the reference.
      merged_flags = [false] * recall_data.primers.size()
      merged_flags[0] = true
      changed = true

      while(changed) #repeat process until no changes to the reference have occured
        changed = false

        1.upto(recall_data.primers.size() - 1) do |pdex|
          next if(merged_flags[pdex]) #skip if its been merged already

          #align
          elem = [reference.split(''), recall_data.primers[pdex].called]
          Aligner.run_alignment(elem)

          #check that there is significant overlap with reference.
          overlap = count_align_overlap(elem[0], elem[1])
          #puts "#{recall_data.primers[pdex].primerid} -> overlap: #{overlap}"
          if(overlap > 60)
            #merge alignment into new reference.
            reference = ''
            0.upto(elem[0].size() - 1) do |i|
              if(elem[0][i] != '-')
                reference += elem[0][i]
              elsif(elem[1][i] != '-')
                reference += elem[1][i]
              else
                puts "error: Invalid merge."
              end
            end

            #mark as merged
            merged_flags[pdex] = true
            changed = true
          end

        end #end primer loop

      end #end while

      #reject bad primers.
      merged_flags.each_with_index do |flag, dex|
        if(!flag)
          recall_data.errors.push("Failing primer #{!recall_data.primers[dex].primerid ? recall_data.primers[dex].name : recall_data.primers[dex].primerid}; can't merge into alignment")
          recall_data.primers[dex] = nil
        end
      end
      recall_data.primers.delete_if {|p| p == nil }


      #Align every primer nucleotide seq to the reference we made
      recall_data.primers.each do |p|
        #align
        elem = [reference.split(''), p.called]
        Aligner.run_alignment(elem)

        aligned_data << elem
      end

      #Align standards to each other(along with the sequence).
  		Aligner.run_alignment_merge(aligned_data) if(aligned_data.size != 0)
      Aligner.correct_alignment(aligned_data) if(aligned_data.size != 0)
      recall_data.standard = aligned_data[0][0] if(aligned_data.size != 0)

      #put aligned_data into the primer.edit variable, and update the other
      #primer variables to account for the new indels
      recall_data.primers.each_with_index do |p, i|
        #assign
        if(!aligned_data[i] || aligned_data[i][0] == nil)
          p.edit = nil
        else
          p.edit = aligned_data[i][1]
        end

        p.edit.each_with_index do |v, j|
  				if(v == '-')
  					p.called.insert(j, '-')
  					p.uncalled.insert(j, '-')
  					p.called_area.insert(j, '-')
  					p.uncalled_area.insert(j, '-')
  					p.loc.insert(j, '-')
  					p.qual.insert(j, '-')
  					p.ignore.insert(j, '-')
            p.amp_a.insert(j, '-')
            p.amp_c.insert(j, '-')
            p.amp_g.insert(j, '-')
            p.amp_t.insert(j, '-')
  				end
  			end
      end

    end

    #end replacement of the alignment algorithm.

    message("#{msg}Basecalling")
    BaseCaller.call_bases(recall_data)

    message("#{msg}Quality Check")
    QualityChecker.check(recall_data)

    recall_data.save
  end

end
