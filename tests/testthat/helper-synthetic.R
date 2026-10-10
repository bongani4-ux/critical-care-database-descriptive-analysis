# Shared test setup. SYNTHETIC DATA ONLY - randomly generated values with a fixed seed; nothing here
# comes from any real database or patient.
Sys.setenv(CCDB_TESTING = "true")
find_root <- function(d = getwd()) {
  repeat {
    if (file.exists(file.path(d, "config", "analysis_config.yml"))) return(normalizePath(d, winslash = "/"))
    p <- dirname(d); if (identical(p, d)) stop("project root not found"); d <- p
  }
}
source(file.path(find_root(), "R", "00_setup.R"))
suppressMessages(ccdb_init(quiet = TRUE))

#' Small hand-built dataset in the harmonised contract. Numbers are chosen so that expected statistics
#' can be computed by hand in the tests:
#'   8 admissions of 6 patients; 3 ICU stays in 3 admissions (one admission has 2 stays); 2 hospital deaths.
make_synthetic_ds <- function() {
  adm <- data.table::data.table(
    db_id = "synthetic", patient_id = c("P1", "P1", "P2", "P3", "P4", "P5", "P6", "P6"),
    admission_id = paste0("A", 1:8),
    age_years = c(30, 31, 45, 65, 72, 85, 17, 18), sex = c("M", "M", "F", "F", "M", NA, "F", "F"),
    hosp_los_days = c(2, 20, 5, 10, 1, 30, 4, 6), hosp_death = c(0L, 1L, 0L, 0L, 0L, 1L, 0L, 0L),
    admit_sort_key = c(1, 2, 1, 1, 1, 1, 1, 2),
    admission_urgency = c("emergency", "elective", NA, "emergency", "other", "elective", NA, "emergency"),
    admission_source = NA_character_, discharge_disposition = NA_character_, period = NA_character_)
  icu <- data.table::data.table(
    db_id = "synthetic", patient_id = c("P1", "P3", "P3"), admission_id = c("A2", "A4", "A4"),
    stay_id = c("S1", "S2", "S3"), stay_seq = c(1L, 1L, 2L), icu_los_days = c(2.5, 1, 4),
    icu_unit = NA_character_, icu_death = c(1L, 0L, 0L))
  ds <- list(
    meta = list(db_id = "synthetic", display_name = "Synthetic", version = "0", measurement_index = "first_icu_admission",
                measurement_analytes_available = c("creatinine", "hr"), support_available = "mech_vent", support_scope = "icu",
                support_definition = list(mech_vent = "synthetic"), icu_by_construction = FALSE),
    flow = flow_new(),
    admission = adm, icu_stay = icu,
    diagnosis = data.table::data.table(admission_id = c("A1", "A2", "A2", "A4"), code = c("I10", "4019", "E87.1", "J18.9"),
                                       code_system = c("ICD10", "ICD9", "ICD10", "ICD10")),
    direct_flags = data.table::data.table(admission_id = character(), comorbidity = character(), value = integer()),
    measurements = data.table::data.table(admission_id = c("A2", "A4"), stay_id = NA_character_, analyte = c("creatinine", "creatinine"),
                                          value = c(100, 80), hours_from_index = c(1, 3), n_in_window = c(2L, 1L)),
    support = data.table::data.table(admission_id = "A2", support_type = "mech_vent", value = 1L),
    severity = empty_severity(),
    availability = data.table::data.table(domain = "x", status = "available", note = ""))
  ds$admission <- finalize_admission(ds$admission, ds$icu_stay)
  ds$flow <- flow_add(ds$flow, "Final cohort", admission = ds$admission, icu_stay = ds$icu_stay)
  ds
}
