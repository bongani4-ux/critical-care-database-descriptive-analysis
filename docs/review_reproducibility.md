# How the review's comparisons were produced, and what can be reproduced

*Basis: the review manuscript (Methods: "Data charting and verification", "Synthesis"), Tables.docx, Supplemental files 3-6.
Statuses below are from `docs/generated/review_comparison.md` (regenerate with `scripts/run_all.R`).*

## 1. What the review actually did

* **Charting, not a pipeline.** Each resource was analysed by the author responsible for it (BM: INSPIRE, PIC, HiRID, Zigong, AmsterdamUMCdb;
  LG: NWICU; AS: MIMIC-IV; MY: MOVER; ZZ: VitalDB; ZJ: eICU-CRD; HZ: SICdb). Values were "verified against patient-level tables where
  accessible, otherwise against source documentation" (basis per resource in Supplemental file 4). The per-database analysis scripts
  are **not** part of the supplement, and no common harmonised code produced the cross-database table.
* **Supplemental file 6 is figure code over hard-coded values.** `dbdata.py` / the 8 CSVs contain the charted numbers; `make_figures.py`
  only draws them; the only arithmetic is totals and overall coverage (documented subdomains / 85). Copied to `review_reproduction/`,
  where `check_charted_values.py` verifies CSVs == module and the coverage arithmetic (passes).
* **Cohort size** = unique patients (first admission retained), with the native denominator (encounter / admission / case) stated alongside.
* **Granularity** = records per hour (8 vital-sign items) and records per day (7 laboratory items), following Sauer 2022 / Jagesar 2025.
  The review gives no exact extraction rule (window, denominator, which item ids).
* **Domain coverage** = a yes/no scoring of 85 subdomains from documentation, shown only as per-domain percentages.

## 2. Reproduction status by charted element

| Element (review file) | Source of the values in the review | Reproduced here? |
|---|---|---|
| Figures 1-5, S2 (`make_figures.py`) | charted values | **Yes** - regenerate from `review_reproduction/code` |
| Figure S1 / search flow (`figure_flow.py`) | screening records; counts computed | **Yes** (1,678 identified -> 1,629 screened -> 190 assessed -> 11 charted, 5 not charted, 174 excluded) |
| Overall coverage 08 | arithmetic on domain table 07 | **Yes** (checked) |
| Domain coverage 07 (85 subdomains) | documentation scoring | **Not independently** - the item-level checklist is not published; publishing it as a CSV would make this fully reproducible |
| Cohort size (01) | direct query / documentation | **19 of 22** count checks match (patients, admissions, stays); see discrepancy report for the rest (MIMIC-IV, VitalDB, ...) |
| Age median / IQR, % male (02) | direct query | median 10/12 match, IQR 17/22 match, sex 6/7 match (counts include the INSPIRE v1.3 version-check run); AmsterdamUMCdb has age groups only (not computable) |
| Mortality, LOS (03, Table 3) | direct query | 12/21 mortality and 10/19 LOS checks match; the mismatches are denominator/definition issues explained in `discrepancy_report.md` (and four unresolved: MIMIC-IV LOS, SICdb ICU mortality, HiRID ICU LOS, eICU mortality/LOS) |
| 30/90-day mortality (03) | team code (INSPIRE: from end of the first operation; Zigong: from admission) | **Yes** - INSPIRE 0.28/0.87 and Zigong 35.56/39.53 match 0.3/0.9 and 35.6/39.5; see `docs/team_code_review.md` |
| 'One-year or all-cause' mortality (03) | INSPIRE 13.3% and Zigong 48.3% are all-cause at any follow-up (team code), MIMIC-IV 5.8% a 1-year value | INSPIRE and Zigong **match** as all-cause; MIMIC-IV 2.1/3.4/5.8 **reproduce** from hospital admission over the patients-table denominator (364,627); over hospitalised first-admission patients (223,450) the rates are 3.4/5.5/9.5% (see `docs/discrepancy_report.md`) |
| Organ support (04) | direct query | **Not reproduced: 0 of 15 computable values match** (4 not computable: NWICU/Zigong ventilation, NWICU vasopressor, HiRID RRT) - e.g. Amsterdam ventilation 87% here vs 71.8% charted. The review gives no definition or denominator, so no choice of definition was tuned to match; the analysts' definitions are needed |
| Granularity (05, 06) | direct query | **Not implemented** - no extraction rule; needs the authors' definition (see section 3) |

## 3. What is needed from the review authors to make everything reproducible

1. **Organ-support definitions and denominators** (which table/items, ICU stays vs patients, whole stay vs first 24 h) for each of the 7 databases in file 04.
2. **Granularity rule**: per patient-hour or pooled; which time window (whole ICU stay? first 24 h?); how "records" are counted (raw rows, distinct timestamps, charted validated values); the item ids used for the 8 vital-sign and 7 laboratory parameters per database.
3. **The 85-subdomain checklist** with the yes/no score per database (the 17 domain percentages in file 07 are derived from it).
4. Per-database analysis scripts, if they still exist, for the values that do not reproduce (MIMIC-IV LOS/age IQR, eICU mortality, SICdb ICU mortality, HiRID ICU LOS).

Items 1-2 can be added to the pipeline as new modules once the definitions are known (the harmonised datasets already contain support events and
timestamped measurements). Until then they are reported here as **not reproduced**, never forced to agree.
