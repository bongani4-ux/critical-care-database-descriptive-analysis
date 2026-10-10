# =============================================================================
# PIC v1.1.0 (Paediatric Intensive Care database) adapter.
# Unit of analysis: hospital admission (HADM_ID); ICU stays (ICUSTAY_ID) nested within.
# Every PIC admission is a PICU admission by construction. Age is derived from
# DOB (shifted, de-identified) and is in YEARS (most patients are < 1 year), so
# the adult age bands are uninformative here: every unit falls in '<18'.
# Diagnoses are Chinese-extended ICD-10 (ICD10_CODE_CN, e.g. K52.901); the shared
# comorbidity patterns match on the 3-character category prefix.
# =============================================================================

adapter_meta <- list(
  db_id = "pic",
  required_files = c("ADMISSIONS.csv", "PATIENTS.csv", "ICUSTAYS.csv", "DIAGNOSES_ICD.csv",
                     "CHARTEVENTS.csv", "LABEVENTS.csv", "D_ITEMS.csv", "D_LABITEMS.csv"))

adapter_build <- function(cfg) {
  flow <- flow_new()
  rd <- function(f, ...) data.table::fread(db_file_any("pic", f), showProgress = FALSE, ...)
  ts <- function(x) as.POSIXct(x, tz = "UTC", format = "%Y-%m-%d %H:%M:%S")

  ad <- rd("ADMISSIONS.csv", select = c("SUBJECT_ID", "HADM_ID", "ADMITTIME", "DISCHTIME", "DEATHTIME",
                                        "HOSPITAL_EXPIRE_FLAG", "ADMISSION_DEPARTMENT"))
  pt <- rd("PATIENTS.csv", select = c("SUBJECT_ID", "GENDER", "DOB", "DOD"))
  assert_unique(ad, "HADM_ID", "PIC admissions"); assert_unique(pt, "SUBJECT_ID", "PIC patients")
  assert_fk(ad, pt, "SUBJECT_ID", "PIC admissions -> patients")
  ad[, `:=`(admit_t = ts(ADMITTIME), disch_t = ts(DISCHTIME), death_t = ts(DEATHTIME))]
  a <- merge(ad, pt[, .(SUBJECT_ID, GENDER, dob = ts(DOB))], by = "SUBJECT_ID", all.x = TRUE, sort = FALSE)
  adm <- a[, .(db_id = "pic", patient_id = as.character(SUBJECT_ID), admission_id = as.character(HADM_ID),
               # newborns admitted a few hours 'before' the recorded DOB time-of-day give tiny negative ages
               # (68 admissions, all > -0.002 y): clamped to 0. Any age below -0.01 y would be left as is and flagged.
               age_years = {x <- as.numeric(difftime(admit_t, dob, units = "days")) / 365.25; data.table::fifelse(x < 0 & x > -0.01, 0, x)},
               sex = harmonize_sex(GENDER),
               hosp_los_days = as.numeric(difftime(disch_t, admit_t, units = "days")),
               hosp_death = as.integer(HOSPITAL_EXPIRE_FLAG),
               admit_sort_key = as.numeric(admit_t),
               admission_urgency = NA_character_, admission_source = ADMISSION_DEPARTMENT,
               discharge_disposition = NA_character_, period = NA_character_,
               death_t = death_t)]
  flow <- flow_add(flow, "Hospital admissions", admission = adm)

  ic <- rd("ICUSTAYS.csv", select = c("SUBJECT_ID", "HADM_ID", "ICUSTAY_ID", "FIRST_CAREUNIT", "INTIME", "OUTTIME"))
  assert_unique(ic, "ICUSTAY_ID", "PIC icustays"); assert_fk(ic, ad, "HADM_ID", "PIC icustays -> admissions")
  ic[, `:=`(in_t = ts(INTIME), out_t = ts(OUTTIME))]
  ic <- merge(ic, adm[, .(admission_id, hosp_death, death_t)][, HADM_ID := as.integer(admission_id)], by = "HADM_ID", all.x = TRUE, sort = FALSE)
  ic[, icu_death := as.integer(hosp_death == 1L & !is.na(death_t) & death_t >= in_t & death_t <= out_t)]
  icu <- ic[, .(db_id = "pic", patient_id = as.character(SUBJECT_ID), admission_id = as.character(HADM_ID),
                stay_id = as.character(ICUSTAY_ID), icu_los_days = as.numeric(difftime(out_t, in_t, units = "days")),
                icu_unit = FIRST_CAREUNIT, icu_death, in_t)]
  data.table::setorder(icu, admission_id, in_t); icu[, stay_seq := seq_len(.N), by = admission_id]
  index <- icu[, .(index_hours = as.numeric(min(in_t)) / 3600), by = .(unit_key = admission_id)]
  adm[, death_t := NULL]

  dx <- rd("DIAGNOSES_ICD.csv", select = c("HADM_ID", "ICD10_CODE_CN"), colClasses = list(character = "ICD10_CODE_CN"))
  diagnosis <- unique(dx[!is.na(ICD10_CODE_CN) & nzchar(ICD10_CODE_CN),
                         .(admission_id = as.character(HADM_ID), code = ICD10_CODE_CN, code_system = "ICD10")])

  # ---- measurements -------------------------------------------------------------------------------------------------
  cm <- read_mapping("pic", "mapping_chartevents.csv"); lm <- read_mapping("pic", "mapping_labevents.csv")
  di <- rd("D_ITEMS.csv", colClasses = list(character = "ITEMID")); dl <- rd("D_LABITEMS.csv", colClasses = list(character = "ITEMID"))
  chk <- function(map, dict, what) {
    m <- merge(map, dict[, .(item = ITEMID, label = LABEL)], by = "item", all.x = TRUE, sort = FALSE)
    bad <- m[is.na(label) | !mapply(grepl, expect_label, label, MoreArgs = list(ignore.case = TRUE))]
    if (nrow(bad)) ccdb_stop("[pic] ", what, " mapping does not match the dictionary: ",
                             paste0(bad$item, " ('", bad$label, "')", collapse = "; "))
  }
  chk(cm, di, "chartevents"); chk(lm, dl, "labevents")
  win <- cfg$measurements$window_hours; pre <- cfg$measurements$pre_index_hours
  adm_of_stay <- icu[, .(stay_id, admission_id)]
  red <- list()
  red[[1]] <- stream_file(db_file_any("pic", "CHARTEVENTS.csv"), function(ch) {
    ch <- ch[ITEMID %in% cm$item]
    if (!nrow(ch)) return(NULL)
    ch <- merge(ch, adm_of_stay, by.x = "ICUSTAY_ID", by.y = "stay_id", sort = FALSE)
    reduce_chunk_first_in_window(ch[, .(unit_key = admission_id, item = ITEMID, time_hours = fast_ts_hours(CHARTTIME),
                                        value = suppressWarnings(as.numeric(VALUENUM)), unit = VALUEUOM)],
                                 cm[, .(item, analyte, source_unit)], index, win, pre)
  }, col_types = readr::cols_only(ICUSTAY_ID = "c", ITEMID = "c", CHARTTIME = "c", VALUENUM = "c", VALUEUOM = "c"), label = "PIC chartevents",
                          arrow_filter = function(d) dplyr::filter(d, ITEMID %in% cm$item))
  red[[2]] <- stream_file(db_file_any("pic", "LABEVENTS.csv"), function(ch) {
    ch <- ch[ITEMID %in% lm$item & !is.na(HADM_ID)]
    if (!nrow(ch)) return(NULL)
    reduce_chunk_first_in_window(ch[, .(unit_key = HADM_ID, item = ITEMID, time_hours = fast_ts_hours(CHARTTIME),
                                        value = suppressWarnings(as.numeric(VALUENUM)), unit = VALUEUOM)],
                                 lm[, .(item, analyte, source_unit)], index, win, pre)
  }, col_types = readr::cols_only(HADM_ID = "c", ITEMID = "c", CHARTTIME = "c", VALUENUM = "c", VALUEUOM = "c"), label = "PIC labevents",
                          arrow_filter = function(d) dplyr::filter(d, ITEMID %in% lm$item))
  meas <- combine_first_in_window(data.table::rbindlist(red, use.names = TRUE, fill = TRUE))
  measurements <- meas[, .(admission_id = unit_key, stay_id = NA_character_, analyte, value, hours_from_index, n_in_window)]

  flow <- flow_add(flow, "Final cohort (all admissions are PICU admissions)", admission = adm, icu_stay = icu)
  icu[, in_t := NULL]
  ds <- list(
    meta = list(
      index_definition = "first ICU admission (INTIME)", measurement_index = "first_icu_admission",
      measurement_analytes_available = unique(measurements$analyte),
      support_available = character(), support_scope = "icu",
      support_unavailable_note = "PIC has no ventilation, dialysis or vasopressor records (INPUTEVENTS holds fluids only)",
      hosp_death_definition = "ADMISSIONS.HOSPITAL_EXPIRE_FLAG == 1",
      hosp_los_definition = "DISCHTIME - ADMITTIME", icu_los_definition = "sum over ICU stays of (OUTTIME - INTIME)",
      icu_death_definition = "hospital death with DEATHTIME inside [INTIME, OUTTIME]",
      age_note = "(ADMITTIME - DOB) / 365.25; paediatric - all units are <18 years; most are infants",
      comorbidity_note = "Chinese-extended ICD-10 (DIAGNOSES_ICD); 3-character prefix matching",
      icu_by_construction = TRUE),
    flow = flow, admission = adm, icu_stay = icu[, .(db_id, patient_id, admission_id, stay_id, stay_seq, icu_los_days, icu_unit, icu_death)],
    diagnosis = diagnosis,
    direct_flags = data.table::data.table(admission_id = character(), comorbidity = character(), value = integer()),
    measurements = measurements, support = empty_support(), severity = empty_severity(),
    availability = data.table::data.table(
      domain = c("Demographics", "Hospital mortality", "ICU stay structure", "ICU mortality", "Comorbidities (coded)",
                 "Vital signs", "Laboratory", "Organ support", "Severity scores", "Microbiology", "Medication", "Surgery/anaesthesia"),
      status = c("available", "available", "available", "partial", "available", "available", "available", "unavailable",
                 "unavailable", "available", "available", "partial"),
      note = c("age from shifted DOB; paediatric", "HOSPITAL_EXPIRE_FLAG", "ICUSTAYS", "derived from DEATHTIME within ICU stay",
               "Chinese-extended ICD-10", "CHARTEVENTS (6 items; BP method not recorded)", "LABEVENTS", "no records",
               "none", "MICROBIOLOGYEVENTS; not harmonised in v0.1", "PRESCRIPTIONS; not harmonised in v0.1",
               "SURGERY_INFO / SURGERY_VITAL_SIGNS; not harmonised in v0.1")))
  ds$admission <- finalize_admission(ds$admission, ds$icu_stay)
  ds
}
