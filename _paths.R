# ==============================================================================
# _paths.R — central, portable path configuration for the CWA repo.
# ------------------------------------------------------------------------------
# Anchors to the repo root (the directory containing .git), so every script runs
# unchanged on any machine or clone — no absolute paths, no package dependency.
#
# Source it at the top of a script with the one-liner (robust to working dir):
#   source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))
#
# Then use the directory constants below, e.g. file.path(RAW_DIR, "ICIS_PERMITS.csv").
# ==============================================================================

CWA_ROOT <- local({
  d <- normalizePath(getwd(), mustWork = FALSE)
  while (!file.exists(file.path(d, ".git")) && dirname(d) != d) d <- dirname(d)
  if (!file.exists(file.path(d, ".git")))
    stop("CWA repo root (.git) not found upward from ", getwd(), " — run inside the repo.")
  d
})

RAW_DIR  <- file.path(CWA_ROOT, "data", "raw", "npdes_downloads")  # ECHO NPDES bulk files
DMR_DIR  <- file.path(CWA_ROOT, "data", "raw", "DMR")              # per-fiscal-year DMR zips
RAW_ROOT <- file.path(CWA_ROOT, "data", "raw")                     # other raw datasets
PROC_DIR <- file.path(CWA_ROOT, "data", "processed")              # built panels / derived data
OUT_DIR  <- file.path(CWA_ROOT, "output")                         # tables, summaries, figures
