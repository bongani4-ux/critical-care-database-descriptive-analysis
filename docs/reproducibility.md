# Reproducibility guide

## Environment

* R >= 4.3 (developed and run on R 4.5.2, Windows 11). Package versions are pinned in `renv.lock`.
* `renv::restore()` installs them. `arrow` and `dplyr` are *optional* (speed only); without them the engine falls back to `readr`
  (identical results, much slower on the largest tables).
* Windows-friendly: paths use `/`, no shell commands except the system `tar` (bsdtar ships with Windows 10/11) to unpack MOVER/HiRID archives.

## One-time configuration

1. `cp config/paths.example.yml config/paths.local.yml` and edit it (git-ignored). Required: `data_root` - the folder containing the
   database folders named in `config/database_registry.csv` (`local_root`). Optional: `cache_dir` (unpacked archives; keep outside the repo),
   `hirid_parquet_dir`, `jinhua_reference_dir`.
2. `Rscript scripts/check_setup.R` lists installed packages and, for every database, `READY`, `BLOCKED_NO_DATA`, `BLOCKED_MISSING_FILES` or `NO_ADAPTER`.

## Reproduce the Jinhua results

```bash
Rscript scripts/run_database.R jinhua --rebuild --no-gt
```

Writes `outputs/tables/jinhua_reproduction_vs_original.csv` (55 comparisons against the original `Table1/2/4`; set `jinhua_reference_dir`
in `paths.local.yml`). Expected: 55 MATCH, 0 DISCREPANCY. The original scripts are never run or changed.

## Run one database

```bash
Rscript scripts/run_database.R mimic_iv --rebuild      # build harmonised dataset, tables, QC, review comparison, figures
Rscript scripts/run_database.R mimic_iv                # reuse derived/mimic_iv/harmonized.rds (seconds)
```

Flags: `--no-figures`, `--no-gt`. Every run writes a timestamped log to `outputs/logs/`.

## Run everything

```bash
Rscript scripts/run_all.R --rebuild            # reference + the 12 review entries, one R process each, then cross-database outputs
Rscript scripts/run_all.R --only=pic,zigong    # subset
```

Indicative run times on a 12-core / 32 GB machine with `arrow`: Jinhua 1 min, PIC 2, NWICU 1-2, Zigong 0.5, SICdb 2, INSPIRE 4,
MOVER-EPIC 1, MOVER-SIS 2, VitalDB < 1, AmsterdamUMCdb < 1, MIMIC-IV ~15, eICU-CRD ~15, HiRID ~60 (1.7 billion rows).

## Regenerate cross-database tables, figures and documents

```bash
Rscript -e "source('R/00_setup.R'); ccdb_init(); run_cross_database()"
Rscript scripts/build_docs_tables.R              # docs/generated/*.md from the outputs
```

## Tests and audit

```bash
Rscript tests/testthat.R       # synthetic-data unit tests (no data access needed)
Rscript scripts/audit_repo.R   # governance audit before pushing
```

## What makes a run reproducible

* Configuration is data (`config/*.yml|csv`), not code; seeds are set (`project.seed`); no stochastic step exists in v0.1.
* Outputs are overwritten atomically; reruns do not append or duplicate.
* The harmonised dataset is cached per database; `--rebuild` ignores the cache.
* Every number in a table is traceable: result row -> `variable` + `note` (definition) -> adapter -> source table/field
  (`dictionaries/database_variable_mappings.csv`).
