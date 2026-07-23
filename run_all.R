# ==============================================================================
# run_all.R — one-command rebuild of the facility-by-MONTH panel from raw data.
# ------------------------------------------------------------------------------
# Usage (from anywhere inside the repo):   Rscript run_all.R
#
# 1. Sources code/00_setup/00_setup.R (package/directory checks).
# 2. Optionally re-downloads the ECHO bulk files (off by default — slow, large;
#    see DOWNLOAD_DATA below).
# 3. Runs the six-step facility-by-month pipeline in code/03_panel_building/:
#      01  base facility x month panel of major individual facilities
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
# Not run here (deliberately): code/diagnostics/, code/summary/, dmr analysis/,
# build/ — those are QC/reporting/sibling pipelines, not part of rebuilding the
# panel. See code/README.md for how they relate.
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
  "06_add_effluent_violations.R"                        # + effluent-violation counts (final)
)

for (s in steps) {
  path <- file.path(CWA_ROOT, "code/03_panel_building", s)
  message("\n===== running ", s, " =====")
  source(path, local = new.env())
  message("done: ", s)
}

message("\n=== pipeline complete: facility-by-month panel rebuilt in data/processed/ ===")
