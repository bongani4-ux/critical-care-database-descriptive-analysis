# =============================================================================
# eICU-CRD v2.0 adapter
#
# Identifier structure (verified against patient.csv):
#   uniquepid (patient) > patienthealthsystemstayid (hospital stay) > patientunitstayid (unit stay)
# HARMONISED UNITS: admission = hospital stay (166,355); ICU stay = unit stay
# (200,859, includes step-down/transfer unit stays as recorded by eICU; see unit_type);
# patient = uniquepid (139,367). All times are minutes offset from each UNIT stay's
# admission, so everything is re-based to the HOSPITAL admission clock using
# hospitaladmitoffset before windows are applied.
# =============================================================================

adapter_meta <- list(
  db_id = "eicu_crd",
  required_files = c("patient.csv", "diagnosis.csv", "treatment.csv", "apachePatientResult.csv",
                     "lab.csv", "vitalPeriodic.csv", "vitalAperiodic.csv"))

adapter_build <- function(cfg) {
  flow <- flow_new()
  rd <- function(f, ...) data.table::fread(db_file("eicu_crd", f), showProgress = FALSE, ...)

  # ---- unit stays -> hospital stays ------------------------------------------------------------------
  p <- rd("patient.csv", select = c("patientunitstayid", "patienthealthsystemstayid", "uniquepid", "gender", "age",
                                    "hospitaladmitoffset", "hospitaladmitsource", "hospitaldischargeoffset",
                                    "hospitaldischargeyear", "hospitaldischargestatus", "hospitaldischargelocation",
                                    "unittype", "unitstaytype", "unitdischargeoffset", "unitdischargestatus"),
          colClasses = list(character = c("patientunitstayid", "patienthealthsystemstayid", "uniquepid", "age")))
  assert_unique(p, "patientunitstayid", "eICU patient")
  assert_no_missing(p, c("patientunitstayid", "patienthealthsystemstayid", "uniquepid"), "eICU patient")
  flow <- flow_add(flow, "Unit stays in patient.csv", n_admissions = data.table::uniqueN(p$patienthealthsystemstayid),
                   n_patients = data.table::uniqueN(p$uniquepid), n_icu_stays = nrow(p),
                   note = "unit stay = ICU stay (incl. step-down/transfer unit stays); hospital stay = admission")
  p[, hao := as.numeric(hospitaladmitoffset)]
  # first unit stay of each hospital stay = earliest unit admission = largest hospitaladmitoffset
  data.table::setorder(p, patienthealthsystemstayid, -hao, patientunitstayid)
  p[, stay_seq := seq_len(.N), by = patienthealthsystemstayid]
  first <- p[stay_seq == 1L]

  sex_h <- harmonize_sex(first$gender)
  age_raw <- first$age
  age_num <- data.table::fcase(age_raw == "> 89", 90, grepl("^[0-9]+$", age_raw), suppressWarnings(as.numeric(age_raw)),
                               default = NA_real_)   # ages >89 are de-identified; treated as 90 (as in the review)
  adm <- first[, .(db_id = "eicu_crd", patient_id = uniquepid, admission_id = patienthealthsystemstayid,
                   age_years = age_num, sex = sex_h,
                   hosp_los_days = (as.numeric(hospitaldischargeoffset) - hao) / 1440,
                   hosp_death = data.table::fcase(hospitaldischargestatus == "Expired", 1L,
                                                  hospitaldischargestatus == "Alive", 0L, default = NA_integer_),
                   admit_sort_key = as.numeric(hospitaldischargeyear) * 1e9 + as.numeric(patienthealthsystemstayid),
                   admission_urgency = NA_character_,           # eICU records the admission SOURCE, not urgency
                   admission_source = hospitaladmitsource,
                   discharge_disposition = data.table::fcase(
                     hospitaldischargelocation %in% c("Home"), "home",
                     hospitaldischargelocation == "Death", "death",
                     hospitaldischargelocation %in% c("Skilled Nursing Facility", "Nursing Home", "Rehabilitation",
                                                      "Other External", "Other Hospital", "Other Internal"), "facility",
                     !is.na(hospitaldischargelocation) & nzchar(hospitaldischargelocation), "other",
                     default = NA_character_),
                   period = hospitaldischargeyear)]
  icu <- p[, .(db_id = "eicu_crd", patient_id = uniquepid, admission_id = patienthealthsystemstayid,
               stay_id = patientunitstayid, stay_seq, icu_los_days = as.numeric(unitdischargeoffset) / 1440,
               icu_unit = unittype,
               icu_death = data.table::fcase(unitdischargestatus == "Expired", 1L, unitdischargestatus == "Alive", 0L,
                                             default = NA_integer_))]
  stay_map <- p[, .(stay_id = patientunitstayid, admission_id = patienthealthsystemstayid, hao)]

  # ---- diagnoses: the icd9code field holds ICD-9 and/or ICD-10-CM codes, comma separated -----------------
  dg <- rd("diagnosis.csv", select = c("patientunitstayid", "icd9code"), colClasses = list(character = c("patientunitstayid", "icd9code")))
  dg <- dg[!is.na(icd9code) & nzchar(icd9code)]
  dg <- merge(dg, stay_map[, .(patientunitstayid = stay_id, admission_id)], by = "patientunitstayid")
  dg <- dg[, .(code_raw = trimws(unlist(strsplit(icd9code, ",", fixed = TRUE)))), by = admission_id]
  # classify on the DOTTED form: ICD-9 numeric 'NNN.x' ; ICD-10-CM 'A99.x'. ICD-9 V-codes and E-codes are
  # ignored: an ICD-9 E-code such as E878.0 would otherwise be misread as ICD-10 'E87' (electrolyte disorders).
  dg[, code_system := data.table::fcase(
    grepl("^[0-9]{3}(\\.[0-9]+)?$", code_raw), "ICD9",
    grepl("^[A-UW-Z][0-9]{2}(\\.[A-Za-z0-9]+)?$", code_raw), "ICD10",
    default = NA_character_)]
  diagnosis <- unique(dg[!is.na(code_system), .(admission_id, code = code_raw, code_system)])

  # ---- severity: APACHE IVa score of the first unit stay ----------------------------------------------------
  ap <- rd("apachePatientResult.csv", select = c("patientunitstayid", "apacheversion", "apachescore"),
           colClasses = list(character = c("patientunitstayid", "apacheversion")))
  ap <- ap[apacheversion == "IVa" & !is.na(apachescore) & apachescore > 0]
  ap <- merge(ap, stay_map, by.x = "patientunitstayid", by.y = "stay_id")
  ap <- merge(ap, p[, .(patientunitstayid, stay_seq)], by = "patientunitstayid")
  ap <- ap[stay_seq == 1L]
  severity <- ap[, .(admission_id, score = "APACHE IVa score (first unit stay)", value = as.numeric(apachescore))]

  # ---- organ support from the treatment table ----------------------------------------------------------------------
  tr <- rd("treatment.csv", select = c("patientunitstayid", "treatmentstring"), colClasses = list(character = c("patientunitstayid", "treatmentstring")))
  tr[, ts := tolower(treatmentstring)]
  flag <- function(rx, excl = NA_character_) {
    sel <- grepl(rx, tr$ts)
    if (!is.na(excl)) sel <- sel & !grepl(excl, tr$ts)
    h <- unique(tr$patientunitstayid[sel])
    unique(stay_map[stay_id %in% h, admission_id])
  }
  support <- data.table::rbindlist(list(
    data.table::data.table(admission_id = flag("mechanical ventilation", "non-invasive"), support_type = "mech_vent", value = 1L),
    data.table::data.table(admission_id = flag("\\|dialysis\\|(hemodialysis|c v v h|peritoneal dialysis|sled|ultrafiltration)"), support_type = "rrt", value = 1L),
    data.table::data.table(admission_id = flag("\\|vasopressors"), support_type = "vasopressor", value = 1L)))
  rm(tr)

  # ---- measurements: first value within the window of FIRST ICU admission ----------------------------------------------------
  mp <- data.table::fread(ccdb_path("databases", "eicu_crd", "mapping_measurements.csv"), encoding = "UTF-8")
  win <- cfg$measurements$window_hours; pre <- cfg$measurements$pre_index_hours
  index <- first[, .(unit_key = patienthealthsystemstayid, index_hours = -hao / 60)]
  hao_by_stay <- stay_map[, .(patientunitstayid = stay_id, unit_key = admission_id, hao)]
  to_hours <- function(ch, off_col) {   # re-base unit-stay offsets (min) to the hospital clock (hours)
    ch <- merge(ch, hao_by_stay, by = "patientunitstayid", sort = FALSE)
    ch[, time_hours := (get(off_col) - hao) / 60]
    ch
  }
  vit_chunk <- function(src, cols) function(ch) {
    ch <- ch[observationoffset <= 1440]                          # safe pre-filter (see header comment of derivation)
    if (!nrow(ch)) return(NULL)
    long <- data.table::melt(ch, id.vars = c("patientunitstayid", "observationoffset"), measure.vars = cols,
                             variable.name = "item", value.name = "value", na.rm = TRUE, variable.factor = FALSE)
    if (!nrow(long)) return(NULL)
    long <- to_hours(long, "observationoffset")
    m <- mp[source == src, .(item, analyte, source_unit)]
    reduce_chunk_first_in_window(long[, .(unit_key, item, time_hours, value, unit = NA_character_)], m, index, win, pre)
  }
  red <- list()
  vp_cols <- mp[source == "vitalperiodic", item]
  red[[1]] <- stream_file(db_file("eicu_crd", "vitalPeriodic.csv"), vit_chunk("vitalperiodic", vp_cols),
                          col_types = do.call(readr::cols_only, c(list(patientunitstayid = "c", observationoffset = "d"),
                                                                  stats::setNames(rep(list("d"), length(vp_cols)), vp_cols))),
                          label = "eICU vitalPeriodic",
                          arrow_filter = function(d) dplyr::filter(d, observationoffset <= 1440))
  va_cols <- mp[source == "vitalaperiodic", item]
  red[[2]] <- stream_file(db_file("eicu_crd", "vitalAperiodic.csv"), vit_chunk("vitalaperiodic", va_cols),
                          col_types = do.call(readr::cols_only, c(list(patientunitstayid = "c", observationoffset = "d"),
                                                                  stats::setNames(rep(list("d"), length(va_cols)), va_cols))),
                          label = "eICU vitalAperiodic",
                          arrow_filter = function(d) dplyr::filter(d, observationoffset <= 1440))
  lm <- mp[source == "lab", .(item, analyte, source_unit)]
  lab_items <- lm$item
  red[[3]] <- stream_file(db_file("eicu_crd", "lab.csv"), function(ch) {
    ch <- ch[labname %in% lm$item & labresultoffset <= 1440]
    if (!nrow(ch)) return(NULL)
    ch <- to_hours(ch, "labresultoffset")
    reduce_chunk_first_in_window(ch[, .(unit_key, item = labname, time_hours, value = labresult, unit = labmeasurenamesystem)],
                                 lm, index, win, pre)
  }, col_types = readr::cols_only(patientunitstayid = "c", labresultoffset = "d", labname = "c", labresult = "d",
                                  labmeasurenamesystem = "c"), label = "eICU lab",
  arrow_filter = function(d) dplyr::filter(d, labname %in% lab_items & labresultoffset <= 1440))
  meas <- combine_first_in_window(data.table::rbindlist(red, use.names = TRUE, fill = TRUE))
  measurements <- meas[, .(admission_id = unit_key, stay_id = NA_character_, analyte, value, hours_from_index, n_in_window)]

  flow <- flow_add(flow, "Final cohort (hospital stays)", admission = adm, icu_stay = icu)
  ds <- list(
    meta = list(
      index_definition = "first unit-stay admission within the hospital stay",
      measurement_index = "first_icu_admission",
      measurement_analytes_available = unique(measurements$analyte),
      support_available = c("mech_vent", "rrt", "vasopressor"), support_scope = "icu",
      support_definition = list(
        mech_vent = "treatment table entry containing 'mechanical ventilation' (non-invasive ventilation entries excluded)",
        rrt = "treatment table entry for hemodialysis / CVVH(D)(F) / peritoneal dialysis / SLED / ultrafiltration (catheter insertion excluded)",
        vasopressor = "treatment table entry containing '|vasopressors'"),
      hosp_death_definition = "patient.hospitaldischargestatus == 'Expired' (blank = missing)",
      hosp_los_definition = "(hospitaldischargeoffset - hospitaladmitoffset) / 1440 of the first unit stay",
      icu_los_definition = "sum over unit stays of unitdischargeoffset / 1440 (step-down/transfer unit stays included)",
      icu_death_definition = "unitdischargestatus == 'Expired' (per unit stay)",
      age_note = "ages > 89 are de-identified and set to 90",
      comorbidity_note = "ICD-9 / ICD-10-CM codes parsed from diagnosis.icd9code; present for a subset of diagnosis rows only",
      icu_by_construction = TRUE,
      surgery_note = ""),
    flow = flow, admission = adm, icu_stay = icu, diagnosis = diagnosis,
    direct_flags = data.table::data.table(admission_id = character(), comorbidity = character(), value = integer()),
    measurements = measurements, support = support, severity = severity,
    availability = data.table::data.table(
      domain = c("Demographics", "Hospital mortality", "ICU stay structure", "ICU mortality", "Comorbidities (coded)",
                 "Vital signs", "Laboratory", "Organ support", "Severity scores", "Microbiology", "Medication", "Surgery/anaesthesia"),
      status = c("available", "available", "available", "available", "partial", "available", "available", "available",
                 "available", "available", "available", "unavailable"),
      note = c("age top-coded at 90", "hospitaldischargestatus (1,751 blank)", "unit stays incl. step-down",
               "unitdischargestatus", "icd9code populated for a subset of diagnoses; pastHistory free-text paths not harmonised",
               "vitalPeriodic/vitalAperiodic", "lab", "treatment table (documented, not validated against delivery)",
               "APACHE IVa", "microLab; not harmonised in v0.1", "medication/infusionDrug; not harmonised in v0.1",
               "no anaesthesia data")))
  ds$admission <- finalize_admission(ds$admission, ds$icu_stay)
  ds
}
