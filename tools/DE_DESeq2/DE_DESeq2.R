#####################################
##
## What: DE_DESeq2.R
## Who : Sergi Sayols
## When: 29-01-2015
##
## Script to perform DE different conditions, based on DESeq2 Negative Binomial model
## and the counts from htseq-count.
## Only supports pairwise comparisons, but any formula could be provided, including blocking factors.
##
## Args:
## -----
## targets=targets.txt      # file describing the targets.
##                          # Must fit the format expected in DESeqDataSetFromHTSeqCount
## contrasts=contrasts.txt  # file describing the contrasts
## mmatrix=~condition       # model matrix. Wrapper constrained to always use an intercept in the model
## gtf=gene_model.gtf       # gene model in gtf format, for rpkm calculation
## filter=TRUE              # perform automatic independent filtering of lowly expressed genes to maximise power
## prefix=RE                # prefix to remove from the sample name
## suffix=RE                # suffix to remove from the sample name (usually _readcounts.tsv)
## cwd=.                    # current working directory where the files .tsv files are located
## out=DE.DESeq2            # prefix filename for output
##
## IMPORTANT: This is a simplified wrapper to DESeq2 which is only able to do Wald tests on
##            simple experiments. It's meant only for pairwise comparisons in non-multifactor
##            designs. Why? to avoid messing our standard pipeline with extra parms, reusing
##            all the edgeR parms from the pipeline. With this simplification come along all
##            the limitations stated here.
##
######################################
options(stringsAsFactors=FALSE)
library(DESeq2)
library(RColorBrewer)
library(gplots)
library(ggplot2)
library(ggrepel)
library(WriteXLS)
library(GenomicRanges)
library(rtracklayer)
library(GenomicFeatures)

##
## get arguments from the command line
##
parseArgs <- function(args,string,default=NULL,convert="as.character") {

    if(length(i <- grep(string,args,fixed=T)) == 1)
        return(do.call(convert,list(gsub(string,"",args[i]))))
    
    if(!is.null(default)) default else do.call(convert,list(NA))
}

args <- commandArgs(T)
ftargets     <- parseArgs(args,"targets=","targets.txt")     # file describing the targets
fcontrasts   <- parseArgs(args,"contrasts=","contrasts.txt") # file describing the contrasts
mmatrix      <- parseArgs(args,"mmatrix=","~condition")      # model matrix
gene.model   <- parseArgs(args,"gtf=","")       # gtf gene model
filter.genes <- parseArgs(args,"filter=",TRUE,convert="as.logical") # automatic independent filtering
pre          <- parseArgs(args,"prefix=","")    # prefix to remove from the sample name
suf          <- parseArgs(args,"suffix=","_readcounts.tsv")    # suffix to remove from the sample name
cwd          <- parseArgs(args,"cwd=","./")     # current working directory
out          <- parseArgs(args,"out=","DE.DESeq2") # output filename

runstr <- "Rscript DE.DESeq2.R [targets=targets.txt] [contrasts=contrasts.txt] [mmatrix=~condition] [gtf=] [filter=TRUE] [prefix=RE] [suffix=RE] [cwd=.] [base=] [out=DE.DESeq2]"
if(!file.exists(ftargets))   stop(paste("File",ftargets,"does NOT exist. Run with:\n",runstr))
if(!file.exists(fcontrasts)) stop(paste("File",fcontrasts,"does NOT exist. Run with:\n",runstr))
if(!file.exists(cwd))        stop(paste("Dir",cwd,"does NOT exist. Run with:\n",runstr))
if(is.na(filter.genes))      stop(paste("Filter genes has to be either TRUE or FALSE. Run with:\n",runstr))
if(!file.exists(gene.model)) stop(paste("GTF File:", gene.model, " does NOT exist. Run with: \n", runstr))

##
## create the design and contrasts matrix
##
# load targets
targets <- read.delim(ftargets,head=T,colClasses="character",comment.char="#")
if(!all(c("group", "file", "sample") %in% colnames(targets))) stop("targets file must have at least 3 columns and fit the format expected in DESeqDatcondition")

#reorder the targets file
add_factors <- colnames(targets)[!colnames(targets) %in% c("group", "sample", "file")]
targets <- targets[, c("sample", "file", "group", add_factors)]

# load contrasts
conts <- read.delim(fcontrasts,head=F,comment.char="#")

# check if the specified targets exists in the CWD
if(!all(x <- sapply(paste0(cwd, "/", targets$file), file.exists)))
    stop("one or more input files do not exist in ", cwd, " (missing file(s): ", paste(targets$file[!x], collapse=" "), ")")

##
## calculate gene lengths
##
gtf <- import.gff(gene.model, format="gtf", feature.type="exon")
gtf.flat <- unlist(reduce(split(gtf, elementMetadata(gtf)$gene_id)))
gene.lengths <- tapply(width(gtf.flat), names(gtf.flat), sum)

# make sure we have a gene_name column (needed as output in the report later)
if(!any(colnames(mcols(gtf)) == "gene_name")) gtf$gene_name <- "NA"

# create a txdb object to collect the genes coordinates for later usage
txdb  <- makeTxDbFromGRanges(gtf)
genes <- as.data.frame(genes(txdb))

##
## DESeq analysis: right now it only allows simple linear models with pairwise comparisons
##
pairwise.dds.and.res <- lapply(conts[,1],function(cont) {

    # parse the formula in cont, get contrasts from resultNames(dds) and create a vector with coefficients
    cont.name <- gsub("(.+)=(.+)","\\1",cont)
    cont.form <- gsub("(.+)=(.+)","\\2",cont)
    factors   <- gsub("(^\\s+|\\s+$)", "", unlist(strsplit(cont.form,"\\W")))
    factors   <- factors[factors != ""]
    if(length(factors) != 2) {
        warning(paste(cont,"cannot deal with designs other than pairwise comparisons!"))
        return(NA)
    }

    # read input HTseq counts
    this_targets <- targets[targets$group %in% factors,]
    dds <- DESeqDataSetFromHTSeqCount(sampleTable=this_targets,
                                      directory=cwd, 
                                      design=as.formula(mmatrix))

    # relevel to make sure the comparison is done in the right direction (B vs A and not A vs B)
    dds$group <- relevel(dds$group, factors[2])

    # create DESeq object
    dds <- DESeq(dds)
    res <- results(dds, independentFiltering=filter.genes, format="DataFrame")

    # calculate quantification (RPKM if gene model provided, rlog transformed values otherwise)
    quantification <- apply(fpm(dds), 2, function(x, y) 1e3 * x / y, gene.lengths[rownames(fpm(dds))])
    res$gene_name <- gtf$gene_name[match(rownames(res), gtf$gene_id)]
    i <- match(rownames(res), genes$gene_id)
    res$chr    <- genes$seqnames[i]
    res$start  <- genes$start[i]
    res$end    <- genes$end[i]
    res$strand <- genes$strand[i]
    
    # write the results
    x <- merge(res[, c("gene_name", "chr", "start", "end", "strand", "baseMean", "log2FoldChange", "padj")], quantification, by=0)
    x <- x[order(x$padj),]
    
    colnames(x)[which(colnames(x) %in% c("baseMean", "log2FoldChange", "padj"))] <- mcols(res)$description[match(c("baseMean", "log2FoldChange", "padj"), colnames(res))]
    colnames(x)[1] <- "gene_id"

    write.csv(x, file=paste0(out, "/", cont.name, ".csv"), row.names=F)
    WriteXLS(x, ExcelFileName=paste0(out, "/", cont.name, ".xls"), row.names=F)
    
    list(dds,res)
})

## separate pairwise PCAs to a list
pairwise.dds <- lapply(pairwise.dds.and.res,function(x){return(x[[1]])})

## separate results to a list
res <- lapply(pairwise.dds.and.res,function(x){return(x[[2]])})
names(res) <-  gsub("=.*", "", conts[,1]) 


##
## Sanity check plots with all the samples together
##
pdf(paste0(out,"/DE_DESeq2.pdf"))

# make a DESeq2 object with all the samples
dds <- DESeqDataSetFromHTSeqCount(sampleTable=targets,
                                  directory=cwd, 
                                  design=as.formula(mmatrix))
dds <- DESeq(dds)
rld <- rlog(dds)

# sample to sample distance heatmap
distsRL <- dist(t(assay(rld)))
mat <- as.matrix(distsRL)
hc <- hclust(distsRL)
hmcol  <- colorRampPalette(brewer.pal(9, "GnBu"))(100)
heatmap.2(mat, Rowv=as.dendrogram(hc),
          symm=TRUE, trace="none",
          col = rev(hmcol), margin=c(13, 13))

# heatmap of the top variant genes
rows <- order(apply(assay(rld), 1, sd), decreasing=TRUE)[1:25]
hmcol  <- colorRampPalette(brewer.pal(9, "GnBu"))(100)
heatmap.2(assay(rld)[rows,],col=hmcol,trace="none",margin=c(10,6),scale="none")

# PCA, group based on the first factor (column 3 in targets)
p <- plotPCA(rld, intgroup=colnames(colData(dds))[1])
plot(p + geom_text_repel(aes(label=rownames(colData(dds)))) + theme_bw())

# MA plot
x <- mapply(function(res, cont) {
    plotMA(res, main=cont, ylim=c(-3,3))
    invisible(0)
}, res, conts[, 1], SIMPLIFY=FALSE)

dev.off()
#save the sessionInformation
writeLines(capture.output(sessionInfo()),paste(out, "/DE_DESeq2_session_info.txt", sep=""))
save(rld, pairwise.dds, dds, res, conts, file=paste0(out,"/DE_DESeq2.RData"))
