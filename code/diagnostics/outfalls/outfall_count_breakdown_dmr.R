# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# outfall_count_breakdown_dmr.R
# ------------------------------------------------------------------------------
# Companion to outfall_count_breakdown.R (same folder). That script counts
# outfalls from NPDES_LIMITS.csv -- i.e. outfalls a facility is PERMITTED to
# discharge from, whether or not anything was ever reported there. This script
# counts outfalls from the DMR file instead -- i.e. outfalls that actually
# SUBMITTED at least one monitoring report in the fiscal year. These are
# different questions and will not match:
#   LIMITS = "how many outfalls is this facility permitted for" (structural)
#   DMR    = "how many outfalls actually reported this year"    (realized)
#   DMR <= LIMITS always, in principle: a permitted outfall can go a full
#   fiscal year with no required/received DMR event (infrequent monitoring
#   schedule, late reissuance, terminated outfall, etc.).
#
# IDENTIFIER: PERM_FEATURE_ID, not PERM_FEATURE_NMBR -- same reasoning as the
#   LIMITS script: PERM_FEATURE_ID is regenerated at every permit reissuance.
#   This matters WITHIN a single fiscal year's DMR file too, not just across
#   NPDES_LIMITS' full history: of 34,797 permits with TSS DMR activity in
#   FY2025, 4,045 (11.6%) span more than one VERSION_NMBR (a mid-year
#   reissuance), and PERM_FEATURE_ID disagrees with PERM_FEATURE_NMBR for
#   3,993 of those (measured). Fix: restrict to each permit's LATEST
#   VERSION_NMBR *observed within this fiscal year's DMR data* before counting
#   distinct PERM_FEATURE_ID. ("Latest observed" here, vs. "latest ever
#   issued" in the LIMITS script -- a DMR file only contains one year, so this
#   is the natural in-file analogue.)
#
# SCOPE: PERM_FEATURE_TYPE_CODE = 'EXO' only; ALL parameters (not restricted
#   to TSS or any pollutant) -- an outfall counts if it reported ANYTHING that
#   year. Facilities are the panel's 7,511 major-individual facilities;
#   multi-permit facilities (427) count distinct outfalls across all their
#   permits. Fiscal year is configurable (FY below), default 2025.
#
# Engine: DuckDB, out-of-core. The FY DMR CSV (~9.7GB) lives inside a zip;
# DuckDB can't read a zip member directly (non-seekable pipe breaks its
# sniffer), so the member is streamed out with `tar` and re-gzipped to scratch
# once (mirrors the external ../EIL Summer/build/filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R
# -- same GZ_TMP path/convention, so a gz already extracted by that script is
# reused here too, and vice versa).
#
# Read-only on raw + processed data. Writes a timestamped CSV to output/tables/.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(DBI)
  library(duckdb)
})

## ---- Config ----
FY          <- 2025L
ZIP_NAME    <- sprintf("npdes_dmrs_fy%d.zip", FY)
CSV_MEMBER  <- sprintf("NPDES_DMRS_FY%d.csv", FY)
F_PERM_FEATURE_TYPE <- "EXO"

PANEL_FILE <- file.path(PROC_DIR, "06_facility_month_panel_major_individual_effluent_2005_2025.csv")
SCRATCH    <- Sys.getenv("CWA_SCRATCH", file.path(tempdir(), "cwa_dmr"))
GZ_TMP     <- file.path(SCRATCH, sprintf("NPDES_DMRS_FY%d.csv.gz", FY))
DUCK_TMP   <- file.path(SCRATCH, "duckdb_spill")
REUSE_GZ   <- TRUE
MEM_LIMIT  <- "5GB"
OUT_DIR    <- file.path(CWA_ROOT, "output/tables")

dir.create(SCRATCH,  showWarnings = FALSE, recursive = TRUE)
dir.create(DUCK_TMP, showWarnings = FALSE, recursive = TRUE)

# ---- 1. Locate the DMR zip, decompress the CSV member -> gzip temp (once) -----
ZIP_PATH <- file.path(DMR_DIR, ZIP_NAME)
if (!file.exists(ZIP_PATH)) stop("FY", FY, " DMR zip not found: ", ZIP_PATH)

if (REUSE_GZ && file.exists(GZ_TMP) && file.info(GZ_TMP)$size > 0) {
  message("Reusing existing gzip temp: ", GZ_TMP,
          " (", round(file.info(GZ_TMP)$size / 1e9, 2), " GB)")
} else {
  message("Streaming CSV member out of the zip and re-gzipping to: ", GZ_TMP)
  message("  (one pass over ~9.7 GB; this takes a few minutes)")
  cmd <- sprintf("tar -xOf %s %s | gzip -1 > %s",
                 shQuote(ZIP_PATH), shQuote(CSV_MEMBER), shQuote(GZ_TMP))
  t0 <- Sys.time()
  status <- system(cmd)
  if (status != 0) stop("Extraction pipeline failed (exit ", status, ").")
  message("  extract+gzip done in ",
          round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min")
}

# ---- 2. DuckDB: distinct (permit, version, EXO feature) directly off the gz ----
con <- dbConnect(duckdb::duckdb())
dbExecute(con, sprintf("SET memory_limit='%s';", MEM_LIMIT))
dbExecute(con, sprintf("SET temp_directory='%s';", DUCK_TMP))
dbExecute(con, "SET preserve_insertion_order=false;")

message("Scanning FY", FY, " DMR for EXO outfalls (all parameters) ...")
t0 <- Sys.time()
outfalls_all_versions <- as.data.table(dbGetQuery(con, sprintf(
  "SELECT DISTINCT EXTERNAL_PERMIT_NMBR AS PERMIT, VERSION_NMBR, PERM_FEATURE_ID AS FEATURE_ID
   FROM read_csv('%s', all_varchar=true, header=true, sample_size=-1)
   WHERE PERM_FEATURE_TYPE_CODE = '%s' AND PERM_FEATURE_ID IS NOT NULL",
  GZ_TMP, F_PERM_FEATURE_TYPE)))
dbDisconnect(con, shutdown = TRUE)
message("  scan done in ", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min")
outfalls_all_versions[, VERSION_NMBR := as.integer(VERSION_NMBR)]
cat("Distinct (permit, version, EXO feature) rows in FY", FY, " DMR:", nrow(outfalls_all_versions), "\n")

# ---- 3. Panel facility -> permit map --------------------------------------------
panel <- fread(PANEL_FILE, select = c("FACILITY_UIN", "NPDES_ID"), showProgress = FALSE)
facilities <- unique(panel)
fac_permit_map <- facilities[, .(PERMIT = trimws(unlist(strsplit(NPDES_ID, ";")))),
                              by = FACILITY_UIN]

# ---- 4. Keep only each permit's LATEST version observed in this FY's DMR data --
latest_version <- outfalls_all_versions[, .(VERSION_NMBR = max(VERSION_NMBR, na.rm = TRUE)),
                                         by = PERMIT]
outfalls_current <- merge(outfalls_all_versions, latest_version, by = c("PERMIT", "VERSION_NMBR"))

# ---- 5. Join to panel facilities, count distinct outfalls per facility --------
joined <- merge(fac_permit_map, outfalls_current, by = "PERMIT", allow.cartesian = TRUE)
n_outfalls <- joined[, .(n_outfalls = uniqueN(FEATURE_ID)), by = FACILITY_UIN]

# Facilities with no EXO DMR activity this FY -> explicit 0 (permitted but did
# not report, OR not covered by the DMR pull -- see docs/data_quirks.md,
# NPDES_DMRS coverage row)
result <- merge(facilities[, .(FACILITY_UIN)], n_outfalls, by = "FACILITY_UIN", all.x = TRUE)
result[is.na(n_outfalls), n_outfalls := 0L]
stopifnot(nrow(result) == nrow(facilities))

# ---- 6. Report ------------------------------------------------------------------
cat("\nPanel facilities:", nrow(result), "\n")
cat("  with >=1 EXO outfall reporting in FY", FY, ":", sum(result$n_outfalls >= 1), "\n")
cat("  with 0 (no EXO DMR activity this FY):", sum(result$n_outfalls == 0), "\n\n")

cat("MULTIPLE (>1) outfalls:", sum(result$n_outfalls > 1),
    sprintf(" (%.1f%% of all %d; %.1f%% of the %d with >=1)\n",
            100 * mean(result$n_outfalls > 1), nrow(result),
            100 * sum(result$n_outfalls > 1) / sum(result$n_outfalls >= 1),
            sum(result$n_outfalls >= 1)))

dist <- result[, .N, by = n_outfalls][order(n_outfalls)]
dist[, pct_of_all := round(100 * N / nrow(result), 1)]

cat("=== Breakdown, 1 to 10 discharge points (DMR-reporting, FY", FY, ") ===\n")
print(dist[n_outfalls >= 1 & n_outfalls <= 10], row.names = FALSE)

cat("\n0 outfalls:", dist[n_outfalls == 0, N], "\n")
cat("11+ outfalls:", sum(dist[n_outfalls > 10, N]), "facilities\n")
cat("\nmedian =", median(result$n_outfalls),
    " mean =", round(mean(result$n_outfalls), 2),
    " max =", max(result$n_outfalls), "\n")

# ---- 7. Write ---------------------------------------------------------------------
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)
stamp <- format(Sys.time(), "%Y-%m-%d_%H%M")
out_facility <- file.path(OUT_DIR, sprintf("outfall_count_per_facility_dmr_fy%d_%s.csv", FY, stamp))
out_dist     <- file.path(OUT_DIR, sprintf("outfall_count_distribution_dmr_fy%d_%s.csv", FY, stamp))
fwrite(result, out_facility)
fwrite(dist, out_dist)
cat("\nWrote:", out_facility, "\n")
cat("Wrote:", out_dist, "\n")
