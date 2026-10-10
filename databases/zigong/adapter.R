# =============================================================================
# Zigong (ZFPH) v1.1 - critical care database of patients with infection.
# Unit of analysis: hospital admission (INP_NO); exactly one admission per patient
# (2,790 admissions = 2,790 patients). All times are HOURS from hospital admission.
# ICU stays are reconstructed from dtTransfer: a maximal run of consecutive transfer
# rows in ICU-type departments (ICU, EICU, NICU, RICU, 'intensive care') is one stay.
# In-hospital death = dtICD.Status_Discharge == 'Dead' (matches the review: 161/2,790).
# =============================================================================

adapter_meta <- list(
  db_id = "zigong",
  required_files = c("dtBaseline.csv", "dtTransfer.csv", "dtICD.csv", "dtOutCome.csv", "dtLab.csv",
                     "dtNursingChart.csv", "dtDrugs.csv"))

ZIG_ICU_REGEX <- "ICU|intensive care"
ZIG_VASO <- "norepinephrine|dopamine|adrenaline|epinephrine|milrinone|dobutamine|levosimendan|deoxyepinephrine"

adapter_build <- function(cfg) {
  flow <- flow_new()
  rd <- function(f, ...) data.table::fread(db_file("zigong", f), showProgress = FALSE, ...)

  b <- rd("dtBaseline.csv", select = c("PATIENT_ID", "INP_NO", "Age", "SEX", "AdmitDept", "InfectionSite",
                                       "ICU_discharge_time", "DISCHARGE_DATE_TIME"),
          colClasses = list(character = c("PATIENT_ID", "INP_NO")))
  assert_unique(b, "INP_NO", "Zigong baseline"); assert_no_missing(b, c("PATIENT_ID", "INP_NO"), "Zigong baseline")
  ic <- rd("dtICD.csv", select = c("INP_NO", "ICD_Code", "Status_Discharge"), colClasses = list(character = c("INP_NO", "ICD_Code")))
  oc <- rd("dtOutCome.csv", select = c("PATIENT_ID", "Follow_Vital"), colClasses = list(character = "PATIENT_ID"))
  dead <- unique(ic[Status_Discharge == "Dead", INP_NO])
  has_status <- unique(ic[!is.na(Status_Discharge), INP_NO])
  b <- merge(b, oc, by = "PATIENT_ID", all.x = TRUE, sort = FALSE)
  adm <- b[, .(db_id = "zigong", patient_id = PATIENT_ID, admission_id = INP_NO,
               age_years = as.numeric(Age), sex = harmonize_sex(SEX),
               hosp_los_days = as.numeric(DISCHARGE_DATE_TIME) / 24,
               hosp_death = data.table::fcase(INP_NO %in% dead, 1L, INP_NO %in% has_status, 0L, default = NA_integer_),
               admit_sort_key = as.numeric(INP_NO), admission_urgency = NA_character_,
               admission_source = AdmitDept, discharge_disposition = NA_character_, period = NA_character_,
               death_any_followup = data.table::fcase(Follow_Vital == "Death", 1L, Follow_Vital == "Alive", 0L, default = NA_integer_))]
  flow <- flow_add(flow, "Admissions in dtBaseline", admission = adm)

  # ---- ICU stays from consecutive ICU-department transfer rows --------------------------------------------------
  t <- rd("dtTransfer.csv", select = c("INP_NO", "StartTime", "StopTime", "TransferDept"), colClasses = list(character = "INP_NO"))
  t[, icu := grepl(ZIG_ICU_REGEX, TransferDept, ignore.case = TRUE)]
  data.table::setorder(t, INP_NO, StartTime)
  t[, run := cumsum(c(TRUE, icu[-1] != icu[-.N] | INP_NO[-1] != INP_NO[-.N]))]
  ep <- t[icu == TRUE, .(ICU_in = min(StartTime), ICU_out = max(StopTime)), by = .(INP_NO, run)]
  data.table::setorder(ep, INP_NO, ICU_in)
  ep[, stay_seq := seq_len(.N), by = INP_NO]
  ep <- merge(ep, b[, .(INP_NO, PATIENT_ID)], by = "INP_NO")
  icu <- ep[, .(db_id = "zigong", patient_id = PATIENT_ID, admission_id = INP_NO, stay_id = paste0(INP_NO, "_ICU", stay_seq),
                stay_seq, icu_los_days = (ICU_out - ICU_in) / 24, icu_unit = NA_character_, icu_death = NA_integer_)]
  index <- ep[, .(index_hours = min(ICU_in)), by = .(unit_key = INP_NO)]

  # ---- diagnoses: Chinese-extended ICD-10 (ICD-O morphology codes such as M80700/3 are dropped) -----------------------
  dx <- unique(ic[grepl("^[A-Z][0-9]{2}", ICD_Code), .(admission_id = INP_NO, code = ICD_Code, code_system = "ICD10")])

  # ---- measurements --------------------------------------------------------------------------------------------------
  mp <- data.table::fread(ccdb_path("databases", "zigong", "mapping_measurements.csv"), colClasses = "character", encoding = "UTF-8")
  win <- cfg$measurements$window_hours; pre <- cfg$measurements$pre_index_hours
  lm <- mp[source == "lab", .(item, analyte, source_unit)]
  lb <- stream_file(db_file("zigong", "dtLab.csv"), function(ch) {
    ch <- ch[Item %in% lm$item]
    if (!nrow(ch)) return(NULL)
    reduce_chunk_first_in_window(ch[, .(unit_key = INP_NO, item = Item, time_hours = LabTime,
                                        value = suppressWarnings(as.numeric(LabValue)), unit = Unit)], lm, index, win, pre)
  }, col_types = readr::cols_only(INP_NO = "c", LabTime = "d", Item = "c", LabValue = "c", Unit = "c"), label = "Zigong dtLab")

  cm <- mp[source == "chart", .(item, analyte, source_unit)]
  chart_cols <- cm$item
  flags <- list()
  nc <- stream_file(db_file("zigong", "dtNursingChart.csv"), function(ch) {
    ch[, ChartTimeN := suppressWarnings(as.numeric(ChartTime))]
    # airway documentation -> support flags (hospital-wide; all Zigong patients are ICU patients)
    flags[[length(flags) + 1L]] <<- rbind(
      ch[!is.na(Endotracheal_intubation) & nzchar(Endotracheal_intubation) & !grepl("拔除", Endotracheal_intubation) |
           grepl("气插导管", Oxygen_inhalation_mode), .(INP_NO, type = "intubation")],
      ch[grepl("气切导管", Oxygen_inhalation_mode), .(INP_NO, type = "tracheostomy")])
    long <- data.table::melt(ch, id.vars = c("INP_NO", "ChartTimeN"), measure.vars = chart_cols, variable.name = "item",
                             value.name = "raw", variable.factor = FALSE)
    long[, value := suppressWarnings(as.numeric(raw))]
    long <- long[!is.na(value)]
    reduce_chunk_first_in_window(long[, .(unit_key = INP_NO, item, time_hours = ChartTimeN, value, unit = NA_character_)],
                                 cm, index, win, pre)
  }, col_types = do.call(readr::cols_only, c(
    list(INP_NO = "c", ChartTime = "c", Endotracheal_intubation = "c", Oxygen_inhalation_mode = "c"),
    stats::setNames(rep(list("c"), length(chart_cols)), chart_cols))), label = "Zigong dtNursingChart")
  meas <- combine_first_in_window(data.table::rbindlist(list(lb, nc), use.names = TRUE, fill = TRUE))
  measurements <- meas[, .(admission_id = unit_key, stay_id = NA_character_, analyte, value, hours_from_index, n_in_window)]

  # ---- organ support ------------------------------------------------------------------------------------------------------
  fl <- unique(data.table::rbindlist(flags))
  dr <- rd("dtDrugs.csv", select = c("PATIENT_ID", "DrugName", "Drug_time"), colClasses = list(character = "PATIENT_ID"))
  dr <- dr[grepl(ZIG_VASO, DrugName, ignore.case = TRUE)]
  dr <- merge(dr, b[, .(PATIENT_ID, INP_NO)], by = "PATIENT_ID")
  vaso <- dr[ep, on = .(INP_NO, Drug_time >= ICU_in, Drug_time <= ICU_out), nomatch = 0L, unique(INP_NO)]
  support <- data.table::rbindlist(list(
    data.table::data.table(admission_id = fl[type == "intubation", unique(INP_NO)], support_type = "intubation", value = 1L),
    data.table::data.table(admission_id = fl[type == "tracheostomy", unique(INP_NO)], support_type = "tracheostomy", value = 1L),
    data.table::data.table(admission_id = vaso, support_type = "vasopressor", value = 1L)), use.names = TRUE)

  flow <- flow_add(flow, "Final cohort (one admission per patient)", admission = adm, icu_stay = icu)
  ds <- list(
    meta = list(
      index_definition = "first ICU-type department transfer (hours from hospital admission)",
      measurement_index = "first_icu_admission", measurement_analytes_available = unique(measurements$analyte),
      support_available = c("vasopressor", "intubation", "tracheostomy"), support_scope = "icu",
      support_definition = list(
        vasopressor = "dtDrugs record of norepinephrine/dopamine/epinephrine/phenylephrine('deoxyepinephrine')/dobutamine/milrinone/levosimendan timed inside an ICU stay",
        intubation = "nursing-chart endotracheal-tube documentation (depth recorded) or oxygen mode 'endotracheal tube'",
        tracheostomy = "nursing-chart oxygen mode 'tracheal cannula'"),
      support_unavailable_note = "ventilator MODE is charted but invasive vs non-invasive ventilation cannot be separated, so mech_vent is not reported; haemodialysis is charted only as a catheter",
      hosp_death_definition = "dtICD.Status_Discharge == 'Dead' (any diagnosis row of the admission)",
      hosp_los_definition = "DISCHARGE_DATE_TIME / 24 (hours from admission)",
      icu_los_definition = "sum over reconstructed ICU stays of (stop - start) / 24",
      icu_death_definition = NA_character_,
      age_note = "integer years; 2 missing; maximum 120 retained as recorded",
      followup_note = "dtOutCome.Follow_Vital (Alive/Death; 553 missing); follow-up length variable",
      comorbidity_note = "Chinese-extended ICD-10 from dtICD (discharge diagnoses)",
      icu_by_construction = TRUE),
    flow = flow, admission = adm, icu_stay = icu, diagnosis = dx,
    direct_flags = data.table::data.table(admission_id = character(), comorbidity = character(), value = integer()),
    measurements = measurements, support = support, severity = empty_severity(),
    availability = data.table::data.table(
      domain = c("Demographics", "Hospital mortality", "ICU stay structure", "ICU mortality", "Comorbidities (coded)",
                 "Vital signs", "Laboratory", "Organ support", "Severity scores", "Microbiology", "Medication", "Surgery/anaesthesia"),
      status = c("available", "available", "partial", "unavailable", "available", "available", "available", "partial",
                 "unavailable", "unavailable", "available", "unavailable"),
      note = c("age years, sex", "dtICD Status_Discharge", "reconstructed from dtTransfer", "no ICU outcome field",
               "ICD-10 (Chinese extension)", "dtNursingChart (charted)", "dtLab", "vasopressors, airway; no ventilation/RRT",
               "none", "none", "dtDrugs; not harmonised in v0.1", "none")))
  ds$admission <- finalize_admission(ds$admission, ds$icu_stay)
  ds
}
