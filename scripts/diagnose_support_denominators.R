# Diagnostic (hypothesis test, NOT a result): does any natural denominator reproduce the review's organ-support percentages?
# Run from the repository root after the databases have been built: Rscript scripts/diagnose_support_denominators.R
root <- normalizePath(".", winslash = "/"); source("R/00_setup.R"); ccdb_init(root = root); options(width = 200)
ref <- data.table::fread("review_reproduction/charted_values/04_organ_support.csv")
ids <- c("MIMIC-IV" = "mimic_iv", "eICU-CRD" = "eicu_crd", "NWICU" = "nwicu", "HiRID" = "hirid", "SICdb" = "sicdb", "AmsterdamUMCdb" = "amsterdamumcdb", "Zigong (ZFPH)" = "zigong")
out <- list()
for (nm in names(ids)) {
  ds <- readRDS(file.path("derived", ids[[nm]], "harmonized.rds")); adm <- ds$admission; icu <- ds$icu_stay; sp <- ds$support
  for (ty in c("mech_vent", "vasopressor", "rrt")) {
    if (!ty %in% ds$meta$support_available) next
    ev <- sp[support_type == ty & value == 1L, unique(admission_id)]
    pat_any <- function(a) adm[admission_id %in% a, unique(patient_id)]
    v <- c(
      icu_adm_first = 100 * mean(adm[is_first_admission == 1L & icu_flag == 1L, admission_id] %in% ev),
      icu_adm_all   = 100 * mean(adm[icu_flag == 1L, admission_id] %in% ev),
      icu_stays     = 100 * mean(icu$admission_id %in% ev),
      all_adm_first = 100 * mean(adm[is_first_admission == 1L, admission_id] %in% ev),
      all_adm       = 100 * mean(adm$admission_id %in% ev),
      icu_pat_any   = 100 * mean(adm[icu_flag == 1L, unique(patient_id)] %in% pat_any(ev)))
    col <- c(mech_vent = "mechanical_ventilation_pct", vasopressor = "vasopressors_pct", rrt = "renal_replacement_pct")[[ty]]
    r <- ref[database == nm][[col]]
    out[[length(out) + 1]] <- data.table::data.table(db = nm, support = ty, review = r, t(round(v, 1)),
                                                    best = names(v)[which.min(abs(v - r))], hit = any(round(v, 1) == r))
  }
}
print(data.table::rbindlist(out))
