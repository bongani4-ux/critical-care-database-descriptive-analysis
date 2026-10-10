#!/usr/bin/env Rscript
# Sanity check of a fresh checkout: packages, config, registry and data access.
#   Rscript scripts/check_setup.R
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]), winslash = "/")) else getwd()
root <- normalizePath(file.path(script_dir, ".."), winslash = "/")
source(file.path(root, "R", "00_setup.R"))
ccdb_init(root = root)

cat("\nR", as.character(getRversion()), "\n")
pk <- c(CCDB_REQUIRED_PKGS, CCDB_OPTIONAL_PKGS)
print(data.frame(package = pk,
                 installed = vapply(pk, requireNamespace, logical(1), quietly = TRUE),
                 version = vapply(pk, function(p) if (requireNamespace(p, quietly = TRUE)) as.character(packageVersion(p)) else NA_character_, character(1)),
                 row.names = NULL))
cat("\nEligible databases (registry == config):", paste(eligible_dbs(), collapse = ", "), "\n\n")
print(access_report())
