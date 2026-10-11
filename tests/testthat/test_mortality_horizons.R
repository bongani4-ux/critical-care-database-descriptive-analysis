# Synthetic-data tests: dated follow-up deaths -> 30/90/365-day mortality and the data dictionary

synthetic_followup <- function() {
  ds <- make_synthetic_ds()
  # hours from admission: A1 dies day 10 (240 h), A3 day 40 (960 h), A4 day 400 (9600 h), A5 dies before admission (-5 h); others none
  ds$followup_death <- data.table::data.table(
    admission_id = paste0("A", 1:8),
    death_h = c(240, NA, 960, 9600, -5, NA, NA, NA),
    discharge_h = c(48, 480, 120, 240, 24, 720, 96, 144), surgery_end_h = NA_real_)
  ds
}

test_that("death_within applies the (death - index) <= H days rule from each index", {
  ds <- synthetic_followup()
  ids <- ds$admission$admission_id
  adm30 <- death_within(ds, ids, 30L, "admission")
  expect_equal(adm30$dead, c(1L, 0L, 0L, 0L, 1L, 0L, 0L, 0L))        # A5's pre-admission death is counted (team-code rule)
  expect_equal(adm30$n_before, 1L)
  expect_equal(sum(death_within(ds, ids, 90L, "admission")$dead), 3L) # + A3 at 40 d
  expect_equal(sum(death_within(ds, ids, 365L, "admission")$dead), 3L)
  dis30 <- death_within(ds, ids, 30L, "discharge")                    # A3: 960 - 120 = 840 h = 35 d -> outside 30 d
  expect_equal(dis30$dead[3], 0L); expect_equal(dis30$dead[1], 1L)
  expect_false(any(death_within(ds, ids, 30L, "surgery_end")$ok))     # no surgery index in this dataset
})

test_that("horizon summaries use the stated denominators and the contract validates", {
  ds <- synthetic_followup()
  expect_false(any(validate_harmonized(ds, stop_on_fail = FALSE)$status == "FAIL"))
  h <- summarise_mortality_horizons(ds)
  r <- h[stratum == "admission" & variable == "Death within 30 days of hospital admission"]
  expect_equal(r$n, 2); expect_equal(r$denominator, 8)
  rp <- h[stratum == "patient" & variable == "Death within 365 days of hospital admission"]
  expect_equal(rp$denominator, 6)                                      # first admissions: P1..P6
  ds$followup_death <- NULL
  expect_equal(summarise_mortality_horizons(ds)[stratum == "patient"]$availability, "unavailable")
})

test_that("the review-metric hook computes horizon percentages", {
  ds <- synthetic_followup()
  expect_equal(compute_review_metric(ds, "death_30d_admission_pct", "admission"), 100 * 2 / 8)
  expect_true(is.na(compute_review_metric(ds, "death_30d_surgery_end_pct", "admission")))
})

test_that("data dictionary has INSPIRE-style columns, correct completeness and the horizon variables", {
  ds <- synthetic_followup()
  dd <- build_data_dictionary(ds)
  expect_true(all(c("Master", "Outcomes") %in% dd$overview$`Sheet Name`))
  expect_equal(names(dd$sheets$Master), c("Variable Name", "Variable Type", "Variable Description", "Missing Values (n)", "Valid (n)",
                                         "Completeness (%)", "Notes", "Unit"))
  sx <- dd$sheets$Master[`Variable Name` == "sex"]
  expect_equal(sx$`Missing Values (n)`, 1); expect_equal(sx$`Valid (n)`, 7); expect_equal(sx$`Completeness (%)`, 87.5)
  expect_true("death_30d_admission" %in% dd$sheets$Outcomes$`Variable Name`)
  expect_equal(dd$overview[`Sheet Name` == "Master"]$`N Rows`, 8)
})
