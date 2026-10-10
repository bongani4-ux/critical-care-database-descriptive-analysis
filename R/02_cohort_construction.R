# =============================================================================
# 02_cohort_construction.R - patient flow, integrity assertions, and the
# shared derivation of admission-level fields from admission + ICU-stay tables.
#
# Adapters decide WHO is in the cohort (database-specific). This file decides how
# the cohort is described and checked (shared), so the rules cannot drift between
# databases.
# =============================================================================

# ---- patient flow ---------------------------------------------------------------

flow_new <- function() {
  data.table::data.table(step = character(), n_admissions = numeric(),
                         n_patients = numeric(), n_icu_stays = numeric(),
                         note = character())
}

#' Append a flow step. Counts are taken from the tables passed in, so the flow
#' can never disagree with the data it describes.
flow_add <- function(flow, step, admission = NULL, icu_stay = NULL, note = "",
                     n_admissions = NA_real_, n_patients = NA_real_, n_icu_stays = NA_real_) {
  if (!is.null(admission)) {
    n_admissions <- data.table::uniqueN(admission$admission_id)
    n_patients   <- data.table::uniqueN(admission$patient_id)
  }
  if (!is.null(icu_stay)) n_icu_stays <- data.table::uniqueN(icu_stay$stay_id)
  data.table::rbindlist(list(flow, data.table::data.table(
    step = step, n_admissions = n_admissions, n_patients = n_patients,
    n_icu_stays = n_icu_stays, note = note)), use.names = TRUE)
}

# ---- integrity assertions (shared by adapters and the QC suite) --------------------

assert_unique <- function(dt, cols, label) {
  d <- dt[, .N, by = cols][N > 1L]
  if (nrow(d))
    ccdb_stop(label, ": ", nrow(d), " duplicated key value(s) on (",
              paste(cols, collapse = ", "), "); first: ",
              paste(unlist(d[1, cols, with = FALSE]), collapse = " / "))
  invisible(TRUE)
}

assert_no_missing <- function(dt, cols, label) {
  for (cl in cols) {
    n <- sum(is.na(dt[[cl]]))
    if (n) ccdb_stop(label, ": column '", cl, "' has ", n, " missing value(s)")
  }
  invisible(TRUE)
}

assert_fk <- function(child, parent, col, label, parent_col = col) {
  orphan <- setdiff(unique(child[[col]]), unique(parent[[parent_col]]))
  if (length(orphan))
    ccdb_stop(label, ": ", length(orphan), " '", col, "' value(s) have no parent row; first: ",
              orphan[1])
  invisible(TRUE)
}

#' Warn (and log) if a join changed the number of rows - the failure mode that
#' inflated Jinhua's expire_flag counts (trap 1 / trap 6 in the reference README).
check_rows <- function(dt, expected, label) {
  if (nrow(dt) != expected) {
    log_msg("WARN", "ROW COUNT CHANGED in ", label, ": ", expected, " -> ", nrow(dt))
    return(invisible(FALSE))
  }
  invisible(TRUE)
}

# ---- shared derivation -------------------------------------------------------------

#' Age band using the Jinhua bands from config (left-closed, right-open).
age_band <- function(age_years, cfg = ccdb_cfg()) {
  b <- cfg$cohort$adult_age_bands
  brk <- as.numeric(unlist(b$breaks))
  brk[is.infinite(brk)] <- Inf
  cut(age_years, breaks = brk, labels = unlist(b$labels), right = FALSE)
}

#' Complete the admission table from the ICU-stay table.
#'
#' Adapter must supply admission columns:
#'   db_id, patient_id, admission_id, age_years, sex ("M"/"F"/NA),
#'   hosp_los_days, hosp_death (0/1/NA)
#' and optionally: admit_sort_key (numeric, for ordering a patient's admissions),
#'   admission_urgency, admission_source, discharge_disposition, period.
#' icu_stay columns: db_id, patient_id, admission_id, stay_id, icu_los_days,
#'   and optionally icu_unit, icu_death (0/1/NA), stay_seq.
finalize_admission <- function(admission, icu_stay, cfg = ccdb_cfg()) {
  adm <- data.table::copy(admission)
  icu <- data.table::copy(icu_stay)
  n0 <- nrow(adm)

  if (nrow(icu)) {
    # order stays within an admission so stay_seq is deterministic
    if (!"stay_seq" %in% names(icu)) {
      icu[, stay_seq := seq_len(.N), by = admission_id]
    }
    s <- icu[, .(n_icu_stays = .N,
                 icu_los_days = if (all(is.na(icu_los_days))) NA_real_
                                else sum(icu_los_days, na.rm = TRUE)),
             by = admission_id]
    adm <- merge(adm, s, by = "admission_id", all.x = TRUE, sort = FALSE)
  } else {
    adm[, `:=`(n_icu_stays = NA_integer_, icu_los_days = NA_real_)]
  }
  check_rows(adm, n0, "finalize_admission: ICU join")
  adm[is.na(n_icu_stays), n_icu_stays := 0L]
  adm[, icu_flag := as.integer(n_icu_stays > 0L)]

  if (!"admit_sort_key" %in% names(adm)) adm[, admit_sort_key := NA_real_]
  data.table::setorder(adm, patient_id, admit_sort_key, admission_id, na.last = TRUE)
  adm[, patient_admission_seq := seq_len(.N), by = patient_id]
  adm[, is_first_admission := as.integer(patient_admission_seq == 1L)]

  adm[, age_band := age_band(age_years, cfg)]
  # Databases that release only age GROUPS (e.g. AmsterdamUMCdb) supply `age_band_given` with labels that
  # already nest inside the harmonised bands; it is used only where a numeric age is not available.
  if ("age_band_given" %in% names(adm)) {
    lv <- levels(adm$age_band)
    adm[is.na(age_years) & !is.na(age_band_given), age_band := factor(age_band_given, levels = lv)]
    adm[, age_band_given := NULL]
  }
  p <- cfg$cohort$prolonged_stay
  adm[, prolonged_hosp_los := as.integer(!is.na(hosp_los_days) & hosp_los_days > p$hospital_days)]
  adm[, prolonged_icu_los  := as.integer(!is.na(icu_los_days)  & icu_los_days  > p$icu_days)]
  for (cl in c("admission_urgency", "admission_source", "discharge_disposition", "period"))
    if (!cl %in% names(adm)) adm[, (cl) := NA_character_]
  adm[]
}
