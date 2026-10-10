# Synthetic-data tests for R/02_cohort_construction.R

test_that("finalize_admission derives ICU fields, first-admission flag and bands", {
  ds <- make_synthetic_ds(); a <- ds$admission
  expect_equal(a[admission_id == "A2", icu_flag], 1L)
  expect_equal(a[admission_id == "A1", icu_flag], 0L)
  expect_equal(a[admission_id == "A4", n_icu_stays], 2L)
  expect_equal(a[admission_id == "A4", icu_los_days], 5)               # 1 + 4, summed per admission
  expect_true(is.na(a[admission_id == "A1", icu_los_days]))
  # P1 has A1 (sort key 1) and A2 (2): only A1 is the first admission
  expect_equal(a[admission_id == "A1", is_first_admission], 1L)
  expect_equal(a[admission_id == "A2", is_first_admission], 0L)
  expect_equal(sum(a$is_first_admission), data.table::uniqueN(a$patient_id))
  expect_equal(as.character(a[admission_id == "A7", age_band]), "<18")   # age 17
  expect_equal(as.character(a[admission_id == "A8", age_band]), "18-39") # age 18 (left-closed band)
  expect_equal(as.character(a[admission_id == "A6", age_band]), ">=80")
  expect_equal(a[admission_id == "A2", prolonged_hosp_los], 1L)          # 20 days > 14
  expect_equal(a[admission_id == "A6", prolonged_icu_los], 0L)           # no ICU stay
})

test_that("a join that multiplies rows is detected, not silent", {
  dt <- data.table::data.table(id = c(1, 1, 2))
  expect_message(check_rows(dt, 2, "toy join"), "ROW COUNT CHANGED")
  expect_true(check_rows(data.table::data.table(id = 1:2), 2, "ok"))
})

test_that("integrity assertions stop with an informative message", {
  d <- data.table::data.table(k = c("a", "a", "b"), v = 1:3)
  expect_error(assert_unique(d, "k", "toy"), "duplicated key")
  expect_true(assert_unique(d, c("k", "v"), "toy"))
  expect_error(assert_no_missing(data.table::data.table(x = c(1, NA)), "x", "toy"), "missing")
  expect_error(assert_fk(data.table::data.table(a = c("x", "z")), data.table::data.table(a = "x"), "a", "toy"), "no parent")
})

test_that("patient flow counts come from the tables themselves", {
  ds <- make_synthetic_ds()
  expect_equal(ds$flow[.N, n_admissions], 8)
  expect_equal(ds$flow[.N, n_patients], 6)
  expect_equal(ds$flow[.N, n_icu_stays], 3)
})

test_that("registry and config agree and exclude out-of-scope resources", {
  reg <- read_registry()
  expect_equal(nrow(reg[role == "reference"]), 1L)
  expect_false(reg[role == "reference", in_review])                         # Jinhua is the reference, not a review entry
  expect_setequal(eligible_dbs(), reg[in_review == TRUE & role == "analysis", db_id])
  ex <- data.table::fread(ccdb_path("config", "excluded_resources.csv"))
  expect_true(all(c("MIMIC-BR", "Zhejiang PPH", "K-MIMIC") %in% ex$resource))
})
