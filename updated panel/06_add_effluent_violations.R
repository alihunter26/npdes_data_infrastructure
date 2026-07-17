# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, PROC_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# 06_add_effluent_violations.R
# ------------------------------------------------------------------------------
# SIXTH STEP in the facility-by-month pipeline. Reads the panel produced by
# 05_add_enforcement.R and attaches, for every facility-month, counts of effluent
# (DMR) violations by violation code, taken from the PRE-BUILT condensed month
# panel rather than by re-streaming the ~16 GB raw effluent file.
#
#   Source (already built by scripts/build/build_effluent_violations_npdes_month_panel.R):
#     data/processed/effluent_violations_npdes_month_panel_2005_2025.csv
#     -- one row per NPDES_ID x month (observed months only), columns:
#        NPDES_ID, month (YYYY-MM-01), n_D80, n_D90, n_E90
#
#   Input  : data/processed/05_facility_month_panel_major_individual_enforcement_2005_2025.csv
#            (one row per FACILITY_UIN x YEAR x MONTH; built by scripts 01-05)
#   Output : data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv
#            (the same panel + 3 new effluent-violation count columns)
#
# COLUMNS ADDED (all integers, counted within each facility-month):
#   n_D80  - effluent violations, VIOLATION_CODE D80 (DMR value overdue)
#   n_D90  - effluent violations, VIOLATION_CODE D90 (DMR value overdue, limited)
#   n_E90  - effluent violations, VIOLATION_CODE E90 (numeric effluent-limit exceedance)
#
# ------------------------------------------------------------------------------
# LABELED ASSUMPTIONS (read before using results):
#
#   1. THESE ARE ALL-PARAMETER CODE COUNTS, DISTINCT FROM 04's TSS COLUMNS. The
#      condensed source counts D80/D90/E90 across EVERY parameter, feature, and
#      monitoring location (see build_effluent_violations_npdes_month_panel.R).
#      Script 04's N_TSS_EFF_D80/_D90/_E90 count the SAME codes but only for the
#      Total-Suspended-Solids gross-effluent monthly-average subset. So these new
#      columns are a SUPERSET: n_D80 >= N_TSS_EFF_D80, etc. They are kept as
#      separate columns on purpose; neither replaces the other.
#
#   2. COUNTS ALREADY DE-DUPLICATED AT SOURCE. The condensed panel counts DISTINCT
#      underlying violations (latest DMR resubmission version only) per
#      NPDES_ID x month x code. We do not re-dedupe; we only re-key and sum.
#
#   3. DATE = DMR MONITORING-PERIOD MONTH. The source `month` is the calendar month
#      of MONITORING_PERIOD_END_DATE (the reporting period the violation pertains
#      to) -- the same date basis script 04 used for effluent violations. We split
#      it into YEAR/MONTH integers to match the panel keys.
#
#   4. ROUTED BY NPDES_ID VIA THE SAME CROSSWALK AS SCRIPTS 02, 04 & 05. Each source
#      row is keyed to a permit (NPDES_ID); we map NPDES_ID -> facility exactly the
#      way scripts 01-05 do (FACILITY_UIN when present, else the NPDES_ID itself)
#      and SUM the code counts across all permits that resolve to the facility, so
#      a facility-month total reflects every permit at the facility.
#
#   5. PANEL DEFINES THE OBSERVATION SET; MISSING = TRUE ZERO. Counts are attached
#      by LEFT-JOINING onto the existing panel spine. The condensed source lists
#      only months in which a violation occurred, so any panel facility-month NOT
#      present in it had no D80/D90/E90 that month -> filled with 0 (per request).
#      Source rows for permits/months outside the panel (minors, general permits,
#      pre-entry months) simply do not match a panel row and drop out.
#
# Deterministic (no stochastic steps); rebuilt entirely from the condensed source
# + scripts 01-05 output + this script. Non-destructive: writes a NEW file, leaves
# script 05's panel untouched, and is safe to re-run.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)   # fast CSV reads + grouped sums over the 2.7M-row source
  library(lubridate)    # year()/month() extraction from the parsed month date
})

## ---- Config (edit here if the panel window or file locations ever change) ----
YEAR_MIN <- 2005L
YEAR_MAX <- 2025L
RAW_DIR  <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
EFF_PATH <- file.path(CWA_ROOT, "data/processed/effluent_violations_npdes_month_panel_2005_2025.csv")
IN_PATH  <- file.path(CWA_ROOT, "data/processed/05_facility_month_panel_major_individual_enforcement_2005_2025.csv")
OUT_PATH <- file.path(CWA_ROOT, "data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv")

new_cols <- c("n_D80", "n_D90", "n_E90")

# Small helper: read only the columns we need, everything as plain text
# (character) so ID columns are never silently reinterpreted as numbers.
rd <- function(file, cols) {
  class_map <- setNames(rep("character", length(cols)), cols)
  fread(file.path(RAW_DIR, file), select = cols,
        colClasses = class_map, showProgress = FALSE)
}

# ------------------------------------------------------------------------------
# STEP 1: Read the facility-by-month panel (output of script 05).
# ------------------------------------------------------------------------------
# One row per FACILITY_UIN x YEAR x MONTH. Read YEAR/MONTH as integers so they
# align with the values we derive from the source `month` below.
panel <- fread(IN_PATH, colClasses = "character", showProgress = FALSE)
panel[, `:=`(YEAR = as.integer(YEAR), MONTH = as.integer(MONTH))]

# ------------------------------------------------------------------------------
# STEP 2: Rebuild the NPDES_ID -> facility_id crosswalk (same rule as scripts 01-05).
# ------------------------------------------------------------------------------
# A facility's id is its FACILITY_UIN when present, else the permit's own
# NPDES_ID. We reproduce that EXACTLY so each source row resolves to the same id
# the panel is keyed on (ASSUMPTION 4).
fac <- rd("ICIS_FACILITIES.csv", c("NPDES_ID", "FACILITY_UIN"))
fac[, NPDES_ID     := trimws(NPDES_ID)]
fac[, FACILITY_UIN := trimws(FACILITY_UIN)]
fac[, facility_id  := fifelse(FACILITY_UIN != "", FACILITY_UIN, NPDES_ID)]
xwalk <- unique(fac[NPDES_ID != "", .(NPDES_ID, facility_id)])

# ------------------------------------------------------------------------------
# STEP 3: Read the condensed effluent month panel, date it, route to facility.
# ------------------------------------------------------------------------------
# Codes read as integer counts; NPDES_ID/month as text. `month` is YYYY-MM-01.
eff <- fread(EFF_PATH, showProgress = FALSE,
             colClasses = list(character = c("NPDES_ID", "month"),
                               integer   = new_cols))
eff[, NPDES_ID := trimws(NPDES_ID)]

# Split the monitoring-period month into YEAR/MONTH; keep the panel window.
eff[, mdate := as.Date(month)]
eff <- eff[!is.na(mdate)]
eff[, `:=`(YEAR = year(mdate), MONTH = month(mdate))]
eff <- eff[YEAR >= YEAR_MIN & YEAR <= YEAR_MAX]

n_rows_read <- nrow(eff)

# Route NPDES_ID -> facility_id. Inner join (nomatch = 0): drop source rows whose
# permit has no facility record -- they can never match a panel row anyway.
eff <- xwalk[eff, on = "NPDES_ID", nomatch = 0]

# ------------------------------------------------------------------------------
# STEP 4: Collapse to one row per facility-month, SUMMING each code across permits.
# ------------------------------------------------------------------------------
# A facility can hold several NPDES permits; sum their code counts so the
# facility-month total reflects every permit at the facility (ASSUMPTION 4).
eff_month <- eff[, lapply(.SD, sum), by = .(facility_id, YEAR, MONTH), .SDcols = new_cols]

# ------------------------------------------------------------------------------
# STEP 5: Attach the counts to the panel and fill non-violation months with 0.
# ------------------------------------------------------------------------------
# Left-join: panel key FACILITY_UIN == source key facility_id, plus YEAR/MONTH.
panel <- eff_month[panel, on = c(facility_id = "FACILITY_UIN", "YEAR", "MONTH")]
setnames(panel, "facility_id", "FACILITY_UIN")            # restore the panel's name

# Facility-months absent from the condensed source came through as NA -> 0L
# (ASSUMPTION 5: missing means no D80/D90/E90 that month).
for (c in new_cols) panel[is.na(get(c)), (c) := 0L]

# Put the new columns at the end, after the existing panel columns, and restore
# the panel's row order.
setcolorder(panel, c(setdiff(names(panel), new_cols), new_cols))
setorder(panel, FACILITY_UIN, YEAR, MONTH)

fwrite(panel, OUT_PATH)

# ------------------------------------------------------------------------------
# STEP 6: Run log (sanity checks).
# ------------------------------------------------------------------------------
message("=== 06_add_effluent_violations: effluent codes attached to month panel ===")
message("Condensed source ID-months in window (2005-2025) : ", n_rows_read)
message("Effluent violations placed on panel (D80/D90/E90): ",
        sum(panel$n_D80), " / ", sum(panel$n_D90), " / ", sum(panel$n_E90))
message("Facility-months with >=1 D80 / D90 / E90         : ",
        sum(panel$n_D80 > 0), " / ", sum(panel$n_D90 > 0), " / ", sum(panel$n_E90 > 0))
# Cross-check vs script 04's TSS subset. These new columns count the same codes
# over ALL parameters, so they are overwhelmingly a superset of 04's TSS-only
# columns (compare the totals above). They are NOT guaranteed to be >= cell-by-
# cell, though: script 04 counts DISTINCT NPDES_VIOLATION_ID while the condensed
# source counts DISTINCT vkey (its more aggressive "latest-version" de-dup), so in
# a vanishingly small number of facility-months the condensed count can be 1-2
# lower. We report the exceptions rather than assert a strict inequality.
if (all(c("N_TSS_EFF_D80", "N_TSS_EFF_D90", "N_TSS_EFF_E90") %in% names(panel))) {
  # The carried-forward panel columns are still character here (only n_* are
  # numeric), so coerce the TSS columns before differencing.
  short <- pmax(0, as.integer(panel$N_TSS_EFF_D80) - panel$n_D80) +
           pmax(0, as.integer(panel$N_TSS_EFF_D90) - panel$n_D90) +
           pmax(0, as.integer(panel$N_TSS_EFF_E90) - panel$n_E90)
  message("Cells where all-param < 04 TSS subset (dedup-key diff): ",
          sum(short > 0), " of ", nrow(panel),
          "  (max shortfall ", if (any(short > 0)) max(short) else 0L, ")")
}
message("Panel rows: ", nrow(panel), " | columns: ", ncol(panel))
message("Written to: ", OUT_PATH)
