# =============================================================================
# AmsterdamUMCdb v1.0.2 adapter.
#
# numericitems.csv (all numeric vital signs, laboratory results and NICE-registry severity scores) is
# distributed as a nested Deflate64 zip that common tools cannot read: extract it with
# databases/amsterdamumcdb/extract_numericitems.py into <cache_dir>/amsterdam_numericitems/numericitems.csv
# (or place the extracted CSV next to admissions.csv). The extractor refuses truncated archives.
# If numericitems.csv is not found, vital signs, laboratory and severity are reported as BLOCKED_local_data
# (an access/completeness blocker, not a property of the database); everything else is unaffected.
# The adapter also refuses a numericitems.csv that looks truncated (no final newline, or monitor values for
# < 50% of ICU admissions). Development-only overrides: CCDB_AMS_NUMERICITEMS=<path> and
# CCDB_ALLOW_INCOMPLETE_INPUT=1 (downgrades those refusals to warnings; never use for reported results).
# Other tables used: admissions, drugitems, processitems (listitems/freetextitems/procedureorderitems not used).
#
# Time base of numericitems: `measuredat` = milliseconds from ADMISSION to the ICU/MC unit (index = 0).
# Item mapping: mapping_numericitems.csv (itemid -> analyte); every mapped item's Dutch label and unit
# are verified against the file itself (a mismatch stops the run).
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

# NICE-registry severity scores stored as numericitems (label regex and plausible range verified at build time).
# The nurse-chart items 'A_Apache_Score'/'MCA_Apache_Score' are NOT used (undocumented, frequent zeros).
AMS_SCORES <- data.frame(
  itemid = c("19499", "19500", "19503"),
  score  = c("APACHE II (NICE registry)", "APACHE IV (NICE registry)", "SAPS II (NICE registry)"),
  label  = c("^NICE Apache II Score$", "^NICE Apache IV Score$", "^NICE SAPS II Score$"),
  max    = c(71, 286, 163), stringsAsFactors = FALSE)

ams_numeric_csv <- function() {
  ov <- Sys.getenv("CCDB_AMS_NUMERICITEMS", "")
  if (nzchar(ov)) return(if (file.exists(ov)) normalizePath(ov, winslash = "/") else NA_character_)
  cand <- c(db_file("amsterdamumcdb", "numericitems.csv", must_exist = FALSE),
            file.path(ccdb_cache_dir("amsterdam_numericitems"), "numericitems.csv"))
  hit <- cand[file.exists(cand)]
  if (length(hit)) hit[1] else NA_character_
}

#' Extract + verify the numericitems vital-sign / laboratory / severity data. Returns list(measurements, severity, notes).
ams_read_numericitems <- function(path, cfg, admissions, icu) {
  allow_incomplete <- identical(Sys.getenv("CCDB_ALLOW_INCOMPLETE_INPUT"), "1")
  refuse <- function(...) { if (allow_incomplete) log_msg("WARN", "[amsterdamumcdb] (override) ", ...) else ccdb_stop("[amsterdamumcdb] ", ...) }
  con <- file(path, "rb"); sz <- file.size(path); seek(con, max(0, sz - 1)); last <- readBin(con, "raw", 1L); close(con)
  if (!identical(last, as.raw(10L)))
    refuse("numericitems.csv does not end with a newline - the file looks truncated (", format(sz, big.mark = ","), " bytes). Re-extract it with extract_numericitems.py from a complete download.")

  mp <- data.table::fread(ccdb_path("databases", "amsterdamumcdb", "mapping_numericitems.csv"), colClasses = "character", encoding = "UTF-8")
  win <- cfg$measurements$window_hours; pre <- cfg$measurements$pre_index_hours
  max_ms <- win * 3600 * 1000
  num_ids <- mp$item; score_ids <- AMS_SCORES$itemid
  index <- admissions[, .(unit_key = admissionid, index_hours = 0)]      # measuredat is relative to ICU/MC admission
  obs <- list(); sc <- list()
  red <- stream_file(path, function(ch) {
    ch <- ch[which((ch$itemid %in% num_ids & ch$measuredat <= max_ms) | ch$itemid %in% score_ids)]
    if (!nrow(ch)) return(NULL)
    obs[[length(obs) + 1L]] <<- unique(ch[, .(itemid, label = item, unit)])
    s <- ch[itemid %in% score_ids & !is.na(value)]
    if (nrow(s)) {
      data.table::setorder(s, admissionid, itemid, measuredat)
      sc[[length(sc) + 1L]] <<- s[, .(value = value[1], measuredat = measuredat[1]), by = .(admissionid, itemid)]
    }
    n <- ch[itemid %in% num_ids]
    if (!nrow(n)) return(NULL)
    reduce_chunk_first_in_window(n[, .(unit_key = admissionid, item = itemid, time_hours = measuredat / 3.6e6, value = value, unit = NA_character_)],
                                 mp, index, win, pre)
  }, col_types = readr::cols_only(admissionid = "c", itemid = "c", item = "c", value = "d", unit = "c", measuredat = "d"),
  label = "Amsterdam numericitems",
  arrow_filter = function(d) dplyr::filter(d, (itemid %in% num_ids & measuredat <= max_ms) | itemid %in% score_ids))

  # ---- verify item labels / units against the data itself -----------------------------------------------------------------
  ob <- unique(data.table::rbindlist(obs))
  ob[, unit_n := tolower(gsub("[^ -~]+", "", data.table::fifelse(is.na(unit), "", unit), useBytes = TRUE))]
  gp <- function(p, x) vapply(seq_along(p), function(i) grepl(p[i], x[i], useBytes = TRUE), logical(1))
  chk <- merge(mp[, .(item, expect_label, expect_unit)], ob, by.x = "item", by.y = "itemid", all.x = TRUE)
  absent <- unique(chk[is.na(label), item])
  if (length(absent)) log_msg("WARN", "[amsterdamumcdb] mapped numericitems with no rows in the extraction window: ", paste(absent, collapse = ", "))
  bad <- chk[!is.na(label)][!gp(expect_label, label) | !gp(expect_unit, unit_n)]
  if (nrow(bad)) ccdb_stop("[amsterdamumcdb] numericitems mapping does not match the data: ",
                           paste0(bad$item, " ('", bad$label, "', unit '", bad$unit_n, "')", collapse = "; "))
  sob <- merge(data.table::as.data.table(AMS_SCORES), ob, by = "itemid")
  sbad <- sob[!gp(label.x, label.y)]
  if (nrow(sbad)) ccdb_stop("[amsterdamumcdb] severity-score items do not match the data: ", paste(sbad$itemid, sbad$label.y, collapse = "; "))

  meas <- combine_first_in_window(red)
  measurements <- meas[, .(admission_id = unit_key, stay_id = NA_character_, analyte, value, hours_from_index, n_in_window)]
  measurements <- measurements[admission_id %in% icu$admission_id]               # ICU-scope measurements

  sev <- data.table::rbindlist(sc)
  severity <- empty_severity()
  if (nrow(sev)) {
    data.table::setorder(sev, admissionid, itemid, measuredat)
    sev <- sev[, .(value = value[1]), by = .(admissionid, itemid)]
    sev <- merge(sev, data.table::as.data.table(AMS_SCORES)[, .(itemid, score, max)], by = "itemid")
    n0 <- nrow(sev); sev <- sev[value > 0 & value <= max]
    if (n0 > nrow(sev)) log_msg("INFO", "[amsterdamumcdb] severity: ", n0 - nrow(sev), " score(s) outside 1..max removed")
    severity <- sev[admissionid %in% icu$admission_id, .(admission_id = admissionid, score, value)]
  }

  vit_adm <- unique(measurements[analyte %in% c("hr", "map", "sbp", "spo2"), admission_id])
  cov <- length(vit_adm) / nrow(icu)
  log_msg("INFO", "[amsterdamumcdb] ICU admissions with a monitor value in the first ", win, " h: ", sprintf("%.1f%%", 100 * cov))
  if (cov < 0.5) refuse("only ", sprintf("%.1f%%", 100 * cov), " of ICU admissions have monitor values: numericitems.csv appears INCOMPLETE. Do not report results from it.")
  else if (cov < 0.8) log_msg("WARN", "[amsterdamumcdb] monitor coverage ", sprintf("%.1f%%", 100 * cov), " of ICU admissions is lower than expected")
  list(measurements = measurements, severity = severity, ok = TRUE, coverage = cov,
       incomplete_override = allow_incomplete)
}

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
  # dated deaths: dateofdeath is on the same patient clock as admittedat (ms; date resolution)
  followup_death <- a[, .(admission_id = admissionid, death_h = (as.numeric(dateofdeath) - as.numeric(admittedat)) / 3.6e6,
                          discharge_h = (as.numeric(dischargedat) - as.numeric(admittedat)) / 3.6e6, surgery_end_h = NA_real_)]
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

  # ---- vital signs, laboratory, severity from numericitems ---------------------------------------------------------------
  num_csv <- ams_numeric_csv()
  measurements <- empty_measurements(); severity <- empty_severity(); num <- NULL
  if (is.na(num_csv)) {
    log_msg("WARN", "[amsterdamumcdb] numericitems.csv not found - vital signs, laboratory and severity are BLOCKED (see adapter header)")
  } else {
    num <- ams_read_numericitems(num_csv, cfg, a, icu)
    measurements <- num$measurements; severity <- num$severity
  }
  num_ok <- !is.null(num)
  sev_adm <- if (num_ok) data.table::uniqueN(severity$admission_id) else 0L
  blocked_note <- "numericitems.csv missing from the local copy"

  flow <- flow_add(flow, "Final cohort (all admissions; ICU flag = IC or IC&MC)", admission = adm, icu_stay = icu)
  ds <- list(
    meta = list(
      index_definition = "ICU admission (offset 0)", measurement_index = "first_icu_admission",
      measurement_analytes_available = if (num_ok) unique(measurements$analyte) else character(), support_available = c("mech_vent", "rrt", "vasopressor", "intubation", "tracheostomy"),
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
      followup_admission_label = "ICU/medium-care admission",
      icu_by_construction = FALSE),
    followup_death = followup_death,
    flow = flow, admission = adm, icu_stay = icu, diagnosis = empty_diagnosis(),
    direct_flags = data.table::data.table(admission_id = character(), comorbidity = character(), value = integer()),
    measurements = measurements, support = support, severity = severity,
    availability = data.table::data.table(
      domain = c("Demographics", "Hospital mortality", "ICU stay structure", "ICU mortality", "Comorbidities (coded)",
                 "Vital signs", "Laboratory", "Organ support", "Severity scores", "Microbiology", "Medication", "Surgery/anaesthesia"),
      status = c("partial", "unavailable", "available", "available", "unavailable",
                 if (num_ok) "partial" else "BLOCKED_local_data", if (num_ok) "available" else "BLOCKED_local_data",
                 "available", if (num_ok) "partial" else "BLOCKED_local_data", "unavailable", "available", "unavailable"),
      note = c("age groups only", "no hospital outcome (follow-up death only)", "IC / MC location; lengthofstay in hours",
               "destination 'Overleden'", "none",
               if (num_ok) "bedside-monitor numeric items (invasive + non-invasive pressures pooled; core temperature sites only)" else blocked_note,
               if (num_ok) "laboratory numeric items (islabresult); Hb in mmol/L converted" else blocked_note,
               "processitems / drugitems",
               if (num_ok) sprintf("NICE-registry APACHE II / APACHE IV / SAPS II numericitems; only %d ICU admissions (%.1f%%) have a score - very sparse", sev_adm, 100 * sev_adm / nrow(icu))
               else "APACHE scores live in numericitems; numericitems missing",
               "none", "drugitems; not harmonised in v0.1", "specialty only")))
  if (num_ok && isTRUE(num$incomplete_override)) ds$meta$data_warning <- "INCOMPLETE numericitems INPUT (development override) - NOT FOR REPORTING"
  ds$admission <- finalize_admission(ds$admission, ds$icu_stay)
  ds
}
