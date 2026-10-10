# Discrepancy report

Reproduced values were compared with (i) the original Jinhua tables and (ii) the figures reported in the authors' *Critical Care Database Review*
(`config/review_reference_values.csv`; `outputs/tables/*_review_comparison.csv`). **Nothing was adjusted to force agreement.** Each mismatch below was
investigated by recomputing the review's number under alternative units of analysis or fields, using the raw data; where an explanation reproduces the
review's value exactly, the evidence is stated. *This file contains aggregate figures derived from restricted databases - confirm release terms
(`docs/data_governance.md`) before making the repository public.*

Match rule: equal at the review's own printed precision (exact for counts).

## 1. Jinhua reproduction - 55 / 55 match

Admissions, patients, age, sex, ICU admission, hospital/ICU LOS, in-hospital death, prolonged stays, ICU readmission, patients with >1 admission,
mechanical ventilation, RRT and all 32 comorbidity counts reproduce the original `Table1/2/4` exactly. Not reproducible: the reference **Table 3
(laboratory) never existed** (the lab-column mapping failed) - details in `docs/jinhua_reference_analysis.md`.

## 2. Review values that match only at a different unit of analysis, field or version

| Database | Review reports | What the data show | Explained? |
|---|---|---|---|
| **MIMIC-IV v3.1** | N = 364,627 "patients" | 364,627 = rows of `hosp/patients.csv` (every patient, including those never hospitalised). Patients with a hospital admission: **223,452** (546,028 admissions; 94,458 ICU stays) | yes (exact) |
| | median age 48 | = median `anchor_age` over **all** rows of `patients.csv` (48). Admitted patients (first admission): 58; ICU patients: 65 | yes (exact) |
| | in-hospital mortality 3.2 % | = 11,801 in-hospital deaths (an *admission* count) / 364,627 (a *patient-table* count): 3.24 %. Admission-level mortality is **2.16 %** (11,801/546,028) | yes (exact) - mismatched numerator and denominator |
| | hospital LOS 2.0 d, ICU LOS 3.0 d | reproduced medians: hospital 2.8 d (admissions), ICU 1.97 d (per stay); the review labels MIMIC-IV "not independently queried" (S3) | **no** - source of 2.0 / 3.0 not identified |
| **NWICU v0.1.0** | 13.7 % "patient-level" (3,554/25,923) | = patients with >= 1 in-hospital death over **any** admission (`patient_any`); first-admission mortality is 6.7 % | yes (exact: 3,554) |
| | 11.9 % / 7.9 % (ICU stays), 5.8 % (admissions) | reproduced: 11.89 % / 7.95 % / 5.75 % using death = discharge `EXPIRED*` **or** death time inside the admission. `hospital_expire_flag` marks only 105 admissions and would give 0.2-0.4 % | yes (exact: 3,558 / 3,401 / 3,554) |
| **SICdb v1.0.8** | "ICU mortality 3.8 %", "last-follow-up mortality 7.8 %", in-hospital "not separately reported" | **7.8 % = `HospitalDischargeType` Deceased (2,134/27,386) = in-hospital mortality**, not follow-up. True follow-up death (`OffsetOfDeath` recorded, 6-month/1-year observation): 18.6 % | 7.8 %: yes (exact). ICU mortality 3.8 %: **no** - by `DischargeState` 3.43 %; 3.73 % among known state; 3.75 % among first cases |
| **AmsterdamUMCdb v1.0.2** | hospital LOS 25.0 **days** (IQR 20-73), patient level | = median of `admissions.lengthofstay` over first admissions of all patients **in hours** (25; IQR 20-73): ICU/medium-care stay, not hospital stay and not days. No hospital LOS or hospital outcome exists in the database ("NR" is right) | yes (exact) |
| **PIC v1.1.0** | mortality 7.2 %, hospital LOS 12.3 d, ICU LOS 2.8 d described as patient-level (first admission) | reproduced exactly at **admission level** (971/13,449 = 7.2 %; median 12.3 d) and ICU-stay level (2.80 d). First-admission values: 7.4 %, 12.2 d | yes |
| **INSPIRE** | version v1.4.2 (S3) / v1.3 (Table 1) | the review's ICU LOS 1.04 d reproduces on **v1.3** (1.038) and **not on v1.4.2** (1.004); patients (99,886), all-cause deaths (13,304), female 56.7 % and hospital LOS 6.0 d are identical in both | yes - **the charted values come from v1.3; S3 names a version that was not charted. Authors must reconcile** |
| | in-hospital mortality 0.9 % (923/99,886) | 923 = patients whose **first operation row** has a non-missing `inhosp_death_time`. That field is copied to every operation of a patient who ever died in hospital (942 patients), so the figure counts deaths in *any* admission. Index-admission in-hospital death: 630 admissions (0.50 %), 477 among first admissions (0.48 %) | yes (exact: 923) |
| **VitalDB v1.0.0** | N = 6,388 "unique patients" | 6,388 = surgical **cases**; unique `subjectid` = **6,090** | yes (exact) |
| | male 51 % | 50.8 % of cases (rounds to 51); 50.4 % of patients' first case | yes (case level) |
| **MOVER-EPIC v1.0** | N = 65,728 "patients", mortality 1.5 %, LOS 2.0 d | 65,728 = rows of `patient_information` (**surgical records**; 64,354 distinct `LOG_ID`; **39,685 patients** by `MRN`; 52,389 admissions). 1.5 % (1,012 Expired / 65,728) and median LOS 2.0 d are *record-level*; admission-level mortality is 0.8 %, patient-level (first admission) 0.9 % | yes (exact) |
| **MOVER-SIS v1.0** | N = 19,114 | = distinct `PID`; the release has no separate patient identifier, so these are records | consistent, but "patients" is unverifiable |
| **HiRID v1.1.1** | ICU LOS 0.94 d | HiRID stores no ICU LOS; derived as last observation - admission time = **0.99 d** (0.99997 if measured from first observation). N, median age, sex, ICU mortality (2,062/33,666 known status) all reproduce | **no** - derivation of 0.94 unknown |

## 3. Internal inconsistencies in the review that affect this project

* **INSPIRE version** (above) and **MOVER host / access** (S3: UCI portal + DUA; Tables 1-2: PhysioNet credentialed).
* Tables report "N (unique patients)" for databases where the value is a record, case or table-row count (MIMIC-IV, VitalDB, MOVER-EPIC).
* Table 3 mixes denominators within and across rows (MIMIC-IV mortality; NWICU patient-level; SICdb hospital mortality in the follow-up column).
* AmsterdamUMCdb LOS unit (hours labelled days).

These do not invalidate the review's qualitative conclusions, but the numbers above should be corrected or their units/denominators stated before publication.

## 4. Unresolved

| Item | State |
|---|---|
| MIMIC-IV hospital LOS 2.0 d and ICU LOS 3.0 d | not reproduced under any tested unit (median or mean) |
| SICdb ICU mortality 3.8 % | closest 3.73-3.75 %; review definition unknown |
| HiRID ICU LOS 0.94 d | derived 0.99 d |
| eICU-CRD hospital / ICU mortality (3.9 % / 2.3 %) and hospital LOS (6.5 d) | not reproduced - see section 5 |

## 5. eICU-CRD

| Item | Review | Reproduced | Notes |
|---|---|---|---|
| N patients / unit stays, median age, % male | 139,367 / 200,859 / 65 / 54.0 % | identical | exact |
| ICU LOS | 1.66 d | 1.65 d (median `unitdischargeoffset`/1440 of each patient's first unit stay); 1.82 d for the summed first hospital stay | nearly: first unit stay, not summed |
| Hospital mortality | 3.9 % | **9.2 %** (first unit stay per patient; 8.96 % of all unit stays; 10.5 % of patients ever Expired) | **not reproduced** |
| ICU mortality | 2.3 % | **5.8 %** (first unit stay; 5.4 % of all unit stays) | **not reproduced** |
| Hospital LOS | 6.5 d | 5.0 d (hospital discharge - admit offset); 4.5 d from the unit-admission offset only; APACHE `actualhospitallos` 5.1 d | **not reproduced** |

The eICU-CRD hospital mortality of roughly 9-10 % is the commonly observed figure for this database, so the review's 3.9 % / 2.3 % are very probably wrong
or defined on a subset that the review does not describe; they cannot be reproduced under any tested definition (`patient`, `apachePatientResult`, first / last / all stays).

## 6. Full machine-generated comparison

`docs/generated/review_comparison.md` (local; regenerate with `scripts/build_docs_tables.R`).
