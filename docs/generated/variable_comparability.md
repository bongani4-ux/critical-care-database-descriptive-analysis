# Variable comparability matrix

D = directly comparable; A = comparable after harmonization (documented transformation); P = partially comparable (important limitation); — = unavailable. Source field and note for every cell: `dictionaries/database_variable_mappings.csv`.

| variable | jinhua | mimic_iv | eicu_crd | nwicu | sicdb | amsterdamumcdb | hirid | pic | zigong | inspire | vitaldb | mover_epic | mover_sis |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| patient_id | D | D | D | D | D | D | D | D | D | D | D | D | P |
| admission_id | D | D | D | D | D | D | D | D | D | D | P | P | P |
| age_years | D | A | A | A | P | — | P | A | D | D | D | D | D |
| sex | D | D | D | D | D | D | D | D | D | D | D | D | D |
| admission_urgency | P | A | — | A | — | A | — | — | — | P | P | — | — |
| hosp_los_days | A | D | D | D | — | — | — | D | A | D | D | D | — |
| hosp_death | D | D | D | A | D | — | — | D | D | A | D | D | — |
| icu_flag_and_stay | P | D | A | D | D | A | D | D | P | P | P | P | — |
| icu_los_days | P | D | A | D | D | A | A | D | P | P | P | — | — |
| icu_death | — | A | D | A | D | D | D | A | — | — | — | — | — |
| death_any_followup | — | P | — | P | P | P | — | — | P | P | — | — | — |
| discharge_disposition | A | A | A | A | — | — | — | — | — | — | — | A | — |
| comorbidities_coded | D | A | P | A | P | — | — | A | A | A | P | P | — |
| vital_signs_first24h | P | D | D | P | P | — | D | P | D | P | — | — | P |
| laboratory_first24h | A | D | D | D | D | — | D | D | D | D | D | D | P |
| mech_vent | P | D | A | — | P | D | P | — | — | P | — | — | — |
| rrt | P | D | A | P | P | D | — | — | — | P | — | — | — |
| vasopressor | — | D | A | — | D | D | D | — | D | P | — | — | — |
| intubation | P | — | — | — | P | P | — | — | P | — | — | — | — |
| tracheostomy | P | — | — | — | P | P | — | — | P | — | — | — | — |
| severity_score | — | — | D | — | D | — | — | — | — | P | P | P | — |
| surgery_flag | P | — | — | — | — | — | — | — | — | D | D | D | D |

