##################################
##
## helper functions to create the plots for the Shiny report
##
##################################
library("edgeR")
library("RColorBrewer")
library("gplots")
library("ggplot2")
library("knitr")		# for markdown output

##
## loadGlobalVars: read configuration from bpipe vars
##
loadGlobalVars <- function(f="shinyReports.txt") {

	# read in the conf file
	conf <- readLines(f)
	conf <- conf[grep("^SHINYREPS_",conf)]
	
	# create the vars
	sapply(conf,function(x) {
		x <- unlist(strsplit(x,"=",fixed=T))
		assign(x[1],x[2],envir=.GlobalEnv)
	})
	
	invisible(0)
}

##
## DEhelper.init: some time consuming tasks that can be done in advance
##
DEhelper.init <- function(task) {
	
	# Prepare the DE data frame
	renderUcscGeneLinks <- function() {
		ucsc_url <- paste0("http://genome.ucsc.edu/cgi-bin/hgGene?org=",SHINYREPS_ORG,"&db=",SHINYREPS_DB,"&hgg_gene=")
		for(i in 1:length(lrt)) {
			lrt[[i]]$table$gene <<- sapply(rownames(lrt[[i]]$table),function(x) {
				paste0("<a href=\"",ucsc_url,x,"\">",x,"</a>")
			})
		}
	}
	prepareDEdataTable <- function() {
		for(i in 1:length(lrt)) {
			lrt[[i]]$table$FDR    <<- p.adjust(lrt[[i]]$table$PValue,method="fdr")
			lrt[[i]]$table$logFC  <<- round(lrt[[i]]$table$logFC,2)
			lrt[[i]]$table$logCPM <<- round(lrt[[i]]$table$logCPM,2)
			lrt[[i]]$table$LR     <<- round(lrt[[i]]$table$LR,2)
			lrt[[i]]$table$PValue <<- round(lrt[[i]]$table$PValue,4)
			lrt[[i]]$table$FDR    <<- round(lrt[[i]]$table$FDR,4)
		}
	}
	
	# Cluster and correlation tasks
	prepareDistanceMatrix <- function() {
		v <<- apply(m,1,sd,na.rm=T)		# get top variant genes
		dists <<- dist(t(m))
		mat <<- as.matrix(dists)
		hmcol <<- colorRampPalette(brewer.pal(max(length(levels(group)),3),"Oranges"))(100)
	}
	
	# dispatch tasks
	switch(task,
		   renderUcscGeneLinks=renderUcscGeneLinks(),
		   prepareDEdataTable=prepareDEdataTable(),
		   prepareDistanceMatrix=prepareDistanceMatrix())
}

##
## DEhelper.MDS
##
DEhelper.MDS <- function() {
	edgeR::plotMDS.DGEList(y,col=brewer.pal(max(length(levels(group)),3),"Accent")[group])
}

##
## DEhelper.var: variance along log gene count-per-milion
##
DEhelper.var <- function() {
	edgeR::plotBCV(y)
}

##
## DEhelper.cluster: Heatmap of top variant 'n' genes of the counts-per-milion table
##
DEhelper.cluster <- function(n=50) {
	heatmap.2(m[rev(order(v))[1:n],],col=hmcol,trace="none",margin=c(10,6))
}

##
## DEhelper.corr: Heatmap of sample to sample distances
##
DEhelper.corr <- function() {
	heatmap.2(mat,trace="none",col=rev(hmcol),margin=c(13,13))
}

##
## DEhelper.MAplot: MA plots
##
DEhelper.MAplot <- function(i=1,fdr=.05) {
	# get DE genes (p.adjust='BH', pval<.05)
	de <- decideTestsDGE(lrt[[i]],p.value=fdr)
	degenes <- rownames(y)[as.logical(de)]
	
	# MA plot
	plotSmear(lrt[[i]],de.tags=degenes,main=names(lrt)[i])	# MA plot
	abline(h=c(-1,1),col="blue")	# indicate 2-fold changes in the MA plot
	abline(v=0,col="blue")			# indicate >1 counts-per-million
}

##
## DEhelper.DEgenes: show the DE results
##
DEhelper.DEgenes <- function(i=1) {
	ord  <- order(-log(lrt[[i]]$table$FDR),
				   abs(lrt[[i]]$table$logFC),
				  decreasing=TRUE)
	cols <- c("gene","logFC","logCPM","LR","PValue","FDR")
	lrt[[i]]$table[ord,cols]
}

##
## DEhelper.STAR: parse STAR log files and create a md table
##
DEhelper.STARparms <- function() {
	
	# log file
	LOG <- SHINYREPS_STAR_LOG
	SUFFIX <- paste0(SHINYREPS_STARparms_SUFFIX,'$')
	if(!file.exists(LOG)) {
		return("STAR statistics not available")
	}
	
	# look for the lines containing the strings and get the values associated with this strings
	parseLog <- function(f) {
		# read in the lines
		f <- file(paste0(LOG,"/",f))
		l <- readLines(f)
		close(f)
		
		# get the version number from the first line (STAR svn revision compiled=STAR_2.3.1z13_r470)
		v <- unlist(strsplit(l[1],"="))[2]
		
		# get the redifined parameters and parse them in a key-value data.frame
		redefined <- l[grep("\\s+\\~RE-DEFINED$",l)]
		redefined <- sapply(redefined,function(x) {
			x <- unlist(strsplit(gsub("\\s+\\~RE-DEFINED$","",x),"\\s+"))
			x[2] <- if(length(x) < 2) "" else x[2]
			l <- nchar(x[2])
			x[2] <- if(l > 40) paste(substr(x[2],1,20),substr(x[2],(l-15),l),sep="...") else x[2]
			x[c(1,2)]
		})
		x <- redefined[2,]
		names(x) <- redefined[1,]
		
		# put the STAR version number
		x <- c(version=v,x)
		return(x)
	}
	df <- sapply(list.files(LOG,pattern=SUFFIX),parseLog)
	
	# remove variable lines (lines depending on the fastq.gz file name)
	# and check if all the columns contain the same value. Display a warning otherwise
	df <- df[!grepl("(outFileNamePrefix|outTmpDir|readFilesIn)",rownames(df)),]
	l <- apply(df,1,function(x) length(unique(x)))	# rows differing (l > 1)
	df <- as.data.frame(df[,1,drop=F])	# keep only the first column
	colnames(df) <- "parms"
	df$warning[l > 1] <- "Some files aligned with a different parm. Check logs"
	
	# set row and column names, and output the md table
	if(all(is.na(df$warning))) {
		kable(df[,1,drop=F],align=c("r"),output=F)
	} else {
		kable(df,align=c("r","r"),output=F)
	}
}

##
## DEhelper.STAR: parse STAR log files and create a md table
##
DEhelper.STAR <- function() {
	
	# log file
	LOG <- SHINYREPS_STAR_LOG
	SUFFIX <- paste0(SHINYREPS_STAR_SUFFIX, '$')
	if(!file.exists(LOG)) {
		return("STAR statistics not available")
	}
	
	# look for the lines containing the strings
	# and get the values associated with this strings
	x <- sapply(list.files(LOG,pattern=SUFFIX),function(f) {
		f <- file(paste0(LOG,"/",f))
		l <- readLines(f)
		close(f)
		
		sapply(c("Number of input reads",                      #1
				 "Uniquely mapped reads number",               #2
				 "Uniquely mapped reads %",                    #3
				 "Number of reads mapped to multiple loci",    #4
				 "Number of reads mapped to too many loci",    #5
				 "% of reads mapped to multiple loci",         #6
				 "% of reads mapped to too many loci",         #7
				 "% of reads unmapped: too many mismatches",   #8
				 "% of reads unmapped: too short",             #9
				 "% of reads unmapped: other"),function(x) {   #10
				 	as.numeric(gsub("%","",gsub(".+\\|\t(.+)","\\1",l[grep(x,l)])))
				 })	
	})
	
	# set row and column names, and output the md table
	colnames(x) <- gsub(paste0("^",SHINYREPS_PREFIX),"",colnames(x))
	colnames(x) <- gsub(paste0(SUFFIX,"$"),"",colnames(x))
	df <- data.frame(input_reads=x[1,],
					 uniq_mapped=paste0(x[2,]," (",x[3,],"%)"),
					 multimapped=paste0(x[4,] + x[5,]," (",x[6,] + x[7,],"%)"),
					 unmapped=paste0(x[8,] + x[9,] + x[10,],"%"))
	kable(df,align=c("r","r","r","r"),output=F)
}

##
## DEhelper.Fastqc: go through Fastqc output dir and create a md table with the duplication & read quals & sequence bias plots
##
DEhelper.Fastqc <- function(web=TRUE) {
	
	# logs folder
	if(!file.exists(SHINYREPS_FASTQC_LOG)) {
		return("Fastqc statistics not available")
	}
	
	# construct the folder name, which is different for web and noweb
	QC <- if(web) "/fastqc" else SHINYREPS_FASTQC_LOG
	
	# construct the image url from the folder contents (skip current dir .)
	samples <- list.dirs(SHINYREPS_FASTQC_LOG,recursive=F)
	df <- sapply(samples,function(f) {
		c(paste0("![alt text](",QC,"/",basename(f),"/Images/duplication_levels.png)"), 
		  paste0("![alt text](",QC,"/",basename(f),"/Images/per_base_quality.png)"), 
		  paste0("![alt text](",QC,"/",basename(f),"/Images/per_base_sequence_content.png)"))
	})

	# set row and column names, and output the md table
	df <- as.data.frame(t(df))
	rownames(df) <- gsub(paste0("^",SHINYREPS_PREFIX),"",basename(samples))
	colnames(df) <- c("Duplication","Read qualities","Sequence bias")
	kable(df,output=F)
}

##
## DEhelper.dupRadar: go through dupRadar output dir and create a md table with
##     the duplication plots
##
DEhelper.dupRadar <- function(web=TRUE) {
	
	# logs folder
	if(!file.exists(SHINYREPS_DUPRADAR_LOG)) {
		return("DupRadar statistics not available")
	}
	
	# construct the folder name, which is different for web and noweb
	QC <- if(web) "/dupRadar" else SHINYREPS_DUPRADAR_LOG
	
	# construct the image url from the folder contents (skip current dir .)
	samples <- list.files(SHINYREPS_DUPRADAR_LOG,pattern="*.png")
	df <- sapply(samples,function(f) {
		paste0("![alt text](",QC,"/",basename(f),")")
	})
	
	# put sample names and output an md table of 4 columns
	while(length(df) %% 4 != 0) df <- c(df,"")
	samples <- sapply(df,function(x) {
		x <- sapply(x,function(x) gsub(paste0("^",SHINYREPS_PREFIX),"",basename(x)))
		gsub("_dupRadar.png)","",x)
	})
	df      <- matrix(df     ,ncol=4,byrow=T)
	samples <- matrix(samples,ncol=4,byrow=T)
	
	# add a row with the sample names
	df.names <- matrix(sapply(1:nrow(df),function(i) { c(df[i,],samples[i,]) }),ncol=4,byrow=T)
	colnames(df.names) <- c(" "," "," "," ")
	
	kable(as.data.frame(df.names),output=F)
}

##
## DEhelper.RNAtypes: go through RNAtypes output dir and create a md table with
##     the RNAtypes plots
##
DEhelper.RNAtypes <- function(web=TRUE) {
	
	# logs folder
	if(!file.exists(SHINYREPS_RNATYPES_LOG)) {
		return("RNAtypes statistics not available")
	}
	
	# construct the folder name, which is different for web and noweb
	QC <- if(web) "/RNAtypes" else SHINYREPS_RNATYPES_LOG
	
	# construct the image url from the folder contents (skip current dir .)
	f <- list.files(SHINYREPS_RNATYPES_LOG,pattern="*.png")
	df <- sapply(f,function(f) {
		paste0("![alt text](",QC,"/",basename(f),")")
	})
	
	# output an md table of 3 columns and 1 row
	df <- matrix(df,ncol=3)
	colnames(df) <- c(" "," "," ")

	kable(as.data.frame(df),output=F)
}

##
## DEhelper.geneBodyCov: go through dupRadar output dir and create a md table with
##     the duplication plots
##
DEhelper.geneBodyCov <- function(web=TRUE) {
	
	# logs folder
	if(!file.exists(SHINYREPS_GENEBODYCOV_LOG)) {
		return("geneBodyCov statistics not available")
	}
	
	# construct the folder name, which is different for web and noweb
	QC <- if(web) "/geneBodyCov" else SHINYREPS_GENEBODYCOV_LOG
	
	# construct the image url from the folder contents (skip current dir .)
	samples <- list.files(SHINYREPS_GENEBODYCOV_LOG,pattern="*.png")
	df <- sapply(samples,function(f) {
		paste0("![alt text](",QC,"/",basename(f),")")
	})
	
	# put sample names and output an md table of 4 columns
	while(length(df) %% 4 != 0) df <- c(df,"")
	samples <- sapply(df,function(x) {
		x <- sapply(x,function(x) gsub(paste0("^",SHINYREPS_PREFIX),"",basename(x)))
		gsub(".geneBodyCoverage.curves.png)","",x)
	})
	df      <- matrix(df     ,ncol=4,byrow=T)
	samples <- matrix(samples,ncol=4,byrow=T)
	
	# add a row with the sample names
	df.names <- matrix(sapply(1:nrow(df),function(i) { c(df[i,],samples[i,]) }),ncol=4,byrow=T)
	colnames(df.names) <- c(" "," "," "," ")
	
	kable(as.data.frame(df.names),output=F)
}

##
## DEhelper.Bustard: call the perl XML interpreter and get the MD output
##
DEhelper.Bustard <- function() {
	f  <- SHINYREPS_BUSTARD
	
	if(!file.exists(f)) {
		return("Bustard statistics not available")
	}
	
	# call the perl XSL inetrpreter
	cmd <- paste(" bustard.pl",f)
	try(ret <- system2("perl",cmd,stdout=TRUE,stderr=FALSE))
	
	# check RC
	if(!is.null(attributes(ret))) {
		return(paste("Error parsing bustard statistics. RC:",attributes(ret)$status,"in command: perl",cmd))
	}
	
	ret 	# ret contains already MD code
}

##
## DEhelper.Subread: parse Subread summary stats and create a md table
##
DEhelper.Subread <- function() {
	
	FOLDER <- SHINYREPS_SUBREAD
	SUFFIX <- paste0(SHINYREPS_SUBREAD_SUFFIX, '$')
	
	# check if folder exists
	if(!file.exists(FOLDER)) {
		return("Subread statistics not available")
	}
	
	# create a matrix using feature names as rownames, sample names as colnames
	x <- sapply(list.files(FOLDER,pattern=SUFFIX),function(f) {
		
		f <- file(paste0(FOLDER, '/', f))
		l <- readLines(f)
		close(f)
		
		
		sapply(c("Assigned",                      #1
				 "Unassigned_Ambiguity",          #2
				 "Unassigned_MultiMapping",       #3
				 "Unassigned_NoFeatures",         #4
				 "Unassigned_Unmapped",           #5
				 "Unassigned_MappingQuality",     #6
				 "Unassigned_FragementLength",    #7
				 "Unassigned_Chimera",            #8
				 "Unassigned_Secondary",          #9
				 "Unassigned_Nonjunction",        #10
				 "Unassigned_Duplicate"),function(y) {   #11
					as.numeric(  gsub( ".+\t(.+)","\\1",l[grep(y,l)] )  )
				 })	
		
	})
	
	# correct column names
	colnames(x) <- gsub(paste0("^",SHINYREPS_PREFIX),"",colnames(x))
	colnames(x) <- gsub(paste0(SUFFIX,"$"),"",colnames(x))
	
	# create md table (omitting various values that are 0 for now)
	df <- data.frame(assigned=x[1,],
					 unass_ambiguous=x[2,],
					 unass_multimap=x[3,],
					 unass_nofeat=x[4,])
	kable(df,align=c("r","r","r","r"),output=F)
	
}

##
## extract tool versions
##

DEhelper.ToolVersions <- function() {
  tools <- c("FastQC", "STAR", "HTseq", "Subread", "DupRadar", "Samtools", "BedTools", "Picard", "R")
  variables <- list(SHINYREPS_TOOL_FASTQC, SHINYREPS_TOOL_STAR, SHINYREPS_TOOL_HTSEQ, SHINYREPS_TOOL_SUBREAD, SHINYREPS_TOOL_DUPRADAR, SHINYREPS_TOOL_SAMTOOLS, SHINYREPS_TOOL_BEDTOOLS, SHINYREPS_TOOL_PICARD, SHINYREPS_TOOL_R)
  # get the last element in path, which is the tool's version (for the tools listed)
  versions <- sapply(variables, function(x) {
    y <- strsplit(x, '/')[[1]]
    tail(y, n=1)
  })
  
  # correct the samtools version (second, but last element)
  tmp_x <- strsplit(SHINYREPS_TOOL_SAMTOOLS, '/')[[1]]
  versions[6] <- head(tail(tmp_x, n=2), n=1) 
  
  df <- data.frame(tool_name=tools, tool_version=versions)
  
  kable(df,align=c("l","l"),output=F)
  
}