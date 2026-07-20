# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# Minimal loader: read ICIS_PERMITS.csv (raw NPDES permits) as-is.
# All columns read as character so IDs/codes are never silently reinterpreted
# as numbers (e.g. leading zeros in permit numbers).

suppressPackageStartupMessages(library(data.table))

naics <- fread(file.path(RAW_DIR, "NPDES_NAICS.csv")
