# =============================================================================
# HiRID v1.1.1 adapter. One ICU admission per patient (33,905 patients).
#
# Sources: reference_data/general_table.csv (sex, age, admission time, ICU discharge status),
# raw_stage observation tables (parquet) and pharma records (parquet).
# The large parquet archives are unpacked into the cache folder (outside the repository)
# unless `hirid_parquet_dir` in config/paths.local.yml already points at an unpacked copy.
#
# What HiRID does NOT contain: hospital outcome / hospital LOS (the discharge status is the
# ICU discharge status), ICD diagnoses, severity scores (APACHE group only), RRT records.
# ICU LOS is derived as (last observation - admission time): HiRID releases data only up to
# ICU discharge. Age is released in 5-year bins (20, 25, ..., 90).
# =============================================================================

adapter_meta <- list(
  db_id = "hirid",
  required_files = c("reference_data/general_table.csv", "reference_data/hirid_variable_reference.csv"))

HIRID_VASO_PHARMA <- c(1000462L, 1000656L, 1000657L, 1000658L,      # noradrenaline
                       71L, 1000750L, 1000649L, 1000650L, 1000655L,  # adrenaline
                       426L, 112L, 113L)                             # dobutamine, vasopressin
HIRID_VENT_MODE <- 3845L                                             # 'Ventilator mode' (categorical)

hirid_dir <- function(kind = c("observation", "pharma")) {
  kind <- match.arg(kind)
  if (kind == "observation") {
    d <- CCDB$paths$hirid_parquet_dir
    if (!is.null(d) && dir.exists(d)) return(d)
    dest <- ccdb_cache_dir("hirid_observation")
    untar_cached(db_file("hirid", "raw_stage", "observation_tables_parquet.tar.gz"), dest,
                 marker = file.path("observation_tables", "parquet", "part-0.parquet"))
    return(file.path(dest, "observation_tables", "parquet"))
  }
  dest <- ccdb_cache_dir("hirid_pharma")
  untar_cached(db_file("hirid", "raw_stage", "pharma_records_parquet.tar.gz"), dest,
               marker = file.path("pharma_records", "parquet", "part-0.parquet"))
  file.path(dest, "pharma_records", "parquet")
}

adapter_build <- function(cfg) {
  flow <- flow_new()
  gt <- data.table::fread(db_file("hirid", "reference_data", "general_table.csv"), colClasses = list(character = "patientid"))
  assert_unique(gt, "patientid", "HiRID general_table")
  gt[, adm_h := fast_ts_hours(admissiontime)]

  obs_dir <- hirid_dir("observation"); pharma_dir <- hirid_dir("pharma")
  opt_pkg("arrow"); opt_pkg("dplyr")

  # ICU stay end = last observation per patient (HiRID data end at ICU discharge)
  last_obs <- dplyr::collect(dplyr::summarise(dplyr::group_by(arrow::open_dataset(obs_dir), patientid),
                                              tmax = max(datetime)))
  last_obs <- data.table::as.data.table(last_obs)
  last_obs[, `:=`(patientid = as.character(patientid), tmax_h = as.numeric(tmax) / 3600)]
  gt <- merge(gt, last_obs[, .(patientid, tmax_h)], by = "patientid", all.x = TRUE, sort = FALSE)
  gt[, icu_los := (tmax_h - adm_h) / 24]

  adm <- gt[, .(db_id = "hirid", patient_id = patientid, admission_id = patientid,
                age_years = as.numeric(age), sex = harmonize_sex(sex),
                hosp_los_days = NA_real_, hosp_death = NA_integer_,       # hospital outcome not recorded
                admit_sort_key = adm_h, admission_urgency = NA_character_, admission_source = NA_character_,
                discharge_disposition = NA_character_, period = NA_character_)]
  flow <- flow_add(flow, "Patients in general_table (1 ICU admission each)", admission = adm)
  icu <- gt[, .(db_id = "hirid", patient_id = patientid, admission_id = patientid, stay_id = patientid, stay_seq = 1L,
                icu_los_days = icu_los, icu_unit = NA_character_,
                icu_death = data.table::fcase(discharge_status == "dead", 1L, discharge_status == "alive", 0L,
                                              default = NA_integer_))]
  index <- gt[, .(unit_key = patientid, index_hours = adm_h)]

  # ---- measurements + ventilator flag from the observation parquet -------------------------------------------------------
  mp <- data.table::fread(ccdb_path("databases", "hirid", "mapping_measurements.csv"), colClasses = "character", encoding = "UTF-8")
  vref <- data.table::fread(db_file("hirid", "reference_data", "hirid_variable_reference.csv"), colClasses = list(character = "ID"))
  chk <- merge(mp, vref[`Source Table` == "Observation", .(item = ID, label = `Variable Name`)], by = "item", all.x = TRUE)
  bad <- chk[is.na(label) | !mapply(grepl, expect_label, label)]
  if (nrow(bad)) ccdb_stop("[hirid] mapping does not match hirid_variable_reference: ",
                           paste0(bad$item, " ('", bad$label, "')", collapse = "; "))
  mm <- mp[, .(item, analyte, source_unit)]
  ids <- as.integer(mm$item)
  win <- cfg$measurements$window_hours; pre <- cfg$measurements$pre_index_hours
  vent_hit <- list()
  red <- stream_parquet_dir(obs_dir, function(ch) {
    ch[, `:=`(unit_key = as.character(patientid), th = as.numeric(datetime) / 3600)]
    v <- merge(ch[variableid == HIRID_VENT_MODE, .(unit_key, th)], index, by = "unit_key")
    vent_hit[[length(vent_hit) + 1L]] <<- unique(v[th >= index_hours, unit_key])      # any time during the ICU stay (observations end at ICU discharge)
    ch <- ch[variableid %in% ids]
    if (!nrow(ch)) return(NULL)
    reduce_chunk_first_in_window(ch[, .(unit_key, item = as.character(variableid), time_hours = th,
                                        value = as.numeric(value), unit = NA_character_)], mm, index, win, pre)
  }, arrow_filter = function(d) dplyr::select(dplyr::filter(d, variableid %in% c(ids, HIRID_VENT_MODE) & !is.na(value) | variableid == HIRID_VENT_MODE),
                                              patientid, datetime, variableid, value),
  label = "HiRID observation_tables")
  meas <- combine_first_in_window(red)
  measurements <- meas[, .(admission_id = unit_key, stay_id = NA_character_, analyte, value, hours_from_index, n_in_window)]

  # ---- vasopressors from pharma records (any positive dose during the ICU stay) ---------------------------------------------------
  vp <- stream_parquet_dir(pharma_dir, function(ch) {
    ch[, `:=`(unit_key = as.character(patientid), th = as.numeric(givenat) / 3600)]
    ch <- merge(ch, index, by = "unit_key")
    ch[th >= index_hours & givendose > 0, .(unit_key)]
  }, arrow_filter = function(d) dplyr::select(dplyr::filter(d, pharmaid %in% HIRID_VASO_PHARMA), patientid, pharmaid, givenat, givendose),
  label = "HiRID pharma_records")
  support <- data.table::rbindlist(list(
    data.table::data.table(admission_id = unique(unlist(vent_hit)), support_type = "mech_vent", value = 1L),
    data.table::data.table(admission_id = if (is.null(vp)) character() else unique(vp$unit_key), support_type = "vasopressor", value = 1L)))
  # keep only vasopressor records inside the ICU stay (before the last observation)
  flow <- flow_add(flow, "Final cohort", admission = adm, icu_stay = icu)

  ds <- list(
    meta = list(
      index_definition = "ICU admission time (general_table.admissiontime)",
      measurement_index = "first_icu_admission", measurement_analytes_available = unique(measurements$analyte),
      support_available = c("mech_vent", "vasopressor"), support_scope = "icu",
      support_definition = list(
        mech_vent = "'Ventilator mode' (variable 3845) recorded at any time during the ICU stay - invasive and non-invasive modes cannot be separated",
        vasopressor = "pharma record with dose > 0 of noradrenaline, adrenaline, vasopressin or dobutamine during the ICU stay"),
      support_unavailable_note = "no renal-replacement records in the released tables (Haemofiltration has no pharma rows); tracheostomy/intubation not coded",
      hosp_death_definition = "NOT RECORDED (discharge_status is the ICU discharge status)",
      hosp_los_definition = "NOT RECORDED",
      icu_los_definition = "last observation time - admission time (data end at ICU discharge)",
      icu_death_definition = "general_table.discharge_status == 'dead' (239 blank = missing)",
      age_note = "5-year age bins (20, 25, ..., 90); medians are approximate",
      comorbidity_note = "no diagnosis codes in HiRID",
      icu_by_construction = TRUE),
    flow = flow, admission = adm, icu_stay = icu, diagnosis = empty_diagnosis(),
    direct_flags = data.table::data.table(admission_id = character(), comorbidity = character(), value = integer()),
    measurements = measurements, support = support, severity = empty_severity(),
    availability = data.table::data.table(
      domain = c("Demographics", "Hospital mortality", "ICU stay structure", "ICU mortality", "Comorbidities (coded)",
                 "Vital signs", "Laboratory", "Organ support", "Severity scores", "Microbiology", "Medication", "Surgery/anaesthesia"),
      status = c("partial", "unavailable", "available", "available", "unavailable", "available", "available", "partial",
                 "unavailable", "unavailable", "available", "unavailable"),
      note = c("age in 5-year bins", "ICU discharge status only", "one ICU stay per patient (LOS derived)", "general_table.discharge_status",
               "no diagnosis codes", "high-resolution monitor data", "laboratory (LOINC-like variables)",
               "ventilator mode (invasive/NIV mixed) and vasopressors; no RRT", "APACHE group only (categorical)",
               "none", "pharma_records; not harmonised in v0.1", "none")))
  ds$admission <- finalize_admission(ds$admission, ds$icu_stay)
  ds
}
