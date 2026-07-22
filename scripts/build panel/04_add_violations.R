# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# 04_add_violations.R
# ------------------------------------------------------------------------------
# FOURTH STEP in the facility-by-month pipeline. Reads the panel produced by
# 03_add_naics_sic.R and attaches, for every facility-month, counts of three
# kinds of NPDES SCHEDULE/EVENT violations:
#
#   NPDES_PS_VIOLATIONS.csv -> permit-schedule violations
#   NPDES_CS_VIOLATIONS.csv -> compliance-schedule violations
#   NPDES_SE_VIOLATIONS.csv -> single-event violations
#
#   Input  : data/processed/03_facility_month_panel_major_individual_naics_sic_2005_2025.csv
#            (one row per FACILITY_UIN x YEAR x MONTH; built by scripts 01-03)
#   Output : data/processed/04_facility_month_panel_major_individual_violations_2005_2025.csv
#            (the same panel + 3 new violation-count columns)
#
# COLUMNS ADDED (all integers, counted within each facility-month):
#   N_PS_VIOLATIONS - permit-schedule violations
#   N_CS_VIOLATIONS - compliance-schedule violations
#   N_SE_VIOLATIONS - single-event violations
#
# NOTE: EFFLUENT (DMR) VIOLATIONS ARE NO LONGER ADDED HERE. The TSS
# gross-effluent monthly-average columns (N_TSS_EFF_VIOLATIONS, N_TSS_EFF_D90/
# _D80/_E90) moved to 06_add_effluent_violations.R, which now owns ALL effluent-
# violation columns (both those TSS counts and the all-parameter n_D80/n_D90/
# n_E90 counts). The final step-06 panel is unchanged; only the step that adds
# the TSS columns moved. This script no longer streams the ~16 GB effluent file
# and no longer needs python3.
#
# ------------------------------------------------------------------------------
# LABELED ASSUMPTIONS (read before using results):
#
#   1. VIOLATION GRAIN = NPDES_VIOLATION_ID. Each violation is one
#      NPDES_VIOLATION_ID. In the permit-schedule and compliance-schedule files
#      the id is already unique per row; the single-event file has a handful of
#      repeated ids. To be safe we count DISTINCT NPDES_VIOLATION_IDs, never raw
#      rows, in all three files.
#
#   2. DATE = WHEN THE VIOLATION OCCURRED (per PI guidance).
#        - Permit-schedule & compliance-schedule: SCHEDULE_DATE, the date the
#          required milestone was due and missed. It is present on 100% of rows,
#          so no violation is dropped for lacking a date. (We deliberately do
#          NOT use RNC_DETECTION_DATE -- that marks when EPA flagged reportable
#          non-compliance, is blank on ~54-61% of rows, and reflects detection
#          timing rather than when the violation happened.)
#        - Single-event: SINGLE_EVENT_VIOLATION_DATE (its start date; also 100%
#          present). SINGLE_EVENT_END_DATE is ignored -- a single-event
#          violation is placed in the month it began, mirroring how script 02
#          dates an inspection by its begin date.
#
#   3. ROUTED BY NPDES_ID VIA THE SAME CROSSWALK AS SCRIPT 02 (per PI guidance:
#      "all permits at the facility"). Violations are keyed to a permit
#      (NPDES_ID). We map NPDES_ID -> facility exactly the way scripts 01-02 do
#      (FACILITY_UIN when present, else the NPDES_ID itself), counting a
#      violation on ANY permit that resolves to the facility -- not only the
#      individual permits the panel lists. This keeps violation counts built the
#      SAME way as the inspection counts in script 02 (both are event-per-
#      facility-month tallies).
#
#   4. PANEL DEFINES THE OBSERVATION SET. Counts are attached by LEFT-JOINING
#      onto the existing panel spine. Violations that fall in a facility-month
#      not in the panel simply do not appear; facility-months with no violation
#      of a given kind get 0 (not NA).
#
# Deterministic (no stochastic steps); rebuilt entirely from raw + scripts 01-03
# output + this script. Non-destructive: writes a NEW file, leaves script 03's
# panel untouched, and is safe to re-run.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)   # fast CSV reads + grouped counts over the violation files
  library(lubridate)    # date parsing (mdy) and year()/month() extraction
})

## ---- Config (edit here if the panel window or file locations ever change) ----
YEAR_MIN <- 2005L
YEAR_MAX <- 2025L
RAW_DIR  <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
IN_PATH  <- file.path(CWA_ROOT, "data/processed/03_facility_month_panel_major_individual_naics_sic_2005_2025.csv")
OUT_PATH <- file.path(CWA_ROOT, "data/processed/04_facility_month_panel_major_individual_violations_2005_2025.csv")

# Small helper: read only the columns we need, everything as plain text
# (character) so ID columns are never silently reinterpreted as numbers.
rd <- function(file, cols) {
  class_map <- setNames(rep("character", length(cols)), cols)
  fread(file.path(RAW_DIR, file), select = cols,
        colClasses = class_map, showProgress = FALSE)
}

# ------------------------------------------------------------------------------
# STEP 1: Read the facility-by-month panel (output of script 03).
# ------------------------------------------------------------------------------
# One row per FACILITY_UIN x YEAR x MONTH. Read YEAR/MONTH as integers so they
# align with the values we derive from the violation dates below.
panel <- fread(IN_PATH, colClasses = "character", showProgress = FALSE)
panel[, `:=`(YEAR = as.integer(YEAR), MONTH = as.integer(MONTH))]

# ------------------------------------------------------------------------------
# STEP 2: Rebuild the NPDES_ID -> facility_id crosswalk (same rule as scripts 01-02).
# ------------------------------------------------------------------------------
# A facility's id is its FACILITY_UIN when present, else the permit's own
# NPDES_ID. We reproduce that EXACTLY so each violation resolves to the same id
# the panel is keyed on (ASSUMPTION 3).
fac <- rd("ICIS_FACILITIES.csv", c("NPDES_ID", "FACILITY_UIN"))
fac[, NPDES_ID     := trimws(NPDES_ID)]
fac[, FACILITY_UIN := trimws(FACILITY_UIN)]
fac[, facility_id  := fifelse(FACILITY_UIN != "", FACILITY_UIN, NPDES_ID)]
xwalk <- unique(fac[NPDES_ID != "", .(NPDES_ID, facility_id)])

# ------------------------------------------------------------------------------
# STEP 3: Helper -- read one violation file and count it to facility-months.
# ------------------------------------------------------------------------------
# Reads (NPDES_ID, NPDES_VIOLATION_ID, <date_col>), dates each violation, keeps
# the 2005-2025 window, routes NPDES_ID -> facility_id, and returns one row per
# (facility_id, YEAR, MONTH) with a DISTINCT-violation count named `out_col`.
count_violations <- function(file, date_col, out_col) {
  v <- rd(file, c("NPDES_ID", "NPDES_VIOLATION_ID", date_col))
  v[, NPDES_ID := trimws(NPDES_ID)]

  # Place each violation in a calendar month by its violation date (ASSUMPTION 2).
  v[, vdate := mdy(get(date_col), quiet = TRUE)]
  v <- v[!is.na(vdate)]
  v[, `:=`(YEAR = year(vdate), MONTH = month(vdate))]
  v <- v[YEAR >= YEAR_MIN & YEAR <= YEAR_MAX]

  # Route NPDES_ID -> facility_id. Inner join (nomatch = 0): drop violations
  # whose permit has no facility record -- they can never match a panel row.
  v <- xwalk[v, on = "NPDES_ID", nomatch = 0]

  # Count DISTINCT violations per facility-month (ASSUMPTION 1).
  out <- v[, .(n = uniqueN(NPDES_VIOLATION_ID)), by = .(facility_id, YEAR, MONTH)]
  setnames(out, "n", out_col)
  out
}

ps <- count_violations("NPDES_PS_VIOLATIONS.csv", "SCHEDULE_DATE",               "N_PS_VIOLATIONS")
cs <- count_violations("NPDES_CS_VIOLATIONS.csv", "SCHEDULE_DATE",               "N_CS_VIOLATIONS")
se <- count_violations("NPDES_SE_VIOLATIONS.csv", "SINGLE_EVENT_VIOLATION_DATE", "N_SE_VIOLATIONS")

# ------------------------------------------------------------------------------
# STEP 4: Combine the three count tables into one facility-month table.
# ------------------------------------------------------------------------------
# Full outer merge so a facility-month with any one kind of violation is kept;
# kinds not present in that month come through as NA and are set to 0 below.
new_cols <- c("N_PS_VIOLATIONS", "N_CS_VIOLATIONS", "N_SE_VIOLATIONS")
counts <- Reduce(function(a, b) merge(a, b, by = c("facility_id", "YEAR", "MONTH"), all = TRUE),
                 list(ps, cs, se))
for (c in new_cols) counts[is.na(get(c)), (c) := 0L]

# ------------------------------------------------------------------------------
# STEP 5: Attach the counts to the panel and fill non-violation months with 0.
# ------------------------------------------------------------------------------
# Left-join: panel key FACILITY_UIN == violation key facility_id, plus YEAR/MONTH.
panel <- counts[panel, on = c(facility_id = "FACILITY_UIN", "YEAR", "MONTH")]
setnames(panel, "facility_id", "FACILITY_UIN")            # restore the panel's name

# Facility-months with no violation of a given kind came through as NA. A true
# zero only applies while the facility was actually operating
# (FACILITY_OPERATING == 1, from 01_build_facility_month_panel_major_individual.R);
# months outside its active window get an explicit NA -- undefined, not zero. But
# a REAL matched violation always wins over the operating flag: some facilities
# have genuine recorded violations outside their computed open/close window
# (e.g. administrative lag near permit boundaries) -- NA only means "not
# operating AND no data," never "not operating, so discard real data."
for (c in new_cols) {
  panel[is.na(get(c)) & FACILITY_OPERATING == "1", (c) := 0L]
  panel[is.na(get(c)) & FACILITY_OPERATING == "0", (c) := NA]
}

# Put the new columns at the end, after the existing panel columns, and restore
# the panel's row order.
setcolorder(panel, c(setdiff(names(panel), new_cols), new_cols))
setorder(panel, FACILITY_UIN, YEAR, MONTH)

fwrite(panel, OUT_PATH)

# ------------------------------------------------------------------------------
# STEP 6: Run log (sanity checks).
# ------------------------------------------------------------------------------
message("=== 04_add_violations: schedule/event violation counts attached to month panel ===")
# na.rm = TRUE throughout: non-operating months are now legitimately NA
# (FACILITY_OPERATING == 0), so these sums are computed over the operating
# rows only, same as before this change for every operating row.
message("Permit-schedule violations placed on panel     : ", sum(panel$N_PS_VIOLATIONS, na.rm = TRUE))
message("Compliance-schedule violations placed on panel : ", sum(panel$N_CS_VIOLATIONS, na.rm = TRUE))
message("Single-event violations placed on panel        : ", sum(panel$N_SE_VIOLATIONS, na.rm = TRUE))
message("Facility-months with >=1 PS / CS / SE violation : ",
        sum(panel$N_PS_VIOLATIONS > 0, na.rm = TRUE), " / ",
        sum(panel$N_CS_VIOLATIONS > 0, na.rm = TRUE), " / ",
        sum(panel$N_SE_VIOLATIONS > 0, na.rm = TRUE))
message("Facility-months NOT operating (NA counts)      : ", sum(panel$FACILITY_OPERATING == "0"))
message("Panel rows: ", nrow(panel), " | columns: ", ncol(panel))
message("Written to: ", OUT_PATH)
