# =============================================================================
# NWICU v0.1.0 adapter. MIMIC-IV-compatible table layout (nw_hosp / nw_icu) but
# with its OWN item ids (verified against nw_icu/d_items and nw_hosp/d_labitems at
# build time) and a much smaller ICU dictionary: no ventilation or vasopressor
# items, no mean arterial pressure, Fahrenheit temperature only.
# Unit of analysis: hospital admission (hadm_id); ICU stays nested within.
# =============================================================================

adapter_meta <- list(
  db_id = "nwicu",
  required_files = c("data/nw_hosp/patients.csv", "data/nw_hosp/admissions.csv", "data/nw_hosp/diagnoses_icd.csv",
                     "data/nw_hosp/labevents.csv", "data/nw_hosp/d_labitems.csv", "data/nw_icu/icustays.csv",
                     "data/nw_icu/chartevents.csv", "data/nw_icu/procedureevents.csv", "data/nw_icu/d_items.csv"))

source(ccdb_path("databases", "_shared", "mimic_schema.R"), local = TRUE)

adapter_build <- function(cfg) {
  nw_urgency <- function(x) data.table::fcase(
    x %in% c("EMERGENCY", "URGENT", "TRAUMA"), "emergency",
    x %in% c("ELECTIVE", "ELECTIVE-ROUTINE"), "elective",
    !is.na(x) & nzchar(x), "other", default = NA_character_)
  nw_disposition <- function(x) data.table::fcase(
    is.na(x) | !nzchar(x) | x == "UNKNOWN", NA_character_,
    grepl("^EXPIRED", x), "death",
    grepl("^HOME", x), "home",
    grepl("AGAINST MEDICAL ADVICE|LEFT AGAINST", x), "other",
    grepl("^ED DISMISSED|ADMITTED TO L&D|GIFT OF HOPE", x), "other",
    default = "facility")
  opts <- list(
    hosp_sub = "data/nw_hosp", icu_sub = "data/nw_icu",
    chart_map = read_mapping("nwicu", "mapping_chartevents.csv"),
    lab_map = read_mapping("nwicu", "mapping_labevents.csv"),
    urgency_fun = nw_urgency, disposition_fun = nw_disposition,
    # NWICU's hospital_expire_flag marks only 105 of ~3,560 deaths. In-hospital death is therefore
    # defined as: discharged 'EXPIRED' / 'EXPIRED - HOSPICE', OR a death time inside the admission.
    # (Matches the counts reported in the Critical Care Database Review: 3,558 admissions,
    # 3,401 ICU stays, 3,554 patients.)
    hosp_death_fun = function(a) {
      exp_loc <- grepl("^EXPIRED", a$discharge_location)
      dth_in  <- !is.na(a$death_t) & a$death_t >= a$admit_t & a$death_t <= a$disch_t
      as.integer(exp_loc | dth_in)
    },
    hosp_death_definition = "discharge_location starts 'EXPIRED' OR deathtime within [admittime, dischtime]; hospital_expire_flag (105 admissions) is NOT used because it is incomplete",
    vent_label = NA_character_,
    rrt_label  = "^HEMODIALYSIS$",
    vaso_label = NA_character_, vaso_source = NA_character_,
    notes = list(
      support_definition = list(
        rrt = "ICU procedureevents ORDER 'HEMODIALYSIS' (an order, not a delivery record)"),
      support_unavailable_note = "no ventilation / vasopressor items in the NWICU ICU dictionary (344 items)",
      comorbidity_note = "ICD-9/ICD-10 diagnoses_icd"),
    availability = data.table::data.table(
      domain = c("Demographics", "Hospital mortality", "ICU stay structure", "ICU mortality", "Comorbidities (coded)",
                 "Vital signs", "Laboratory", "Organ support", "Severity scores", "Microbiology", "Medication", "Surgery/anaesthesia"),
      status = c("available", "available", "available", "partial", "available", "partial", "available", "partial",
                 "unavailable", "unavailable", "partial", "unavailable"),
      note = c("anchor age/year de-identification (age >89 censored)", "hospital_expire_flag", "icustays",
               "derived from deathtime within ICU stay window", "ICD-9/ICD-10",
               "8 chartevents items; no MAP; temperature in F", "labevents", "dialysis order only; no ventilation/vasopressor items",
               "none", "no microbiology table", "emar + prescriptions; not harmonised in v0.1", "none")))
  build_mimic_like("nwicu", opts, cfg)
}
