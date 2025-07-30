#!/bin/bash
#SBATCH -q batch -p compute
#SBATCH -N 1
#SBATCH -n 2
#SBATCH -t 12:00:00 # (DD-HH:MM:SS)
#SBATCH --mem=8GB
#SBATCH -o slurm.%j.out # STDOUT
#SBATCH -e slurm.%j.err # STDERR

# LOAD NEXTFLOW
module use --append /projects/omics_share/meta/modules
module load nextflow
module load singularity

NXF_VER=22.04.3 nextflow run mainPP.nf   --yaml  BXD_inbred_combined.yaml --shufyaml BXD_inbred_combined_shuffle.yaml --input bxd_jabs_2025-02-19.csv --outdir  output_pp --addpostp="--loddrop 0" -profile slurm,singularity  --resume

