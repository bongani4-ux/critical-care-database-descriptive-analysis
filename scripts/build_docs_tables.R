#!/usr/bin/env Rscript
# Build the generated documentation tables (docs/generated/*.md) from outputs/tables/.
# These contain AGGREGATE statistics only. Per docs/data_governance.md, review each database's data-use agreement
# before committing them; they are generated into docs/generated/, which is git-ignored by default.
#   Rscript scripts/build_docs_tables.R
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]), winslash = "/")) else getwd()
root <- normalizePath(file.path(script_dir, ".."), winslash = "/")
source(file.path(root, "R", "00_setup.R")); ccdb_init(root = root, quiet = TRUE)
library(data.table)
td <- ccdb_output_dir("tables"); gd <- ccdb_path("docs", "generated"); dir.create(gd, showWarnings = FALSE, recursive = TRUE)
reg <- read_registry()
dbs <- c(ccdb_cfg()$databases$reference, eligible_dbs())

md_table <- function(dt) {
  dt <- as.data.table(dt); dt[] <- lapply(dt, function(x) { x <- as.character(x); x[is.na(x)] <- "—"; gsub("\\|", "/", x) })
  c(paste0("| ", paste(names(dt), collapse = " | "), " |"), paste0("|", paste(rep("---", ncol(dt)), collapse = "|"), "|"),
    apply(dt, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}
write_md <- function(name, title, note, body) writeLines(c(paste0("# ", title), "", note, "", body, ""), file.path(gd, name), useBytes = TRUE)

res <- rbindlist(lapply(dbs, function(d) { f <- file.path(td, paste0(d, "_descriptive_results.csv")); if (file.exists(f)) fread(f, encoding = "UTF-8") }), fill = TRUE)
g <- function(d, v, st = "admission", field = "text", dom = NULL) {
  x <- res[db_id == d & stratum == st & variable == v]; if (!is.null(dom)) x <- x[domain == dom]
  if (!nrow(x)) return(NA_character_); as.character(x[[field]][1])
}

# ---- 1. cohort overview -------------------------------------------------------------------------------------------------
ov <- rbindlist(lapply(dbs, function(d) {
  r <- reg[db_id == d]
  data.table(Database = r$display_name, Version = r$version, Setting = r$setting,
             Admissions = g(d, "Admissions"), Patients = g(d, "Unique patients"), `ICU stays` = {
               x <- res[db_id == d & stratum == "admission" & variable == "ICU LOS, days (per ICU stay)"]; if (nrow(x) && !is.na(x$denominator[1]) && x$denominator[1] > 0) format(x$denominator[1], big.mark = ",") else NA },
             `ICU admission` = g(d, "ICU admission"), `Age, median (IQR)` = g(d, "Age, years"), `Male` = g(d, "Male sex"),
             `In-hospital death` = g(d, "In-hospital death"), `ICU death (per stay)` = g(d, "Death during ICU stay (per ICU stay)"),
             `Hospital LOS, d` = g(d, "Hospital LOS, days"), `ICU LOS, d (per stay)` = g(d, "ICU LOS, days (per ICU stay)"))
}))
write_md("cohort_overview.md", "Cohort overview (all admissions)",
         "Unit = hospital admission (see docs/methods.md for what that means per database). Denominators in `outputs/tables/*_descriptive_results.csv`. — = not available in the database.", md_table(ov))

# ---- 2. measurement coverage ------------------------------------------------------------------------------------------------------
mc <- res[stratum == "admission" & domain %in% c("vital", "lab") & stat == "median_iqr" & !grepl("measurements in window", variable)]
mc[, cell := fifelse(availability == "available", sprintf("%.0f%%", pct), "—")]
mw <- dcast(mc[, .(variable, db_id, cell)], variable ~ db_id, value.var = "cell")
ord <- intersect(dbs, names(mw)); setcolorder(mw, c("variable", ord))
write_md("measurement_coverage.md", "Coverage of the harmonised first-24-hour measurements",
         "% of units with an index time that have >= 1 valid value in [index, index + 24 h]. Index: first ICU admission (ICU databases), hospital admission (INSPIRE, VitalDB, MOVER-EPIC, Jinhua), OR start (MOVER-SIS). — = not extracted / not available (see mapping notes).", md_table(mw))

# ---- 3. variable comparability matrix -------------------------------------------------------------------------------------------------
vm <- fread(ccdb_path("dictionaries", "database_variable_mappings.csv"), encoding = "UTF-8")
code <- c("directly comparable" = "D", "comparable after harmonization" = "A", "partially comparable" = "P", "unavailable" = "—")
vm[, k := code[comparability]]
cm <- dcast(vm, variable ~ db_id, value.var = "k"); vars <- unique(vm$variable)
cm <- cm[match(vars, variable)]; setcolorder(cm, c("variable", intersect(dbs, names(cm))))
write_md("variable_comparability.md", "Variable comparability matrix",
         "D = directly comparable; A = comparable after harmonization (documented transformation); P = partially comparable (important limitation); — = unavailable. Source field and note for every cell: `dictionaries/database_variable_mappings.csv`.", md_table(cm))

# ---- 4. review comparison ------------------------------------------------------------------------------------------------------------
rv <- rbindlist(lapply(c(dbs, "inspire_v1_3"), function(d) { f <- file.path(td, paste0(d, "_review_comparison.csv")); if (file.exists(f)) fread(f, encoding = "UTF-8") }), fill = TRUE)
if (nrow(rv)) {
  rv[, `:=`(review_value = format(review_value, trim = TRUE), reproduced_value = ifelse(is.na(reproduced_value), NA, signif(reproduced_value, 5)))]
  write_md("review_comparison.md", "Reproduced values vs the Critical Care Database Review",
           "MATCH = equal at the review's own printed precision. `also_matches_at_level` = other unit of analysis at which the review's value would match. Explanations: docs/discrepancy_report.md.",
           md_table(rv[, .(db_id, metric, level, review_value, reproduced_value, status, also_matches_at_level, review_confidence)]))
}

# ---- 5. domain availability ----------------------------------------------------------------------------------------------------------------
av <- rbindlist(lapply(dbs, function(d) { f <- file.path(td, paste0(d, "_domain_availability.csv")); if (file.exists(f)) cbind(db_id = d, fread(f, encoding = "UTF-8")) }), fill = TRUE)
aw <- dcast(av, domain ~ db_id, value.var = "status"); ordd <- unique(av$domain); aw <- aw[match(ordd, domain)]; setcolorder(aw, c("domain", intersect(dbs, names(aw))))
write_md("domain_availability.md", "Domain availability", "Statement made by each adapter about what its database does and does not contain.", md_table(aw))
cat("written to", gd, ":", paste(list.files(gd), collapse = ", "), "\n")
