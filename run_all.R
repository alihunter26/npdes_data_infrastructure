# ==============================================================================
# run_all.R — rebuild the entire NPDES panel pipeline from raw data.
# ------------------------------------------------------------------------------
# Usage (from anywhere inside the repo):   Rscript run_all.R
#
# Each build step is self-contained: it sources _paths.R, reads from data/raw/,
# and writes to data/processed/. The numbering encodes dependency order. Steps
# are sourced in isolated environments so their variables can't collide; data
# passes between steps via the CSVs on disk, not R objects.
# ==============================================================================

# Locate the repo root and load path config (defines CWA_ROOT, RAW_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

steps <- c(
  "01_build_npdes_panel.R",                     # base facility-year panel from raw ECHO
  "02_build_crosswalk_npdesid_externalpermit.R",# NPDES_ID <-> external permit crosswalk
  "03_facility_uin_multiple_npdes.R",           # FRS lookup: facilities with >1 NPDES ID
  "04_filter_major_individual_facilities.R",    # major+individual filter of the base panel
  "05_build_facility_panel_major_individual.R", # FRS-facility panel (never-minor, entry/exit)
  "06_build_permit_panel_major_continuous.R",   # permit panel: major every year (balanced)
  "07_build_permit_panel_major_entryexit.R"     # permit panel: never-minor (entry/exit)
)

for (s in steps) {
  path <- file.path(CWA_ROOT, "scripts", "build", s)
  message("\n===== running ", s, " =====")
  source(path, local = new.env())
  message("done: ", s)
}

message("\n=== pipeline complete: all panels rebuilt in data/processed/ ===")
