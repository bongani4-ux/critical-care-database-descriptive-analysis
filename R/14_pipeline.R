# =============================================================================
# 14_pipeline.R - orchestration. One database per R process keeps memory bounded:
# the project never needs two databases loaded at once.
# =============================================================================

#' Build (or load) the harmonised dataset for one database.
#' The harmonised dataset is cached in derived/<db_id>/harmonized.rds (git-ignored,
#' patient-level). `rebuild = TRUE` ignores the cache.
get_harmonized <- function(db_id, rebuild = FALSE) {
  f <- file.path(ccdb_derived_dir(db_id), "harmonized.rds")
  if (file.exists(f) && !rebuild) {
    log_msg("INFO", "[", db_id, "] using cached harmonised dataset: ", f)
    return(readRDS(f))
  }
  ad <- load_adapter(db_id)
  log_msg("INFO", "[", db_id, "] building harmonised dataset from source files")
  t0 <- Sys.time()
  ds <- ad$adapter_build(ccdb_cfg())
  g <- get_db(db_id)
  ds$meta$db_id <- db_id
  ds$meta$display_name <- g$display_name
  ds$meta$version <- g$version
  val <- validate_harmonized(ds, stop_on_fail = TRUE)
  log_msg("INFO", "[", db_id, "] contract validation: ", sum(val$status == "PASS"), " PASS, ",
          sum(val$status == "WARN"), " WARN, ", sum(val$status == "FAIL"), " FAIL (",
          round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min)")
  safe_save_rds(ds, f)
  ds
}

run_database <- function(db_id, rebuild = FALSE, figures = TRUE, gt_table = TRUE) {
  log_start(db_id)
  acc <- check_db_access(db_id)
  if (acc$status != "READY") {
    log_msg("WARN", "[", db_id, "] ", acc$status, " - missing: ", acc$missing)
    safe_write_csv(acc, file.path(ccdb_output_dir("tables"), paste0(db_id, "_access_status.csv")))
    return(invisible(list(db_id = db_id, status = acc$status)))
  }
  ds <- get_harmonized(db_id, rebuild = rebuild)
  results <- compute_all_results(ds)
  write_database_results(ds, results)

  qc <- run_quality_checks(ds, results)
  td <- ccdb_output_dir("tables")
  safe_write_csv(qc, file.path(td, paste0(db_id, "_quality_checks.csv")))
  tryCatch(write_data_dictionary(ds), error = function(e) log_msg("WARN", "[", db_id, "] data dictionary not written: ", conditionMessage(e)))
  rv <- compare_to_review(ds)
  if (nrow(rv)) safe_write_csv(rv, file.path(td, paste0(db_id, "_review_comparison.csv")))

  g <- get_db(db_id)
  if (identical(g$role, "reference") && !is.null(CCDB$paths$jinhua_reference_dir)) {
    jr <- compare_jinhua_reference(ds, results, CCDB$paths$jinhua_reference_dir)
    safe_write_csv(jr, file.path(td, "jinhua_reproduction_vs_original.csv"))
    log_msg("INFO", "[jinhua] reproduction vs original: ", sum(jr$status == "MATCH"), " MATCH, ",
            sum(jr$status != "MATCH"), " DISCREPANCY")
  }
  if (figures && requireNamespace("ggplot2", quietly = TRUE)) plot_database_figures(ds, results)
  if (gt_table && requireNamespace("gt", quietly = TRUE)) {
    gt::gtsave(render_table_gt(results, paste(ds$meta$display_name, ds$meta$version, "- descriptive characteristics")),
               file.path(td, paste0(db_id, "_table1.html")))
  }
  log_msg("INFO", "[", db_id, "] QC: ", sum(qc$status == "PASS"), " PASS, ", sum(qc$status == "WARN"), " WARN, ",
          sum(qc$status == "FAIL"), " FAIL")
  invisible(list(db_id = db_id, status = "DONE", results = results, qc = qc, review = rv))
}

#' Combine per-database outputs into the cross-database tables and figures.
run_cross_database <- function(db_ids = eligible_dbs()) {
  log_start("cross_database")
  td <- ccdb_output_dir("tables")
  files <- file.path(td, paste0(db_ids, "_descriptive_results.csv"))
  have <- file.exists(files)
  if (any(!have)) log_msg("WARN", "No results yet for: ", paste(db_ids[!have], collapse = ", "))
  if (!any(have)) ccdb_stop("No per-database results found; run run_database() first.")
  all <- data.table::rbindlist(lapply(files[have], data.table::fread, encoding = "UTF-8"), use.names = TRUE, fill = TRUE)
  safe_write_csv(all, file.path(td, "cross_database_results_long.csv"))
  safe_write_csv(cross_database_table(all), file.path(td, "cross_database_table_patient_stratum.csv"))
  safe_write_csv(coverage_matrix(all), file.path(td, "cross_database_coverage_matrix.csv"))
  rv <- data.table::rbindlist(lapply(file.path(td, paste0(db_ids, "_review_comparison.csv")[have]),
                                     function(f) if (file.exists(f)) data.table::fread(f) else NULL), fill = TRUE)
  if (nrow(rv)) safe_write_csv(rv, file.path(td, "cross_database_review_comparison.csv"))
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    plot_cross_coverage(all); plot_cross_mortality(all)
  }
  invisible(all)
}
