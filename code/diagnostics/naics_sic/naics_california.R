# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# naics_california.R
# ------------------------------------------------------------------------------
# Subset NPDES_NAICS.csv to California facilities only, annotated with permit
# type, so you can see at a glance whether the CA permits carrying a NAICS code
# are general/minor/non-NPDES permits, or major individual dischargers.
#
#   NPDES_NAICS.csv has no state field of its own (it only has NPDES_ID,
#   NAICS_CODE, NAICS_DESC, PRIMARY_INDICATOR_FLAG), so STATE_CODE is joined in
#   from ICIS_FACILITIES.csv (keyed 1:1 by NPDES_ID). California = "CA".
#
#   We also attach, from ICIS_PERMITS (that permit's CURRENT version,
#   VERSION_NMBR == 0):
#     PERMIT_TYPE_CODE        - raw ECHO code (NPD, GPC, ...)
#     PERMIT_VEHICLE          - a friendlier "General" vs "Individual" label
#                               we derive from that code (see the `vehicle`
#                               lookup below)
#     MAJOR_MINOR_STATUS_FLAG - M / N, as of the current version
#
# LABELED ASSUMPTIONS:
#   1. "Current version" means VERSION_NMBR == 0 in ICIS_PERMITS. Both
#      PERMIT_TYPE_CODE and MAJOR_MINOR_STATUS_FLAG are read from that one row
#      per permit, not reconstructed across a permit's full version history --
#      this is a present-day snapshot, not a time series.
#
# Inputs : data/raw/npdes_downloads/NPDES_NAICS.csv, ICIS_FACILITIES.csv,
#          ICIS_PERMITS.csv
# Output : output/tables/npdes_naics_california_<timestamp>.csv
# Read-only on raw data; deterministic except for the output filename's timestamp.
# ==============================================================================

suppressPackageStartupMessages(library(data.table))

RAW <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
OUT_DIR <- file.path(CWA_ROOT, "output/tables")

rd <- function(f, cols) fread(file.path(RAW, f), select = cols,
                              colClasses = "character", showProgress = FALSE)

# ---- 1. Read NAICS + state lookup --------------------------------------------
naics <- rd("NPDES_NAICS.csv",
            c("NPDES_ID", "NAICS_CODE", "NAICS_DESC", "PRIMARY_INDICATOR_FLAG"))
naics[, NPDES_ID := trimws(NPDES_ID)]

fac <- rd("ICIS_FACILITIES.csv", c("NPDES_ID", "STATE_CODE"))
fac[, NPDES_ID := trimws(NPDES_ID)]
fac <- unique(fac, by = "NPDES_ID")   # one state per NPDES_ID

# ---- 2. Join state, keep California ------------------------------------------
naics <- fac[naics, on = "NPDES_ID"]           # adds STATE_CODE
ca <- naics[STATE_CODE == "CA"]

# ---- 2b. Merge permit type (general vs individual) + major/minor status -------
# Both taken from each permit's CURRENT version (VERSION_NMBR == 0).
# PERMIT_TYPE_CODE is essentially version-invariant; MAJOR_MINOR_STATUS_FLAG can
# change at reissuance, so this reports the current one.
perm <- rd("ICIS_PERMITS.csv",
           c("EXTERNAL_PERMIT_NMBR", "VERSION_NMBR",
             "PERMIT_TYPE_CODE", "MAJOR_MINOR_STATUS_FLAG"))
perm[, NPDES_ID := trimws(EXTERNAL_PERMIT_NMBR)]
perm <- unique(perm[trimws(VERSION_NMBR) == "0",
                    .(NPDES_ID,
                      PERMIT_TYPE_CODE        = trimws(PERMIT_TYPE_CODE),
                      MAJOR_MINOR_STATUS_FLAG = trimws(MAJOR_MINOR_STATUS_FLAG))],
               by = "NPDES_ID")

# General vs individual label from the permit-type code.
vehicle <- c(NPD = "Individual",             GPC = "General",
             IIU = "Individual (non-NPDES)", SIN = "Individual (non-NPDES)",
             NGP = "General (non-NPDES)",     UFT = "Not a permit",
             APR = "Not a permit",            SNN = "Other (non-NPDES)")
perm[, PERMIT_VEHICLE := vehicle[PERMIT_TYPE_CODE]]

ca <- perm[ca, on = "NPDES_ID"]   # adds PERMIT_TYPE_CODE, PERMIT_VEHICLE, MAJOR_MINOR_STATUS_FLAG
setcolorder(ca, c("NPDES_ID", "STATE_CODE", "PERMIT_TYPE_CODE", "PERMIT_VEHICLE",
                  "MAJOR_MINOR_STATUS_FLAG", "NAICS_CODE", "NAICS_DESC",
                  "PRIMARY_INDICATOR_FLAG"))

# ---- 3. Report + write --------------------------------------------------------
cat("NAICS rows total:", nrow(naics), "\n")
cat("NAICS rows in CA:", nrow(ca),
    "  (", uniqueN(ca$NPDES_ID), "distinct CA permits )\n")
cat("\nCA NAICS rows by permit vehicle:\n")
print(ca[, .(rows = .N, distinct_permits = uniqueN(NPDES_ID)), by = PERMIT_VEHICLE][order(-rows)])
cat("\nCA NAICS rows by current major/minor flag:\n")
print(ca[, .(rows = .N, distinct_permits = uniqueN(NPDES_ID)), by = MAJOR_MINOR_STATUS_FLAG][order(-rows)])

if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)
stamp <- format(Sys.time(), "%Y-%m-%d_%H%M")
out_f <- file.path(OUT_DIR, paste0("npdes_naics_california_", stamp, ".csv"))
fwrite(ca, out_f)
cat("Written to:", out_f, "\n")
