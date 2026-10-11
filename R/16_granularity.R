# =============================================================================
# 16_granularity.R - recording frequency (records per hour for vital signs, records per day for laboratory values)
#
# RULE (one rule for every database; the review states none, so the most common convention is used):
#   * unit: ICU stay; only records timed INSIDE the stay [start, end] count (records of a hospital-wide table that fall
#     before or after the ICU stay are ignored);
#   * rate per stay = records of the parameter / stay duration in hours (vital signs) or in days (laboratory values);
#   * a "record" is one row of the source table holding a value of the parameter (or, for wide tables, one non-empty cell);
#     all items listed for a parameter in dictionaries/granularity_specs.csv are pooled (e.g. invasive + non-invasive SBP);
#   * summary: MEDIAN rate over stays with >= 1 record (primary; mean, quartiles, the pooled ratio sum(records)/sum(hours) and the share of
#     stays with data are also reported; mean and pooled are alternatives shown for transparency, never used to choose the rule).
# Item ids / columns per database are in dictionaries/granularity_specs.csv (read there, edit there).
# =============================================================================

gran_time_hours <- function(x, unit) {
  if (inherits(x, "POSIXt")) return(as.numeric(x) / 3600)
  switch(unit, datetime = fast_ts_hours(as.character(x)), min = as.numeric(x) / 60, sec = as.numeric(x) / 3600,
         ms = as.numeric(x) / 3.6e6, hours = as.numeric(x), ccdb_stop("unknown time unit '", unit, "'"))
}

#' ICU stay intervals for the granularity rule, on the time scale of the database's event tables (hours).
granularity_stays <- function(db, ds) {
  rd <- function(rel, ...) data.table::fread(db_file_any(db, rel), showProgress = FALSE, ...)
  out <- switch(db,
    mimic_iv = , nwicu = {
      sub <- if (identical(db, "mimic_iv")) "icu/icustays.csv" else "data/nw_icu/icustays.csv"
      s <- rd(sub, select = c("stay_id", "hadm_id", "intime", "outtime"), colClasses = list(character = c("stay_id", "hadm_id")))
      s[, .(stay_id, skey = stay_id, akey = hadm_id, pkey = NA_character_, start_h = fast_ts_hours(intime), end_h = fast_ts_hours(outtime))]
    },
    eicu_crd = {
      s <- rd("patient.csv", select = c("patientunitstayid", "unitdischargeoffset"), colClasses = list(character = "patientunitstayid"))
      s[, .(stay_id = patientunitstayid, skey = patientunitstayid, akey = patientunitstayid, pkey = patientunitstayid, start_h = 0, end_h = unitdischargeoffset / 60)]
    },
    sicdb = {
      s <- rd("cases.csv", select = c("CaseID", "TimeOfStay"), colClasses = list(character = "CaseID"))
      s[, .(stay_id = CaseID, skey = CaseID, akey = CaseID, pkey = CaseID, start_h = 0, end_h = TimeOfStay / 3600)]
    },
    amsterdamumcdb = {
      s <- rd("admissions.csv", select = c("admissionid", "location", "lengthofstay"), colClasses = list(character = "admissionid"))
      s <- s[location %in% c("IC", "IC&MC", "MC&IC")]
      s[, .(stay_id = admissionid, skey = admissionid, akey = admissionid, pkey = admissionid, start_h = 0, end_h = as.numeric(lengthofstay))]
    },
    hirid = {
      g <- data.table::fread(db_file("hirid", "reference_data", "general_table.csv"), select = c("patientid", "admissiontime"), colClasses = list(character = "patientid"))
      s <- merge(g, ds$icu_stay[, .(patientid = admission_id, los = icu_los_days)], by = "patientid")
      s[, .(stay_id = patientid, skey = patientid, akey = patientid, pkey = patientid, start_h = fast_ts_hours(admissiontime), end_h = fast_ts_hours(admissiontime) + los * 24)]
    },
    zigong = {
      t <- rd("dtTransfer.csv", select = c("INP_NO", "StartTime", "StopTime", "TransferDept"), colClasses = list(character = "INP_NO"))
      t[, icu := grepl(ZIG_ICU_REGEX_GRAN, TransferDept, ignore.case = TRUE)]
      data.table::setorder(t, INP_NO, StartTime)
      t[, run := cumsum(c(TRUE, icu[-1] != icu[-.N] | INP_NO[-1] != INP_NO[-.N]))]
      ep <- t[icu == TRUE, .(start_h = min(StartTime), end_h = max(StopTime)), by = .(INP_NO, run)]
      data.table::setorder(ep, INP_NO, start_h); ep[, k := seq_len(.N), by = INP_NO]
      b <- rd("dtBaseline.csv", select = c("PATIENT_ID", "INP_NO"), colClasses = list(character = c("PATIENT_ID", "INP_NO")))
      ep <- merge(ep, b, by = "INP_NO")
      ep[, .(stay_id = paste0(INP_NO, "_ICU", k), skey = paste0(INP_NO, "_ICU", k), akey = INP_NO, pkey = PATIENT_ID, start_h, end_h)]
    },
    ccdb_stop("no ICU-stay interval definition for '", db, "'"))
  out <- out[!is.na(start_h) & !is.na(end_h) & end_h > start_h]
  out[]
}
ZIG_ICU_REGEX_GRAN <- "ICU|intensive care"

#' One pass over a source table: records of every parameter of the pass, assigned to ICU stays.
gran_pass <- function(db, sp, stays) {
  s1 <- sp[1]
  path <- audit_resolve(db, s1$root, s1$table)
  link <- s1$link
  skey <- stays[, .(ek = get(link), stay_id, start_h, end_h)][!is.na(ek)]
  wide <- identical(s1$kind, "wide")
  lbl <- paste(db, "granularity:", basename(path))
  acc <- list()
  handle <- function(ek, t_h, param) {
    d <- data.table::data.table(ek = as.character(ek), t_h = t_h, parameter = param)[!is.na(t_h)]
    j <- merge(d, skey, by = "ek", allow.cartesian = TRUE)[t_h >= start_h & t_h <= end_h]
    if (nrow(j)) acc[[length(acc) + 1L]] <<- j[, .N, by = .(stay_id, parameter)]
  }
  if (wide) {
    cols <- unique(unlist(strsplit(sp$items, "\\|", fixed = FALSE)))
    p2 <- stats::setNames(rep(sp$parameter, lengths(strsplit(sp$items, "\\|"))), unlist(strsplit(sp$items, "\\|")))
    allc <- c(s1$key_col, s1$time_col, cols)
    ct <- do.call(readr::cols_only, stats::setNames(rep(list("c"), length(allc)), allc))
    stream_file(path, function(ch) {
      t_h <- gran_time_hours(ch[[s1$time_col]], s1$time_unit)
      for (cl in cols) { ok <- has_value(ch[[cl]]); if (any(ok)) handle(ch[[s1$key_col]][ok], t_h[ok], p2[[cl]]) }
      NULL
    }, col_types = ct, label = lbl, arrow_filter = if (identical(s1$engine, "readr")) NULL else function(d) d)
  } else if (identical(s1$format, "parquet")) {
    items <- unique(unlist(strsplit(sp[items != "*"]$items, "\\|")))
    map <- stats::setNames(rep(sp[items != "*"]$parameter, lengths(strsplit(sp[items != "*"]$items, "\\|"))), unlist(strsplit(sp[items != "*"]$items, "\\|")))
    star <- sp[items == "*"]$parameter
    cols <- unique(c(s1$key_col, if (nzchar(s1$item_col)) s1$item_col, s1$time_col))
    stream_parquet_dir(path, function(ch) {
      key <- ch[[s1$key_col]]; t_h <- gran_time_hours(ch[[s1$time_col]], s1$time_unit)
      if (length(star)) handle(key, t_h, star)
      else { it <- as.character(ch[[s1$item_col]]); ok <- it %in% items; if (any(ok)) handle(key[ok], t_h[ok], map[it[ok]]) }
      NULL
    }, arrow_filter = function(d) { d <- dplyr::select(d, dplyr::all_of(cols)); if (!length(star)) d <- dplyr::filter(d, as.character(!!rlang::sym(s1$item_col)) %in% items); d }, label = lbl)
  } else {
    star <- sp[items == "*"]$parameter
    items <- unique(unlist(strsplit(sp[items != "*"]$items, "\\|")))
    map <- stats::setNames(rep(sp[items != "*"]$parameter, lengths(strsplit(sp[items != "*"]$items, "\\|"))), unlist(strsplit(sp[items != "*"]$items, "\\|")))
    fcol <- if (nzchar(s1$filter_col)) s1$filter_col; frx <- if (nzchar(s1$filter_regex)) s1$filter_regex
    allc <- unique(c(s1$key_col, s1$item_col, s1$time_col, fcol))
    ct <- do.call(readr::cols_only, stats::setNames(rep(list("c"), length(allc)), allc))
    flt <- function(d) {
      if (!length(star)) d <- dplyr::filter(d, (!!rlang::sym(s1$item_col)) %in% items)
      if (!is.null(fcol)) d <- dplyr::filter(d, grepl(!!frx, !!rlang::sym(fcol)))
      d
    }
    stream_file(path, function(ch) {
      if (!is.null(fcol)) ch <- ch[grepl(frx, ch[[fcol]])]
      t_h <- gran_time_hours(ch[[s1$time_col]], s1$time_unit)
      if (length(star)) handle(ch[[s1$key_col]], t_h, star)
      else { it <- ch[[s1$item_col]]; ok <- it %in% items; if (any(ok)) handle(ch[[s1$key_col]][ok], t_h[ok], map[it[ok]]) }
      NULL
    }, col_types = ct, label = lbl, arrow_filter = flt)
  }
  if (!length(acc)) return(data.table::data.table(stay_id = character(), parameter = character(), N = integer()))
  data.table::rbindlist(acc)[, .(N = sum(N)), by = .(stay_id, parameter)]
}

#' Granularity of one database: one row per parameter.
run_granularity <- function(ds) {
  db <- sub("_v[0-9_]+$", "", ds$meta$db_id)
  sp <- data.table::fread(ccdb_path("dictionaries", "granularity_specs.csv"), colClasses = "character", na.strings = NULL, encoding = "UTF-8")[db_id == db]
  if (!nrow(sp)) return(NULL)
  stays <- granularity_stays(db, ds)
  stays[, dur_h := end_h - start_h]
  log_msg("INFO", "[", db, "] granularity: ", nrow(stays), " ICU stays, ", sum(stays$dur_h) |> round(), " ICU hours")
  if (!"engine" %in% names(sp)) sp[, engine := "arrow"]
  sp[, pass := paste(root, table, engine, format, kind, link, key_col, item_col, time_col, time_unit, filter_col, filter_regex, sep = "||")]
  # a '*' (all rows) parameter must be alone in its pass
  sp[items == "*", pass := paste(pass, parameter, sep = "||")]
  counts <- data.table::rbindlist(lapply(split(sp, sp$pass), function(g) tryCatch(gran_pass(db, g, stays),
    error = function(e) { log_msg("WARN", "[", db, "] granularity pass failed (", g$table[1], "): ", conditionMessage(e)); NULL })), fill = TRUE)
  par <- unique(sp[, .(parameter, group)])
  res <- lapply(seq_len(nrow(par)), function(i) {
    p <- par$parameter[i]; grp <- par$group[i]
    n <- counts[parameter == p, .(N = sum(N)), by = stay_id]
    n[, parameter := p]
    x <- merge(n, stays[, .(stay_id, dur_h)], by = "stay_id")
    x[, rate := if (identical(grp, "lab")) N / (dur_h / 24) else N / dur_h]
    data.table::data.table(db_id = ds$meta$db_id, parameter = p, group = grp, unit = if (identical(grp, "lab")) "records per day" else "records per hour",
                           n_stays = nrow(stays), n_stays_with_data = nrow(x), pct_stays_with_data = 100 * nrow(x) / nrow(stays),
                           median = stats::median(x$rate), q1 = unname(stats::quantile(x$rate, .25)), q3 = unname(stats::quantile(x$rate, .75)),
                           mean = mean(x$rate), pooled = sum(x$N) / (sum(x$dur_h) / (if (identical(grp, "lab")) 24 else 1)), n_records = sum(x$N))
  })
  data.table::rbindlist(res)[order(group, parameter)]
}

# review label -> parameter, for the comparison with the charted values
GRAN_REVIEW_LABELS <- c("SpO₂" = "spo2", "FiO₂" = "fio2", "PEEP" = "peep", "Heart rate" = "hr", "Systolic BP" = "sbp",
                        "Cardiac output" = "co", "Medications" = "medications", "Fluids out" = "fluids_out",
                        "Lactate" = "lactate", "PaO₂" = "pao2", "Sodium" = "sodium", "Hemoglobin" = "hemoglobin",
                        "CRP" = "crp", "Creatinine" = "creatinine", "ALT" = "alt")
GRAN_REVIEW_DB <- c("MIMIC-IV" = "mimic_iv", "eICU-CRD" = "eicu_crd", "NWICU" = "nwicu", "HiRID" = "hirid", "SICdb" = "sicdb",
                    "AmsterdamUMCdb" = "amsterdamumcdb", "Zigong (ZFPH)" = "zigong")

#' Compare reproduced granularity with the review's charted values (review_reproduction/charted_values/05, 06).
compare_granularity_to_review <- function(g) {
  cv <- function(f) data.table::fread(ccdb_path("review_reproduction", "charted_values", f), encoding = "UTF-8", colClasses = "character", na.strings = "")
  rv <- data.table::rbindlist(lapply(c("05_granularity_vitals.csv", "06_granularity_labs.csv"), function(f) {
    x <- cv(f); x <- data.table::melt(x, id.vars = "parameter", variable.name = "review_db", value.name = "txt", variable.factor = FALSE)
    x[, `:=`(db_id = GRAN_REVIEW_DB[review_db], param = GRAN_REVIEW_LABELS[parameter])][!is.na(db_id)]
  }))
  out <- merge(rv, g[, .(db_id, param = parameter, median, mean, pooled, n_stays_with_data, pct_stays_with_data)], by = c("db_id", "param"), all.x = TRUE)
  out[, review_value := as.numeric(txt)]
  out[, dec := nchar(sub("^[^.]*[.]?", "", txt))]
  out[, status := data.table::fcase(is.na(txt) & (is.na(median) | n_stays_with_data == 0L), "BOTH_ABSENT",
                                    is.na(txt) & !is.na(median), "REPRODUCED_ONLY (review: not recorded)",
                                    !is.na(txt) & is.na(median), "NOT_COMPUTABLE",
                                    mapply(function(v, d, r) isTRUE(all.equal(round(v, d), r)), median, dec, review_value), "MATCH (median)",
                                    mapply(function(v, d, r) isTRUE(all.equal(round(v, d), r)), mean, dec, review_value), "MATCH (mean)",
                                    mapply(function(v, d, r) isTRUE(all.equal(round(v, d), r)), pooled, dec, review_value), "MATCH (pooled; alternative rule)",
                                    default = "DISCREPANCY")]
  out[order(db_id, param), .(db_id, parameter = param, review_value, median = round(median, 2), mean = round(mean, 2), pooled = round(pooled, 2), pct_stays_with_data = round(pct_stays_with_data, 1), status)]
}
