#!/usr/bin/env Rscript
# Recording frequency (records per hour for vital signs, per day for laboratory values) with ONE rule for all databases
# (R/16_granularity.R, dictionaries/granularity_specs.csv), compared with the review's charted values (Supplemental file 6, 05/06).
#
#   Rscript scripts/run_granularity.R [db_id ...]       default: the seven ICU databases charted in the review
args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]), winslash = "/")) else getwd()
source(file.path(script_dir, "..", "R", "00_setup.R"))
ccdb_init(root = normalizePath(file.path(script_dir, ".."), winslash = "/"))
dbs <- if (length(args)) args else unname(GRAN_REVIEW_DB)
td <- ccdb_output_dir("tables")
for (d in dbs) {
  ds <- get_harmonized(d, rebuild = FALSE)
  g <- run_granularity(ds)
  if (!is.null(g)) safe_write_csv(g, file.path(td, paste0(d, "_granularity.csv")))
}
files <- file.path(td, paste0(unname(GRAN_REVIEW_DB), "_granularity.csv"))
g <- data.table::rbindlist(lapply(files[file.exists(files)], data.table::fread, colClasses = list(character = "db_id")))
if (nrow(g)) {
  cmp <- compare_granularity_to_review(g)
  safe_write_csv(cmp, file.path(td, "granularity_review_comparison.csv"))
  log_msg("INFO", "granularity vs review: ", paste(names(table(cmp$status)), table(cmp$status), collapse = "; "))
}
