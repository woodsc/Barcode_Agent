=begin
lib/pipelines/default_alignment.rb
Copyright (c) 2007-2023 University of British Columbia

Default alignment processing.
=end

module DefaultAlignmentPipeline
  def default_alignment_process_sample(sample, project, label, msg)
    recall_data = @mgr.get_recall_data(label, sample)

    RecallConfig.set_context(recall_data.project, @user)
    recall_data.qa = QaData.new
    message("#{msg}Cleaning up the primers")
    PrimerFixer.scan_quality(recall_data)
    PrimerFixer.trim(recall_data)
    PrimerFixer.smelt(recall_data)
    PrimerFixer.reject_primers(recall_data)

    message("#{msg}Aligning and assembling")
    Aligner.align(recall_data)

    message("#{msg}Basecalling")
    BaseCaller.call_bases(recall_data)

    message("#{msg}Checking for inserts")
    InsertDetector.fix_inserts(recall_data)
    InsertDetector.fix_deletions(recall_data)
    Aligner.trim_stop_codon(recall_data)

    message("#{msg}Quality Check")
    QualityChecker.check(recall_data)

    recall_data.save
  end

end
