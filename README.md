![IMB-logo](resources/IMB_logo.png)

# NGSpipe2go #
A set of tools used at IMB and you're very welcome to do so at your institute as well.

The tool set consists of several published tools and others developed at IMB (<http://www.imb-mainz.de/home/>).
Currently, the tool set sports a RNAseq and ChIPseq pipeline and its respective modules.

## Prerequisites ##
### RNAseq ###
#### Programs required ####
- FastQC
- STAR
- Samtools
- Subread package
- Picard tools
- BED tools
- UCSC tool set
- RSeQC
- EdgeR
- DEseq2
- dupRadar (*)

(*) is provided via another project from imbforge

#### Files required ####
- targets.txt (+) (*)
- contrasts.txt (+) (*)
- chromosome sizes (*)
- raw reads or mapped data

(+) files are needed to run the EdgeR and DEseq2 modules.

(*) examples provided within this project

### ChIPseq ###
#### Programs required ####
- FastQC
- Bowtie 1
- Samtools
- BED tools
- Picard tools
- UCSC tool set
- encodeChIPqc (*)
- MACS2

(*) is provided via another project from imbforge

#### Files required ####
- chromosome sizes (*)
- targets.txt (*)
- raw reads or mapped data

(*) examples provided within this project

## Preparations to run ##
NGS projects are required to be run in a consistant way and may be required to be rerun in the near or far future. Hence NGSpipe2go asks you to copy all tools into the project folder, which will ensure that you always use the same program versions at a later time point.
To this end we suggest to copy all modules, which may be subject to updates, into the project folder.

    cp -r github/imbforge/ project_folder/

Select a pipeline to run and make it available in the main project.

    ln -s project_folder/imbforge/pipelines/RNAseq/* project_folder/
or 

    ln -s project_folder/imbforge/pipelines/ChIPseq/* project_folder/

Adjust the information found in the following files:
- Folder information in modules/RNAseq/tool.locations or modules/ChIPseq/tool.locations (*)
- Project_folder needs to be entered in modules/RNAseq/essential.vars.groovy modules/ChIPseq/essential.vars.groovy (+)
- Folder information in the recently linked rnaseq- or chipseq pipeline file (+)
- Compute requirements for the used queueing system according to the project data (Whole genome data might need more compute ressources than a low coverage ChIPseq experiment) (*)

(*) these steps need to be done once for the setup of NGSpipe2go

(+) these steps need to be repeated for each project to be run

## Run ##

We suggest to put the input files to a folder, e.g. project_folder/rawdata.

To start running the pipeline (tested for bpipe-0.9.8.7)

    bpipe run rnaseq_v1.2.txt rawdata/*.fastq.gz
or

    bpipe run chipseq_v1.2.txt rawdata/*.fastq.gz