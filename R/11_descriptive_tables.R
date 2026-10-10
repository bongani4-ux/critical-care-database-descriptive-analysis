# =============================================================================
# 11_descriptive_tables.R - run all summaries for one database, write results,
# and build publication tables (per database and across databases).
# =============================================================================

#' All descriptive results for one harmonised dataset (long format).
compute_all_results <- function(ds) {
  parts <- list(
    summarise_demographics(ds),
    summarise_clinical(ds),
    summarise_measurements(ds),
    summarise_comorbidities(ds),
    summarise_support(ds),
    summarise_outcomes(ds))
  r <- data.table::rbindlist(parts, use.names = TRUE, fill = TRUE)
  r[, row_order := seq_len(.N)]
  # small-cell flag: counts below the configured threshold are flagged, not suppressed
  thr <- ccdb_cfg()$statistics$small_cell_flag
  r[, small_cell := stat == "n_pct" & !is.na(n) & n > 0 & n < thr]
  r[]
}

write_database_results <- function(ds, results) {
  db <- ds$meta$db_id
  td <- ccdb_output_dir("tables")
  safe_write_csv(results, file.path(td, paste0(db, "_descriptive_results.csv")))
  safe_write_csv(summarise_missing(ds), file.path(td, paste0(db, "_missing_data.csv")))
  safe_write_csv(ds$flow, file.path(td, paste0(db, "_patient_flow.csv")))
  safe_write_csv(ds$availability, file.path(td, paste0(db, "_domain_availability.csv")))
  invisible(td)
}

#' Build a gt table (HTML) of one database's results; returns the gt object.
render_table_gt <- function(results, title) {
  opt_pkg("gt")
  r <- data.table::copy(results)
  r[, label := data.table::fifelse(is.na(level), variable, paste0("  ", level))]
  r[, key := paste(domain, variable, level, sep = "||")]
  keep <- r[!duplicated(r[, .(stratum, key)])]
  adm <- keep[stratum == "admission", .(domain, variable, label, key, row_order, `All admissions` = text)]
  pt  <- keep[stratum == "patient", .(key, `First admission per patient` = text)]
  w <- merge(adm, pt, by = "key", all.x = TRUE, sort = FALSE)[order(row_order)]
  g <- gt::gt(w[, .(domain, label, `All admissions`, `First admission per patient`)],
              groupname_col = "domain", rowname_col = "label")
  g <- gt::tab_header(g, title = title)
  g <- gt::tab_source_note(g, "Median (IQR) for continuous variables; n (%) otherwise. — = not available. Denominators are in the results CSV.")
  g
}

#' Cross-database wide table (patient stratum): one column per database.
cross_database_table <- function(results_all, which_stratum = "patient") {
  r <- data.table::copy(results_all)[stratum == which_stratum]
  r[, key := paste(domain, variable, ifelse(is.na(level), "", level), sep = "||")]
  r[, label := data.table::fifelse(is.na(level), variable, paste0(variable, ": ", level))]
  ord <- unique(r[, .(key, domain, label)])
  w <- data.table::dcast(r, key ~ db_id, value.var = "text", fun.aggregate = function(x) x[1])
  w <- merge(ord, w, by = "key", sort = FALSE)
  w[, key := NULL]
  w[]
}

#' Coverage / comparability matrix across databases from the availability rows.
coverage_matrix <- function(results_all) {
  r <- results_all[stratum == "admission"]
  r[, label := paste(domain, "|", variable)]
  cm <- r[, .(status = if (all(availability == "unavailable")) "unavailable"
                        else if (any(availability == "unavailable")) "partial" else "available"),
          by = .(label, db_id)]
  data.table::dcast(cm, label ~ db_id, value.var = "status")
}
