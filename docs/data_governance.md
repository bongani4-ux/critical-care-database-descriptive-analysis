# Data governance

This repository contains **code and documentation only**. It must never contain patient-level data, protected
health information, database extracts, credentials or access tokens.

## What is and is not committed

| Item | Committed? | Why |
|---|---|---|
| R code, configuration templates, mapping CSVs, dictionaries | yes | contain no patient data |
| `config/paths.local.yml` | **no** (git-ignored) | holds machine-specific absolute paths |
| `derived/` (harmonised datasets, `.rds`) | **no** (git-ignored) | patient-level |
| `outputs/tables`, `outputs/figures`, `outputs/logs` | **no** by default (git-ignored) | aggregate results derived from restricted data; release is a per-database decision |
| Unpacked archives (`cache_dir`) | **no** - lives outside the repository | bulky, untrusted source data |
| `config/review_reference_values.csv` | yes | aggregate figures taken from the authors' own review manuscript, no patient data |
| Synthetic test fixtures | yes | generated in code, fixed seed, not derived from any patient |

## Releasing aggregate results

Aggregate descriptive statistics are *derived* from restricted data. Several data-use agreements restrict
redistribution of derived material, or require small cells to be suppressed. Before copying anything from
`outputs/` into `outputs/shareable/` (the only output folder that may be committed):

1. Read the data-use agreement of the database (access class is in `config/database_registry.csv`).
2. Check cells flagged `small_cell = TRUE` in `*_descriptive_results.csv` (counts below `statistics.small_cell_flag`,
   default 10). The pipeline **flags** but does not suppress them, so the decision is explicit.
3. Record the decision (database, date, who approved) in `docs/release_log.md`.

## Database-specific notes

| Database | Access class (from the review) | Note |
|---|---|---|
| MIMIC-IV, eICU-CRD, NWICU, PIC, INSPIRE, Zigong | PhysioNet credentialed (PIC also owner approval per review Table 2) | credentialed-user DUA: do not redistribute data; follow PhysioNet's rules on sharing derived work |
| HiRID, SICdb | PhysioNet restricted (owner approval) | as above, plus the data owners' conditions |
| AmsterdamUMCdb | portal + end-user agreement (practising intensivist on the team) | the local copy is incomplete (see `docs/database_coverage.md`) |
| MOVER (EPIC, SIS) | UCI portal + DUA (Supplement S3) / PhysioNet credentialed (review Table 1-2) - the review is internally inconsistent | data-use terms confirmed by the project lead on 2026-10-11; correct the review's host statement |
| VitalDB | open access (CC BY 4.0) | attribution required |
| Jinhua | institutional | data-use terms confirmed by the project lead on 2026-10-11 (the terms themselves are not stored in the repository); the repository contains no Jinhua data or tables |

## Secrets and authentication

- No passwords, tokens or connection strings are used by any script (all data are read from local files).
- GitHub authentication must use the Git Credential Manager / SSH keys / `gh auth login`; never paste a token into a
  script, `.Renviron` that is committed, or a log. `.gitignore` excludes `.Renviron`, `*.pem`, `*.key`, `*.token`,
  `credentials*` and `secrets*`.
- Log files record row counts and file names, never data values.
- Before every push run `scripts/audit_repo.R` (checks tracked files for data-like extensions, large files,
  absolute local paths and token-like strings).
