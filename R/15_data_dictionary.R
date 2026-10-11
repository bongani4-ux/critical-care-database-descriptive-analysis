# =============================================================================
# 15_data_dictionary.R - analysis-ready tables + data dictionary with completeness, one per database
#
# Mirrors the structure of the review team's INSPIRE data dictionary ("inspire data dictionary (summary).xlsx"):
#   Overview   one row per analysis-ready table (name, description, source, rows, variables)
#   <table>    one row per variable: Variable Name | Variable Type | Variable Description | Missing Values (n) |
#              Valid (n) | Completeness (%) | Notes | Unit
# The tables are built from the HARMONISED dataset, so the same dictionary exists for every database and the
# variables, units and definitions are comparable across them. Counts are results-derived aggregates and are
# written to outputs/dictionaries/ (git-ignored; release only after the DUA review in docs/data_governance.md).
# The analysis-ready tables themselves are patient-level and are never written to disk by this module.
# =============================================================================

DICT_COLUMNS <- c("Variable Name", "Variable Type", "Variable Description", "Missing Values (n)", "Valid (n)",
                  "Completeness (%)", "Notes", "Unit")

# descriptions for harmonised columns that are not in dictionaries/master_variable_dictionary.csv
DICT_EXTRA <- data.table::data.table(
  variable = c("db_id", "admit_sort_key", "admission_source", "period", "is_first_admission", "n_admissions_patient",
               "stay_id", "stay_seq", "icu_unit", "death_any_followup", "hours_from_index", "n_in_window",
               "death_h", "discharge_h", "surgery_end_h"),
  description = c("Database identifier", "Chronological ordering key of a patient's admissions (database clock)",
                  "Admission source / department as coded by the database", "Calendar period group, where released",
                  "1 = the patient's first admission in this database (patient-level stratum)", "Admissions of the patient in this database",
                  "ICU stay identifier", "Order of the ICU stay within the admission", "ICU / care unit as coded",
                  "Death at any recorded follow-up (mixes in-hospital and post-discharge deaths; variable follow-up)",
                  "Hours from the measurement index to the charted value", "Values available in the window (first value is used)",
                  "Hours from admission to recorded death (any source)", "Hours from admission to discharge",
                  "Hours from admission to the end of the index operation"),
  unit = c("-", "-", "-", "-", "0/1", "count", "-", "count", "-", "0/1", "h", "count", "h", "h", "h"))

dict_type <- function(x) if (is.integer(x)) "integer" else if (is.numeric(x)) "numeric" else if (is.logical(x)) "logical" else "character"

#' Dictionary rows for the columns of one wide table.
#' `desc`: named list column -> list(description, unit, notes, denominator) overriding the defaults.
dict_rows <- function(tbl, desc = list(), denominator = nrow(tbl), key = character()) {
  mv <- read_dictionary("master_variable_dictionary")
  rows <- lapply(names(tbl), function(cl) {
    x <- tbl[[cl]]
    d <- desc[[cl]]
    mvr <- mv[variable == cl]
    ex <- DICT_EXTRA[variable == cl]
    description <- d$description %||% (if (nrow(mvr)) mvr$label[1] else if (nrow(ex)) ex$description[1] else cl)
    if (is.null(d$description) && nrow(mvr) && nzchar(mvr$definition[1])) description <- paste0(mvr$label[1], ": ", mvr$definition[1])
    unit <- d$unit %||% (if (nrow(mvr) && !mvr$units_or_levels[1] %in% c("-", "")) mvr$units_or_levels[1] else if (nrow(ex)) ex$unit[1] else "-")
    notes <- d$notes %||% (if (cl %in% key) "Key" else if (nrow(mvr) && !is.na(mvr$notes[1])) mvr$notes[1] else "")
    den <- d$denominator %||% denominator
    valid <- sum(!is.na(x))
    data.table::data.table(`Variable Name` = cl, `Variable Type` = dict_type(x), `Variable Description` = description,
                           `Missing Values (n)` = max(den - valid, 0), `Valid (n)` = valid,
                           `Completeness (%)` = round(100 * valid / max(den, 1), 2), Notes = notes, Unit = unit)
  })
  data.table::rbindlist(rows)
}

#' Build the analysis-ready tables of a harmonised dataset (patient-level; kept in memory only).
build_analysis_tables <- function(ds) {
  adm <- data.table::copy(ds$admission); icu <- ds$icu_stay
  ids <- adm$admission_id
  tabs <- list(); desc <- list(); src <- list(); den <- list()

  # Master: one row per admission
  tabs$Master <- adm[, setdiff(names(adm), c("db_id")), with = FALSE]
  src$Master <- "admission (cohort construction); see docs/methods.md"
  den$Master <- nrow(adm)

  # ICU stays: one row per ICU stay
  if (nrow(icu)) { tabs$`ICU stays` <- icu[, setdiff(names(icu), "db_id"), with = FALSE]; src$`ICU stays` <- "ICU stay structure (adapter)"; den$`ICU stays` <- nrow(icu) }

  # Outcomes: one row per admission
  oc <- adm[, intersect(c("admission_id", "hosp_death", "death_any_followup", "hosp_los_days", "prolonged_hosp_los", "icu_los_days", "prolonged_icu_los"), names(adm)), with = FALSE]
  icud <- if (nrow(icu) && any(!is.na(icu$icu_death))) icu[, .(icu_death = as.integer(any(icu_death == 1L, na.rm = TRUE))), by = admission_id] else NULL
  if (!is.null(icud)) oc <- merge(oc, icud, by = "admission_id", all.x = TRUE, sort = FALSE)
  if (!is.null(ds$followup_death) && any(!is.na(ds$followup_death$death_h))) {
    for (idx in c("admission", "discharge", "surgery_end")) {
      f <- ds$followup_death[match(ids, admission_id)]
      if (!any(!is.na(switch(idx, admission = 0, discharge = f$discharge_h, surgery_end = f$surgery_end_h)))) next
      for (H in HORIZON_DAYS) {
        r <- death_within(ds, ids, H, idx)
        nm <- sprintf("death_%dd_%s", H, idx)
        oc[, (nm) := data.table::fifelse(r$ok, r$dead, NA_integer_)]
        desc[[nm]] <- list(description = sprintf("Death within %d days of %s (dated deaths only; no censoring adjustment)", H, HORIZON_INDEX_LABEL(ds, idx)),
                           unit = "0/1")
      }
    }
  }
  tabs$Outcomes <- oc; src$Outcomes <- "admission + ICU stay + dated follow-up deaths"; den$Outcomes <- nrow(oc)

  # Measurements (first valid value in the window): one row per admission in scope
  m <- ds$measurements
  if (nrow(m)) {
    ad <- read_dictionary("analyte_definitions")
    scope_ids <- if (identical(ds$meta$measurement_index, "first_icu_admission")) adm[icu_flag == 1L, admission_id] else ids
    w <- data.table::dcast(m[admission_id %in% scope_ids], admission_id ~ analyte, value.var = "value", fun.aggregate = function(v) v[1])
    w <- merge(data.table::data.table(admission_id = scope_ids), w, by = "admission_id", all.x = TRUE, sort = FALSE)
    for (an in setdiff(names(w), "admission_id")) {
      a <- ad[analyte == an]
      desc[[an]] <- list(description = paste0(a$label, " - first valid value in the window"), unit = a$canonical_unit,
                         notes = paste0(a$category, "; ", a$notes))
    }
    tabs$`Measurements (first window)` <- w; den$`Measurements (first window)` <- length(scope_ids)
    src$`Measurements (first window)` <- paste0("measurements; index = ", ds$meta$index_definition %||% "see meta")
  }

  # Comorbidities
  has_dx <- nrow(ds$diagnosis) > 0 || (!is.null(ds$direct_flags) && nrow(ds$direct_flags) > 0)
  if (has_dx) {
    cmx <- build_comorbidity_matrix(ds); defs <- read_dictionary("comorbidity_definitions")
    for (i in seq_len(nrow(defs))) desc[[defs$comorbidity[i]]] <- list(description = defs$label[i], unit = "0/1",
                                                                        notes = paste0("source: ", attr(cmx, "source")[[defs$comorbidity[i]]]))
    tabs$Comorbidities <- cmx; den$Comorbidities <- nrow(cmx); src$Comorbidities <- "diagnosis codes / direct flags (dictionaries/comorbidity_definitions.csv)"
  }

  # Organ support
  av <- ds$meta$support_available %||% character()
  if (length(av)) {
    sp <- data.table::data.table(admission_id = ids)
    for (ty in names(SUPPORT_LABELS)) {
      if (ty %in% av) { ev <- ds$support[support_type == ty & value == 1L, unique(admission_id)]; sp[, (ty) := as.integer(admission_id %in% ev)] }
      else sp[, (ty) := NA_integer_]
      desc[[ty]] <- list(description = SUPPORT_LABELS[[ty]], unit = "0/1",
                         notes = if (ty %in% av) ds$meta$support_definition[[ty]] %||% "" else "not ascertainable in this database")
    }
    tabs$`Organ support` <- sp; den$`Organ support` <- nrow(sp); src$`Organ support` <- "support events (adapter definitions in meta$support_definition)"
  }

  # Severity scores
  if (nrow(ds$severity)) {
    sv <- data.table::dcast(ds$severity, admission_id ~ score, value.var = "value", fun.aggregate = function(v) v[1])
    sv <- merge(data.table::data.table(admission_id = ids), sv, by = "admission_id", all.x = TRUE, sort = FALSE)
    for (sc in setdiff(names(sv), "admission_id")) desc[[sc]] <- list(description = paste0(sc, " (native score, not recalculated)"), unit = "points")
    tabs$Severity <- sv; den$Severity <- nrow(sv); src$Severity <- "severity (native scores)"
  }
  list(tables = tabs, desc = desc, source = src, denominator = den)
}

#' Data dictionary of one harmonised dataset: list(overview, sheets).
build_data_dictionary <- function(ds) {
  at <- build_analysis_tables(ds)
  sheets <- lapply(names(at$tables), function(nm) {
    tb <- at$tables[[nm]]
    dict_rows(tb, desc = at$desc, denominator = at$denominator[[nm]], key = c("patient_id", "admission_id", "stay_id"))
  })
  names(sheets) <- names(at$tables)
  if (nrow(ds$diagnosis)) {
    dg <- ds$diagnosis
    sheets$`Diagnosis (long)` <- dict_rows(dg, desc = list(admission_id = list(description = "Hospital admission identifier", notes = "Key; one admission = many rows"),
                                                         code = list(description = "Diagnosis code as recorded"),
                                                         code_system = list(description = "ICD10 / ICD9 (code_system)")),
                                          denominator = nrow(dg), key = "admission_id")
    at$tables$`Diagnosis (long)` <- dg[0]; at$source$`Diagnosis (long)` <- "diagnosis codes (long)"
  }
  ov <- data.table::rbindlist(lapply(seq_along(sheets), function(i) {
    nm <- names(sheets)[i]
    n_rows <- if (nm == "Diagnosis (long)") nrow(ds$diagnosis) else nrow(at$tables[[nm]])
    data.table::data.table(`#` = i, `Sheet Name` = nm, Source = at$source[[nm]] %||% "", `N Rows` = n_rows, Variables = nrow(sheets[[nm]]))
  }))
  list(overview = ov, sheets = sheets, db_id = ds$meta$db_id)
}

# ---- item-level audit of long event tables (labs, monitoring, medications, diagnosis codes) ---------------------------------
# The INSPIRE / PIC / Zigong dictionaries list EVERY item (not only the harmonised analytes) with the number of patients that
# have >= 1 value ("most recent value" wide tables). This reproduces those counts by streaming the raw long tables once; the
# patient-level wide tables are not materialised.

has_value <- function(v) if (is.character(v)) !is.na(v) & nzchar(v) else !is.na(v)
#' Numeric result present (text results such as '<0.5' or 'POSITIVE' do not count, as in the team's `as.numeric(VALUE)` wide tables).
has_num <- function(v) if (is.character(v)) !is.na(suppressWarnings(as.numeric(v))) else !is.na(v)

#' Accumulates (pid, item, n, nv) counts chunk by chunk and compacts them, so memory stays bounded.
new_pair_accumulator <- function() {
  acc <- NULL; pending <- list(); np <- 0
  compact <- function() {
    if (!length(pending)) return(invisible())
    acc <<- data.table::rbindlist(c(list(acc), pending))[, .(n = sum(n), nv = sum(nv)), by = .(pid, item)]
    pending <<- list(); np <<- 0
  }
  list(add = function(d) { if (is.null(d) || !nrow(d)) return(invisible()); pending[[length(pending) + 1L]] <<- d; np <<- np + nrow(d)
                           if (np > 4e6) compact() },
       result = function() { compact(); acc })
}

#' Stream a long table and return the patient x item counts (pid, item, n = rows, nv = rows with a value).
#' `where`: optional dplyr filter expression (string) applied by arrow before rows reach R.
audit_long_items <- function(path, pid, item, value = NULL, label = basename(path), where = NULL, engine = "arrow") {
  cols <- c(pid, item, value)
  ct <- do.call(readr::cols_only, stats::setNames(rep(list("c"), length(cols)), cols))
  ac <- new_pair_accumulator()
  flt <- if (identical(engine, "arrow")) function(d) { if (!is.null(where)) d <- dplyr::filter(d, !!rlang::parse_expr(where)); d } else NULL
  stream_file(path, function(ch) {
    data.table::setnames(ch, cols, c("pid", "item", if (!is.null(value)) "val"))
    if (is.null(value)) ch[, val := "1"]
    ac$add(ch[!is.na(item) & !is.na(pid), .(n = .N, nv = sum(has_num(val))), by = .(pid, item)])
    NULL
  }, col_types = ct, label = label, arrow_filter = flt)
  ac$result()
}

#' Wide table: every column in `cols` (default: all columns except `pid` and `exclude`) is an item.
audit_wide_items <- function(path, pid, cols = NULL, exclude = character(), label = basename(path), engine = "arrow") {
  hdr <- names(data.table::fread(path, nrows = 0L))
  hdr <- hdr[nzchar(hdr)]
  if (is.null(cols)) cols <- setdiff(hdr, c(pid, exclude, "V1"))
  cols <- intersect(cols, hdr)
  allc <- c(pid, cols)
  ct <- do.call(readr::cols_only, stats::setNames(rep(list("c"), length(allc)), allc))
  ac <- new_pair_accumulator()
  stream_file(path, function(ch) {
    out <- lapply(cols, function(cl) ch[!is.na(get(pid)) & has_value(get(cl)), .(item = cl, n = .N, nv = .N), by = .(pid = get(pid))])
    ac$add(data.table::rbindlist(out)[, .(pid, item, n, nv)])
    NULL
  }, col_types = ct, label = label, arrow_filter = if (identical(engine, "arrow")) function(d) d else NULL)
  ac$result()
}

#' Parquet dataset (HiRID observation / pharma tables).
audit_parquet_items <- function(dir, pid, item, value = NULL, label = basename(dir)) {
  cols <- c(pid, item, value)
  ac <- new_pair_accumulator()
  stream_parquet_dir(dir, function(ch) {
    data.table::setnames(ch, cols, c("pid", "item", if (!is.null(value)) "val"))
    if (is.null(value)) ch[, val := 1L]
    ch[, `:=`(pid = as.character(pid), item = as.character(item))]
    ac$add(ch[!is.na(item) & !is.na(pid), .(n = .N, nv = sum(has_num(val))), by = .(pid, item)])
    NULL
  }, arrow_filter = function(d) dplyr::select(d, dplyr::all_of(cols)), label = label)
  ac$result()
}

#' Dictionary rows (INSPIRE layout) for items: `agg` = pid x item counts, `N` = denominator (patients), `info` = item, description, unit.
items_dictionary <- function(agg, N, info = NULL, upper = TRUE) {
  fix_utf8 <- function(x) { bad <- !is.na(x) & !validUTF8(x); if (any(bad)) x[bad] <- iconv(x[bad], "latin1", "UTF-8", sub = "?"); x }
  agg[, item := fix_utf8(item)]
  s <- agg[, .(n_records = sum(n), n_patients = sum(nv > 0), med = as.numeric(stats::median(nv[nv > 0]))), by = item][order(-n_patients, item)]
  if (!is.null(info)) { info <- data.table::copy(info)[, `:=`(item = fix_utf8(item), description = fix_utf8(description), unit = fix_utf8(unit))]; s <- merge(s, info, by = "item", all.x = TRUE, sort = FALSE)[order(-n_patients, item)] }
  if (is.null(info)) s[, `:=`(description = NA_character_, unit = NA_character_)]
  s[, .(`Variable Name` = if (upper) toupper(item) else item, `Variable Type` = "numeric",
        `Variable Description` = data.table::fifelse(is.na(description), item, description),
        `Missing Values (n)` = N - n_patients, `Valid (n)` = n_patients, `Completeness (%)` = round(100 * n_patients / N, 2),
        Notes = sprintf("Records = %s; median records per patient with data = %s", format(n_records, big.mark = ","), format(round(med, 1), nsmall = 1)),
        Unit = data.table::fifelse(is.na(unit) | !nzchar(unit), "-", unit))]
}

# ---- spec-driven item audit (dictionaries/item_audit_specs.csv) ----------------------------------------------------------------
audit_resolve <- function(db_id, root, rel) {
  if (identical(root, "db")) return(db_file_any(db_id, rel))
  if (startsWith(root, "cfg:")) { d <- CCDB$paths[[sub("^cfg:", "", root)]]; if (is.null(d)) ccdb_stop("config path '", sub("^cfg:", "", root), "' is not set"); return(if (nzchar(rel)) file.path(d, rel) else d) }
  if (identical(root, "cache")) {
    cd <- CCDB$paths$cache_dir %||% file.path(CCDB$paths$data_root, "_extracted_cache")
    p <- file.path(cd, rel)
    if (!file.exists(p) && !dir.exists(p)) ccdb_stop("cached source not found: ", p)
    return(p)
  }
  ccdb_stop("unknown root '", root, "'")
}

audit_labels <- function(db_id, sp, root_for_labels = sp$root) {
  if (!nzchar(sp$label_table)) return(NULL)
  p <- tryCatch(audit_resolve(db_id, "db", sp$label_table), error = function(e) tryCatch(audit_resolve(db_id, "cache", sp$label_table), error = function(e2) NULL))
  if (is.null(p)) return(NULL)
  want <- c(sp$label_key, sp$label_text, if (nzchar(sp$label_unit)) sp$label_unit)
  lb <- data.table::fread(p, select = want, colClasses = "character", encoding = "UTF-8", showProgress = FALSE)
  data.table::setnames(lb, want, c("item", "description", if (nzchar(sp$label_unit)) "unit"))
  if (!"unit" %in% names(lb)) lb[, unit := NA_character_]
  unique(lb, by = "item")
}

audit_denominator <- function(db_id, den, ds) {
  if (startsWith(den, "units:")) {
    z <- strsplit(sub("^units:", "", den), ":")[[1]]
    return(data.table::uniqueN(data.table::fread(audit_resolve(db_id, "cache", z[1]), select = z[2], colClasses = "character", showProgress = FALSE)[[1]]))
  }
  switch(den, admissions = nrow(ds$admission), patients = data.table::uniqueN(ds$admission$patient_id),
         icu_admissions = sum(ds$admission$icu_flag == 1L), icu_stays = nrow(ds$icu_stay), ccdb_stop("unknown denominator '", den, "'"))
}

#' Item-level audit of the raw tables listed in dictionaries/item_audit_specs.csv for this database.
run_item_audit <- function(ds, only = NULL) {
  db <- sub("_v[0-9_]+$", "", ds$meta$db_id)
  spf <- ccdb_path("dictionaries", "item_audit_specs.csv")
  sp <- data.table::fread(spf, colClasses = "character", na.strings = NULL, encoding = "UTF-8")[db_id == db]
  if (!is.null(only)) sp <- sp[sheet %in% only]
  if (!nrow(sp)) return(NULL)
  sheets <- list(); src <- character(); nr <- numeric()
  for (i in seq_len(nrow(sp))) {
    s <- sp[i]
    cf <- file.path(ccdb_derived_dir(ds$meta$db_id), paste0("item_audit_", gsub("[^A-Za-z0-9]+", "_", s$sheet), ".rds"))
    fi <- tryCatch(file.info(audit_resolve(db, s$root, s$table)), error = function(e) NULL)
    key <- paste(unlist(s), if (!is.null(fi)) paste(fi$size, as.numeric(fi$mtime)), collapse = "|")
    if (file.exists(cf) && !identical(Sys.getenv("CCDB_REFRESH_AUDIT"), "1")) {
      old <- readRDS(cf)
      if (identical(old$key, key)) {
        sheets[[s$sheet]] <- old$d; src[s$sheet] <- s$table; nr[s$sheet] <- old$N
        log_msg("INFO", "[", db, "] item audit '", s$sheet, "': reused cached result (", nrow(old$d), " items)")
        next
      }
    }
    r <- tryCatch({
      path <- audit_resolve(db, s$root, s$table)
      lbl <- paste(db, s$sheet)
      agg <- if (identical(s$format, "parquet")) audit_parquet_items(path, s$pid, s$item, if (nzchar(s$value)) s$value, lbl)
             else if (identical(s$kind, "wide")) audit_wide_items(path, s$pid, if (nzchar(s$cols)) strsplit(s$cols, ",")[[1]], if (nzchar(s$exclude)) strsplit(s$exclude, ",")[[1]] else character(), lbl, s$engine)
             else audit_long_items(path, s$pid, s$item, if (nzchar(s$value)) s$value, lbl, if (nzchar(s$where)) s$where, s$engine)
      N <- audit_denominator(db, s$denominator, ds)
      d <- items_dictionary(agg, N, audit_labels(db, s), upper = FALSE)
      if (nzchar(s$note)) d[, Notes := paste0(Notes, "; ", s$note)]
      list(d = d, N = N)
    }, error = function(e) { log_msg("WARN", "[", db, "] item audit '", s$sheet, "' failed: ", conditionMessage(e)); NULL })
    if (is.null(r)) next
    sheets[[s$sheet]] <- r$d; src[s$sheet] <- s$table; nr[s$sheet] <- r$N
    safe_save_rds(list(key = key, d = r$d, N = r$N), cf)
    log_msg("INFO", "[", db, "] item audit '", s$sheet, "': ", nrow(r$d), " items")
  }
  list(sheets = sheets, source = src, n_rows = nr)
}

#' Write the dictionary: one xlsx (Overview + one sheet per table, like the INSPIRE workbook) and a long CSV.
write_data_dictionary <- function(ds, item_audit = FALSE) {
  dd <- build_data_dictionary(ds)
  if (item_audit) {
    ad <- tryCatch(load_adapter(sub("_v[0-9_]+$", "", ds$meta$db_id)), error = function(e) NULL)
    if (!is.null(ad) && exists("adapter_item_audit", envir = ad, inherits = FALSE)) {
      ex <- ad$adapter_item_audit(ccdb_cfg(), ds)
      for (nm in names(ex$sheets)) dd$sheets[[nm]] <- ex$sheets[[nm]]
      dd$overview <- rbind(dd$overview, data.table::data.table(`#` = nrow(dd$overview) + seq_along(ex$sheets), `Sheet Name` = names(ex$sheets),
                                                               Source = ex$source[names(ex$sheets)], `N Rows` = ex$n_rows[names(ex$sheets)],
                                                               Variables = vapply(ex$sheets, nrow, integer(1))))
    } else {
      ex <- run_item_audit(ds)
      if (!is.null(ex) && length(ex$sheets)) {
        for (nm in names(ex$sheets)) dd$sheets[[nm]] <- ex$sheets[[nm]]
        dd$overview <- rbind(dd$overview, data.table::data.table(`#` = nrow(dd$overview) + seq_along(ex$sheets), `Sheet Name` = names(ex$sheets),
                                                                 Source = ex$source[names(ex$sheets)], `N Rows` = ex$n_rows[names(ex$sheets)],
                                                                 Variables = vapply(ex$sheets, nrow, integer(1))))
      } else log_msg("INFO", "[", ds$meta$db_id, "] no item-level audit defined for this database")
    }
  }
  od <- ccdb_output_dir("dictionaries")
  long <- data.table::rbindlist(c(list(), lapply(names(dd$sheets), function(nm) cbind(Sheet = nm, dd$sheets[[nm]]))), use.names = TRUE)
  safe_write_csv(cbind(db_id = dd$db_id, long), file.path(od, paste0(dd$db_id, "_data_dictionary.csv")))
  if (requireNamespace("openxlsx", quietly = TRUE)) {
    wb <- openxlsx::createWorkbook()
    openxlsx::addWorksheet(wb, "Overview"); openxlsx::writeData(wb, "Overview", dd$overview)
    for (nm in names(dd$sheets)) {
      sn <- substr(gsub("[\\[\\]\\*\\?/\\\\:]", "-", nm), 1, 31)
      openxlsx::addWorksheet(wb, sn); openxlsx::writeData(wb, sn, dd$sheets[[nm]])
    }
    f <- file.path(od, paste0(dd$db_id, "_data_dictionary.xlsx"))
    openxlsx::saveWorkbook(wb, paste0(f, ".tmp.xlsx"), overwrite = TRUE); file.rename(paste0(f, ".tmp.xlsx"), f)
  }
  log_msg("INFO", "[", dd$db_id, "] data dictionary: ", nrow(dd$overview), " table(s), ", sum(dd$overview$Variables), " variable rows")
  invisible(dd)
}
