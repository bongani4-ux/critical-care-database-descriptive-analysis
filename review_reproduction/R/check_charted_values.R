#!/usr/bin/env Rscript
# Internal consistency of the charted values and of the search-flow counts. Exit status 1 on any inconsistency.
#   Rscript review_reproduction/R/check_charted_values.R [--values=<dir>]
args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
HERE <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]), winslash = "/")) else normalizePath("review_reproduction/R", winslash = "/")
ROOT <- normalizePath(file.path(HERE, ".."), winslash = "/")
va <- grep("^--values=", args, value = TRUE); VALUES <- if (length(va)) sub("^--values=", "", va[1]) else file.path(ROOT, "charted_values")
rd <- function(f) as.data.frame(data.table::fread(file.path(VALUES, f), na.strings = c("", "NA"), encoding = "UTF-8", check.names = FALSE, data.table = FALSE))
bad <- character()
chk <- function(ok, msg) if (!isTRUE(ok)) bad <<- c(bad, msg)

cohort <- rd("01_cohort.csv"); demo <- rd("02_demographics.csv"); mort <- rd("03_mortality.csv"); org <- rd("04_organ_support.csv")
dom <- rd("07_domain_coverage.csv"); ovr <- rd("08_overall_coverage.csv"); gv <- rd("05_granularity_vitals.csv"); gl <- rd("06_granularity_labs.csv")

# same databases everywhere
chk(setequal(cohort$database, demo$database), "01 and 02 list different databases")
chk(setequal(cohort$database, mort$database), "01 and 03 list different databases")
chk(all(org$database %in% cohort$database), "04 lists a database that is not in 01")
chk(all(setdiff(names(gv), "parameter") %in% cohort$database) && all(setdiff(names(gl), "parameter") %in% cohort$database), "05/06 list a database that is not in 01")
chk(all(setdiff(names(dom), c("domain_group", "n_subdomains")) %in% cohort$database), "07 lists a database that is not in 01")
# ranges
chk(all(demo$iqr_low <= demo$median_age_years & demo$median_age_years <= demo$iqr_high), "age median outside its IQR")
chk(all(demo$percent_male >= 0 & demo$percent_male <= 100), "percent male outside 0-100")
mp <- as.matrix(mort[, setdiff(names(mort), "database")]); chk(all(mp[!is.na(mp)] >= 0 & mp[!is.na(mp)] <= 100), "mortality outside 0-100")
chk(all(org[, -1][!is.na(org[, -1])] >= 0 & org[, -1][!is.na(org[, -1])] <= 100), "organ support outside 0-100")
# coverage arithmetic: documented subdomains = sum(round(pct/100 * size)); percent_of_85 = 100 * k / 85
dbs <- setdiff(names(dom), c("domain_group", "n_subdomains")); N <- sum(dom$n_subdomains); chk(N == 85, paste("subdomains sum to", N, "not 85"))
for (d in dbs) {
  k <- sum(round(dom[[d]] / 100 * dom$n_subdomains), na.rm = TRUE)
  chk(identical(as.integer(k), as.integer(ovr$subdomains_documented[ovr$database == d])), paste("documented subdomains differ for", d))
  chk(isTRUE(all.equal(round(100 * k / N, 1), ovr$percent_of_85[ovr$database == d])), paste("percent of 85 differs for", d))
}
# search-flow integrity (the review's own assertions)
fc <- jsonlite::read_json(file.path(ROOT, "data", "flow_counts.json"), simplifyVector = TRUE)
chk(fc$identified == fc$repo_raw + fc$pubmed_raw + fc$wos_raw + fc$epmc_raw + fc$arxiv_raw + fc$other_raw, "identified != sum of sources")
chk(fc$dupes == fc$repo_dupes + fc$epmc_dupes, "duplicates != repository + preprint duplicates")
chk(fc$screened == fc$identified - fc$dupes, "screened != identified - duplicates")
chk(fc$screen_excluded + fc$assessed == fc$screened, "screening exclusions + assessed != screened")
chk(fc$included + fc$not_charted + fc$excluded == fc$assessed, "included + not charted + excluded != assessed")
rs <- fc$reasons; n_reason <- if (is.matrix(rs)) sum(as.integer(rs[, 2])) else sum(as.integer(rs[[2]])); chk(n_reason == fc$excluded, "exclusion reasons do not sum to the excluded count")
chk(fc$included == nrow(cohort), "included resources != rows of 01_cohort.csv")

if (length(bad)) { cat("INCONSISTENT:\n  ", paste(bad, collapse = "\n  "), "\n", sep = ""); quit(status = 1) }
cat("OK: charted values, coverage arithmetic and search-flow counts are consistent.\n")
