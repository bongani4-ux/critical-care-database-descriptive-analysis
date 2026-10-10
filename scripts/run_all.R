#!/usr/bin/env Rscript
# Run every eligible database, each in its own R process (bounded memory), then
# build the cross-database tables and figures.
#
#   Rscript scripts/run_all.R [--rebuild] [--only=mimic_iv,eicu_crd] [--no-figures]
#
# A database whose source files are missing is reported BLOCKED in
# outputs/tables/<db_id>_access_status.csv - it is never skipped silently.
args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]), winslash = "/")) else getwd()
root <- normalizePath(file.path(script_dir, ".."), winslash = "/")
source(file.path(root, "R", "00_setup.R"))
ccdb_init(root = root)

only <- sub("^--only=", "", grep("^--only=", args, value = TRUE))
dbs <- if (length(only)) strsplit(only, ",")[[1]] else c(ccdb_cfg()$databases$reference, eligible_dbs())
flags <- intersect(args, c("--rebuild", "--no-figures", "--no-gt"))
rscript <- file.path(R.home("bin"), "Rscript")

log_start("run_all")
status <- vapply(dbs, function(d) {
  log_msg("INFO", "==== ", d, " ====")
  rc <- system2(rscript, c(shQuote(file.path(root, "scripts", "run_database.R")), d, flags))
  if (rc == 0) "DONE" else paste0("FAILED(rc=", rc, ")")
}, character(1))
print(data.frame(db_id = dbs, status = status, row.names = NULL))
safe_write_csv(data.table::data.table(db_id = dbs, status = status),
               file.path(ccdb_output_dir("tables"), "run_all_status.csv"))
if (!"--no-cross" %in% args) try(run_cross_database(setdiff(dbs, ccdb_cfg()$databases$reference)))
