#!/usr/bin/env Rscript
# Run the full descriptive workflow for ONE database.
#
#   Rscript scripts/run_database.R <db_id> [--rebuild] [--no-figures] [--no-gt]
#
# db_id is a value from config/database_registry.csv (e.g. jinhua, mimic_iv).
# --rebuild   ignore the cached harmonised dataset in derived/<db_id>/
args <- commandArgs(trailingOnly = TRUE)
if (!length(args) || startsWith(args[1], "--")) stop("Usage: Rscript scripts/run_database.R <db_id> [--rebuild] [--no-figures] [--no-gt]")

# locate the project root from this script's own location (works from any cwd)
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]), winslash = "/")) else getwd()
source(file.path(script_dir, "..", "R", "00_setup.R"))
ccdb_init(root = normalizePath(file.path(script_dir, ".."), winslash = "/"))

run_database(args[1],
             rebuild  = "--rebuild" %in% args,
             figures  = !"--no-figures" %in% args,
             gt_table = !"--no-gt" %in% args)
