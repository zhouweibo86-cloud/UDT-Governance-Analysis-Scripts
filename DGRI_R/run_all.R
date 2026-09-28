# Main pipeline execution script
# Reconstructs panel dataset, fits models, runs bootstrap inference, and generates reports

args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(if (length(args)) args[1] else ".", winslash = "/")
out <- if (length(args) > 1) args[2] else file.path(root, "reproduced_output")

if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE, recursive = TRUE))) {
  stop("Output directory must be new or empty. Existing results are never removed.")
}
dir.create(out, recursive = TRUE, showWarnings = FALSE)
out <- normalizePath(out, winslash = "/")

for (s in c("data", "models", "tables", "audit", "figures")) {
  dir.create(file.path(out, s), showWarnings = FALSE)
}

# Automatically add local package library if present
local_lib <- file.path(root, ".R-library")
custom_lib <- Sys.getenv("DGRI_R_LIB", unset = "")
if (nzchar(custom_lib) && dir.exists(custom_lib)) {
  .libPaths(c(custom_lib, .libPaths()))
} else if (dir.exists(local_lib)) {
  .libPaths(c(local_lib, .libPaths()))
}

required <- c("fixest", "fwildclusterboot", "readxl", "jsonlite", "digest", "sandwich", "dqrng")
for (pkg in required) {
  stopifnot(requireNamespace(pkg, quietly = TRUE))
}

lock <- jsonlite::fromJSON(file.path(root, "renv.lock"), simplifyVector = FALSE)$Packages
for (pkg in names(lock)) {
  stopifnot(identical(utils::packageDescription(pkg, fields = "Version"), lock[[pkg]]$Version))
}

fixest::setFixest_nthreads(1)
options(digits = 17, warn = 1)

write_csv <- function(x, path) {
  write.table(x, path, sep = ",", row.names = FALSE, col.names = TRUE, na = "", fileEncoding = "UTF-8", qmethod = "double")
}

write_json <- function(x, path) {
  jsonlite::write_json(x, path, pretty = TRUE, auto_unbox = TRUE, digits = 16, null = "null")
}

# Load modular workflow scripts
scripts <- c("01_build_data.R", "02_models.R", "03_diagnostics.R", "04_verify.R", "05_report.R")
for (script in scripts) {
  source(file.path(root, "R", script), encoding = "UTF-8")
}

cat("Rebuilding the country-year panel from frozen source files...\n")
d <- build_data(root, out)

cat("Constructing scores, fitting models, and computing bootstrap tests...\n")
d <- prepare(d, out)
results <- analyse(d, out)

cat("Running specification diagnostics...\n")
diagnostics(d, results, out)

cat("Verifying replication outputs...\n")
verify(d, results, root, out)

cat("Generating summary tables and figures...\n")
report(d, results, root, out)

capture.output(sessionInfo(), file = file.path(out, "audit/sessionInfo.txt"))
write_json(
  list(
    passed = TRUE,
    main_sample_n = 81,
    countries = 27,
    years = 2022:2024,
    models = 28,
    bootstrap_tests = 44,
    reps = 9999,
    seed = 20260918,
    pipeline = "complete"
  ),
  file.path(out, "audit/completion.json")
)
cat("COMPLETE: Full R analysis and replication pipeline successfully executed.\n")
