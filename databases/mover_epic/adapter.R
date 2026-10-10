# =============================================================================
# MOVER-EPIC v1.0 adapter (perioperative; UCI Health). Source: EPIC_EMR.tar.gz, unpacked (selected
# tables only) into the cache folder outside the repository.
#
# Identifier structure (verified): patient_information has 65,728 rows = surgical RECORDS, with
# 64,354 distinct LOG_ID and 39,685 distinct MRN (patients). The review's N = 65,728 'patients' is the
# record count. Here: patient = MRN; admission = (MRN, HOSP_ADMSN_TIME) = 52,389 hospital admissions.
#
# LIMITATIONS: patient_coding (ICD-10-CM / ICD-9-CM) has an MRN key but no encounter key, so codes are
# attached to every admission of the patient (patient-level history, not encounter-specific).
# No ICU times/stay table (only ICU_ADMIN_FLAG), no vital signs table in EPIC_EMR.
# =============================================================================

adapter_meta <- list(
  db_id = "mover_epic",
  required_files = c("EPIC_EMR.tar(2).gz"))

MOVER_EPIC_MEMBERS <- c("patient_information.csv", "patient_coding.csv", "patient_labs.csv")

adapter_build <- function(cfg) {
  flow <- flow_new()
  dest <- ccdb_cache_dir("mover_epic")
  untar_cached(db_file("mover_epic", "EPIC_EMR.tar(2).gz"), dest, marker = file.path("EPIC_EMR", "EMR", "patient_labs.csv"),
               members = paste0("EPIC_EMR/EMR/", MOVER_EPIC_MEMBERS))
  emr <- file.path(dest, "EPIC_EMR", "EMR")
  tm <- function(x) as.POSIXct(x, tz = "UTC", format = "%m/%d/%y %H:%M")

  p <- data.table::fread(file.path(emr, "patient_information.csv"), colClasses = "character", showProgress = FALSE, encoding = "UTF-8")
  assert_no_missing(p, c("MRN"), "MOVER-EPIC patient_information")
  p[, `:=`(admit_t = tm(HOSP_ADMSN_TIME), disch_t = tm(HOSP_DISCH_TIME))]
  p[, adm_key := paste(MRN, HOSP_ADMSN_TIME, sep = "|")]
  disp_group <- function(x) data.table::fcase(
    grepl("^Home", x), "home", x == "Expired", "death", x %in% c("Coroner"), "death",
    x == "Against Medical Advice", "other", is.na(x) | !nzchar(x), NA_character_, default = "facility")
  asa_num <- c("Healthy" = 1, "Mild Systemic Disease" = 2, "Severe Systemic Disease" = 3, "Incapacitating Disease" = 4,
               "Moribund" = 5, "Brain Dead" = 6)
  records <- list(n_surgical_records = nrow(p),
                  hosp_death_pct_records = 100 * mean(p$DISCH_DISP == "Expired", na.rm = TRUE),
                  hosp_los_median_records = stats::median(as.numeric(p$LOS), na.rm = TRUE))
  h <- p[, .(patient_id = MRN[1], age_years = suppressWarnings(as.numeric(BIRTH_DATE[1])), sex = SEX[1],
             adm = min(admit_t), dis = max(disch_t), death = any(DISCH_DISP %in% c("Expired", "Coroner")),
             disp = DISCH_DISP[which.max(as.numeric(disch_t))], icu = any(ICU_ADMIN_FLAG == "Yes"),
             cls = PATIENT_CLASS_GROUP[1], asa = suppressWarnings(max(asa_num[ASA_RATING], na.rm = TRUE))), by = adm_key]
  h[is.infinite(asa), asa := NA_real_]
  adm <- h[, .(db_id = "mover_epic", patient_id, admission_id = adm_key, age_years, sex = harmonize_sex(sex),
               hosp_los_days = as.numeric(difftime(dis, adm, units = "days")), hosp_death = as.integer(death),
               admit_sort_key = as.numeric(adm), admission_urgency = NA_character_, admission_source = cls,
               discharge_disposition = disp_group(disp), period = format(adm, "%Y"), surgery_flag = 1L)]
  flow <- flow_add(flow, "Surgical records -> hospital admissions", admission = adm,
                   note = sprintf("%d surgical records; %d distinct LOG_ID", nrow(p), data.table::uniqueN(p$LOG_ID)))
  icu <- h[icu == TRUE, .(db_id = "mover_epic", patient_id, admission_id = adm_key, stay_id = paste0(adm_key, "_ICU1"), stay_seq = 1L,
                          icu_los_days = NA_real_, icu_unit = NA_character_, icu_death = NA_integer_)]
  severity <- h[!is.na(asa), .(admission_id = adm_key, score = "ASA physical status (max of the admission's records)", value = asa)]

  # ---- diagnoses (MRN-level) -------------------------------------------------------------------------------------------------
  cod <- data.table::fread(file.path(emr, "patient_coding.csv"), select = c("MRN", "REF_BILL_CODE_SET_NAME", "REF_BILL_CODE"),
                           colClasses = "character", showProgress = FALSE, encoding = "UTF-8")
  cod <- unique(cod[REF_BILL_CODE_SET_NAME %in% c("ICD-10-CM", "ICD-9-CM") & !is.na(REF_BILL_CODE),
                    .(MRN, code = REF_BILL_CODE, code_system = data.table::fifelse(REF_BILL_CODE_SET_NAME == "ICD-9-CM", "ICD9", "ICD10"))])
  diagnosis <- merge(h[, .(MRN = patient_id, admission_id = adm_key)], cod, by = "MRN", allow.cartesian = TRUE)[, .(admission_id, code, code_system)]

  # ---- laboratory results, first 24 h of hospital admission ------------------------------------------------------------------------
  lm <- read_mapping("mover_epic", "mapping_labs.csv")
  win <- cfg$measurements$window_hours; pre <- cfg$measurements$pre_index_hours
  h[, `:=`(lo = as.numeric(adm) / 3600 - pre, hi = as.numeric(adm) / 3600 + win)]
  wtab <- h[, .(MRN = patient_id, admission_id = adm_key, lo, hi, adm_h = as.numeric(adm) / 3600)]
  index <- h[, .(unit_key = adm_key, index_hours = as.numeric(adm) / 3600)]
  mm <- lm[, .(item, analyte, source_unit)]; codes <- mm$item
  lb <- stream_file(file.path(emr, "patient_labs.csv"), function(ch) {
    ch <- ch[`Lab Code` %in% codes & !is.na(MRN)]
    if (!nrow(ch)) return(NULL)
    ch[, `:=`(th = fast_ts_hours(`Collection Datetime`), v = suppressWarnings(as.numeric(`Observation Value`)))]
    ch[v == 9999999, v := NA_real_]
    j <- wtab[ch, on = .(MRN, lo <= th, hi >= th), nomatch = 0L,
              .(unit_key = admission_id, item = `Lab Code`, time_hours = th, value = v, unit = `Measurement Units`)]
    if (!nrow(j)) return(NULL)
    reduce_chunk_first_in_window(j, mm, index, win, pre)
  }, col_types = readr::cols_only(MRN = "c", `Lab Code` = "c", `Observation Value` = "c", `Measurement Units` = "c", `Collection Datetime` = "c"),
  label = "MOVER-EPIC patient_labs", arrow_filter = function(d) dplyr::filter(d, `Lab Code` %in% codes))
  meas <- combine_first_in_window(lb)
  measurements <- meas[, .(admission_id = unit_key, stay_id = NA_character_, analyte, value, hours_from_index, n_in_window)]

  flow <- flow_add(flow, "Final cohort", admission = adm, icu_stay = icu)
  ds <- list(
    meta = list(
      index_definition = "hospital admission (HOSP_ADMSN_TIME)", measurement_index = "hospital_admission",
      measurement_analytes_available = unique(measurements$analyte), support_available = character(), support_scope = "hospital",
      support_unavailable_note = "no ventilation / dialysis / vasopressor records in the EPIC_EMR tables used",
      hosp_death_definition = "DISCH_DISP in {Expired, Coroner} on any record of the admission",
      hosp_los_definition = "latest HOSP_DISCH_TIME - HOSP_ADMSN_TIME (days)",
      icu_los_definition = "NOT RECORDED (ICU_ADMIN_FLAG only)", icu_death_definition = NA_character_,
      surgery_note = "all records are surgical by construction",
      age_note = "age in years at surgery (column BIRTH_DATE holds the age; top-coded 90)",
      comorbidity_note = "ICD-10-CM / ICD-9-CM from patient_coding attached at patient (MRN) level - NOT encounter-specific",
      extra_metrics = records, icu_by_construction = FALSE),
    flow = flow, admission = adm, icu_stay = icu, diagnosis = diagnosis,
    direct_flags = data.table::data.table(admission_id = character(), comorbidity = character(), value = integer()),
    measurements = measurements, support = empty_support(), severity = severity,
    availability = data.table::data.table(
      domain = c("Demographics", "Hospital mortality", "ICU stay structure", "ICU mortality", "Comorbidities (coded)",
                 "Vital signs", "Laboratory", "Organ support", "Severity scores", "Microbiology", "Medication", "Surgery/anaesthesia"),
      status = c("available", "available", "partial", "unavailable", "partial", "unavailable", "available", "unavailable", "partial",
                 "unavailable", "available", "available"),
      note = c("age, sex", "DISCH_DISP", "ICU flag only (no times)", "none", "patient-level codes, not encounter-specific",
               "no vitals table in EPIC_EMR (vitals exist only in MOVER-SIS)", "patient_labs (LOINC)", "none", "ASA physical status",
               "none", "patient_medications; not harmonised in v0.1", "patient_procedure events, anaesthesia type")))
  ds$admission <- finalize_admission(ds$admission, ds$icu_stay)
  ds
}
