# Run all tests:  Rscript tests/testthat.R   (from the project root)
# Tests use SYNTHETIC data only (tests/testthat/helper-synthetic.R); no patient data, no database access.
Sys.setenv(CCDB_TESTING = "true")
library(testthat)
test_dir("tests/testthat", reporter = "summary", stop_on_failure = TRUE)
