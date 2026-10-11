# =============================================================================
# 09_outcomes.R - mortality, length of stay and readmission
#
# Mortality is never merged across definitions (review Table 3 principle):
#   hosp_death          in-hospital death (database-specific ascertainment in meta)
#   icu_death           death during an ICU stay (stay level)
#   death_any_followup  death at any recorded follow-up (optional; mixes in- and
#                       post-discharge deaths, variable follow-up length)
# =============================================================================

summarise_outcomes <- function(ds) {
  db <- ds$meta$db_id
  icu <- ds$icu_stay
  by_stratum(ds, function(a, st) {
    N <- nrow(a)
    Nicu <- sum(a$icu_flag == 1L)
    s <- icu[admission_id %in% a$admission_id]
    out <- list()
    out[[1]] <- if (any(!is.na(a$hosp_death)))
      stat_binary(a$hosp_death, db, st, "Mortality", "In-hospital death", denominator = N,
                  note = ds$meta$hosp_death_definition %||% "")
    else stat_unavailable(db, st, "Mortality", "In-hospital death", ds$meta$hosp_death_definition %||% "hospital outcome not recorded")
    out[[2]] <- if ("icu_death" %in% names(s) && any(!is.na(s$icu_death)))
      stat_binary(s$icu_death, db, st, "Mortality", "Death during ICU stay (per ICU stay)",
                  denominator = nrow(s), note = ds$meta$icu_death_definition %||% "")
    else stat_unavailable(db, st, "Mortality", "Death during ICU stay (per ICU stay)",
                          "ICU mortality not ascertainable in this database")
    out[[3]] <- if ("death_any_followup" %in% names(a) && any(!is.na(a$death_any_followup)))
      stat_binary(a$death_any_followup, db, st, "Mortality", "Death at last recorded follow-up",
                  denominator = N, note = paste("mixes in-hospital and post-discharge deaths;", ds$meta$followup_note %||% ""))
    else stat_unavailable(db, st, "Mortality", "Death at last recorded follow-up",
                          "no post-discharge vital status")
    out[[4]] <- stat_cont(a$hosp_los_days, db, st, "Length of stay", "Hospital LOS, days", N, digits = 1,
                          note = ds$meta$hosp_los_definition %||% "")
    out[[5]] <- if (any(!is.na(a$hosp_los_days)))
      stat_binary(a$prolonged_hosp_los, db, st, "Length of stay",
                  sprintf("Hospital LOS > %d days", ccdb_cfg()$cohort$prolonged_stay$hospital_days),
                  denominator = sum(!is.na(a$hosp_los_days)))
    else stat_unavailable(db, st, "Length of stay", sprintf("Hospital LOS > %d days", ccdb_cfg()$cohort$prolonged_stay$hospital_days),
                          "hospital LOS not recorded")
    out[[6]] <- stat_cont(a[icu_flag == 1L]$icu_los_days, db, st, "Length of stay",
                          "ICU LOS, days (summed per ICU admission)", Nicu, digits = 2,
                          note = ds$meta$icu_los_definition %||% "")
    out[[7]] <- stat_cont(s$icu_los_days, db, st, "Length of stay", "ICU LOS, days (per ICU stay)",
                          nrow(s), digits = 2)
    out[[8]] <- if (any(!is.na(a[icu_flag == 1L]$icu_los_days)))
      stat_binary(a[icu_flag == 1L]$prolonged_icu_los, db, st, "Length of stay",
                  sprintf("ICU LOS > %d days", ccdb_cfg()$cohort$prolonged_stay$icu_days),
                  denominator = sum(!is.na(a[icu_flag == 1L]$icu_los_days)))
    else stat_unavailable(db, st, "Length of stay", sprintf("ICU LOS > %d days", ccdb_cfg()$cohort$prolonged_stay$icu_days), "ICU LOS not recorded")
    out[[9]] <- stat_binary(as.integer(a[icu_flag == 1L]$n_icu_stays > 1L), db, st, "Readmission",
                            "More than one ICU stay in the admission", denominator = Nicu,
                            note = "Jinhua definition of ICU readmission (>1 ICU episode)")
    if (st == "admission") {
      pt <- a[, .(multi = as.integer(.N > 1L)), by = patient_id]
      out[[10]] <- stat_binary(pt$multi, db, st, "Readmission", "Patients with > 1 hospital admission",
                               denominator = nrow(pt), note = "unit = patient")
    }
    if (any(!is.na(a$discharge_disposition)))
      out[[length(out) + 1]] <- stat_cat(a$discharge_disposition, db, st, "Outcomes", "Discharge disposition (harmonised)",
                                         denominator = N, note = "harmonised: home / facility / death / other / unknown")
    data.table::rbindlist(out, use.names = TRUE, fill = TRUE)
  })
}

# ---- mortality horizons: 30 / 90 / 365 days ---------------------------------------------------------------------------------
# Death within H days of an index event, over ALL units of the stratum (no censoring adjustment: follow-up completeness differs by
# database and is stated in meta$followup_note). A death recorded BEFORE the index is counted as a death within the horizon
# (this is the rule of the review team's INSPIRE/Zigong code: `(death - index) <= H`); the number is reported in the note.
# Index events: "admission" (database time-zero), "discharge", "surgery_end" (index operation; perioperative databases).
HORIZON_DAYS <- c(30L, 90L, 365L)
HORIZON_INDEX_LABEL <- function(ds, idx) switch(idx, admission = ds$meta$followup_admission_label %||% "hospital admission",
                                                discharge = "hospital discharge", surgery_end = "the end of the index operation")

#' For admissions `ids`: list(dead = 0/1 vector, ok = index known, n_before = deaths dated before the index).
death_within <- function(ds, ids, H, idx) {
  fd <- ds$followup_death
  f <- fd[match(ids, fd$admission_id)]
  ih <- switch(idx, admission = rep(0, length(ids)), discharge = f$discharge_h, surgery_end = f$surgery_end_h)
  delta <- f$death_h - ih
  list(dead = as.integer(!is.na(delta) & delta <= H * 24), ok = !is.na(ih) & !is.na(f$admission_id),
       n_before = sum(!is.na(delta) & delta < 0))
}

summarise_mortality_horizons <- function(ds) {
  db <- ds$meta$db_id; fd <- ds$followup_death
  by_stratum(ds, function(a, st) {
    if (is.null(fd) || !nrow(fd) || !any(!is.na(fd$death_h)))
      return(stat_unavailable(db, st, "Mortality horizons", "Death within 30 / 90 / 365 days of an index event",
                              "no dated post-discharge deaths in this database"))
    out <- list()
    for (idx in c("admission", "discharge", "surgery_end")) {
      f <- fd[match(a$admission_id, fd$admission_id)]
      has_idx <- switch(idx, admission = TRUE, discharge = any(!is.na(f$discharge_h)), surgery_end = any(!is.na(f$surgery_end_h)))
      if (!has_idx) next
      for (H in HORIZON_DAYS) {
        r <- death_within(ds, a$admission_id, H, idx)
        out[[length(out) + 1L]] <- stat_binary(r$dead[r$ok], db, st, "Mortality horizons",
          sprintf("Death within %d days of %s", H, HORIZON_INDEX_LABEL(ds, idx)), denominator = sum(r$ok),
          note = sprintf("%d death(s) dated before the index are counted; no censoring adjustment; %s",
                         r$n_before, ds$meta$followup_note %||% ""))
      }
    }
    data.table::rbindlist(out, use.names = TRUE, fill = TRUE)
  })
}
