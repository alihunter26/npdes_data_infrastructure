# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

panel <- fread(file.path(CWA_ROOT, "data/processed/facility_panel_major_individual_2005_2025.csv"))

short_panel <-fread(file.path(CWA_ROOT, "data/processed/npdes_enforcement_panel_2005_2025.csv"), nrows = 1000)

duplicates <- read.csv(file.path(CWA_ROOT, "data/processed/facility_uin_multiple_npdes.csv"))
