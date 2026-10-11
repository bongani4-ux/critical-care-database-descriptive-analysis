# Reproducing the review: charted values and figures (R)

This folder holds the numbers the review charted (its Supplemental file 6) and **R code that redraws every figure from them**.
The review is still being revised, so nothing is typed into the code: change a CSV (or point `--values` at an updated copy) and the figures follow.

| Question | Where |
|---|---|
| Can the review's **figures** be regenerated from its charted values? | here: `Rscript review_reproduction/R/make_figures.R` |
| Can the charted values be regenerated from the databases? | the pipeline in this repository (`R/`, `databases/`, `scripts/`); status per value in [`docs/review_reproducibility.md`](../docs/review_reproducibility.md) |

The review's own code does not compute any statistic: its values are hard-coded numbers charted from each database (patient-level queries
where access allowed, otherwise documentation). The original matplotlib code is in the review's Supplemental file 6; this folder keeps only the data
and the R re-implementation.

## Contents

```
charted_values/   01_cohort ... 08_overall_coverage .csv  (database-level summary statistics only; no patient-level data)
search_flow/       flow_counts.json (search-flow counts), screen_records.json, pubmed_records.json (screening records)
R/make_figures.R  Figure_1 cohort size, Figure_2 age and sex, Figure_3 domain coverage, Figure_4 mortality, Figure_5 organ support,
                  FigureS1_flow (search flow), FigureS2_granularity   ->  PNG + TIFF (LZW) + PDF, 600 dpi
R/check_charted_values.R   internal consistency (shared databases, ranges, 85-subdomain arithmetic, search-flow integrity)
```

## Run (R >= 4.1; packages ggplot2, patchwork, ragg, data.table, jsonlite)

```bash
Rscript review_reproduction/R/check_charted_values.R
Rscript review_reproduction/R/make_figures.R                       # -> review_reproduction/R/figures/ (git-ignored)
Rscript review_reproduction/R/make_figures.R --values=<dir>        # figures from an updated copy of the CSVs
Rscript review_reproduction/R/make_figures.R --granularity=pipeline  # Figure S2 from this pipeline's own results (needs scripts/run_granularity.R first)
```

Differences from the matplotlib originals: the infection-specific and mixed-setting bars are shown as lighter tints instead of hatching, and label offsets and
box corners are approximate. Values, ordering, panels and labels are identical. The serif face is the system serif (Times New Roman on Windows).

## Provenance and licence

`charted_values/` and `search_flow/` are copied unchanged from the review's Supplemental file 6 (version of 2 September 2026), except `search_flow/flow_counts.json`, which gained
`repo_dupes` (41) and `epmc_dupes` (8) - the two duplicate counts the original Python computed from its record files (41 + 8 = 49 = `dupes`).
Confirm the licence the authors want for these files before making the repository public (the repository root is MIT).
