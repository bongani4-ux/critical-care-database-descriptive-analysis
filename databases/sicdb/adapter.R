# =============================================================================
# SICdb v1.0.8 (Salzburg Intensive Care database) adapter.
#
# Unit of analysis: CASE (CaseID) = hospital admission with an ICU stay; patient =
# PatientID. Every case is an ICU case by construction (one ICU stay per case here).
# All times are SECONDS from ICU admission (verified: first monitor value at offset 0
# in 99.6% of cases; labs before ICU entry have negative offsets). ICUOffset is the
# delay from hospital admission to ICU admission.
#
# Coding resolved from the database's own d_references table (not assumed):
#   Sex 735 = male, 736 = female, 737 = unknown
#   HospitalDischargeType 2026 = Survived, 2028 = Deceased
#   DischargeState (ICU discharge) 2202 = alive, 2215 = deceased, 2212 = unknown
# Hospital length of stay is NOT recorded (only the ICU time); hospital LOS is
# therefore unavailable. Age is released in 5-year bins (15, 20, ..., 90).
# =============================================================================

adapter_meta <- list(
  db_id = "sicdb",
  required_files = c("cases.csv", "d_references.csv", "laboratory.csv", "data_float_h.csv", "data_range.csv",
                     "data_ref.csv", "medication.csv"))

SIC_VASO_DRUGS <- c(1562, 1502, 1550, 1593, 1618, 1559, 1560)  # norepinephrine, epinephrine, vasopressin, phenylephrine, dopamine, dobutamine, milrinone
SIC_VENT_SIGNALS <- c(711, 715)                                  # PEEP, peak airway pressure (ventilator signals)

adapter_build <- function(cfg) {
  flow <- flow_new()
  rd <- function(f, ...) data.table::fread(db_file_any("sicdb", f), showProgress = FALSE, ...)
  ref <- rd("d_references.csv")

  # resolve coded fields from the dictionary (and stop if the coding is not what this adapter expects)
  refval <- function(id) ref[ReferenceGlobalID == id, ReferenceValue]
  stopifnot(identical(refval(735), "male"), identical(refval(736), "female"),
            identical(refval(2026), "Survived"), identical(refval(2028), "Deceased"),
            identical(refval(2215), "verstorben"), identical(refval(2202), "lebend"))

  cs <- rd("cases.csv", colClasses = list(character = c("CaseID", "PatientID")))
  assert_unique(cs, "CaseID", "SICdb cases"); assert_no_missing(cs, c("CaseID", "PatientID"), "SICdb cases")
  adm <- cs[, .(db_id = "sicdb", patient_id = PatientID, admission_id = CaseID,
                age_years = as.numeric(AgeOnAdmission),
                sex = data.table::fcase(Sex == 735L, "M", Sex == 736L, "F", default = NA_character_),
                hosp_los_days = NA_real_,                                  # not recorded
                hosp_death = data.table::fcase(HospitalDischargeType == 2028L, 1L, HospitalDischargeType == 2026L, 0L,
                                               default = NA_integer_),
                admit_sort_key = as.numeric(OffsetAfterFirstAdmission),
                admission_urgency = NA_character_, admission_source = as.character(ReferringUnit),
                discharge_disposition = NA_character_, period = as.character(AdmissionYear),
                death_any_followup = as.integer(!is.na(OffsetOfDeath)))]
  # dated deaths: OffsetOfDeath = seconds from ICU admission (the database's time-zero); recorded within 6 months / 1 year only
  followup_death <- cs[, .(admission_id = CaseID, death_h = as.numeric(OffsetOfDeath) / 3600,
                           discharge_h = as.numeric(TimeOfStay) / 3600, surgery_end_h = NA_real_)]
  flow <- flow_add(flow, "Cases in cases table", admission = adm)

  unit_name <- ref[ReferenceName == "HospitalUnit", stats::setNames(ReferenceValue, as.character(ReferenceGlobalID))]
  icu <- cs[, .(db_id = "sicdb", patient_id = PatientID, admission_id = CaseID, stay_id = CaseID, stay_seq = 1L,
                icu_los_days = as.numeric(TimeOfStay) / 86400, icu_unit = unname(unit_name[as.character(HospitalUnit)]),
                icu_death = data.table::fcase(DischargeState == 2215L, 1L, DischargeState == 2202L, 0L, default = NA_integer_))]

  # severity: SAPS 3 (0 = not recorded)
  severity <- cs[!is.na(saps3) & saps3 > 0, .(admission_id = CaseID, score = "SAPS 3", value = as.numeric(saps3))]

  # diagnoses: ONE principal ICD-10-GM diagnosis per case (ICD10Main)
  diagnosis <- cs[!is.na(ICD10Main) & nzchar(ICD10Main), .(admission_id = CaseID, code = ICD10Main, code_system = "ICD10")]

  # direct comorbidity flags from the database's processed fields (Yes/No/Unknown)
  dref <- rd("data_ref.csv", colClasses = list(character = "CaseID"))
  direct_map <- c("3097" = "DIABETES", "3098" = "HYPERTENSION")
  df <- dref[FieldID %in% as.integer(names(direct_map)) & RefID %in% c(738L, 740L)]
  direct_flags <- df[, .(admission_id = CaseID, comorbidity = unname(direct_map[as.character(FieldID)]),
                         value = as.integer(RefID == 740L))]

  # ---- organ support ---------------------------------------------------------------------------------------
  support_parts <- list(data.table::data.table(admission_id = cs[HoursOfCRRT > 0, CaseID], support_type = "rrt", value = 1L))
  vr <- rd("data_range.csv", colClasses = list(character = "CaseID"))
  stay_end <- cs[, .(CaseID, end_s = as.numeric(TimeOfStay))]
  vr <- merge(vr, stay_end, by = "CaseID")
  in_stay <- vr[Offset <= end_s & OffsetEnd >= 0]
  support_parts[[2]] <- data.table::data.table(admission_id = unique(in_stay[DataID == 720L, CaseID]), support_type = "intubation", value = 1L)
  support_parts[[3]] <- data.table::data.table(admission_id = unique(in_stay[DataID == 3041L, CaseID]), support_type = "tracheostomy", value = 1L)
  md <- rd("medication.csv", select = c("CaseID", "DrugID", "Offset"), colClasses = list(character = "CaseID"))
  md <- merge(md[DrugID %in% SIC_VASO_DRUGS & Offset >= 0], stay_end, by = "CaseID")
  support_parts[[4]] <- data.table::data.table(admission_id = unique(md[Offset <= end_s, CaseID]), support_type = "vasopressor", value = 1L)

  # ---- measurements (offset 0 = ICU admission) ------------------------------------------------------------------
  mp <- data.table::fread(ccdb_path("databases", "sicdb", "mapping_measurements.csv"), colClasses = "character", encoding = "UTF-8")
  chk <- function(src, nm) {
    m <- merge(mp[source == src], ref[ReferenceName == nm, .(item = as.character(ReferenceGlobalID), label = ReferenceValue)], by = "item", all.x = TRUE)
    bad <- m[is.na(label) | !mapply(grepl, expect_label, label)]
    if (nrow(bad)) ccdb_stop("[sicdb] ", src, " mapping does not match d_references: ", paste0(bad$item, " ('", bad$label, "')", collapse = "; "))
  }
  chk("float", "SignalFloat"); chk("lab", "Laboratory")
  win <- cfg$measurements$window_hours; pre <- cfg$measurements$pre_index_hours
  index <- cs[, .(unit_key = CaseID, index_hours = 0)]
  fm <- mp[source == "float", .(item, analyte, source_unit)]
  vent_hit <- list()
  float_ids <- c(fm$item, as.character(SIC_VENT_SIGNALS)); max_off <- win * 3600
  fl <- stream_file(db_file_any("sicdb", "data_float_h.csv"), function(ch) {
    ch <- ch[Offset <= win * 3600]
    if (!nrow(ch)) return(NULL)
    vent_hit[[length(vent_hit) + 1L]] <<- unique(ch[DataID %in% as.character(SIC_VENT_SIGNALS) & Val > 0, CaseID])
    ch <- ch[DataID %in% fm$item]
    if (!nrow(ch)) return(NULL)
    reduce_chunk_first_in_window(ch[, .(unit_key = CaseID, item = DataID, time_hours = Offset / 3600, value = Val, unit = NA_character_)],
                                 fm, index, win, pre)
  }, col_types = readr::cols_only(CaseID = "c", DataID = "c", Offset = "d", Val = "d"), label = "SICdb data_float_h",
  arrow_filter = function(d) dplyr::filter(d, DataID %in% float_ids & Offset <= max_off))
  lm <- mp[source == "lab", .(item, analyte, source_unit)]
  lab_ids <- lm$item
  lb <- stream_file(db_file_any("sicdb", "laboratory.csv"), function(ch) {
    ch <- ch[LaboratoryID %in% lm$item & Offset <= win * 3600]
    if (!nrow(ch)) return(NULL)
    reduce_chunk_first_in_window(ch[, .(unit_key = CaseID, item = LaboratoryID, time_hours = Offset / 3600, value = LaboratoryValue, unit = NA_character_)],
                                 lm, index, win, pre)
  }, col_types = readr::cols_only(CaseID = "c", LaboratoryID = "c", Offset = "d", LaboratoryValue = "d"), label = "SICdb laboratory",
  arrow_filter = function(d) dplyr::filter(d, LaboratoryID %in% lab_ids & Offset <= max_off))
  meas <- combine_first_in_window(data.table::rbindlist(list(fl, lb), use.names = TRUE, fill = TRUE))
  measurements <- meas[, .(admission_id = unit_key, stay_id = NA_character_, analyte, value, hours_from_index, n_in_window)]
  support_parts[[5]] <- data.table::data.table(admission_id = unique(unlist(vent_hit)), support_type = "mech_vent", value = 1L)
  support <- data.table::rbindlist(support_parts, use.names = TRUE)

  flow <- flow_add(flow, "Final cohort (all cases are ICU cases)", admission = adm, icu_stay = icu)
  ds <- list(
    meta = list(
      index_definition = "ICU admission (offset 0)", measurement_index = "first_icu_admission",
      measurement_analytes_available = unique(measurements$analyte),
      support_available = c("mech_vent", "rrt", "vasopressor", "intubation", "tracheostomy"), support_scope = "icu",
      support_definition = list(
        mech_vent = "ventilator signal recorded (PEEP or peak airway pressure > 0) in the first 24 h of the ICU stay; first-24h only, signal-based proxy",
        rrt = "cases.HoursOfCRRT > 0 (continuous RRT only; intermittent haemodialysis not captured)",
        vasopressor = "medication record of norepinephrine/epinephrine/vasopressin/phenylephrine/dopamine/dobutamine/milrinone during the ICU stay",
        intubation = "endotracheal-tube airway interval overlapping the ICU stay",
        tracheostomy = "tracheal-cannula airway interval overlapping the ICU stay"),
      hosp_death_definition = "cases.HospitalDischargeType == 2028 ('Deceased')",
      hosp_los_definition = "NOT RECORDED (database holds ICU time only)",
      icu_los_definition = "cases.TimeOfStay / 86400", icu_death_definition = "cases.DischargeState == 2215 ('verstorben')",
      age_note = "5-year age bins (15, 20, ... 90 = lower bound / top-coded); medians are approximate",
      followup_note = "OffsetOfDeath recorded within 6 months (3,143 cases) or 1 year (24,243 cases) of observation",
      comorbidity_note = "diabetes and hypertension from the database's own Yes/No flags; all other groups only via the single principal ICD-10-GM diagnosis (not comorbid history)",
      followup_admission_label = "ICU admission",
      icu_by_construction = TRUE),
    followup_death = followup_death,
    flow = flow, admission = adm, icu_stay = icu, diagnosis = diagnosis, direct_flags = direct_flags,
    measurements = measurements, support = support, severity = severity,
    availability = data.table::data.table(
      domain = c("Demographics", "Hospital mortality", "ICU stay structure", "ICU mortality", "Comorbidities (coded)",
                 "Vital signs", "Laboratory", "Organ support", "Severity scores", "Microbiology", "Medication", "Surgery/anaesthesia"),
      status = c("partial", "available", "available", "available", "partial", "partial", "available", "partial", "available",
                 "unavailable", "available", "partial"),
      note = c("age in 5-year bins; no hospital LOS", "HospitalDischargeType", "one ICU stay per case", "DischargeState",
               "principal diagnosis + 2 direct flags", "hourly aggregated monitor values (first hour), not instantaneous",
               "laboratory (units from d_references)", "signal/airway/CRRT/medication-based; see definitions", "SAPS 3",
               "none", "medication; not harmonised in v0.1", "SurgicalSite; HeartSurgery fields; not harmonised in v0.1")))
  ds$admission <- finalize_admission(ds$admission, ds$icu_stay)
  ds
}
