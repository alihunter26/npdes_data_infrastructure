# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# 01_build_facility_month_panel_major_individual.R
# ------------------------------------------------------------------------------
# Build a FACILITY-by-MONTH panel (Jan 2005 - Dec 2025) of facilities that were
# EVER major AND EVER held an individual (not general) NPDES permit, at any
# point in their permit history.
#
#   Unit of analysis : FRS facility (FACILITY_UIN; falls back to NPDES_ID when
#                       FACILITY_UIN is blank -- see STEP 4 below)
#   Population        : facilities linked to >=1 individual ("NPD") permit that
#                       was flagged MAJOR ("M") in at least one of its permit-
#                       version records, at any point in its history. This is
#                       "ever major", NOT "always major" -- a facility that was
#                       major for even one year of its history qualifies, even
#                       if it was minor before or after.
#   Spine             : BALANCED = every qualifying facility x every (year, month)
#                       in the full Jan 2005 - Dec 2025 window, regardless of when
#                       that facility actually held an active permit. A new
#                       FACILITY_OPERATING flag (1/0) marks which rows fall inside
#                       vs. outside each facility's own earliest-open/latest-close
#                       window (clipped to the panel window) -- downstream scripts
#                       use it to distinguish a true zero (operating, no event) from
#                       an undefined one (not operating -- see LABELED ASSUMPTION 9).
#

# LABELED ASSUMPTIONS (read before using results):
#   1. "EVER MAJOR", NOT "ALWAYS MAJOR". This is a broader/looser population
#      than 03_build_facility_panel_major_individual.R (in scripts/build/),
#      which requires a facility to be major in EVERY held year and NEVER
#      minor. Here, one "M" flag anywhere in the permit's version history is
#      enough. (Per PI guidance.)
#   2. PER-PERMIT WINDOW = EARLIEST POSSIBLE OPEN -> LATEST POSSIBLE CLOSE.
#      ICIS_PERMITS has several candidate date fields for when a permit
#      started and ended. To be maximally inclusive (better to over-cover than
#      under-cover the true active window), we take:
#        opening = EARLIEST of EFFECTIVE_DATE, ISSUE_DATE, ORIGINAL_ISSUE_DATE
#        closing = LATEST of EXPIRATION_DATE, TERMINATION_DATE, RETIREMENT_DATE
#      (Per PI guidance: "earliest possible date for opening... latest
#      possible date for closing.")
#   3. NO CLOSING DATE = STILL ACTIVE. If a permit has none of the three
#      closing-date fields filled in, it is treated as active through the end
#      of the panel window (Dec 2025). This matches the convention already
#      used in scripts/build/03_build_facility_panel_major_individual.R.
#   4. FACILITY WINDOW = UNION ACROSS *ALL* ITS INDIVIDUAL PERMITS. Once a
#      facility qualifies (>=1 ever-major individual permit at some point), the
#      facility's own month range runs from the EARLIEST opening to the LATEST
#      closing across ALL individual permits ever linked to it -- not just the
#      specific permit(s) that were major -- because the facility (not the
#      permit) is the unit of analysis here.
#   5. FACILITY_UIN FALLBACK. A small number of ICIS_FACILITIES rows have a
#      blank FACILITY_UIN. Per PI guidance, these are kept, and identified by
#      their NPDES_ID instead, so no permit is silently dropped for lacking an
#      FRS identifier.
#   6. MULTIPLE NPDES_IDs PER FACILITY -> SEMICOLON LIST. A facility can be
#      linked to more than one individual permit over time (e.g., an old permit
#      number that was reissued under a new number). All individual NPDES_IDs
#      ever linked to a qualifying facility are combined into one semicolon-
#      separated string per facility-month, so facility-month stays a single,
#      unique row. (Per PI guidance.)
#   7. SNAPSHOT ATTRIBUTES. FACILITY_TYPE_CODE, FACILITY_NAME, address, county,
#      and lat/long are all read from ICIS_FACILITIES, which stores only ONE
#      current snapshot per facility record -- there is no history of how these
#      attributes changed over time. We take a single representative record per
#      facility (preferring one with a non-blank name) and broadcast it across
#      every month in that facility's window. Real address/location changes
#      over time are NOT captured.
#   8. ZIP KEPT AS TEXT. ZIP is read and stored as a character column
#      throughout (never coerced to numeric), so leading zeros in ZIP codes
#      (e.g., many New England zips) are preserved exactly as in the source
#      file.
#   9. FACILITY_OPERATING = 1 iff the calendar month falls within
#      [floor_date(spine_start,"month"), floor_date(spine_end,"month")] for that
#      facility -- i.e. within the SAME earliest-open/latest-close window (unioned
#      across all the facility's individual permits, clipped to the panel window;
#      see ASSUMPTIONS 2-4) already used to decide which facilities/months qualify
#      for the spine at all. This introduces no new business rule -- it exposes a
#      value already computed, so downstream scripts can tell "operating, zero
#      events" (FACILITY_OPERATING=1, count=0) apart from "not operating, count is
#      undefined" (FACILITY_OPERATING=0, count should read NA). Facility ATTRIBUTE
#      columns (name, address, NPDES_ID list, ...) are NOT masked by this flag --
#      they keep broadcasting the one representative snapshot across every month,
#      unchanged from before (per ASSUMPTION 7).
#
# Source: EPA ECHO bulk "ICIS-NPDES" download (ICIS_PERMITS.csv, ICIS_FACILITIES.csv)
# Output: data/processed/01_facility_month_panel_major_individual_2005_2025.csv
# Deterministic (no stochastic steps); rebuilt entirely from raw + this script.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)   # fast CSV reads + table joins over ~1-2 million row inputs
  library(lubridate)    # date parsing (mdy) and year()/month() extraction
})

## ---- Config (edit here if the panel window or file locations ever change) ----
YEAR_MIN <- 2005L
YEAR_MAX <- 2025L
RAW_DIR  <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
OUT_PATH <- file.path(CWA_ROOT, "data/processed/01_facility_month_panel_major_individual_2005_2025.csv")

# The first and last calendar months the panel can ever contain.
WINDOW_START <- as.Date(sprintf("%d-01-01", YEAR_MIN))   # Jan 1, 2005
WINDOW_END   <- as.Date(sprintf("%d-12-01", YEAR_MAX))   # Dec 1, 2025

# Small helper: read only the columns we need, and read everything as plain
# text (character), never as numbers. This matters most for ZIP and the ID
# columns, which must not be silently reinterpreted as numeric.
rd <- function(file, cols) {
  class_map <- setNames(rep("character", length(cols)), cols)
  fread(file.path(RAW_DIR, file), select = cols,
        colClasses = class_map, showProgress = FALSE)
}

# ------------------------------------------------------------------------------
# STEP 1: Read ICIS_PERMITS.csv and keep only INDIVIDUAL permits.
# ------------------------------------------------------------------------------
# Each row in ICIS_PERMITS is one *version* of a permit: the same permit number
# (called EXTERNAL_PERMIT_NMBR here, but this is the same ID as NPDES_ID
# elsewhere) can appear many times as it is reissued, modified, or as its
# major/minor status changes across the years. PERMIT_TYPE_CODE == "NPD" is
# EPA's code for an "individual" permit (as opposed to a general permit, which
# covers many facilities under one shared permit).
pm <- rd("ICIS_PERMITS.csv",
         c("EXTERNAL_PERMIT_NMBR", "PERMIT_TYPE_CODE", "MAJOR_MINOR_STATUS_FLAG",
           "EFFECTIVE_DATE", "ISSUE_DATE", "ORIGINAL_ISSUE_DATE",
           "EXPIRATION_DATE", "TERMINATION_DATE", "RETIREMENT_DATE"))

pm[, NPDES_ID         := trimws(EXTERNAL_PERMIT_NMBR)]
pm[, PERMIT_TYPE_CODE := trimws(PERMIT_TYPE_CODE)]
pm[, MAJOR_MINOR_STATUS_FLAG := trimws(MAJOR_MINOR_STATUS_FLAG)]
pm <- pm[PERMIT_TYPE_CODE == "NPD"]   # keep individual permits only

# ------------------------------------------------------------------------------
# STEP 2: For each permit-version row, work out the widest possible opening
# and closing month, and whether that version was flagged "major".
# ------------------------------------------------------------------------------
# Opening: take the EARLIEST non-missing date among the three candidate
# "start" fields. This is the most generous (earliest) reading of when the
# permit could have started being active.
pm[, open_date := pmin(mdy(EFFECTIVE_DATE, quiet = TRUE),
                       mdy(ISSUE_DATE, quiet = TRUE),
                       mdy(ORIGINAL_ISSUE_DATE, quiet = TRUE),
                       na.rm = TRUE)]

# Closing: take the LATEST non-missing date among the three candidate "end"
# fields. This is the most generous (latest) reading of when the permit could
# have stopped being active.
pm[, close_date := pmax(mdy(EXPIRATION_DATE, quiet = TRUE),
                        mdy(TERMINATION_DATE, quiet = TRUE),
                        mdy(RETIREMENT_DATE, quiet = TRUE),
                        na.rm = TRUE)]

# Was this specific permit-version ever flagged "M" (major)?
pm[, is_major := MAJOR_MINOR_STATUS_FLAG == "M"]

# If a permit-version has no usable opening date at all, we have no way to
# place it in time, so drop it (a very small share of rows -- see run log).
n_pm_before <- uniqueN(pm$NPDES_ID)
pm <- pm[!is.na(open_date)]

# ------------------------------------------------------------------------------
# STEP 3: Collapse permit-versions down to one row per NPDES_ID (i.e., per
# permit), keeping that permit's overall earliest-open / latest-close window
# and whether it was EVER major in any of its versions.
# ------------------------------------------------------------------------------
permits <- pm[, .(
    permit_open  = min(open_date, na.rm = TRUE),
    # If every version of this permit is missing a closing date, treat the
    # permit as still active through the last month of the panel (see
    # LABELED ASSUMPTION 3 above).
    permit_close = if (all(is.na(close_date))) WINDOW_END else max(close_date, na.rm = TRUE),
    ever_major   = any(is_major),
    major_minor_status = paste(sort(unique(MAJOR_MINOR_STATUS_FLAG)), collapse = "; "),
    permit_type = paste(sort(unique(PERMIT_TYPE_CODE)), collapse = "; ")
  ), by = NPDES_ID]

# ------------------------------------------------------------------------------
# STEP 4: Read ICIS_FACILITIES and link each individual permit to its facility.
# ------------------------------------------------------------------------------
# ICIS_FACILITIES has one row per NPDES_ID and carries the FRS facility
# identifier (FACILITY_UIN) plus the facility's name/address/location snapshot.
fac <- rd("ICIS_FACILITIES.csv",
          c("NPDES_ID", "FACILITY_UIN", "FACILITY_TYPE_CODE", "FACILITY_NAME",
            "LOCATION_ADDRESS", "CITY", "STATE_CODE", "ZIP", "COUNTY_CODE",
            "GEOCODE_LATITUDE", "GEOCODE_LONGITUDE"))
fac[, NPDES_ID     := trimws(NPDES_ID)]
fac[, FACILITY_UIN := trimws(FACILITY_UIN)]

# Keep only facility records for the individual permits identified in STEP 1-3.
fac <- fac[NPDES_ID %in% permits$NPDES_ID]

# FACILITY_UIN fallback (LABELED ASSUMPTION 5): if FACILITY_UIN is blank, use
# the permit's own NPDES_ID as the facility identifier instead of dropping it.
fac[, facility_id := fifelse(FACILITY_UIN != "", FACILITY_UIN, NPDES_ID)]

# Attach each permit's open/close window and ever_major flag to its facility record.
fac <- permits[fac, on = "NPDES_ID"]

# Filter to 48 continental US states + DC (exclude Alaska, Hawaii, and US territories).
fac <- fac[!(STATE_CODE %in% c("AK", "HI", "PR", "VI", "GU", "AS", "MP"))]

# ------------------------------------------------------------------------------
# STEP 5: Facility-level eligibility and window.
# ------------------------------------------------------------------------------
# A facility qualifies if ANY of its linked individual permits was ever major.
# Its overall window spans the earliest opening to the latest closing across
# ALL of its individual permits (LABELED ASSUMPTION 4), and we also build the
# semicolon-separated list of every individual NPDES_ID linked to it
# (LABELED ASSUMPTION 6).
fac_window <- fac[, .(
    facility_open       = min(permit_open),
    facility_close       = max(permit_close),
    facility_ever_major  = any(ever_major),
    NPDES_ID             = paste(sort(unique(NPDES_ID)), collapse = "; "),
    MAJOR_MINOR_FLAG    = paste(sort(unique(major_minor_status)), collapse = "; "),
    PERMIT_TYPE_FLAG    = paste(sort(unique(permit_type)), collapse = "; ")
  ), by = facility_id]

qual_fac <- fac_window[facility_ever_major == TRUE]

# Clip each qualifying facility's window to the panel's Jan 2005 - Dec 2025
# bounds, then drop any facility whose true window doesn't overlap that range
# at all (e.g., a permit that closed for good before 2005).
qual_fac[, spine_start := pmax(facility_open, WINDOW_START)]
qual_fac[, spine_end   := pmin(facility_close, WINDOW_END)]
qual_fac <- qual_fac[spine_start <= spine_end]

# Calendar-month bounds of the operating window (LABELED ASSUMPTION 9), used below
# to compute FACILITY_OPERATING at the same month granularity the spine itself uses.
qual_fac[, spine_start_month := floor_date(spine_start, "month")]
qual_fac[, spine_end_month   := floor_date(spine_end,   "month")]

# ------------------------------------------------------------------------------
# STEP 6: Facility attribute snapshot (one representative record per facility).
# ------------------------------------------------------------------------------
# When a facility has more than one linked NPDES_ID, prefer the record that has
# a non-blank FACILITY_NAME as the representative snapshot (LABELED ASSUMPTION 7).
fac[, has_name := as.integer(!is.na(FACILITY_NAME) & FACILITY_NAME != "")]
setorder(fac, facility_id, -has_name)
fac_attr <- unique(fac, by = "facility_id")[
  , .(facility_id, FACILITY_TYPE_CODE, FACILITY_NAME, LOCATION_ADDRESS, CITY,
      STATE_CODE, ZIP, COUNTY_CODE,
      FAC_LAT  = GEOCODE_LATITUDE,
      FAC_LONG = GEOCODE_LONGITUDE)]

# ------------------------------------------------------------------------------
# STEP 7: Build the facility-by-month spine (BALANCED panel) + FACILITY_OPERATING.
# ------------------------------------------------------------------------------
# Create a complete grid: every qualifying facility x every month in the full
# panel window (Jan 2005 - Dec 2025), regardless of when each facility was
# actually open. Facility ATTRIBUTES (name, address, ...) still broadcast across
# every month unchanged (ASSUMPTION 7) -- but every row also gets FACILITY_OPERATING
# (ASSUMPTION 9), so downstream scripts can tell a real zero apart from an
# undefined one for months outside the facility's active window.
all_months <- data.table(month_date = seq(WINDOW_START, WINDOW_END, by = "month"))
all_months[, `:=`(YEAR = year(month_date), MONTH = month(month_date))]

# BUG FIX (2026-07-21): CJ() does not dedupe its inputs by default (unique=FALSE).
# all_months$YEAR/$MONTH are NOT unique (252 rows each, e.g. YEAR=2005 repeated
# 12x) -- passing them as-is squares the year-month dimension (252 x 252
# instead of 21 x 12), producing ~477M rows instead of ~1.89M and blowing R's
# vector memory limit. Fix: cross facility_id against the DISTINCT year/month
# values, matching every other spine-building in this codebase.
spine <- CJ(facility_id = unique(qual_fac$facility_id),
            YEAR = unique(all_months$YEAR),
            MONTH = unique(all_months$MONTH))
spine <- all_months[spine, on = c("YEAR", "MONTH")]

# Attach each facility's operating-window bounds and flag which spine rows fall
# inside it. Every facility_id here has exactly one (spine_start_month,
# spine_end_month) pair (guaranteed by qual_fac's own spine_start <= spine_end
# filter above), so this join can never introduce a missing bound.
spine <- qual_fac[, .(facility_id, spine_start_month, spine_end_month)][spine, on = "facility_id"]
spine[, FACILITY_OPERATING := as.integer(month_date >= spine_start_month &
                                          month_date <= spine_end_month)]
spine[, c("month_date", "spine_start_month", "spine_end_month") := NULL]

# ------------------------------------------------------------------------------
# STEP 8: Assemble the final panel: spine + facility attributes + NPDES_ID list.
# ------------------------------------------------------------------------------
panel <- fac_attr[spine, on = "facility_id"]
panel <- qual_fac[, .(facility_id, NPDES_ID, MAJOR_MINOR_FLAG, PERMIT_TYPE_FLAG)][panel, on = "facility_id"]
setnames(panel, "facility_id", "FACILITY_UIN")

setcolorder(panel, c("FACILITY_UIN", "YEAR", "MONTH", "NPDES_ID", "MAJOR_MINOR_FLAG",
                     "PERMIT_TYPE_FLAG", "FACILITY_OPERATING", "FACILITY_TYPE_CODE",
                     "FACILITY_NAME", "LOCATION_ADDRESS", "CITY", "STATE_CODE", "ZIP",
                     "COUNTY_CODE", "FAC_LAT", "FAC_LONG"))
setorder(panel, FACILITY_UIN, YEAR, MONTH)

# ZIP must stay text (not numeric) all the way through to the file on disk.
# Format as 5-character string, padding with leading zeros if needed.
panel[, ZIP := sprintf("%05s", ZIP)]
stopifnot(is.character(panel$ZIP))

fwrite(panel, OUT_PATH)

# ------------------------------------------------------------------------------
# STEP 9: Run log -- always print what was built, so a bad run is caught early.
# ------------------------------------------------------------------------------
message("=== facility-by-month panel: ever-major, ever-individual, entry/exit allowed ===")
message("Individual (NPD) permits read                 : ", n_pm_before)
message("...with an unplaceable opening date (dropped)  : ", n_pm_before - uniqueN(pm$NPDES_ID))
message("Individual permits ever flagged major          : ", sum(permits$ever_major))
message("Qualifying facilities (ever major, ever indiv.): ", nrow(qual_fac))
message("Facilities with >1 linked NPDES_ID             : ",
        sum(lengths(strsplit(qual_fac$NPDES_ID, "; ")) > 1))
message("Panel rows (balanced facility x month, all ", YEAR_MIN, "-", YEAR_MAX, " months): ", nrow(panel))
message("  FACILITY_OPERATING == 1 (in active window)   : ", sum(panel$FACILITY_OPERATING == 1L))
message("  FACILITY_OPERATING == 0 (outside active window): ", sum(panel$FACILITY_OPERATING == 0L))
months_per_fac <- panel[, .N, by = FACILITY_UIN]$N
message("Months per facility: min ", min(months_per_fac), " max ", max(months_per_fac),
        " (", YEAR_MIN, "-", YEAR_MAX, " = ", (YEAR_MAX - YEAR_MIN + 1) * 12, " months if never clipped)")
message("Written to: ", OUT_PATH)
