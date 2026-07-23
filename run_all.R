# ==============================================================================
# run_all.R — one-command rebuild of the facility-by-MONTH panel from raw data.
# ------------------------------------------------------------------------------
# Usage (from anywhere inside the repo):   Rscript run_all.R
#
# 1. Sources code/00_setup/00_setup.R (package/directory checks).
# 2. Optionally re-downloads the ECHO bulk files (off by default — slow, large;
#    see DOWNLOAD_DATA below).
# 3. Runs the seven-step facility-by-month pipeline in code/03_panel_building/:
#      01  base facility x month panel of major individual facilities
#          -> data/processed/01_facility_month_panel_major_individual_2005_2025.csv
#      02  + inspection counts
#      03  + NAICS/SIC industry codes
#      04  + PS/CS/SE violation counts
#      05  + formal/informal enforcement counts + penalty $
#      06  + effluent-violation counts
#          -> data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv
#      07  corrects FACILITY_OPERATING, which undercounted real activity by up to
#          250 months for some facilities (permits in administrative continuance) --
#          reads ONLY step 06's output, no raw files (final panel)
#          -> data/processed/07_facility_month_panel_major_individual_operating_corrected_2005_2025.csv
#
# The numbering encodes dependency order: each step reads the CSV the previous
# step wrote. Steps are sourced in isolated environments so their variables
# can't collide; data passes between them via the CSVs on disk, not R objects.
#
# Not run here (deliberately):
#   - code/diagnostics/, code/summary/, dmr analysis/, build/ -- QC/reporting/
#     sibling pipelines, not part of rebuilding the panel. See code/README.md.
#   - code/03_panel_building/restrict_06_to_fy2025.R -- optional helper, run
#     manually after this script. Repointed 2026-07-23 to read the step-07 panel
#     (its own filename still says "06" for historical reasons) ->
#     data/processed/07_facility_month_panel_major_individual_operating_corrected_fy2025.csv
# ==============================================================================

# Locate the repo root and load path config (defines CWA_ROOT, RAW_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

source(file.path(CWA_ROOT, "code/00_setup/00_setup.R"))

# Set TRUE to (re-)fetch the ECHO bulk files before rebuilding. Off by default:
# slow (multi-GB downloads) and data/raw/ is normally already populated.
DOWNLOAD_DATA <- FALSE
if (DOWNLOAD_DATA) {
  source(file.path(CWA_ROOT, "code/01_data_download/01_download_echo_bulk_files.R"),
         local = new.env())
}

steps <- c(
  "01_build_facility_month_panel_major_individual.R", # base facility x month panel
  "02_add_inspections.R",                              # + inspection-count columns
  "03_add_naics_sic.R",                                # + NAICS/SIC industry codes
  "04_add_violations.R",                               # + PS/CS/SE violation counts
  "05_add_enforcement.R",                               # + enforcement counts + penalty $
  "06_add_effluent_violations.R",                       # + effluent-violation counts
  "07_extend_facility_operating.R"                      # corrects FACILITY_OPERATING (final)
)

for (s in steps) {
  path <- file.path(CWA_ROOT, "code/03_panel_building", s)
  message("\n===== running ", s, " =====")
  source(path, local = new.env())
  message("done: ", s)
}

message("\n=== pipeline complete: facility-by-month panel rebuilt in data/processed/ ===")
