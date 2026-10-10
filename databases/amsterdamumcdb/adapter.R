# =============================================================================
# AmsterdamUMCdb v1.0.2 adapter.
#
# LOCAL COPY IS INCOMPLETE: numericitems.csv (all numeric vital signs and laboratory results)
# is NOT in the local folder, so vital signs and laboratory variables are reported as
# UNAVAILABLE for this database (an access/completeness blocker, not a property of the database).
# What is present: admissions, listitems, freetextitems, drugitems, procedureorderitems, processitems.
#
# Facts verified against the data and the review:
#  * admissions: 23,106 admissions / 20,109 patients (matches the review).
#  * lengthofstay is the ICU length of stay in HOURS (median 25 h at patient level, IQR 20-73).
#    The review's "hospital LOS 25.0 d (IQR 20-73)" therefore appears to be hours, not days,
#    and ICU - not hospital - length of stay. Reported in the discrepancy log.
#  * destination == 'Overleden' (Dutch: deceased) = death during the ICU/MC admission (2,288).
#    dateofdeath (ms) carries follow-up death status for any time after (deceased at last
#    follow-up: 31.0% of patients - matches the review).
#  * location: IC = ICU, MC = medium care, IC&MC / MC&IC = both. MC-only admissions are NOT ICU.
#  * Age is released only in groups (18-39, 40-49, ..., 80+): numeric age is unavailable.
# =============================================================================

adapter_meta <- list(
  db_id = "amsterdamumcdb",
  required_files = c("admissions.csv", "processitems.csv", "drugitems.csv"))

AMS_VASO <- "^(Noradrenaline|Dopamine|Dobutamine|Adrenaline|Fenylefrine|Terlipressine)"

adapter_build <- function(cfg) {
  flow <- flow_new()
  a <- data.table::fread(db_file("amsterdamumcdb", "admissions.csv"), showProgress = FALSE, encoding = "UTF-8",
                         colClasses = list(character = c("patientid", "admissionid")))
  assert_unique(a, "admissionid", "AmsterdamUMCdb admissions"); assert_no_missing(a, c("patientid", "admissionid"), "AmsterdamUMCdb admissions")
  a[, is_icu := location %in% c("IC", "IC&MC", "MC&IC")]
  band_map <- c("18-39" = "18-39", "40-49" = "40-59", "50-59" = "40-59", "60-69" = "60-69", "70-79" = "70-79", "80+" = ">=80")
  adm <- a[, .(db_id = "amsterdamumcdb", patient_id = patientid, admission_id = admissionid,
               age_years = NA_real_, age_band_given = unname(band_map[agegroup]),
               sex = harmonize_sex(gender), hosp_los_days = NA_real_,              # hospital LOS not recorded
               hosp_death = NA_integer_,                                          # hospital outcome not recorded
               admit_sort_key = as.numeric(admissioncount),
               admission_urgency = data.table::fcase(urgency == 1L, "emergency", urgency == 0L, "elective", default = NA_character_),
               admission_source = origin, discharge_disposition = NA_character_, period = admissionyeargroup,
               death_any_followup = as.integer(!is.na(dateofdeath)))]
  flow <- flow_add(flow, "Admissions (ICU and medium-care)", admission = adm,
                   note = "includes MC-only admissions, which are not ICU")
  icu <- a[is_icu == TRUE, .(db_id = "amsterdamumcdb", patient_id = patientid, admission_id = admissionid, stay_id = admissionid,
                             stay_seq = 1L, icu_los_days = as.numeric(lengthofstay) / 24, icu_unit = location,
                             icu_death = data.table::fifelse(destination == "Overleden", 1L, 0L))]

  # ---- organ support from process items and drug items ---------------------------------------------------------------
  pr <- data.table::fread(db_file("amsterdamumcdb", "processitems.csv"), showProgress = FALSE, encoding = "UTF-8",
                          select = c("admissionid", "itemid"), colClasses = list(character = "admissionid"))
  flag <- function(ids, ty) data.table::data.table(admission_id = unique(pr[itemid %in% ids, admissionid]), support_type = ty, value = 1L)
  support_parts <- list(flag(9328L, "mech_vent"), flag(12465L, "rrt"), flag(12634L, "intubation"), flag(12635L, "tracheostomy"))
  vp <- stream_file(db_file("amsterdamumcdb", "drugitems.csv"), function(ch) ch[grepl(AMS_VASO, item), .(admissionid)],
                    col_types = readr::cols_only(admissionid = "c", item = "c"), label = "Amsterdam drugitems",
                    arrow_filter = function(d) dplyr::filter(d, grepl(AMS_VASO, item)))
  support_parts[[5]] <- data.table::data.table(admission_id = if (is.null(vp)) character() else unique(vp$admissionid),
                                              support_type = "vasopressor", value = 1L)
  support <- data.table::rbindlist(support_parts, use.names = TRUE)
  support <- support[admission_id %in% icu$admission_id]                        # ICU-scope: restrict to ICU admissions

  flow <- flow_add(flow, "Final cohort (all admissions; ICU flag = IC or IC&MC)", admission = adm, icu_stay = icu)
  ds <- list(
    meta = list(
      index_definition = "ICU admission (offset 0)", measurement_index = "first_icu_admission",
      measurement_analytes_available = character(), support_available = c("mech_vent", "rrt", "vasopressor", "intubation", "tracheostomy"),
      support_scope = "icu",
      support_definition = list(
        mech_vent = "processitems 'Beademen' (invasive ventilation; 'Beademen non-invasief' and CPAP excluded)",
        rrt = "processitems 'CVVH'", vasopressor = "drugitems noradrenaline/dopamine/dobutamine/adrenaline/phenylephrine/terlipressin",
        intubation = "processitems 'Tube'", tracheostomy = "processitems 'Tracheostoma'"),
      hosp_death_definition = "NOT RECORDED (destination 'Overleden' = death during the ICU/MC admission)",
      hosp_los_definition = "NOT RECORDED", icu_los_definition = "lengthofstay (HOURS) / 24 - ICU/MC stay length",
      icu_death_definition = "destination == 'Overleden' (deceased during the ICU/MC admission)",
      age_note = "age released in groups only (18-39, 40-49, 50-59, 60-69, 70-79, 80+); 40-49 and 50-59 are pooled into 40-59",
      followup_note = "dateofdeath (registry follow-up up to ~14 years); mixes in-ICU, in-hospital and post-discharge deaths",
      comorbidity_note = "no diagnosis codes in the local tables (diagnoses are APACHE categories in listitems; not harmonised)",
      support_unavailable_note = "not applicable",
      extra_metrics = list(los_all_locations_median_hours = stats::median(a[admissioncount == 1L]$lengthofstay, na.rm = TRUE)),
      icu_by_construction = FALSE),
    flow = flow, admission = adm, icu_stay = icu, diagnosis = empty_diagnosis(),
    direct_flags = data.table::data.table(admission_id = character(), comorbidity = character(), value = integer()),
    measurements = empty_measurements(), support = support, severity = empty_severity(),
    availability = data.table::data.table(
      domain = c("Demographics", "Hospital mortality", "ICU stay structure", "ICU mortality", "Comorbidities (coded)",
                 "Vital signs", "Laboratory", "Organ support", "Severity scores", "Microbiology", "Medication", "Surgery/anaesthesia"),
      status = c("partial", "unavailable", "available", "available", "unavailable", "BLOCKED_local_data", "BLOCKED_local_data",
                 "available", "BLOCKED_local_data", "unavailable", "available", "unavailable"),
      note = c("age groups only", "no hospital outcome (follow-up death only)", "IC / MC location; lengthofstay in hours",
               "destination 'Overleden'", "none", "numericitems.csv missing from the local copy", "numericitems.csv missing from the local copy",
               "processitems / drugitems", "APACHE scores live in numericitems/listitems; numericitems missing",
               "none", "drugitems; not harmonised in v0.1", "specialty only")))
  ds$admission <- finalize_admission(ds$admission, ds$icu_stay)
  ds
}
