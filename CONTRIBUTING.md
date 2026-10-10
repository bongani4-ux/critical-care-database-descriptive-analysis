# Contributing

The design goal is that a collaborator can **add or correct a database without editing the shared core** (`R/`).

## Add a database

1. Add one row to `config/database_registry.csv` (id, exact version, version date, access class, persistent id, `local_root`) and the id to
   `databases.eligible` in `config/analysis_config.yml`. Only databases included in the authors' review are eligible; anything else needs the
   review team's agreement first (record it in `config/excluded_resources.csv` until then).
2. Create `databases/<db_id>/adapter.R` defining
   * `adapter_meta <- list(db_id = "...", required_files = c(...))`  (relative to the database root; `.gz` twins are found automatically)
   * `adapter_build(cfg)` returning the **harmonised dataset** (contract in `R/03_variable_harmonization.R`, example: `databases/pic/adapter.R`).
3. Put item mappings in `databases/<db_id>/mapping_*.csv` (not in code) and **verify every mapped item against the database's own dictionary**
   inside the adapter (see `databases/_shared/mimic_schema.R::check_map`). A wrong itemid must stop the run.
4. Document what is true of *this* database that is not true of the others in the adapter header comment (units, time origin, what
   "admission" is, traps) and in `meta` (`hosp_death_definition`, `icu_los_definition`, `support_definition`, `age_note`, ...).
5. Add the variable rows to `dictionaries/database_variable_mappings.csv` (source field, comparability class, note).
6. Run `Rscript scripts/run_database.R <db_id> --rebuild`, read `outputs/tables/<db_id>_quality_checks.csv` and fix every FAIL.
7. If the review reports numbers for the database, add them to `config/review_reference_values.csv`. A mismatch is **not** a bug to be
   tuned away: investigate which field/denominator the review used and write it in `docs/discrepancy_report.md`.

## Rules for changes to the shared core

* Do not add database-specific code to `R/`. If an adapter needs a new capability, add a generic function and a test.
* Every new function gets a test with **synthetic** data in `tests/testthat/`. Run `Rscript tests/testthat.R`.
* Never "force agreement": report discrepancies. Do not change a plausibility range or a unit factor to make a result match.
* Do not add dependencies unless required; declare them in `DESCRIPTION` and run `renv::snapshot()`.
* Keep results reproducible: no unseeded randomness, no absolute paths, no data in the repository.

## Before every pull request / push

```bash
Rscript tests/testthat.R
Rscript scripts/audit_repo.R
```

The audit fails on data-like files, files over 2 MB, absolute local paths and token-like strings.
Read `docs/data_governance.md` before committing anything from `outputs/`.

## Commit messages

Imperative, one subject line (<= 72 characters) and a body saying *why*: `Add NWICU death rule (expire flag marks 105 deaths)`.
