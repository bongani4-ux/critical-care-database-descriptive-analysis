# =============================================================================
# INSPIRE v1.4.2 adapter (perioperative; Seoul National University Hospital).
#
# Unit of analysis: hospital admission (hadm_id; 126,673 admissions, 99,886 patients), built
# from the operations table (130,960 operations). All times are MINUTES on a patient-specific
# relative clock, so records are linked to an admission by (subject_id, time window).
#
# Mortality (the review's INSPIRE figure is NOT an index-admission rate):
#   * inhosp_death_time is propagated to every operation of a patient who died in hospital at
#     ANY admission. Index-admission in-hospital death here = death time inside THIS admission's
#     [admission_time, discharge_time]  (630 admissions; 477 first admissions).
#   * The review's 923/99,886 equals the number of patients whose FIRST operation row carries a
#     non-missing inhosp_death_time (i.e. 'ever died in hospital', 942 patients over all rows).
#   * allcause_death_time -> death at any follow-up (13,304 patients = 13.3%, as in the review).
# =============================================================================

adapter_meta <- list(
  db_id = "inspire",
  required_files = c("operations.csv", "diagnosis.csv", "labs.csv", "vitals.csv", "ward_vitals.csv", "parameters.csv"))

INSPIRE_VASO_ITEMS <- c("nepi", "epii", "dopai", "pepi", "vaso")

adapter_build <- function(cfg) {
  flow <- flow_new()
  rd <- function(f, ...) data.table::fread(db_file_any(adapter_meta$db_id, f), showProgress = FALSE, ...)
  o <- rd("operations.csv", colClasses = list(character = c("subject_id", "hadm_id", "op_id")))
  assert_unique(o, "op_id", "INSPIRE operations"); assert_no_missing(o, c("subject_id", "hadm_id"), "INSPIRE operations")
  flow <- flow_add(flow, "Operations", n_admissions = data.table::uniqueN(o$hadm_id), n_patients = data.table::uniqueN(o$subject_id),
                   note = paste(nrow(o), "operations"))
  # admission-level constants must really be constant within hadm_id
  for (cl in c("admission_time", "discharge_time")) {
    if (o[, data.table::uniqueN(get(cl)), by = hadm_id][, any(V1 > 1L)]) ccdb_stop("[inspire] ", cl, " varies within hadm_id")
  }
  o[, dth_in := !is.na(inhosp_death_time) & inhosp_death_time >= admission_time & inhosp_death_time <= discharge_time]
  first_op <- data.table::copy(o)[order(subject_id, opdate, op_id)][, .SD[1], by = subject_id]
  extra_metrics <- list(hosp_death_n_first_op_flag = sum(!is.na(first_op$inhosp_death_time)))

  h <- o[, .(patient_id = subject_id[1], age_years = suppressWarnings(as.numeric(min(age, na.rm = TRUE))), sex = sex[1],
             adm = as.numeric(admission_time[1]), dis = as.numeric(discharge_time[1]),
             emop = as.integer(any(emop == 1L, na.rm = TRUE)), asa = suppressWarnings(as.numeric(max(asa, na.rm = TRUE))),
             dth = any(dth_in), dept = department[1], allcause = any(!is.na(allcause_death_time))), by = hadm_id]
  h[is.infinite(asa), asa := NA_real_]; h[is.infinite(age_years), age_years := NA_real_]
  adm <- h[, .(db_id = adapter_meta$db_id, patient_id, admission_id = hadm_id, age_years, sex = harmonize_sex(sex),
               hosp_los_days = (dis - adm) / 1440, hosp_death = as.integer(dth), admit_sort_key = adm,
               admission_urgency = data.table::fifelse(emop == 1L, "emergency", "elective"),
               admission_source = dept, discharge_disposition = NA_character_, period = NA_character_,
               death_any_followup = as.integer(allcause), surgery_flag = 1L)]
  flow <- flow_add(flow, "Hospital admissions with >= 1 operation", admission = adm)

  icu_rows <- unique(o[!is.na(icuin_time), .(subject_id, hadm_id, icuin_time, icuout_time)])
  data.table::setorder(icu_rows, hadm_id, icuin_time); icu_rows[, stay_seq := seq_len(.N), by = hadm_id]
  icu <- icu_rows[, .(db_id = adapter_meta$db_id, patient_id = subject_id, admission_id = hadm_id, stay_id = paste0(hadm_id, "_ICU", stay_seq),
                      stay_seq, icu_los_days = (icuout_time - icuin_time) / 1440, icu_unit = NA_character_, icu_death = NA_integer_)]
  severity <- h[!is.na(asa), .(admission_id = hadm_id, score = "ASA physical status (max of the admission's operations)", value = asa)]

  # ---- diagnoses: all codes recorded up to the end of the admission (history + current) ---------------------------------
  dx <- rd("diagnosis.csv", colClasses = list(character = c("subject_id", "icd10_cm")))
  win_all <- h[, .(subject_id = patient_id, admission_id = hadm_id, dis)]
  dxj <- dx[win_all, on = .(subject_id, chart_time <= dis), nomatch = 0L, .(admission_id, code = icd10_cm)]
  diagnosis <- unique(dxj[!is.na(code) & nzchar(code), .(admission_id, code, code_system = "ICD10")])

  # ---- measurements: first value in the first 24 h of hospital admission ------------------------------------------------------
  mp <- data.table::fread(ccdb_path("databases", "inspire", "mapping_measurements.csv"), colClasses = "character", encoding = "UTF-8")
  par <- rd("parameters.csv")
  unit_check <- merge(mp, par[, .(source = Table, item = Label, par_unit = Unit)][, source := c(labs = "lab", vitals = "vitals", ward_vitals = "ward")[source]],
                      by = c("source", "item"), all.x = TRUE)
  if (anyNA(unit_check$par_unit)) {
    # an item that this VERSION does not contain (e.g. ward art_sbp was added in v1.4.2) is dropped with a warning
    miss <- unit_check[is.na(par_unit), paste(source, item)]
    log_msg("WARN", "[", adapter_meta$db_id, "] mapped item(s) absent from this version's parameters.csv, dropped: ", paste(miss, collapse = ", "))
    mp <- mp[!paste(source, item) %in% miss]
  }
  win <- cfg$measurements$window_hours; pre <- cfg$measurements$pre_index_hours
  win24 <- h[, .(subject_id = patient_id, admission_id = hadm_id, lo = adm - pre * 60, hi = adm + win * 60, adm)]
  index <- h[, .(unit_key = hadm_id, index_hours = adm / 60)]
  run_src <- function(file, src, cols) {
    m <- mp[source == src, .(item, analyte, source_unit)]
    items <- m$item
    stream_file(db_file_any(adapter_meta$db_id, file), function(ch) {
      ch <- ch[item_name %in% items]
      if (!nrow(ch)) return(NULL)
      j <- win24[ch, on = .(subject_id, lo <= chart_time, hi >= chart_time), nomatch = 0L,
                 .(unit_key = admission_id, item = item_name, time_hours = chart_time / 60, value = value, unit = NA_character_)]
      if (!nrow(j)) return(NULL)
      reduce_chunk_first_in_window(j, m, index, win, pre)
    }, col_types = do.call(readr::cols_only, cols), label = paste("INSPIRE", file),
    arrow_filter = function(d) dplyr::filter(d, item_name %in% items))
  }
  red <- list(
    run_src("labs.csv", "lab", list(subject_id = "c", chart_time = "d", item_name = "c", value = "d")),
    run_src("ward_vitals.csv", "ward", list(subject_id = "c", chart_time = "d", item_name = "c", value = "d")),
    run_src("vitals.csv", "vitals", list(subject_id = "c", chart_time = "d", item_name = "c", value = "d")))
  meas <- combine_first_in_window(data.table::rbindlist(red, use.names = TRUE, fill = TRUE))
  measurements <- meas[, .(admission_id = unit_key, stay_id = NA_character_, analyte, value, hours_from_index, n_in_window)]

  # ---- support flags over the whole admission window ----------------------------------------------------------------------------
  win_adm <- h[, .(subject_id = patient_id, admission_id = hadm_id, adm, dis)]
  wv <- stream_file(db_file_any(adapter_meta$db_id, "ward_vitals.csv"), function(ch) {
    ch <- ch[item_name %in% c("vent", "crrt") & value > 0]
    if (!nrow(ch)) return(NULL)
    win_adm[ch, on = .(subject_id, adm <= chart_time, dis >= chart_time), nomatch = 0L, .(admission_id, support_type = data.table::fifelse(item_name == "vent", "mech_vent", "rrt"))]
  }, col_types = readr::cols_only(subject_id = "c", chart_time = "d", item_name = "c", value = "d"), label = "INSPIRE ward_vitals (support)",
  arrow_filter = function(d) dplyr::filter(d, item_name %in% c("vent", "crrt") & value > 0))
  vv <- stream_file(db_file_any(adapter_meta$db_id, "vitals.csv"), function(ch) {
    ch <- ch[item_name %in% INSPIRE_VASO_ITEMS & value > 0]
    if (!nrow(ch)) return(NULL)
    win_adm[ch, on = .(subject_id, adm <= chart_time, dis >= chart_time), nomatch = 0L, .(admission_id, support_type = "vasopressor")]
  }, col_types = readr::cols_only(subject_id = "c", chart_time = "d", item_name = "c", value = "d"), label = "INSPIRE vitals (vasopressor infusions)",
  arrow_filter = function(d) dplyr::filter(d, item_name %in% INSPIRE_VASO_ITEMS & value > 0))
  support <- unique(data.table::rbindlist(list(wv, vv), use.names = TRUE, fill = TRUE))[, value := 1L]
  if (!nrow(support)) support <- empty_support()

  flow <- flow_add(flow, "Final cohort", admission = adm, icu_stay = icu)
  ds <- list(
    meta = list(
      index_definition = "hospital admission (admission_time)", measurement_index = "hospital_admission",
      measurement_analytes_available = unique(measurements$analyte),
      support_available = c("mech_vent", "rrt", "vasopressor"), support_scope = "hospital",
      support_definition = list(
        mech_vent = "ward_vitals 'vent' = 1 at any time in the admission (ward charting; intra-operative ventilation not counted)",
        rrt = "ward_vitals 'crrt' = 1 (haemodialysis or CRRT) at any time in the admission",
        vasopressor = "intra-operative infusion record of norepinephrine/epinephrine/dopamine/phenylephrine/vasopressin (intra-operative only)"),
      hosp_death_definition = "inhosp_death_time inside this admission's [admission_time, discharge_time] (the raw field is propagated across a patient's admissions)",
      hosp_los_definition = "(discharge_time - admission_time) / 1440", icu_los_definition = "sum over distinct (icuin_time, icuout_time) pairs",
      icu_death_definition = NA_character_,
      surgery_note = "all admissions have >= 1 operation by construction",
      age_note = "age at operation (years; 5-year top-code 90)", followup_note = "allcause_death_time (variable follow-up; NOT a fixed landmark)",
      comorbidity_note = "ICD-10-CM codes recorded up to the end of the admission (history + current); 3-character resolution",
      extra_metrics = extra_metrics, icu_by_construction = FALSE),
    flow = flow, admission = adm, icu_stay = icu, diagnosis = diagnosis,
    direct_flags = data.table::data.table(admission_id = character(), comorbidity = character(), value = integer()),
    measurements = measurements, support = support, severity = severity,
    availability = data.table::data.table(
      domain = c("Demographics", "Hospital mortality", "ICU stay structure", "ICU mortality", "Comorbidities (coded)",
                 "Vital signs", "Laboratory", "Organ support", "Severity scores", "Microbiology", "Medication", "Surgery/anaesthesia"),
      status = c("available", "available", "partial", "unavailable", "available", "partial", "available", "partial", "partial",
                 "unavailable", "available", "available"),
      note = c("age (years), sex", "death time inside admission window", "ICU in/out times per operation", "no ICU outcome",
               "ICD-10-CM", "intra-operative + ward vitals; first 24 h of admission mostly intra-operative", "labs (units from parameters.csv)",
               "ward ventilation/CRRT flags; intra-operative vasopressors", "ASA physical status only", "none",
               "medications (ATC); not harmonised in v0.1", "operations: ICD-10-PCS, ASA, anaesthesia type")))
  ds$admission <- finalize_admission(ds$admission, ds$icu_stay)
  ds
}
