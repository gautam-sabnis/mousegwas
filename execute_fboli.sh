#!/bin/bash
#SBATCH -q batch -p compute
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -t 1-5:00
#SBATCH --mem=16GB
#SBATCH -o slurm.%j.out # STDOUT
#SBATCH -e slurm.%j.err # STDERR
module load singularity
export G=https://github.com/gautam-sabnis/mousegwas

nextflow run gautam-sabnis/mousegwas \
  --yaml $G/example/fboli.yaml \
  --input $G/example/df_growth_params.csv \ \
  --outdir fboli_output --addpostp="--loddrop 0" -profile slurm,singularity
