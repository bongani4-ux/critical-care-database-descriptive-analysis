# Synthetic-data tests for R/03_variable_harmonization.R and the measurement engine in R/06

test_that("unit strings are normalised consistently", {
  expect_equal(norm_unit("µmol/L"), "umol/l")
  expect_equal(norm_unit("μmol/L"), "umol/l")
  expect_equal(norm_unit(" mg / dL "), "mg/dl")
  expect_equal(norm_unit("°C"), "degc")
  expect_equal(norm_unit("℃"), "degc")
  expect_equal(norm_unit("10ˆ3/µL"), "10^3/ul")
})

test_that("conversion to canonical units is exact and flags unexpected units", {
  d <- data.table::data.table(
    analyte = c("creatinine", "creatinine", "hemoglobin", "temp", "glucose", "sodium", "creatinine", "creatinine"),
    value   = c(1, 88.4,        140,          98.6,   100,       140,      1.2,          1.2),
    unit    = c("mg/dL", "umol/L", "g/L",     "degF", "mg/dL",  "mEq/L",  "furlongs",   NA))
  r <- to_canonical(d)
  expect_equal(r$value_canon[1], 88.4)
  expect_equal(r$value_canon[2], 88.4)
  expect_equal(r$value_canon[3], 14)
  expect_equal(r$value_canon[4], 37, tolerance = 1e-3)
  expect_equal(r$value_canon[5], 5.55, tolerance = 1e-3)
  expect_equal(r$value_canon[6], 140)
  expect_equal(r$unit_status[7], "unknown"); expect_true(is.na(r$value_canon[7]))
  expect_equal(r$unit_status[8], "missing"); expect_true(is.na(r$value_canon[8]))
  # a missing unit can be accepted only when the adapter says so explicitly
  r2 <- to_canonical(d[8], assume_canonical = "creatinine")
  expect_equal(r2$unit_status, "assumed"); expect_equal(r2$value_canon, 1.2)
})

test_that("implausible values are set to missing, not silently kept", {
  d <- data.table::data.table(analyte = c("creatinine", "creatinine", "hr"), value_canon = c(80, 99999, 500))
  r <- apply_plausibility(d)
  expect_equal(r$implausible, c(FALSE, TRUE, TRUE))
  expect_equal(is.na(r$value_canon), c(FALSE, TRUE, TRUE))
})

test_that("comorbidity flags handle ICD-9 and ICD-10, punctuation, and absent codes", {
  dx <- data.table::data.table(admission_id = c("A", "B", "C", "D", "D"),
                               code = c("I10", "401.9", "I67.1", "E87.1", "E878.0"),
                               code_system = c("ICD10", "ICD9", "ICD10", "ICD10", "ICD9"))
  fl <- flag_comorbidities(dx, c("A", "B", "C", "D", "Z"))
  g <- function(id, cm) fl[admission_id == id][[cm]]
  expect_equal(g("A", "HYPERTENSION"), 1L)           # ICD-10 I10
  expect_equal(g("B", "HYPERTENSION"), 1L)           # ICD-9 401.9
  expect_equal(g("C", "CEREBRAL_ANEURYSM"), 1L)      # 'I67.1' normalised to I671
  expect_equal(g("D", "ELECTROLYTE_DISORDER"), 1L)
  expect_equal(g("A", "DIABETES"), 0L)
  expect_equal(g("Z", "HYPERTENSION"), 0L); expect_equal(g("Z", "dx_data_available"), 0L)   # no codes: 0 AND flagged
  expect_equal(g("A", "dx_data_available"), 1L)
  # an ICD-9 E-code (E878.0) must NOT be read as ICD-10 E87 (electrolyte disorders)
  dx2 <- data.table::data.table(admission_id = "Q", code = "E878.0", code_system = "ICD9")
  expect_equal(flag_comorbidities(dx2, "Q")$ELECTROLYTE_DISORDER, 0L)
})

test_that("ICD-10 definitions in the dictionary equal the Jinhua originals after punctuation removal", {
  d <- read_dictionary("comorbidity_definitions")
  # behavioural equivalence: on every ICD-10 style code (letter + 2 digits, with 0-9 sub-codes) the original regex
  # applied to the DOTTED code must give the same answer as the dictionary regex applied to the punctuation-free code
  three <- as.vector(outer(LETTERS, sprintf("%02d", 0:99), paste0))
  dotted <- c(three, as.vector(outer(three, 0:9, function(a, b) paste0(a, ".", b))))
  plain <- normalise_icd(dotted)
  for (i in seq_len(nrow(d)))
    expect_identical(grepl(d$jinhua_original_regex[i], dotted), grepl(d$icd10_regex[i], plain),
                     info = d$comorbidity[i])
  expect_equal(nrow(d), 32L)
})

test_that("sex harmonisation maps known labels and refuses to guess codes", {
  expect_equal(harmonize_sex(c("Male", "F", "man", "Vrouw", "1", "Unknown", NA)), c("M", "F", "M", "F", NA, NA, NA))
})

test_that("first-in-window reduction picks the earliest valid value in canonical units", {
  chunk <- data.table::data.table(
    unit_key = c("A", "A", "A", "A", "B", "B"),
    item = c("cr", "cr", "cr", "cr", "cr", "hr"),
    time_hours = c(30, 5, 2, -3, 1, 1),                                  # A: -3 is before the index; 30 is after 24 h
    value = c(1.0, 2.0, 3.0, 9.0, 1500, 70), unit = c("mg/dL", "mg/dL", NA, "mg/dL", "mg/dL", NA))
  mapping <- data.table::data.table(item = c("cr", "hr"), analyte = c("creatinine", "hr"), source_unit = c("mg/dL", "/min"))
  index <- data.table::data.table(unit_key = c("A", "B"), index_hours = c(0, 0))
  r <- reduce_chunk_first_in_window(chunk, mapping, index, window_hours = 24, pre_index_hours = 0)
  a <- r[unit_key == "A" & analyte == "creatinine"]
  expect_equal(a$hours_from_index, 2)                                      # earliest inside [0, 24]
  expect_equal(a$value, 3 * 88.4)                                          # unit NA -> mapping unit mg/dL -> umol/L
  expect_equal(a$n_in_window, 2L)                                          # times 2 and 5 only
  expect_equal(nrow(r[unit_key == "B" & analyte == "creatinine"]), 0L)      # 1500 mg/dL is implausible -> dropped
  expect_equal(r[unit_key == "B" & analyte == "hr", value], 70)
})

test_that("combining chunks keeps the earliest value and sums the counts", {
  r <- data.table::data.table(unit_key = c("A", "A"), analyte = "hr", value = c(80, 75), hours_from_index = c(4, 1),
                              n_in_window = c(2L, 3L))
  out <- combine_first_in_window(r)
  expect_equal(out$value, 75); expect_equal(out$n_in_window, 5L); expect_equal(out$hours_from_index, 1)
})

test_that("fast timestamp parser equals POSIXct arithmetic", {
  x <- c("2180-07-23 14:00:00", "2101-01-01 00:00:01", "2209-12-31 23:59:59")
  expect_equal(fast_ts_hours(x), as.numeric(as.POSIXct(x, tz = "UTC")) / 3600, tolerance = 1e-9)
})

test_that("the harmonised-dataset validator catches contract violations", {
  ds <- make_synthetic_ds()
  ok <- validate_harmonized(ds, stop_on_fail = FALSE)
  expect_false(any(ok$status == "FAIL"))
  bad <- data.table::copy(ds); bad$admission <- rbind(bad$admission, bad$admission[1])
  expect_error(validate_harmonized(bad), "failed")
  bad2 <- data.table::copy(ds); bad2$admission <- data.table::copy(ds$admission); bad2$admission[1, sex := "X"]
  expect_error(validate_harmonized(bad2), "sex")
  bad3 <- data.table::copy(ds); bad3$icu_stay <- data.table::copy(ds$icu_stay); bad3$icu_stay[1, admission_id := "NOPE"]
  expect_error(validate_harmonized(bad3), "integrity")
  bad4 <- data.table::copy(ds); bad4$measurements <- data.table::copy(ds$measurements); bad4$measurements[1, value := 1e9]
  expect_error(validate_harmonized(bad4), "plausible")
})
