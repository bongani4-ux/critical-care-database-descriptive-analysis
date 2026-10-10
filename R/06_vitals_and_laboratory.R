# =============================================================================
# 06_vitals_and_laboratory.R
#   (a) chunked extraction engine shared by all adapters
#   (b) descriptive summary of harmonised first-in-window measurements
#
# DEFINITION (harmonised): for each admission x analyte, the FIRST valid value in
# [index - pre_index_hours, index + window_hours]. Index = first ICU admission for
# ICU-based databases, hospital admission otherwise (declared in meta). Values are
# converted to the canonical unit; implausible values are removed (and counted).
# This is deliberately NOT Jinhua's convention (last value per admission) - that
# convention is reproduced only in the reference-validation step.
# =============================================================================

#' Stream a delimited (optionally gzipped) file in chunks.
#'
#' `fn(chunk)` is called once per chunk and must return a data.table (or NULL);
#' results are row-bound. Memory use is bounded by `chunk_rows`.
#' Select columns with readr::cols_only(...) in `col_types`; unlisted columns are skipped.
stream_file <- function(path, fn, col_types = readr::cols(.default = "c"),
                        delim = ",", chunk_rows = ccdb_cfg()$io$chunk_rows, label = basename(path)) {
  opt_pkg("readr")
  res <- list(); k <- 0L; nread <- 0
  cb <- readr::DataFrameCallback$new(function(x, pos) {
    k <<- k + 1L; nread <<- nread + nrow(x)
    r <- fn(data.table::as.data.table(x))
    if (!is.null(r) && nrow(r)) res[[length(res) + 1L]] <<- r
    if (k %% 10L == 0L) log_msg("INFO", "  [", label, "] ", fmt_int(nread), " rows read")
    NULL
  })
  readr::read_delim_chunked(path, cb, delim = delim, chunk_size = chunk_rows,
                            col_types = col_types, progress = FALSE, na = c("", "NA"))
  log_msg("INFO", "  [", label, "] done: ", fmt_int(nread), " rows in ", k, " chunk(s)")
  if (length(res)) data.table::rbindlist(res, use.names = TRUE, fill = TRUE) else NULL
}

#' Reduce a standardised chunk to first-in-window values.
#'
#' chunk columns: unit_key, item, time_hours, value (numeric), unit (chr or NA)
#' mapping columns: item, analyte, source_unit (used when the row has no unit)
#' index columns: unit_key, index_hours
#' Returns one row per unit_key x analyte with: value (canonical), hours_from_index,
#' n_in_window, plus bookkeeping counts as attributes.
reduce_chunk_first_in_window <- function(chunk, mapping, index, window_hours, pre_index_hours = 0,
                                         assume_canonical = character()) {
  ch <- merge(chunk, mapping[, .(item, analyte, source_unit)], by = "item", sort = FALSE)
  if (!nrow(ch)) return(NULL)
  ch <- merge(ch, index, by = "unit_key", sort = FALSE)
  ch[, hours_from_index := time_hours - index_hours]
  ch <- ch[!is.na(value) & hours_from_index >= -pre_index_hours & hours_from_index <= window_hours]
  if (!nrow(ch)) return(NULL)
  ch[, unit := data.table::fifelse(is.na(unit) | !nzchar(trimws(unit)), source_unit, unit)]
  ch <- to_canonical(ch, assume_canonical = assume_canonical)
  nbad_unit <- ch[unit_status %in% c("unknown", "missing"), .N]
  ch <- apply_plausibility(ch)
  nimp <- ch[implausible == TRUE, .N]
  ch <- ch[!is.na(value_canon)]
  if (!nrow(ch)) return(NULL)
  data.table::setorder(ch, unit_key, analyte, hours_from_index)
  r <- ch[, .(value = value_canon[1], hours_from_index = hours_from_index[1], n_in_window = .N),
          by = .(unit_key, analyte)]
  r[, `:=`(n_unit_issue = nbad_unit, n_implausible = nimp)]
  r[]
}

#' Combine per-chunk reductions into the final first-in-window table.
combine_first_in_window <- function(reduced) {
  if (is.null(reduced) || !nrow(reduced)) return(data.table::data.table(
    unit_key = character(), analyte = character(), value = numeric(),
    hours_from_index = numeric(), n_in_window = integer()))
  data.table::setorder(reduced, unit_key, analyte, hours_from_index)
  reduced[, .(value = value[1], hours_from_index = hours_from_index[1],
              n_in_window = sum(n_in_window)), by = .(unit_key, analyte)]
}

# ---- descriptive summary --------------------------------------------------------------------

summarise_measurements <- function(ds) {
  db <- ds$meta$db_id
  cfg <- ccdb_cfg()
  ad <- read_dictionary("analyte_definitions")
  m <- ds$measurements
  idx_mode <- ds$meta$measurement_index %||% "hospital_admission"
  avail <- ds$meta$measurement_analytes_available %||% character()
  by_stratum(ds, function(a, st) {
    denom_ids <- if (identical(idx_mode, "first_icu_admission")) a[icu_flag == 1L, admission_id] else a$admission_id
    D <- length(denom_ids)
    out <- lapply(ad$analyte, function(an) {
      lbl <- sprintf("%s (%s)", ad[analyte == an, label], ad[analyte == an, canonical_unit])
      if (!an %in% avail)
        return(stat_unavailable(db, st, ad[analyte == an, category], lbl,
                                "analyte not extracted / not available for this database"))
      v <- m[analyte == an & admission_id %in% denom_ids]
      r <- stat_cont(v$value, db, st, ad[analyte == an, category], lbl, denominator = D,
                     digits = if (an %in% c("creatinine", "hr", "sbp", "dbp", "map", "rr", "platelets", "sodium", "wbc")) 1 else 2,
                     note = sprintf("first value within %d h of index (%s)", cfg$measurements$window_hours, idx_mode))
      r[, stat := "median_iqr"]
      cnt <- data.table::data.table(
        db_id = db, stratum = st, domain = ad[analyte == an, category],
        variable = paste0(lbl, " - measurements in window"), level = NA_character_,
        stat = "median_iqr", n = nrow(v), denominator = D,
        pct = NA_real_, median = stats::median(v$n_in_window), q1 = stats::quantile(v$n_in_window, .25, names = FALSE),
        q3 = stats::quantile(v$n_in_window, .75, names = FALSE), mean = NA_real_, sd = NA_real_,
        n_missing = NA_real_,
        text = if (nrow(v)) fmt_median_iqr(stats::median(v$n_in_window), stats::quantile(v$n_in_window, .25, names = FALSE),
                                           stats::quantile(v$n_in_window, .75, names = FALSE), 0) else "—",
        availability = if (nrow(v)) "available" else "unavailable",
        note = "measurement density among units with >= 1 value")
      data.table::rbindlist(list(r, cnt), use.names = TRUE, fill = TRUE)
    })
    data.table::rbindlist(out, use.names = TRUE, fill = TRUE)
  })
}
