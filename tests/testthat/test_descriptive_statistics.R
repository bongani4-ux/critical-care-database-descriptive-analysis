# Synthetic-data tests for the statistics modules (R/04-R/13)

test_that("continuous summaries match hand calculation, with explicit denominators", {
  x <- c(1, 2, 3, 4, NA)
  r <- stat_cont(x, "t", "admission", "d", "v", denominator = 5)
  expect_equal(r$median, 2.5); expect_equal(r$q1, 1.75); expect_equal(r$q3, 3.25)
  expect_equal(r$mean, 2.5); expect_equal(r$sd, stats::sd(1:4))
  expect_equal(r$n, 4); expect_equal(r$denominator, 5); expect_equal(r$n_missing, 1); expect_equal(r$pct, 80)
  expect_equal(r$text, "2.5 (1.8–3.2)")
})

test_that("binary and categorical summaries use the stated denominator", {
  b <- stat_binary(c(1L, 0L, 1L, NA), "t", "admission", "d", "v", denominator = 4)
  expect_equal(b$n, 2); expect_equal(b$denominator, 4); expect_equal(b$pct, 50); expect_equal(b$n_missing, 1)
  b2 <- stat_binary(c(1L, 0L, 1L, NA), "t", "admission", "d", "v")
  expect_equal(b2$denominator, 3)                                          # default: non-missing
  cat <- stat_cat(c("a", "a", "b", NA), "t", "admission", "d", "v", levels = c("a", "b", "c"), denominator = 4)
  expect_equal(cat$n, c(2, 1, 0)); expect_equal(cat$pct, c(50, 25, 0))
  expect_equal(stat_unavailable("t", "admission", "d", "v")$availability, "unavailable")
})

test_that("demographic and outcome tables reproduce the synthetic cohort exactly", {
  ds <- make_synthetic_ds()
  dem <- summarise_demographics(ds)
  g <- function(r, v, st = "admission", f = "n") r[stratum == st & variable == v][[f]][1]
  expect_equal(g(dem, "Admissions"), 8); expect_equal(g(dem, "Unique patients"), 6)
  expect_equal(g(dem, "Admissions", "patient"), 6)                         # first admissions only
  expect_equal(g(dem, "Male sex"), 3); expect_equal(g(dem, "Female sex"), 4)
  expect_equal(g(dem, "Male sex", f = "n_missing"), 1)                     # one unknown sex counted as missing
  out <- summarise_outcomes(ds)
  expect_equal(g(out, "In-hospital death"), 2); expect_equal(g(out, "In-hospital death", f = "denominator"), 8)
  expect_equal(g(out, "Hospital LOS, days", f = "median"), 5.5)
  expect_equal(g(out, "Death during ICU stay (per ICU stay)"), 1); expect_equal(g(out, "Death during ICU stay (per ICU stay)", f = "denominator"), 3)
  expect_equal(g(out, "More than one ICU stay in the admission"), 1)       # only A4
  expect_equal(g(out, "Patients with > 1 hospital admission"), 2)          # P1 and P6
})

test_that("measurement coverage uses ICU admissions as denominator for ICU-indexed data", {
  ds <- make_synthetic_ds()
  m <- summarise_measurements(ds)
  cr <- m[stratum == "admission" & grepl("^Creatinine", variable) & !grepl("window", variable)]
  expect_equal(cr$n, 2); expect_equal(cr$denominator, 2)                   # 2 ICU admissions (A2, A4)
  hr <- m[stratum == "admission" & grepl("^Heart rate", variable) & !grepl("window", variable)]
  expect_equal(hr$availability, "unavailable")                             # declared available but no values -> unavailable
  wbc <- m[stratum == "admission" & grepl("^White", variable)]
  expect_equal(wbc$availability, "unavailable")                            # not declared -> reported as unavailable, not 0
})

test_that("organ support: absent record = 0 only where the support type is ascertainable", {
  ds <- make_synthetic_ds()
  s <- summarise_support(ds)
  v <- s[stratum == "admission" & variable == "Invasive mechanical ventilation"]
  expect_equal(v$n, 1); expect_equal(v$denominator, 2)
  rrt <- s[stratum == "admission" & variable == "Renal replacement therapy"]
  expect_equal(rrt$availability, "unavailable")
})

test_that("the QC suite passes on a consistent dataset and detects a corrupted result table", {
  ds <- make_synthetic_ds()
  res <- compute_all_results(ds)
  qc <- qc_results_table(ds, res)
  expect_true(all(qc$status == "PASS"), info = paste(qc[status != "PASS", check], collapse = "; "))
  qr <- qc_recompute(ds, res)
  expect_true(all(qr$status == "PASS"))
  broken <- data.table::copy(res); broken[variable == "In-hospital death" & stratum == "admission", n := n + 1]
  qr2 <- qc_recompute(ds, broken)
  expect_true(any(qr2$status == "FAIL"))
})

test_that("results are deterministic (same input, same output)", {
  ds <- make_synthetic_ds()
  expect_identical(compute_all_results(ds)[, !"row_order"], compute_all_results(ds)[, !"row_order"])
})

test_that("review comparison applies the rounding rule and reports alternative levels", {
  expect_equal(decimals_of("3.2"), 1L); expect_equal(decimals_of("2790"), 0L); expect_equal(decimals_of("0.94"), 2L)
  p <- parse_ref_text("11,682 (56.9%)"); expect_equal(p$n, 11682); expect_equal(p$pct, 56.9)
  q <- parse_ref_text("61.0 (51.0–69.0)"); expect_equal(c(q$median, q$q1, q$q3), c(61, 51, 69))
  expect_equal(parse_ref_text("20,530")$n, 20530)
  ds <- make_synthetic_ds()
  expect_equal(compute_review_metric(ds, "n_patients", "patient"), 6)
  expect_equal(compute_review_metric(ds, "hosp_death_pct", "admission"), 25)
  # patient_any: P1 died in one of its admissions, P5 died; 2 of 6 patients
  expect_equal(compute_review_metric(ds, "hosp_death_pct", "patient_any"), 100 * 2 / 6)
})
