# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, PROC_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# build_effluent_violations_npdes_month_panel.R
# ------------------------------------------------------------------------------
# PREREQUISITE for the facility-by-month pipeline, not one of its six numbered
# steps. This script reads the raw effluent-violations file straight from EPA
# and condenses it down into one small, fast-to-read summary table: for every
# permit (NPDES_ID) and every calendar month, how many effluent violations of
# each kind (D80, D90, E90) occurred. Two other scripts depend on this file
# existing before they can run:
#   - 01_build_facility_month_panel_major_individual.R uses it for a quick
#     "did this facility have ANY effluent violation this month" existence
#     check (see that script's LABELED ASSUMPTION 12).
#   - 06_add_effluent_violations.R uses it for the actual violation COUNTS
#     that go into the final panel.
# Because of that, `run_all.R` must run this script FIRST, before step 01 --
# not just before step 06.
#
#   Input  : NPDES_EFF_VIOLATIONS.csv, inside a zip in data/raw/ (~15.9 GB
#            uncompressed -- too big to read into memory whole on this
#            machine, so it's streamed and processed out-of-core; see STEP 1-2)
#   Output : data/processed/effluent_violations_npdes_month_panel_2005_2025.csv
#            One row per (NPDES_ID, month). Columns:
#              n_D80 / n_D90 / n_E90                       -- ALL-PARAMETER counts
#              N_TSS_EFF_VIOLATIONS / _D90 / _D80 / _E90   -- TSS-only counts
#            (see COLUMNS ADDED below for what each one means)
#
# WHY TWO DIFFERENT COUNTS OF (SEEMINGLY) THE SAME THING:
#   n_D80/n_D90/n_E90 count violations of that code across EVERY pollutant,
#   discharge point, and monitoring location a permit has -- "how many
#   violations of this kind did this permit rack up, at all, this month."
#   N_TSS_EFF_* count the SAME violation codes but ONLY for one specific,
#   narrow slice: Total Suspended Solids, measured at the "gross effluent"
#   location, using a monthly-average limit (see LABELED ASSUMPTION 3 for the
#   exact filter). So N_TSS_EFF_* is always a subset of the all-parameter
#   counts for the same permit-month. Neither replaces the other; the final
#   panel keeps both.
#
# COLUMNS ADDED (all are integer counts, computed per NPDES_ID x calendar month):
#   n_D80  - ALL-PARAMETER violations, code D80 (DMR value overdue, monitor-only)
#   n_D90  - ALL-PARAMETER violations, code D90 (DMR value overdue, has a limit)
#   n_E90  - ALL-PARAMETER violations, code E90 (a reported value exceeded its
#            numeric permit limit)
#   N_TSS_EFF_VIOLATIONS - TSS/gross-effluent/monthly-average violations, any code
#   N_TSS_EFF_D90/_D80/_E90 - ...of that TSS subset, broken out by code
#
# ------------------------------------------------------------------------------
# LABELED ASSUMPTIONS (read before using results):
#
#   1. ONE ROW PER PERMIT-MONTH; NO ZERO-FILL. A (NPDES_ID, month) combination
#      only appears in the output if that permit had at least one D80/D90/E90
#      violation (of ANY kind) that month. A permit-month with zero violations
#      simply has no row here -- it is not a measured zero. Downstream scripts
#      (01, 06) are the ones that decide what "no row here" should mean once
#      this table is joined onto their own facility-month panels.
#
#   2. MONTH = MONITORING-PERIOD MONTH, NOT WHEN THE VIOLATION WAS DETECTED OR
#      RECORDED. Every row in the raw file has a MONITORING_PERIOD_END_DATE --
#      the calendar month the discharge measurement covers. We floor that date
#      to the first of its month. This is the same convention every other
#      panel-building script in this project uses for dating an event.
#
#   3. THE "TSS SUBSET" IS ONE SPECIFIC, NARROW SLICE (per PI guidance -- same
#      definition previously used inside 06_add_effluent_violations.R, moved
#      here so it's computed in the SAME pass over the raw file instead of a
#      second one). A row counts toward the TSS columns only if ALL of:
#        - PARAMETER_CODE == "00530"              (Total Suspended Solids)
#        - MONITORING_LOCATION_CODE == "1"        (Effluent Gross)
#        - STATISTICAL_BASE_MONTHLY_AVG == "A"    (a monthly-average limit)
#
#   4. TWO DIFFERENT "DE-DUPLICATION" RULES, KEPT DELIBERATELY DIFFERENT.
#      A single real-world violation can appear as MULTIPLE rows in the raw
#      file -- most commonly because a Discharge Monitoring Report (DMR) was
#      RESUBMITTED (corrected and re-filed), which creates an additional row
#      rather than overwriting the original. Naively counting raw rows, or
#      counting distinct NPDES_VIOLATION_ID, can therefore over-count.
#        - ALL-PARAMETER counts (n_D80/n_D90/n_E90) are counted as DISTINCT
#          "vkey" -- see LABELED ASSUMPTION 5 below for exactly what that is.
#        - TSS counts (N_TSS_EFF_*) are counted as DISTINCT NPDES_VIOLATION_ID
#          instead -- this matches the TSS logic exactly as it worked before
#          it was moved into this script, and is NOT being "fixed" to match
#          the all-parameter rule; that would silently change a downstream
#          number. As a result, in a vanishingly small number of permit-months
#          the TSS count and the all-parameter count can disagree by 1-2 --
#          06_add_effluent_violations.R's run log reports this, it does not
#          hide it.
#
#   5. WHAT "vkey" MEANS AND WHY IT'S NEEDED (see also cs cleaning). A DMR
#      resubmission gets its own, brand-new NPDES_VIOLATION_ID -- so distinct
#      NPDES_VIOLATION_ID does NOT collapse resubmissions for the all-parameter
#      counts the way we need it to. Instead, "vkey" identifies WHAT the
#      violation is actually about, independent of which submission produced
#      the row: the permit, the discharge point, the limit set, the monitoring
#      location, the pollutant, the statistical basis for the limit (e.g.
#      daily max vs. monthly average), and the reporting month. Two rows that
#      agree on all seven of those are the same underlying violation, just
#      reported more than once; two rows that differ in any of the seven are
#      genuinely different violations and both should count. Concretely:
#        vkey = NPDES_ID + PERM_FEATURE_NMBR + LIMIT_SET_DESIGNATOR +
#                MONITORING_LOCATION_CODE + PARAMETER_CODE +
#                STATISTICAL_BASE_CODE + MONITORING_PERIOD_END_DATE
#      Counting DISTINCT vkey is equivalent to keeping only the latest-version
#      row per vkey group and counting what's left, but doesn't require R/
#      DuckDB to actually pick out which row is "latest" -- for a pure count,
#      the two approaches give the identical number.
#
#   6. ONLY THE THREE SCHEDULE-TYPE CODES ARE KEPT. The raw file's
#      VIOLATION_CODE column has other values beyond D80/D90/E90 (for other
#      kinds of DMR issues); this script filters to exactly those three,
#      matching every downstream use of this file.
#
#   7. WINDOWED TO THE PANEL'S RANGE. Only violations whose monitoring-period
#      month falls in Jan 2005 - Dec 2025 are kept; anything outside that
#      range, or with an unparseable MONITORING_PERIOD_END_DATE, is dropped
#      (the drop count is reported in the run log, not silently discarded).
#
# ENGINE: this file is far too large to read into R's memory whole on this
# machine (RAW_DIR is on a machine with limited RAM). We use DuckDB instead,
# which processes the file OUT-OF-CORE (reading and aggregating in chunks,
# spilling to disk as needed rather than holding everything in memory at
# once). The non-ASCII space in the zip's real filename means `unzip` has to
# be pointed at it through a plain-ASCII symlink first (same workaround
# 06_add_effluent_violations.R already used); the CSV member is then streamed
# out of the zip and re-compressed to a much smaller gzip file ONCE (a scratch
# file, not tracked or committed), which DuckDB can then read and re-read
# quickly for the rest of this script.
#
# Deterministic (no stochastic steps); rebuilt entirely from the raw effluent
# file. Non-destructive: writes one new file; does not modify data/raw/.
# Runtime: on the order of 15-20 minutes (one full pass to build the gzip
# scratch file, plus DuckDB's scan/aggregation passes).
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(DBI)
  library(duckdb)
})

## ---- Config (edit here if the panel window or file locations ever change) ----
YEAR_MIN <- 2005L
YEAR_MAX <- 2025L
OUT_PATH <- file.path(CWA_ROOT, "data/processed/effluent_violations_npdes_month_panel_2005_2025.csv")

# The TSS/gross-effluent/monthly-average filter (LABELED ASSUMPTION 3).
TSS_PARAM_CODE <- "00530"       # Solids, total suspended (standard EPA TSS code)
GROSS_LOC_CODE <- "1"           # MONITORING_LOCATION_CODE for Effluent Gross
MONTHLY_AVG    <- "A"           # STATISTICAL_BASE_MONTHLY_AVG flag = monthly average

# Locate the raw effluent zip. Its real filename has a non-ASCII space EPA's
# download tool inserted, which `unzip`/shell commands can't reliably handle --
# so we find it by pattern instead of hardcoding the exact name.
EFF_ZIP <- list.files(file.path(CWA_ROOT, "data/raw"), pattern = "eff.*zip",
                      full.names = TRUE)[1]
if (is.na(EFF_ZIP)) stop("Could not find the raw effluent-violations zip under data/raw/.")
EFF_CSV <- "NPDES_EFF_VIOLATIONS.csv"

# Scratch space for the one-time zip-member -> gzip conversion, and for
# DuckDB's own disk-spill files. Same CWA_SCRATCH convention already used by
# code/diagnostics/outfalls/outfall_count_breakdown_dmr.R, so the two scripts
# can share a scratch root if the environment variable is set.
SCRATCH   <- Sys.getenv("CWA_SCRATCH", file.path(tempdir(), "cwa_eff"))
GZ_TMP    <- file.path(SCRATCH, "NPDES_EFF_VIOLATIONS.csv.gz")
DUCK_TMP  <- file.path(SCRATCH, "duckdb_spill")
REUSE_GZ  <- TRUE     # skip re-extracting if a previous run already left GZ_TMP
MEM_LIMIT <- "5GB"     # keep DuckDB's own memory use well under this machine's RAM

dir.create(SCRATCH,  showWarnings = FALSE, recursive = TRUE)
dir.create(DUCK_TMP, showWarnings = FALSE, recursive = TRUE)

# ------------------------------------------------------------------------------
# STEP 1: Stream the CSV member out of the zip and re-compress it to gzip, once.
# ------------------------------------------------------------------------------
# DuckDB can read a gzip-compressed CSV directly and efficiently, but it can't
# reach into a zip archive itself, and this particular zip's member can't be
# piped straight into most tools because of the non-ASCII filename -- so we
# point an ASCII-named temporary symlink at the real zip first.
if (REUSE_GZ && file.exists(GZ_TMP) && file.info(GZ_TMP)$size > 0) {
  message("Reusing existing gzip temp: ", GZ_TMP,
          " (", round(file.info(GZ_TMP)$size / 1e9, 2), " GB)")
} else {
  link <- file.path(tempdir(), "npdes_eff_downloads.zip")
  unlink(link, force = TRUE)
  file.symlink(EFF_ZIP, link)
  on.exit(unlink(link, force = TRUE), add = TRUE)

  message("Streaming ", EFF_CSV, " out of the zip and re-gzipping to: ", GZ_TMP)
  message("  (one pass over ~16 GB; this takes several minutes)")
  cmd <- sprintf("unzip -p %s %s | gzip -1 > %s",
                 shQuote(link), shQuote(EFF_CSV), shQuote(GZ_TMP))
  t0 <- Sys.time()
  status <- system(cmd)
  if (status != 0) stop("Extraction pipeline failed (exit ", status, ").")
  message("  extract+gzip done in ",
          round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min")
}

# ------------------------------------------------------------------------------
# STEP 2: DuckDB -- filter to D80/D90/E90, tag TSS rows, compute vkey, once.
# ------------------------------------------------------------------------------
# CREATE TEMP TABLE materializes this filtered-and-tagged subset ONE time; both
# queries below (the per-permit-month pivot, and the summary totals used for
# the run log) then read from this small(er) table instead of re-scanning the
# full ~16 GB file twice.
con <- dbConnect(duckdb::duckdb())
dbExecute(con, sprintf("SET memory_limit='%s';", MEM_LIMIT))
dbExecute(con, sprintf("SET temp_directory='%s';", DUCK_TMP))
dbExecute(con, "SET preserve_insertion_order=false;")

message("Scanning the effluent file for D80/D90/E90 rows in the panel window ...")
t0 <- Sys.time()
dbExecute(con, sprintf("
  CREATE TEMP TABLE tagged AS
  WITH raw_tagged AS (
    SELECT
      NPDES_ID,
      VIOLATION_CODE,
      NPDES_VIOLATION_ID,
      strptime(MONITORING_PERIOD_END_DATE, '%%m/%%d/%%Y') AS period_date,
      (PARAMETER_CODE = '%s' AND MONITORING_LOCATION_CODE = '%s'
       AND STATISTICAL_BASE_MONTHLY_AVG = '%s') AS is_tss,
      concat_ws('|', NPDES_ID, PERM_FEATURE_NMBR, LIMIT_SET_DESIGNATOR,
                     MONITORING_LOCATION_CODE, PARAMETER_CODE,
                     STATISTICAL_BASE_CODE, MONITORING_PERIOD_END_DATE) AS vkey
    FROM read_csv('%s', all_varchar=true, header=true, sample_size=-1)
    WHERE VIOLATION_CODE IN ('D80', 'D90', 'E90')
  )
  SELECT *, date_trunc('month', period_date) AS month
  FROM raw_tagged
  WHERE period_date IS NOT NULL
    AND year(period_date) BETWEEN %d AND %d
", TSS_PARAM_CODE, GROSS_LOC_CODE, MONTHLY_AVG, GZ_TMP, YEAR_MIN, YEAR_MAX))
message("  scan+filter done in ",
        round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min")

n_dropped <- dbGetQuery(con, sprintf("
  SELECT COUNT(*) AS n FROM read_csv('%s', all_varchar=true, header=true, sample_size=-1)
  WHERE VIOLATION_CODE IN ('D80','D90','E90')
    AND (strptime(MONITORING_PERIOD_END_DATE, '%%m/%%d/%%Y') IS NULL
         OR year(strptime(MONITORING_PERIOD_END_DATE, '%%m/%%d/%%Y')) NOT BETWEEN %d AND %d)
", GZ_TMP, YEAR_MIN, YEAR_MAX))$n

# ------------------------------------------------------------------------------
# STEP 3: Aggregate to one row per (NPDES_ID, month) -- the actual output table.
# ------------------------------------------------------------------------------
# NOTE ON QUERY SHAPE: an earlier version of this script tried to compute all 7
# count columns in a SINGLE query, using a `COUNT(DISTINCT CASE WHEN ... END)`
# expression per column. That ran DuckDB out of its 5 GB memory budget --
# tracking 7 separate "what have I seen so far" distinct-value sets at once,
# across ~41 million rows, is far more memory-hungry than tracking just one.
# The fix: ask for only ONE distinct-count at a time, with VIOLATION_CODE as an
# extra GROUP BY column instead of a CASE WHEN branch (long/"tidy" format, one
# row per NPDES_ID x month x code), then reshape to wide format afterward in R
# -- reshaping a few million already-aggregated rows is cheap; the expensive
# part was always the distinct-counting over the raw rows, and that now only
# happens once per query instead of 7 times at once.
message("Aggregating all-parameter counts (one distinct-count pass) ...")
t0 <- Sys.time()
all_param_long <- as.data.table(dbGetQuery(con, "
  SELECT NPDES_ID, month, VIOLATION_CODE, COUNT(DISTINCT vkey) AS n
  FROM tagged
  GROUP BY NPDES_ID, month, VIOLATION_CODE
"))
message("  done in ", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min")

message("Aggregating TSS-subset counts (one distinct-count pass) ...")
t0 <- Sys.time()
tss_long <- as.data.table(dbGetQuery(con, "
  SELECT NPDES_ID, month, VIOLATION_CODE, COUNT(DISTINCT NPDES_VIOLATION_ID) AS n
  FROM tagged
  WHERE is_tss
  GROUP BY NPDES_ID, month, VIOLATION_CODE
"))
message("  done in ", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min")

# N_TSS_EFF_VIOLATIONS is DISTINCT NPDES_VIOLATION_ID across ALL codes together
# (matching the original 06_add_effluent_violations.R semantics exactly), which
# is NOT necessarily the same as summing the three per-code counts above unless
# every violation ID carries exactly one code -- rather than assume that, ask
# DuckDB for the code-agnostic distinct count directly.
message("Aggregating TSS-subset totals (code-agnostic distinct count) ...")
t0 <- Sys.time()
tss_total_long <- as.data.table(dbGetQuery(con, "
  SELECT NPDES_ID, month, COUNT(DISTINCT NPDES_VIOLATION_ID) AS n
  FROM tagged
  WHERE is_tss
  GROUP BY NPDES_ID, month
"))
message("  done in ", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min")

# n_raw_rows_in_window needs no distinct-tracking at all (just a row count), so
# it's cheap even over the full ~41M-row table.
n_raw_rows_in_window <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM tagged")$n

dbDisconnect(con, shutdown = TRUE)

# ---- Reshape long -> wide in R (cheap: a few million already-aggregated rows) ----
# All-parameter: every (NPDES_ID, month) that could ever need a row already
# appears here (TSS rows are a strict subset of these, filtered further by
# is_tss -- see this script's header), so this is the spine everything else
# joins onto.
all_param_wide <- dcast(all_param_long, NPDES_ID + month ~ paste0("n_", VIOLATION_CODE),
                        value.var = "n", fill = 0L)
tss_wide <- dcast(tss_long, NPDES_ID + month ~ paste0("N_TSS_EFF_", VIOLATION_CODE),
                  value.var = "n", fill = 0L)

# Any of the 3 codes' TSS column that never occurred anywhere won't exist as a
# column at all after dcast (there was nothing to pivot) -- add it as all-0 so
# the output always has the same 8 columns regardless of what's in the data.
for (col in c("n_D80", "n_D90", "n_E90")) if (!col %in% names(all_param_wide)) all_param_wide[[col]] <- 0L
for (col in c("N_TSS_EFF_D80", "N_TSS_EFF_D90", "N_TSS_EFF_E90")) if (!col %in% names(tss_wide)) tss_wide[[col]] <- 0L

setnames(tss_total_long, "n", "N_TSS_EFF_VIOLATIONS")
panel <- merge(all_param_wide, tss_wide, by = c("NPDES_ID", "month"), all.x = TRUE)
panel <- merge(panel, tss_total_long, by = c("NPDES_ID", "month"), all.x = TRUE)
for (col in c("N_TSS_EFF_D80", "N_TSS_EFF_D90", "N_TSS_EFF_E90", "N_TSS_EFF_VIOLATIONS"))
  panel[is.na(get(col)), (col) := 0L]
setcolorder(panel, c("NPDES_ID", "month", "n_D80", "n_D90", "n_E90",
                     "N_TSS_EFF_VIOLATIONS", "N_TSS_EFF_D90", "N_TSS_EFF_D80", "N_TSS_EFF_E90"))

# ---- Summary totals for the run log, derived from the results above (no need ----
# ---- for another pass over the raw data): a vkey embeds NPDES_ID and the -------
# ---- monitoring-period date, so it belongs to exactly one (NPDES_ID, month) ----
# ---- group -- summing the per-group distinct counts equals the true overall ---
# ---- distinct count for that code. --------------------------------------------
n_distinct_vkey_in_window <- sum(all_param_long$n)
code_totals <- all_param_long[, .(total = sum(n)), by = VIOLATION_CODE]
# A code with zero matching rows in-window simply has no row in code_totals at
# all (rather than a row with total = 0) -- fall back to 0L so the run log
# always prints a number, not a blank, even in that edge case.
code_total_or_zero <- function(code) {
  v <- code_totals[VIOLATION_CODE == code, total]
  if (length(v) == 0) 0L else v
}
n_D80_total <- code_total_or_zero("D80")
n_D90_total <- code_total_or_zero("D90")
n_E90_total <- code_total_or_zero("E90")

# ZIP-like ID columns must stay text throughout (NPDES_ID can contain letters).
panel[, NPDES_ID := as.character(NPDES_ID)]
panel[, month := as.character(as.Date(month))]
setorder(panel, NPDES_ID, month)

fwrite(panel, OUT_PATH)

# ------------------------------------------------------------------------------
# STEP 5: Run log -- always print what was built, and cross-check against the
# exact figures already on record in docs/notes.md from this file's original
# construction, so a silent regression would be caught immediately.
# ------------------------------------------------------------------------------
message("=== build_effluent_violations_npdes_month_panel: condensed effluent panel ===")
message("Raw D80/D90/E90 rows dropped for missing/out-of-window date : ", n_dropped)
message("Raw D80/D90/E90 rows in window                              : ", n_raw_rows_in_window)
message("Distinct vkey (de-duplicated) in window                     : ", n_distinct_vkey_in_window)
message("  of which D80 / D90 / E90                                  : ",
        n_D80_total, " / ", n_D90_total, " / ", n_E90_total)
message("  (docs/notes.md, 2026-07-14 build, for comparison           : 43,317,821 raw / ",
        "41,451,812 distinct / D80 21,073,782 / D90 17,814,134 / E90 2,563,896)")
message("Permit-month rows written                                   : ", nrow(panel))
message("Distinct NPDES_IDs                                          : ", uniqueN(panel$NPDES_ID))
message("  (docs/notes.md, for comparison: 2,694,316 ID-months across 121,708 distinct NPDES_IDs)")
message("TSS-subset totals (violations / D90 / D80 / E90)            : ",
        sum(panel$N_TSS_EFF_VIOLATIONS), " / ", sum(panel$N_TSS_EFF_D90), " / ",
        sum(panel$N_TSS_EFF_D80), " / ", sum(panel$N_TSS_EFF_E90))
message("Written to: ", OUT_PATH)
