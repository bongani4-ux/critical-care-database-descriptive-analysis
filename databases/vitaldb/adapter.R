# =============================================================================
# VitalDB v1.0.0 adapter (perioperative; Seoul National University Hospital).
#
# Unit of analysis: SURGICAL CASE (caseid; 6,388) standing in for the hospital admission - the
# release has no separate admission identifier, so patients with several cases (subjectid:
# 6,090 patients) appear as several 'admissions'. The review's N = 6,388 is therefore a CASE count.
# Times in clinical_data are SECONDS relative to case start (adm < 0 = admitted before surgery).
# Vital-sign waveforms (.vital files, 100 GB) are NOT parsed in v0.1: vital signs are
# reported as unavailable, not as zero.
# =============================================================================

adapter_meta <- list(
  db_id = "vitaldb",
  required_files = c("clinical_data.csv", "lab_data.csv", "lab_parameters.csv"))

VDB_LABS <- data.table::data.table(
  item = c("cr", "hb", "wbc", "plt", "na", "k", "lac", "tbil", "gluc", "alb", "hco3"),
  analyte = c("creatinine", "hemoglobin", "wbc", "platelets", "sodium", "potassium", "lactate", "bilirubin_total", "glucose", "albumin", "bicarbonate"),
  source_unit = c("mg/dL", "g/dL", "x1000/mcL", "x1000/mcL", "mmol/L", "mmol/L", "mmol/L", "mg/dL", "mg/dL", "g/dL", "mmol/L"))

adapter_build <- function(cfg) {
  flow <- flow_new()
  cd <- data.table::fread(db_file("vitaldb", "clinical_data.csv"), showProgress = FALSE,
                          colClasses = list(character = c("caseid", "subjectid", "age")))
  assert_unique(cd, "caseid", "VitalDB clinical_data"); assert_no_missing(cd, c("caseid", "subjectid"), "VitalDB clinical_data")
  age_num <- data.table::fcase(cd$age == ">89", 90, grepl("^[0-9.]+$", cd$age), suppressWarnings(as.numeric(cd$age)), default = NA_real_)
  adm <- cd[, .(db_id = "vitaldb", patient_id = subjectid, admission_id = caseid, age_years = age_num, sex = harmonize_sex(sex),
                hosp_los_days = (as.numeric(dis) - as.numeric(adm)) / 86400,
                hosp_death = as.integer(death_inhosp), admit_sort_key = as.numeric(caseid),
                admission_urgency = data.table::fifelse(emop == 1L, "emergency", "elective"),
                admission_source = department, discharge_disposition = NA_character_, period = NA_character_,
                surgery_flag = 1L)]
  flow <- flow_add(flow, "Surgical cases in clinical_data", admission = adm, note = "case = admission stand-in")
  icu <- cd[!is.na(icu_days) & icu_days > 0, .(db_id = "vitaldb", patient_id = subjectid, admission_id = caseid, stay_id = caseid,
                                               stay_seq = 1L, icu_los_days = as.numeric(icu_days), icu_unit = NA_character_, icu_death = NA_integer_)]
  severity <- cd[!is.na(asa), .(admission_id = caseid, score = "ASA physical status", value = as.numeric(asa))]
  direct_flags <- data.table::rbindlist(list(
    cd[!is.na(preop_htn), .(admission_id = caseid, comorbidity = "HYPERTENSION", value = as.integer(preop_htn))],
    cd[!is.na(preop_dm),  .(admission_id = caseid, comorbidity = "DIABETES", value = as.integer(preop_dm))]))

  # ---- laboratory results in the first 24 h of hospital admission (relative to case start in seconds) -----------------
  lp <- data.table::fread(db_file("vitaldb", "lab_parameters.csv"))
  stopifnot(all(VDB_LABS$item %in% lp$Parameter))
  win <- cfg$measurements$window_hours; pre <- cfg$measurements$pre_index_hours
  index <- cd[, .(unit_key = caseid, index_hours = as.numeric(adm) / 3600)]
  lb <- stream_file(db_file("vitaldb", "lab_data.csv"), function(ch) {
    ch <- ch[name %in% VDB_LABS$item]
    reduce_chunk_first_in_window(ch[, .(unit_key = caseid, item = name, time_hours = dt / 3600, value = result, unit = NA_character_)],
                                 VDB_LABS, index, win, pre)
  }, col_types = readr::cols_only(caseid = "c", dt = "d", name = "c", result = "d"), label = "VitalDB lab_data")
  meas <- combine_first_in_window(lb)
  measurements <- meas[, .(admission_id = unit_key, stay_id = NA_character_, analyte, value, hours_from_index, n_in_window)]

  flow <- flow_add(flow, "Final cohort", admission = adm, icu_stay = icu)
  ds <- list(
    meta = list(
      index_definition = "hospital admission (adm, seconds before/after case start)", measurement_index = "hospital_admission",
      measurement_analytes_available = unique(measurements$analyte), support_available = character(), support_scope = "hospital",
      support_unavailable_note = "organ-support data exist only as intra-operative waveform tracks, not parsed in v0.1",
      hosp_death_definition = "clinical_data.death_inhosp == 1",
      hosp_los_definition = "(dis - adm) / 86400", icu_los_definition = "clinical_data.icu_days (post-operative ICU days)",
      icu_death_definition = NA_character_, surgery_note = "all cases are surgical by construction",
      age_note = "years; '>89' (8 cases) set to 90", comorbidity_note = "direct pre-operative flags only: hypertension (preop_htn), diabetes (preop_dm)",
      icu_by_construction = FALSE,
      extra_metrics = list(n_unique_subjects = data.table::uniqueN(cd$subjectid))),
    flow = flow, admission = adm, icu_stay = icu, diagnosis = empty_diagnosis(), direct_flags = direct_flags,
    measurements = measurements, support = empty_support(), severity = severity,
    availability = data.table::data.table(
      domain = c("Demographics", "Hospital mortality", "ICU stay structure", "ICU mortality", "Comorbidities (coded)",
                 "Vital signs", "Laboratory", "Organ support", "Severity scores", "Microbiology", "Medication", "Surgery/anaesthesia"),
      status = c("available", "available", "partial", "unavailable", "partial", "BLOCKED_not_implemented", "available", "unavailable",
                 "partial", "unavailable", "unavailable", "available"),
      note = c("age, sex", "death_inhosp", "icu_days only", "none", "two pre-operative flags", "waveform tracks (.vital) not parsed in v0.1",
               "lab_data (units from lab_parameters)", "none outside intra-operative tracks", "ASA physical status only", "none",
               "intra-operative drug totals only (clinical_data)", "rich: optype, opname, approach, position, anaesthesia type")))
  ds$admission <- finalize_admission(ds$admission, ds$icu_stay)
  ds
}
