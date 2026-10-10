#!/usr/bin/env Rscript
# Pre-push governance audit of everything git tracks (or would track).
#   Rscript scripts/audit_repo.R
# Exits with status 1 if anything suspicious is found. It is a safety net, not a substitute for reading the DUAs.
files <- system2("git", c("ls-files", "--cached", "--others", "--exclude-standard"), stdout = TRUE)
if (!length(files)) stop("No files found - run from inside the repository.")
problems <- character()
add <- function(...) problems <<- c(problems, paste0(...))

bad_ext <- "[.](rds|rda|rdata|parquet|feather|fst|sqlite|duckdb|db|gz|bz2|zip|tar|7z|vital|xlsx|xls|pem|key)$"
for (f in files[grepl(bad_ext, files, ignore.case = TRUE)]) add("data-like or secret-like extension tracked: ", f)

big <- files[file.exists(files) & file.size(files) > 2e6]
for (f in big) add("file larger than 2 MB: ", f, " (", round(file.size(f) / 1e6, 1), " MB)")

text_ext <- "[.](R|r|md|yml|yaml|csv|txt|cff|json|gitignore|gitattributes)$"
patterns <- c(
  absolute_windows_path = "[A-Za-z]:[/\\\\](Users|PhD|Program Files)",
  github_token          = "(ghp_|gho_|ghu_|ghs_|github_pat_)[A-Za-z0-9_]{20,}",
  private_key           = "-----BEGIN [A-Z ]*PRIVATE KEY-----",
  password_assignment   = "(?i)(password|passwd|secret|api[_-]?key|token)\\s*[:=]\\s*['\"][^'\"]{6,}['\"]")
allow_abs <- c("config/paths.example.yml", "scripts/audit_repo.R", "docs/data_governance.md", "docs/reproducibility.md")
for (f in setdiff(files[grepl(text_ext, files) & file.exists(files)], "scripts/audit_repo.R")) {   # the script defines the patterns
  txt <- tryCatch(readLines(f, warn = FALSE, encoding = "UTF-8"), error = function(e) character())
  for (nm in names(patterns)) {
    if (nm == "absolute_windows_path" && f %in% allow_abs) next
    hit <- grep(patterns[[nm]], txt, perl = TRUE)
    if (length(hit)) add(nm, " in ", f, " (line ", hit[1], ")")
  }
}
if (any(files == "config/paths.local.yml")) add("config/paths.local.yml is tracked")

if (length(problems)) {
  cat("AUDIT FAILED\n"); cat(paste0(" - ", problems, collapse = "\n"), "\n"); quit(status = 1)
}
cat(sprintf("AUDIT PASSED: %d files checked; no data-like files, secrets, large files or absolute local paths.\n", length(files)))
