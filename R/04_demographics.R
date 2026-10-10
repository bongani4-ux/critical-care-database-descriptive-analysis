# =============================================================================
# 04_demographics.R - shared statistic helpers + demographic characteristics
#
# RESULT TABLE CONTRACT (used by modules 04-10, assembled in 11):
#   db_id, stratum, domain, variable, level, stat, n, denominator, pct,
#   median, q1, q3, mean, sd, n_missing, text, availability, note
# stratum: "admission"  = every hospital admission in the cohort
#          "patient"    = first admission per patient (matches the review's
#                         patient-level convention; see docs/methods.md)
# =============================================================================

# ---- formatting -------------------------------------------------------------------

fmt_int <- function(x) format(x, big.mark = ",", trim = TRUE, scientific = FALSE)

fmt_n_pct <- function(n, d, digits = 1) {
  if (is.na(d) || d == 0) return("—")
  sprintf("%s (%s%%)", fmt_int(n), formatC(100 * n / d, format = "f", digits = digits))
}

fmt_median_iqr <- function(med, q1, q3, digits = 1) {
  if (is.na(med)) return("—")
  f <- function(v) formatC(v, format = "f", digits = digits)
  sprintf("%s (%s–%s)", f(med), f(q1), f(q3))
}

fmt_mean_sd <- function(m, s, digits = 1) {
  if (is.na(m)) return("—")
  sprintf("%s ± %s", formatC(m, format = "f", digits = digits), formatC(s, format = "f", digits = digits))
}

# ---- result-row constructors ----------------------------------------------------------

new_rows <- function() data.table::data.table(
  db_id = character(), stratum = character(), domain = character(), variable = character(),
  level = character(), stat = character(), n = numeric(), denominator = numeric(),
  pct = numeric(), median = numeric(), q1 = numeric(), q3 = numeric(), mean = numeric(),
  sd = numeric(), n_missing = numeric(), text = character(), availability = character(),
  note = character())

#' Continuous summary: median (IQR), mean (SD), n, n missing against `denominator`.
#' `denominator` is the number of units the variable COULD have been recorded for.
stat_cont <- function(x, db_id, stratum, domain, variable, denominator = length(x),
                      digits = 1, level = NA_character_, note = "") {
  xn <- x[!is.na(x)]
  q <- if (length(xn)) stats::quantile(xn, c(.25, .5, .75), names = FALSE, type = 7) else rep(NA_real_, 3)
  data.table::data.table(
    db_id = db_id, stratum = stratum, domain = domain, variable = variable, level = level,
    stat = "median_iqr", n = length(xn), denominator = denominator,
    pct = if (denominator > 0) 100 * length(xn) / denominator else NA_real_,
    median = q[2], q1 = q[1], q3 = q[3],
    mean = if (length(xn)) mean(xn) else NA_real_,
    sd = if (length(xn) > 1) stats::sd(xn) else NA_real_,
    n_missing = denominator - length(xn),
    text = fmt_median_iqr(q[2], q[1], q[3], digits),
    availability = if (length(xn)) "available" else "unavailable", note = note)
}

#' Binary summary: n (%) of `x == 1` over `denominator` (default: non-missing x).
stat_binary <- function(x, db_id, stratum, domain, variable, denominator = NULL,
                        level = NA_character_, note = "") {
  nn <- sum(x == 1L, na.rm = TRUE)
  d <- if (is.null(denominator)) sum(!is.na(x)) else denominator
  data.table::data.table(
    db_id = db_id, stratum = stratum, domain = domain, variable = variable, level = level,
    stat = "n_pct", n = nn, denominator = d, pct = if (d > 0) 100 * nn / d else NA_real_,
    median = NA_real_, q1 = NA_real_, q3 = NA_real_, mean = NA_real_, sd = NA_real_,
    n_missing = sum(is.na(x)), text = fmt_n_pct(nn, d),
    availability = if (any(!is.na(x))) "available" else "unavailable", note = note)
}

#' Categorical summary: one n (%) row per level; denominator = all units supplied.
stat_cat <- function(x, db_id, stratum, domain, variable, levels = NULL, denominator = length(x),
                     note = "", top = Inf) {
  tb <- sort(table(x, useNA = "no"), decreasing = TRUE)
  lv <- if (is.null(levels)) names(tb) else levels
  if (is.finite(top)) lv <- head(lv, top)
  rows <- lapply(lv, function(l) {
    n <- if (l %in% names(tb)) as.numeric(tb[[l]]) else 0
    data.table::data.table(
      db_id = db_id, stratum = stratum, domain = domain, variable = variable, level = l,
      stat = "n_pct", n = n, denominator = denominator,
      pct = if (denominator > 0) 100 * n / denominator else NA_real_,
      median = NA_real_, q1 = NA_real_, q3 = NA_real_, mean = NA_real_, sd = NA_real_,
      n_missing = sum(is.na(x)), text = fmt_n_pct(n, denominator),
      availability = "available", note = note)
  })
  if (!length(rows)) return(new_rows())
  data.table::rbindlist(rows)
}

#' A row stating that a variable is not available in this database.
stat_unavailable <- function(db_id, stratum, domain, variable, note = "not recorded in this database") {
  data.table::data.table(
    db_id = db_id, stratum = stratum, domain = domain, variable = variable, level = NA_character_,
    stat = "unavailable", n = NA_real_, denominator = NA_real_, pct = NA_real_, median = NA_real_,
    q1 = NA_real_, q3 = NA_real_, mean = NA_real_, sd = NA_real_, n_missing = NA_real_,
    text = "—", availability = "unavailable", note = note)
}

#' Run `fn(admission_subset, stratum_name)` for both strata and bind the results.
by_stratum <- function(ds, fn) {
  adm <- ds$admission
  data.table::rbindlist(list(
    fn(adm, "admission"),
    fn(adm[is_first_admission == 1L], "patient")), use.names = TRUE, fill = TRUE)
}

# ---- demographics ----------------------------------------------------------------------

summarise_demographics <- function(ds) {
  db <- ds$meta$db_id
  by_stratum(ds, function(a, st) {
    N <- nrow(a)
    out <- list(
      data.table::data.table(
        db_id = db, stratum = st, domain = "Cohort", variable = "Admissions", level = NA_character_,
        stat = "n", n = N, denominator = NA_real_, pct = NA_real_, median = NA_real_, q1 = NA_real_,
        q3 = NA_real_, mean = NA_real_, sd = NA_real_, n_missing = 0, text = fmt_int(N),
        availability = "available", note = ""),
      data.table::data.table(
        db_id = db, stratum = st, domain = "Cohort", variable = "Unique patients", level = NA_character_,
        stat = "n", n = data.table::uniqueN(a$patient_id), denominator = NA_real_, pct = NA_real_,
        median = NA_real_, q1 = NA_real_, q3 = NA_real_, mean = NA_real_, sd = NA_real_, n_missing = 0,
        text = fmt_int(data.table::uniqueN(a$patient_id)), availability = "available", note = ""),
      stat_cont(a$age_years, db, st, "Demographics", "Age, years", N,
                note = ds$meta$age_note %||% ""),
      stat_cat(as.character(a$age_band), db, st, "Demographics", "Age band",
               levels = unlist(ccdb_cfg()$cohort$adult_age_bands$labels), denominator = N),
      stat_binary(as.integer(a$sex == "M"), db, st, "Demographics", "Male sex", denominator = N,
                  note = "denominator = all units; missing sex counted in n_missing"),
      stat_binary(as.integer(a$sex == "F"), db, st, "Demographics", "Female sex", denominator = N))
    if (st == "admission") {
      apt <- a[, .N, by = patient_id]$N
      out[[length(out) + 1]] <- stat_cont(apt, db, st, "Cohort", "Admissions per patient",
                                          digits = 0, note = "per unique patient")
    }
    data.table::rbindlist(out, use.names = TRUE, fill = TRUE)
  })
}

`%||%` <- function(a, b) if (is.null(a)) b else a
