# ==============================================================================
# run_all.R — rebuild the facility-by-MONTH panel from raw data.
# ------------------------------------------------------------------------------
# Usage (from anywhere inside the repo):   Rscript run_all.R
#
# Runs the two-step facility-by-month pipeline in the "updated panel" folder:
#   01  builds the base facility x month panel of major individual facilities
#       -> data/processed/01_facility_month_panel_major_individual_2005_2025.csv
#   02  reads that panel and attaches per-facility-month inspection counts
#       -> data/processed/02_facility_month_panel_major_individual_inspections_2005_2025.csv
#
# The numbering encodes dependency order: 02 reads the CSV that 01 writes. Steps
# are sourced in isolated environments so their variables can't collide; data
# passes between them via the CSVs on disk, not R objects.
# ==============================================================================

# Locate the repo root and load path config (defines CWA_ROOT, RAW_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

steps <- c(
  "01_build_facility_month_panel_major_individual.R", # base facility x month panel
  "02_add_inspections.R"                              # + inspection-count columns
)

for (s in steps) {
  path <- file.path(CWA_ROOT, "updated panel", s)
  message("\n===== running ", s, " =====")
  source(path, local = new.env())
  message("done: ", s)
}

message("\n=== pipeline complete: facility-by-month panel rebuilt in data/processed/ ===")
