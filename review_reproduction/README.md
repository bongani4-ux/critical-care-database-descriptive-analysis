# Reproducing the review (figures, charted values and how each value was produced)

This folder holds the **code and data that the review itself published** as its Supplemental file 6
("Charted data file and figure-generating source code"), plus a consistency check. It answers two different questions:

| Question | Where |
|---|---|
| Can the review's **figures** be regenerated from its charted values? | here (`code/`): yes - `make_figures.py`, `figure_flow.py` |
| Can the review's **charted values** be regenerated from the databases? | the R pipeline in this repository (`R/`, `databases/`, `scripts/`); the value-by-value status is in [`docs/review_reproducibility.md`](../docs/review_reproducibility.md) |

**Important:** the review's own code does not compute any statistic. `dbdata.py` and the CSVs in `charted_values/` are
hard-coded numbers that the authors charted from each database (patient-level queries where access allowed, otherwise source
documentation - basis per value in the review's Supplemental file 4). The only computation in the review's code is arithmetic
on those numbers (totals, overall coverage = documented subdomains / 85) and the screening-flow counts.

## Contents

```
charted_values/   01_cohort ... 08_overall_coverage .csv (database-level summary statistics only; no patient-level data)
code/             dbdata.py (the same values as a Python module + figure styling), make_figures.py (Figures 1-5, S2),
                  figure_flow.py + flow_data.py + physionet_records.py + pubmed_records.py + *.json (Figure S1 and screening record),
                  check_charted_values.py (new: checks CSVs == dbdata.py and the 85-subdomain arithmetic)
```

## Run (any OS; Python >= 3.9)

```bash
python -m pip install "matplotlib>=3.8" numpy
cd review_reproduction/code
python check_charted_values.py     # CSVs, dbdata.py and coverage arithmetic agree
python make_figures.py             # Figures 1-5 and S2 -> ./figures/ (git-ignored), 600 dpi PNG/TIFF/PDF
python figure_flow.py              # Figure S1 (PRISMA-ScR flow), counts computed from the screening records
```

Run these as normal scripts from `code/` (they import `dbdata`); do not use `python -I`. The figures use a serif font
metrically compatible with Times New Roman and fall back to DejaVu Serif if it is missing - layout is unchanged, glyph shapes differ slightly.

## Provenance and licence

The files were authored by the review team and are copied unchanged from Supplemental file 6 (version of 2 September 2026),
except for the added `check_charted_values.py` and this README. Add the licence the authors want for them before making the repository public
(the repository root is MIT; confirm that this also applies to the review's code and charted values).
