# ==============================================================================
# run_all.R — one-command rebuild of the facility-by-MONTH panel from raw data.
# ------------------------------------------------------------------------------
# Usage (from anywhere inside the repo):   Rscript run_all.R
#
# 1. Sources code/00_setup/00_setup.R (package/directory checks).
# 2. Acquires the ECHO bulk files into data/raw/ if they're missing (the default
#    DOWNLOAD_DATA = "auto" — a fresh clone downloads automatically, an already-
#    populated setup skips it). Set TRUE to always run the downloader, FALSE to
#    never. See DOWNLOAD_DATA below.
# 3. Builds the condensed effluent-violations panel if it isn't already on disk
#    (see BUILD_EFFLUENT_PANEL below) — both step 01 and step 06 need this file
#    to exist before they can run.
# 4. Runs the six-step facility-by-month pipeline in code/03_panel_building/:
#      01  base facility x month panel of "ever major, ever individual"
#          facilities -- as of 2026-07-28, a facility is admitted if EITHER its
#          permit-paperwork window overlaps 2005-2025 OR it has independent
#          proxy evidence (inspection, violation, enforcement, effluent)
#          anywhere in that range (see step 01's README, Assumption 1B).
#          Writes THREE operating flags: FACILITY_OPERATING (the union -- use
#          this), FACILITY_OPERATING_PERMIT_WINDOW (permit-dates only), and
#          FACILITY_OPERATING_PROXY_WINDOW (proxy evidence only; Assumption 11).
#          Set USE_PROXIES <- FALSE inside the script to skip the proxy scan
#          entirely (permit-window-overlap-only membership, faster run).
#          -> data/processed/01_facility_month_panel_major_individual_2005_2025.csv
#      02  + inspection counts
#      03  + NAICS/SIC industry codes
#      04  + PS/CS/SE violation counts
#      05  + formal/informal enforcement counts + penalty $
#      06  + effluent-violation counts (final panel)
#          -> data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv
# 5. Rebuilds the website's data (website/scripts/build_website_data.R): the
#    per-dataset summaries + year-coverage + panel QA summary, converted to the
#    website/data/*.json the static site reads. On by default (BUILD_WEBSITE);
#    fail-soft and SLOW (the `limits` summary alone loads a multi-GB file), so
#    set BUILD_WEBSITE <- FALSE to rebuild just the panel. Serve the result over
#    HTTP (the pages fetch JSON, which browsers block under file://).
#
# The numbering encodes dependency order: each step reads the CSV the previous
# step wrote. Steps are sourced in isolated environments so their variables
# can't collide; data passes between them via the CSVs on disk, not R objects.
#
# Not run here (deliberately): code/diagnostics/, code/dmr/ (incl. its two standalone
# filter pipelines) -- QC/filter pipelines, not part of rebuilding the panel.
# (code/summary/ IS run, but only as part of the step-5 website build above.)
# See code/README.md.
#
# REMOVED 2026-07-23: the FY2025 row-filter helper (restrict_06_to_fy2025.R) was
# deleted. Its outputs (data/processed/07_facility_month_panel_major_individual_
# operating_corrected_fy2025.csv and the earlier data/processed/06_..._effluent_
# fy2025.csv) remain on disk as static files -- neither is regenerable by any
# script. Filter the current 06 panel directly if you need a fresh FY2025 (or
# other) extract.
# ==============================================================================

# Locate the repo root and load path config (defines CWA_ROOT, RAW_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

message("\n===== running 00_setup.R =====")
source(file.path(CWA_ROOT, "code/00_setup/00_setup.R"))
message("done: 00_setup.R")

# Raw-data acquisition. Three modes:
#   "auto"  (default) -- fetch ONLY if data/raw/ looks unpopulated, so a fresh
#                        clone downloads on its own while an already-populated
#                        setup skips the multi-GB transfer.
#   TRUE              -- always run the downloader (it still skips files already
#                        on disk; set REFRESH <- TRUE inside that script to force
#                        a re-download).
#   FALSE             -- never download.
# The downloader is idempotent (logs SKIPPED-EXISTS, fetches only gaps), so
# "auto" can safely re-run it whenever a sentinel file is absent.
DOWNLOAD_DATA <- "auto"

# A minimal set of files the panel build needs; if any is absent, "auto" treats
# data/raw/ as unpopulated and runs the downloader (which then fills only gaps).
RAW_SENTINELS <- c(
  file.path(RAW_DIR,  "ICIS_FACILITIES.csv"),      # core npdes_downloads table
  file.path(RAW_DIR,  "ICIS_PERMITS.csv"),
  file.path(RAW_ROOT, "npdes_eff_downloads.zip")   # effluent source (stays zipped)
)
raw_present <- all(file.exists(RAW_SENTINELS))
do_download <- isTRUE(DOWNLOAD_DATA) ||
  (identical(DOWNLOAD_DATA, "auto") && !raw_present)

if (do_download) {
  if (identical(DOWNLOAD_DATA, "auto"))
    message("\n===== raw data not found in data/raw/; auto-downloading (multi-GB, slow) =====")
  message("\n===== running 01_download_echo_bulk_files.R =====")
  source(file.path(CWA_ROOT, "code/01_data_download/01_download_echo_bulk_files.R"),
         local = new.env())
  message("done: 01_download_echo_bulk_files.R")
} else if (identical(DOWNLOAD_DATA, "auto")) {
  message("\n===== skipping download (raw data already present in data/raw/) =====")
} else {
  message("\n===== skipping 01_download_echo_bulk_files.R (DOWNLOAD_DATA = FALSE) =====")
}

# Build the condensed effluent-violations panel if it's not already there. This
# is a genuine prerequisite (not an optional slow step like DOWNLOAD_DATA
# above) -- steps 01 and 06 cannot run without it -- but it takes ~15-20
# minutes (one full pass over the ~16 GB raw effluent file), so we only rebuild
# it when it's actually missing rather than on every run.
EFF_PANEL_PATH <- file.path(CWA_ROOT, "data/processed/effluent_violations_npdes_month_panel_2005_2025.csv")
if (!file.exists(EFF_PANEL_PATH)) {
  message("\n===== condensed effluent panel not found; building it first (~15-20 min) =====")
  source(file.path(CWA_ROOT, "code/02_cleaning/build_effluent_violations_npdes_month_panel.R"),
         local = new.env())
  message("done: build_effluent_violations_npdes_month_panel.R")
} else {
  message("\n===== skipping build_effluent_violations_npdes_month_panel.R (",
          "condensed effluent panel already on disk at ", EFF_PANEL_PATH, ") =====")
}

steps <- c(
  "01_build_facility_month_panel_major_individual.R", # base facility x month panel + all three operating flags
  "02_add_inspections.R",                              # + inspection-count columns
  "03_add_naics_sic.R",                                # + NAICS/SIC industry codes
  "04_add_violations.R",                               # + PS/CS/SE violation counts
  "05_add_enforcement.R",                               # + enforcement counts + penalty $
  "06_add_effluent_violations.R"                        # + effluent-violation counts (final)
)

for (s in steps) {
  path <- file.path(CWA_ROOT, "code/03_panel_building", s)
  message("\n===== running ", s, " =====")
  source(path, local = new.env())
  message("done: ", s)
}

message("\n=== pipeline complete: facility-by-month panel rebuilt in data/processed/ ===")

# ---- Website data (final stage) ----------------------------------------------
# Rebuild the JSON the static site reads (data summaries, year coverage, panel
# QA). SLOW -- the `limits` summary loads a multi-GB file and the two
# eff_violations states each stream a ~2.9 GB zip. Fail-soft: wrapped so a
# problem here logs a warning but never discards the panel just built. Set FALSE
# to skip; run website/scripts/build_website_data.R by hand to (re)build later.
BUILD_WEBSITE <- TRUE
if (BUILD_WEBSITE) {
  message("\n===== building website data (summaries -> JSON); this can take a while =====")
  tryCatch(
    source(file.path(CWA_ROOT, "website/scripts/build_website_data.R"), local = new.env()),
    error = function(e)
      message("WARNING: website build failed (", conditionMessage(e), "). ",
              "The panel is built; re-run website/scripts/build_website_data.R to retry.")
  )
} else {
  message("\n===== skipping website build (BUILD_WEBSITE = FALSE) =====")
}
