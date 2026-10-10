# =============================================================================
# MOVER-SIS v1.0 adapter (perioperative; UCI Health surgical information system; 19,114 records).
# Source: sis_emr.tar.gz unpacked into the cache folder outside the repository.
#
# SIS is an INTRA-OPERATIVE anaesthesia record: there is NO hospital admission/discharge time, NO
# outcome (death, LOS), NO ICU information and NO diagnosis table. 'Admission' = one PID (one surgical
# record; the release gives no separate patient identifier, so patients cannot be told from records).
# Index time = OR start (the earliest anchor available); measurement window = first 24 h from OR start
# (intra-operative values dominate). Laboratory columns carry no units: the canonical units are ASSUMED
# from physiology (Na/K/HCO3 mmol/L, glucose mg/dL, Hb g/dL) and the assumption is recorded.
# =============================================================================

adapter_meta <- list(
  db_id = "mover_sis",
  required_files = c("sis_emr.tar(2).gz"))

adapter_build <- function(cfg) {
  flow <- flow_new()
  dest <- ccdb_cache_dir("mover_sis")
  untar_cached(db_file("mover_sis", "sis_emr.tar(2).gz"), dest, marker = file.path("EMR", "patient_vitals.csv"))
  emr <- file.path(dest, "EMR")
  na_codes <- c("\\N", "")
  q <- data.table::fread(file.path(emr, "patient_information.csv"), colClasses = "character", showProgress = FALSE,
                         encoding = "UTF-8", na.strings = na_codes)
  assert_unique(q, "PID", "MOVER-SIS patient_information")
  q[, or_start := as.POSIXct(OR_start, tz = "UTC", format = "%m/%d/%y %H:%M")]
  adm <- q[, .(db_id = "mover_sis", patient_id = PID, admission_id = PID, age_years = suppressWarnings(as.numeric(Age)),
               sex = harmonize_sex(Gender), hosp_los_days = NA_real_, hosp_death = NA_integer_,
               admit_sort_key = as.numeric(or_start), admission_urgency = NA_character_, admission_source = NA_character_,
               discharge_disposition = NA_character_, period = format(or_start, "%Y"), surgery_flag = 1L)]
  flow <- flow_add(flow, "Surgical records (PID)", admission = adm, note = "no separate patient identifier: record = patient")
  index <- q[, .(unit_key = PID, index_hours = as.numeric(or_start) / 3600)]

  win <- cfg$measurements$window_hours; pre <- cfg$measurements$pre_index_hours
  num <- function(x) suppressWarnings(as.numeric(x))
  lmap <- data.table::data.table(item = c("Na", "K", "Gluc", "HCO3", "HgB"), analyte = c("sodium", "potassium", "glucose", "bicarbonate", "hemoglobin"),
                                 source_unit = c("mmol/L", "mmol/L", "mg/dL", "mmol/L", "g/dL"))
  vmap <- data.table::data.table(item = c("HRe", "HRp", "nSBP", "nMAP", "nDBP", "SP02"), analyte = c("hr", "hr", "sbp", "map", "dbp", "spo2"),
                                 source_unit = c("/min", "/min", "mmHg", "mmHg", "mmHg", "%"))
  wide_to_long <- function(ch, map) {
    long <- data.table::melt(ch, id.vars = c("PID", "Obs_time"), measure.vars = map$item, variable.name = "item", value.name = "raw",
                             variable.factor = FALSE)
    long[, value := num(raw)]
    long <- long[!is.na(value)]
    long[, .(unit_key = PID, item, time_hours = fast_ts_hours(Obs_time), value, unit = NA_character_)]
  }
  lb <- stream_file(file.path(emr, "patient_labs.csv"), function(ch) {
    reduce_chunk_first_in_window(wide_to_long(ch, lmap), lmap, index, win, pre)
  }, col_types = do.call(readr::cols_only, c(list(PID = "c", Obs_time = "c"), stats::setNames(rep(list("c"), nrow(lmap)), lmap$item))),
  label = "MOVER-SIS patient_labs")
  vt <- stream_file(file.path(emr, "patient_vitals.csv"), function(ch) {
    reduce_chunk_first_in_window(wide_to_long(ch, vmap), vmap, index, win, pre)
  }, col_types = do.call(readr::cols_only, c(list(PID = "c", Obs_time = "c"), stats::setNames(rep(list("c"), nrow(vmap)), vmap$item))),
  label = "MOVER-SIS patient_vitals")
  meas <- combine_first_in_window(data.table::rbindlist(list(lb, vt), use.names = TRUE, fill = TRUE))
  measurements <- meas[, .(admission_id = unit_key, stay_id = NA_character_, analyte, value, hours_from_index, n_in_window)]

  flow <- flow_add(flow, "Final cohort", admission = adm, icu_stay = empty_icu_stay())
  ds <- list(
    meta = list(
      index_definition = "operating-room start (OR_start); no admission time exists", measurement_index = "hospital_admission",
      measurement_analytes_available = unique(measurements$analyte), support_available = character(), support_scope = "hospital",
      support_unavailable_note = "intra-operative anaesthesia record only; no organ-support data comparable to ICU care",
      hosp_death_definition = "NOT RECORDED", hosp_los_definition = "NOT RECORDED", icu_los_definition = "NOT RECORDED",
      icu_death_definition = NA_character_, surgery_note = "all records are surgical by construction",
      age_note = "age in years (0-117 as recorded)", comorbidity_note = "no diagnosis table in sis_emr",
      icu_by_construction = FALSE),
    flow = flow, admission = adm, icu_stay = empty_icu_stay(), diagnosis = empty_diagnosis(),
    direct_flags = data.table::data.table(admission_id = character(), comorbidity = character(), value = integer()),
    measurements = measurements, support = empty_support(), severity = empty_severity(),
    availability = data.table::data.table(
      domain = c("Demographics", "Hospital mortality", "ICU stay structure", "ICU mortality", "Comorbidities (coded)",
                 "Vital signs", "Laboratory", "Organ support", "Severity scores", "Microbiology", "Medication", "Surgery/anaesthesia"),
      status = c("available", "unavailable", "unavailable", "unavailable", "unavailable", "partial", "partial", "unavailable",
                 "unavailable", "unavailable", "available", "available"),
      note = c("age, sex", "no outcome fields", "none", "none", "none", "intra-operative minute-level monitor values; NIBP only",
               "5 intra-operative blood-gas analytes; units assumed", "none", "none", "none",
               "intra-operative drug administrations; not harmonised in v0.1", "ventilator, a-line, procedure events")))
  ds$admission <- finalize_admission(ds$admission, ds$icu_stay)
  ds
}
