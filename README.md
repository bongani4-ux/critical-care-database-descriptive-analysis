# critical-care-database-descriptive-analysis

Reproducible R workflows for **harmonized descriptive analysis across the critical care databases and versions included in our
database review**. The Jinhua cohort analysis is the reference implementation; the same framework is applied to the 12 entries
(11 resources) of the *Critical Care Database Review*.

> **No patient-level data, database extracts, credentials or tokens are, or may ever be, committed here.** The repository
> contains code, configuration, dictionaries and documentation only. Read [docs/data_governance.md](docs/data_governance.md) first.

## What it does

For every eligible database an adapter builds a **harmonised dataset** (admission / ICU-stay / diagnosis / first-24-hour
measurement / organ-support / severity tables with a validated contract). The shared core then produces, with explicit
denominators: cohort and patient flow, demographics, admission characteristics, vital signs and laboratory variables,
comorbidities, organ support, ICU and hospital outcomes, missing-data summaries, tables and figures, and automated QC.
Variables that a database cannot support are reported **unavailable**, never as zero.

| Entry (review) | Version | Setting | Access class (per the review) |
|---|---|---|---|
| MIMIC-IV | v3.1 | mixed hospital + ICU, USA | PhysioNet credentialed |
| eICU-CRD | v2.0 | multi-centre adult ICU, USA | PhysioNet credentialed |
| NWICU | v0.1.0 | adult ICU (COVID-rich), USA | PhysioNet credentialed |
| SICdb | v1.0.8 | adult ICU, Austria | PhysioNet restricted (owner approval) |
| AmsterdamUMCdb | v1.0.2 | adult ICU, Netherlands | portal + end-user agreement |
| HiRID | v1.1.1 | adult ICU, Switzerland | PhysioNet restricted (owner approval) |
| PIC | v1.1.0 | paediatric ICU, China | PhysioNet credentialed (+ owner approval) |
| Zigong (ZFPH) | v1.1 | adult ICU, infection, China | PhysioNet credentialed |
| INSPIRE | v1.4.2 *(project decision; the review text also says v1.3 - see discrepancy report)* | perioperative, South Korea | PhysioNet credentialed |
| VitalDB | v1.0.0 | perioperative, South Korea | PhysioNet open (CC BY 4.0) |
| MOVER-EPIC / MOVER-SIS | v1.0 | perioperative, USA | UCI portal + DUA *(review Table 1 says PhysioNet credentialed)* |
| **Jinhua** (reference, *not* a review entry) | cleaned extract | hospital, neurosurgical-dominant, China | institutional - terms to be confirmed |

Out of scope by design: MIMIC-BR, Zhejiang PPH, K-MIMIC, and the other local copies (MIMIC-IV v2.2, INSPIRE v1.0) - `config/excluded_resources.csv`.

## Repository layout

```
config/        database_registry.csv  analysis_config.yml  review_reference_values.csv  paths.example.yml  (paths.local.yml: yours, git-ignored)
R/             00_setup ... 14_pipeline: shared, database-agnostic core (registry, cohort, harmonisation, statistics, QC, figures)
databases/     <db_id>/adapter.R + mapping_*.csv  - everything database-specific lives here  (_shared/ = MIMIC-schema builder)
dictionaries/  master_variable_dictionary.csv  database_variable_mappings.csv  comorbidity_definitions.csv  analyte_definitions.csv
               unit_conversions.csv  jinhua_reference_variables.csv
scripts/       check_setup.R  run_database.R  run_all.R  build_docs_tables.R  audit_repo.R
tests/         testthat/ - synthetic-data unit tests
docs/          methods, database_inventory, database_coverage, data_limitations, discrepancy_report, jinhua_reference_analysis,
               reproducibility, data_governance
outputs/       tables/ figures/ logs/   (generated; git-ignored by default)
derived/       harmonised patient-level datasets (generated; git-ignored)
```

## Quick start

```bash
# 1. R >= 4.3.  Restore the pinned package set (arrow + dplyr are optional but make MIMIC/eICU/HiRID ~100x faster)
Rscript -e "install.packages('renv'); renv::restore()"

# 2. Point the project at your data (git-ignored file)
cp config/paths.example.yml config/paths.local.yml      # then edit data_root, cache_dir, ...

# 3. Check packages, configuration and which databases are READY / BLOCKED
Rscript scripts/check_setup.R

# 4. Run one database, or everything (each database in its own R process)
Rscript scripts/run_database.R pic --rebuild
Rscript scripts/run_all.R --rebuild

# 5. Test and audit before you push
Rscript tests/testthat.R
Rscript scripts/audit_repo.R
```

Full instructions (including how to reproduce the Jinhua tables): [docs/reproducibility.md](docs/reproducibility.md).

## Data preparation

Place each database in its own folder under `data_root` (folder names: `local_root` in `config/database_registry.csv`).
Two databases are shipped as archives and are unpacked **outside the repository** into `cache_dir` on first use:
MOVER (`EPIC_EMR.tar.gz`, `sis_emr.tar.gz`) and, unless `hirid_parquet_dir` is set, HiRID (`raw_stage/*_parquet.tar.gz`).
A database whose files are missing is reported `BLOCKED`, never skipped silently.

## Outputs (`outputs/`, one set per database `<db_id>_*`)

`descriptive_results.csv` (long format: variable, level, stat, n, denominator, %, median/IQR, text, availability, note) -
`missing_data.csv` - `patient_flow.csv` - `domain_availability.csv` - `quality_checks.csv` - `review_comparison.csv` -
`table1.html` - `fig_*.png` - cross-database: `cross_database_*.csv`, coverage heat-map, mortality plot.
`scripts/build_docs_tables.R` turns them into the markdown matrices cited in the docs.

## Validation in one paragraph

The harmonised pipeline reproduces **55/55** compared values of the original Jinhua `Table1/2/4`; every database passes the
contract and result-table QC; reproduced values are compared with the review at its printed precision. Most mismatches were traced
to a specific cause (denominator, unit, field or version) and a few remain **unresolved** - all in
[docs/discrepancy_report.md](docs/discrepancy_report.md). Several of the review's numbers do not describe what their table captions
say (MIMIC-IV, MOVER-EPIC, VitalDB, INSPIRE, SICdb, AmsterdamUMCdb) - these are reported, not silently corrected. The INSPIRE
version decision (v1.4.2 analysed; the review's numbers were charted on v1.3) is recorded in the registry.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `config/paths.local.yml not found` | copy `config/paths.example.yml` and set `data_root` |
| `BLOCKED_MISSING_FILES` in `check_setup.R` | a required file is absent (the `missing` column names it); AmsterdamUMCdb vitals/labs/severity need a complete `numericitems.csv` (extract with `databases/amsterdamumcdb/extract_numericitems.py`; the pipeline still runs without it and reports those domains as blocked) |
| `mapping does not match the item dictionary` | an item id in `databases/<db>/mapping_*.csv` does not carry the expected label in *your* version of the database - fix the mapping, do not relax the check |
| very slow MIMIC/eICU/HiRID run | install `arrow` and `dplyr`; keep `io.use_arrow: true` |
| `tar failed` unpacking MOVER/HiRID | needs the system `tar` (bsdtar, included in Windows 10/11); check free space in `cache_dir` |
| `Column ... is type 'integer' but expecting 'double'` | a grouped summary returned mixed types; cast explicitly in the adapter |

## Citation, licence, contributing

Code: MIT (`LICENSE`) - the licence covers the code only; **each database keeps its own data-use agreement**. Cite the code via
`CITATION.cff` and each database via the primary citations in [docs/database_coverage.md](docs/database_coverage.md).
Contributions: [CONTRIBUTING.md](CONTRIBUTING.md).

## Reproducing the review

* `review_reproduction/` - the review's own charted values and figure code (Supplemental file 6) with a consistency check; `python check_charted_values.py`, `python make_figures.py`.
* `docs/review_reproducibility.md` - how each charted value was produced and which ones this pipeline reproduces (and which need the authors' definitions).
* `scripts/run_granularity.R`, `scripts/inspire_version_update.R`, `scripts/build_data_dictionaries.R`, `scripts/diagnose_support_denominators.R` - recording frequency (one common rule), INSPIRE v1.4.2 update table, INSPIRE-style data dictionaries, organ-support denominator test.
