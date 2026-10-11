#!/usr/bin/env Rscript
# Build the data dictionaries (INSPIRE-style workbook: Overview + one sheet per analysis-ready table, plus the item-level audit
# of labs / monitoring / medications / diagnosis codes where the adapter defines one) from the cached harmonised datasets.
#
#   Rscript scripts/build_data_dictionaries.R [db_id ...] [--no-items]
#
# Outputs go to outputs/dictionaries/ (git-ignored; counts are results-derived aggregates - see docs/data_governance.md).
args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]), winslash = "/")) else getwd()
source(file.path(script_dir, "..", "R", "00_setup.R"))
ccdb_init(root = normalizePath(file.path(script_dir, ".."), winslash = "/"))
dbs <- setdiff(args, "--no-items")
if (!length(dbs)) dbs <- c(ccdb_cfg()$databases$reference, eligible_dbs())
for (d in dbs) {
  ds <- tryCatch(get_harmonized(d, rebuild = FALSE), error = function(e) { log_msg("WARN", "[", d, "] ", conditionMessage(e)); NULL })
  if (!is.null(ds)) write_data_dictionary(ds, item_audit = !"--no-items" %in% args)
}
