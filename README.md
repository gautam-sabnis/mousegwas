We will run this pipeline in two parts:

- Implement GWAS to perform association testing and estimate heritability. 
- Run post-processing scripts that leverage GWAS results to prepare figures and perform other downstream analyses. 

To implement GWAS, you need to edit `nextflow.config` file:

```bash
Include line 20, i.e, 

container = '/projects/kumar-lab/sabnig/Builds/mousegwas_gs.sif'

and comment out line 21, i.e, 

// container = '/projects/kumar-lab/sabnig/Pipelines/gwas/mousegwas_vk.sif'
```

and provide the following files: 
```
yaml file - example/BXD_inbred_combined.yaml
shufyaml file - example/BXD_inbred_combined_shuffle.yaml
phenotype/input file - example/bxd_jabs_2025-02-19.csv 

Note: The phenotype/yaml file should contain, in addition to the phenotypes, at least two fields, namely, Strain and MouseID. 
```

To run GWAS, execute: 
```
sbatch submit_gwas.sh

Note: You can specify the directory where you want to save your results using the `outdir` flag. It is highly recommended that you set it to output. 
```


After the GWAS scripts have finished running, you can view the results in the output folder. 

To start the post-processing step, you need to edit `nextflow.config` file: 

```bash
Comment out line 20, i.e, 

// container = '/projects/kumar-lab/sabnig/Builds/mousegwas_gs.sif'

and include line 21, i.e, 

container = '/projects/kumar-lab/sabnig/Pipelines/gwas/mousegwas_vk.sif'
```

Next, execute: 
```
sbatch submit_pp.sh

Note: You can specify the directory where you want to save your results using the `outdir` flag. It is highly recommended that you set it to output_pp. 
```
