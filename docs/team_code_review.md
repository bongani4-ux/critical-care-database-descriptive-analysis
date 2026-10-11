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

Outputs go to `outputs/dictionaries/` (git-ignored: counts are results-derived aggregates, `docs/data_governance.md`).
Item-level audits for the other databases (PIC, Zigong, HiRID, eICU, MIMIC-IV, SICdb, ...) follow the same `adapter_item_audit()` pattern and are listed as open work in `docs/completion_report.md`.
