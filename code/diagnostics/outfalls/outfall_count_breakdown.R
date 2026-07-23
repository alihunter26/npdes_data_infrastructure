# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# outfall_count_breakdown.R
# ------------------------------------------------------------------------------
# For every facility in the major-individual facility-month panel, counts its
# current number of external discharge points (outfalls) and reports the 1-10
# breakdown.
#
# IDENTIFIER: PERM_FEATURE_ID (NPDES_LIMITS.csv), not PERM_FEATURE_NMBR.
#   PERM_FEATURE_ID is ICIS's internal key; PERM_FEATURE_NMBR is the permit's
#   human label ("001", "002", ...). They are NOT interchangeable across a
#   permit's full history: PERM_FEATURE_ID is regenerated at every reissuance.
#   Example (permit AL0023400, outfall label "001" throughout):
#     VERSION_NMBR 0 -> PERM_FEATURE_ID 3600771428
#     VERSION_NMBR 2 -> PERM_FEATURE_ID 1600002540
#     VERSION_NMBR 3 -> PERM_FEATURE_ID 3000004222
#     VERSION_NMBR 4 -> PERM_FEATURE_ID 3600227497
#   Same physical outfall, four different IDs. Counting distinct IDs across ALL
#   versions therefore counts (outfall x version) pairs, not physical outfalls,
#   and inflates the multi-outfall rate from ~62% to ~92% (measured).
#
# FIX: restrict to each permit's LATEST VERSION_NMBR before counting distinct
#   PERM_FEATURE_ID. Within one version, ID and NMBR agree almost perfectly
#   (2 of 147,646 permits differ -- measured), so this is a clean "outfalls the
#   facility currently has" snapshot count.
#
# SCOPE: PERM_FEATURE_TYPE_CODE = 'EXO' (external outfall) only; all
#   parameters (not restricted to any single pollutant). Facilities are the
#   7,511 in the major-individual facility-month panel; multi-permit
#   facilities (427 of them) count DISTINCT outfalls across all their permits.
#
# CAVEAT: this is a CURRENT-VERSION snapshot, not a facility-month time series.
#   A facility's outfall roster can and does change over its history (~31% of
#   panel facilities had their TSS-outfall count change at least once across
#   2005-2025 -- see docs/data_quirks.md). This script answers "how many
#   outfalls does the facility have on its current permit," not "how many did
#   it have in a given past year."
#
# Engine: DuckDB, out-of-core (NPDES_LIMITS.csv is ~7GB, too large to fread on
# an 8GB machine). Read-only on raw + processed data; writes a timestamped CSV
# to output/tables/.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(DBI)
  library(duckdb)
})

PANEL_FILE <- file.path(PROC_DIR, "06_facility_month_panel_major_individual_effluent_2005_2025.csv")
LIMITS_FILE <- file.path(RAW_ROOT, "NPDES_LIMITS.csv")
OUT_DIR <- file.path(CWA_ROOT, "output/tables")

# ---- 1. Panel facility -> permit map ------------------------------------------
# NPDES_ID is semicolon-joined for the 427 facilities holding >1 permit (see
# docs/data_quirks.md, ICIS_FACILITIES row); split back into one row per permit.
panel <- fread(PANEL_FILE, select = c("FACILITY_UIN", "NPDES_ID"), showProgress = FALSE)
facilities <- unique(panel)
fac_permit_map <- facilities[, .(PERMIT = trimws(unlist(strsplit(NPDES_ID, ";")))),
                              by = FACILITY_UIN]

# ---- 2. Stream NPDES_LIMITS: distinct (permit, version, EXO feature) ----------
con <- dbConnect(duckdb())
dbExecute(con, "PRAGMA memory_limit='4GB'")
outfalls_all_versions <- as.data.table(dbGetQuery(con, sprintf(
  "SELECT DISTINCT EXTERNAL_PERMIT_NMBR AS PERMIT, VERSION_NMBR, PERM_FEATURE_ID AS FEATURE_ID
   FROM read_csv_auto('%s', all_varchar=true)
   WHERE PERM_FEATURE_TYPE_CODE = 'EXO' AND PERM_FEATURE_ID IS NOT NULL",
  LIMITS_FILE)))
dbDisconnect(con, shutdown = TRUE)
outfalls_all_versions[, VERSION_NMBR := as.integer(VERSION_NMBR)]

# ---- 3. Keep only each permit's LATEST version ---------------------------------
latest_version <- outfalls_all_versions[, .(VERSION_NMBR = max(VERSION_NMBR, na.rm = TRUE)),
                                         by = PERMIT]
outfalls_current <- merge(outfalls_all_versions, latest_version, by = c("PERMIT", "VERSION_NMBR"))

# ---- 4. Join to panel facilities, count distinct outfalls per facility --------
joined <- merge(fac_permit_map, outfalls_current, by = "PERMIT", allow.cartesian = TRUE)
n_outfalls <- joined[, .(n_outfalls = uniqueN(FEATURE_ID)), by = FACILITY_UIN]

# Facilities with no EXO feature on their current version -> explicit 0
result <- merge(facilities[, .(FACILITY_UIN)], n_outfalls, by = "FACILITY_UIN", all.x = TRUE)
result[is.na(n_outfalls), n_outfalls := 0L]
stopifnot(nrow(result) == nrow(facilities))   # every panel facility accounted for

# ---- 5. Report ------------------------------------------------------------------
cat("Panel facilities:", nrow(result), "\n")
cat("  with >=1 current EXO outfall:", sum(result$n_outfalls >= 1), "\n")
cat("  with 0 (no EXO feature on current version):", sum(result$n_outfalls == 0), "\n\n")

cat("MULTIPLE (>1) outfalls:", sum(result$n_outfalls > 1),
    sprintf(" (%.1f%% of all %d; %.1f%% of the %d with >=1)\n",
            100 * mean(result$n_outfalls > 1), nrow(result),
            100 * sum(result$n_outfalls > 1) / sum(result$n_outfalls >= 1),
            sum(result$n_outfalls >= 1)))

dist <- result[, .N, by = n_outfalls][order(n_outfalls)]
dist[, pct_of_all := round(100 * N / nrow(result), 1)]

cat("\n=== Breakdown, 1 to 10 discharge points ===\n")
print(dist[n_outfalls >= 1 & n_outfalls <= 10], row.names = FALSE)

cat("\n0 outfalls:", dist[n_outfalls == 0, N], "\n")
cat("11+ outfalls:", sum(dist[n_outfalls > 10, N]), "facilities\n")
cat("\nmedian =", median(result$n_outfalls),
    " mean =", round(mean(result$n_outfalls), 2),
    " max =", max(result$n_outfalls), "\n")

# ---- 6. Write ---------------------------------------------------------------------
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)
stamp <- format(Sys.time(), "%Y-%m-%d_%H%M")
out_facility <- file.path(OUT_DIR, sprintf("outfall_count_per_facility_%s.csv", stamp))
out_dist     <- file.path(OUT_DIR, sprintf("outfall_count_distribution_%s.csv", stamp))
fwrite(result, out_facility)
fwrite(dist, out_dist)
cat("\nWrote:", out_facility, "\n")
cat("Wrote:", out_dist, "\n")
