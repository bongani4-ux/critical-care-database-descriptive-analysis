#!/usr/bin/env Rscript
# INSPIRE: the review charted v1.3 (Table 1) while the project analyses v1.4.2. This script lists, for every INSPIRE value in
# config/review_reference_values.csv, the review's charted value, the value reproduced on v1.3 and on v1.4.2, and the v1.4.2 value
# rounded to the review's own precision = the value to use when the review is updated to v1.4.2.
#   Rscript scripts/inspire_version_update.R        (needs the cached datasets of `inspire` and `inspire_v1_3`)
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]), winslash = "/")) else getwd()
source(file.path(script_dir, "..", "R", "00_setup.R"))
ccdb_init(root = normalizePath(file.path(script_dir, ".."), winslash = "/"))
ref <- data.table::fread(ccdb_path("config", "review_reference_values.csv"), colClasses = list(character = "value"), encoding = "UTF-8")[db_id == "inspire"]
d14 <- get_harmonized("inspire"); d13 <- get_harmonized("inspire_v1_3")
val <- function(ds, m, lv) as.numeric(tryCatch(compute_review_metric(ds, m, lv), error = function(e) NA_real_))
out <- ref[, {
  dec <- decimals_of(value)
  v13 <- val(d13, metric, level); v14 <- val(d14, metric, level)
  .(review_value_charted = as.numeric(value), v1_3_reproduced = v13, v1_4_2_reproduced = v14, decimals = as.numeric(dec),
    v1_4_2_for_review = if (is.na(v14)) NA_real_ else round(v14, dec),
    changed = !is.na(v14) && !is.na(v13) && round(v13, dec) != round(v14, dec), source, note)
}, by = .(metric, level)]
safe_write_csv(out, file.path(ccdb_output_dir("tables"), "inspire_v1_4_2_update.csv"))
print(out[, .(metric, level, review_value_charted, v1_3 = round(v1_3_reproduced, 3), v1_4_2 = round(v1_4_2_reproduced, 3), v1_4_2_for_review, changed)])
