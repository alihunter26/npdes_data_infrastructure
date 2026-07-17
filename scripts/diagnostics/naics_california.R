# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# Subset NPDES_NAICS.csv to California facilities only, annotated with permit type.
#
# NPDES_NAICS has no state field (NPDES_ID, NAICS_CODE, NAICS_DESC,
# PRIMARY_INDICATOR_FLAG), so state is joined from ICIS_FACILITIES.csv
# (STATE_CODE, keyed 1:1 by NPDES_ID). California = STATE_CODE "CA".
#
# Also merges, from ICIS_PERMITS (current version, VERSION_NMBR == 0):
#   PERMIT_TYPE_CODE        - raw ECHO code (NPD, GPC, ...)
#   PERMIT_VEHICLE          - General vs Individual label derived from that code
#   MAJOR_MINOR_STATUS_FLAG - M / N (current version)
# so you can see at a glance that the CA permits carrying NAICS are general /
# minor / non-NPDES, not major individual dischargers.
#
# Read-only on raw data. Writes a timestamped CSV to output/tables/.

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
