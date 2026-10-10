# =============================================================================
# 08_treatments_and_support.R - organ support and treatment flags
#
# `ds$support` holds admission_id x support_type (0/1). `meta$support_available`
# lists which support types the database can ascertain at all; a type absent from
# that list is reported as UNAVAILABLE rather than as 0%.
# `meta$support_scope` is "icu" (flags describe ICU care; denominator = ICU
# admissions) or "hospital" (denominator = all admissions).
# =============================================================================

SUPPORT_LABELS <- c(mech_vent = "Invasive mechanical ventilation",
                    rrt = "Renal replacement therapy",
                    vasopressor = "Vasopressor / inotrope infusion",
                    intubation = "Endotracheal intubation",
                    tracheostomy = "Tracheostomy")

summarise_support <- function(ds) {
  db <- ds$meta$db_id
  avail <- ds$meta$support_available %||% character()
  scope <- ds$meta$support_scope %||% "icu"
  by_stratum(ds, function(a, st) {
    ids <- if (identical(scope, "icu")) a[icu_flag == 1L, admission_id] else a$admission_id
    D <- length(ids)
    out <- lapply(names(SUPPORT_LABELS), function(ty) {
      if (!ty %in% avail)
        return(stat_unavailable(db, st, "Organ support", SUPPORT_LABELS[[ty]],
                                ds$meta$support_unavailable_note %||% "not ascertainable in this database"))
      s <- ds$support[support_type == ty & admission_id %in% ids]
      v <- merge(data.table::data.table(admission_id = ids), s[, .(admission_id, value)],
                 by = "admission_id", all.x = TRUE)
      # ascertainable but no record => 0 (absence of a charted/procedure record)
      v[is.na(value), value := 0L]
      stat_binary(v$value, db, st, "Organ support", SUPPORT_LABELS[[ty]], denominator = D,
                  note = paste0("scope: ", scope, "; ", ds$meta$support_definition[[ty]] %||% "definition: see adapter"))
    })
    data.table::rbindlist(out, use.names = TRUE, fill = TRUE)
  })
}
