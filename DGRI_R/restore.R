# Restore project package dependencies using renv
args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(if (length(args)) args[1] else ".", winslash = "/")

Sys.setenv(RENV_PATHS_ROOT = file.path(root, ".renv-cache"), RENV_CONFIG_CONSENT = "TRUE")
lib <- file.path(root, ".R-library")
dir.create(lib, showWarnings = FALSE)
.libPaths(c(lib, .libPaths()))

if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", lib = lib, repos = "https://cloud.r-project.org")
}

renv::restore(project = root, library = lib, lockfile = file.path(root, "renv.lock"), prompt = FALSE)
cat("Dependencies successfully restored to", lib, "\n")
