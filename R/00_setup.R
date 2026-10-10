# =============================================================================
# 00_setup.R - project root, configuration, logging, safe I/O
#
# Usage (from any script):
#   source("R/00_setup.R"); ccdb_init()
# or, from a script located elsewhere in the project:
#   source(file.path(dirname(sys.frame(1)$ofile), "../R/00_setup.R"))
#
# No absolute paths live in the code. Machine-specific paths are read from
# config/paths.local.yml (git-ignored). `here` is deliberately not used: the
# root is found by walking up to the folder containing config/analysis_config.yml.
# =============================================================================

CCDB <- new.env(parent = emptyenv())   # package-level state (config, root, log file)

# Packages the shared core needs. Optional packages are loaded only where used.
CCDB_REQUIRED_PKGS <- c("data.table", "yaml", "readr")
CCDB_OPTIONAL_PKGS <- c("ggplot2", "gt", "arrow", "testthat", "openxlsx", "scales")

# ---- root and config --------------------------------------------------------

#' Walk up from `start` until the folder containing config/analysis_config.yml.
ccdb_find_root <- function(start = getwd()) {
  d <- normalizePath(start, winslash = "/", mustWork = FALSE)
  repeat {
    if (file.exists(file.path(d, "config", "analysis_config.yml"))) return(d)
    parent <- dirname(d)
    if (identical(parent, d))
      stop("Could not find the project root (config/analysis_config.yml) above '",
           start, "'. Run scripts from inside the project folder.", call. = FALSE)
    d <- parent
  }
}

ccdb_path <- function(...) file.path(CCDB$root, ...)

#' Initialise the session: root, packages, config, seed. Idempotent.
ccdb_init <- function(root = NULL, quiet = FALSE) {
  CCDB$root <- if (is.null(root)) ccdb_find_root() else normalizePath(root, winslash = "/")
  missing_pkgs <- CCDB_REQUIRED_PKGS[!vapply(CCDB_REQUIRED_PKGS, requireNamespace,
                                              logical(1), quietly = TRUE)]
  if (length(missing_pkgs))
    stop("Required packages not installed: ", paste(missing_pkgs, collapse = ", "),
         ". Run renv::restore() or install.packages().", call. = FALSE)
  suppressPackageStartupMessages(library(data.table))
  CCDB$cfg <- yaml::read_yaml(ccdb_path("config", "analysis_config.yml"))
  CCDB$paths <- ccdb_read_paths()
  set.seed(CCDB$cfg$project$seed)

  # source the shared core in numeric order (00_setup.R itself is already loaded)
  core <- sort(list.files(ccdb_path("R"), pattern = "^[0-9]{2}_.*[.]R$", full.names = TRUE))
  core <- core[basename(core) != "00_setup.R"]
  for (f in core) sys.source(f, envir = globalenv())

  if (!quiet) log_msg("INFO", "Project root: ", CCDB$root)
  invisible(CCDB)
}

ccdb_cfg <- function() {
  if (is.null(CCDB$cfg)) stop("Call ccdb_init() first.", call. = FALSE)
  CCDB$cfg
}

#' Read config/paths.local.yml; fail with an actionable message if absent.
ccdb_read_paths <- function() {
  f <- ccdb_path("config", "paths.local.yml")
  if (!file.exists(f))
    stop("config/paths.local.yml not found. Copy config/paths.example.yml to ",
         "config/paths.local.yml and set data_root.", call. = FALSE)
  p <- yaml::read_yaml(f)
  if (is.null(p$data_root) || !nzchar(p$data_root))
    stop("data_root is not set in config/paths.local.yml.", call. = FALSE)
  p
}

#' Resolve a (possibly relative) path against derived_dir / output dirs.
ccdb_derived_dir <- function(db_id = NULL) {
  d <- CCDB$paths$derived_dir
  d <- if (grepl("^([A-Za-z]:|/)", d)) d else ccdb_path(d)
  if (!is.null(db_id)) d <- file.path(d, db_id)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

ccdb_output_dir <- function(kind = c("tables", "figures", "logs")) {
  kind <- match.arg(kind)
  d <- ccdb_path("outputs", kind)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

# ---- logging ----------------------------------------------------------------

#' Start a per-run log file; messages go to console and file.
log_start <- function(tag) {
  CCDB$log_file <- file.path(ccdb_output_dir("logs"),
                             sprintf("%s_%s.log", tag, format(Sys.time(), "%Y%m%d_%H%M%S")))
  log_msg("INFO", "Log file: ", basename(CCDB$log_file))
  invisible(CCDB$log_file)
}

log_msg <- function(level = "INFO", ...) {
  line <- sprintf("%s [%s] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), level,
                  paste0(..., collapse = ""))
  message(line)
  if (!is.null(CCDB$log_file)) cat(line, "\n", file = CCDB$log_file, append = TRUE, sep = "")
  invisible(line)
}

#' Stop with a logged, informative message.
ccdb_stop <- function(...) {
  log_msg("ERROR", ...)
  stop(paste0(...), call. = FALSE)
}

# ---- safe, rerunnable output --------------------------------------------------

#' Write a CSV atomically (temp file then rename) so an interrupted run cannot
#' leave a half-written output, and a rerun overwrites rather than appends.
safe_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  data.table::fwrite(x, tmp, bom = TRUE)
  if (!file.rename(tmp, path)) {          # Windows: rename fails if target exists
    file.remove(path)
    file.rename(tmp, path)
  }
  invisible(path)
}

safe_save_rds <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  saveRDS(x, tmp)
  if (!file.rename(tmp, path)) { file.remove(path); file.rename(tmp, path) }
  invisible(path)
}

opt_pkg <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE))
    ccdb_stop("Optional package '", pkg, "' is required for this step. install.packages('", pkg, "')")
  invisible(TRUE)
}
