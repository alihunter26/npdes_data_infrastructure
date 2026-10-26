# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, PROC_DIR, RAW_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))
source(file.path(CWA_ROOT, "code/02_cleaning/cleaning_helpers.R"))   # build_facility_crosswalk()

# ==============================================================================
# build_dmr_clean_panel.R
# ------------------------------------------------------------------------------
# Build a CLEANED DMR panel carrying only the variables we concluded are worth
# keeping, restricted to major individual permits / TSS / Effluent Gross /
# external outfalls / monthly-average measurements.
#
# Everything that is a judgment call is a TOGGLE in the CONFIG block below --
# fiscal year, input file, whether to keep non-monthly reporting periods, which
# value types and statistical bases, which violation fields to carry, and
# whether to attach FACILITY_ID. Change the toggle, re-run, and the run log
# reports what each choice cost.
#
#   Input  : code/dmr/03_dmr_fy<FY>_00530_monloc1.csv  (configurable)
#   Output : data/processed/clean_dmr_<year>.csv, where <year> is the fiscal
#            year of the rows actually READ, not the FY toggle (see STEP 2).
#
# ------------------------------------------------------------------------------
# LABELED ASSUMPTIONS (read before using results):
#
#   1. THE INPUT IS ALREADY PARTLY RESTRICTED. The default input comes from the
#      code/dmr/ row-filter pipeline steps 1-3, which have already applied:
#        - major under an INDIVIDUAL permit (PERMIT_TYPE_CODE 'NPD', ever
#          MAJOR_MINOR_STATUS_FLAG 'M')
#        - PARAMETER_CODE '00530' (TSS)
#        - MONITORING_LOCATION_CODE in ('1','EG')
#      This script adds the external-outfall and monthly-average restrictions.
#      It ASSERTS the upstream ones rather than assuming them, so pointing
#      INPUT_PATH at an unfiltered file fails loudly instead of silently
#      producing a different population.
#
#   2. BOTH '1' AND 'EG' ARE EFFLUENT GROSS. Per EPA's ICIS-NPDES DMR Data
#      Element Dictionary (https://echo.epa.gov/node/206) the monitoring
#      location code has three Effluent Gross variants: '1', 'EG', and 'Y'
#      (Effluent Gross - Supplementary). The upstream filter keeps '1' and 'EG';
#      accepting only '1' would silently discard the 1,101 FY2017 'EG' rows and
#      delete two permits entirely. 'Y' is excluded upstream and verified
#      harmless for this scope (its one in-scope FY2017 row duplicates a
#      primary measurement).
#
#   3. "OUTFALL" MEANS EXTERNAL OUTFALL (PERM_FEATURE_TYPE_CODE 'EXO').
#      Monitoring location 1 still admits internal outfalls ('INO') and other
#      feature types; counting those would double-count the same water on its
#      way out.
#      OUTFALL IDENTITY IS (permit, PERM_FEATURE_NMBR), NEVER THE NUMBER ALONE
#      -- 199 of 457 distinct FY2017 outfall numbers occur under more than one
#      permit, so outfall '001' is a different physical outfall at different
#      permits. The output carries that pair as its two own columns
#      (EXTERNAL_PERMIT_NMBR, PERM_FEATURE_NMBR); KEY ON BOTH. No pasted-together
#      `outfall_uid` column is written -- a composite string has to be split
#      again to be joined on, and it reads as a single opaque id, which is
#      exactly the mistake this assumption warns against.
#
#   4. MONTHLY AVERAGE = EVERY STATISTICAL BASE EPA FLAGS AS ONE: the codes with
#      STATISTICAL_BASE_MONTHLY_AVG == 'A' in data/raw/reference/
#      REF_STATISTICAL_BASE.csv (12 codes, read from the file, not typed here).
#      That includes 'DB' (Daily Average) and the 30-day codes ('3C' etc.), not
#      just 'MK'. STATISTICAL_BASE_CODE is carried and is part of the row key, so
#      any narrower definition is a filter on the output. In FY2017, 660 of
#      5,223 permits with a monthly-average-flagged base other than DB report
#      no 'MK' row at all (mostly '3C'), so 'MK' alone is not a neutral choice.
#      To drop a code (e.g. DB), list it in EXCLUDE_STAT_BASES.
#
#   5. STATISTICAL BASE AND REPORTING PERIOD ARE INDEPENDENT. 'MK' says the
#      STATISTIC is a monthly average; NMBR_OF_REPORT says how many MONTHS the
#      row covers (EPA: "The number of months in the monitoring period covered
#      by the DMR (e.g., monthly = 1, quarterly = 3, semi-annually = 6)").
#      A quarterly row with 'MK' is a monthly average computed over 3 months,
#      dated to the window's end. Such rows are KEPT by default
#      (RESTRICT_MONTHLY_ONLY = FALSE): a quarterly reporter has one row per
#      quarter, and the two months without a row are not missing data.
#      NMBR_OF_SUBMISSION is deliberately NOT carried: it is the FILING cadence,
#      not the measurement window, and filtering on it would discard 4,019
#      genuine monthly observations that happen to be filed in quarterly
#      batches.
#
#   6. ROW KEY. One row per
#        EXTERNAL_PERMIT_NMBR x PERM_FEATURE_NMBR x MONITORING_PERIOD_END_DATE
#        x VALUE_TYPE_CODE x LIMIT_SET_ID x STATISTICAL_BASE_CODE
#        x MONITORING_LOCATION_CODE x LIMIT_ID
#      asserted unique before writing. Every part is needed in FY2017: a limit
#      set can report one statistic in two concentration slots (C2 with C1 or
#      C3), under both '1' and 'EG', or under two LIMIT_IDs. MULTIPLE LIMIT SETS
#      ARE KEPT, never collapsed or tie-broken. LIMIT_SET_DESIGNATOR is carried
#      beside LIMIT_SET_ID: within one month they identify the same limit set,
#      but a permit modification or reissuance keeps the designator and issues
#      a new LIMIT_SET_ID (775 of 7,264 FY2017 permit-outfall-designators switch
#      ID mid-year, every switch coinciding with a VERSION_NMBR change).
#
#      Two things are NOT unique at the source and are handled explicitly:
#      (a) VIOLATION FAN-OUT. EPA writes one row per violation, so a value
#          carrying two violations (FY2017: 67 keys, all D90 + E90) appears
#          twice, identical except for the violation fields. Those rows are
#          collapsed to one, with VIOLATION_COLS joined by ';' in a common row
#          order. The script asserts every other column agrees first, so the
#          collapse cannot lose a value.
#      (b) TWO LIMIT_IDs IN ONE LIMIT SET for the same statistic, slot,
#          location and month (FY2017: 21 cells in 3 permits; 18 carry the same
#          value and limit under both IDs, a possible duplicate). Both rows are
#          KEPT and marked FLAG_MULTI_LIMIT_ID = TRUE. Summing across LIMIT_ID
#          within a flagged cell may double-count.
#
#      VERSION_NMBR is not used. EPA: "The current permit is VERSION_NMBR = 0.
#      The oldest permit version is VERSION_NMBR = 1" -- it is the permit
#      version, not a DMR resubmission counter, and "highest" is not "latest".
#
#   7. VALUES ARE COPIED VERBATIM. Every column is read AND written as
#      character, so no number is reparsed, rounded or reformatted. Numeric
#      casting is left to whoever uses the file. Always compare the
#      *_STANDARD_UNITS fields, never the permit-specific *_NMBR fields --
#      permits write TSS limits in g/d, kg/d, lb/d, lb/kgal, lb/qtr, mg/L and
#      ug/L, and only the standard-units columns are comparable across outfalls.
#      STANDARD_UNIT_DESC is carried so every row states its own unit (kg/d for
#      the mass value types, mg/L for concentration).
#
#   8. EXCEEDENCE_PCT CARRIES A SENTINEL. 9 FY2017 in-scope rows hold
#      99999 or more, which is a placeholder rather than a real percentage.
#      They are left exactly as reported and COUNTED in the run log -- filter
#      them before averaging.
#
#   9. NOTHING IS CORRECTED, ONLY REPORTED. Negative TSS values, censored
#      ('<') rows whose number is a detection limit rather than a measurement,
#      and rows blank on both value and NODI code all pass through unchanged.
#      The run log counts each. What to do about them is a research decision.
#
#  10. PREREQUISITES CAN BE BUILT AUTOMATICALLY, STAGE BY STAGE. With
#      AUTO_RUN_PREREQS the script calls the code/dmr/ filter pipeline for any
#      MISSING stage rather than re-running the whole chain: those scripts
#      always rebuild their output, so blindly invoking step 1 would re-stream
#      the 8.24 GB zip member even when 01_dmr_fy<FY>.csv is already on disk.
#      It runs the newest missing stage onwards, verifies each expected output
#      appeared, and stops on the first non-zero exit. Auto-build applies ONLY
#      when INPUT_PATH is the pipeline's own step-3 path for FY -- a custom
#      INPUT_PATH cannot be regenerated, so a missing one is an error.
#      This script never DELETES or overwrites a pipeline file; it only asks
#      the pipeline to create what is absent.
#
# Deterministic (no stochastic steps); read-only with respect to its input;
# non-destructive (writes a NEW file); safe to re-run.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
})

# ---- CONFIG validation -------------------------------------------------------
# Fails on a malformed toggle here rather than surfacing later as an empty
# filter or a generic "no rows survived".
validate_config <- function() {
  if (!is.character(VALUE_TYPES) || length(VALUE_TYPES) == 0L ||
      anyNA(VALUE_TYPES) || any(!nzchar(VALUE_TYPES)))
    stop('VALUE_TYPES must be "all" or a character vector of VALUE_TYPE_CODEs, ',
         'e.g. c("C1","Q2").')
  if (!identical(VALUE_TYPES, "all")) {
    known <- c("C1", "C2", "C3", "Q1", "Q2")
    bad <- setdiff(VALUE_TYPES, known)
    if (length(bad))
      stop("VALUE_TYPES holds code(s) not in C1/C2/C3/Q1/Q2: ",
           paste(bad, collapse = ", "),
           '\n  (To keep every code present, set VALUE_TYPES <- "all".)')
    if (anyDuplicated(VALUE_TYPES))
      stop("VALUE_TYPES repeats a code: ",
           paste(unique(VALUE_TYPES[duplicated(VALUE_TYPES)]), collapse = ", "))
  }
  for (nm in c("RESTRICT_MONTHLY_ONLY", "AUTO_RUN_PREREQS", "ADD_FACILITY_ID")) {
    v <- get(nm)
    if (!is.logical(v) || length(v) != 1L || is.na(v))
      stop(nm, " must be a single TRUE or FALSE, got: ", deparse(v))
  }
  if (!is.character(EXCLUDE_STAT_BASES) || anyNA(EXCLUDE_STAT_BASES))
    stop('EXCLUDE_STAT_BASES must be a character vector, e.g. character(0) or c("DB").')
  allowed_viol <- c("VIOLATION_CODE", "NPDES_VIOLATION_ID", "RNC_DETECTION_CODE",
                    "RNC_DETECTION_DATE", "RNC_RESOLUTION_CODE", "RNC_RESOLUTION_DATE")
  if (!is.character(VIOLATION_COLS) || length(VIOLATION_COLS) == 0L ||
      length(setdiff(VIOLATION_COLS, allowed_viol)))
    stop("VIOLATION_COLS must be a non-empty subset of: ",
         paste(allowed_viol, collapse = ", "))
  invisible(TRUE)
}

# ==============================================================================
# ---- CONFIG: edit these ------------------------------------------------------
# ==============================================================================

## Which fiscal year, and which DMR file to read -------------------------------
FY <- 2017L

# Default: the code/dmr/ pipeline's step-3 output for FY. Point this anywhere
# (another stage, another year, a hand-made extract) -- STEP 1 asserts the
# upstream restrictions hold, so a wrong file errors instead of quietly
# changing the population. See ASSUMPTION 1.
INPUT_PATH <- file.path(CWA_ROOT, "code", "dmr",
                        sprintf("03_dmr_fy%d_00530_monloc1.csv", FY))

# Where the cleaned file goes. The YEAR in the name is not taken from the FY
# toggle -- it is read off the input's own MONITORING_PERIOD_END_DATEs in
# STEP 2, so the filename always states the fiscal year of the data inside it
# even when INPUT_PATH points somewhere unexpected. %d is that year.
OUTPUT_DIR      <- PROC_DIR
OUTPUT_NAME_FMT <- "clean_dmr_%d.csv"

# If INPUT_PATH is missing, build it by running the code/dmr/ pipeline steps
# 1-3 for FY (ASSUMPTION 10). Only the MISSING stages run, so an existing
# 01_/02_ file is reused rather than re-streamed from the 8.24 GB zip.
# TRUE  -> one command, cold start costs ~45 min (mostly the zip stream)
# FALSE -> stop with the commands to run by hand
AUTO_RUN_PREREQS <- TRUE

## Scope toggles ---------------------------------------------------------------
# Keep only rows whose monitoring period is a single month (ASSUMPTION 5).
# FALSE -> (default) full coverage; a quarterly row sits in its period-end
#          month and represents three. Carry NMBR_OF_REPORT and weight
#          accordingly.
# TRUE  -> a clean monthly time axis; in FY2017 (MK only) it cost ~1.6% of
#          rows, ~1.5% of permits and ~8.6% of outfalls, and the loss is NOT
#          random (reduced monitoring is granted by permit, clusters in a few
#          states).
RESTRICT_MONTHLY_ONLY <- FALSE

# Which reported-value slots to keep. A character vector of VALUE_TYPE_CODEs,
# or the literal string "all" for every code present (C1/C2/C3/Q1/Q2).
# Default "all". VALUE_TYPE_CODE is part of the row key (ASSUMPTION 6), so a
# narrower set is a filter on the output, not a different grain.
# Codes are report SLOTS, not statistics -- the C/Q split is
# concentration-vs-quantity, and the digit is the slot, read off ECHO's field
# description since no REF_VALUE_TYPE lookup is published
# (see code/dmr/value_type_vs_statistical_base.md, ASSUMPTION 3 there).
VALUE_TYPES <- "all"

# Statistical bases to DROP from EPA's monthly-average set (ASSUMPTION 4).
# character(0) keeps all of them; c("DB") drops Daily Average.
EXCLUDE_STAT_BASES <- character(0)

# Violation-level fields to carry. These are the only fields that differ
# between the rows EPA writes for one value with several violations, so they
# are joined by ';' when those rows are collapsed (ASSUMPTION 6a). Any subset
# of VIOLATION_CODE, NPDES_VIOLATION_ID (joins to
# NPDES_VIOLATION_ENFORCEMENTS.csv), RNC_DETECTION_CODE, RNC_DETECTION_DATE,
# RNC_RESOLUTION_CODE, RNC_RESOLUTION_DATE.
VIOLATION_COLS <- c("VIOLATION_CODE")

## Added-column toggles --------------------------------------------------------
# Beyond the requested variable list. Both default TRUE because the panel is
# facility-keyed and because keying on the bare outfall number is wrong
# (ASSUMPTION 3).
ADD_FACILITY_ID  <- TRUE    # FACILITY_ID via build_facility_crosswalk()

## Fixed scope (change only with a reason) -------------------------------------
F_PARAM     <- "00530"        # TSS
F_MONLOC    <- c("1", "EG")   # both = Effluent Gross (ASSUMPTION 2)
F_FEATURE   <- "EXO"          # external outfall      (ASSUMPTION 3)
# Monthly average = every code EPA flags as one (ASSUMPTION 4), read in STEP 2.
STAT_BASE_REF <- file.path(RAW_ROOT, "reference", "REF_STATISTICAL_BASE.csv")

## The variables to keep, in output order --------------------------------------
# VIOLATION_COLS (above) are written after EXCEEDENCE_PCT; FLAG_MULTI_LIMIT_ID
# is appended last.
KEEP_COLS <- c(
  # keys
  "EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_NMBR", "MONITORING_PERIOD_END_DATE",
  # scope confirmation (near-constant by construction; kept so the file is
  # self-documenting about what population it represents).
  # MONITORING_LOCATION_CODE and STATISTICAL_BASE_CODE are also row-key parts.
  "PERM_FEATURE_TYPE_CODE", "PARAMETER_CODE", "MONITORING_LOCATION_CODE",
  "STATISTICAL_BASE_CODE",
  # grain + limit set (ASSUMPTION 6)
  "VALUE_TYPE_CODE", "LIMIT_SET_DESIGNATOR", "LIMIT_SET_ID", "LIMIT_ID",
  # measurement
  "LIMIT_VALUE_STANDARD_UNITS", "DMR_VALUE_STANDARD_UNITS", "STANDARD_UNIT_DESC",
  "DMR_VALUE_QUALIFIER_CODE", "NODI_CODE",
  # compliance (plus VIOLATION_COLS)
  "EXCEEDENCE_PCT",
  # reporting-period integrity
  "NMBR_OF_REPORT"
)

# Read for internal checks, then dropped from the output.
# Add any of these to KEEP_COLS if you want them retained.
INTERNAL_COLS <- c("LIMIT_VALUE_QUALIFIER_CODE")

# The row key (ASSUMPTION 6). `period_end` is the parsed MONITORING_PERIOD_END_DATE.
ROW_KEY <- c("EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_NMBR", "period_end",
             "VALUE_TYPE_CODE", "LIMIT_SET_ID", "STATISTICAL_BASE_CODE",
             "MONITORING_LOCATION_CODE", "LIMIT_ID")

# Derived columns used for work INSIDE the script but deliberately NOT written:
# `period_end` is the parsed Date driving the fiscal-year clip, de-duplication,
# row ordering and the run log. The output already states the date twice --
# MONITORING_PERIOD_END_DATE verbatim as EPA wrote it (ASSUMPTION 7) and
# YEAR/MONTH for joining -- and a third, re-formatted copy is how two date
# columns start disagreeing downstream.
INTERNAL_DERIVED <- "period_end"

# ==============================================================================
# ---- END CONFIG -------------------------------------------------------------
# ==============================================================================

validate_config()

# ==============================================================================
# STEP 0: make sure the input exists, building it if asked to (ASSUMPTION 10)
# ==============================================================================
DMR_DIR_CODE <- file.path(CWA_ROOT, "code", "dmr")

# The pipeline's three stages, in order: the script to call and the file it
# produces. Stage 3's output is this script's default INPUT_PATH.
PREREQ <- list(
  list(script = "filter_dmr_major_individual.R",
       out    = file.path(DMR_DIR_CODE, sprintf("01_dmr_fy%d.csv", FY)),
       note   = "major individual permits (streams the raw zip -- the slow one)"),
  list(script = "filter_dmr_00530.R",
       out    = file.path(DMR_DIR_CODE, sprintf("02_dmr_fy%d_00530.csv", FY)),
       note   = "TSS (PARAMETER_CODE 00530)"),
  list(script = "filter_dmr_monloc1.R",
       out    = file.path(DMR_DIR_CODE, sprintf("03_dmr_fy%d_00530_monloc1.csv", FY)),
       note   = "Effluent Gross monitoring locations")
)
DEFAULT_INPUT <- PREREQ[[3]]$out

if (!file.exists(INPUT_PATH)) {

  if (!AUTO_RUN_PREREQS || !normalizePath(INPUT_PATH, mustWork = FALSE) ==
                            normalizePath(DEFAULT_INPUT, mustWork = FALSE)) {
    stop("Input DMR file not found: ", INPUT_PATH,
         if (!AUTO_RUN_PREREQS)
           "\n  AUTO_RUN_PREREQS is FALSE. Build it with:"
         else
           paste0("\n  INPUT_PATH is not the pipeline's step-3 path for FY", FY,
                  ",\n  so it cannot be rebuilt automatically. Either point INPUT_PATH at",
                  "\n  ", DEFAULT_INPUT, "\n  or create your file by hand. The pipeline is:"),
         "\n    Rscript code/dmr/filter_dmr_major_individual.R ", FY,
         "\n    Rscript code/dmr/filter_dmr_00530.R ", FY,
         "\n    Rscript code/dmr/filter_dmr_monloc1.R ", FY)
  }

  # Start from the LAST stage whose output already exists -- the filter scripts
  # rebuild unconditionally, so re-running a satisfied stage would redo the
  # 8.24 GB zip stream for nothing.
  have <- vapply(PREREQ, function(p) file.exists(p$out), logical(1))
  first <- if (any(have)) max(which(have)) + 1L else 1L

  message("Input not found: ", basename(INPUT_PATH))
  message("AUTO_RUN_PREREQS is TRUE -- building stages ", first, "-", length(PREREQ),
          " of the code/dmr/ pipeline for FY", FY, ".")
  for (i in seq_along(PREREQ))
    message("   stage ", i, ": ", if (have[i]) "present, reused" else
            if (i >= first) "WILL RUN" else "skipped", "  (", basename(PREREQ[[i]]$out), ")")
  if (first == 1L)
    message("   NOTE: stage 1 streams the ~8.24 GB raw CSV out of its zip; expect ~45 min.")

  RSCRIPT <- file.path(R.home("bin"), "Rscript")
  for (i in seq(first, length(PREREQ))) {
    st <- PREREQ[[i]]
    message("\n--- stage ", i, "/", length(PREREQ), ": ", st$script, " ", FY,
            "  (", st$note, ") ---")
    t0 <- Sys.time()
    status <- system2(RSCRIPT, c(shQuote(file.path(DMR_DIR_CODE, st$script)), FY))
    mins <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
    if (!identical(status, 0L))
      stop("Stage ", i, " (", st$script, ") failed with exit status ", status,
           ".\n  Nothing was written by this script. Fix the stage and re-run.")
    if (!file.exists(st$out))
      stop("Stage ", i, " (", st$script, ") exited 0 but did not produce\n  ", st$out,
           "\n  Refusing to continue on a missing prerequisite.")
    message("--- stage ", i, " done in ", mins, " min -> ", basename(st$out),
            " (", round(file.info(st$out)$size / 1e9, 2), " GB) ---")
  }
  message("\nPrerequisites ready. Continuing with the clean panel build.\n")
}

# ------------------------------------------------------------------------------
# STEP 1: read, and assert the upstream restrictions actually hold
# ------------------------------------------------------------------------------
message("Reading ", basename(INPUT_PATH), " ...")
d <- fread(INPUT_PATH, select = c(KEEP_COLS, VIOLATION_COLS, INTERNAL_COLS),
           colClasses = "character", showProgress = FALSE)
for (j in names(d)) d[[j]] <- trimws(d[[j]])
n_read <- nrow(d)

# ASSUMPTION 1 -- fail loudly on the wrong input rather than silently changing
# the population. %in% for the monitoring location, not ==, per ASSUMPTION 2.
if (!all(d$PARAMETER_CODE == F_PARAM))
  stop("Input is not restricted to PARAMETER_CODE ", F_PARAM,
       " -- found: ", paste(head(unique(d$PARAMETER_CODE), 5), collapse = ", "),
       "\n  Point INPUT_PATH at the step-2 output or later (see ASSUMPTION 1).")
if (!all(d$MONITORING_LOCATION_CODE %in% F_MONLOC))
  stop("Input is not restricted to Effluent Gross (",
       paste(F_MONLOC, collapse = "/"), ") -- found: ",
       paste(head(setdiff(unique(d$MONITORING_LOCATION_CODE), F_MONLOC), 5), collapse = ", "),
       "\n  Point INPUT_PATH at the step-3 output (see ASSUMPTION 1).")

# ------------------------------------------------------------------------------
# STEP 2: apply this script's own restrictions
# ------------------------------------------------------------------------------
n_not_exo <- sum(d$PERM_FEATURE_TYPE_CODE != F_FEATURE)
d <- d[PERM_FEATURE_TYPE_CODE == F_FEATURE]                        # ASSUMPTION 3

# ASSUMPTION 4: EPA's own monthly-average flag, minus any listed exclusions.
if (!file.exists(STAT_BASE_REF))
  stop("Statistical base reference table not found: ", STAT_BASE_REF,
       "\n  It is not in the bulk downloads; see data/raw/README.md.")
ref_sb <- fread(STAT_BASE_REF, colClasses = "character")
if (!all(c("STATISTICAL_BASE_CODE", "STATISTICAL_BASE_MONTHLY_AVG") %in% names(ref_sb)))
  stop(basename(STAT_BASE_REF), " lacks STATISTICAL_BASE_CODE / STATISTICAL_BASE_MONTHLY_AVG.")
ref_sb[, STATISTICAL_BASE_CODE := trimws(STATISTICAL_BASE_CODE)]
monthly_avg_codes <- ref_sb[trimws(STATISTICAL_BASE_MONTHLY_AVG) == "A", STATISTICAL_BASE_CODE]
bad_excl <- setdiff(EXCLUDE_STAT_BASES, monthly_avg_codes)
if (length(bad_excl))
  stop("EXCLUDE_STAT_BASES lists code(s) not in EPA's monthly-average set: ",
       paste(bad_excl, collapse = ", "),
       "\n  Monthly-average codes: ", paste(monthly_avg_codes, collapse = ", "))
F_STAT_BASES <- setdiff(monthly_avg_codes, EXCLUDE_STAT_BASES)

n_not_avg  <- sum(!d$STATISTICAL_BASE_CODE %in% monthly_avg_codes)
n_excl_avg <- sum(d$STATISTICAL_BASE_CODE %in% EXCLUDE_STAT_BASES)
d <- d[STATISTICAL_BASE_CODE %in% F_STAT_BASES]

vt_wanted <- if (identical(VALUE_TYPES, "all")) sort(unique(d$VALUE_TYPE_CODE)) else VALUE_TYPES
n_not_vt <- sum(!d$VALUE_TYPE_CODE %in% vt_wanted)
d <- d[VALUE_TYPE_CODE %in% vt_wanted]

if (nrow(d) == 0L) stop("No rows survived the scope filters -- check the CONFIG block.")

# Dates: period-end month, clipped to the federal fiscal-year window.
d[, period_end := mdy(MONITORING_PERIOD_END_DATE)]
n_bad_date <- sum(is.na(d$period_end))
d <- d[!is.na(period_end)]

# WHICH YEAR DID WE ACTUALLY READ? Federal fiscal year of a period-end date:
# Oct-Dec belong to the NEXT calendar year's FY. Taken from the data rather
# than from the FY toggle so the output filename cannot misreport its own
# contents. The modal value is the file's year; anything else is counted as
# out-of-window below, exactly as before.
fy_of <- function(x) year(x) + (month(x) >= 10L)
fy_tab  <- sort(table(fy_of(d$period_end)), decreasing = TRUE)
fy_data <- as.integer(names(fy_tab)[1])

# A mismatch used to surface only as every row being clipped away and a
# confusing "no rows survived". Say what actually happened instead.
if (fy_data != FY)
  stop("INPUT_PATH holds FY", fy_data, " data but FY is set to ", FY, ".\n  ",
       INPUT_PATH, "\n  Fiscal years present (rows): ",
       paste(sprintf("FY%s=%s", names(fy_tab), format(as.integer(fy_tab), big.mark = ",")),
             collapse = ", "),
       "\n  Set FY <- ", fy_data, "L, or point INPUT_PATH at FY", FY, " data.")

OUTPUT_PATH <- file.path(OUTPUT_DIR, sprintf(OUTPUT_NAME_FMT, fy_data))

fy_start <- as.Date(sprintf("%d-10-01", fy_data - 1L))
fy_end   <- as.Date(sprintf("%d-09-30", fy_data))
n_outside <- sum(d$period_end < fy_start | d$period_end > fy_end)
d <- d[period_end >= fy_start & period_end <= fy_end]

# ------------------------------------------------------------------------------
# STEP 3: reporting period (ASSUMPTION 5)
# ------------------------------------------------------------------------------
d[, nmbr_report_i := suppressWarnings(as.integer(NMBR_OF_REPORT))]
report_tab <- d[, .N, by = NMBR_OF_REPORT][order(suppressWarnings(as.integer(NMBR_OF_REPORT)))]
n_multimonth <- sum(d$nmbr_report_i > 1L, na.rm = TRUE)
mm_permits  <- uniqueN(d[nmbr_report_i > 1L, EXTERNAL_PERMIT_NMBR])
mm_outfalls <- uniqueN(d[nmbr_report_i > 1L, paste(EXTERNAL_PERMIT_NMBR, PERM_FEATURE_NMBR)])

if (RESTRICT_MONTHLY_ONLY) {
  p_before <- uniqueN(d$EXTERNAL_PERMIT_NMBR)
  o_before <- uniqueN(paste(d$EXTERNAL_PERMIT_NMBR, d$PERM_FEATURE_NMBR))
  d <- d[nmbr_report_i == 1L]
  lost_permits  <- p_before - uniqueN(d$EXTERNAL_PERMIT_NMBR)
  lost_outfalls <- o_before - uniqueN(paste(d$EXTERNAL_PERMIT_NMBR, d$PERM_FEATURE_NMBR))
} else {
  lost_permits <- lost_outfalls <- 0L
}

# ------------------------------------------------------------------------------
# STEP 4: one row per ROW_KEY (ASSUMPTION 6)
# ------------------------------------------------------------------------------
# Outfall x month x value type; used only by the run log.
CELL <- c("EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_NMBR", "period_end", "VALUE_TYPE_CODE")
n_pre_collapse <- nrow(d)

# 4a. Violation fan-out (ASSUMPTION 6a). Rows sharing a key must agree on every
#     column outside VIOLATION_COLS -- otherwise collapsing would discard a
#     value, so stop instead. Then join each VIOLATION_COLS field with ';' in
#     one common row order, so the k-th entry of every joined field comes from
#     the same source row.
non_viol <- setdiff(names(d), VIOLATION_COLS)
if (uniqueN(d, by = non_viol) != uniqueN(d, by = ROW_KEY))
  stop("Rows sharing a ROW_KEY differ outside VIOLATION_COLS, so collapsing them ",
       "would lose data.\n  Inspect d[, .N, by = ROW_KEY][N > 1] and extend ROW_KEY.")
d[, n_in_key := .N, by = ROW_KEY]
n_fanout_keys <- uniqueN(d[n_in_key > 1L], by = ROW_KEY)
n_fanout_rows <- sum(d$n_in_key > 1L)
if (n_fanout_keys > 0L) {
  setorderv(d, c(ROW_KEY, intersect("VIOLATION_CODE", VIOLATION_COLS)))
  for (v in VIOLATION_COLS)
    d[n_in_key > 1L, (v) := paste(get(v), collapse = ";"), by = ROW_KEY]
  d <- unique(d, by = ROW_KEY)
}
d[, n_in_key := NULL]
stopifnot(nrow(d) == n_pre_collapse - (n_fanout_rows - n_fanout_keys))

# 4b. Two LIMIT_IDs in one limit set for the same statistic, slot, location and
#     month (ASSUMPTION 6b). Kept, and flagged; `flag_same` records whether the
#     LIMIT_IDs carry identical limit, value, qualifier and NODI (a possible
#     duplicate) or differ (a conflict). Reported in the run log, not written.
LS_CELL <- setdiff(ROW_KEY, "LIMIT_ID")
d[, FLAG_MULTI_LIMIT_ID := uniqueN(LIMIT_ID) > 1L, by = LS_CELL]
flag_tab <- d[FLAG_MULTI_LIMIT_ID == TRUE,
              .(flag_same = uniqueN(paste(LIMIT_VALUE_STANDARD_UNITS, DMR_VALUE_STANDARD_UNITS,
                                          DMR_VALUE_QUALIFIER_CODE, NODI_CODE, sep = "|")) == 1L,
                permit = EXTERNAL_PERMIT_NMBR[1]),
              by = LS_CELL]

# ------------------------------------------------------------------------------
# STEP 5: derived keys, then trim to the requested columns
# ------------------------------------------------------------------------------
n_unrouted <- NA_integer_
n_pre_join <- nrow(d)
if (ADD_FACILITY_ID) {
  xwalk <- build_facility_crosswalk(raw_dir = RAW_DIR)
  d <- xwalk[d, on = c(NPDES_ID = "EXTERNAL_PERMIT_NMBR")]
  setnames(d, "NPDES_ID", "EXTERNAL_PERMIT_NMBR")
  # build_facility_crosswalk() returns the column lower-case as `facility_id`;
  # renamed here (NOT in the helper, which other scripts share) so every column
  # in this file reads in EPA's own ALL-CAPS style. Same values, same rule:
  # FACILITY_UIN when ICIS_FACILITIES.csv has one, else the permit's own
  # NPDES_ID. See the README section "Where FACILITY_ID comes from".
  setnames(d, "facility_id", "FACILITY_ID")
  n_unrouted <- sum(is.na(d$FACILITY_ID))
}

# YEAR/MONTH are derived from MONITORING_PERIOD_END_DATE for joining to the
# facility-by-month panel; the original date string is retained alongside.
d[, `:=`(YEAR = year(period_end), MONTH = month(period_end))]

# INTERNAL_DERIVED rides along here and is dropped at write time in STEP 6.
rest_cols <- setdiff(KEEP_COLS, c("EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_NMBR"))
rest_cols <- append(rest_cols, VIOLATION_COLS, after = match("EXCEEDENCE_PCT", rest_cols))
out_cols <- c(if (ADD_FACILITY_ID) "FACILITY_ID",
              "EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_NMBR",
              INTERNAL_DERIVED, "YEAR", "MONTH",
              rest_cols, "FLAG_MULTI_LIMIT_ID")
out <- d[, ..out_cols]
setorderv(out, c(if (ADD_FACILITY_ID) "FACILITY_ID", "EXTERNAL_PERMIT_NMBR",
                 "PERM_FEATURE_NMBR", "period_end", "VALUE_TYPE_CODE",
                 "STATISTICAL_BASE_CODE", "MONITORING_LOCATION_CODE",
                 "LIMIT_SET_DESIGNATOR", "LIMIT_SET_ID", "LIMIT_ID"))

# ------------------------------------------------------------------------------
# STEP 6: verify, then write
# ------------------------------------------------------------------------------
# One row per ROW_KEY (ASSUMPTION 6). The facility join must not have added rows.
stopifnot(!anyDuplicated(out, by = ROW_KEY))
stopifnot(nrow(out) == n_pre_join)
stopifnot(all(KEEP_COLS %in% names(out)), all(VIOLATION_COLS %in% names(out)))
stopifnot(all(out$PERM_FEATURE_TYPE_CODE == F_FEATURE),
          all(out$STATISTICAL_BASE_CODE %in% F_STAT_BASES),
          all(out$VALUE_TYPE_CODE %in% vt_wanted))
if (RESTRICT_MONTHLY_ONLY) stopifnot(all(out$NMBR_OF_REPORT == "1"))

# Everything above checked and ordered itself on `period_end`; it leaves here.
written_cols <- setdiff(names(out), INTERNAL_DERIVED)
stopifnot(!any(c("period_end", "outfall_uid", "facility_id") %in% written_cols))
fwrite(out[, ..written_cols], OUTPUT_PATH)

# ------------------------------------------------------------------------------
# STEP 7: run log (sanity checks)
# ------------------------------------------------------------------------------
per_cell <- out[, .N, by = c("EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_NMBR",
                             "period_end", "VALUE_TYPE_CODE")]
num <- function(x) suppressWarnings(as.numeric(x))
reported <- out$DMR_VALUE_STANDARD_UNITS != ""
limited  <- out$LIMIT_VALUE_STANDARD_UNITS != ""

message("\n=== build_dmr_clean_panel: FY", FY, " ===")
message("Input                        : ", INPUT_PATH)
message("Toggles                      : RESTRICT_MONTHLY_ONLY=", RESTRICT_MONTHLY_ONLY,
        " | VALUE_TYPES=", paste(if (identical(VALUE_TYPES, "all")) "all" else VALUE_TYPES, collapse = "/"),
        " | EXCLUDE_STAT_BASES=",
        if (length(EXCLUDE_STAT_BASES)) paste(EXCLUDE_STAT_BASES, collapse = "/") else "none",
        "\n                               VIOLATION_COLS=", paste(VIOLATION_COLS, collapse = "/"),
        " | ADD_FACILITY_ID=", ADD_FACILITY_ID)
message("\n-- filter funnel --")
message("Rows read                    : ", format(n_read, big.mark = ","))
message("  dropped, not ", F_FEATURE, "          : ", format(n_not_exo, big.mark = ","))
message("  dropped, not a monthly avg : ", format(n_not_avg, big.mark = ","),
        "   (base outside EPA's STATISTICAL_BASE_MONTHLY_AVG == 'A' set)")
message("  dropped, EXCLUDE_STAT_BASES: ", format(n_excl_avg, big.mark = ","))
message("  dropped, value type        : ", format(n_not_vt, big.mark = ","))
message("  unparseable dates          : ", n_bad_date)
message("  outside FY", FY, " window       : ", format(n_outside, big.mark = ","))
if (RESTRICT_MONTHLY_ONLY)
  message("  dropped, NMBR_OF_REPORT > 1: ", format(n_multimonth, big.mark = ","),
          "   (", lost_permits, " permits and ", lost_outfalls,
          " outfalls lost entirely -- NOT a random subset, ASSUMPTION 5)")
message("  violation fan-out collapsed: ", format(n_fanout_rows, big.mark = ","),
        " rows -> ", format(n_fanout_keys, big.mark = ","), " (ASSUMPTION 6a)")
message("Rows written                 : ", format(nrow(out), big.mark = ","),
        " | columns: ", length(written_cols), " | unique on ROW_KEY: TRUE (asserted)")

message("\n-- coverage --")
message("Facilities / permits / outfalls : ",
        if (ADD_FACILITY_ID) uniqueN(out$FACILITY_ID) else NA, " / ",
        uniqueN(out$EXTERNAL_PERMIT_NMBR), " / ",
        uniqueN(paste(out$EXTERNAL_PERMIT_NMBR, out$PERM_FEATURE_NMBR)))
message("Months covered                  : ", uniqueN(paste(out$YEAR, out$MONTH)),
        "  (", min(out$period_end), " .. ", max(out$period_end), ")")
if (ADD_FACILITY_ID && !is.na(n_unrouted))
  message("Rows with no facility match     : ", format(n_unrouted, big.mark = ","))
message("Cells (outfall x month x value type): ", format(nrow(per_cell), big.mark = ","))
message("  ...cells with >1 row (limit sets / bases / locations / LIMIT_IDs, all kept): ",
        format(sum(per_cell$N > 1L), big.mark = ","),
        sprintf(" (%.2f%%)", 100 * sum(per_cell$N > 1L) / nrow(per_cell)),
        " | max rows in a cell: ", max(per_cell$N))

message("\n-- FLAG_MULTI_LIMIT_ID (ASSUMPTION 6b) --")
message("Limit-set cells with >1 LIMIT_ID : ", nrow(flag_tab),
        " (", sum(out$FLAG_MULTI_LIMIT_ID), " rows, ", uniqueN(flag_tab$permit), " permits)")
message("  same limit/value/qualifier/NODI under every LIMIT_ID (possible duplicate): ",
        sum(flag_tab$flag_same))
message("  different content across LIMIT_IDs (conflict)                          : ",
        sum(!flag_tab$flag_same))
if (nrow(flag_tab))
  print(flag_tab[, .(cells = .N, possible_duplicate = sum(flag_same),
                     conflict = sum(!flag_same)), by = permit])

message("\n-- value types --")
print(out[, .N, by = VALUE_TYPE_CODE][order(-N)])
message("-- statistical bases --")
print(merge(out[, .N, by = STATISTICAL_BASE_CODE],
            ref_sb[, .(STATISTICAL_BASE_CODE, STATISTICAL_BASE_LONG_DESC)],
            by = "STATISTICAL_BASE_CODE", all.x = TRUE)[order(-N)])
message("-- reporting period (NMBR_OF_REPORT) --")
print(out[, .N, by = NMBR_OF_REPORT][order(suppressWarnings(as.integer(NMBR_OF_REPORT)))])
# Counted on the WRITTEN rows (after the STEP 4 collapse), not on n_multimonth.
mm_out <- out[suppressWarnings(as.integer(NMBR_OF_REPORT)) > 1L]
if (!RESTRICT_MONTHLY_ONLY && nrow(mm_out) > 0L)
  message("  NOTE: ", format(nrow(mm_out), big.mark = ","), " rows cover >1 month, across ",
          uniqueN(mm_out$EXTERNAL_PERMIT_NMBR), " permits / ",
          uniqueN(mm_out[, paste(EXTERNAL_PERMIT_NMBR, PERM_FEATURE_NMBR)]),
          " outfalls. A quarterly row sits in one",
          "\n        month but represents three -- weight by NMBR_OF_REPORT before summing loads,",
          "\n        and use per-reporting-opportunity rates, not per-month counts (ASSUMPTION 5).")

message("\n-- measurement completeness --")
message("Rows with a reported value   : ", format(sum(reported), big.mark = ","),
        sprintf(" (%.1f%%)", 100 * sum(reported) / nrow(out)))
message("Rows with a numeric limit    : ", format(sum(limited), big.mark = ","),
        sprintf(" (%.1f%%)", 100 * sum(limited) / nrow(out)),
        "   (the rest are monitor-only: reporting required, no cap)")
# Checked on the INTERNAL copy of LIMIT_VALUE_QUALIFIER_CODE (the LIMIT's
# operator -- not DMR_VALUE_QUALIFIER_CODE, which is the reported value's and
# where '<' means non-detect). A floor ('>=') would invert the exceedance test,
# so it is reported here even though the column is not carried (ASSUMPTION 7).
qual_tab <- d[LIMIT_VALUE_STANDARD_UNITS != "", .N, by = LIMIT_VALUE_QUALIFIER_CODE][order(-N)]
n_floor  <- d[LIMIT_VALUE_STANDARD_UNITS != "" &
              LIMIT_VALUE_QUALIFIER_CODE %in% c(">", ">="), .N]
message("Limit direction (LIMIT_VALUE_QUALIFIER_CODE, checked but not carried):")
print(qual_tab)
message("  rows with a FLOOR limit ('>' / '>=') : ", n_floor,
        if (n_floor == 0L) "   -> exceedance = reported > limit is safe"
        else "   -> WARNING: the exceedance test inverts for these (ASSUMPTION 7)")

message("\n-- data quality, reported not corrected (ASSUMPTION 9) --")
message("Censored rows ('<' / '<='), value is a detection limit : ",
        format(sum(out$DMR_VALUE_QUALIFIER_CODE %in% c("<", "<=")), big.mark = ","))
message("NEGATIVE reported values (physically impossible)       : ",
        format(sum(reported & num(out$DMR_VALUE_STANDARD_UNITS) < 0, na.rm = TRUE), big.mark = ","))
message("Blank on BOTH value and NODI code (unexplained)        : ",
        format(sum(!reported & out$NODI_CODE == ""), big.mark = ","))
message("EXCEEDENCE_PCT sentinel rows (>= 99999)                : ",
        format(sum(num(out$EXCEEDENCE_PCT) >= 99999, na.rm = TRUE), big.mark = ","),
        "   (ASSUMPTION 8: filter before averaging)")
message("\n-- compliance (collapsed rows hold ';'-joined values) --")
for (v in VIOLATION_COLS) {
  message(v, " -- rows non-blank: ", format(sum(out[[v]] != ""), big.mark = ","))
  if (v == "VIOLATION_CODE") print(out[VIOLATION_CODE != "", .N, by = VIOLATION_CODE][order(-N)])
}
message("\nWritten to : ", OUTPUT_PATH)
