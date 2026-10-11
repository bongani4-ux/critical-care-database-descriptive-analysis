# What the review team's own scripts do (and how this repository replicates them)

*Scripts examined: `codes/INSPIRE data dictionary` (`inspre.R`, `inspire data dictionary.R`, `demographics.R`), `codes/Zigong data dictionary`,
`codes/PIC data dictionary`, `codes/HiRID data dictionary` (section structure only), `codes/VitalDB` (figure script) and the data-dictionary
workbooks for INSPIRE, PIC, Zigong, SICdb, eICU, MIMIC-IV. The scripts are the team's working code and are not copied into this repository
(they contain absolute local paths and write patient-level files); their logic is re-implemented in `R/` and `databases/`.*

## 1. The INSPIRE template (reused for PIC and Zigong; HiRID follows the same outline)

Each database was processed with the same recipe, INSPIRE first:

1. **Master** - one row per patient: the patient's **first operation** (`slice_min(OPSTART_TIME)`; PIC: first surgery / first ICU stay; Zigong: the single admission).
2. **Diagnosis** - ICD flags, restricted to codes charted up to the end of the index operation; wide 0/1 tables.
3. **Labs (wide)** - the **most recent value** per item over the whole record (`slice_max(CHART_TIME)`), not the first value in a window.
4. **Balance / Monitor** - sums or mean/min/max/SD per item and timing (PRE_OP / INTRA_OP / POST_OP; Zigong re-anchors to ICU admission).
5. **Medications** - wide count per drug and per ATC code.
6. **Outcomes** - in-hospital death, all-cause death, `DEATH_30D`, `DEATH_90D`, LOS, ICU admission, AKI/AKD.
7. **Data dictionary** - an Overview sheet plus one sheet per table listing every variable with type, description, missing n, valid n,
   completeness and unit, then the raw `schema` sheet. The "fill-rate auditor" is the same helper in every script.

**Consequences for comparisons** (documented, not hidden): labs in the team dictionaries are "most recent value", the harmonised analysis uses the
first valid value in the first 24 h; several figures in `demographics.R` carry typed-in annotations (e.g. "ASA IV-VI 492 (0.5%)", "median 6 d, IQR 3-9",
surgery-duration bin counts) rather than computed ones; the INSPIRE workbook mixes versions - lab counts equal v1.4.2, medication/ATC counts equal v1.3
(verified here, section 3).

## 2. Mortality horizons - the team's definitions (now implemented)

| Database | Team code | Here |
|---|---|---|
| INSPIRE | `DEATH_30D/90D = (ALLCAUSE_DEATH_TIME - OPEND_TIME)/1440 <= 30/90`, first operation, deaths before the index counted | index `surgery_end`; **0.28% / 0.87% = review 0.3% / 0.9%**; all-cause 13.32% = 13.3% |
| Zigong | `Death_Date/24 <= 30/90` from hospital admission; all-cause = dated death OR in-hospital death OR follow-up "Death" | **35.56% / 39.53% = 35.6% / 39.5%**; composite 48.32% = 48.3% |
| MIMIC-IV | no team script found; review basis "direct query / documentation" | from `deathtime`/`dod` (a date, +/- 1 day) and hospital admission: **2.106 / 3.372 / 5.807% = review 2.1 / 3.4 / 5.8%** when the denominator is the patients TABLE (364,627 rows, as for the review's in-hospital 3.2%). Over first admissions that have an admission row (223,450 patients) the same deaths give **3.44 / 5.50 / 9.48%** (in-hospital 2.16%) |
| PIC, SICdb, AmsterdamUMCdb, NWICU | not charted in the review | computed and reported (not compared) |
| eICU, HiRID, MOVER, VitalDB | no dated post-discharge deaths | unavailable |

Two charted cells are mislabelled in the review's CSV column "year1_or_allcause": INSPIRE 13.3% and Zigong 48.3% are **all-cause at any follow-up**, not
365-day landmarks (INSPIRE 365-day from surgery end = 3.0%; Zigong 365-day from admission = 43.3%). Only MIMIC-IV's 5.8% is presented as a 1-year value.

## 3. Data dictionaries (`scripts/build_data_dictionaries.R`)

Same workbook layout for every database (Overview + one sheet per analysis-ready table, columns *Variable Name, Variable Type, Variable Description,
Missing Values (n), Valid (n), Completeness (%), Notes, Unit*) built from the harmonised dataset, plus an **item-level audit** of the raw long tables where
an adapter defines one (INSPIRE: labs, monitoring items, drugs, ATC classes, ICD-10 codes). Replication check against the team's INSPIRE workbook:

| Sheet | Compared | Identical valid-n |
|---|---|---|
| Labs (v1.4.2) | 32 items (6 more are the team's renamed typos, e.g. `lacate`) | 32 of 32 |
| Medications - drug (v1.3) | 1,140 matched names (2 more differ only in spelling) | 1,139 (METFORMIN differs: 3,638 vs 3,507) |
| Medications - ATC (v1.3) | 989 codes | 989 of 989 |

### Item-level audits for every reviewed database (`dictionaries/item_audit_specs.csv`)

One declarative spec row per raw table (path, patient key, item column, value column, label dictionary, denominator) drives a single engine
(`run_item_audit()` in `R/15_data_dictionary.R`; arrow-streamed, bounded memory, per-sheet cache under `derived/`). "Valid (n)" = units with >= 1 numeric
result (text-only results do not count, as in the team's `as.numeric()` wide tables).

| Database | Audited tables | Items listed |
|---|---|---|
| MIMIC-IV | labevents, chartevents, inputs, outputs, procedures, prescriptions, ICD codes | 43,252 |
| NWICU | labs, chartevents, procedures, prescriptions, ICD codes | 12,397 |
| eICU-CRD | lab, vital (periodic, aperiodic), nurse and respiratory charting, intake/output, medication, infusion, admission drugs, diagnoses, treatments | 19,332 |
| SICdb | signals, labs, medications, intervals, reference fields | 1,252 |
| AmsterdamUMCdb | numericitems (monitor / lab), list, drug, process, procedure-order items | 4,077 |
| HiRID | observation variables, pharma records | 681 |
| PIC | labs, chartevents, surgery vitals, outputs, prescriptions, ICD, symptoms | 2,976 |
| Zigong | labs, nursing chart, drugs, ICD codes | 4,439 |
| INSPIRE | labs, monitoring, drugs, ATC, ICD codes | ~2,900 |
| VitalDB | lab_data, clinical_data | 106 |
| MOVER-EPIC / MOVER-SIS | labs, diagnoses, complications / observations, vitals, ventilator, labs, drugs, events, I/O | 4,873 / 295 |

Replication check against the team's workbooks (items in both): PIC medications **638 of 638 identical**; PIC labs 508 of 557 identical (the 49 differences are lab
names that map to several ITEMIDs - the team groups by name, the audit by item id); Zigong labs 100 of 101 identical; INSPIRE as above.
VitalDB's waveform/track inventory (which of the 6,388 `.vital` files hold which track) is not part of this audit; `track_names.csv` is the dictionary.

Outputs go to `outputs/dictionaries/` (git-ignored: counts are results-derived aggregates, `docs/data_governance.md`).
Rebuild with `Rscript scripts/build_data_dictionaries.R <db_id>` (set `CCDB_REFRESH_AUDIT=1` to ignore the per-sheet cache).
