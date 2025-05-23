#' Find peaks and LD blocks in the LMM results
#'
#' \code{rep_peaks} use the individual strains genotypes matrix to find LD blocks in a greedy way
#' it starts by sorting the GWAS p-values and then choosing the lowest p-value and removing all
#' markers with a high correlation. It then selects the next marker and so on until all markers with
#' p-values smaller than the threshold are in peak regions.
#'
#'
#' @param genotypes The genotypes matrix, one column for each strain, used for computing correlations
#' @param gwas_pvs GWAS output pvalues
#' @param rs_thr Threshold for correlation, \eqn{r^2} larger than this value will be considered same peak
#' @param pthr P-value threshold
#' @param mxd Maximal peak width
#' @param test Test name in the results data frmae
#'
#' @return a table with the marker name, choose = peak region number, ispeak = marker is peak, rsq = r square value
#' @export
#'
rep_peaks <- function(genotypes, gwas_pvs, rs_thr=0.4, pthr=1e-20, mxd=10000000, test="p_wald"){
  tmat <- base::t(genotypes)
  srt_pv <- gwas_pvs %>% dplyr::select_("rs", test) %>% arrange_(test) %>% mutate(choose = 0, ispeak=FALSE)
  rssq <- tibble(rs=character(0), rsq=numeric(0))
  peaknum = 1
  while (any(srt_pv$choose[srt_pv[,test,drop=T] <= pthr] == 0)){
    nr <- which(srt_pv$choose == 0 & srt_pv[,test,drop=T] <= pthr)[1]
    rs <- srt_pv$rs[nr]
    # Select other SNPs in its vicinity
    rsnum <- gwas_pvs$rs==rs
    subt <- tmat[,gwas_pvs$rs[gwas_pvs$chr==gwas_pvs$chr[rsnum] & gwas_pvs$ps >= gwas_pvs$ps[rsnum]-mxd &
                                gwas_pvs$ps <= gwas_pvs$ps[rsnum]+mxd]]
    if (!is.null(dim(subt))){
      rsset = c(rs)
      changed <- T
      while (changed){
        cvec <- cor(tmat[,rsset], subt)
        rel_rs <- colnames(cvec)[colSums(cvec^2 >= rs_thr, na.rm = T)>=1]
        if (length(rel_rs)>0){
          rssq <- rbind(rssq, tibble(rs=rel_rs, rsq=cvec[1,rel_rs]^2))
          #srt_pv$rsq[[rel_rs, "rsq"] <- cvec[1,rel_rs]^2
        }
        #if (length(setdiff(rel_rs, rsset)) == 0) changed = F
        changed = F
        rsset <- c(rsset, rel_rs)
      }
      srt_pv[srt_pv$rs %in% rsset & srt_pv$choose==0, "choose"] = peaknum
    }
    srt_pv[nr, "choose"] = peaknum
    srt_pv[nr, "ispeak"] = TRUE
    peaknum = peaknum + 1
  }
  rssq <- rssq %>% group_by(rs) %>% summarize(rsq=max(rsq)) %>% ungroup()
  srt_pv <- left_join(srt_pv, rssq, by="rs") %>% tidyr::replace_na(list(rsq=0))

  return(srt_pv %>% dplyr::select(rs, choose, ispeak, rsq))
}

#' Get blocks as computed by the paper A sequence-based variation map of 8.27 million SNPs in inbred mouse strains
#' https://www.nature.com/articles/nature06067
#' Downloaded from: http://mouse.cs.ucla.edu/perlegen/
#'
#' @param gwas_pvs The gwas results with p-values
#' @param blocks The blocks file, found in the extdata folder
#' @param test which test to use (default p_wald)
#' @param pthr p-value threshold
#'
#' @return
#' @export
#'
#' @import dplyr
get_blocks <- function(gwas_pvs, blocks=system.file("extdata", "block_summary.txt", package = "mousegwas"), test="p_wald", pthr=1e-6){
  blks <- read.delim(blocks, header = TRUE, sep = "\t")
  blks$chr <- gsub("^0", "", blks$chrom)
  blks <- blks[,c("blockid", "chr", "startbp", "endbp")]
  comb <- NULL
  gwas_pvs <- as.data.frame(gwas_pvs)
  for (c in setdiff(unique(gwas_pvs$chr), NA)) {
    comb1 <-
      merge(gwas_pvs[gwas_pvs$chr == c, ],
            blks,
            by = "chr",
            all.x = TRUE,
            all.y = FALSE)
    comb1 <-
      comb1[comb1$ps <= comb1$endbp & comb1$ps >= comb1$startbp,]
    comb1$choose <- comb1$blockid
    comb1$ispeak <- FALSE
    for (bl in unique(comb1$blockid[comb1[,test] <= pthr])) {
      comb1$ispeak <-
        comb1$ispeak |
        (comb1[, test] <= pthr &
           comb1[, test] == min(comb1[comb1$choose == bl, test]))
    }
    print(head(comb1))
    comb <- rbind(comb, comb1)
  }
  comb <- comb[!is.na(comb$chr),]
  return (comb)
}

#' Plot the GWAS results as a Manhattan plot and highlight specific genes
#'
#' @param results_file A GEMMA results file
#' @param name The title
#' @param metasoft set TRUE if the input is metaSOFT output
#' @param pyLMM TRUE if the input is pyLMM output with rs ID in the first column SNP_ID
#' @param annotations If metasoft is TRUE then annoattions file should be given
#' @param namethr Print gene name above this threshold
#' @param redthr Red points above this thr
#' @param diff A file with results to be subtracted from the first file. Must be in the same format, only implemented for GEMMA
#' @param genotypes The genotypes of the input strains to compute correlation. If given (as data.frame with row.names) every peak will be colored
#' @param maxdist maximal distance between peak and related SNPs
#' @param corrthr r-square threshold to consider SNPs in the same peak, combined with maxdist
#' @param test Name of test to use
#' @param addgenes A boolean. Add gene names or not
#' @param annot Genes table, optional. If NULL pull from biomaRt
#'
#'
#' @return An object with the plot object, (plot), The GWAS results (gwas) and the plotted object (pwas)
#' @export
#'
#' @import dplyr
#' @import readr
#' @import ggplot2
#' @import ggnewscale
#' @importFrom magrittr `%>%`
#' @importFrom readr read_delim
plot_gemma_lmm <- function(results_file, name="GWAS results", metasoft=FALSE, pyLMM=FALSE, annotations=NULL, namethr=5, redthr=4, diff=NULL, genotypes=NULL, maxdist=1000000, corrthr=0.6, test="p_wald", addgenes=TRUE, annot=NULL, blocks = FALSE) {
  if (metasoft){
    print("Metasoft")
    gwas_results <- read_delim(results_file, "\t", col_names = FALSE, skip=1, guess_max = Inf)
    gwas_results <- gwas_results %>% dplyr::select_("rs"="X1", test="X9")  # RSID and PVALUE_RE2
    anno <- read_delim(annotations, ",", col_names = c("rs", "ps", "chr"), guess_max = Inf)
    gwas_results <- left_join(gwas_results, anno, by="rs")
  }else if (pyLMM){
    print("NOT Metasoft")
    gwas_results <- read_delim(results_file, "\t", col_names = TRUE, guess_max = Inf)
    gwas_results <- gwas_results %>% dplyr::select_("rs"="SNP_ID", test="P_VALUE")  # RSID and PVALUE_RE2
    anno <- read_delim(annotations, ",", col_names = c("rs", "ps", "chr"), guess_max = Inf)
    gwas_results <- left_join(gwas_results, anno, by="rs")
  }else{
    print("Something Else")
    gwas_results <- NULL
    # Results file might be a vector of files
    for (rf in results_file){
      gwas_results <- rbind(gwas_results, read_delim(rf, "\t", col_names = TRUE, col_type = cols(
        .default = col_double(),
        chr = col_character(),
        rs = col_character(),
        ps = col_double(),
        n_miss = col_double(),
        allele1 = col_character(),
        allele0 = col_character())))
    }

    if (! is.null(diff)){
      difres <- read_delim(diff, "\t", col_names = TRUE, col_type = cols(
        .default = col_double(),
        chr = col_character(),
        rs = col_character(),
        ps = col_double(),
        n_miss = col_double(),
        allele1 = col_character(),
        allele0 = col_character()))
      jres <- gwas_results %>% inner_join(dplyr::select_(difres, c("rs", test)), by="rs", suffix = c("", ".d"))
      gwas_results <- jres %>% mutate_(test = paste0(test,"/",test,".d")) %>% dplyr::select_(paste0("-",test,".d"))
    }

  }



  #chr     rs      ps      n_miss  allele1 allele0 af      beta_1  beta_2  beta_3  Vbeta_1_1       Vbeta_1_2       Vbeta_1_3       Vbeta_2_2       Vbeta_2_3       Vbeta_3_3       p_lrt
  #"1"     "rs32166183"    3046097 0       "A"     "C"     0.300   4.737279e-02    1.737096e-02    6.561576e-02    1.160875e-03    9.232757e-04    2.029432e-03    1.757942e-03    2.437142e-03    4.390245e-03    5.048649e-01
  # Add peak color if genotypes are supplied
  genesdist = 10000
  if (blocks){
    gwas_results <- get_blocks(gwas_results, pthr = 10^-redthr)
  }
  else if (!is.null(genotypes)){
    #allgeno <- read.csv(genotypes, header = FALSE, row.names = 1)
    #allgeno <- allgeno[, 3:ncol(allgeno)]
    pnums <- rep_peaks(genotypes, gwas_results, rs_thr=corrthr, pthr=10^-redthr, mxd=maxdist, test=test)
    gwas_results <- gwas_results %>% left_join(pnums, by="rs")
  }else{
    gwas_results <- gwas_results %>% mutate(choose=0, ispeak=FALSE, rsq=0)
  }
  gwas_results <- gwas_results %>% mutate_("P" = paste0("-log10(",test,")"))
  ret_gwas <- gwas_results
  gwas_results[gwas_results$chr=="X","chr"] <- "20"# gwas_results %>% dplyr::filter(chr=="X") %>% dplyr::mutate(chr=20)
  gwas_results <- gwas_results %>% mutate(chr=as.numeric(chr)) %>% arrange(chr, ps)

  don <- gwas_results %>%

    # Compute chromosome size
    group_by(chr) %>%
    summarise(chr_len=max(ps)+50000000) %>%

    # Calculate cumulative position of each chromosome
    mutate(tot=cumsum(as.numeric(chr_len))-chr_len) %>%
    dplyr::select(-chr_len) %>%

    # Add this info to the initial dataset
    left_join(gwas_results, ., by=c("chr"="chr")) %>%

    # Add a cumulative position of each SNP
    arrange(chr, ps) %>%
    mutate(BPcum=ps+tot) %>%

    # Add highlight and annotation information
    #mutate( is_highlight=ifelse(SNP_ID %in% snpsOfInterest, "yes", "no")) %>%

    # Filter SNP to make the plot lighter
    filter(! is.na(chr))
    # Replace chr 20 to X
 # don[don$chr==20, "chr"] = "X"


  # Prepare X axis
  axisdf <- don %>% group_by(chr) %>% summarize(center=( max(BPcum) + min(BPcum) ) / 2 )

  # Get the RSIDs to put names on
  # Prepare text description for each SNP:
  #don$text <- paste("SNP: ", don$rs, "\nPosition: ", don$ps, "\nChromosome: ", don$chr, "\nLOD score:", don$P %>% round(2), "\nWhat else do you wanna know", sep="")
  log10P <- don$P
  ymax <- 1.25 * max(log10P, na.rm = TRUE)
  ymin <- 1.25 * min(log10P, na.rm = TRUE)
  chr_label <- axisdf$chr
  chr_label[chr_label==20] = "X"
  
  print("Reached gwas plotting")
  # Make the plot
  p <- ggplot2::ggplot(don, aes(x=BPcum, y=P)) +

    # Show all points
    geom_point(aes(color=as.factor(chr), size=P) , alpha=1) +
    scale_color_manual(values = c(rep(c("#CCCCCC", "#969696"),10))) +
#    scale_size_continuous(range=c(0,1), trans = "exp") +
    geom_segment(y = redthr, x=min(don$BPcum)-50000000, xend=max(don$BPcum)+50000000, yend=redthr,color="#FCBBA1" )
  
  print("Reached gwas plotting: 2")

  if (sum(don$ispeak) > 0){
    # Plot peaks in color
    p <- p + ggnewscale::new_scale(c("color", "size")) +
    geom_point(data= don %>% filter(ispeak), aes(color = "#377EB8"), alpha=1, size = 1)

    # Print names around peaks
    if (addgenes){
      toprs <- get_genes_ac(ret_gwas %>% filter(P>namethr, ispeak==TRUE), dist = genesdist, annot=annot) %>% dplyr::select(rs, mgi_symbol) %>%
      filter(!is.na(mgi_symbol), !stringr::str_detect(mgi_symbol, "Rik$"), !stringr::str_detect(mgi_symbol, "^Gm")) %>% unique()
    # Add gene names
      p <- p + ggrepel::geom_text_repel(data = dplyr::filter(don, rs %in% toprs$rs) %>% left_join(dplyr::select(toprs, rs, mgi_symbol), by="rs"),
                                    aes(BPcum, P, label = mgi_symbol), alpha = 0.7, size=2, family="Courier")
    }
}
  print("Reached gwas plotting: 3")
  p <- p + scale_x_continuous( label = chr_label, breaks= axisdf$center ) +
    scale_y_continuous(expand = c(0, 0) ) +     # remove space between plot area and x axis
    ylim(ymin,ymax) +
    xlab(name) +
    ylab("-log(P-value)") +
    theme_bw() +
    theme(
      legend.position="none",
      text = element_text(size=20),
      panel.border = element_blank(),
      panel.grid.major.x = element_blank(),
      panel.grid.minor.x = element_blank()
    )

  print("Reached gwas plotting: 4")
  return(list(plot=p, gwas=ret_gwas, pwas=don))
}

