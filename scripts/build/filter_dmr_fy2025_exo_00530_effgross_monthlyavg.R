# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, DMR_DIR, PROC_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R
# ------------------------------------------------------------------------------
# Row-filter the FY2025 DMR file down to a single, small CSV that keeps only the
# lines matching all four criteria below. ALL 57 original columns are preserved
# (this is a row filter, not a column selection).
#
# Source: EPA ECHO bulk "NPDES_DMRS_FY2025.csv" (~9.68 GB uncompressed),
#   delivered inside data/raw/DMR/npdes_dmrs_fy2025.zip.
#
# Output: data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg.csv
#
# ---- Filter criteria -> exact ICIS codes (verified, not guessed) -------------
#   PERM_FEATURE_TYPE_CODE   = 'EXO'          external outfall
#                                             (docs/panel_questions_for_pis.md)
#   PARAMETER_CODE           = '00530'        Solids, total suspended (TSS)
#   MONITORING_LOCATION_CODE in {'1','EG'}    "Effluent Gross". Repo notes say the
#                                             bulk files use '1'; EPA's reference
#                                             table maps BOTH '1' and 'EG' to
#                                             "Effluent Gross", so we accept both
#                                             and log which actually appears rather
#                                             than silently dropping rows.
#   STATISTICAL_BASE_CODE    = 'MK'           "Monthly Average" (the average
#                                             monthly limit) -- EPA reference
#                                             REF_STATISTICAL_BASE.csv.
#
#   All four conditions are ANDed. For TSS (00530) a monthly-average limit is
#   expressed either as a concentration (mg/L) or a quantity/mass load (lb/day,
#   kg/day); STATISTICAL_BASE_CODE='MK' already captures BOTH, so the parenthetical
#   "(concentration or quantity mass load)" is not an extra filter -- both forms
#   are kept and their split is reported in the diagnostics below.
#
# ---- Engine / memory ---------------------------------------------------------
# ENGINE = DuckDB, out-of-core. The 9.68 GB CSV cannot be held in RAM on this
# machine (8 GB). We decompress the single zip member to a gzip temp on scratch
# disk (~4 GB), then let DuckDB stream + spill to disk. Mirrors the pattern in
# scripts/build/build_effluent_violations_npdes_month_panel.R.
#
# WHY A TEMP FILE: DuckDB reads files, not .zip members, and reading a CSV from a
# non-seekable pipe breaks its sniffer. We stream the single CSV member out of
# the zip with `tar` (libarchive) and gzip it once; DuckDB reads the .gz directly.
# ==============================================================================

# ---- 0. Setup ----------------------------------------------------------------
suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
})

## ---- Config (edit here) ----
FY            <- 2025L
ZIP_NAME      <- sprintf("npdes_dmrs_fy%d.zip", FY)
CSV_MEMBER    <- sprintf("NPDES_DMRS_FY%d.csv", FY)   # member name inside the zip

# Filter values, named for readability. Effluent-gross accepts both known codes.
F_PERM_FEATURE_TYPE <- "EXO"
F_PARAMETER         <- "00530"
F_MON_LOC           <- c("1", "EG")   # both = "Effluent Gross" per EPA reference
F_STAT_BASE         <- "MK"           # "Monthly Average" per REF_STATISTICAL_BASE

SCRATCH   <- Sys.getenv("CWA_SCRATCH", file.path(tempdir(), "cwa_dmr"))
GZ_TMP    <- file.path(SCRATCH, sprintf("NPDES_DMRS_FY%d.csv.gz", FY))  # member, re-gzipped
DUCK_TMP  <- file.path(SCRATCH, "duckdb_spill")                         # DuckDB out-of-core spill
REUSE_GZ  <- TRUE          # reuse an existing GZ_TMP instead of re-extracting the member
KEEP_GZ   <- FALSE         # keep GZ_TMP after the run (TRUE speeds re-runs; costs ~4 GB)
MEM_LIMIT <- "5GB"         # DuckDB RAM cap; it spills to DUCK_TMP beyond this

OUT_PATH  <- file.path(PROC_DIR, "dmr_fy2025_exo_00530_effgross_monthlyavg.csv")

dir.create(SCRATCH,  showWarnings = FALSE, recursive = TRUE)
dir.create(DUCK_TMP, showWarnings = FALSE, recursive = TRUE)
dir.create(PROC_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- 1. Locate the FY2025 DMR zip --------------------------------------------
ZIP_PATH <- file.path(DMR_DIR, ZIP_NAME)
if (!file.exists(ZIP_PATH))
  stop("FY", FY, " DMR zip not found: ", ZIP_PATH)
message("DMR zip: ", ZIP_PATH)

# ---- 2. Decompress the CSV member -> gzip temp (once) ------------------------
# `tar` on macOS is libarchive and streams a single named zip member to stdout.
if (REUSE_GZ && file.exists(GZ_TMP) && file.info(GZ_TMP)$size > 0) {
  message("Reusing existing gzip temp: ", GZ_TMP,
          " (", round(file.info(GZ_TMP)$size / 1e9, 2), " GB)")
} else {
  message("Streaming CSV member out of the zip and re-gzipping to: ", GZ_TMP)
  message("  (one pass over ~9.68 GB; this takes a few minutes)")
  cmd <- sprintf("tar -xOf %s %s | gzip -1 > %s",
                 shQuote(ZIP_PATH), shQuote(CSV_MEMBER), shQuote(GZ_TMP))
  t0 <- Sys.time()
  status <- system(cmd)
  if (status != 0) stop("Extraction pipeline failed (exit ", status, ").")
  message("  extract+gzip done in ",
          round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min; ",
          round(file.info(GZ_TMP)$size / 1e9, 2), " GB gz")
}

# ---- 3. DuckDB, out-of-core --------------------------------------------------
con <- dbConnect(duckdb::duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, sprintf("SET memory_limit='%s';", MEM_LIMIT))
dbExecute(con, sprintf("SET temp_directory='%s';", DUCK_TMP))
dbExecute(con, "SET preserve_insertion_order=false;")  # lower memory for scans

# Build the WHERE clause once, reused for diagnostics and the write.
in_list <- function(vals) paste(sprintf("'%s'", vals), collapse = ", ")
WHERE_SQL <- sprintf(
  "PERM_FEATURE_TYPE_CODE = '%s'
   AND PARAMETER_CODE = '%s'
   AND MONITORING_LOCATION_CODE IN (%s)
   AND STATISTICAL_BASE_CODE = '%s'",
  F_PERM_FEATURE_TYPE, F_PARAMETER, in_list(F_MON_LOC), F_STAT_BASE)

# all_varchar=true: read every column as text (57 cols, ECHO quirks incl. leading
# zeros in PARAMETER_CODE), no type sniffing -- mirrors the colClasses="character"
# convention used elsewhere in the repo. read_csv reference reused twice below.
READ_CSV <- sprintf("read_csv('%s', all_varchar=true, header=true, sample_size=-1)", GZ_TMP)

# ---- 3a. Diagnostics on the EXO + 00530 subset (traceability) ----------------
# Show, within external-outfall TSS rows, how the monitoring-location and
# statistical-base codes are actually distributed -- confirms '1' vs 'EG' and
# that both concentration and mass-load forms are present before we narrow.
message("\nScanning FY", FY, " DMR for diagnostics (EXO + ", F_PARAMETER, ") ...")
t0 <- Sys.time()
diag <- dbGetQuery(con, sprintf("
  SELECT MONITORING_LOCATION_CODE, STATISTICAL_BASE_CODE,
         VALUE_TYPE_CODE, STANDARD_UNIT_DESC,
         count(*) AS n
  FROM %s
  WHERE PERM_FEATURE_TYPE_CODE = '%s' AND PARAMETER_CODE = '%s'
  GROUP BY 1,2,3,4
  ORDER BY n DESC",
  READ_CSV, F_PERM_FEATURE_TYPE, F_PARAMETER))
message("  diagnostic scan done in ",
        round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min")

message("\n--- EXO + ", F_PARAMETER,
        " breakdown by (mon_loc, stat_base, value_type, std_unit) ---")
if (nrow(diag) == 0) {
  message("  (no EXO rows for parameter ", F_PARAMETER, " in FY", FY, ")")
} else {
  print(utils::head(diag[order(-diag$n), ], 40), row.names = FALSE)
  message("\nRealized MONITORING_LOCATION_CODE values (EXO+", F_PARAMETER, "): ",
          paste(sort(unique(diag$MONITORING_LOCATION_CODE)), collapse = ", "))
  hit_mk <- diag[diag$STATISTICAL_BASE_CODE %in% F_STAT_BASE &
                 diag$MONITORING_LOCATION_CODE %in% F_MON_LOC, , drop = FALSE]
  message("Effluent-gross monthly-average (MK) rows split by unit:")
  if (nrow(hit_mk) == 0) message("  (none)")
  else print(aggregate(n ~ STANDARD_UNIT_DESC, hit_mk, sum), row.names = FALSE)
}

# ---- 4. Write the filtered file (all columns, streamed straight to CSV) -------
# Guard: refuse to write an empty output -- surface it instead (CLAUDE.md rule).
n_match <- dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s WHERE %s",
                                   READ_CSV, WHERE_SQL))$n
if (n_match == 0)
  stop("Zero rows matched all four filters -- NOT writing an empty file. ",
       "Check the diagnostics above (esp. MONITORING_LOCATION_CODE) before rerunning.")

message("\nMatching rows: ", format(n_match, big.mark = ","),
        " -> writing all 57 columns to ", OUT_PATH)
dbExecute(con, sprintf("
  COPY (SELECT * FROM %s WHERE %s)
  TO '%s' (HEADER, DELIMITER ',');",
  READ_CSV, WHERE_SQL, OUT_PATH))

# ---- 5. Verify the output ----------------------------------------------------
OUT_CSV <- sprintf("read_csv('%s', all_varchar=true, header=true, sample_size=-1)", OUT_PATH)
chk <- dbGetQuery(con, sprintf("
  SELECT count(*)                                       AS n_rows,
         count(DISTINCT EXTERNAL_PERMIT_NMBR)           AS n_permits,
         count(DISTINCT PARAMETER_CODE)                 AS n_param,
         count(DISTINCT PERM_FEATURE_TYPE_CODE)         AS n_feat,
         count(DISTINCT STATISTICAL_BASE_CODE)          AS n_stat,
         min(MONITORING_PERIOD_END_DATE)                AS first_period,
         max(MONITORING_PERIOD_END_DATE)                AS last_period
  FROM %s", OUT_CSV))

# Column-count parity: output header must match the source's 57 columns.
in_ncol  <- length(dbGetQuery(con, sprintf("SELECT * FROM %s LIMIT 0", READ_CSV)))
out_ncol <- length(dbGetQuery(con, sprintf("SELECT * FROM %s LIMIT 0", OUT_CSV)))

# Value-domain assertions: every kept row must satisfy each filter.
bad <- dbGetQuery(con, sprintf("
  SELECT
    sum(CASE WHEN PERM_FEATURE_TYPE_CODE <> '%s' THEN 1 ELSE 0 END)      AS bad_feat,
    sum(CASE WHEN PARAMETER_CODE <> '%s' THEN 1 ELSE 0 END)              AS bad_param,
    sum(CASE WHEN MONITORING_LOCATION_CODE NOT IN (%s) THEN 1 ELSE 0 END) AS bad_loc,
    sum(CASE WHEN STATISTICAL_BASE_CODE <> '%s' THEN 1 ELSE 0 END)       AS bad_stat
  FROM %s",
  F_PERM_FEATURE_TYPE, F_PARAMETER, in_list(F_MON_LOC), F_STAT_BASE, OUT_CSV))

message("\n=== DONE ===")
message("Output:                ", OUT_PATH)
message("Rows:                  ", format(chk$n_rows,   big.mark = ","))
message("Distinct permits:      ", format(chk$n_permits, big.mark = ","))
message("Columns (in / out):    ", in_ncol, " / ", out_ncol,
        if (in_ncol == out_ncol) "  (match)" else "  (MISMATCH!)")
message("Monitoring period:     ", chk$first_period, " .. ", chk$last_period)
message("Distinct param / feat / stat-base in output: ",
        chk$n_param, " / ", chk$n_feat, " / ", chk$n_stat, " (each should be 1)")
message("Filter violations in output (all should be 0): feat=", bad$bad_feat,
        " param=", bad$bad_param, " loc=", bad$bad_loc, " stat=", bad$bad_stat)

if (in_ncol != out_ncol || chk$n_param != 1 || chk$n_feat != 1 || chk$n_stat != 1 ||
    bad$bad_feat + bad$bad_param + bad$bad_loc + bad$bad_stat > 0)
  stop("Verification FAILED -- see mismatches above. Output left in place for inspection.")
message("Verification passed.")

# ---- 6. Cleanup --------------------------------------------------------------
if (!KEEP_GZ && file.exists(GZ_TMP)) {
  unlink(GZ_TMP)
  message("Removed gzip temp (set KEEP_GZ=TRUE to retain for faster re-runs).")
}
unlink(DUCK_TMP, recursive = TRUE)
