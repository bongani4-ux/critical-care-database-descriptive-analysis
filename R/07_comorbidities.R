# =============================================================================
# 07_comorbidities.R - comorbidity prevalence
#
# Source of each flag is recorded: ICD-coded (ICD-10 or the analyst-defined
# ICD-9-CM equivalents in dictionaries/comorbidity_definitions.csv) or a direct
# non-ICD flag supplied by the adapter (e.g. VitalDB pre-operative hypertension).
# Prevalence is reported over (i) all units (Jinhua convention: absent code = 0)
# and (ii) units with any coded diagnosis, so under-coding is visible.
# =============================================================================

#' Build the admission-level comorbidity matrix for a harmonised dataset.
build_comorbidity_matrix <- function(ds) {
  defs <- read_dictionary("comorbidity_definitions")
  ids <- ds$admission$admission_id
  fl <- flag_comorbidities(ds$diagnosis, ids)
  src <- stats::setNames(rep(if (nrow(ds$diagnosis)) "icd" else NA_character_, nrow(defs)), defs$comorbidity)
  df <- ds$direct_flags
  if (!is.null(df) && nrow(df)) {
    for (cm in intersect(unique(df$comorbidity), defs$comorbidity)) {
      v <- df[comorbidity == cm, .(admission_id, dv = as.integer(value))]
      fl <- merge(fl, v, by = "admission_id", all.x = TRUE, sort = FALSE)
      # a direct flag overrides ICD for that comorbidity; absent direct value = unknown
      fl[, (cm) := dv][, dv := NULL]
      src[[cm]] <- "direct flag"
    }
  }
  attr(fl, "source") <- src
  fl
}

summarise_comorbidities <- function(ds) {
  db <- ds$meta$db_id
  defs <- read_dictionary("comorbidity_definitions")
  has_any <- nrow(ds$diagnosis) > 0 || (!is.null(ds$direct_flags) && nrow(ds$direct_flags) > 0)
  by_stratum(ds, function(a, st) {
    if (!has_any)
      return(stat_unavailable(db, st, "Comorbidities", "Coded comorbidities",
                              ds$meta$comorbidity_note %||% "no diagnosis codes or comorbidity flags in this database"))
    fl <- build_comorbidity_matrix(ds)
    src <- attr(fl, "source")
    fl <- fl[admission_id %in% a$admission_id]
    N <- nrow(fl)
    out <- lapply(seq_len(nrow(defs)), function(i) {
      cm <- defs$comorbidity[i]
      if (is.na(src[[cm]]))
        return(stat_unavailable(db, st, "Comorbidities", defs$label[i], "no source for this comorbidity"))
      r <- stat_binary(fl[[cm]], db, st, "Comorbidities", defs$label[i], denominator = N,
                       note = paste0("source: ", src[[cm]]))
      if (identical(src[[cm]], "icd")) {
        r2 <- stat_binary(fl[dx_data_available == 1L][[cm]], db, st, "Comorbidities (coded units)",
                          defs$label[i], note = "denominator = units with >= 1 coded diagnosis")
        r <- data.table::rbindlist(list(r, r2), use.names = TRUE, fill = TRUE)
      }
      r
    })
    out[[length(out) + 1]] <- stat_binary(fl$dx_data_available, db, st, "Comorbidities",
                                          "Any coded diagnosis recorded", denominator = N,
                                          note = "coverage of coded diagnoses")
    # the count is only meaningful when every group comes from ICD codes
    if ("n_comorbidities" %in% names(fl) && all(src == "icd", na.rm = FALSE) && any(fl$dx_data_available == 1L))
      out[[length(out) + 1]] <- stat_cont(fl$n_comorbidities, db, st, "Comorbidities",
                                          sprintf("Comorbidity count (of %d defined groups)", nrow(defs)),
                                          denominator = N, digits = 0)
    data.table::rbindlist(out, use.names = TRUE, fill = TRUE)
  })
}
