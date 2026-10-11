# Synthetic tests for the granularity rule (R/16_granularity.R)

test_that("time units convert to hours", {
  expect_equal(gran_time_hours(c("120", "60"), "min"), c(2, 1))
  expect_equal(gran_time_hours("7200", "sec"), 2)
  expect_equal(gran_time_hours("7200000", "ms"), 2)
  expect_equal(gran_time_hours("2.5", "hours"), 2.5)
  expect_equal(gran_time_hours("1970-01-01 02:30:00", "datetime"), 2.5)
  expect_error(gran_time_hours("1", "weeks"))
})

test_that("only records inside an ICU stay are counted, per stay, with wide and long tables", {
  skip_if_not_installed("arrow"); skip_if_not_installed("dplyr")
  d <- tempfile("gran"); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  old <- CCDB$paths$gran_test_dir; CCDB$paths$gran_test_dir <- d; on.exit(CCDB$paths$gran_test_dir <- old, add = TRUE)
  # long table: minutes from unit admission; stay S1 = [0, 2 h], stay S2 = [0, 1 h]
  data.table::fwrite(data.table::data.table(sid = c("S1", "S1", "S1", "S1", "S2", "S2", "S3"), item = c("hr", "hr", "hr", "na", "hr", "hr", "hr"),
                                            t = c(10, 60, 130, 30, 5, 70, 5)), file.path(d, "ev.csv"))   # 130 min is after S1 ends; 70 min after S2 ends; S3 unknown
  stays <- data.table::data.table(stay_id = c("S1", "S2"), skey = c("S1", "S2"), akey = c("A1", "A2"), pkey = NA_character_, start_h = 0, end_h = c(2, 1))
  sp <- data.table::data.table(db_id = "t", parameter = c("hr", "sodium"), group = c("vital", "lab"), root = "cfg:gran_test_dir", table = "ev.csv",
                               format = "csv", kind = "long", link = "skey", key_col = "sid", item_col = "item", items = c("hr", "na"), time_col = "t",
                               time_unit = "min", filter_col = "", filter_regex = "", note = "", engine = "arrow")
  r <- gran_pass("t", sp, stays)
  expect_equal(r[parameter == "hr"][order(stay_id)]$N, c(2L, 1L))       # S1: 10, 60 min; S2: 5 min
  expect_equal(r[parameter == "sodium"]$N, 1L)
  # wide table with an empty cell
  data.table::fwrite(data.table::data.table(sid = c("S1", "S1", "S2"), t = c(10, 20, 10), spo2 = c(97, NA, 98)), file.path(d, "w.csv"))
  sw <- data.table::copy(sp[1])[, `:=`(parameter = "spo2", table = "w.csv", kind = "wide", item_col = "", items = "spo2")]
  rw <- gran_pass("t", sw, stays)
  expect_equal(rw[order(stay_id)]$N, c(1L, 1L))
})

test_that("the granularity spec file is well formed", {
  sp <- data.table::fread(ccdb_path("dictionaries", "granularity_specs.csv"), colClasses = "character", na.strings = NULL)
  expect_true(all(sp$db_id %in% unname(GRAN_REVIEW_DB)))
  expect_true(all(sp$parameter %in% unname(GRAN_REVIEW_LABELS)))
  expect_true(all(sp$link %in% c("skey", "akey", "pkey")) && all(sp$time_unit %in% c("datetime", "min", "sec", "ms", "hours")))
  expect_true(all(sp$group %in% c("vital", "lab")))
})
