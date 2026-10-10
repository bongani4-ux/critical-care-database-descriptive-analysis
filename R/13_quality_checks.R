# =============================================================================
# 13_quality_checks.R - automated validation
#   1. contract + integrity checks (validate_harmonized)
#   2. internal consistency of the result table (n <= denominator, pct, flow)
#   3. independent recomputation of headline statistics from the dataset
#   4. comparison with values reported in the Critical Care Database Review
#   5. comparison of the reproduced Jinhua analysis with the original outputs
# Discrepancies are REPORTED. Nothing here adjusts a result to force agreement.
# =============================================================================

qc_result <- function(db_id, check, status, detail = "") {
  data.table::data.table(db_id = db_id, check = check, status = status, detail = detail)
}

#' Internal-consistency checks on the long results table.
qc_results_table <- function(ds, results) {
  db <- ds$meta$db_id
  adm <- ds$admission
  R <- list()
  chk <- function(name, ok, detail = "") R[[length(R) + 1]] <<- qc_result(db, name, if (isTRUE(ok)) "PASS" else "FAIL", detail)

  np <- results[stat == "n_pct" & !is.na(n)]
  chk("numerator <= denominator in every n_pct row", all(np$n <= np$denominator + 1e-9),
      paste(sum(np$n > np$denominator + 1e-9), "violations"))
  chk("percent = 100*n/denominator", all(abs(np$pct - 100 * np$n / np$denominator) < 1e-6, na.rm = TRUE))
  ct <- results[stat == "median_iqr" & !is.na(n)]
  chk("n non-missing + n missing = denominator (continuous rows)",
      all(ct[!grepl("measurements in window", variable)]$n +
          ct[!grepl("measurements in window", variable)]$n_missing ==
          ct[!grepl("measurements in window", variable)]$denominator))
  chk("n <= denominator in every continuous row", all(ct$n <= ct$denominator + 1e-9, na.rm = TRUE),
      paste(sum(ct$n > ct$denominator + 1e-9, na.rm = TRUE), "violations"))
  chk("quartiles ordered (q1 <= median <= q3)", all(ct$q1 <= ct$median + 1e-9 & ct$median <= ct$q3 + 1e-9, na.rm = TRUE))
  a1 <- results[stratum == "admission" & variable == "Admissions", n]
  chk("results 'Admissions' equals admission table rows", identical(as.numeric(a1), as.numeric(nrow(adm))))
  p1 <- results[stratum == "patient" & variable == "Admissions", n]
  chk("patient stratum rows = unique patients", identical(as.numeric(p1), as.numeric(data.table::uniqueN(adm$patient_id))))
  last <- ds$flow[.N]
  chk("patient-flow final step equals cohort", isTRUE(all.equal(last$n_admissions, nrow(adm))) &&
        isTRUE(all.equal(last$n_patients, data.table::uniqueN(adm$patient_id))),
      sprintf("flow %s/%s vs cohort %d/%d", last$n_admissions, last$n_patients, nrow(adm), data.table::uniqueN(adm$patient_id)))
  chk("one first-admission flag per patient", adm[, sum(is_first_admission), by = patient_id][, all(V1 == 1L)])
  data.table::rbindlist(R)
}

#' Independent recomputation: recompute headline numbers directly from the dataset
#' (not through the summarise_* functions) and compare with the results table.
qc_recompute <- function(ds, results) {
  db <- ds$meta$db_id; adm <- ds$admission
  R <- list()
  cmp <- function(name, direct, from_results) {
    ok <- isTRUE(all.equal(as.numeric(direct), as.numeric(from_results), tolerance = 1e-9))
    R[[length(R) + 1]] <<- qc_result(db, paste("recompute:", name), if (ok) "PASS" else "FAIL",
                                     sprintf("direct=%s results=%s", format(direct), format(from_results)))
  }
  r <- function(v, st = "admission", stat_ = NULL) {
    x <- results[stratum == st & variable == v]
    if (!is.null(stat_)) x <- x[stat == stat_]
    x[1]
  }
  if (any(!is.na(adm$hosp_death))) cmp("hospital deaths", sum(adm$hosp_death == 1L, na.rm = TRUE), r("In-hospital death")$n)
  else R[[length(R) + 1]] <- qc_result(db, "recompute: hospital deaths", if (identical(r("In-hospital death")$availability, "unavailable")) "PASS" else "FAIL",
                                       "hospital death not recorded: must be reported as unavailable")
  cmp("median hospital LOS", stats::median(adm$hosp_los_days, na.rm = TRUE), r("Hospital LOS, days")$median)
  cmp("ICU admissions", sum(adm$icu_flag), r("ICU admission")$n)
  cmp("male count", sum(adm$sex == "M", na.rm = TRUE), r("Male sex")$n)
  fa <- adm[is_first_admission == 1L]
  cmp("patient-level median age", stats::median(fa$age_years, na.rm = TRUE), r("Age, years", "patient")$median)
  data.table::rbindlist(R)
}

# ---- review reference comparison --------------------------------------------------------------

decimals_of <- function(txt) {
  s <- sub("^.*[.]", "", ifelse(grepl("[.]", txt), txt, ""))
  nchar(s)
}

#' Compute one review metric from the harmonised dataset. Returns NA_real_ if the
#' metric cannot be computed from this database (reported as NOT_COMPUTABLE).
compute_review_metric <- function(ds, metric, level) {
  # database-specific diagnostic metrics computed by the adapter from raw fields (e.g. INSPIRE first-operation flag)
  if (!is.null(ds$meta$extra_metrics[[metric]])) return(as.numeric(ds$meta$extra_metrics[[metric]]))
  adm <- ds$admission; icu <- ds$icu_stay
  # levels: patient = first admission per patient; patient_any = patients with >= 1 event over ALL their
  # admissions; admission = every admission; icu_stay = every ICU stay
  base <- if (level %in% c("patient", "patient_any")) adm[is_first_admission == 1L] else adm
  hd <- adm[, .(admission_id, hosp_death)]
  icu2 <- merge(icu, hd, by = "admission_id", all.x = TRUE)
  switch(metric,
    n_patients      = data.table::uniqueN(adm$patient_id),
    n_admissions    = nrow(adm),
    n_cases         = nrow(adm),
    n_icu_stays     = nrow(icu),
    n_unit_stays    = nrow(icu),
    age_median      = stats::median(base$age_years, na.rm = TRUE),
    male_pct        = 100 * mean(base[sex %in% c("M", "F")]$sex == "M"),
    female_pct      = 100 * mean(base[sex %in% c("M", "F")]$sex == "F"),
    hosp_death_n    = if (level == "patient_any") adm[, .(d = any(hosp_death == 1L, na.rm = TRUE)), by = patient_id][, sum(d)]
                      else sum(base$hosp_death == 1L, na.rm = TRUE),
    hosp_death_pct  = if (level == "icu_stay") 100 * mean(icu2$hosp_death == 1L, na.rm = TRUE)
                      else if (level == "patient_any") 100 * adm[, .(d = any(hosp_death == 1L, na.rm = TRUE)), by = patient_id][, mean(d)]
                      else 100 * mean(base$hosp_death == 1L, na.rm = TRUE),
    icu_death_pct   = if (!"icu_death" %in% names(icu) || all(is.na(icu$icu_death))) NA_real_
                      else if (level == "icu_stay") 100 * mean(icu$icu_death == 1L, na.rm = TRUE)
                      else {
                        # admission/patient level: died during any ICU stay of the (first) admission
                        ad <- icu[admission_id %in% base$admission_id,
                                  .(d = as.integer(any(icu_death == 1L, na.rm = TRUE))), by = admission_id]
                        100 * mean(ad$d)
                      },
    icu_los_median_hours = if (level == "icu_stay") 24 * stats::median(icu$icu_los_days, na.rm = TRUE)
                           else 24 * stats::median(base[icu_flag == 1L]$icu_los_days, na.rm = TRUE),
    hosp_los_median_days = stats::median(base$hosp_los_days, na.rm = TRUE),
    icu_los_median_days  = if (level == "icu_stay") stats::median(icu$icu_los_days, na.rm = TRUE)
                           else stats::median(base[icu_flag == 1L]$icu_los_days, na.rm = TRUE),
    deceased_last_followup_pct = if (!"death_any_followup" %in% names(base)) NA_real_
                                 else 100 * mean(base$death_any_followup == 1L, na.rm = TRUE),
    NA_real_)
}

#' Compare reproduced values with the review. Rounding rule: a reproduced value
#' MATCHES when, rounded to the reference's own printed precision, it equals the
#' reference ("exact" metrics must be identical).
compare_to_review <- function(ds) {
  db <- ds$meta$db_id
  f <- ccdb_path("config", "review_reference_values.csv")
  db_ref <- sub("_v[0-9_]+$", "", db)          # version-check runs (e.g. inspire_v1_3) are compared with their review entry
  ref <- data.table::fread(f, colClasses = list(character = "value"), encoding = "UTF-8")[db_id == db_ref]
  if (!nrow(ref)) return(data.table::data.table())
  res <- lapply(seq_len(nrow(ref)), function(i) {
    x <- ref[i]
    refv <- as.numeric(x$value)
    dec <- decimals_of(x$value)
    matches <- function(val) {
      if (is.na(val)) return(FALSE)
      if (x$tolerance_type == "exact") isTRUE(all.equal(val, refv)) else isTRUE(all.equal(round(val, dec), refv))
    }
    val <- tryCatch(compute_review_metric(ds, x$metric, x$level), error = function(e) NA_real_)
    status <- if (is.na(val)) "NOT_COMPUTABLE" else if (matches(val)) "MATCH" else "DISCREPANCY"
    # Does the reported value match at a DIFFERENT unit of analysis? (the review's captions and its
    # numbers do not always agree on the denominator; this is reported, never silently adopted)
    other <- setdiff(c("patient", "patient_any", "admission", "icu_stay"), x$level)
    alt <- vapply(other, function(lv) {
      v <- tryCatch(compute_review_metric(ds, x$metric, lv), error = function(e) NA_real_)
      if (matches(v)) lv else NA_character_
    }, character(1))
    data.table::data.table(db_id = db, metric = x$metric, level = x$level, review_value = refv,
                           reproduced_value = val, abs_diff = val - refv, status = status,
                           also_matches_at_level = paste(stats::na.omit(alt), collapse = ";"),
                           review_confidence = x$confidence, review_source = x$source, review_note = x$note)
  })
  data.table::rbindlist(res)
}

# ---- Jinhua original-output comparison ------------------------------------------------------------

#' Parse "11,682 (56.9%)" / "61.0 (51.0-69.0)" / "20,530" into numeric parts.
parse_ref_text <- function(x) {
  x <- gsub("–|—|−", "-", x)
  num <- function(s) as.numeric(gsub(",", "", s))
  m1 <- regmatches(x, regexec("^\\s*([0-9,]+)\\s*\\(([0-9.]+)%\\)\\s*$", x))[[1]]
  if (length(m1) == 3) return(list(type = "n_pct", n = num(m1[2]), pct = as.numeric(m1[3])))
  m2 <- regmatches(x, regexec("^\\s*(-?[0-9.]+)\\s*\\((-?[0-9.]+)-(-?[0-9.]+)\\)\\s*$", x))[[1]]
  if (length(m2) == 4) return(list(type = "median_iqr", median = as.numeric(m2[2]),
                                   q1 = as.numeric(m2[3]), q3 = as.numeric(m2[4])))
  m3 <- regmatches(x, regexec("^\\s*([0-9,]+)\\s*$", x))[[1]]
  if (length(m3) == 2) return(list(type = "n", n = num(m3[2])))
  list(type = "unparsed")
}

#' Compare the reproduced Jinhua results with the ORIGINAL tables (read-only).
#' `ref_dir` holds Table1_demographics.csv, Table2_comorbidities.csv, Table4_outcomes.csv.
compare_jinhua_reference <- function(ds, results, ref_dir) {
  db <- ds$meta$db_id
  rd <- function(f) {
    p <- file.path(ref_dir, f)
    if (!file.exists(p)) ccdb_stop("Jinhua reference table not found: ", p)
    data.table::fread(p, encoding = "UTF-8", colClasses = "character")
  }
  t1 <- rd("Table1_demographics.csv"); data.table::setnames(t1, c("label", "value"))
  t1[, label := trimws(label)]
  t2 <- rd("Table2_comorbidities.csv")
  t4 <- rd("Table4_outcomes.csv"); data.table::setnames(t4, c("label", "value", "denom")); t4[, label := trimws(label)]
  get1 <- function(lab, tb = t1) { v <- tb[label == lab, value]; if (length(v)) parse_ref_text(v[1]) else list(type = "missing") }
  R <- list()
  add <- function(item, ref, got, kind) {
    ok <- !is.na(got) && !is.na(ref) && isTRUE(all.equal(ref, got, tolerance = 1e-9))
    R[[length(R) + 1]] <<- data.table::data.table(item = item, kind = kind, original = ref,
                                                  reproduced = got, status = if (ok) "MATCH" else "DISCREPANCY")
  }
  g <- function(v, st = "admission", field = "n") { x <- results[stratum == st & variable == v]; if (nrow(x)) x[[field]][1] else NA_real_ }
  rnd <- function(x, d) round(x, d)

  p <- get1("Admissions"); add("Admissions", p$n, g("Admissions"), "count")
  p <- get1("Unique patients"); add("Unique patients", p$n, g("Unique patients"), "count")
  p <- get1("Age, years, median (IQR)")
  add("Age median", p$median, rnd(g("Age, years", field = "median"), 1), "median")
  add("Age Q1", p$q1, rnd(g("Age, years", field = "q1"), 1), "q1"); add("Age Q3", p$q3, rnd(g("Age, years", field = "q3"), 1), "q3")
  p <- get1("Male sex, n (%)"); add("Male sex n", p$n, g("Male sex"), "count"); add("Male sex %", p$pct, rnd(g("Male sex", field = "pct"), 1), "pct")
  p <- get1("ICU admission, n (%)"); add("ICU admission n", p$n, g("ICU admission"), "count"); add("ICU admission %", p$pct, rnd(g("ICU admission", field = "pct"), 1), "pct")
  p <- get1("Hospital LOS, days, median (IQR)")
  add("Hospital LOS median", p$median, rnd(g("Hospital LOS, days", field = "median"), 1), "median")
  add("Hospital LOS Q1", p$q1, rnd(g("Hospital LOS, days", field = "q1"), 1), "q1"); add("Hospital LOS Q3", p$q3, rnd(g("Hospital LOS, days", field = "q3"), 1), "q3")
  p <- get1("ICU LOS, days, median (IQR) [ICU only]")
  add("ICU LOS median", p$median, rnd(g("ICU LOS, days (summed per ICU admission)", field = "median"), 1), "median")
  add("ICU LOS Q1", p$q1, rnd(g("ICU LOS, days (summed per ICU admission)", field = "q1"), 1), "q1")
  add("ICU LOS Q3", p$q3, rnd(g("ICU LOS, days (summed per ICU admission)", field = "q3"), 1), "q3")
  p <- get1("In-hospital death, n (%)"); add("In-hospital death n", p$n, g("In-hospital death"), "count"); add("In-hospital death %", p$pct, rnd(g("In-hospital death", field = "pct"), 1), "pct")
  p <- get1("Hospital LOS > 14 days", t4); add("Hospital LOS > 14 d n", p$n, g("Hospital LOS > 14 days"), "count")
  p <- get1("ICU LOS > 3 days", t4); add("ICU LOS > 3 d n", p$n, g("ICU LOS > 3 days"), "count")
  p <- get1("ICU readmission (>1 ICU episode)", t4); add("ICU readmission n", p$n, g("More than one ICU stay in the admission"), "count")
  p <- get1("Patients with >1 hospital admission", t4); add("Patients >1 admission n", p$n, g("Patients with > 1 hospital admission"), "count")
  p <- get1("MECH VENTILATION"); add("Mechanical ventilation n", p$n, results[stratum == "admission" & variable == "Invasive mechanical ventilation", n][1], "count")
  p <- get1("RRT DIALYSIS");      add("RRT n", p$n, results[stratum == "admission" & variable == "Renal replacement therapy", n][1], "count")

  # comorbidity counts: original label e.g. "STROKE ISCHEMIC" -> dictionary id STROKE_ISCHEMIC
  defs <- read_dictionary("comorbidity_definitions")
  fl <- build_comorbidity_matrix(ds)
  for (i in seq_len(nrow(t2))) {
    cm <- gsub(" ", "_", t2$Comorbidity[i])
    if (!cm %in% defs$comorbidity) next
    add(paste("Comorbidity:", cm), as.numeric(t2$n[i]), sum(fl[[cm]] == 1L, na.rm = TRUE), "count")
  }
  out <- data.table::rbindlist(R)
  out[, db_id := db]
  data.table::setcolorder(out, "db_id")
  out[]
}

#' Run every check for one database and return a combined table.
run_quality_checks <- function(ds, results) {
  val <- validate_harmonized(ds, stop_on_fail = FALSE)
  val <- data.table::data.table(db_id = ds$meta$db_id, check = val$check, status = val$status, detail = val$detail)
  data.table::rbindlist(list(val, qc_results_table(ds, results), qc_recompute(ds, results)), use.names = TRUE, fill = TRUE)
}
