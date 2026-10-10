# =============================================================================
# Shared builder for databases that use the MIMIC-IV table layout
# (hosp/{patients,admissions,diagnoses_icd,labevents} + icu/{icustays,chartevents,
# procedureevents[,inputevents]}). Used by MIMIC-IV and NWICU.
#
# What differs between such databases (vocabularies, item ids, available tables)
# is passed in `opts`; the logic below is shared so that it cannot drift.
# =============================================================================

#' @param opts list with:
#'   hosp_sub, icu_sub        sub-folders under the database root
#'   chart_map, lab_map       data.tables: item (id as chr), analyte, source_unit, expect_label (regex)
#'   urgency_fun, disposition_fun   functions(chr) -> harmonised category
#'   vent_label, rrt_label, vaso_label   regex on d_items$label (NA = not ascertainable)
#'   vent_scope, rrt_scope ("procedureevents") ; vaso_source ("inputevents" or NA)
#'   notes                    list copied into meta
build_mimic_like <- function(db_id, opts, cfg) {
  flow <- flow_new()
  P <- function(sub, f) db_file_any(db_id, sub, f)
  rd <- function(sub, f, ...) data.table::fread(P(sub, f), showProgress = FALSE, ...)
  ts <- function(x) as.POSIXct(x, tz = "UTC", format = "%Y-%m-%d %H:%M:%S")

  # ---- admissions + patients ------------------------------------------------------------
  pt <- rd(opts$hosp_sub, "patients.csv", select = c("subject_id", "gender", "anchor_age", "anchor_year", "anchor_year_group", "dod"))
  ad <- rd(opts$hosp_sub, "admissions.csv", select = c("subject_id", "hadm_id", "admittime", "dischtime", "deathtime",
                                                       "admission_type", "discharge_location", "hospital_expire_flag"))
  assert_unique(ad, "hadm_id", paste(db_id, "admissions"))
  assert_unique(pt, "subject_id", paste(db_id, "patients"))
  orphan <- setdiff(ad$subject_id, pt$subject_id)
  if (length(orphan)) ccdb_stop("[", db_id, "] ", length(orphan), " admissions have no patient row")
  ad[, `:=`(admit_t = ts(admittime), disch_t = ts(dischtime), death_t = ts(deathtime))]
  a <- merge(ad, pt, by = "subject_id", all.x = TRUE, sort = FALSE)
  a[, age_calc := anchor_age + (as.integer(format(admit_t, "%Y")) - anchor_year)]
  # Ages above 89 are de-identified: anchor_age is set to the censoring value (91) and
  # shifted with time. They are kept at the censoring value, not extrapolated.
  n_cens <- a[anchor_age >= 90, .N]
  a[anchor_age >= 90, age_calc := anchor_age]
  adm <- a[, .(db_id = db_id, patient_id = as.character(subject_id), admission_id = as.character(hadm_id),
               age_years = as.numeric(age_calc), sex = harmonize_sex(gender),
               hosp_los_days = as.numeric(difftime(disch_t, admit_t, units = "days")),
               hosp_death = as.integer(hospital_expire_flag),
               admit_sort_key = as.numeric(admit_t),
               admission_urgency = opts$urgency_fun(admission_type),
               admission_source = admission_type,
               discharge_disposition = opts$disposition_fun(discharge_location),
               period = anchor_year_group,
               death_any_followup = as.integer(!is.na(dod) | hospital_expire_flag == 1L),
               death_t = death_t)]
  flow <- flow_add(flow, "Hospital admissions in admissions table", admission = adm)

  # ---- ICU stays ---------------------------------------------------------------------------
  ic <- rd(opts$icu_sub, "icustays.csv")
  assert_unique(ic, "stay_id", paste(db_id, "icustays"))
  assert_fk(ic, ad, "hadm_id", paste(db_id, "icustays -> admissions"))
  ic[, `:=`(in_t = ts(intime), out_t = ts(outtime))]
  ic <- merge(ic, adm[, .(admission_id, hosp_death, death_t)][, hadm_id := as.integer(admission_id)],
              by = "hadm_id", all.x = TRUE, sort = FALSE)
  # in-ICU death: hospital death with the recorded death time inside the ICU stay window
  ic[, icu_death := as.integer(hosp_death == 1L & !is.na(death_t) & death_t >= in_t & death_t <= out_t)]
  icu <- ic[, .(db_id = db_id, patient_id = as.character(subject_id), admission_id = as.character(hadm_id),
                stay_id = as.character(stay_id), icu_los_days = as.numeric(difftime(out_t, in_t, units = "days")),
                icu_unit = first_careunit, icu_death, in_t)]
  data.table::setorder(icu, admission_id, in_t)
  icu[, stay_seq := seq_len(.N), by = admission_id]
  flow <- flow_add(flow, "ICU stays", admission = adm[admission_id %in% icu$admission_id], icu_stay = icu,
                   note = "admissions with >= 1 ICU stay")
  index_tbl <- icu[, .(index_hours = as.numeric(min(in_t)) / 3600), by = .(unit_key = admission_id)]
  adm[, death_t := NULL]

  # ---- diagnoses ---------------------------------------------------------------------------
  dx <- rd(opts$hosp_sub, "diagnoses_icd.csv", select = c("hadm_id", "icd_code", "icd_version"), colClasses = list(character = "icd_code"))
  diagnosis <- dx[, .(admission_id = as.character(hadm_id), code = icd_code,
                      code_system = data.table::fifelse(icd_version == 9L, "ICD9", "ICD10"))]

  # ---- measurement mapping, validated against the database's own dictionaries ---------------------
  di <- rd(opts$icu_sub, "d_items.csv"); dl <- rd(opts$hosp_sub, "d_labitems.csv")
  check_map <- function(map, dict, what) {
    m <- merge(map, dict[, .(item = as.character(itemid), label)], by = "item", all.x = TRUE, sort = FALSE)
    bad <- m[is.na(label) | !mapply(grepl, expect_label, label, MoreArgs = list(ignore.case = TRUE))]
    if (nrow(bad)) ccdb_stop("[", db_id, "] ", what, " mapping does not match the item dictionary for item(s): ",
                             paste0(bad$item, " (", bad$analyte, ": '", bad$label, "')", collapse = "; "))
    invisible(TRUE)
  }
  check_map(opts$chart_map, di, "chartevents"); check_map(opts$lab_map, dl, "labevents")

  win <- cfg$measurements$window_hours; pre <- cfg$measurements$pre_index_hours
  adm_of_stay <- icu[, .(stay_id, admission_id)]
  red <- list()
  idx <- index_tbl

  cm <- opts$chart_map[, .(item, analyte, source_unit)]
  red[[1]] <- stream_file(P(opts$icu_sub, "chartevents.csv"), function(ch) {
    ch <- ch[itemid %in% cm$item]
    if (!nrow(ch)) return(NULL)
    ch <- merge(ch, adm_of_stay, by = "stay_id", sort = FALSE)
    reduce_chunk_first_in_window(
      ch[, .(unit_key = admission_id, item = itemid, time_hours = as.numeric(ts(charttime)) / 3600,
             value = suppressWarnings(as.numeric(valuenum)), unit = valueuom)], cm, idx, win, pre)
  }, col_types = readr::cols_only(stay_id = "c", itemid = "c", charttime = "c", valuenum = "c", valueuom = "c"),
  label = paste(db_id, "chartevents"))

  lm <- opts$lab_map[, .(item, analyte, source_unit)]
  red[[2]] <- stream_file(P(opts$hosp_sub, "labevents.csv"), function(ch) {
    ch <- ch[itemid %in% lm$item & !is.na(hadm_id)]
    if (!nrow(ch)) return(NULL)
    reduce_chunk_first_in_window(
      ch[, .(unit_key = hadm_id, item = itemid, time_hours = as.numeric(ts(charttime)) / 3600,
             value = suppressWarnings(as.numeric(valuenum)), unit = valueuom)], lm, idx, win, pre)
  }, col_types = readr::cols_only(hadm_id = "c", itemid = "c", charttime = "c", valuenum = "c", valueuom = "c"),
  label = paste(db_id, "labevents"))

  meas <- combine_first_in_window(data.table::rbindlist(red, use.names = TRUE, fill = TRUE))
  measurements <- meas[, .(admission_id = unit_key, stay_id = NA_character_, analyte, value, hours_from_index, n_in_window)]

  # ---- organ support from ICU procedure / input events -------------------------------------------------
  stay_flag <- function(src_file, label_rx, label) {
    if (is.na(label_rx)) return(NULL)
    ids <- di[grepl(label_rx, label, ignore.case = TRUE) & linksto == src_file, as.character(itemid)]
    if (!length(ids)) return(NULL)
    log_msg("INFO", "[", db_id, "] ", label, " items: ", paste(ids, collapse = ","))
    hit <- stream_file(P(opts$icu_sub, paste0(src_file, ".csv")), function(ch) ch[itemid %in% ids, .(stay_id)],
                       col_types = readr::cols_only(stay_id = "c", itemid = "c"), label = paste(db_id, src_file))
    if (is.null(hit)) return(data.table::data.table(admission_id = character(), support_type = character(), value = integer()))
    adm_ids <- unique(merge(unique(hit), adm_of_stay, by = "stay_id")$admission_id)
    data.table::data.table(admission_id = adm_ids, support_type = label, value = 1L)
  }
  support <- data.table::rbindlist(list(
    stay_flag("procedureevents", opts$vent_label, "mech_vent"),
    stay_flag("procedureevents", opts$rrt_label, "rrt"),
    if (!is.na(opts$vaso_source)) stay_flag(opts$vaso_source, opts$vaso_label, "vasopressor")), use.names = TRUE, fill = TRUE)
  if (!nrow(support)) support <- empty_support()

  flow <- flow_add(flow, "Final cohort (all hospital admissions)", admission = adm, icu_stay = icu)
  icu[, in_t := NULL]

  sup_av <- c(if (!is.na(opts$vent_label)) "mech_vent", if (!is.na(opts$rrt_label)) "rrt",
              if (!is.na(opts$vaso_source)) "vasopressor")
  ds <- list(
    meta = c(list(
      index_definition = "first ICU admission (intime); non-ICU admissions have no index",
      measurement_index = "first_icu_admission",
      measurement_analytes_available = unique(measurements$analyte),
      support_available = sup_av, support_scope = "icu",
      hosp_death_definition = "admissions.hospital_expire_flag == 1",
      hosp_los_definition = "dischtime - admittime",
      icu_los_definition = "sum over ICU stays of (outtime - intime)",
      icu_death_definition = "hospital death with deathtime inside [intime, outtime] of the ICU stay",
      age_note = sprintf("anchor_age + (admission year - anchor_year); %d patients with anchor_age >= 90 are censored and kept at the censoring value", n_cens),
      followup_note = "patients.dod (state death records; limited post-discharge window) or in-hospital death",
      icu_by_construction = FALSE), opts$notes),
    flow = flow, admission = adm, icu_stay = icu[, .(db_id, patient_id, admission_id, stay_id, stay_seq, icu_los_days, icu_unit, icu_death)],
    diagnosis = diagnosis,
    direct_flags = data.table::data.table(admission_id = character(), comorbidity = character(), value = integer()),
    measurements = measurements, support = support, severity = empty_severity(),
    availability = opts$availability)
  ds$admission <- finalize_admission(ds$admission, ds$icu_stay)
  ds
}

# Read a mapping CSV shipped with an adapter (editable without touching code).
read_mapping <- function(db_id, file) {
  f <- ccdb_path("databases", db_id, file)
  m <- data.table::fread(f, colClasses = "character", encoding = "UTF-8", na.strings = c("", "NA"))
  m[, item := as.character(item)]
  m
}
