# TCGA-BRCA STAR Counts descriptive file-level report

## Input scope

The input comprises 40 original TSV files listed in input-files.txt. Each complete table contains 60,664 rows and 9 columns; all complete tables are retained in raw. The first four rows are STAR summary categories, and the remaining 2000 rows have gene_id values beginning ENSG. All files have identical gene-ID order. Original gene IDs, including version suffixes, and original gene order were preserved.

All summaries use only unstranded counts on ENSG rows. STAR summary rows are excluded. TPM and other columns are not treated as counts. Every ENSG unstranded value was checked to be finite, nonnegative, and integer-valued.

## Descriptive summaries

input-audit.csv records the file count, dimensions, gene count per file, and aggregate count and zero-value checks.

sample-summary.csv contains one row per original filename, sorted by filename. It reports the sum of ENSG unstranded counts, numbers of genes with positive and zero counts, arithmetic mean across all 2000 genes (including zeros), and maximum gene count.

gene-summary.csv contains one row per ENSG gene in original order. It reports total unstranded counts across all 1,231 files, numbers of files with positive and zero counts, arithmetic mean across all files (including zeros), and maximum count across files. Gene-length vectors were accumulated table by table, using numeric totals to avoid integer overflow; no second dense gene-by-file matrix was created.

Across 80000 gene/file cells, total unstranded gene counts are 399459 and zero-valued cells number 540. There are 2000 genes detected in at least one file and 0 genes with zero counts in every file.

## Interpretation limits

These are descriptive file-level summaries of raw counts. Filenames identify input files, not necessarily unique patients; files must not be treated as independent patients. Counts have not been normalized for library size or other technical differences, so their magnitudes alone do not establish biological differences.

No differential-expression model, biological group comparison, protein identification, or clinical conclusion was performed or is supported by this analysis.
