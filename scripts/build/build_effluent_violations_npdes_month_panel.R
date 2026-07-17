# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_ROOT, PROC_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# build_effluent_violations_npdes_month_panel.R
# ------------------------------------------------------------------------------
# Build an NPDES_ID-by-MONTH panel of effluent-violation counts, 2005-2025,
# with one column per target violation code: n_D80, n_D90, n_E90.
#
# Source: EPA ECHO bulk "NPDES_EFF_VIOLATIONS.csv" (~15.9 GB uncompressed),
#   delivered inside data/raw/npdes_eff_downloads*.zip (a zip64 archive).
#
# Output: data/processed/effluent_violations_npdes_month_panel_2005_2025.csv
#
# ---- Design decisions (see project notes / prior discussion) -----------------
#   * MONTH  = calendar month of MONITORING_PERIOD_END_DATE (the DMR reporting
#              period the violation pertains to). Format in the file: MM/DD/YYYY.
#   * SCOPE  = observed ID-months only. A row appears only where >=1 target code
#              occurred; there is NO zero-filled balanced grid. A month absent
#              for an NPDES_ID means "no D80/D90/E90 that month".
#   * COUNT  = distinct underlying violation, latest VERSION_NMBR only. DMR
#              resubmissions store the same violation under an incremented
#              VERSION_NMBR. Because the underlying-violation key (below) already
#              pins down the monitoring period, feature, parameter, limit-set and
#              statistical base, "keep the latest version" is IDENTICAL, for a
#              count, to "count DISTINCT keys": every version of one violation
#              collapses to a single key. We therefore COUNT(DISTINCT vkey) per
#              (NPDES_ID, month, code) -- validated against a row_number() dedup
#              on a 3M-row sample (both give the same total). This also avoids a
#              DuckDB internal-planner bug in row_number() OVER (PARTITION BY ...).
#   * ENGINE = DuckDB, out-of-core. The 15.9 GB CSV cannot be held in RAM on this
#              machine (8 GB). We decompress the zip member to a gzip temp on
#              scratch disk (~3-4 GB), then let DuckDB stream + spill to disk.
#
# WHY A TEMP FILE: DuckDB reads files, not .zip members, and reading a CSV from a
# non-seekable pipe breaks its sniffer. We stream the single CSV member out of
# the zip with `tar` (libarchive) and gzip it once; DuckDB reads the .gz directly.
#
# CAVEAT (logged, not corrected): counts are taken over rows already filtered to
# the target codes. If a later VERSION_NMBR corrected a period to compliant, that
# compliant row is not in the file as a violation, so such a "flip to compliant"
# is not netted out. In the sample only ~0.3% of violations had ANY resubmission,
# so this is negligible; flag if it ever matters.
# ==============================================================================

# ---- 0. Setup ----------------------------------------------------------------
suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
})

## ---- Config (edit here) ----
YEAR_MIN     <- 2005L
YEAR_MAX     <- 2025L
TARGET_CODES <- c("D80", "D90", "E90")   # VIOLATION_CODE values -> one count column each
DATE_COL     <- "MONITORING_PERIOD_END_DATE"
DATE_FORMAT  <- "%m/%d/%Y"               # ECHO's format for the date column

# Columns that (together with the parsed monitoring-period date) identify ONE
# underlying violation, independent of resubmission VERSION_NMBR. NPDES_ID is
# included so a key is unique across permits, not just within one.
VKEY_COLS <- c("NPDES_ID", "PERM_FEATURE_NMBR", "LIMIT_SET_DESIGNATOR",
               "MONITORING_LOCATION_CODE", "PARAMETER_CODE", "STATISTICAL_BASE_CODE")

SCRATCH   <- Sys.getenv("CWA_SCRATCH", file.path(tempdir(), "cwa_eff"))
GZ_TMP    <- file.path(SCRATCH, "NPDES_EFF_VIOLATIONS.csv.gz")   # decompressed member, re-gzipped
DUCK_TMP  <- file.path(SCRATCH, "duckdb_spill")                  # DuckDB out-of-core spill dir
REUSE_GZ  <- TRUE          # reuse an existing GZ_TMP instead of re-extracting the 16 GB member
KEEP_GZ   <- FALSE         # keep GZ_TMP after the run (TRUE speeds up re-runs; costs ~3-4 GB)
MEM_LIMIT <- "5GB"         # DuckDB RAM cap; it spills to DUCK_TMP beyond this

OUT_PATH  <- file.path(PROC_DIR, "effluent_violations_npdes_month_panel_2005_2025.csv")

dir.create(SCRATCH,  showWarnings = FALSE, recursive = TRUE)
dir.create(DUCK_TMP, showWarnings = FALSE, recursive = TRUE)
dir.create(PROC_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- 1. Locate the effluent-violations zip -----------------------------------
# NOTE: the filename contains a non-breaking narrow space (U+202F), so we never
# hardcode it -- match by pattern and pass the exact path through as bytes.
zip_hits <- list.files(RAW_ROOT, pattern = "npdes_eff.*\\.zip$",
                       ignore.case = TRUE, full.names = TRUE)
if (length(zip_hits) == 0)
  stop("No effluent-violations zip found under ", RAW_ROOT,
       " (looked for 'npdes_eff*.zip').")
ZIP_PATH <- zip_hits[1]
message("Effluent zip: ", ZIP_PATH)

# ---- 2. Decompress the CSV member -> gzip temp (once) ------------------------
# `tar` on macOS is libarchive and streams the single zip member to stdout.
# The zip filename contains a non-breaking narrow space (U+202F). Passing that
# byte through system() fails if the R session locale isn't UTF-8, so we keep it
# OUT of the shell string: cd into the (ASCII) raw dir and let an ASCII glob
# expand to the file. Pathname-expansion results are not word-split, so the
# spaces / U+202F stay intact as a single argument to tar.
if (REUSE_GZ && file.exists(GZ_TMP) && file.info(GZ_TMP)$size > 0) {
  message("Reusing existing gzip temp: ", GZ_TMP,
          " (", round(file.info(GZ_TMP)$size / 1e9, 2), " GB)")
} else {
  zip_dir  <- dirname(ZIP_PATH)             # ASCII (…/data/raw)
  zip_glob <- "npdes_eff_downloads*.zip"    # ASCII; must match exactly one file
  if (length(Sys.glob(file.path(zip_dir, zip_glob))) != 1)
    stop("Expected exactly one file matching ", zip_glob, " in ", zip_dir)
  message("Streaming CSV member out of the zip and re-gzipping to: ", GZ_TMP)
  message("  (one pass over ~15.9 GB; this takes several minutes)")
  cmd <- sprintf("cd %s && tar -xOf %s | gzip -1 > %s",
                 shQuote(zip_dir), zip_glob, shQuote(GZ_TMP))
  t0 <- Sys.time()
  status <- system(cmd)
  if (status != 0) stop("Extraction pipeline failed (exit ", status, ").")
  message("  extract+gzip done in ",
          round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min; ",
          round(file.info(GZ_TMP)$size / 1e9, 2), " GB gz")
}

# ---- 3. DuckDB: load target rows once, then count distinct violations ---------
con <- dbConnect(duckdb::duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, sprintf("SET memory_limit='%s';", MEM_LIMIT))
dbExecute(con, sprintf("SET temp_directory='%s';", DUCK_TMP))
dbExecute(con, "SET preserve_insertion_order=false;")  # lower memory for sort/aggregate

codes_sql <- paste(sprintf("'%s'", TARGET_CODES), collapse = ", ")

# vkey = the underlying-violation identity, as one delimited string (chr(31) =
# unit separator, safe against collisions). Includes the parsed period date.
vkey_sql <- sprintf("concat_ws(chr(31), %s, CAST(mped AS VARCHAR))",
                    paste(VKEY_COLS, collapse = ", "))

date_parse <- sprintf("try_strptime(%s, '%s')", DATE_COL, DATE_FORMAT)

# all_varchar=true: read every column as text (43 cols, ECHO quirks), cast in
# SQL -- mirrors the colClasses="character" pattern used elsewhere in the repo.
# One CSV parse populates t_win (target codes, valid date, in the year window).
message("\nParsing effluent CSV and loading target-code rows into DuckDB ...")
t0 <- Sys.time()
dbExecute(con, sprintf("
  CREATE TEMP TABLE t_win AS
  SELECT
    NPDES_ID,
    VIOLATION_CODE,
    CAST(date_trunc('month', mped) AS DATE) AS month,
    %s AS vkey
  FROM (
    SELECT *, %s AS mped
    FROM read_csv('%s', all_varchar=true, header=true, sample_size=-1)
    WHERE VIOLATION_CODE IN (%s)
  )
  WHERE mped IS NOT NULL
    AND CAST(mped AS DATE) >= DATE '%d-01-01'
    AND CAST(mped AS DATE) <  DATE '%d-01-01'",
  vkey_sql, date_parse, GZ_TMP, codes_sql, YEAR_MIN, YEAR_MAX + 1L))
message("  loaded in ",
        round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min")

# ---- 3a. Diagnostics: raw target rows vs de-duplicated (latest version) -------
diag <- dbGetQuery(con, "
  SELECT count(*)                                             AS rows_raw_in_window,
         count(DISTINCT concat_ws(chr(31), VIOLATION_CODE, vkey)) AS rows_deduped_latest_version
  FROM t_win")
message("\n--- de-duplication check (full file, ", YEAR_MIN, "-", YEAR_MAX, ") ---")
message("raw target rows in window:      ", format(diag$rows_raw_in_window, big.mark=","))
message("deduped (latest version) count: ", format(diag$rows_deduped_latest_version, big.mark=","))
message(sprintf("resubmissions removed:          %s (%.2f%%)",
                format(diag$rows_raw_in_window - diag$rows_deduped_latest_version, big.mark=","),
                100 * (1 - diag$rows_deduped_latest_version / diag$rows_raw_in_window)))

# ---- 4. Aggregate to NPDES_ID x month, one distinct-count column per code -----
# COPY straight to CSV (memory-light; never materialises the panel in R).
count_cols <- paste(sprintf(
  "COUNT(DISTINCT CASE WHEN VIOLATION_CODE='%s' THEN vkey END) AS n_%s",
  TARGET_CODES, TARGET_CODES), collapse = ",\n         ")

message("\nWriting panel via DuckDB COPY -> ", OUT_PATH)
dbExecute(con, sprintf("
  COPY (
    SELECT NPDES_ID, month,
           %s
    FROM t_win
    GROUP BY NPDES_ID, month
    ORDER BY NPDES_ID, month
  ) TO '%s' (HEADER, DELIMITER ',');",
  count_cols, OUT_PATH))

# ---- 5. Report ---------------------------------------------------------------
rep <- dbGetQuery(con, sprintf("
  WITH p AS (SELECT * FROM read_csv('%s', header=true))
  SELECT count(*) AS n_rows,
         count(DISTINCT NPDES_ID) AS n_npdes,
         min(month) AS first_month, max(month) AS last_month,
         sum(n_D80) AS tot_D80, sum(n_D90) AS tot_D90, sum(n_E90) AS tot_E90
  FROM p", OUT_PATH))

message("\n=== DONE ===")
message("Panel rows (NPDES_ID x month): ", format(rep$n_rows,  big.mark=","))
message("Distinct NPDES_IDs:            ", format(rep$n_npdes, big.mark=","))
message("Month range:                   ", rep$first_month, " .. ", rep$last_month)
message("Total D80 / D90 / E90:         ",
        format(rep$tot_D80, big.mark=","), " / ",
        format(rep$tot_D90, big.mark=","), " / ",
        format(rep$tot_E90, big.mark=","))
message("(D80+D90+E90 should equal the deduped count above: ",
        format(rep$tot_D80 + rep$tot_D90 + rep$tot_E90, big.mark=","), ")")
message("Written to:                    ", OUT_PATH)

# ---- 6. Cleanup --------------------------------------------------------------
if (!KEEP_GZ && file.exists(GZ_TMP)) {
  unlink(GZ_TMP)
  message("Removed gzip temp (set KEEP_GZ=TRUE to retain for faster re-runs).")
}
unlink(DUCK_TMP, recursive = TRUE)
