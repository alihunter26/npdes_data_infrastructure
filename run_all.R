# ==============================================================================
# run_all.R — one-command rebuild of the facility-by-MONTH panel from raw data.
# ------------------------------------------------------------------------------
# Usage (from anywhere inside the repo):   Rscript run_all.R
#
# 1. Sources code/00_setup/00_setup.R (package/directory checks).
# 2. Optionally re-downloads the ECHO bulk files (off by default — slow, large;
#    see DOWNLOAD_DATA below).
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
#
# The numbering encodes dependency order: each step reads the CSV the previous
# step wrote. Steps are sourced in isolated environments so their variables
# can't collide; data passes between them via the CSVs on disk, not R objects.
#
# Not run here (deliberately): code/diagnostics/, code/summary/, code/dmr/
# (incl. its two standalone filter pipelines) -- QC/reporting/filter pipelines,
# not part of rebuilding the panel. See code/README.md.
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

# Set TRUE to (re-)fetch the ECHO bulk files before rebuilding. Off by default:
# slow (multi-GB downloads) and data/raw/ is normally already populated.
DOWNLOAD_DATA <- FALSE
if (DOWNLOAD_DATA) {
  message("\n===== running 01_download_echo_bulk_files.R =====")
  source(file.path(CWA_ROOT, "code/01_data_download/01_download_echo_bulk_files.R"),
         local = new.env())
  message("done: 01_download_echo_bulk_files.R")
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
