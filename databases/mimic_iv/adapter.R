# =============================================================================
# MIMIC-IV v3.1 adapter (hosp + icu modules)
# Unit of analysis: hospital admission (hadm_id); ICU stays (stay_id) nested within.
# All hospital admissions are retained; ICU admission is a flag (icu_flag).
# =============================================================================

adapter_meta <- list(
  db_id = "mimic_iv",
  required_files = c("hosp/patients.csv", "hosp/admissions.csv", "hosp/diagnoses_icd.csv", "hosp/labevents.csv",
                     "hosp/d_labitems.csv", "icu/icustays.csv", "icu/chartevents.csv", "icu/procedureevents.csv",
                     "icu/inputevents.csv", "icu/d_items.csv"))

source(ccdb_path("databases", "_shared", "mimic_schema.R"), local = TRUE)

adapter_build <- function(cfg) {
  mimic_urgency <- function(x) data.table::fcase(
    x %in% c("EW EMER.", "URGENT", "DIRECT EMER."), "emergency",
    x %in% c("ELECTIVE", "SURGICAL SAME DAY ADMISSION"), "elective",
    !is.na(x) & nzchar(x), "other", default = NA_character_)
  mimic_disposition <- function(x) data.table::fcase(
    x %in% c("HOME", "HOME HEALTH CARE"), "home",
    x == "DIED", "death",
    x %in% c("SKILLED NURSING FACILITY", "REHAB", "CHRONIC/LONG TERM ACUTE CARE", "HOSPICE", "ACUTE HOSPITAL",
             "PSYCH FACILITY", "OTHER FACILITY", "ASSISTED LIVING", "HEALTHCARE FACILITY"), "facility",
    x == "AGAINST ADVICE", "other", default = NA_character_)
  opts <- list(
    hosp_sub = "hosp", icu_sub = "icu",
    chart_map = read_mapping("mimic_iv", "mapping_chartevents.csv"),
    lab_map = read_mapping("mimic_iv", "mapping_labevents.csv"),
    urgency_fun = mimic_urgency, disposition_fun = mimic_disposition,
    hosp_death_fun = function(a) as.integer(a$hospital_expire_flag),
    hosp_death_definition = "admissions.hospital_expire_flag == 1",
    vent_label = "^Invasive Ventilation$",
    rrt_label  = "^(Dialysis - (CRRT|CVVHD|CVVHDF|SCUF)|Hemodialysis|Peritoneal Dialysis)$",
    vaso_label = "^(Norepinephrine|Epinephrine|Vasopressin|Phenylephrine|Dopamine|Dobutamine|Milrinone)$",
    vaso_source = "inputevents",
    notes = list(
      support_definition = list(
        mech_vent = "procedureevents 'Invasive Ventilation' during an ICU stay",
        rrt = "procedureevents CRRT/CVVHD/CVVHDF/SCUF/hemodialysis/peritoneal dialysis during an ICU stay",
        vasopressor = "inputevents record of norepinephrine, epinephrine, vasopressin, phenylephrine, dopamine, dobutamine or milrinone during an ICU stay"),
      comorbidity_note = "ICD-9 and ICD-10 codes from diagnoses_icd (both versions; version flag respected)"),
    availability = data.table::data.table(
      domain = c("Demographics", "Hospital mortality", "ICU stay structure", "ICU mortality", "Comorbidities (coded)",
                 "Vital signs", "Laboratory", "Organ support", "Severity scores", "Microbiology", "Medication", "Surgery/anaesthesia"),
      status = c("available", "available", "available", "partial", "available", "available", "available", "available",
                 "unavailable", "available", "available", "unavailable"),
      note = c("anchor age/year de-identification (age >89 censored)", "hospital_expire_flag", "icustays",
               "derived from deathtime within ICU stay window", "ICD-9 + ICD-10", "chartevents (ICU only)",
               "labevents (hospital-wide)", "procedureevents / inputevents (ICU)",
               "no native score in v3.1 hosp/icu modules; derived concepts not implemented in v0.1",
               "microbiologyevents; not harmonised in v0.1", "emar/prescriptions/inputevents; not harmonised in v0.1",
               "no anaesthesia data")))
  build_mimic_like("mimic_iv", opts, cfg)
}
