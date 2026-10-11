# =============================================================================
# 03_variable_harmonization.R - the harmonised dataset contract, unit
# conversion, plausibility limits, comorbidity flagging and validation.
#
# HARMONISED DATASET (what every adapter returns from adapter_build()):
#   meta         list: db_id, version, index_definition, notes ...
#   flow         patient-flow table (flow_new()/flow_add())
#   admission    one row per hospital admission (see finalize_admission())
#   icu_stay     one row per ICU stay (may be empty)
#   diagnosis    admission_id, code, code_system ("ICD9" | "ICD10")
#   direct_flags admission_id, comorbidity, value   (non-ICD sources, optional)
#   measurements first value per admission x analyte inside the index window
#   support      admission_id, support_type, value  (mech_vent, rrt, ...)
#   severity     admission_id, score, value
#   availability domain-level statement of what the database does/doesn't have
# =============================================================================

read_dictionary <- function(name) {
  f <- ccdb_path("dictionaries", paste0(name, ".csv"))
  if (!file.exists(f)) ccdb_stop("Dictionary not found: ", f)
  data.table::fread(f, encoding = "UTF-8", na.strings = c("", "NA"))
}

# ---- units ----------------------------------------------------------------------

#' Normalise a unit string for matching: lower case, no spaces, micro/mu -> u.
norm_unit <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[µμ]", "u", x)
  x <- gsub("×", "x", x)
  x <- gsub("℃", "degc", x)          # single-glyph degree-Celsius sign
  x <- gsub("ˆ", "^", x)             # modifier circumflex used as a caret (e.g. "10ˆ3/uL")
  x <- gsub("ˆ", "^", x)             # modifier circumflex used as a caret, e.g. "10<U+02C6>3/uL"
  x <- gsub("°", "deg", x)
  x <- gsub("\\s+", "", x)
  x
}

#' Convert a long measurement table to canonical units.
#'
#' `dt` needs: analyte, value (numeric), unit (character, may be NA).
#' Adds value_canon and unit_status:
#'   "ok"       unit recognised for that analyte (converted if needed)
#'   "missing"  unit NA/blank and `assume_canonical` is FALSE -> value_canon = NA
#'   "assumed"  unit NA/blank and assume_canonical TRUE        -> value kept unchanged
#'   "unknown"  unit present but not in dictionaries/unit_conversions.csv -> NA
#' Unexpected units are therefore counted, never silently passed through.
to_canonical <- function(dt, assume_canonical = character()) {
  uc <- read_dictionary("unit_conversions")
  uc[, from_norm := norm_unit(from_unit)]
  uc <- unique(uc[, .(analyte, from_norm, factor, offset)], by = c("analyte", "from_norm"))
  d <- data.table::copy(dt)
  d[, unit_norm := norm_unit(unit)]
  d[unit_norm %in% c("", "na", "nan", "null"), unit_norm := NA_character_]
  d <- merge(d, uc, by.x = c("analyte", "unit_norm"), by.y = c("analyte", "from_norm"),
             all.x = TRUE, sort = FALSE)
  d[, unit_status := data.table::fcase(
    !is.na(factor),                                   "ok",
    is.na(unit_norm) & analyte %in% assume_canonical, "assumed",
    is.na(unit_norm),                                 "missing",
    default =                                         "unknown")]
  d[unit_status == "ok",      value_canon := value * factor + offset]
  d[unit_status == "assumed", value_canon := value]
  d[!unit_status %in% c("ok", "assumed"), value_canon := NA_real_]
  d[, c("factor", "offset") := NULL]
  d[]
}

#' Set values outside the analyte's plausible range to NA (counted, not dropped).
apply_plausibility <- function(dt, value_col = "value_canon") {
  ad <- read_dictionary("analyte_definitions")[, .(analyte, plausible_min, plausible_max)]
  d <- merge(dt, ad, by = "analyte", all.x = TRUE, sort = FALSE)
  d[, implausible := !is.na(get(value_col)) & !is.na(plausible_min) &
       (get(value_col) < plausible_min | get(value_col) > plausible_max)]
  d[implausible == TRUE, (value_col) := NA_real_]
  d[, c("plausible_min", "plausible_max") := NULL]
  d[]
}

# ---- simple code harmonisation -----------------------------------------------------

#' Map a vector of sex labels to "M" / "F" / NA. Numeric or coded values must be
#' resolved by the adapter (e.g. SICdb 735/736) and passed in as labels.
harmonize_sex <- function(x) {
  y <- tolower(trimws(as.character(x)))
  data.table::fcase(
    y %in% c("m", "male", "man", "mannelijk", "boy"),                 "M",
    y %in% c("f", "female", "woman", "vrouw", "vrouwelijk", "girl"),  "F",
    default = NA_character_)
}

# ---- comorbidities -----------------------------------------------------------------

#' ICD codes with punctuation removed and upper-cased: "I67.1" -> "I671".
normalise_icd <- function(x) toupper(gsub("[^A-Za-z0-9]", "", as.character(x)))

#' Flag comorbidities from coded diagnoses.
#'
#' `diagnosis`: admission_id, code, code_system ("ICD9" | "ICD10").
#' Returns one row per admission in `admission_ids` with 0/1 flags for every
#' definition in dictionaries/comorbidity_definitions.csv, plus
#' `dx_data_available` (1 if the admission has >= 1 code of a usable system).
#' An admission with no recorded code gets flags of 0 AND dx_data_available = 0
#' so the denominator question is never hidden (Jinhua convention: absent = 0).
flag_comorbidities <- function(diagnosis, admission_ids) {
  defs <- read_dictionary("comorbidity_definitions")
  out <- data.table::data.table(admission_id = unique(admission_ids))
  if (!nrow(diagnosis)) {
    out[, (defs$comorbidity) := 0L]; out[, dx_data_available := 0L]
    return(out[])
  }
  dx <- unique(data.table::copy(diagnosis)[, .(admission_id, code = normalise_icd(code), code_system)])
  dx <- dx[nzchar(code) & !is.na(code) & code_system %in% c("ICD9", "ICD10")]
  codes <- unique(dx[, .(code, code_system)])
  for (i in seq_len(nrow(defs))) {
    nm <- defs$comorbidity[i]
    hit10 <- codes[code_system == "ICD10" & grepl(defs$icd10_regex[i], code), code]
    hit9  <- codes[code_system == "ICD9"  & !is.na(defs$icd9_regex[i]) &
                   grepl(defs$icd9_regex[i], code), code]
    hit_ids <- unique(c(dx[code_system == "ICD10" & code %in% hit10, admission_id],
                        dx[code_system == "ICD9"  & code %in% hit9,  admission_id]))
    out[, (nm) := as.integer(admission_id %in% hit_ids)]
  }
  out[, dx_data_available := as.integer(admission_id %in% dx$admission_id)]
  out[, n_comorbidities := rowSums(.SD), .SDcols = defs$comorbidity]
  out[]
}

# ---- contract validation -------------------------------------------------------------

SCHEMA_ADMISSION <- c(db_id = "character", patient_id = "character", admission_id = "character",
                      age_years = "numeric", sex = "character", hosp_los_days = "numeric",
                      hosp_death = "integer", icu_flag = "integer", n_icu_stays = "integer")
SCHEMA_ICU_STAY  <- c(db_id = "character", patient_id = "character", admission_id = "character",
                      stay_id = "character", icu_los_days = "numeric")
SCHEMA_DIAGNOSIS <- c(admission_id = "character", code = "character", code_system = "character")
SCHEMA_MEASURE   <- c(admission_id = "character", analyte = "character", value = "numeric",
                      hours_from_index = "numeric")

check_cols <- function(dt, schema, label) {
  res <- list()
  miss <- setdiff(names(schema), names(dt))
  if (length(miss)) {
    res[[length(res) + 1]] <- list(check = paste0(label, ": required columns"), status = "FAIL",
                                   detail = paste("missing:", paste(miss, collapse = ", ")))
    return(res)
  }
  for (cl in names(schema)) {
    ok <- switch(schema[[cl]],
                 character = is.character(dt[[cl]]),
                 numeric   = is.numeric(dt[[cl]]),
                 integer   = is.integer(dt[[cl]]) || is.logical(dt[[cl]]),
                 TRUE)
    if (!ok) res[[length(res) + 1]] <- list(
      check = paste0(label, ": type of ", cl), status = "FAIL",
      detail = paste0("expected ", schema[[cl]], ", got ", class(dt[[cl]])[1]))
  }
  res
}

#' Validate a harmonised dataset. Returns a data.table of checks; stops if any FAIL
#' and `stop_on_fail`. WARN = analytically important but not contract-breaking.
validate_harmonized <- function(ds, stop_on_fail = TRUE) {
  R <- list()
  add <- function(check, status, detail = "") R[[length(R) + 1]] <<- list(check = check, status = status, detail = detail)
  need <- c("meta", "flow", "admission", "icu_stay", "diagnosis", "measurements",
            "support", "severity", "availability")
  miss <- setdiff(need, names(ds))
  if (length(miss)) add("dataset elements", "FAIL", paste("missing:", paste(miss, collapse = ", ")))
  else add("dataset elements", "PASS")
  if (length(miss)) {
    out <- data.table::rbindlist(R)
    if (stop_on_fail) ccdb_stop("Harmonised dataset invalid: ", out$detail[1])
    return(out)
  }
  adm <- ds$admission; icu <- ds$icu_stay

  R <- c(R, check_cols(adm, SCHEMA_ADMISSION, "admission"))
  R <- c(R, check_cols(icu, SCHEMA_ICU_STAY, "icu_stay"))
  if (nrow(ds$diagnosis))    R <- c(R, check_cols(ds$diagnosis, SCHEMA_DIAGNOSIS, "diagnosis"))
  if (nrow(ds$measurements)) R <- c(R, check_cols(ds$measurements, SCHEMA_MEASURE, "measurements"))

  # keys
  dup <- adm[, .N, by = admission_id][N > 1L]
  add("admission_id unique", if (nrow(dup)) "FAIL" else "PASS",
      if (nrow(dup)) paste(nrow(dup), "duplicated ids") else "")
  add("admission keys non-missing", if (anyNA(adm$admission_id) || anyNA(adm$patient_id)) "FAIL" else "PASS")
  if (nrow(icu)) {
    dups <- icu[, .N, by = stay_id][N > 1L]
    add("stay_id unique", if (nrow(dups)) "FAIL" else "PASS")
    orphan <- setdiff(icu$admission_id, adm$admission_id)
    add("icu_stay -> admission integrity", if (length(orphan)) "FAIL" else "PASS",
        if (length(orphan)) paste(length(orphan), "orphan stays") else "")
  }
  if (nrow(ds$diagnosis)) {
    orphan <- setdiff(ds$diagnosis$admission_id, adm$admission_id)
    add("diagnosis -> admission integrity", if (length(orphan)) "FAIL" else "PASS")
    badsys <- setdiff(unique(ds$diagnosis$code_system), c("ICD9", "ICD10"))
    add("diagnosis code_system values", if (length(badsys)) "FAIL" else "PASS", paste(badsys, collapse = ","))
  }
  if (nrow(ds$measurements)) {
    orphan <- setdiff(ds$measurements$admission_id, adm$admission_id)
    add("measurements -> admission integrity", if (length(orphan)) "FAIL" else "PASS")
    unk <- setdiff(unique(ds$measurements$analyte), read_dictionary("analyte_definitions")$analyte)
    add("measurement analytes in dictionary", if (length(unk)) "FAIL" else "PASS", paste(unk, collapse = ","))
    ad <- read_dictionary("analyte_definitions")
    mm <- merge(ds$measurements, ad[, .(analyte, plausible_min, plausible_max)], by = "analyte")
    nbad <- mm[value < plausible_min | value > plausible_max, .N]
    add("measurements within plausible range", if (nbad) "FAIL" else "PASS", if (nbad) paste(nbad, "outside") else "")
  }

  if (!is.null(ds$followup_death)) {
    fd <- ds$followup_death
    add("followup_death columns", if (all(c("admission_id", "death_h", "discharge_h", "surgery_end_h") %in% names(fd))) "PASS" else "FAIL")
    add("followup_death admission_id unique and known", if (!anyDuplicated(fd$admission_id) && all(fd$admission_id %in% adm$admission_id)) "PASS" else "FAIL")
  }

  # values
  add("sex coding (M/F/NA)", if (all(adm$sex %in% c("M", "F", NA))) "PASS" else "FAIL")
  add("hosp_death coding (0/1/NA)", if (all(adm$hosp_death %in% c(0L, 1L, NA))) "PASS" else "FAIL")
  add("icu_flag consistent with icu_stay",
      if (all(adm$icu_flag == as.integer(adm$admission_id %in% icu$admission_id))) "PASS" else "FAIL")
  add("hospital LOS non-negative", if (any(adm$hosp_los_days < 0, na.rm = TRUE)) "WARN" else "PASS",
      paste(sum(adm$hosp_los_days < 0, na.rm = TRUE), "negative"))
  add("age plausible (0-120)", if (any(adm$age_years < 0 | adm$age_years > 120, na.rm = TRUE)) "WARN" else "PASS",
      paste(sum(adm$age_years < 0 | adm$age_years > 120, na.rm = TRUE), "outside"))
  if (nrow(icu)) add("ICU LOS non-negative", if (any(icu$icu_los_days < 0, na.rm = TRUE)) "WARN" else "PASS")

  out <- data.table::rbindlist(R, fill = TRUE)
  nfail <- sum(out$status == "FAIL")
  if (nfail && stop_on_fail)
    ccdb_stop("Harmonised dataset failed ", nfail, " check(s): ",
              paste(out[status == "FAIL", check], collapse = "; "))
  out[]
}

#' An empty-but-valid table for each optional element, so adapters can omit what
#' their database does not have without breaking the contract.
empty_diagnosis    <- function() data.table::data.table(admission_id = character(), code = character(), code_system = character())
empty_measurements <- function() data.table::data.table(admission_id = character(), stay_id = character(), analyte = character(), value = numeric(), hours_from_index = numeric(), n_in_window = integer())
empty_support      <- function() data.table::data.table(admission_id = character(), support_type = character(), value = integer())
empty_severity     <- function() data.table::data.table(admission_id = character(), score = character(), value = numeric())
#' Optional dated follow-up deaths (hours relative to the database's own admission time-zero, `meta$followup_admission_label`).
#' death_h: hours from admission to the recorded death (any source; NA = no death recorded); discharge_h: hours from admission to
#' discharge; surgery_end_h: hours from admission to the end of the index operation (perioperative databases only).
empty_followup_death <- function() data.table::data.table(admission_id = character(), death_h = numeric(), discharge_h = numeric(), surgery_end_h = numeric())
empty_icu_stay     <- function() data.table::data.table(db_id = character(), patient_id = character(), admission_id = character(), stay_id = character(), stay_seq = integer(), icu_los_days = numeric(), icu_unit = character(), icu_death = integer())

#' Read an item-mapping CSV shipped with an adapter (editable without touching code).
#' The `item` column is always read as character so numeric ids and labels are handled alike.
read_mapping <- function(db_id, file) {
  f <- ccdb_path("databases", db_id, file)
  if (!file.exists(f)) ccdb_stop("Mapping file not found: ", f)
  m <- data.table::fread(f, colClasses = "character", encoding = "UTF-8", na.strings = c("", "NA"))
  m[, item := as.character(item)]
  m[]
}
