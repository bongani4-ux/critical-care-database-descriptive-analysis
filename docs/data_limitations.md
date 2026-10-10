# Limitations and sources of non-comparability

These apply to **every** cross-database comparison produced by this project. Differences in the tables are a mixture of
(i) genuinely different patient populations and (ii) differences created by how each database was built, coded and measured.
The framework separates the two where the data allow, by (a) reporting the unit of analysis, (b) keeping mortality definitions apart,
(c) classing each variable's comparability (`dictionaries/database_variable_mappings.csv`, `docs/generated/variable_comparability.md`),
and (d) marking what is unavailable instead of zero.

## 1. Populations and care settings

| Group | Databases | Consequence |
|---|---|---|
| Hospital-wide with ICU as a subset | MIMIC-IV, NWICU, Jinhua, AmsterdamUMCdb (IC + medium care) | admission-level rates (mortality, LOS) mix ICU and non-ICU stays; ICU-specific rates need the ICU-stay level |
| ICU-only | eICU-CRD (incl. step-down unit stays), SICdb, HiRID, PIC, Zigong | no non-ICU comparison group |
| Perioperative | INSPIRE, VitalDB, MOVER-EPIC, MOVER-SIS | low-risk elective surgical cohorts; "ICU" is a post-operative flag; first-24-h values are mostly pre/intra-operative |
| Special populations | PIC (paediatric; adult age bands uninformative), Zigong (infection only), NWICU (COVID-rich), Jinhua (51.9 % neurosurgery) | case mix, not database structure, drives many differences |

## 2. Units of analysis (the largest single source of discordance)

The review's Table 1/3 figures were produced at different units in different databases; the unit that reproduces each reported value is
documented in `docs/discrepancy_report.md`. Within this project the three levels (admission / first admission per patient / ICU stay) are explicit.
VitalDB and MOVER-EPIC/SIS cannot identify admissions or patients cleanly (case / surgical record).

## 3. Outcomes

| Database | In-hospital death | ICU death | Hospital LOS | Follow-up death |
|---|---|---|---|---|
| Jinhua, MIMIC-IV, NWICU, PIC, Zigong, eICU-CRD, INSPIRE, VitalDB, MOVER-EPIC | yes (rule differs; see methods section 5) | partly (derived) | yes | partial |
| SICdb | yes | yes | **no** | yes (6-12 months) |
| HiRID | **no** (ICU status only) | yes | **no** | no |
| AmsterdamUMCdb | **no** | yes | **no** (ICU/MC hours) | yes (registry, years) |
| MOVER-SIS | no | no | no | no |

* Follow-up mortality windows differ (MIMIC `dod`: limited post-discharge window; SICdb 6 months or 1 year; INSPIRE variable; AmsterdamUMCdb up to ~14 years; Zigong variable).
  It is **not** a fixed-landmark mortality and must not be compared across databases.
* ICU LOS: summed ICU stays per admission and per stay are both reported; step-down unit stays in eICU, medium-care in AmsterdamUMCdb, and reconstructed
  stays (Jinhua, Zigong, INSPIRE) are not equivalent to MIMIC-style ICU stays.

## 4. Coding systems and comorbidity ascertainment

* ICD-9-CM (MIMIC-IV, NWICU, eICU, MOVER-EPIC), ICD-10 variants (Chinese extension in Jinhua/PIC/Zigong, ICD-10-CM in INSPIRE/MOVER-EPIC/eICU, ICD-10-GM in SICdb) and none (HiRID, AmsterdamUMCdb, MOVER-SIS).
* ICD-9-CM equivalents of the Jinhua ICD-10 groups are **analyst-defined, approximate**, not a published crosswalk. Prevalences across ICD-9 and ICD-10 databases
  are therefore "comparable after harmonization" at best.
* Ascertainment is not equal: SICdb has one principal diagnosis per case (prevalences reflect admission diagnosis, except two direct flags); MOVER-EPIC codes are linked at patient level
  (no encounter key); eICU codes exist for a subset of diagnosis rows; VitalDB has two flags; Jinhua pools discharge diagnoses. The proportion with any coded diagnosis is reported beside every prevalence.
* "Absent code = not present" (Jinhua convention) under-estimates prevalence wherever coding is incomplete.

## 5. Measurement

* Harmonised variable = first valid value in the first 24 h after an **index time that is not the same event everywhere** (first ICU admission, hospital admission, OR start).
  Coverage and medians therefore reflect both physiology and charting practice (a database that measures lactate only in sicker patients will show higher lactate and lower coverage).
* Pooled sources: invasive + non-invasive blood pressure; chemistry + blood-gas sodium/potassium/glucose/haemoglobin/bicarbonate; arterial + venous lactate; temperature sites.
  PIC and Zigong do not record the blood-pressure method.
* SICdb monitor values are **hourly aggregates**, not instantaneous values. HiRID age is in 5-year bins; SICdb as well.
* Units were converted from each database's recorded units; MOVER-SIS laboratory columns carry no units (canonical units assumed from physiology and flagged); Jinhua SpO2 has no unit (assumed %).
  Values outside plausible ranges (`dictionaries/analyte_definitions.csv`) are set to missing and counted - ranges are generic, not database-tuned.
* Known extraction gaps that depress coverage (not properties of the databases): eICU body temperature (9 %) is mostly charted in `nurseCharting`, which is not used;
  HiRID glucose (8 %) and albumin (5 %) use only the mapped variable ids; PIC heart rate/blood pressure coverage reflects the six charted items only;
  INSPIRE and VitalDB first-24-h-of-admission coverage is low because most laboratory values are pre-/post-operative.
* Data anomalies reported, not corrected: negative hospital LOS in 175 MIMIC-IV admissions, 13 eICU hospital stays and 2 PIC admissions; negative ICU LOS in a few eICU, PIC and INSPIRE v1.3 stays (QC WARN).
* Not implemented in v0.1: vital-sign waveforms (VitalDB `.vital`), eICU nurse charting / past-history text, severity-score derivation (SOFA, APACHE, SAPS) where no native score exists,
  microbiology/medication/imaging harmonisation, and any inferential statistics or adjustment.

## 6. Time and calendar coverage (verified in the data where possible)

| Database | Calendar information available |
|---|---|
| MIMIC-IV | anchor-year groups 2008-2022 (dates shifted) |
| NWICU | anchor-year groups 2017-2019 and 2020-2022 |
| SICdb | admission years 2013-2021 |
| AmsterdamUMCdb | admission-year groups 2003-2009, 2010-2016 |
| MOVER-EPIC / SIS | wall-clock dates parsed (EPIC 2017-2023; SIS 2012-2021 including sparse years) |
| Jinhua | 3-year intervals 2013-2015 ... 2020-2022 |
| eICU-CRD | discharge year only (hospitaldischargeyear) |
| HiRID, PIC, Zigong, INSPIRE, VitalDB | dates de-identified or relative: calendar period not derivable from the files |

Practice patterns, coding rules (ICD-9 to ICD-10 transition) and the COVID-19 period differ across these windows.

## 7. Missingness

Missingness is reported per variable with its denominator (`*_missing_data.csv`, `*_descriptive_results.csv`). No imputation is performed; "first value in window" is not defined
for units with no measurement. Several domains are *structurally* unavailable (see the comparability matrix) - that is a property of the database, not missing data.

## 8. Access and completeness of the local copies

* **AmsterdamUMCdb**: `numericitems.csv` is missing from the local folder, so vitals, laboratory values and APACHE scores are **blocked** for this database (not absent from the database itself).
* **VitalDB**: waveform tracks (100 GB) are not parsed; vital signs are unavailable.
* **MOVER**: tables are unpacked from archives outside the repository; EPIC procedure/medication/post-operative-complication tables are not used.
* **Jinhua**: the data-use terms are unknown (not in the files); no Jinhua-derived aggregate should be published until the data owner confirms.
* The review itself contains **internal inconsistencies** (INSPIRE version; MOVER host; several Table 1/3 denominators) listed in `docs/discrepancy_report.md`.
