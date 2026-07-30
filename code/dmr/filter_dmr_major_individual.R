# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, DMR_DIR, RAW_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# filter_dmr_major_individual.R
# ------------------------------------------------------------------------------
# Parameterized replacement for filter_dmr_fy2025_major_individual.R /
# filter_dmr_fy2009_major_individual.R -- same logic, FY taken as a
# command-line argument instead of being hardcoded per file.
#
# Usage:
#   Rscript code/dmr/filter_dmr_major_individual.R <FY>
#   e.g.    Rscript code/dmr/filter_dmr_major_individual.R 2025
#
# Moved in from the root-level `dmr analysis/` folder 2026-07-29 -- script AND its
# input/output CSVs both now live in code/dmr/, git-ignored via `code/dmr/*.csv`
# (see code/dmr/README.md). The old `dmr analysis/` folder is gone.
#
# Row-filter the FULL FY<year> DMR file down to permits that are MAJOR under
# an INDIVIDUAL permit -- the same population the facility panels use. Does
# NOT narrow by parameter, feature type, monitoring location, or statistical
# base: every row for an eligible permit is kept (all 57 original columns).
#
# Source: EPA ECHO bulk "NPDES_DMRS_FY<year>.csv", delivered inside
#   data/raw/DMR/npdes_dmrs_fy<year>.zip.
# Population: ICIS_PERMITS.csv (data/raw/npdes_downloads/) -- a static
#   current-state extract, not FY-specific, so the "ever major individual"
#   eligible-permit set is the same regardless of which FY's DMR is filtered.
#
# Output: code/dmr/01_dmr_fy<year>.csv
#
# ---- Population definition ----------------------------------------------------
#   INDIVIDUAL : PERMIT_TYPE_CODE == "NPD".
#   EVER MAJOR : MAJOR_MINOR_STATUS_FLAG == "M" in AT LEAST ONE version row of
#                the permit (not "major every year").
#
# ---- Engine / memory ---------------------------------------------------------
# ENGINE = DuckDB, out-of-core (DMR CSVs are multi-GB, too large for this 8GB
# machine's RAM). Decompresses the zip member to a per-FY gzip temp on
# scratch disk, then lets DuckDB stream + spill to disk.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(DBI)
  library(duckdb)
})

## ---- FY from command line ----
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1 || is.na(suppressWarnings(as.integer(args[1]))))
  stop("Usage: Rscript filter_dmr_major_individual.R <FY>  (e.g. 2025)")
FY <- as.integer(args[1])

## ---- Config ----
ZIP_NAME   <- sprintf("npdes_dmrs_fy%d.zip", FY)
CSV_MEMBER <- sprintf("NPDES_DMRS_FY%d.csv", FY)
ZIP_PATH   <- file.path(DMR_DIR, ZIP_NAME)
PERMITS    <- file.path(RAW_DIR, "ICIS_PERMITS.csv")

DMR_FILTER_DIR <- file.path(CWA_ROOT, "code", "dmr")
OUT_PATH   <- file.path(DMR_FILTER_DIR, sprintf("01_dmr_fy%d.csv", FY))

# Scratch dir named per-FY so gz caches for different years never collide.
SCRATCH   <- Sys.getenv("CWA_SCRATCH", file.path(tempdir(), sprintf("cwa_dmr_mi_fy%d", FY)))
GZ_TMP    <- file.path(SCRATCH, sprintf("NPDES_DMRS_FY%d.csv.gz", FY))
ELIGIBLE_TMP <- file.path(SCRATCH, "eligible_permits.csv")
DUCK_TMP  <- file.path(SCRATCH, "duckdb_spill")
REUSE_GZ  <- TRUE
KEEP_GZ   <- FALSE
MEM_LIMIT <- "5GB"

dir.create(SCRATCH,  showWarnings = FALSE, recursive = TRUE)
dir.create(DUCK_TMP, showWarnings = FALSE, recursive = TRUE)
dir.create(DMR_FILTER_DIR, showWarnings = FALSE, recursive = TRUE)

if (!file.exists(ZIP_PATH)) stop("FY", FY, " DMR zip not found: ", ZIP_PATH)
message("FY: ", FY)
message("DMR zip: ", ZIP_PATH)

# ---- 1. Ever-major INDIVIDUAL permit set from ICIS_PERMITS -------------------
pm <- fread(PERMITS, select = c("EXTERNAL_PERMIT_NMBR", "PERMIT_TYPE_CODE",
                                "MAJOR_MINOR_STATUS_FLAG"),
            colClasses = "character", showProgress = FALSE)
pm[, id   := trimws(EXTERNAL_PERMIT_NMBR)]
pm[, ptc  := trimws(PERMIT_TYPE_CODE)]
pm[, flag := trimws(MAJOR_MINOR_STATUS_FLAG)]
pm <- pm[ptc == "NPD"]
major_ind <- pm[, .(ever_major = any(flag == "M")), by = id][ever_major == TRUE, id]
message("Individual (NPD) permits in ICIS_PERMITS       : ", uniqueN(pm$id))
message("...ever major (eligible permit set)            : ", length(major_ind))

fwrite(data.table(EXTERNAL_PERMIT_NMBR = major_ind), ELIGIBLE_TMP)

# ---- 2. Decompress the CSV member -> gzip temp (once) ------------------------
if (REUSE_GZ && file.exists(GZ_TMP) && file.info(GZ_TMP)$size > 0) {
  message("Reusing existing gzip temp: ", GZ_TMP,
          " (", round(file.info(GZ_TMP)$size / 1e9, 2), " GB)")
} else {
  message("Streaming CSV member out of the zip and re-gzipping to: ", GZ_TMP)
  cmd <- sprintf("tar -xOf %s %s | gzip -1 > %s",
                 shQuote(ZIP_PATH), shQuote(CSV_MEMBER), shQuote(GZ_TMP))
  t0 <- Sys.time()
  status <- system(cmd)
  if (status != 0) stop("Extraction pipeline failed (exit ", status, ").")
  message("  extract+gzip done in ",
          round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min; ",
          round(file.info(GZ_TMP)$size / 1e9, 2), " GB gz")
}

# ---- 3. DuckDB, out-of-core ---------------------------------------------------
con <- dbConnect(duckdb::duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, sprintf("SET memory_limit='%s';", MEM_LIMIT))
dbExecute(con, sprintf("SET temp_directory='%s';", DUCK_TMP))
dbExecute(con, "SET preserve_insertion_order=false;")

READ_CSV <- sprintf("read_csv('%s', all_varchar=true, header=true, sample_size=-1)", GZ_TMP)
ELIGIBLE_CSV <- sprintf("read_csv('%s', all_varchar=true, header=true)", ELIGIBLE_TMP)

# ---- 4. Write the filtered file (all columns, streamed straight to CSV) -------
message("\nFiltering to ever-major individual permits and writing -> ", OUT_PATH)
dbExecute(con, sprintf("
  COPY (
    SELECT d.*
    FROM %s d
    INNER JOIN %s e
      ON trim(d.EXTERNAL_PERMIT_NMBR) = trim(e.EXTERNAL_PERMIT_NMBR)
  ) TO '%s' (HEADER, DELIMITER ',');",
  READ_CSV, ELIGIBLE_CSV, OUT_PATH))

# ---- 5. Verify the output ----------------------------------------------------
OUT_CSV <- sprintf("read_csv('%s', all_varchar=true, header=true, sample_size=-1)", OUT_PATH)

in_ncol  <- length(dbGetQuery(con, sprintf("SELECT * FROM %s LIMIT 0", READ_CSV)))
out_ncol <- length(dbGetQuery(con, sprintf("SELECT * FROM %s LIMIT 0", OUT_CSV)))

chk <- dbGetQuery(con, sprintf("
  SELECT count(*)                              AS n_rows,
         count(DISTINCT EXTERNAL_PERMIT_NMBR)  AS n_permits,
         count(DISTINCT PARAMETER_CODE)        AS n_param,
         count(DISTINCT PERM_FEATURE_TYPE_CODE) AS n_feat,
         count(DISTINCT MONITORING_LOCATION_CODE) AS n_monloc,
         min(MONITORING_PERIOD_END_DATE)       AS first_period,
         max(MONITORING_PERIOD_END_DATE)       AS last_period
  FROM %s", OUT_CSV))

bad_permits <- dbGetQuery(con, sprintf("
  SELECT count(*) AS n FROM (
    SELECT DISTINCT trim(EXTERNAL_PERMIT_NMBR) AS id FROM %s
  ) o
  WHERE o.id NOT IN (SELECT trim(EXTERNAL_PERMIT_NMBR) FROM %s)",
  OUT_CSV, ELIGIBLE_CSV))$n

message("\n=== DONE (FY", FY, ") ===")
message("Output:                ", OUT_PATH)
message("Rows:                  ", format(chk$n_rows,   big.mark = ","))
message("Distinct permits:      ", format(chk$n_permits, big.mark = ","),
        " (of ", length(major_ind), " eligible)")
message("Columns (in / out):    ", in_ncol, " / ", out_ncol,
        if (in_ncol == out_ncol) "  (match)" else "  (MISMATCH!)")
message("Distinct parameter codes / feature types / monitoring locations kept: ",
        chk$n_param, " / ", chk$n_feat, " / ", chk$n_monloc)
message("Monitoring period text range: ", chk$first_period, " .. ", chk$last_period)
message("Output permits not in the eligible set (should be 0): ", bad_permits)

if (in_ncol != out_ncol || bad_permits > 0)
  stop("Verification FAILED -- see mismatches above. Output left in place for inspection.")
message("Verification passed.")

# ---- 6. Cleanup --------------------------------------------------------------
if (!KEEP_GZ && file.exists(GZ_TMP)) {
  unlink(GZ_TMP)
  message("Removed gzip temp (set KEEP_GZ=TRUE to retain for faster re-runs).")
}
unlink(ELIGIBLE_TMP)
unlink(DUCK_TMP, recursive = TRUE)
