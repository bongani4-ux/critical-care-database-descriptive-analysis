# The Jinhua reference analysis - what it does, and what was found

**Status of this file:** reverse-engineered from the original scripts (`jinhua database/code/01-06_*.R`,
`README_JINHUA.md`) and their saved outputs. The original scripts were **not modified**; they remain the reference
implementation. Variable-level detail: `dictionaries/jinhua_reference_variables.csv`.

## Source and population

* 19 cleaned CSV tables from one hospital (`清洗后数据/`), keyed by `subject_id` (patient) and `hadm_id` (admission, `IP#####`).
* **20,530 admissions / 8,773 patients**, adult (median age 61, IQR 51-69; 56.9 % male), 51.9 % admitted to Neurosurgery.
* **Unit of analysis: one row per hospital admission, all admissions retained.** ICU and surgery are flags, not filters.
* There is **no ICU-stay table**. ICU episodes are reconstructed from ward transfers (`transfer.csv`): a move *into* an ICU
  department opens an episode; the next move *out of* an ICU department closes it (strictly later, so an ICU-to-ICU move cannot pair
  with itself); admissions that *start* in an ICU begin at t = 0; an open episode ends at discharge. 1,851 admissions (9.0 %) have one.

## Workflow

| Script | Purpose |
|---|---|
| `01_JINHUA_data_dictionary.R` | chunked header/fill profile of all tables (handles the 2 GB lab file) |
| `02_JINHUA_build_dataset.R` | cohort, ICU episodes, comorbidities, vitals, labs (Part G), microbiology, outcomes, KDIGO AKI |
| `03_JINHUA_summary_tables.R` | Tables 1-9 (CSV + workbook) |
| `04_JINHUA_figures.R` | ~18 publication PNGs (house palette, direct n (%) labels) |
| `05/06_*` | creatinine export and AKI/AKD analysis (a separate study, not part of this framework) |

## Methods in the reference

* **Mortality**: discharge disposition (`discharge_type_en == "Die"`), never `expire_flag` (trap 1).
* **Times**: every `*_base` column is *minutes from admission* (trap 2); `" "` is a missing-value code (trap 3).
* **Comorbidities**: 32 ICD-10 groups, regular expressions over the `;`-split codes pooled from `diagnosis.icd10_code` and the
  front-page discharge diagnosis; absent code = 0.
* **Statistics**: median (IQR), mean +- SD, n (%); denominator = all admissions unless a table states otherwise
  (ICU admissions for ICU LOS, culture-positive admissions, ...). **No hypothesis tests.**
* **Plausibility limits**: height 50-250 cm, weight 2-300 kg, BMI 8-80, temperature 30-45 C, SBP 40-300, vitals ranges in 02 Part C.
* **Thresholds**: prolonged hospital stay > 14 days, prolonged ICU stay > 3 days.
* **AKI**: KDIGO creatinine criteria; baseline = last value at/before admission, else lowest in first 24 h; 7-day window; 1 mg/dL = 88.4 umol/L.

## Traps documented by the original authors (all handled in the adapter)

1. `expire_flag` is patient-level (663 deaths vs 1,496 flagged admissions). 2. `*_base` = minutes. 3. `" "` = missing.
4. Trailing commas create empty unnamed columns. 5. `herbal_medicine` misspells `subject_id` (`subect_id`). 6. `patient_expire_hospital`
has 37 duplicate rows. 7. `surgical_record_front_page` is a *procedure* table (it also records ventilation, lumbar puncture,
acupuncture) and has a row for all 20,530 admissions. 8. `microbiology_culture` mixes blood typing with cultures.
9. `year` is a 3-year interval, not a calendar year.

## Findings made while reproducing it (new)

| # | Finding | Consequence |
|---|---|---|
| 1 | **Table 3 (laboratory) was never produced.** `02_*.R` Part G maps the lab value column with patterns (`^value$`, `quantitative_value$`, `^result`, `value$`), but the actual column is `test_results_quantitative`; the unit is `inspection_entity`. The script therefore skipped Part G, and `JINHUA_lab_header.txt` was written. | No reference laboratory table exists to reproduce. This project derives laboratory values itself (first value, first 24 h). |
| 2 | `02_*.R` contains interactive debugging calls (`View(orders)`, `View(fp)`, `View(mr)`) and reads the 775 MB `orders` table that nothing uses. | Not reproduced; the script cannot be run unattended. |
| 3 | `README_JINHUA.md` says medication and orders "currently have no coverage beyond intra-operative drugs". | Vasopressor ascertainment is **unavailable** here (medication.csv not processed in v0.1). |
| 4 | "Any recorded procedure" (74.4 %) counts non-operations (ventilation, lumbar puncture, physiotherapy). | The harmonised `surgery_flag` counts *named operations* (52.3 %) and is labelled an extension. |
| 5 | No Table 3 means the reference "labs_wide" analytes (>= 1 % of admissions) were never characterised. | Laboratory coverage in this project is a new result, not a replication. |

## Reproduction result

The harmonised pipeline reproduces **55 / 55** compared values of the original `Table1_demographics`, `Table2_comorbidities`
and `Table4_outcomes` (admissions, patients, age, sex, ICU, LOS, deaths, prolonged stays, readmissions, ventilation, RRT and all 32
comorbidity counts) exactly - `outputs/tables/jinhua_reproduction_vs_original.csv`. Tables 5-9 (vitals timing, intra-operative drugs,
microbiology, surgery, imaging) are Jinhua-specific and were **not** reproduced (see `docs/methods.md`, section 12).
