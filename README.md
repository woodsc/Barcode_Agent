# Barcode_Agent

This project provides a tool for automatic basecalling and manual inspection of aligned chromatogram data for Barcode genes like CO1. It is designed for use in academic research.

Please note: while this software is free to use for academic purposes, commercial users must contact the Univerity of British Columbia to purchase a license.

https://uilo.ubc.ca/about-us/contact-us

## Features

- Reads ABI and SCF chromatogram files.
- Automatic sequence alignment from a reference, or without a reference.
- Automatic basecalling and sequence QA.
- Built in visual editor for manually calling bases.

## Table of Contents

1. [Installation](#installation)
2. [Configuration](#configuration)
3. [Usage](#usage)
4. [Support](#support)
5. [License](#license)

## Installation

### Windows

- Install ruby 2.7 or higher with a devkit from https://rubyinstaller.org/ .
  - Choose ("Install only for me") and allow it to install MSYS2.
- Double click on the file Barcode_Agent/windows_setup.rb .  This may take up to an hour.
  - If it pauses with a Y/N question, press enter to continue.
- Put the phred executable at Barcode_Agent/bin/phred.exe .
  - Phred can be obtained at https://www.phrap.com/phred/ .

### Linux

- Install ruby 2.7 or higher (and ruby-dev).
- Install the alignment.gem
```
cd Barcode_agent/bin
gem install alignment_ext-1.0.0.gem
```
- Install gtk2
    `sudo apt-get install libgtk-3-dev`   (for debian based systems)
    `sudo dnf install gtk3-devel`  (for fedora/RHEL/CentOS)
    `sudo pacman -S gtk3`  (for Arch Linux/Manjaro)
    `sudo apt install`
- Put the phred executable at Barcode_Agent/bin/phred_linux_x86_64 .
  - If running 32 bit linux, put it at Barcode_Agent/bin/phred_linux_i686.exe .
  - Phred can be obtained at https://www.phrap.com/phred/ .


## Configuration

Configuration files are kept in Barcode_Agent/config/ .   

### primers.txt

The primers file is what Barcode Agent uses to determine the forward/reverse direction of each chromatogram.  It is formatted like:
```
F forward
R reverse
AFBA forward
AR44 reverse
```
### standards.txt

The standards file is a fasta file containing all your reference sequences.  Each
reference sequence is a **project** which can have its own configuration parameters.  If
a project doesn't require a reference, it should still have an entry here, such as:
```
>no_ref
NNNNNN
```

Reference standards can contain mixture nucleotides for more variable regions.


### Project configuration files

All project files are named as proj_PROJECTNAME.txt .  These must match the references contained in standards.txt.  The file default.txt contains all the default configuration values, while the individual project configuration files will override the default.txt settings.  This means you can generally add just a few configuration changes to the project files.  Comments start with a **#** and nothing will be processed after a **#**.  Below is a list of common configuration settings:

- **common.pipeline**:  Either ==default_alignment== or ==no_ref== if there is no reference sequence for this project.
- **common.autoapprove**:  If set to ==true== then samples will be automatically approved if the data has no errors.
- **tasks.export_lc_edits**:  If set to ==true== then sequence exports will have human edits exported in lowercase letters.  
- **tasks.export_with_dashes**:  If set to ==true== then deletions will be preserved in the exported sequence.
- **aligner.gap_initialization_penalty**:  Sets the alignment algorithms gap init penalty.  
- **aligner.gap_extension_penalty**:  Sets the alignment algorithms gap extend penalty.
- **primer_fixer.trim_quality_cutoff**:  Sets the quality threshold for trimming chromatograms.
- **primer_fixer.primer_min_good**:  Chromatograms will be rejected if the number of good bases dodn't meet this threshold.
- **base_caller.mark_on_single_cov**:  If set to ==true== marks bases with single coverage.  
- **base_caller.mixture_area_percent**:  Calls a mixture if the uncalled base area under the curve of the called base meets this threshold.
- **base_caller.mark_area_percent**:  Marks a base if the uncalled base area under the curve of the called base meets this threshold.
- **base_caller.mark_average_quality_cutoff**:  Marks a base if below a quality threshold.  
- **base_caller.remove_single_cov_inserts**:  If **true** will attempt to remove inserts with single chromatogram coverage.
- **insert_detector.common_insert_points**:  Either `*` or a comma seperated list of nucleotide positions.  If a list, then it will attempt to align insertions near these locations to these locations.   
- **insert_detector.frame_align_deletions**:  If set to  ==true== then it will attempt to frame align  deletions.    
- **quality_checker.check_stop_codons**:  If set to ==true== then QA will have errors if stop codons are found.   
- **quality_checker.check_manymixture**:  If set to ==true== then QA will have errors if too many mixtures are found.   
- **quality_checker.check_manyns**:  If set to ==true== then QA will have errors if too many N's are found.     
- **quality_checker.check_manymarks**:  If set to ==true== then QA will have errors if too many marks  are found.   
- **quality_checker.check_badqualsection**:  If set to ==true== then QA will have errors if a large poor quality section is found.
- **quality_checker.check_manysinglecov**:  If set to ==true== then QA will have errors if single coverage is found  
- **quality_checker.check_hasinserts**:  If set to ==true== then QA will have errors if inserts are found.  
- **quality_checker.check_hasdeletions**:  If set to ==true== then QA will have errors if non-frame aligned deletions are found.   
- **quality_checker.max_single_coverage**:  Acceptable single coverage count threshold.  
- **quality_checker.max_mixtures**:  Acceptable mixture count threshold.
- **quality_checker.max_ns**:  Acceptable N count threshold.
- **quality_checker.max_marks**:  Acceptable mark count threshold.

### Sample/Primer File Syntax

Barcode Agent processes chromatogram files by splitting the filename into samplename and primer values, however many labs use widely varying naming schemes for their files.  Because of this we have three different ways to process filenames.

#### common.sample_primer_delimiter  

The simplest is to set the common.sample_primer_delimiter in the default.txt file.  This cuts the filename in half at a particular character, with everything before the character being the samplename and everything after being the primer name.  For example:

```
common.sample_primer_delimiter=_

#sample01_primer01.ab1:
#sampleid would be "sample01"
#primerid would be "primer01"
```

#### common.sample_primer_syntax

For slightly more complex filenames, such as a file with extra data, you can use the common.sample_primer_syntax.  This lets you parse the filename by section.  

```
common.sample_primer_syntax=%s_%o_%p+%o

#sample01_12-jul-2023_primer01+cap23.ab1
#sampleid would be "sample01"
#primerid would be "primer01"
```

%s, %p, and %o are codes for sample, primer, and other.  This handles most naming systems.

#### common.sample_primer_regexp

For absolute flexibility you can also use common.sample_primer_regexp to parse via regular expressions.  Regular expressions are a computer programming concept used for string parsing, and information on how to use them can be found online.  In our case, the first regular expression group will be the sampleid and the second one will be the primer.

```
common.sample_primer_regexp=^([^_\[]+)[_\[].+_([FR])$
#sample01_REP1[Reuk454FWD1,V4r]_F.ab1
#sampleid would be "sample01"
#primerid would be "F"
#
```  

### Automatic Reference Guessing

Barcode Agent has a feature where you can set up a project to attempt to align your chromatograms to several different project references and then pick the closest matching reference.  This can be done by setting up a project with no reference, and giving it the configuration line:

**common.choose=subproject1,.affix1,subproject2,.affix2,...**

The configuration value should contain a comma separated list of pairs of project names and affixes to add to the sample names.  In the above example, if sample01 aligns to subproject2, it will be renamed as sample01.affix2.  This can help to visually identify which reference was used after sequences have been exported.

## Usage

Execute the barcode_agent.rb to run the application.  Barcode Agent first asks for your initials.  This is used to store individual user preferences and to keep your processed data separate from any other
users using this installation of Barcode Agent.  After entering your initials, the sample management window will open.  From here you can select the **Add Samples** menu option to add chromatograms to a project.  A file dialog will appear and you can select the folder you wish to process.

If everything is set up correctly, it should display a list of your samples in this folder and the number of primers.  You can choose the project you wish to use to process the samples individually, or use the **Change All** drop downs to set them all at once.  After pressing **Continue** it will ask for you to choose a name for this set up samples.  Pick one and **Continue** and Barcode Agent will then process all of your samples.  The status of this is displayed in the status bar at the bottom of the window.

The top-left section of the window displays a list of all your sets of data.  If you click on one of the sets then the bottom-left section of the window will display each of your samples and their status.  
- **Green** samples have been approved by a user (or the system if the `common.autoapprove` configuration variable is set to true.)
- **Orange** samples have no errors but still require a user to inspect some nucleotide positions.
- **Red** samples have errors and either need extensive inspection by a user or need to be rejected.
- **Black** samples have major errors and likely can not be approved.

Double click on a sample to open the sequence finisher and inspect the chromatograms.  This will show the alignment along with the final called sequence.  Bases may be **marked** with a yellow background, which indicates that the base requires a user to confirm the basecall.  This is usually caused by single-coverage, low sequence quality, suspicious mixtures, or indels.  

You can move the current base selection with the arrow keys, or by clicking the base you want to look at, or clicking a location on the primer map.  

- **Ctrl-Right/Left**:  Move the cursor forward 1 page.
- **Home/End**:  Move the cursor to the start or end of the sequence.
- **Ctrl-N & Ctrl-P**:  Move the cursor to the next or previous marked base.
- **Ctrl-E**:  Cycle between user edits.
- **Any nucleotide letter**:  Change the nucleotide at the current position.

When you press the **Save or Exit** menu button, it will display any errors and any user edits it thinks are suspicious(to prevent accidental sequence changes).  You can then **Save & Approve** or **Fail Sample**.

Finally when you are satisfied you can press the **Approve and Export**  button above the sample list to export all the sequence files as text or fasta.

## Support

If you encounter any problems or have any questions about this software, please create an issue in this GitHub repository.

## License

This software is free to use for academic purposes. For commercial use, please contact the University of British Columbia to purchase a license.

## Contact

University-Industry Liaison Office
Technology Enterprise Facility III
#103 - 6190 Agronomy Road, Vancouver, BC
V6T 1Z3
Tel: (604) 822-8580

https://uilo.ubc.ca/about-us/contact-us
