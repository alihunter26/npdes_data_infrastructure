# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# 04_add_violations.R
# ------------------------------------------------------------------------------
# FOURTH STEP in the facility-by-month pipeline. Reads the panel produced by
# 03_add_naics_sic.R and attaches, for every facility-month, counts of four
# kinds of NPDES violations:
#
#   NPDES_PS_VIOLATIONS.csv -> permit-schedule violations
#   NPDES_CS_VIOLATIONS.csv -> compliance-schedule violations
#   NPDES_SE_VIOLATIONS.csv -> single-event violations
#   NPDES_EFF_VIOLATIONS.csv -> effluent (DMR) violations, restricted to
#                               Total Suspended Solids gross-effluent monthly
#                               averages (see the EFFLUENT section below)
#
#   Input  : data/processed/03_facility_month_panel_major_individual_naics_sic_2005_2025.csv
#            (one row per FACILITY_UIN x YEAR x MONTH; built by scripts 01-03)
#   Output : data/processed/04_facility_month_panel_major_individual_violations_2005_2025.csv
#            (the same panel + 7 new violation-count columns)
#
# COLUMNS ADDED (all integers, counted within each facility-month):
#   N_PS_VIOLATIONS       - permit-schedule violations
#   N_CS_VIOLATIONS       - compliance-schedule violations
#   N_SE_VIOLATIONS       - single-event violations
#   N_TSS_EFF_VIOLATIONS  - TSS gross-effluent monthly-average violations (all codes)
#   N_TSS_EFF_D90         - ...of which VIOLATION_CODE D90 (DMR, Limited - Overdue)
#   N_TSS_EFF_D80         - ...of which VIOLATION_CODE D80 (DMR, Monitor Only - Overdue)
#   N_TSS_EFF_E90         - ...of which VIOLATION_CODE E90 (effluent limit exceedance)
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
#   5. EFFLUENT VIOLATIONS ARE FILTERED TO A SINGLE, SPECIFIC LIMIT (per PI
#      guidance). NPDES_EFF_VIOLATIONS.csv is one row per parameter/limit value
#      reported on a DMR. We keep ONLY rows that are ALL of:
#        - Total Suspended Solids : PARAMETER_CODE == "00530" (EPA's standard TSS
#          code; the several other suspended-solids synonym codes are excluded).
#        - gross effluent         : MONITORING_LOCATION_CODE == "1" (Effluent
#          Gross; rare variants like "EG"/"E1" are excluded).
#        - monthly average        : STATISTICAL_BASE_MONTHLY_AVG == "A" (EPA's
#          monthly-average-equivalent flag, which groups the true monthly average
#          MK/"MO AVG" with the equivalents EPA treats as monthly limits).
#      Each kept violation is dated by MONITORING_PERIOD_END_DATE (the DMR
#      monitoring period it covers; 100% present in this subset). N_TSS_EFF_D90 /
#      _D80 / _E90 break the total out by VIOLATION_CODE; the D-codes are DMR
#      non-receipt (a required value not reported) and E90 is a numeric limit
#      exceedance. N_TSS_EFF_VIOLATIONS counts ALL codes in the subset, so it is
#      >= the sum of the three break-outs if any other code ever appears.
#
#   6. THE EFFLUENT FILE IS STREAMED ONCE AND PRE-FILTERED IN PYTHON.
#      NPDES_EFF_VIOLATIONS.csv is ~16 GB uncompressed, so it is never extracted
#      to disk: it is streamed straight out of its zip (via `unzip -p`) and
#      piped through a small Python csv filter that keeps only the tiny
#      TSS/gross/monthly subset and emits just the columns we need, so R never
#      holds the whole file (keeps peak memory small on a constrained machine).
#      REQUIRES python3 on PATH. NOTE: this file writes empty fields as bare
#      commas but non-empty ones quoted, so a naive awk/`cut` delimiter-split
#      would misalign columns -- it must be parsed by a real CSV reader (Python's
#      csv module here; fread on the R side reads the already-clean subset).
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

# Effluent-violations source: a ~16 GB CSV inside a zip in data/raw/ (streamed,
# never extracted). The filter constants below define the single limit we keep
# (see ASSUMPTION 5): TSS parameter code, gross-effluent location code, and the
# monthly-average flag.
EFF_ZIP        <- list.files(file.path(CWA_ROOT, "data/raw"),
                             pattern = "eff.*zip", full.names = TRUE)[1]
EFF_CSV        <- "NPDES_EFF_VIOLATIONS.csv"
TSS_PARAM_CODE <- "00530"       # Solids, total suspended (standard EPA TSS code)
GROSS_LOC_CODE <- "1"           # MONITORING_LOCATION_CODE for Effluent Gross
MONTHLY_AVG    <- "A"           # STATISTICAL_BASE_MONTHLY_AVG flag = monthly average

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
# STEP 3B: Stream the effluent file and count TSS gross monthly-average
#          violations to facility-months (ASSUMPTIONS 5-6).
# ------------------------------------------------------------------------------
# Streams NPDES_EFF_VIOLATIONS.csv straight from its zip, pre-filtering to the
# small TSS/gross/monthly subset in Python before the data reaches R, then
# dates, routes, and counts exactly like count_violations() above. Returns one
# row per (facility_id, YEAR, MONTH) with the total plus the D90/D80/E90 break-outs.
count_effluent_violations <- function() {
  # The raw zip's real filename contains a non-ASCII space (a narrow no-break
  # space) that fread(cmd=) cannot encode into its shell command. Point an
  # ASCII-named temporary symlink at the zip -- this neither copies nor modifies
  # the immutable raw file -- and stream through that instead.
  link <- file.path(tempdir(), "npdes_eff_downloads.zip")
  unlink(link, force = TRUE)                 # no-op if absent; clears a stale link
  file.symlink(EFF_ZIP, link)
  on.exit(unlink(link, force = TRUE), add = TRUE)

  # Pre-filter the ~16 GB stream in Python BEFORE it reaches R, so peak memory
  # stays tiny on a memory-constrained machine. Python's csv module parses the
  # file's quoting correctly (empty fields are bare commas, non-empty ones are
  # quoted -- a naive awk/`cut` split would misalign columns), keeps only the
  # TSS / gross-effluent / monthly-average rows, and emits just the four columns
  # we need. fread then reads that small result. The filter values are passed as
  # arguments so the TSS/gross/monthly definition lives in ONE place (the config
  # constants above). Column positions are located by header name, so the filter
  # survives any future column re-ordering in the source file.
  python <- Sys.which("python3")
  if (python == "") stop("python3 not found on PATH; it is required to stream the effluent file.")
  py_code <- '
import csv, sys
param_code, loc_code, monthly_flag = sys.argv[1], sys.argv[2], sys.argv[3]
reader = csv.reader(sys.stdin)
writer = csv.writer(sys.stdout)
header = next(reader)
i_param = header.index("PARAMETER_CODE")
i_loc   = header.index("MONITORING_LOCATION_CODE")
i_ma    = header.index("STATISTICAL_BASE_MONTHLY_AVG")
out_cols = ["NPDES_ID", "NPDES_VIOLATION_ID", "VIOLATION_CODE", "MONITORING_PERIOD_END_DATE"]
out_idx  = [header.index(c) for c in out_cols]
need_max = max(i_param, i_loc, i_ma, *out_idx)
writer.writerow(out_cols)
for row in reader:
    if len(row) <= need_max:
        continue
    if row[i_param] == param_code and row[i_loc] == loc_code and row[i_ma] == monthly_flag:
        writer.writerow([row[j] for j in out_idx])
'
  py_file <- tempfile(fileext = ".py")
  writeLines(py_code, py_file)
  on.exit(unlink(py_file, force = TRUE), add = TRUE)

  read_cmd <- sprintf("unzip -p %s %s | %s %s %s %s %s",
                      shQuote(link), shQuote(EFF_CSV),
                      shQuote(python), shQuote(py_file),
                      shQuote(TSS_PARAM_CODE), shQuote(GROSS_LOC_CODE), shQuote(MONTHLY_AVG))

  # The Python step already applied the TSS/gross/monthly filter (ASSUMPTION 5),
  # so fread receives only the small matching subset (its 4 columns, named).
  eff <- fread(cmd = read_cmd, colClasses = "character", showProgress = FALSE)
  stopifnot(nrow(eff) > 0)          # guard against a silent pipe/filter failure
  eff[, NPDES_ID := trimws(NPDES_ID)]

  # Date by the DMR monitoring period, keep the window, route to facility.
  eff[, vdate := mdy(MONITORING_PERIOD_END_DATE, quiet = TRUE)]
  eff <- eff[!is.na(vdate)]
  eff[, `:=`(YEAR = year(vdate), MONTH = month(vdate))]
  eff <- eff[YEAR >= YEAR_MIN & YEAR <= YEAR_MAX]
  eff <- xwalk[eff, on = "NPDES_ID", nomatch = 0]

  # DISTINCT violations per facility-month: total, then broken out by code.
  eff[, .(
      N_TSS_EFF_VIOLATIONS = uniqueN(NPDES_VIOLATION_ID),
      N_TSS_EFF_D90        = uniqueN(NPDES_VIOLATION_ID[VIOLATION_CODE == "D90"]),
      N_TSS_EFF_D80        = uniqueN(NPDES_VIOLATION_ID[VIOLATION_CODE == "D80"]),
      N_TSS_EFF_E90        = uniqueN(NPDES_VIOLATION_ID[VIOLATION_CODE == "E90"])
    ), by = .(facility_id, YEAR, MONTH)]
}

eff <- count_effluent_violations()

# ------------------------------------------------------------------------------
# STEP 4: Combine the four count tables into one facility-month table.
# ------------------------------------------------------------------------------
# Full outer merge so a facility-month with any one kind of violation is kept;
# kinds not present in that month come through as NA and are set to 0 below.
new_cols <- c("N_PS_VIOLATIONS", "N_CS_VIOLATIONS", "N_SE_VIOLATIONS",
              "N_TSS_EFF_VIOLATIONS", "N_TSS_EFF_D90", "N_TSS_EFF_D80", "N_TSS_EFF_E90")
counts <- Reduce(function(a, b) merge(a, b, by = c("facility_id", "YEAR", "MONTH"), all = TRUE),
                 list(ps, cs, se, eff))
for (c in new_cols) counts[is.na(get(c)), (c) := 0L]

# ------------------------------------------------------------------------------
# STEP 5: Attach the counts to the panel and fill non-violation months with 0.
# ------------------------------------------------------------------------------
# Left-join: panel key FACILITY_UIN == violation key facility_id, plus YEAR/MONTH.
panel <- counts[panel, on = c(facility_id = "FACILITY_UIN", "YEAR", "MONTH")]
setnames(panel, "facility_id", "FACILITY_UIN")            # restore the panel's name

# Facility-months with no violation of a given kind came through as NA -> 0L.
for (c in new_cols) panel[is.na(get(c)), (c) := 0L]

# Put the new columns at the end, after the existing panel columns, and restore
# the panel's row order.
setcolorder(panel, c(setdiff(names(panel), new_cols), new_cols))
setorder(panel, FACILITY_UIN, YEAR, MONTH)

fwrite(panel, OUT_PATH)

# ------------------------------------------------------------------------------
# STEP 6: Run log (sanity checks).
# ------------------------------------------------------------------------------
message("=== 04_add_violations: violation counts attached to month panel ===")
message("Permit-schedule violations placed on panel     : ", sum(panel$N_PS_VIOLATIONS))
message("Compliance-schedule violations placed on panel : ", sum(panel$N_CS_VIOLATIONS))
message("Single-event violations placed on panel        : ", sum(panel$N_SE_VIOLATIONS))
message("Facility-months with >=1 PS / CS / SE violation : ",
        sum(panel$N_PS_VIOLATIONS > 0), " / ",
        sum(panel$N_CS_VIOLATIONS > 0), " / ",
        sum(panel$N_SE_VIOLATIONS > 0))
message("TSS gross monthly-avg effluent violations       : ", sum(panel$N_TSS_EFF_VIOLATIONS),
        "  (D90 ", sum(panel$N_TSS_EFF_D90),
        " / D80 ", sum(panel$N_TSS_EFF_D80),
        " / E90 ", sum(panel$N_TSS_EFF_E90), ")")
message("Facility-months with >=1 TSS effluent violation : ", sum(panel$N_TSS_EFF_VIOLATIONS > 0))
message("Panel rows: ", nrow(panel), " | columns: ", ncol(panel))
message("Written to: ", OUT_PATH)
