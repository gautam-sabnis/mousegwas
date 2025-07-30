#!/usr/bin/env nextflow

/*
 * A pipeline for running mousegwas with shuffling and figure generation
 * https://github.com/TheJacksonLaboratory/mousegwas
 *
 * Parameters:
 *   - input: csv input file with phenotypes
 *   - yaml: yaml file that describes the run
 *   - outdir: output directory for all scripts
 *   - clusters: Number of clusters for clustering QTL (default: 7)
 *   - downsample: Number of individuals to sample from each strain (default: 10)
 *   - genotype: either genotyping files (with -g) or --MDA (default)
 *   - shuffles: Number of shuffles for computing empirical p-values (default: 1000)
 *   - shufyaml: A yaml file describing the shuffle run, should include one phenotype
 *   - pvalue: Threshold for calling a QTL (default 0.05)
 *   - addpostp: Additional parameters for postprocess_mv.R
 *   - addgwas: Additional parameters for run_GWAS.R
 */

params.yaml = ""
params.outdir = "."
params.clusters = 7
params.downsample = 10
params.genotype = "--MDA"
params.shuffles = 10
params.shufyaml = ""
params.pvalue = 0.5
params.addpostp = ""
params.addgwas = ""
params.addheatmap = ""
params.input = "NO_FILE"
input = file(params.input)
Channel.fromPath(params.yaml).into{yaml; yaml2; yaml3}
Channel.fromPath(params.shufyaml).set{shufyml}

process postp{
  label 'mousegwas'
  label 'high_mem'
  publishDir path:params.outdir, mode:'copy'
  input:
    file yml from yaml2
  output:
    file "pvalue-threshold.txt" into pvalt
    file "postprocess_nomv/*" into outfiles2
    file "postprocess_nomv/genes_coordinates_for_INRICH.txt" into ggCh
    file "postprocess_nomv/SNPs_map_for_INRICH.txt" into snpCh
    file "postprocess_nomv/intervals*INRICH.txt" into interLs
    file "postprocess_nomv/groups*INRICH.txt" into groupsLs
  script:
  """
  outval=9.018538e-05
  echo \$outval > pvalue-threshold.txt
  Rscript -e 'source(file="/projects/kumar-lab/sabnig/Pipelines/gwas/postprocess_ac.R")' -p postprocess_nomv -c ${params.clusters} --external_inrich -s 10000 --nomv --pvalthr \$(awk -v o=\$outval 'BEGIN{print -(log(o)/log(10))}') --peakcorr 0.2 -o '/projects/kumar-lab/sabnig/Pipelines/gwas/output/outdir' -i 20 -j 200 -y $yml ${params.addpostp}
  """
}

//Transforms the lists into channels
interLs.flatMap().set{interCh}
groupsLs.flatMap().set{groupsCh}

//Execute each INRICH run separately
process runINRICH{
  publishDir path:params.outdir, mode:'copy'
  label 'mousegwas'
  label 'single_cpu'
  input:
    file groups from groupsCh
    each file(interv) from interCh
    each file(genes) from ggCh
    each file(snps) from snpCh
  output:
    file "*.out.inrich" into inrout

  script:
  """
  inrich  -c -a $interv -m $snps -g $genes -t $groups -o ${interv.baseName}_${groups.baseName} -i 20 -j 200
  """
}

//plot the heatmap of the INRICH p-values
process plotheatmap{
  publishDir path:params.outdir, mode:'copy'
  label 'mousegwas'
  label 'single_cpu'
  input:
    file yaml from yaml3
    file inr from inrout.collect()
  output:
    file "*.pdf" into pvalout
  script:
  """
    Rscript -e 'source(file=system.file("exec/plot_INRICH_pvalues.R", package="mousegwas"))' -c ${params.clusters} -y $yaml ${params.addheatmap} -f $inr
  """
}

