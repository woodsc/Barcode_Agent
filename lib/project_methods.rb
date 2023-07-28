=begin
project_methods.rb
Copyright (c) 2007-2023 University of British Columbia

Project specific methods
=end

class ProjectMethods
    @@classes = Hash.new

    def ProjectMethods.classes
        return @@classes
    end

    #Often used for renaming files
    def ProjectMethods.align_samples_custom_pre(samps)
        samps.map {|s| s[1] }.uniq.each do |c|
            cl = @@classes[c]
            if(cl != nil and cl.singleton_methods.include?('align_samples_custom_pre'))
                cl.align_samples_custom_pre(samps)
            end
        end
    end

    #This method doesn't actually make sense.  If we are approving a group of samples, then we can't just shove them into one
    #project method.
    def ProjectMethods.approve_samples_post(label, samps)
        cl = @@classes[RecallConfig.proj_context.upcase]
        if(cl != nil and cl.singleton_methods.include?('approve_samples_post'))
            cl.approve_samples_post(label, samps)
        end
    end

    def ProjectMethods.adjust_alignment(aligned_data)
        cl = @@classes[RecallConfig.proj_context.upcase]
        if(cl != nil and cl.singleton_methods.include?('adjust_alignment'))
            cl.adjust_alignment(aligned_data)
        end
    end

    def ProjectMethods.custom_marks(data)
        cl = @@classes[RecallConfig.proj_context.upcase]
        if(cl != nil and cl.singleton_methods.include?('custom_marks'))
            cl.custom_marks(data)
        end
    end

    def ProjectMethods.custom_basecalls(data, primer, i, correction, cutoff_a, cutoff_b, mark_cutoff_a, mark_cutoff_b, num, num_marked)
        cl = @@classes[RecallConfig.proj_context.upcase]
        if(cl != nil and cl.singleton_methods.include?('custom_basecalls'))
            return cl.custom_basecalls(data, primer, i, correction, cutoff_a, cutoff_b, mark_cutoff_a, mark_cutoff_b, num, num_marked)
        else
            return true
        end
    end

    #note, this can really only be used to make this more liberal, not more strict..
    def ProjectMethods.custom_basecall_mix_criteria(data, i, cov, std_base, max, max_n, second, second_n, third, third_n)
        cl = @@classes[RecallConfig.proj_context.upcase]
        if(cl != nil and cl.singleton_methods.include?('custom_basecall_mix_criteria'))
            return cl.custom_basecall_mix_criteria(data, i, cov, std_base, max, max_n, second, second_n, third, third_n)
        else
            return false
        end
    end
end


Dir['lib/proj/*'].each do |f|
    require f
end
