# ==============================================================================
# 00_setup.R — package/directory checks, run first by run_all.R.
# ------------------------------------------------------------------------------
# This module's master script (per the lab's numbered-module convention): checks
# that every package the pipeline uses is installed (installing any that are
# missing) and that the directories every script expects to write into exist.
# It does not touch data/raw/ contents or run any build step.
#
# Inputs:  none.
# Outputs: none (side effect: installed packages, created directories).
# ==============================================================================

source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ---- 1. Packages used anywhere in the pipeline (confirmed via repo-wide grep) -
REQUIRED_PACKAGES <- c(
  "data.table", "DBI", "duckdb",                 # data build / large-file reads
  "ggplot2", "scales", "cowplot",                # brief-generator figures
  "dplyr", "tidyr", "lubridate",                 # a handful of scripts
  "openxlsx"                                     # code/summary/ workbooks
)

missing_pkgs <- REQUIRED_PACKAGES[!vapply(REQUIRED_PACKAGES, requireNamespace,
                                           logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  message("Installing missing packages: ", paste(missing_pkgs, collapse = ", "))
  install.packages(missing_pkgs)
} else {
  message("All required R packages already installed.")
}

# ---- 2. Directories every script expects to exist ----------------------------
REQUIRED_DIRS <- c(
  RAW_ROOT, RAW_DIR, DMR_DIR,
  PROC_DIR,
  file.path(CWA_ROOT, "data", "crosswalks"),
  OUT_DIR, file.path(OUT_DIR, "tables"), file.path(OUT_DIR, "figures")
)
for (d in REQUIRED_DIRS) dir.create(d, showWarnings = FALSE, recursive = TRUE)

message("Setup complete: packages checked, directories ready.")
