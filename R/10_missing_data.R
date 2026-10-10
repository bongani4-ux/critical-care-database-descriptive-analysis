# =============================================================================
# 10_missing_data.R - completeness of the core harmonised variables, with the
# denominator stated for every row.
# =============================================================================

summarise_missing <- function(ds) {
  db <- ds$meta$db_id
  a <- ds$admission
  N <- nrow(a)
  Nicu <- sum(a$icu_flag == 1L)
  core <- list(
    list("Age (years)",              a$age_years,                          N),
    list("Sex",                      a$sex,                                N),
    list("Hospital LOS",             a$hosp_los_days,                      N),
    list("In-hospital death",        a$hosp_death,                         N),
    list("Admission urgency",        a$admission_urgency,                  N),
    list("Discharge disposition",    a$discharge_disposition,              N),
    list("ICU LOS (ICU admissions)", a[icu_flag == 1L]$icu_los_days,       Nicu))
  rows <- lapply(core, function(z) {
    nm <- sum(is.na(z[[2]]))
    data.table::data.table(db_id = db, variable = z[[1]], denominator = z[[3]],
                           n_missing = nm, pct_missing = if (z[[3]] > 0) 100 * nm / z[[3]] else NA_real_,
                           all_missing = nm == z[[3]])
  })
  r <- data.table::rbindlist(rows)
  # measurement coverage: units with no value in the window
  idx_mode <- ds$meta$measurement_index %||% "hospital_admission"
  D <- if (identical(idx_mode, "first_icu_admission")) Nicu else N
  avail <- ds$meta$measurement_analytes_available %||% character()
  if (length(avail)) {
    m <- ds$measurements[, .(n = data.table::uniqueN(admission_id)), by = analyte]
    mm <- data.table::data.table(db_id = db, variable = paste0("Measured in window: ", avail), analyte = avail)
    mm <- merge(mm, m, by = "analyte", all.x = TRUE)
    mm[is.na(n), n := 0L]
    r <- data.table::rbindlist(list(r, mm[, .(db_id, variable, denominator = D, n_missing = D - n,
                                              pct_missing = if (D > 0) 100 * (D - n) / D else NA_real_,
                                              all_missing = n == 0L)]), use.names = TRUE)
  }
  r[]
}
