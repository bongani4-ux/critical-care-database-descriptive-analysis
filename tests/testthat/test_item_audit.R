# Synthetic tests for the item-level audit helpers (R/15_data_dictionary.R)

test_that("long, wide and parquet-free audits count patients with numeric results, not rows", {
  skip_if_not_installed("arrow"); skip_if_not_installed("dplyr")
  tmp <- tempfile(fileext = ".csv")
  data.table::fwrite(data.table::data.table(
    pid = c("A", "A", "A", "B", "B", "C", "C"), item = c("hr", "hr", "na", "hr", "na", "hr", "na"),
    val = c("80", "82", "140", "x", "139", NA, "141")), tmp)
  a <- audit_long_items(tmp, "pid", "item", "val", "synthetic")
  s <- a[, .(rows = sum(n), pats = sum(nv > 0)), by = item][order(item)]
  expect_equal(s$item, c("hr", "na")); expect_equal(s$rows, c(4, 3)); expect_equal(s$pats, c(1, 3))   # 'x' and NA are not numeric results
  w <- tempfile(fileext = ".csv")
  data.table::fwrite(data.table::data.table(id = c("A", "A", "B"), t = c(1, 2, 1), hr = c(70, NA, 80), spo2 = c(NA, NA, 99)), w)
  aw <- audit_wide_items(w, "id", exclude = "t", label = "wide")
  sw <- aw[, .(pats = sum(nv > 0)), by = item][order(item)]
  expect_equal(sw$item, c("hr", "spo2")); expect_equal(sw$pats, c(2, 1))
})

test_that("items_dictionary reports valid n, completeness and repairs invalid UTF-8", {
  agg <- data.table::data.table(pid = c("A", "B", "A"), item = c("k", "k", "z\xe9"), n = c(2L, 1L, 1L), nv = c(2L, 1L, 1L))
  Encoding(agg$item) <- "unknown"
  d <- items_dictionary(agg, N = 4, info = NULL, upper = FALSE)
  expect_equal(d[`Variable Name` == "k"]$`Valid (n)`, 2); expect_equal(d[`Variable Name` == "k"]$`Completeness (%)`, 50)
  expect_equal(d[`Variable Name` == "k"]$`Missing Values (n)`, 2)
  expect_true(all(validUTF8(d$`Variable Name`)))
})

test_that("the audit spec file is well formed", {
  sp <- data.table::fread(ccdb_path("dictionaries", "item_audit_specs.csv"), colClasses = "character", na.strings = NULL)
  expect_true(all(sp$db_id %in% read_registry()$db_id))
  expect_true(all(sp$kind %in% c("long", "wide")) && all(sp$denominator != ""))
  expect_false(anyDuplicated(sp[, .(db_id, sheet)]) > 0)
  expect_true(all(sp$pid != ""))
})
