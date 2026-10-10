# =============================================================================
# 01_database_registry.R - which databases exist, where they are, what state
#
# The registry (config/database_registry.csv) is the single definition of the
# eligible set. Anything not listed there is out of scope by design.
# =============================================================================

read_registry <- function() {
  f <- ccdb_path("config", "database_registry.csv")
  r <- data.table::fread(f, na.strings = c("", "NA"), encoding = "UTF-8")
  r[, in_review := as.logical(in_review)]
  r[]
}

get_db <- function(db_id) {
  r <- read_registry()
  want <- db_id                       # avoid data.table column-name shadowing
  hit <- r[which(r$db_id == want)]
  if (nrow(hit) != 1L)
    ccdb_stop("Unknown db_id '", want, "'. Registered: ", paste(r$db_id, collapse = ", "))
  as.list(hit)
}

#' Databases in scope: exactly the review's entries, from the registry AND the
#' config's `databases.eligible` list. A mismatch is an error, not a warning.
eligible_dbs <- function() {
  r <- read_registry()
  in_reg <- r[in_review == TRUE & role == "analysis", db_id]
  in_cfg <- unlist(ccdb_cfg()$databases$eligible)
  if (!setequal(in_reg, in_cfg))
    ccdb_stop("config 'databases.eligible' and the registry disagree. ",
              "Only in registry: ", paste(setdiff(in_reg, in_cfg), collapse = ", "),
              "; only in config: ", paste(setdiff(in_cfg, in_reg), collapse = ", "))
  in_cfg
}

#' Absolute root folder of a database's source data.
db_root <- function(db_id) {
  ov <- CCDB$paths$overrides[[db_id]]
  if (!is.null(ov)) return(normalizePath(ov, winslash = "/", mustWork = FALSE))
  rel <- get_db(db_id)$local_root
  if (is.na(rel)) return(NA_character_)
  normalizePath(file.path(CCDB$paths$data_root, rel), winslash = "/", mustWork = FALSE)
}

#' Full path to a file inside a database root; `must_exist` stops with a clear message.
db_file <- function(db_id, ..., must_exist = TRUE) {
  p <- file.path(db_root(db_id), ...)
  if (must_exist && !file.exists(p))
    ccdb_stop("[", db_id, "] expected source file not found: ", p)
  p
}

#' Prefer the compressed file; fall back to the uncompressed twin (or reverse).
db_file_any <- function(db_id, ..., must_exist = TRUE) {
  base <- file.path(db_root(db_id), ...)
  cand <- unique(c(base, paste0(base, ".gz"), sub("[.]gz$", "", base)))
  hit <- cand[file.exists(cand) & !dir.exists(cand)]
  if (!length(hit)) {
    if (must_exist) ccdb_stop("[", db_id, "] expected source file not found (tried): ",
                              paste(cand, collapse = " | "))
    return(NA_character_)
  }
  hit[1]
}

# ---- adapter loading ----------------------------------------------------------

#' Each database adapter lives in databases/<db_id>/adapter.R and must define:
#'   adapter_meta : list(db_id, required_files = character())
#'   adapter_build(cfg) : returns a harmonised dataset (see 03_variable_harmonization.R)
#' Adapters are sourced into their own environment so they cannot clobber the core.
load_adapter <- function(db_id) {
  f <- ccdb_path("databases", db_id, "adapter.R")
  if (!file.exists(f)) ccdb_stop("No adapter for '", db_id, "' (expected ", f, ")")
  env <- new.env(parent = globalenv())
  sys.source(f, envir = env)
  for (nm in c("adapter_meta", "adapter_build"))
    if (!exists(nm, envir = env, inherits = FALSE))
      ccdb_stop("Adapter for '", db_id, "' must define `", nm, "`.")
  env
}

#' Check that the adapter's required source files exist. Returns a data.table
#' with a status so that a missing database is REPORTED as blocked, never skipped silently.
check_db_access <- function(db_id) {
  root <- db_root(db_id)
  ad <- tryCatch(load_adapter(db_id), error = function(e) NULL)
  req <- if (is.null(ad)) character() else ad$adapter_meta$required_files
  found <- vapply(req, function(f) {
    base <- file.path(root, f)
    any(file.exists(c(base, paste0(base, ".gz"), sub("[.]gz$", "", base))))
  }, logical(1))
  data.table::data.table(
    db_id = db_id, root = root, root_exists = !is.na(root) && dir.exists(root),
    n_required = length(req), n_found = sum(found),
    missing = paste(req[!found], collapse = "; "),
    status = fifelse(is.null(ad), "NO_ADAPTER",
             fifelse(!(!is.na(root) && dir.exists(root)), "BLOCKED_NO_DATA",
             fifelse(all(found), "READY", "BLOCKED_MISSING_FILES"))))
}

access_report <- function(db_ids = c(ccdb_cfg()$databases$reference, eligible_dbs())) {
  data.table::rbindlist(lapply(db_ids, check_db_access))
}
