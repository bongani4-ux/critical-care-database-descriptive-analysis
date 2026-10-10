# =============================================================================
# Jinhua adapter - REFERENCE database (not part of the Critical Care Database Review)
#
# An independent re-implementation of the cohort, ICU-episode, comorbidity and
# organ-support logic in the original scripts (jinhua database/code/02_*.R,
# 03_*.R), written against the harmonised dataset contract. The original scripts
# are NOT modified; their saved outputs are the comparison target
# (compare_jinhua_reference() in R/13_quality_checks.R).
#
# Unit of analysis: hospital admission (hadm_id). ICU episodes are reconstructed
# from transfer.csv because the database has no ICU-stay table.
# See databases/jinhua/NOTES.md for the traps found while profiling the source.
# =============================================================================

adapter_meta <- list(
  db_id = "jinhua",
  required_files = c("medical_record_front_page.csv", "transfer.csv", "diagnosis.csv",
                     "surgical_record_front_page.csv", "basic_info_operation_anesthesia.csv",
                     "operation.csv", "vital_signs.csv", "laboratory_test.csv"))

JINHUA_ICU_DEPARTMENTS <- c("Intensive Care Unit", "Emergency intensive care unit",
                            "Emergency room intensive care", "Neonatal Intensive Care Unit")
JINHUA_NA <- c("", "NA", "NaN", "NULL", "-")          # whitespace-only cells are already NA (strip.white)

# Organ-support / procedure patterns on surgery_name_norm_en (as in the reference)
JINHUA_SUPPORT <- list(
  mech_vent    = "ventilat",
  rrt          = "hemodialysis|haemodialysis|peritoneal dialysis|hemoperfusion|hemofiltration|artificial liver",
  intubation   = "endotracheal intubation|tracheal intubation",
  tracheostomy = "tracheostom|tracheotom")

jh_num <- function(x) suppressWarnings(as.numeric(x))

jh_read <- function(name) {
  f <- db_file("jinhua", paste0(name, ".csv"))
  dt <- data.table::fread(f, colClasses = "character", encoding = "UTF-8",
                          na.strings = JINHUA_NA, showProgress = FALSE)
  data.table::setnames(dt, sub("^﻿", "", names(dt)))
  # TRAP 4: trailing commas create unnamed / V<n> all-empty columns
  bad <- names(dt)[names(dt) == "" | grepl("^V[0-9]+$", names(dt))]
  bad <- bad[vapply(bad, function(cn) all(is.na(dt[[cn]])), logical(1))]
  if (length(bad)) dt[, (bad) := NULL]
  dt
}

# Map a lower-cased lab sub-project name + specimen to a harmonised analyte.
# Urine, CSF, effusions, 24 h collections and the CRRT "post filter" circuit are
# excluded by construction (blood specimens only).
JINHUA_LAB_PATTERNS <- c(
  creatinine      = "^creatinine \\(crea\\) ?- ?(unknown|arterial blood|venous blood)",
  hemoglobin      = "^hemoglobin \\(hb\\) ?-",
  wbc             = "^white blood cell count \\(wbc#\\) ?-",
  platelets       = "^platelet count \\(plt#\\) ?-",
  sodium          = "^sodium ions? \\(na\\+\\) ?- ?(unknown|arterial blood)",
  potassium       = "^potassium ions? \\(k\\+\\) ?- ?(unknown|arterial blood)",
  lactate         = "^lactate ?- ?arterial blood",
  bilirubin_total = "^total bilirubin \\(tbil\\)",
  glucose         = "^glucose \\(glu\\) ?- ?(unknown|arterial blood|venous blood)",
  albumin         = "^albumin \\(alb\\) ?- ?(unknown|arterial blood|venous blood)",
  bicarbonate     = "^actual bicarbonate \\(ab\\)")
JINHUA_LAB_SPECIMENS <- c("serum", "plasma", "whole blood", "arterial blood",
                          "central arterial blood", "venous blood")
# modal unit per analyte in this database, used ONLY when a row has no unit
JINHUA_LAB_DEFAULT_UNIT <- c(creatinine = "umol/L", hemoglobin = "g/L", wbc = "10^9/L",
                             platelets = "10^9/L", sodium = "mmol/L", potassium = "mmol/L",
                             lactate = "mmol/L", bilirubin_total = "umol/L", glucose = "mmol/L",
                             albumin = "g/L", bicarbonate = "mmol/L")

jh_lab_analyte <- function(name_lower) {
  un <- unique(name_lower)
  key <- vapply(un, function(s) {
    if (is.na(s)) return(NA_character_)
    for (a in names(JINHUA_LAB_PATTERNS)) if (grepl(JINHUA_LAB_PATTERNS[[a]], s)) return(a)
    NA_character_
  }, character(1))
  unname(key[match(name_lower, un)])
}

adapter_build <- function(cfg) {
  flow <- flow_new()

  # ---- admissions ----------------------------------------------------------------------
  fp <- jh_read("medical_record_front_page")
  assert_unique(fp, "hadm_id", "Jinhua front page")
  assert_no_missing(fp, c("subject_id", "hadm_id"), "Jinhua front page")
  flow <- flow_add(flow, "Front-page rows (hospital admissions)", admission = data.table::data.table(
    admission_id = fp$hadm_id, patient_id = fp$subject_id), note = "all admissions retained; ICU and surgery are flags, not filters")

  DISCHARGE_MAP <- c("Doctor's order to leave the hospital" = "home",
                     "Die" = "death",
                     "Leaving the hospital without medical advice" = "other",
                     "Doctor's order to transfer hospital" = "facility",
                     "Transfer medical orders to community health service institutions/township health centers" = "facility",
                     "Other" = "other")
  adm <- fp[, .(
    db_id = "jinhua", patient_id = subject_id, admission_id = hadm_id,
    age_years = jh_num(age), sex = harmonize_sex(patient_gender_en),
    hosp_los_days = jh_num(dischtime_base) / 1440,                       # TRAP 2: *_base = minutes from admission
    hosp_death = data.table::fifelse(discharge_type_en == "Die", 1L, 0L),  # TRAP 1: never expire_flag
    admit_sort_key = jh_num(admitted_rank),
    admission_urgency = data.table::fcase(admission_route_en == "Emergency", "emergency",
                                          !is.na(admission_route_en), "other"),
    admission_source = admission_route_en,
    discharge_disposition = unname(DISCHARGE_MAP[discharge_type_en]),
    period = year,                                                       # TRAP 9: 3-year interval, not a calendar year
    admission_department = admission_department_en,
    dischtime_min = jh_num(dischtime_base))]

  # ---- ICU episodes reconstructed from transfer.csv ---------------------------------------
  tr <- jh_read("transfer")
  tf <- tr[, .(admission_id = hadm_id,
               T_IN  = data.table::fcoalesce(jh_num(intime_base), jh_num(outtime_base)),
               T_OUT = jh_num(outtime_base), FROM = out_department_en, TO = transfer_department_en)]
  data.table::setorder(tf, admission_id, T_OUT)
  tf[, ROW_I := seq_len(.N), by = admission_id]
  icu_in  <- tf[TO   %in% JINHUA_ICU_DEPARTMENTS, .(admission_id, ROW_I, ICU_IN = T_IN)]
  icu_out <- tf[FROM %in% JINHUA_ICU_DEPARTMENTS, .(admission_id, ROW_I, ICU_OUT = T_OUT)]
  if (nrow(icu_in) && nrow(icu_out)) {
    # +0.5 makes the match strictly later, so an ICU-to-ICU move cannot pair with itself
    icu_in[,  ROW_KEY := ROW_I + 0.5]; icu_out[, ROW_KEY := as.numeric(ROW_I)]
    data.table::setkey(icu_out, admission_id, ROW_KEY); data.table::setkey(icu_in, admission_id, ROW_KEY)
    episodes <- icu_out[icu_in, roll = -Inf, .(admission_id, ICU_IN = i.ICU_IN, ICU_OUT)]
  } else episodes <- data.table::data.table(admission_id = character(), ICU_IN = numeric(), ICU_OUT = numeric())
  # admissions that BEGIN in an ICU never generate a transfer-in row
  start_icu <- fp[admission_department_en %in% JINHUA_ICU_DEPARTMENTS, .(admission_id = hadm_id)]
  first_out <- tf[FROM %in% JINHUA_ICU_DEPARTMENTS, .(ICU_OUT = min(T_OUT, na.rm = TRUE)), by = admission_id]
  start_icu <- merge(start_icu, first_out, by = "admission_id", all.x = TRUE)
  start_icu[, ICU_IN := 0]
  episodes <- unique(rbind(episodes, start_icu[, .(admission_id, ICU_IN, ICU_OUT)]), by = c("admission_id", "ICU_IN"))
  episodes <- merge(episodes, adm[, .(admission_id, patient_id, dischtime_min)], by = "admission_id", all.x = TRUE)
  episodes[is.na(ICU_OUT), ICU_OUT := dischtime_min]                     # open ICU stay ends at discharge
  episodes[, icu_los_days := (ICU_OUT - ICU_IN) / 1440]
  episodes <- episodes[is.na(icu_los_days) | icu_los_days >= 0]
  data.table::setorder(episodes, admission_id, ICU_IN)
  episodes[, stay_seq := seq_len(.N), by = admission_id]
  icu <- episodes[, .(db_id = "jinhua", patient_id, admission_id,
                      stay_id = paste0(admission_id, "_ICU", stay_seq), stay_seq, icu_los_days,
                      icu_unit = NA_character_, icu_death = NA_integer_)]
  # index time (minutes from admission) for the first ICU entry: used by the QC/tests only
  adm[, dischtime_min := NULL]

  # ---- surgery flag (extension beyond the reference tables) --------------------------------
  bo <- jh_read("basic_info_operation_anesthesia"); op <- jh_read("operation")
  surg_ids <- unique(c(bo[!is.na(surgery_name) | !is.na(starttime_base), hadm_id], op[!is.na(surgery_name), hadm_id]))
  adm[, surgery_flag := as.integer(admission_id %in% surg_ids)]

  # ---- organ support from procedure records (TRAP 7: a row is not proof of surgery) -------------
  sf <- jh_read("surgical_record_front_page")
  pn <- sf[!is.na(surgery_name_norm_en), .(admission_id = hadm_id, P = surgery_name_norm_en)]
  support <- data.table::rbindlist(lapply(names(JINHUA_SUPPORT), function(ty) {
    hit <- unique(pn[grepl(JINHUA_SUPPORT[[ty]], P, ignore.case = TRUE), admission_id])
    data.table::data.table(admission_id = hit, support_type = ty, value = 1L)
  }))

  # ---- diagnoses (ICD-10, pooled from diagnosis.icd10_code and front-page codes) -------------------
  dg <- jh_read("diagnosis")
  codes <- data.table::rbindlist(list(
    dg[!is.na(icd10_code), .(admission_id = hadm_id, code = icd10_code)],
    fp[!is.na(discharge_diagnosis_code), .(admission_id = hadm_id, code = discharge_diagnosis_code)]))
  codes <- codes[, .(code = unlist(strsplit(code, ";", fixed = TRUE))), by = admission_id]
  codes[, code := toupper(trimws(code))]
  codes <- unique(codes[grepl("^[A-Z][0-9]", code)])
  diagnosis <- codes[, .(admission_id, code, code_system = "ICD10")]

  # ---- measurements: first value within the window of hospital admission -----------------------------
  win <- cfg$measurements$window_hours; pre <- cfg$measurements$pre_index_hours
  index <- data.table::data.table(unit_key = adm$admission_id, index_hours = 0)

  # vitals (charted): item map
  vmap <- data.table::data.table(
    item = c("temperature", "pulse", "respiratory", "sbp", "dbp", "spo2"),
    analyte = c("temp", "hr", "rr", "sbp", "dbp", "spo2"),
    source_unit = NA_character_)
  red <- list()
  vt <- jh_read("vital_signs")
  red[[1]] <- reduce_chunk_first_in_window(
    vt[, .(unit_key = hadm_id, item = tolower(subcategory_name_en), time_hours = jh_num(charttime_base) / 60,
           value = jh_num(value), unit = subcategory_unit)],
    vmap, index, win, pre, assume_canonical = "spo2")        # SpO2 carries no unit in this database
  rm(vt)

  # labs (2 GB): stream in chunks; blood specimens only
  lmap <- data.table::data.table(item = names(JINHUA_LAB_DEFAULT_UNIT), analyte = names(JINHUA_LAB_DEFAULT_UNIT),
                                 source_unit = unname(JINHUA_LAB_DEFAULT_UNIT))
  lab_file <- db_file("jinhua", "laboratory_test.csv")
  ct <- readr::cols_only(hadm_id = "c", inspection_subproject_name_en = "c", test_results_quantitative = "c",
                         inspection_entity = "c", test_specimen_en = "c", test_specimen_time_base = "c",
                         report_time_base = "c")
  lab <- stream_file(lab_file, function(ch) {
    ch[, nm := tolower(trimws(inspection_subproject_name_en))]
    ch <- ch[tolower(trimws(test_specimen_en)) %in% JINHUA_LAB_SPECIMENS]
    if (!nrow(ch)) return(NULL)
    ch[, item := jh_lab_analyte(nm)]
    ch <- ch[!is.na(item)]
    if (!nrow(ch)) return(NULL)
    r <- reduce_chunk_first_in_window(
      ch[, .(unit_key = hadm_id, item, time_hours = data.table::fcoalesce(jh_num(test_specimen_time_base), jh_num(report_time_base)) / 60,
             value = jh_num(test_results_quantitative), unit = inspection_entity)],
      lmap, index, win, pre)
    r
  }, col_types = ct, label = "Jinhua laboratory_test")
  red[[2]] <- lab
  meas <- combine_first_in_window(data.table::rbindlist(red, use.names = TRUE, fill = TRUE))
  measurements <- meas[, .(admission_id = unit_key, stay_id = NA_character_, analyte, value, hours_from_index, n_in_window)]

  flow <- flow_add(flow, "Final cohort (all admissions)", admission = adm, icu_stay = icu)
  adm[, c("admission_department") := NULL]

  ds <- list(
    meta = list(
      db_id = "jinhua",
      index_definition = "hospital admission (t = 0); ICU entry reconstructed from transfer.csv",
      measurement_index = "hospital_admission",
      measurement_analytes_available = unique(measurements$analyte),
      support_available = names(JINHUA_SUPPORT), support_scope = "hospital",
      support_definition = list(
        mech_vent = "procedure-record name contains 'ventilat' (hospital-wide, incl. non-ICU)",
        rrt = "procedure-record name matches dialysis / haemofiltration / haemoperfusion / artificial liver",
        intubation = "procedure-record endotracheal intubation", tracheostomy = "procedure-record tracheostomy/tracheotomy"),
      support_unavailable_note = "no vasopressor ascertainment implemented (medication.csv 797 MB not processed in v0.1)",
      hosp_death_definition = "discharge_type_en == 'Die' (medical_record.expire_flag is patient-level and NOT used)",
      hosp_los_definition = "dischtime_base / 1440 (minutes from admission)",
      icu_los_definition = "sum of ICU episodes reconstructed from transfer.csv (no ICU-stay table exists)",
      icu_death_definition = NA_character_,
      surgery_note = "admission has >= 1 record in basic_info_operation_anesthesia or operation (named operation); extension - not in the reference tables",
      age_note = "integer years at admission",
      icu_by_construction = FALSE),
    flow = flow, admission = adm, icu_stay = icu, diagnosis = diagnosis,
    direct_flags = data.table::data.table(admission_id = character(), comorbidity = character(), value = integer()),
    measurements = measurements, support = support, severity = empty_severity(),
    availability = data.table::data.table(
      domain = c("Demographics", "Hospital mortality", "ICU stay structure", "ICU mortality", "Comorbidities (coded)",
                 "Vital signs", "Laboratory", "Organ support", "Severity scores", "Microbiology", "Medication", "Surgery/anaesthesia"),
      status = c("available", "available", "partial", "unavailable", "available", "partial", "available", "partial",
                 "unavailable", "available", "available", "available"),
      note = c("age, sex", "discharge disposition", "reconstructed from ward transfers; no ICU-stay table",
               "no ICU outcome field", "ICD-10 discharge/diagnosis codes (Chinese extension codes, normalised)",
               "9 charted items; ward charting, not ICU monitor data", "blood specimens; units from inspection_entity",
               "procedure-record based; vasopressors not implemented", "no native score",
               "culture/susceptibility present; not harmonised in v0.1", "present; not harmonised in v0.1",
               "intra-operative and ward; not harmonised in v0.1")))
  finalize_ds(ds)
}

# Local helper: complete the admission table with the shared derivation.
finalize_ds <- function(ds) {
  ds$admission <- finalize_admission(ds$admission, ds$icu_stay)
  ds
}
