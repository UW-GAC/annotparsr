# annotparsr

This package includes tools to work with annotation files produced by
\href{https://sites.google.com/site/jpopgen/wgsa}{WGSA}.

## Installation

You can install annotparsr from github with:

```R # install.packages("devtools") 
devtools::install_github("annotparsr/UW-GAC") ```

## Example

This'll come, once I have some!

```R 

# list all fields in an annotation file: 
all_fields <- get_fields("WGSA_chr_1.gz")


# select the #chr, pos, ref, alt, VEP_ensembl_Transcript_ID, and
# VEP_ensembl_Gene_ID fields. Parse the VEP_ensembl_Transcript_ID and
# VEP_ensembl_Gene_ID complex fields, and write the output to file

target_columns <-
  c("`#chr`", "pos", "ref", "alt", "VEP_ensembl_Transcript_ID", 
    "VEP_ensembl_Gene_ID")

columns_to_split <-
  c("VEP_ensembl_Transcript_ID", "VEP_ensembl_Gene_ID")

parse_to_file(soure = "WGSA_chr_1.gz", 
  destination = "parsed_chr_1.csv", 
  desired_columns = target_columns, 
  to_split = columns_to_split, 
  chunk_size = 1000) 
```