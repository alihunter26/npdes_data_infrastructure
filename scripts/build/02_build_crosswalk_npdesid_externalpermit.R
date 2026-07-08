# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# build_crosswalk_npdesid_externalpermit.R
# ------------------------------------------------------------------------------
# Builds a crosswalk between NPDES_ID and EXTERNAL_PERMIT_NMBR.
#
# These two identifiers never co-occur in a single ICIS table: NPDES_ID keys one
# family of tables (facilities, violations, QNCR, inspections, enforcement,
# NAICS/SICS, catchments, ATTAINS) and EXTERNAL_PERMIT_NMBR keys the other
# (permits, limits, perm components, feature coords, data groups, outfalls).
# To join across the two families we need to know how the keys correspond.
#
# Approach: take the authoritative universe of each key —
#   NPDES_ID             from ICIS_FACILITIES
#   EXTERNAL_PERMIT_NMBR from ICIS_PERMITS
# — and measure overlap, match rates, and cardinality. Output a long crosswalk
# with a presence flag for each family.
#
# Assumption (correspondence rule): two ids correspond if and only if, after
# trimming whitespace and upper-casing, their strings are exactly equal. No
# fuzzy matching. NPDES_IDs that appear only in the other NPDES_ID-keyed tables
# (e.g. a violation with no facility record) are out of scope here — the
# universe is anchored on ICIS_FACILITIES.
# ------------------------------------------------------------------------------

library(data.table)

# ── Configuration ─────────────────────────────────────────────────────────────

DATA_DIR <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
# Timestamped output so each run writes its own file (date + time, to the minute)
OUT_FILE <- sprintf(
  file.path(CWA_ROOT, "data/crosswalks/xwalk_npdesid_externalpermit_%s.csv"),
  format(Sys.time(), "%Y-%m-%d_%H%M"))

# Normalize keys before any comparison (see correspondence-rule assumption above)
norm <- function(x) toupper(trimws(x))

# ── Load the two key universes (one column each) ──────────────────────────────

fac <- fread(file.path(DATA_DIR, "ICIS_FACILITIES.csv"), select = "NPDES_ID",
             colClasses = "character", na.strings = c("", "NA"))
per <- fread(file.path(DATA_DIR, "ICIS_PERMITS.csv"), select = "EXTERNAL_PERMIT_NMBR",
             colClasses = "character", na.strings = c("", "NA"))

fac_rows <- nrow(fac); per_rows <- nrow(per)

# Normalize once, then split out missing so dup/distinct counts are clean
fac_key <- norm(fac$NPDES_ID)
per_key <- norm(per$EXTERNAL_PERMIT_NMBR)
fac_na  <- sum(is.na(fac_key)); per_na <- sum(is.na(per_key))
fac_key <- fac_key[!is.na(fac_key)]
per_key <- per_key[!is.na(per_key)]

npdes_id <- unique(fac_key)   # distinct NPDES_ID universe
ext_nmbr <- unique(per_key)   # distinct EXTERNAL_PERMIT_NMBR universe

# ── Cardinality within each source (are these unique, permit-level keys?) ──────

fac_dup <- length(fac_key) - length(npdes_id)   # rows beyond distinct (non-missing)
per_dup <- length(per_key) - length(ext_nmbr)

# ── Overlap ───────────────────────────────────────────────────────────────────

both     <- intersect(npdes_id, ext_nmbr)
only_fac <- setdiff(npdes_id, ext_nmbr)   # in facilities, no permit record
only_per <- setdiff(ext_nmbr, npdes_id)   # in permits, no facility record

# ── Crosswalk table: every id, with presence in each family ───────────────────

all_ids <- sort(union(npdes_id, ext_nmbr))
xwalk <- data.table(
  permit_id     = all_ids,
  in_facilities = all_ids %in% npdes_id,   # appears as NPDES_ID
  in_permits    = all_ids %in% ext_nmbr    # appears as EXTERNAL_PERMIT_NMBR
)
dir.create(dirname(OUT_FILE), showWarnings = FALSE, recursive = TRUE)
fwrite(xwalk, OUT_FILE)

# ── Report ────────────────────────────────────────────────────────────────────

pct <- function(a, b) sprintf("%.1f%%", 100 * a / b)
cat("\n── NPDES_ID  <->  EXTERNAL_PERMIT_NMBR crosswalk ─────────────────────\n")
cat(sprintf("ICIS_FACILITIES rows: %s | distinct NPDES_ID: %s | dup rows: %s | missing: %s\n",
            format(fac_rows, big.mark=","), format(length(npdes_id), big.mark=","),
            format(fac_dup, big.mark=","), format(fac_na, big.mark=",")))
cat(sprintf("ICIS_PERMITS    rows: %s | distinct EXTERNAL_PERMIT_NMBR: %s | dup rows: %s | missing: %s\n",
            format(per_rows, big.mark=","), format(length(ext_nmbr), big.mark=","),
            format(per_dup, big.mark=","), format(per_na, big.mark=",")))
cat("\nOverlap (normalized exact string match):\n")
cat(sprintf("  in BOTH:                 %s\n", format(length(both), big.mark=",")))
cat(sprintf("  only in FACILITIES:      %s\n", format(length(only_fac), big.mark=",")))
cat(sprintf("  only in PERMITS:         %s\n", format(length(only_per), big.mark=",")))
cat("\nMatch rates:\n")
cat(sprintf("  facilities -> permits:   %s of NPDES_IDs have a permit record\n",
            pct(length(both), length(npdes_id))))
cat(sprintf("  permits -> facilities:   %s of EXTERNAL_PERMIT_NMBRs have a facility record\n",
            pct(length(both), length(ext_nmbr))))
cat(sprintf("\nCardinality: %s\n",
            if (fac_dup == 0 && per_dup == 0)
              "1-to-1 (both are unique permit-level keys); join is a direct string match"
            else "NOT unique on at least one side — inspect before joining"))
cat("Crosswalk written to:", OUT_FILE, "\n")
