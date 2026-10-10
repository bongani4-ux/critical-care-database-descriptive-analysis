# =============================================================================
# 05_clinical_characteristics.R - admission and care-pathway characteristics
#
# Only harmonised categories are tabulated across databases. Database-specific
# labels (hospital units, departments, admission routes) are carried through in
# `admission_source` / `icu_unit` for within-database tables and are NOT pooled.
# =============================================================================

summarise_clinical <- function(ds) {
  db <- ds$meta$db_id
  sev <- ds$severity
  by_stratum(ds, function(a, st) {
    N <- nrow(a)
    out <- list()
    if (any(!is.na(a$admission_urgency))) {
      out[[length(out) + 1]] <- stat_cat(a$admission_urgency, db, st, "Admission", "Admission urgency",
                                         levels = c("emergency", "elective", "other"), denominator = N,
                                         note = "harmonised: emergency / elective / other")
    } else {
      out[[length(out) + 1]] <- stat_unavailable(db, st, "Admission", "Admission urgency")
    }
    out[[length(out) + 1]] <- stat_binary(a$icu_flag, db, st, "Care pathway", "ICU admission", denominator = N,
                                          note = if (isTRUE(ds$meta$icu_by_construction))
                                            "ICU admission by construction (every admission is an ICU admission)" else "")
    out[[length(out) + 1]] <- stat_cont(a[icu_flag == 1L]$n_icu_stays, db, st, "Care pathway",
                                        "ICU stays per ICU admission", denominator = sum(a$icu_flag == 1L),
                                        digits = 0)
    if ("surgery_flag" %in% names(a) && any(!is.na(a$surgery_flag))) {
      out[[length(out) + 1]] <- stat_binary(a$surgery_flag, db, st, "Care pathway", "Surgical admission",
                                            denominator = N, note = ds$meta$surgery_note %||% "")
    } else {
      out[[length(out) + 1]] <- stat_unavailable(db, st, "Care pathway", "Surgical admission")
    }
    # severity scores: tabulated only where the database provides them natively
    if (nrow(sev)) {
      for (sc in unique(sev$score)) {
        v <- sev[score == sc & admission_id %in% a$admission_id]
        out[[length(out) + 1]] <- stat_cont(v$value, db, st, "Severity", sc,
                                            denominator = sum(a$icu_flag == 1L),
                                            note = "native score; not recalculated; not comparable across scores")
      }
    } else {
      out[[length(out) + 1]] <- stat_unavailable(db, st, "Severity", "Native severity score",
                                                 "no native severity score; derivation (e.g. SOFA) not implemented in v0.1")
    }
    data.table::rbindlist(out, use.names = TRUE, fill = TRUE)
  })
}
