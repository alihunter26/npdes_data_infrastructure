# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# 02_add_inspections.R
# ------------------------------------------------------------------------------
# SECOND STEP in the facility-by-month pipeline. Reads the base panel produced by
# 01_build_facility_month_panel_major_individual.R and attaches, for every
# facility-month, counts of NPDES compliance inspections.
#
#   Input  : data/processed/01_facility_month_panel_major_individual_2005_2025.csv
#            (one row per FACILITY_UIN x YEAR x MONTH; built by script 01)
#   Output : data/processed/02_facility_month_panel_major_individual_inspections_2005_2025.csv
#            (the same panel + 7 new inspection-count columns)
#
# COLUMNS ADDED (all integers, counted within each facility-month):
#   N_INSPECTIONS_TOTAL  - total inspections (any type)
#   N_CEI                - Compliance Evaluation Inspections   (CEI)
#   N_ROS                - Reconnaissance without Sampling      (ROS)
#   N_SA1                - Sampling inspections                 (SA1)
#   N_AU1                - Audits                               (AU1)
#   N_STATE_INSPECTIONS  - inspections led by a STATE agency    (STATE_EPA_FLAG = "S")
#   N_EPA_INSPECTIONS    - inspections led by EPA               (STATE_EPA_FLAG = "E")
#
# ------------------------------------------------------------------------------
# LABELED ASSUMPTIONS (read before using results):
#
#   1. INSPECTION GRAIN = ACTIVITY_ID. In NPDES_INSPECTIONS.csv a single physical
#      inspection (one ACTIVITY_ID) can appear as SEVERAL rows -- one per
#      "monitoring component" it involved (e.g. an Evaluation row AND a Sampling
#      row for the same visit on the same day). So we count DISTINCT ACTIVITY_IDs,
#      never raw rows; counting rows would over-count multi-component inspections
#      by ~6%.
#
#   2. TYPE COUNTS CAN OVERLAP. Because one inspection may carry more than one
#      monitoring type, a visit that was both an Evaluation and a Sampling is
#      counted in BOTH N_CEI and N_SA1. Therefore
#          N_CEI + N_ROS + N_SA1 + N_AU1  MAY EXCEED  N_INSPECTIONS_TOTAL,
#      and the four type columns are NOT a partition of the total. (There are
#      also other, rarer inspection types not broken out here, so they need not
#      sum to the total from below either.)
#
#   3. CONDUCTOR IS ONE PER INSPECTION. Each inspection is led by either a state
#      agency ("S") or EPA ("E"), so the two conductor counts DO partition the
#      total:  N_STATE_INSPECTIONS + N_EPA_INSPECTIONS == N_INSPECTIONS_TOTAL.
#
#   4. ROUTED BY NPDES_ID (NOT REGISTRY_ID). Inspections are keyed to a permit
#      (NPDES_ID). We map NPDES_ID -> facility exactly the way script 01 does
#      (FACILITY_UIN when present, otherwise the NPDES_ID itself as the id), so
#      an inspection lands on the same key the panel calls FACILITY_UIN. We do
#      NOT join on REGISTRY_ID: it is the FRS site id, disagrees with FACILITY_UIN
#      for a handful of permits, and cannot reproduce the id fallback above.
#
#   5. PANEL DEFINES THE OBSERVATION SET. Counts are attached by LEFT-JOINING onto
#      the existing panel spine. Inspections that fall in a facility-month NOT in
#      the panel (e.g. a month before the facility entered, or a non-major month)
#      simply do not appear; facility-months with no inspection get 0 (not NA).
#
#   6. INSPECTION DATE = BEGIN DATE. A visit is placed in the month of its
#      ACTUAL_BEGIN_DATE, falling back to ACTUAL_END_DATE if begin is missing
#      (same date logic script 01 uses for permits).
#
# Deterministic (no stochastic steps); rebuilt entirely from raw + script 01's
# output + this script. Non-destructive: writes a NEW file, leaves the base panel
# from script 01 untouched, and is safe to re-run.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)   # fast CSV reads + grouped counts over ~1.9M inspection rows
  library(lubridate)    # date parsing (mdy) and year()/month() extraction
})

## ---- Config (edit here if the panel window or file locations ever change) ----
YEAR_MIN <- 2005L
YEAR_MAX <- 2025L
RAW_DIR  <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
IN_PATH  <- file.path(CWA_ROOT, "data/processed/01_facility_month_panel_major_individual_2005_2025.csv")
OUT_PATH <- file.path(CWA_ROOT, "data/processed/02_facility_month_panel_major_individual_inspections_2005_2025.csv")

# The four monitoring-type codes we break out, and the COMP_MONITOR_TYPE_CODE
# value each corresponds to in NPDES_INSPECTIONS.csv.
#   CEI = Evaluation | ROS = Reconnaissance w/o Sampling | SA1 = Sampling | AU1 = Audit
TYPE_CODES <- c(N_CEI = "CEI", N_ROS = "ROS", N_SA1 = "SA1", N_AU1 = "AU1")

# Small helper: read only the columns we need, everything as plain text
# (character) so ID columns are never silently reinterpreted as numbers.
rd <- function(file, cols) {
  class_map <- setNames(rep("character", length(cols)), cols)
  fread(file.path(RAW_DIR, file), select = cols,
        colClasses = class_map, showProgress = FALSE)
}

# ------------------------------------------------------------------------------
# STEP 1: Read the base facility-by-month panel (output of script 01).
# ------------------------------------------------------------------------------
# One row per FACILITY_UIN x YEAR x MONTH. FACILITY_UIN here is already the
# "facility id" (FRS FACILITY_UIN, or the NPDES_ID itself where no UIN existed).
# We read YEAR/MONTH as integers so they align with the values we derive from the
# inspection dates below.
panel <- fread(IN_PATH, colClasses = "character", showProgress = FALSE)
panel[, `:=`(YEAR = as.integer(YEAR), MONTH = as.integer(MONTH))]

# ------------------------------------------------------------------------------
# STEP 2: Rebuild the NPDES_ID -> facility_id crosswalk (same rule as script 01).
# ------------------------------------------------------------------------------
# ICIS_FACILITIES has one row per NPDES_ID and carries the FRS FACILITY_UIN.
# Script 01 defines a facility's id as its FACILITY_UIN when present, and falls
# back to the permit's own NPDES_ID when the UIN is blank. We reproduce that
# EXACTLY so each inspection resolves to the same id the panel is keyed on.
fac <- rd("ICIS_FACILITIES.csv", c("NPDES_ID", "FACILITY_UIN"))
fac[, NPDES_ID     := trimws(NPDES_ID)]
fac[, FACILITY_UIN := trimws(FACILITY_UIN)]
fac[, facility_id  := fifelse(FACILITY_UIN != "", FACILITY_UIN, NPDES_ID)]
xwalk <- unique(fac[NPDES_ID != "", .(NPDES_ID, facility_id)])

# ------------------------------------------------------------------------------
# STEP 3: Read inspections, date them, and route each to its facility_id.
# ------------------------------------------------------------------------------
insp <- rd("NPDES_INSPECTIONS.csv",
           c("NPDES_ID", "ACTIVITY_ID", "COMP_MONITOR_TYPE_CODE",
             "STATE_EPA_FLAG", "ACTUAL_BEGIN_DATE", "ACTUAL_END_DATE"))
insp[, NPDES_ID := trimws(NPDES_ID)]

# Place each inspection in a calendar month by its begin date (fallback: end).
insp[, insp_date := fcoalesce(mdy(ACTUAL_BEGIN_DATE, quiet = TRUE),
                              mdy(ACTUAL_END_DATE,   quiet = TRUE))]
insp <- insp[!is.na(insp_date)]
insp[, `:=`(YEAR = year(insp_date), MONTH = month(insp_date))]
insp <- insp[YEAR >= YEAR_MIN & YEAR <= YEAR_MAX]

n_rows_read <- nrow(insp)

# Route NPDES_ID -> facility_id. Inner join (nomatch = 0): drop inspections whose
# permit has no facility record -- they can never match a panel row anyway.
insp <- xwalk[insp, on = "NPDES_ID", nomatch = 0]

# ------------------------------------------------------------------------------
# STEP 4: Collapse to one row per facility-month with the seven counts.
# ------------------------------------------------------------------------------
# All counts are DISTINCT ACTIVITY_IDs (see ASSUMPTION 1): uniqueN() over the
# relevant subset. The type counts (ASSUMPTION 2) may overlap; the two conductor
# counts (ASSUMPTION 3) partition the total.
insp_month <- insp[, .(
    N_INSPECTIONS_TOTAL = uniqueN(ACTIVITY_ID),
    N_CEI               = uniqueN(ACTIVITY_ID[COMP_MONITOR_TYPE_CODE == TYPE_CODES["N_CEI"]]),
    N_ROS               = uniqueN(ACTIVITY_ID[COMP_MONITOR_TYPE_CODE == TYPE_CODES["N_ROS"]]),
    N_SA1               = uniqueN(ACTIVITY_ID[COMP_MONITOR_TYPE_CODE == TYPE_CODES["N_SA1"]]),
    N_AU1               = uniqueN(ACTIVITY_ID[COMP_MONITOR_TYPE_CODE == TYPE_CODES["N_AU1"]]),
    N_STATE_INSPECTIONS = uniqueN(ACTIVITY_ID[STATE_EPA_FLAG == "S"]),
    N_EPA_INSPECTIONS   = uniqueN(ACTIVITY_ID[STATE_EPA_FLAG == "E"])
  ), by = .(facility_id, YEAR, MONTH)]

# ------------------------------------------------------------------------------
# STEP 5: Attach the counts to the panel and fill non-inspected months with 0.
# ------------------------------------------------------------------------------
new_cols <- c("N_INSPECTIONS_TOTAL", "N_CEI", "N_ROS", "N_SA1", "N_AU1",
              "N_STATE_INSPECTIONS", "N_EPA_INSPECTIONS")

# Left-join: panel key FACILITY_UIN == inspection key facility_id, plus YEAR/MONTH.
panel <- insp_month[panel,
                    on = c(facility_id = "FACILITY_UIN", "YEAR", "MONTH")]
setnames(panel, "facility_id", "FACILITY_UIN")            # restore the panel's name

# Facility-months with no inspection came through as NA. A true zero only
# applies while the facility was actually operating (FACILITY_OPERATING == 1,
# from 01_build_facility_month_panel_major_individual.R); months outside its
# active window get an explicit NA -- the count is undefined, not zero. But a
# REAL matched inspection always wins over the operating flag: some facilities
# have genuine recorded inspections outside their computed open/close window
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
# STEP 6: Run log (sanity checks; see ASSUMPTIONS 2-3 for why sums differ).
# ------------------------------------------------------------------------------
message("=== 02_add_inspections: inspection counts attached to month panel ===")
message("Inspection rows in window (2005-2025)          : ", n_rows_read)
# na.rm = TRUE throughout: non-operating months are now legitimately NA
# (FACILITY_OPERATING == 0), so these sanity checks are computed over the
# operating rows only, same as before this change for every operating row.
message("Distinct inspections routed onto panel months  : ", sum(panel$N_INSPECTIONS_TOTAL, na.rm = TRUE))
message("Facility-months with >=1 inspection            : ", sum(panel$N_INSPECTIONS_TOTAL > 0, na.rm = TRUE))
message("  of which any CEI / ROS / SA1 / AU1           : ",
        sum(panel$N_CEI > 0, na.rm = TRUE), " / ", sum(panel$N_ROS > 0, na.rm = TRUE), " / ",
        sum(panel$N_SA1 > 0, na.rm = TRUE), " / ", sum(panel$N_AU1 > 0, na.rm = TRUE))
message("State-led / EPA-led inspection totals          : ",
        sum(panel$N_STATE_INSPECTIONS, na.rm = TRUE), " / ", sum(panel$N_EPA_INSPECTIONS, na.rm = TRUE))
message("Identity n_state + n_epa == n_total holds      : ",
        all(panel$N_STATE_INSPECTIONS + panel$N_EPA_INSPECTIONS == panel$N_INSPECTIONS_TOTAL, na.rm = TRUE))
message("Facility-months NOT operating (NA counts)      : ", sum(panel$FACILITY_OPERATING == "0"))
message("Panel rows: ", nrow(panel), " | columns: ", ncol(panel))
message("Written to: ", OUT_PATH)
