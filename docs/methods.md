# Methods

This document describes what the code does. Every rule below is implemented in `R/` or in a database adapter
(`databases/<db_id>/adapter.R`) and is exercised by `tests/` or the automated QC checks (`outputs/tables/*_quality_checks.csv`).

## 1. Scope

*Eligible databases* are exactly the entries of the authors' *Critical Care Database Review*: **12 entries /
11 distinct resources** (MOVER contributes two entries, EPIC and SIS) - `config/database_registry.csv`. Resources the
review lists as "not included" (MIMIC-BR, Zhejiang PPH, K-MIMIC) and other local copies (MIMIC-IV v2.2, INSPIRE v1.0)
are listed in `config/excluded_resources.csv` and are **not analysed**.

*Jinhua* is **not** a review entry. It is the analytical **reference implementation**: its scripts define the
descriptive framework, and the harmonised code is validated by reproducing its published tables (section 9).

## 2. Units of analysis

Three nested units are used; which one a database offers is a property of the database and is never hidden:

| Unit | Meaning | Used for |
|---|---|---|
| **admission** | one hospital encounter | primary denominator ("all admissions") |
| **patient** | first admission of each patient (`is_first_admission`) | patient-level stratum; matches the review's "unique patient" convention |
| **icu_stay** | one ICU stay inside an admission | ICU LOS, in-ICU death, ICU readmission |

What "admission" is in each database (verified against the data):

| Database | admission = | notes |
|---|---|---|
| MIMIC-IV, NWICU | `hadm_id` | admissions without an ICU stay are retained (ICU is a flag) |
| eICU-CRD | `patienthealthsystemstayid` (hospital stay) | ICU stay = `patientunitstayid`; includes step-down/transfer unit stays as recorded |
| SICdb | `CaseID` | one ICU stay per case |
| AmsterdamUMCdb | `admissionid` | includes medium-care (MC-only) admissions, which are **not** ICU |
| HiRID | `patientid` | one ICU admission per patient |
| PIC | `HADM_ID` | all admissions are PICU admissions |
| Zigong | `INP_NO` | one admission per patient; ICU stays reconstructed from transfers |
| INSPIRE | `hadm_id` | built from operations (an admission can hold several operations) |
| VitalDB | `caseid` (surgical **case**) | no admission id exists; a patient with several cases appears several times |
| MOVER-EPIC | `MRN` + `HOSP_ADMSN_TIME` | the 65,728 rows of `patient_information` are surgical **records**, not patients |
| MOVER-SIS | `PID` | no separate patient identifier; record = patient |
| Jinhua | `hadm_id` | ICU episodes reconstructed from ward transfers |

## 3. The harmonised dataset

Every adapter returns the same contract (`R/03_variable_harmonization.R`): `meta`, `flow`, `admission`, `icu_stay`,
`diagnosis`, `direct_flags`, `measurements`, `support`, `severity`, `availability`. `validate_harmonized()` checks
key uniqueness, foreign keys (ICU stays, diagnoses and measurements must belong to an admission), value coding
(sex, death flags), the consistency of `icu_flag` with the ICU table, plausible ranges and analyte names.
The shared core never sees database-specific tables, so adding a database never touches `R/`.

## 4. Cohort construction and patient flow

All admissions in a database are kept. ICU admission, surgery and organ support are **flags, not filters** (the
Jinhua convention). Each adapter records a patient-flow table (`flow_add()`); counts are computed from the tables
themselves, and QC check *"patient-flow final step equals cohort"* fails if they disagree.

## 5. Definitions that differ between databases (and how they are kept separate)

**Mortality is never merged across definitions.** Three endpoints are reported separately:

| Endpoint | Variable | Notes |
|---|---|---|
| in-hospital death | `hosp_death` | ascertainment documented per database (`meta$hosp_death_definition`) |
| death during an ICU stay | `icu_death` (stay level) | not ascertainable in several databases |
| death at last recorded follow-up | `death_any_followup` | mixes in-hospital and post-discharge deaths; follow-up length differs |

Documented rules that are non-obvious (each was found and verified in the data):

* **Jinhua** - `medical_record.expire_flag` is patient-level (2.3x over-count); in-hospital death = discharge disposition "Die".
* **NWICU** - `hospital_expire_flag` marks 105 admissions only; death = discharge location `EXPIRED*` **or** a death time inside the admission (reproduces the review's 3,558 / 3,401 / 3,554).
* **INSPIRE** - `inhosp_death_time` is propagated to all operations of a patient who ever died in hospital; admission-level death requires the death time to lie inside the admission window.
* **SICdb** - hospital death = `HospitalDischargeType` 2028; ICU death = `DischargeState` 2215; hospital LOS is not recorded. Sex codes 735/736 are decoded from the database's own `d_references` (male/female).
* **AmsterdamUMCdb** - `lengthofstay` is ICU/medium-care stay in **hours**; no hospital outcome; death during the admission = `destination == "Overleden"`; `dateofdeath` is follow-up death.
* **HiRID** - `discharge_status` is the ICU discharge status; no hospital outcome; ICU LOS = last observation - admission time.
* **Zigong** - in-hospital death = `Status_Discharge == "Dead"`; all times are hours from admission.
* **eICU-CRD** - ages above 89 are set to 90; the admission is the hospital stay and times are re-based from unit-stay offsets to the hospital clock.

Age is released as groups in AmsterdamUMCdb (numeric age unavailable) and in 5-year bins in HiRID/SICdb; medians in
those databases are approximate and flagged in `meta$age_note`.

## 6. Vital signs and laboratory variables (`R/06_vitals_and_laboratory.R`)

**Definition (harmonised):** the *first valid value* of each analyte inside `[index, index + 24 h]`, converted to a
canonical unit (`dictionaries/analyte_definitions.csv`), after removing implausible values. The count of valid values
in the window is also reported (measurement density).

* **Index time**: first ICU admission for ICU-based databases; hospital admission for databases without ICU stays
  (INSPIRE, VitalDB, MOVER-EPIC, Jinhua); operating-room start for MOVER-SIS (no admission time exists). Coverage
  denominators are units that *have* an index time.
* **Unit conversion** (`dictionaries/unit_conversions.csv`): a unit that is missing or not in the table is **not** passed
  through - the value is excluded and counted (`unit_status`), unless an adapter explicitly declares an assumption
  (Jinhua SpO2; MOVER-SIS laboratory units).
* **Item mappings** are CSV files per database (`databases/<db_id>/mapping_*.csv`). Where a database provides an item
  dictionary, the adapter **verifies each mapped item against it** and stops if the label does not match
  (this is what prevents a wrong itemid from silently producing a plausible-looking table).
* Different clinical sources are pooled by analyte (e.g. invasive and non-invasive blood pressure; chemistry and blood-gas sodium);
  the source mix is in the mapping files and is a documented limitation.

*Difference from Jinhua:* the reference script keeps the **last** value per admission and never produced its laboratory
table (see `docs/jinhua_reference_analysis.md`); the harmonised window is therefore not a replication of that
convention but of its *intent* (a descriptive value per admission) on a definition that is valid across databases.

## 7. Comorbidities (`R/07_comorbidities.R`)

The 32 groups and ICD-10 regular expressions are the Jinhua definitions, stored punctuation-free in
`dictionaries/comorbidity_definitions.csv`; a unit test proves they are behaviourally identical to the original
(dotted) expressions on every ICD-10-shaped code. For ICD-9-coded databases (MIMIC-IV, NWICU, eICU-CRD, MOVER-EPIC)
**analyst-defined ICD-9-CM equivalents** are used. These are *not* a published crosswalk; they are approximate and the
affected comparisons are classed "comparable after harmonization", not "directly comparable". ICD-9 E-codes and V-codes
are never read as ICD-10. Databases with direct non-ICD flags (SICdb, VitalDB) use those flags for the groups they cover.

Prevalence is reported (i) over all units (Jinhua convention: absent code = 0) and (ii) over units with any coded diagnosis,
and the proportion with any coded diagnosis is itself reported, so under-coding is visible.

## 8. Organ support (`R/08_treatments_and_support.R`)

`mech_vent`, `rrt`, `vasopressor`, `intubation`, `tracheostomy`. A type missing from `meta$support_available` is shown as
**unavailable**, never as 0 %. Definitions differ (procedure events, treatment strings, signals, charted modes, orders)
and are written beside each result (`note` column) and in each adapter.

## 9. Statistics

Continuous: median (Q1-Q3) (type 7 quantiles) with mean (SD) stored; categorical and binary: n (%). Every row carries
its **denominator** and `n_missing`. Counts below `statistics.small_cell_flag` are flagged (`small_cell`), not suppressed.
Two strata are produced for every table: **admission** (all admissions) and **patient** (first admission per patient).
No inferential tests are computed (the Jinhua reference reports none); comparing databases is descriptive.
No stochastic procedure exists in v0.1; a seed is set anyway (`project.seed`).

## 10. Quality assurance

1. **Contract validation** of the harmonised dataset (16 checks).
2. **Result-table consistency**: numerator <= denominator, % = 100 n/d, n + missing = denominator, ordered quartiles,
   patient-flow = cohort, one first-admission flag per patient.
3. **Independent recomputation** of headline statistics straight from the dataset.
4. **Jinhua reproduction** (`outputs/tables/jinhua_reproduction_vs_original.csv`): 55 values compared with the original
   `Table1/2/4` outputs; discrepancies would be reported, never adjusted.
5. **Review comparison** (`*_review_comparison.csv`): reproduced values vs the *Critical Care Database Review*, matched to the
   review's own printed precision. The unit of analysis at which a value matches is reported (`also_matches_at_level`).
   Where the review's value matches a different denominator or a different field, that is a finding about the
   review (see `docs/discrepancy_report.md`), not something the code corrects.
6. **Unit tests** (`tests/testthat/`) on synthetic data only.
7. **Governance audit** (`scripts/audit_repo.R`) before any push.

## 11. Engineering

* One database per R process (`scripts/run_all.R`); the harmonised dataset is cached in `derived/<db_id>/harmonized.rds`.
* Multi-gigabyte tables are streamed in chunks; if the `arrow` package is installed the scan is multi-threaded with the
  filter applied before rows reach R (identical results, ~100x faster on MIMIC `chartevents`).
* Outputs are written atomically (temp file + rename) and overwritten on rerun, never appended.
* Long tables are never held for two databases at once.

## 12. Deviations from the original Jinhua analysis (all deliberate and documented)

| Original | Here | Reason |
|---|---|---|
| Admission physiology from the admission note | not harmonised | does not exist in other databases |
| Last laboratory value per admission (never produced) | first value in first 24 h | valid across databases; reference table never existed |
| ICU/vital timing classes (PRE_ICU...) | single index time | Jinhua-specific |
| "Any recorded procedure" | `surgery_flag` = named operation | procedure rows include ventilation, lumbar puncture, acupuncture |
| Ethnicity, marital status, insurance | not harmonised | not comparable across jurisdictions |
| Microbiology, imaging, anaesthesia drugs, KDIGO AKI | domain availability only | not part of a cross-database descriptive framework in v0.1 |
