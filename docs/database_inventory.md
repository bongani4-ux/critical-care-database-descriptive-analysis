# Phase 1 - Definitive inventory (audit of the actual files)

*Audit date: 2026-10-11. Source of the eligible list: the authors' review - `Tables.docx` (Table 1-5, "12 included databases"),
`Supplement_S3_Version_Access_Verification_Log.docx` (version / host / access / charting basis) and the manuscript text
("twelve entries", "eleven distinct resources"). All paths are relative to the data root.*

## A. Eligibility decision

| Entry in the review | Eligible | Version used here | Evidence |
|---|---|---|---|
| MIMIC-IV | yes | v3.1 | Table 1; S3 |
| eICU-CRD | yes | v2.0 | Table 1; S3 |
| INSPIRE | yes | **v1.4.2** (project decision, 2026-10-11) | review text says v1.3 (Table 1) and v1.4.2 (S3); both local copies hold the same 130,960 operations / 99,886 patients; the review's ICU LOS (1.04 d) reproduces on v1.3 only (v1.4.2: 1.00 d). v1.3 is retained as a version check (`inspire_v1_3`); see `discrepancy_report.md` |
| MOVER-EPIC, MOVER-SIS | yes (2 entries, 1 resource) | v1.0 | Table 1; S3 (host differs between the two) |
| HiRID | yes | v1.1.1 | Table 1; S3 |
| SICdb | yes | v1.0.8 | Table 1; S3 |
| NWICU | yes | v0.1.0 | Table 1; S3 |
| AmsterdamUMCdb | yes | v1.0.2 | Table 1; S3 |
| PIC | yes | v1.1.0 | Table 1; S3 |
| VitalDB | yes | v1.0.0 | Table 1; S3 |
| Zigong (ZFPH) | yes | v1.1 | Table 1; S3 |
| MIMIC-BR, Zhejiang PPH, K-MIMIC | **no** | - | explicitly "not included" (S3, Table 4) |
| MIMIC-IV v2.2 (`MIMIC4_2.2_.zip`), INSPIRE v1.0 | **no** | - | other versions; present locally only |
| **Jinhua** | reference only | cleaned extract | not in the review; it is the origin of the analytical framework |

## B. Per-database inventory

| Database | Source data (local) | Existing descriptive work found | Dictionaries / documentation found | Reproducing the Jinhua framework |
|---|---|---|---|---|
| **Jinhua** | `jinhua database/清洗后数据/` (19 CSV, lab file 2 GB) | `code/01-06_JINHUA_*.R`, `README_JINHUA*.md`, `output/tables/Table1-9`, 18 figures | `JINHUA_data_dictionary.xlsx/csv`, `JINHUA_headers.txt`, `JINHUA_table_inventory.csv` | **done**: 55/55 values reproduced |
| **MIMIC-IV v3.1** | `mimic-iv-3.1/` (`hosp/`, `icu/`) | AKI/AKD script only (`codes/AKI-AKD analysis/MIMIC IV`) | `data dictionaries/mimic_IV_3.1 data dictionary.xlsx`; item dictionaries `d_items`, `d_labitems` | full (cohort, outcomes, ICD-9/10, vitals, labs, support) |
| **eICU-CRD v2.0** | `eicu-collaborative-research-database-2.0/` (30 CSV, of which `eicu biomarkers.csv` is a stray non-eICU file; `vitalPeriodic` 7.9 GB) | AKI/AKD script only | `data dictionaries/eicu data dictionary.xlsx` | full; admission = hospital stay, times re-based |
| **NWICU v0.1.0** | `northwestern-icu-nwicu-database-0.1.0/.../data/{nw_hosp,nw_icu}` | AKI/AKD script only | none found beyond its own `d_items` (344 items) / `d_labitems` | full except ventilation, vasopressors, MAP |
| **SICdb v1.0.8** | `SICdb/SICdb/` | AKI/AKD script only | `Documentation.pdf`; `d_references` (all codes decoded) | full; no hospital LOS |
| **AmsterdamUMCdb v1.0.2** | `Amsterdamumc/` - **6 of the usual tables; `numericitems.csv` is missing** | creatinine export script only | `fpubh-10-852410.pdf` (paper), `arfeula_v1.6.pdf` (end-user licence); no data dictionary | cohort, outcomes, support; **vitals/labs/severity BLOCKED** (needs `numericitems.csv`) |
| **HiRID v1.1.1** | `hirid-.../` (archives) + `hirid_extracted/observation_tables` (250 parquet parts, 33,904 patients) | data-dictionary + figure scripts (`codes/HiRID data dictionary`) | `reference_data/hirid_variable_reference.csv`, `schemata.pdf` | full for what exists; no hospital outcome, no ICD |
| **PIC v1.1.0** | `paediatric-intensive-care-database-1.1.0/` | dictionary / summary-table / figure scripts (`codes/PIC data dictionary`) - *the template the Jinhua scripts mirror* | `PIC.pdf`; `D_ITEMS`, `D_LABITEMS` | full except organ support (none recorded) |
| **Zigong v1.1** | `Critical care database comprising patients with infection.../DataTables` | dictionary script (`codes/Zigong data dictionary`) | `datDictionary.csv`; paper PDF | full; ICU stays reconstructed |
| **INSPIRE v1.4.2** (also v1.3, v1.0 present) | `inspire-...-1.4.2/` (gz + csv twins) | dictionary / demographics scripts (`codes/INSPIRE data dictionary`) | `schema.csv`, `parameters.csv`, `CHANGELOG.txt`, `INSPIRE.pdf`, `inspire data dictionary.xlsx` | cohort, outcomes, ICD-10-CM, labs, vitals, ward support |
| **VitalDB v1.0.0** | `vitaldb-.../` (`clinical_data.csv`, `lab_data.csv`, 6,388 `.vital` waveform files) | `codes/VitalDB/.../scripe analysis.R` | `clinical_parameters.csv`, `lab_parameters.csv`, `track_names.csv`, `Vitaldb.pdf`, `vital DB数据集概要.xlsx` | cohort, outcomes, labs; **waveform vital signs not parsed (v0.1)** |
| **MOVER-EPIC v1.0** | `mover/EPIC_EMR.tar(2).gz` (1.1 GB archive, 3.6 GB `patient_labs`) | creatinine export script only | none found | cohort, outcomes, ICD, labs; no vitals, no ICU times |
| **MOVER-SIS v1.0** | `mover/sis_emr.tar(2).gz` | none | none found | intra-operative vitals + 5 labs only; no outcomes |

## C. Structural differences that shape everything downstream

* **What an "admission" is differs** (hospital stay, case, surgical case, surgical record) - `docs/methods.md` section 2.
* **ICU structure**: explicit ICU-stay tables (MIMIC-IV, NWICU, PIC, eICU unit stays, SICdb case); reconstructed from transfers (Jinhua, Zigong, INSPIRE times);
  ICU flag only (MOVER-EPIC); none (MOVER-SIS, HiRID is ICU-only).
* **Clocks**: absolute shifted datetimes (MIMIC, NWICU, PIC, HiRID), unit-stay offsets in minutes (eICU), seconds from ICU admission (SICdb),
  milliseconds (AmsterdamUMCdb), hours from admission (Zigong), minutes on a patient clock (INSPIRE, Jinhua), seconds from case start (VitalDB), wall-clock strings (MOVER).
* **Coding**: ICD-9 + ICD-10 (MIMIC-IV, NWICU, eICU, MOVER-EPIC), ICD-10 variants (Jinhua, PIC, Zigong: Chinese extension; INSPIRE: ICD-10-CM; SICdb: ICD-10-GM, principal only), none (HiRID, AmsterdamUMCdb, MOVER-SIS, VitalDB two flags).
* **Cohort rules**: Jinhua is a neurosurgical hospital cohort; Zigong is infection-only; NWICU is COVID-rich; PIC is paediatric; INSPIRE/VitalDB/MOVER are perioperative.

## D. Access / information still needed

| Need | For | Why |
|---|---|---|
| `numericitems.csv` of AmsterdamUMCdb v1.0.2 (portal; practising-intensivist agreement) | AmsterdamUMCdb | the only source of vitals, labs and APACHE scores |
| `numericitems.csv` still pending | AmsterdamUMCdb | to be added by the project lead later |
| Optional: MOVER-EPIC procedure/medication/post-op tables | MOVER-EPIC | not used in v0.1 |
