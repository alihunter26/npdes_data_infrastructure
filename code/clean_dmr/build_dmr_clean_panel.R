# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, PROC_DIR, RAW_DIR, ...)
# Walks up from THIS FILE's location, not getwd(), so the script runs from any
# working directory. The old getwd() form ended at "/" and failed with the
# cryptic: cannot open file '//_paths.R'.
source(local({
  this <- NULL
  m <- grep("^--file=", commandArgs(FALSE), value = TRUE)            # Rscript
  if (length(m)) this <- sub("^--file=", "", m[[1]])
  if (is.null(this))                                                 # source() / RStudio Source
    for (i in rev(seq_len(sys.nframe()))) {
      of <- get0("ofile", envir = sys.frame(i), inherits = FALSE)
      if (is.character(of) && length(of) == 1L && nzchar(of)) { this <- of; break }
    }
  d <- if (is.null(this)) normalizePath(getwd(), mustWork = FALSE)    # console: last resort
       else dirname(normalizePath(this, mustWork = FALSE))
  while (!file.exists(file.path(d, "_paths.R")) && dirname(d) != d) d <- dirname(d)
  if (!file.exists(file.path(d, "_paths.R")))
    stop("Could not find _paths.R above ", if (is.null(this)) getwd() else this,
         " -- run this script from inside the CWA repo.", call. = FALSE)
  file.path(d, "_paths.R")
}))
source(file.path(CWA_ROOT, "code/02_cleaning/cleaning_helpers.R"))   # rd(), build_facility_crosswalk(), build_major_individual_permits()

# ==============================================================================
# build_dmr_clean_panel.R
# ------------------------------------------------------------------------------
# Build a CLEANED DMR panel carrying only the variables we concluded are worth
# keeping, restricted to major individual permits / TSS / Effluent Gross /
# external outfalls / monthly-average measurements / the continental US.
#
# Reads the RAW per-fiscal-year DMR zips directly and writes one cleaned file
# per fiscal year. YEARS says which years to build -- one, several, or "all".
#
# Everything that is a judgment call is a TOGGLE in the CONFIG block below --
# which years, whether to keep non-monthly reporting periods, which value types
# and statistical bases, which violation fields to carry, whether to restrict to
# the continental US, and whether to attach FACILITY_ID and the NODI text.
# Change the toggle, re-run, and the run log reports what each choice cost.
#
#   Input  : data/raw/DMR/npdes_dmrs_fy<FY>.zip        (FY >= 2009)
#            data/raw/DMR/npdes_dmrs_prefy2009.zip     (FY <= 2008, many FYs)
#            data/raw/npdes_downloads/ICIS_PERMITS.csv    (permit population)
#            data/raw/npdes_downloads/ICIS_FACILITIES.csv (FACILITY_ID, STATE_CODE)
#            data/raw/reference/REF_STATISTICAL_BASE.csv  (monthly-average bases)
#            data/raw/reference/REF_NODI.csv              (NODI descriptions)
#   Output : data/processed/clean_dmr_<FY>.csv, one per fiscal year built. The
#            <FY> in the name is always read off the rows' own
#            MONITORING_PERIOD_END_DATEs, never from a toggle.
#
# ------------------------------------------------------------------------------
# LABELED ASSUMPTIONS -- one line each. THE FULL TEXT, with the reasoning, the
# measured counts and the rejected alternatives, is in build_dmr_clean_panel.md
# under "Decisions and Assumptions", which is the authoritative version. Read it
# before using results; these lines are reminders, not the argument.
#
#   1. The script applies the whole restriction itself, from raw -- population
#      (shared rule), TSS, Effluent Gross, EXO, statistical base, value type,
#      continental US. Equivalence to the old pipeline route is a CHECK TO RUN.
#   2. Both '1' and 'EG' are Effluent Gross; '1' alone would drop 1,101 FY2017
#      rows and two permits entirely.
#   3. "Outfall" means EXO, and outfall identity is the PAIR
#      (permit, PERM_FEATURE_NMBR) -- never the number alone. Key on both.
#   4. Monthly average = every base EPA flags 'A' in REF_STATISTICAL_BASE.csv
#      (12 codes, incl. DB and the 30-day codes), not just 'MK'.
#   5. Statistical base is the STATISTIC; NMBR_OF_REPORT is how many MONTHS the
#      row covers. Multi-month rows are kept -- weight by it before summing.
#   6. One row per ROW_KEY, asserted. Multiple limit sets kept, never
#      tie-broken; violation fan-out collapsed with ';'; two LIMIT_IDs in one
#      cell both kept and flagged FLAG_MULTI_LIMIT_ID. VERSION_NMBR unused.
#   7. Values are copied verbatim as character; compare *_STANDARD_UNITS, never
#      the permit-specific *_NMBR fields.
#   8. EXCEEDENCE_PCT carries a >= 99999 sentinel (5 FY2017 rows) -- filter it
#      before averaging.
#   9. Nothing is corrected, only reported: negatives, censored '<' rows and
#      rows blank on both value and NODI pass through, counted in the run log.
#  10. One pass per source zip; requested years are batched by source so each
#      zip is read once. Nothing in data/raw/ is ever written or deleted.
#  11. Continental US = the 48 states + DC (F_STATES), by FACILITY location
#      joined from ICIS -- NOT the NPDES_ID prefix, which is the issuing
#      authority. An allowlist; everything outside it is dropped and counted.
#  12. NODI_DESC is EPA's own text, readability only; NODI_CODE stays the key.
#      An undocumented code stops that year. EPA_CODE_STATUS not carried.
#  13. prefy2009.zip holds FY1986-FY2008 in one member. Early years are thin and
#      the population/geography rules are anachronistic -- not comparable across
#      the FY2009 boundary. A year that filters to zero rows is a SKIP.
#  14. A fiscal year must come from exactly one source zip, asserted; a per-FY
#      zip is held to its own year and stray rows are dropped as out-of-window.
#
# Deterministic (no stochastic steps); read-only with respect to data/raw/;
# non-destructive (writes NEW files); safe to re-run.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(DBI)
  library(duckdb)
})

# ---- CONFIG validation -------------------------------------------------------
# Fails on a malformed toggle here rather than surfacing later as an empty
# filter or a generic "no rows survived".
validate_config <- function() {
  # YEARS: "all", or a vector of plausible fiscal years.
  if (!(identical(YEARS, "all") ||
        (is.numeric(YEARS) && length(YEARS) > 0L && !anyNA(YEARS) &&
         all(YEARS == as.integer(YEARS)))))
    stop('YEARS must be "all" or a numeric vector of fiscal years, ',
         'e.g. 2017L, c(2017L, 2019L) or 2009:2012.')
  if (!identical(YEARS, "all")) {
    yr <- as.integer(YEARS)
    if (any(yr < FY_FLOOR | yr > FY_CEILING))
      stop("YEARS holds a fiscal year outside ", FY_FLOOR, "-", FY_CEILING, ": ",
           paste(sort(unique(yr[yr < FY_FLOOR | yr > FY_CEILING])), collapse = ", "),
           '\n  (The DMR downloads cover FY1986-FY2025; use "all" for everything available.)')
    if (anyDuplicated(yr))
      stop("YEARS repeats a fiscal year: ",
           paste(unique(yr[duplicated(yr)]), collapse = ", "))
  }
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
  for (nm in c("RESTRICT_MONTHLY_ONLY", "ADD_FACILITY_ID",
               "RESTRICT_CONTINENTAL", "ADD_NODI_DESC", "KEEP_GZ", "REUSE_GZ")) {
    v <- get(nm)
    if (!is.logical(v) || length(v) != 1L || is.na(v))
      stop(nm, " must be a single TRUE or FALSE, got: ", deparse(v))
  }
  # ASSUMPTION 11: the state allowlist is the whole definition of "continental",
  # so a typo in it is a silent change of population, not a syntax error.
  if (!is.character(F_STATES) || length(F_STATES) == 0L || anyNA(F_STATES))
    stop("F_STATES must be a non-empty character vector of 2-letter state codes.")
  if (any(nchar(F_STATES) != 2L) || any(F_STATES != toupper(F_STATES)))
    stop("F_STATES must hold upper-case 2-character codes; got: ",
         paste(F_STATES[nchar(F_STATES) != 2L | F_STATES != toupper(F_STATES)],
               collapse = ", "))
  if (anyDuplicated(F_STATES))
    stop("F_STATES repeats a code: ",
         paste(unique(F_STATES[duplicated(F_STATES)]), collapse = ", "))
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

## WHICH YEARS -----------------------------------------------------------------
# "all"              -> every DMR zip present in data/raw/DMR/, which means
#                       prefy2009 (FY1986-FY2008, ASSUMPTION 13) plus FY2009-2025
# 2017L              -> one fiscal year
# c(2017L, 2019L)    -> several
# 2009:2012          -> a range
# Overridable from the command line, so a batch needs no file edit:
#   Rscript code/clean_dmr/build_dmr_clean_panel.R 2017
#   Rscript code/clean_dmr/build_dmr_clean_panel.R all
# A year that cannot be built (unreadable zip, or no rows after filtering) is
# REPORTED AND SKIPPED, and the others still run; the script exits non-zero if
# anything was skipped, so a wrapper notices (ASSUMPTION 10, 13).
#
# Defaults to ONE year, not "all", so running the script by accident costs a
# minute instead of a night. Set YEARS <- "all" (or pass `all`) when you mean it.
YEARS <- 2017L

# Sanity bounds for the YEARS toggle -- not a filter on the data, just a guard
# against a typo like 217 or 20177 silently matching no zip.
FY_FLOOR   <- 1986L
FY_CEILING <- 2025L

# Where the cleaned files go. The year in each name is read off that year's own
# MONITORING_PERIOD_END_DATEs, so a filename cannot misreport its contents.
OUTPUT_DIR      <- PROC_DIR
OUTPUT_NAME_FMT <- "clean_dmr_%d.csv"

## Engine (the raw members are 3.7-22 GB; this machine has 8 GB of RAM) --------
# DuckDB streams the raw CSV out-of-core and spills to disk. Only the permit +
# TSS filter runs there; what returns to R is small (~160k rows for a normal
# year), and every other filter runs in R exactly as it always has.
# 8 GB of RAM total, and R holds the returned rows on top of whatever DuckDB
# takes, so DuckDB cannot be given most of the machine. At 5GB the OS killed
# the process outright (SIGKILL -- no R error, the shell prompt just returns).
# 2GB makes DuckDB spill to DUCK_TMP instead of growing: slower, but it finishes.
DUCKDB_MEM_LIMIT <- "2GB"
# DuckDB defaults to one thread per core (8 here) and each CSV-reader thread
# holds its own buffers, which is the real peak-memory multiplier. Capping at 2
# costs some speed and removes most of the spike.
DUCKDB_THREADS   <- 2L
# Scratch for the gzip temp and DuckDB's spill. CWA_SCRATCH if set, else the
# session temp dir -- same convention as code/dmr/filter_dmr_major_individual.R.
# The default lands on whatever volume holds the session temp dir, which on a
# nearly-full disk is the wrong place: the gzip temp and DuckDB's spill both go
# here. Point CWA_SCRATCH at a roomy volume (an external drive is fine):
#   export CWA_SCRATCH=/Users/you/cwa_scratch
# No absolute default is hardcoded -- this repo is meant to run unchanged on any
# machine (see _paths.R), so the path stays an environment choice.
SCRATCH_ROOT <- Sys.getenv("CWA_SCRATCH", file.path(tempdir(), "cwa_clean_dmr"))

# Free space on the scratch volume, checked before any extraction. Below WARN we
# say so and continue (a single recent year needs only a few GB); below ABORT
# nothing can finish, so we stop before spending hours to die mid-write.
SCRATCH_WARN_FREE_GB  <- 30
SCRATCH_ABORT_FREE_GB <- 5
REUSE_GZ <- TRUE    # reuse an existing gzip temp for a source instead of re-extracting
KEEP_GZ  <- FALSE   # TRUE keeps each gzip temp (faster re-runs, ~0.5-1.3 GB each)

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

# Keep only facilities in the continental US -- the 48 states + DC listed in
# F_STATES below (ASSUMPTION 11). The state is NOT in the DMR file; it is joined
# from raw ICIS_FACILITIES.csv and written to the output as STATE_CODE.
# TRUE  -> (default) 48 states + DC, matching the facility-month panel built by
#          code/03_panel_building/01_build_facility_month_panel_major_individual.R.
#          In FY2017 it costs 2,504 rows / 111 permits (PR, AK, HI, VI, AS, GU, MP).
# FALSE -> every state and territory; no ICIS state read, no STATE_CODE column.
RESTRICT_CONTINENTAL <- TRUE

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

# Carry EPA's own text for NODI_CODE as NODI_DESC, immediately beside the code
# (ASSUMPTION 12). Readability only -- no logic in this script or downstream
# reads the description, and a blank code keeps a blank description.
ADD_NODI_DESC    <- TRUE

## Fixed scope (change only with a reason) -------------------------------------
F_PARAM     <- "00530"        # TSS
F_MONLOC    <- c("1", "EG")   # both = Effluent Gross (ASSUMPTION 2)
F_FEATURE   <- "EXO"          # external outfall      (ASSUMPTION 3)
# Monthly average = every code EPA flags as one (ASSUMPTION 4).
STAT_BASE_REF <- file.path(RAW_ROOT, "reference", "REF_STATISTICAL_BASE.csv")
# EPA's NODI code -> description table (ASSUMPTION 12).
NODI_REF      <- file.path(RAW_ROOT, "reference", "REF_NODI.csv")

# The continental US, as an ALLOWLIST (ASSUMPTION 11): the 48 contiguous states
# plus DC. DC is included to match the facility-month panel's own filter in
# code/03_panel_building/01_build_facility_month_panel_major_individual.R, so
# the two files cover the same geography. Dropping DC here would leave DC
# facilities in that panel with no DMR rows, indistinguishable from genuine
# non-reporting. Excluded by construction: AK, HI, PR, VI, GU, AS, MP, every
# non-state ICIS code (XX, MB, MW, UM, GM, GE, ...) and a blank state.
F_STATES <- c("AL", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "ID",
              "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD", "MA", "MI",
              "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY",
              "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN",
              "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY", "DC")

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
# `period_end` is the parsed Date driving the fiscal-year split, de-duplication,
# row ordering and the run log. The output already states the date twice --
# MONITORING_PERIOD_END_DATE verbatim as EPA wrote it (ASSUMPTION 7) and
# YEAR/MONTH for joining -- and a third, re-formatted copy is how two date
# columns start disagreeing downstream.
INTERNAL_DERIVED <- "period_end"

# ==============================================================================
# ---- END CONFIG -------------------------------------------------------------
# ==============================================================================

# Command-line override of YEARS (see the YEARS comment above).
local({
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) == 0L) return(invisible(NULL))
  if (length(args) == 1L && tolower(args[1]) == "all") {
    YEARS <<- "all"; return(invisible(NULL))
  }
  yr <- suppressWarnings(as.integer(args))
  if (anyNA(yr))
    stop("Unparseable YEARS argument(s): ", paste(args[is.na(yr)], collapse = ", "),
         '\n  Usage: Rscript build_dmr_clean_panel.R [all | <FY> [<FY> ...]]')
  YEARS <<- yr
})

validate_config()

# ==============================================================================
# STEP 0: resolve YEARS -> source zips, and pre-flight them (ASSUMPTION 10)
# ==============================================================================
# A source is one zip. FY >= 2009 has its own; FY <= 2008 all live in the single
# prefy2009 member (ASSUMPTION 13). `nominal_fy` is NA for prefy2009, which is
# the only source allowed to emit more than one year (ASSUMPTION 14).
PREFY_FIRST <- 2009L   # first fiscal year with its own zip

fy_source <- function(fy) {
  if (fy >= PREFY_FIRST)
    list(key = sprintf("fy%d", fy),
         zip = file.path(DMR_DIR, sprintf("npdes_dmrs_fy%d.zip", fy)),
         member = sprintf("NPDES_DMRS_FY%d.csv", fy),
         nominal_fy = as.integer(fy))
  else
    list(key = "prefy2009",
         zip = file.path(DMR_DIR, "npdes_dmrs_prefy2009.zip"),
         member = "NPDES_DMRS_PREFY2009.csv",
         nominal_fy = NA_integer_)
}

# Which sources to process, and which years to accept out of each.
if (identical(YEARS, "all")) {
  # Everything on disk, rather than a hardcoded year list: a newly downloaded
  # FY2026 zip is picked up without editing the script.
  zips <- sort(list.files(DMR_DIR, pattern = "^npdes_dmrs_(fy[0-9]{4}|prefy2009)\\.zip$",
                          full.names = TRUE))
  if (!length(zips))
    stop("No DMR zips found in ", DMR_DIR,
         "\n  Expected npdes_dmrs_fy<FY>.zip / npdes_dmrs_prefy2009.zip",
         "\n  (download with code/01_data_download/01_download_echo_bulk_files.R)")
  SOURCES <- lapply(zips, function(z) {
    if (grepl("prefy2009", z))
      list(key = "prefy2009", zip = z, member = "NPDES_DMRS_PREFY2009.csv",
           nominal_fy = NA_integer_, want = NULL)          # NULL = accept every FY found
    else {
      fy <- as.integer(sub(".*npdes_dmrs_fy([0-9]{4})\\.zip$", "\\1", z))
      s <- fy_source(fy); s$want <- fy; s
    }
  })
  REQUESTED_FYS <- NULL   # not knowable up front: prefy2009's years come from the data
} else {
  yr <- sort(unique(as.integer(YEARS)))
  srcs <- lapply(yr, fy_source)
  keys <- vapply(srcs, `[[`, character(1), "key")
  SOURCES <- lapply(unique(keys), function(k) {
    i <- which(keys == k)[1]
    s <- srcs[[i]]
    s$want <- yr[keys == k]        # several pre-2009 years share one source: read it ONCE
    s
  })
  REQUESTED_FYS <- yr
}

# ---- Pre-flight: is each zip there, and readable? ----------------------------
# `unzip -l` costs milliseconds and catches a truncated download (a missing
# end-of-central-directory record) before hours of work. Unreadable sources are
# reported and SKIPPED; the rest still run.
zip_problem <- function(path) {
  if (!file.exists(path)) return("missing")
  st <- suppressWarnings(system2("unzip", c("-l", shQuote(path)),
                                 stdout = FALSE, stderr = FALSE))
  if (!identical(as.integer(st), 0L))
    return("unreadable (truncated download: no end-of-central-directory record)")
  NA_character_
}

message("=== build_dmr_clean_panel ===")
message("YEARS requested : ",
        if (identical(YEARS, "all")) "all" else paste(REQUESTED_FYS, collapse = ", "))
message("Sources         : ", length(SOURCES), " zip(s) in ", DMR_DIR)

for (i in seq_along(SOURCES)) SOURCES[[i]]$problem <- zip_problem(SOURCES[[i]]$zip)
bad_src <- vapply(SOURCES, function(s) !is.na(s$problem), logical(1))
if (any(bad_src)) {
  message("\n!! ", sum(bad_src), " source(s) unusable -- skipped, the rest still run:")
  for (s in SOURCES[bad_src])
    message("     ", basename(s$zip), " : ", s$problem)
  message("   Re-download with code/01_data_download/01_download_echo_bulk_files.R",
          "\n   (its DMR URLs are an INFERRED pattern and it only logs a failure,",
          "\n    which is how a truncated zip gets left on disk unnoticed).")
}

# Shared scratch, created once.
DUCK_TMP <- file.path(SCRATCH_ROOT, "duckdb_spill")
dir.create(SCRATCH_ROOT, showWarnings = FALSE, recursive = TRUE)
dir.create(DUCK_TMP,     showWarnings = FALSE, recursive = TRUE)
if (!dir.exists(SCRATCH_ROOT))
  stop("Could not create scratch dir: ", SCRATCH_ROOT,
       "\n  Set CWA_SCRATCH to a writable location.", call. = FALSE)

# ---- Pre-flight: room on the scratch volume ----------------------------------
# A full scratch volume is the other way a long run dies with nothing to show:
# the extraction or DuckDB's spill fails after the expensive part. `df -Pk` is
# POSIX and needs no package; available blocks are field 4.
scratch_free_gb <- function(path) {
  out <- suppressWarnings(system2("df", c("-Pk", shQuote(path)),
                                  stdout = TRUE, stderr = FALSE))
  if (!length(out) || length(out) < 2L) return(NA_real_)
  f <- strsplit(trimws(out[[length(out)]]), "[[:space:]]+")[[1]]
  if (length(f) < 4L) return(NA_real_)
  suppressWarnings(as.numeric(f[[4]]) * 1024 / 1e9)
}

SCRATCH_FREE_GB <- scratch_free_gb(SCRATCH_ROOT)
message("Scratch         : ", SCRATCH_ROOT,
        if (is.na(SCRATCH_FREE_GB)) " (free space unknown)"
        else sprintf(" (%.0f GB free)", SCRATCH_FREE_GB))
# Cap DuckDB's spill by what the volume actually has, leaving 3 GB of headroom
# for the gzip temp and anything else sharing the disk; never more than 20 GB.
DUCKDB_SPILL_CAP_GB <- if (is.na(SCRATCH_FREE_GB)) 20L else
  max(2L, min(20L, as.integer(floor(SCRATCH_FREE_GB - 3))))

if (!is.na(SCRATCH_FREE_GB)) {
  if (SCRATCH_FREE_GB < SCRATCH_ABORT_FREE_GB) {
    stop(sprintf(paste0("only %.1f GB free on the scratch volume (need at least ",
                        "%d GB).\n  Point CWA_SCRATCH at a roomier volume:",
                        "\n    export CWA_SCRATCH=/path/with/space"),
                 SCRATCH_FREE_GB, SCRATCH_ABORT_FREE_GB), call. = FALSE)
  } else if (SCRATCH_FREE_GB < SCRATCH_WARN_FREE_GB) {
    message(sprintf(paste0("   !! only %.0f GB free; a single recent year should fit, ",
                           "but the\n      largest members (up to 22 GB uncompressed) ",
                           "may not. If this run\n      dies during extraction or ",
                           "spill, set CWA_SCRATCH to a roomier volume."),
                    SCRATCH_FREE_GB))
  }
}

# ==============================================================================
# STEP 1: reference data, loaded ONCE for every year
# ==============================================================================
# These were per-run reads when the script built one year at a time. Loading
# them once here is what makes a 40-year batch affordable: ICIS_FACILITIES.csv
# alone is 190 MB and would otherwise be read twice per year.
message("\nLoading reference data (once for all years) ...")

# ASSUMPTION 1: the shared population rule, not a copy of it.
ELIGIBLE_PERMITS <- build_major_individual_permits(raw_dir = RAW_DIR)

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

# ASSUMPTION 12: EPA's NODI text.
nodi <- NULL
if (ADD_NODI_DESC) {
  if (!file.exists(NODI_REF))
    stop("NODI reference table not found: ", NODI_REF,
         "\n  It is not in the bulk downloads; see data/raw/reference/README.md.")
  nodi <- fread(NODI_REF, colClasses = "character", showProgress = FALSE)
  if (!all(c("NODI_CODE", "NODI_DESC") %in% names(nodi)))
    stop(basename(NODI_REF), " lacks NODI_CODE / NODI_DESC.")
  nodi[, NODI_CODE := trimws(NODI_CODE)]
  nodi[, NODI_DESC := trimws(NODI_DESC)]
  if (anyDuplicated(nodi, by = "NODI_CODE"))
    stop(basename(NODI_REF), " repeats a NODI_CODE, so the description is ambiguous.")
}

# ASSUMPTION 11: facility location, for the continental-US filter.
state_tab <- NULL
if (RESTRICT_CONTINENTAL) {
  # A separate, minimal read rather than extending build_facility_crosswalk():
  # that helper is shared by scripts 02/04/05/06 and documented as returning
  # exactly (NPDES_ID, facility_id). Re-implementing its FACILITY_UIN fallback
  # here to save one read would duplicate the rule in two places.
  state_tab <- rd("ICIS_FACILITIES.csv", c("NPDES_ID", "STATE_CODE"), raw_dir = RAW_DIR)
  state_tab[, NPDES_ID   := trimws(NPDES_ID)]
  state_tab[, STATE_CODE := trimws(STATE_CODE)]
  state_tab <- unique(state_tab[NPDES_ID != ""])
  # unique() above collapses identical repeats, but a permit listed under TWO
  # different states would survive it and silently multiply rows in the join.
  if (uniqueN(state_tab, by = "NPDES_ID") != nrow(state_tab))
    stop("ICIS_FACILITIES.csv gives one NPDES_ID more than one STATE_CODE, so the ",
         "state join would multiply DMR rows.",
         "\n  Inspect state_tab[, .N, by = NPDES_ID][N > 1].")
}

# FACILITY_ID crosswalk.
xwalk <- if (ADD_FACILITY_ID) build_facility_crosswalk(raw_dir = RAW_DIR) else NULL

# Federal fiscal year of a period-end date: Oct-Dec belong to the NEXT calendar
# year's FY. This is what names every output file (ASSUMPTION 13/14).
fy_of <- function(x) year(x) + (month(x) >= 10L)

# ==============================================================================
# STEP 2: per source -- extract the member, then filter it in DuckDB
# ==============================================================================
# Returns a data.table of population + TSS rows for the whole member, with every
# column character and trimmed. Every other filter runs in R, per fiscal year,
# in process_fy() below -- same order and same counts as before (ASSUMPTION 1).
read_source <- function(src) {
  gz <- file.path(SCRATCH_ROOT, paste0(src$key, ".csv.gz"))

  if (REUSE_GZ && file.exists(gz) && file.info(gz)$size > 0) {
    message("  reusing gzip temp: ", basename(gz),
            " (", round(file.info(gz)$size / 1e9, 2), " GB)")
  } else {
    message("  extracting ", src$member, " -> ", basename(gz), " ...")
    t0 <- Sys.time()
    # pipefail so a tar failure is not masked by gzip's exit status.
    cmd <- sprintf("set -o pipefail; tar -xOf %s %s | gzip -1 > %s",
                   shQuote(src$zip), shQuote(src$member), shQuote(gz))
    status <- system2("bash", c("-c", shQuote(cmd)))
    if (!identical(as.integer(status), 0L)) {
      unlink(gz)
      stop("extract failed (exit ", status, ") for member ", src$member,
           " in ", basename(src$zip))
    }
    message("    done in ", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1),
            " min; ", round(file.info(gz)$size / 1e9, 2), " GB gz")
  }

  con <- dbConnect(duckdb::duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
  dbExecute(con, sprintf("SET memory_limit='%s';", DUCKDB_MEM_LIMIT))
  dbExecute(con, sprintf("SET threads=%d;", DUCKDB_THREADS))
  dbExecute(con, sprintf("SET temp_directory='%s';", DUCK_TMP))
  # Without a spill cap DuckDB can fill the scratch volume instead of erroring.
  dbExecute(con, sprintf("SET max_temp_directory_size='%dGB';", DUCKDB_SPILL_CAP_GB))
  dbExecute(con, "SET preserve_insertion_order=false;")
  dbWriteTable(con, "eligible_permits",
               data.frame(EXTERNAL_PERMIT_NMBR = ELIGIBLE_PERMITS,
                          stringsAsFactors = FALSE))

  want_cols <- unique(c(KEEP_COLS, VIOLATION_COLS, INTERNAL_COLS))
  # all_varchar: every value comes back exactly as written (ASSUMPTION 7).
  # Only the needed columns are projected -- 22 of 57.
  sql <- sprintf("
    SELECT %s
    FROM read_csv('%s', all_varchar=true, header=true, sample_size=-1) d
    WHERE trim(d.\"PARAMETER_CODE\") = '%s'
      AND trim(d.\"EXTERNAL_PERMIT_NMBR\") IN
          (SELECT \"EXTERNAL_PERMIT_NMBR\" FROM eligible_permits)",
    paste(sprintf("d.\"%s\"", want_cols), collapse = ", "), gz, F_PARAM)

  message("  DuckDB: eligible permits + PARAMETER_CODE ", F_PARAM, " ...")
  t0 <- Sys.time()
  d <- setDT(dbGetQuery(con, sql))
  message("    returned ", format(nrow(d), big.mark = ","), " rows in ",
          round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min")

  if (!KEEP_GZ && file.exists(gz)) unlink(gz)
  for (j in names(d)) d[[j]] <- trimws(d[[j]])
  d
}

# ==============================================================================
# STEP 3-7 for ONE fiscal year, on rows already restricted to population + TSS
# ==============================================================================
# Writes data/processed/clean_dmr_<fy_data>.csv and prints that year's run log.
# Returns a one-row data.table for the closing summary.
process_fy <- function(d, fy_data, src, n_src_rows) {

  OUTPUT_PATH <- file.path(OUTPUT_DIR, sprintf(OUTPUT_NAME_FMT, fy_data))
  n_in <- nrow(d)

  # ---- the scope filters, in the order the funnel reports them ---------------
  # ASSUMPTION 2: %in%, not ==, so 'EG' is kept alongside '1'.
  n_not_monloc <- sum(!d$MONITORING_LOCATION_CODE %in% F_MONLOC)
  d <- d[MONITORING_LOCATION_CODE %in% F_MONLOC]

  n_not_exo <- sum(d$PERM_FEATURE_TYPE_CODE != F_FEATURE)
  d <- d[PERM_FEATURE_TYPE_CODE == F_FEATURE]                      # ASSUMPTION 3

  n_not_avg  <- sum(!d$STATISTICAL_BASE_CODE %in% monthly_avg_codes)
  n_excl_avg <- sum(d$STATISTICAL_BASE_CODE %in% EXCLUDE_STAT_BASES)
  d <- d[STATISTICAL_BASE_CODE %in% F_STAT_BASES]                  # ASSUMPTION 4

  vt_wanted <- if (identical(VALUE_TYPES, "all")) sort(unique(d$VALUE_TYPE_CODE)) else VALUE_TYPES
  n_not_vt <- sum(!d$VALUE_TYPE_CODE %in% vt_wanted)
  d <- d[VALUE_TYPE_CODE %in% vt_wanted]

  if (nrow(d) == 0L)
    return(data.table(fy = fy_data, source = src$key, status = "skipped",
                      reason = "0 rows after the scope filters", rows = 0L))

  # ASSUMPTION 11: continental US, by FACILITY location joined from raw ICIS.
  # Done here, with the other scope filters, so the drop appears in the run
  # log's funnel and so the fan-out and FLAG_MULTI_LIMIT_ID counts below
  # describe the population actually written rather than one including
  # territories.
  n_not_cont     <- 0L
  state_drop_tab <- NULL
  if (RESTRICT_CONTINENTAL) {
    n_pre_state <- nrow(d)
    d <- state_tab[d, on = c(NPDES_ID = "EXTERNAL_PERMIT_NMBR")]
    setnames(d, "NPDES_ID", "EXTERNAL_PERMIT_NMBR")
    if (nrow(d) != n_pre_state)
      stop("The STATE_CODE join changed the row count (", n_pre_state, " -> ", nrow(d),
           "). It must only attach a column.")

    # Counted by code BEFORE dropping, so nothing leaves without a number on it.
    # A missing match and a blank state are named rather than lumped in as "other".
    state_drop_tab <- d[!STATE_CODE %in% F_STATES,
                        .(rows = .N, permits = uniqueN(EXTERNAL_PERMIT_NMBR)),
                        by = .(STATE_CODE = fifelse(is.na(STATE_CODE), "<no ICIS match>",
                                             fifelse(STATE_CODE == "", "<blank>",
                                                     STATE_CODE)))][order(-rows)]
    n_not_cont <- sum(state_drop_tab$rows)
    d <- d[STATE_CODE %in% F_STATES]
    if (nrow(d) == 0L)
      return(data.table(fy = fy_data, source = src$key, status = "skipped",
                        reason = "0 rows after the continental-US filter", rows = 0L))
  }

  # The fiscal-year window. period_end was parsed and the FY derived by the
  # caller, so every row is already inside this window -- asserted, not assumed.
  fy_start <- as.Date(sprintf("%d-10-01", fy_data - 1L))
  fy_end   <- as.Date(sprintf("%d-09-30", fy_data))
  stopifnot(all(d$period_end >= fy_start & d$period_end <= fy_end))

  # ----------------------------------------------------------------------------
  # STEP 3: reporting period (ASSUMPTION 5)
  # ----------------------------------------------------------------------------
  d[, nmbr_report_i := suppressWarnings(as.integer(NMBR_OF_REPORT))]
  n_multimonth <- sum(d$nmbr_report_i > 1L, na.rm = TRUE)

  if (RESTRICT_MONTHLY_ONLY) {
    p_before <- uniqueN(d$EXTERNAL_PERMIT_NMBR)
    o_before <- uniqueN(paste(d$EXTERNAL_PERMIT_NMBR, d$PERM_FEATURE_NMBR))
    d <- d[nmbr_report_i == 1L]
    lost_permits  <- p_before - uniqueN(d$EXTERNAL_PERMIT_NMBR)
    lost_outfalls <- o_before - uniqueN(paste(d$EXTERNAL_PERMIT_NMBR, d$PERM_FEATURE_NMBR))
    if (nrow(d) == 0L)
      return(data.table(fy = fy_data, source = src$key, status = "skipped",
                        reason = "0 rows after RESTRICT_MONTHLY_ONLY", rows = 0L))
  } else {
    lost_permits <- lost_outfalls <- 0L
  }

  # ----------------------------------------------------------------------------
  # STEP 4: one row per ROW_KEY (ASSUMPTION 6)
  # ----------------------------------------------------------------------------
  n_pre_collapse <- nrow(d)

  # 4a. Violation fan-out (ASSUMPTION 6a). Rows sharing a key must agree on every
  #     column outside VIOLATION_COLS -- otherwise collapsing would discard a
  #     value, so stop instead. Then join each VIOLATION_COLS field with ';' in
  #     one common row order, so the k-th entry of every joined field comes from
  #     the same source row.
  non_viol <- setdiff(names(d), VIOLATION_COLS)
  if (uniqueN(d, by = non_viol) != uniqueN(d, by = ROW_KEY))
    stop("FY", fy_data, ": rows sharing a ROW_KEY differ outside VIOLATION_COLS, so ",
         "collapsing them would lose data.",
         "\n  Inspect d[, .N, by = ROW_KEY][N > 1] and extend ROW_KEY.")
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

  # ----------------------------------------------------------------------------
  # STEP 5: derived keys, then trim to the requested columns
  # ----------------------------------------------------------------------------
  n_unrouted <- NA_integer_
  n_pre_join <- nrow(d)
  if (ADD_FACILITY_ID) {
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

  # ASSUMPTION 12: EPA's own NODI text beside the code. Readability only.
  if (ADD_NODI_DESC) {
    # An undocumented code stops this year rather than being written with a
    # blank description, which would read as "no NODI reported" (same rule as
    # code/03_panel_building/07_add_dmr.R).
    unknown_nodi <- setdiff(unique(d[NODI_CODE != "", NODI_CODE]), nodi$NODI_CODE)
    if (length(unknown_nodi))
      stop("FY", fy_data, " holds NODI code(s) absent from ", basename(NODI_REF), ": ",
           paste(sort(unknown_nodi), collapse = ", "),
           "\n  Refusing to write a blank description for a code EPA documents.",
           "\n  Re-transcribe the reference table (see REF_NODI_PROVENANCE.md).")

    d[nodi, on = "NODI_CODE", NODI_DESC := i.NODI_DESC]
    d[NODI_CODE == "", NODI_DESC := ""]      # blank code -> blank text, not NA
    # Description present exactly where a code is, and nowhere else.
    stopifnot(!anyNA(d$NODI_DESC), all(nzchar(d$NODI_DESC) == nzchar(d$NODI_CODE)))
  }

  # INTERNAL_DERIVED rides along here and is dropped at write time in STEP 6.
  rest_cols <- setdiff(KEEP_COLS, c("EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_NMBR"))
  rest_cols <- append(rest_cols, VIOLATION_COLS, after = match("EXCEEDENCE_PCT", rest_cols))
  # NODI_DESC sits immediately right of the code it explains (ASSUMPTION 12).
  if (ADD_NODI_DESC)
    rest_cols <- append(rest_cols, "NODI_DESC", after = match("NODI_CODE", rest_cols))
  out_cols <- c(if (ADD_FACILITY_ID) "FACILITY_ID",
                "EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_NMBR",
                if (RESTRICT_CONTINENTAL) "STATE_CODE",
                INTERNAL_DERIVED, "YEAR", "MONTH",
                rest_cols, "FLAG_MULTI_LIMIT_ID")
  out <- d[, ..out_cols]

  # Row order: facility, then time, then the full row key. Facility first because
  # the file is read and merged facility-by-facility; period_end breaks ties
  # within a YEAR x MONTH (a month can hold more than one period-end day); the
  # remaining key parts make the order TOTAL, so the same input always writes
  # byte-identical rows in the same sequence.
  SORT_KEY <- c(if (ADD_FACILITY_ID) "FACILITY_ID" else "EXTERNAL_PERMIT_NMBR",
                "YEAR", "MONTH", "period_end",
                "EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_NMBR", "VALUE_TYPE_CODE",
                "STATISTICAL_BASE_CODE", "MONITORING_LOCATION_CODE",
                "LIMIT_SET_DESIGNATOR", "LIMIT_SET_ID", "LIMIT_ID")
  setorderv(out, SORT_KEY)

  # ----------------------------------------------------------------------------
  # STEP 6: verify, then write
  # ----------------------------------------------------------------------------
  # One row per ROW_KEY (ASSUMPTION 6). The facility join must not have added rows.
  stopifnot(!anyDuplicated(out, by = ROW_KEY))
  stopifnot(nrow(out) == n_pre_join)
  stopifnot(all(KEEP_COLS %in% names(out)), all(VIOLATION_COLS %in% names(out)))
  stopifnot(all(out$PERM_FEATURE_TYPE_CODE == F_FEATURE),
            all(out$PARAMETER_CODE == F_PARAM),
            all(out$MONITORING_LOCATION_CODE %in% F_MONLOC),
            all(out$STATISTICAL_BASE_CODE %in% F_STAT_BASES),
            all(out$VALUE_TYPE_CODE %in% vt_wanted))
  # ASSUMPTION 1: the population filter really was applied.
  stopifnot(all(out$EXTERNAL_PERMIT_NMBR %in% ELIGIBLE_PERMITS))
  # ASSUMPTION 14: this file holds exactly the fiscal year its name claims.
  stopifnot(all(fy_of(out$period_end) == fy_data))
  if (RESTRICT_MONTHLY_ONLY) stopifnot(all(out$NMBR_OF_REPORT == "1"))
  # ASSUMPTION 11: nothing outside the allowlist, and the column is actually there
  # to prove it.
  if (RESTRICT_CONTINENTAL)
    stopifnot("STATE_CODE" %in% names(out), !anyNA(out$STATE_CODE),
              all(out$STATE_CODE %in% F_STATES))
  # ASSUMPTION 12: a description exactly where there is a code, and EPA's own text.
  if (ADD_NODI_DESC)
    stopifnot("NODI_DESC" %in% names(out), !anyNA(out$NODI_DESC),
              all(nzchar(out$NODI_DESC) == nzchar(out$NODI_CODE)),
              nrow(out[NODI_CODE != ""][!nodi, on = c("NODI_CODE", "NODI_DESC")]) == 0L)
  # The written order is part of what this file promises, so it is asserted, not
  # assumed: re-sorting a copy must not move a single row.
  stopifnot(identical(out, setorderv(copy(out), SORT_KEY)))

  # Everything above checked and ordered itself on `period_end`; it leaves here.
  written_cols <- setdiff(names(out), INTERNAL_DERIVED)
  stopifnot(!any(c("period_end", "outfall_uid", "facility_id") %in% written_cols))
  fwrite(out[, ..written_cols], OUTPUT_PATH)

  # ----------------------------------------------------------------------------
  # STEP 7: run log (sanity checks)
  # ----------------------------------------------------------------------------
  per_cell <- out[, .N, by = c("EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_NMBR",
                               "period_end", "VALUE_TYPE_CODE")]
  num <- function(x) suppressWarnings(as.numeric(x))
  reported <- out$DMR_VALUE_STANDARD_UNITS != ""
  limited  <- out$LIMIT_VALUE_STANDARD_UNITS != ""

  message("\n=== build_dmr_clean_panel: FY", fy_data, " ===")
  message("Source                       : ", basename(src$zip),
          "  (member ", src$member, ")")
  message("Toggles                      : RESTRICT_MONTHLY_ONLY=", RESTRICT_MONTHLY_ONLY,
          " | VALUE_TYPES=", paste(if (identical(VALUE_TYPES, "all")) "all" else VALUE_TYPES, collapse = "/"),
          " | EXCLUDE_STAT_BASES=",
          if (length(EXCLUDE_STAT_BASES)) paste(EXCLUDE_STAT_BASES, collapse = "/") else "none",
          "\n                               VIOLATION_COLS=", paste(VIOLATION_COLS, collapse = "/"),
          " | ADD_FACILITY_ID=", ADD_FACILITY_ID,
          "\n                               RESTRICT_CONTINENTAL=", RESTRICT_CONTINENTAL,
          " (", length(F_STATES), " state codes)",
          " | ADD_NODI_DESC=", ADD_NODI_DESC)
  message("\n-- filter funnel --")
  message("Eligible permits (population): ", format(length(ELIGIBLE_PERMITS), big.mark = ","),
          "   (ASSUMPTION 1, shared with code/dmr/filter_dmr_major_individual.R)")
  message("Rows from source, population + TSS: ", format(n_src_rows, big.mark = ","),
          "   (DuckDB, whole member)")
  message("  ...of which FY", fy_data, "      : ", format(n_in, big.mark = ","))
  message("  dropped, not Effluent Gross: ", format(n_not_monloc, big.mark = ","),
          "   (MONITORING_LOCATION_CODE outside ", paste(F_MONLOC, collapse = "/"), ")")
  message("  dropped, not ", F_FEATURE, "          : ", format(n_not_exo, big.mark = ","))
  message("  dropped, not a monthly avg : ", format(n_not_avg, big.mark = ","),
          "   (base outside EPA's STATISTICAL_BASE_MONTHLY_AVG == 'A' set)")
  message("  dropped, EXCLUDE_STAT_BASES: ", format(n_excl_avg, big.mark = ","))
  message("  dropped, value type        : ", format(n_not_vt, big.mark = ","))
  if (RESTRICT_CONTINENTAL) {
    message("  dropped, non-continental   : ", format(n_not_cont, big.mark = ","),
            "   (kept: 48 states + DC, by facility location; ASSUMPTION 11)")
    if (nrow(state_drop_tab)) print(state_drop_tab)
  }
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
  if (RESTRICT_CONTINENTAL)
    message("States covered                  : ", uniqueN(out$STATE_CODE), " of ",
            length(F_STATES), " kept",
            if (uniqueN(out$STATE_CODE) < length(F_STATES))
              paste0("   (no in-scope rows in: ",
                     paste(sort(setdiff(F_STATES, unique(out$STATE_CODE))), collapse = ", "), ")")
            else "")
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

  if (ADD_NODI_DESC) {
    message("\n-- NODI codes, EPA's own text (ASSUMPTION 12) --")
    message("Rows with a NODI code        : ",
            format(sum(out$NODI_CODE != ""), big.mark = ","),
            sprintf(" (%.1f%%)", 100 * mean(out$NODI_CODE != "")),
            " | distinct codes: ", uniqueN(out[NODI_CODE != "", NODI_CODE]),
            " of ", nrow(nodi), " EPA documents")
    print(out[NODI_CODE != "", .N, by = .(NODI_CODE, NODI_DESC)][order(-N)])
  }

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

  data.table(fy = fy_data, source = src$key, status = "built",
             reason = NA_character_, rows = nrow(out))
}

# ==============================================================================
# ORCHESTRATION: one pass per source, then one call per fiscal year found
# ==============================================================================
results <- list()
claimed_by <- character(0)   # fy -> source key, for ASSUMPTION 14
t_all <- Sys.time()

for (si in seq_along(SOURCES)) {
  src <- SOURCES[[si]]

  if (!is.na(src$problem)) {
    fys <- if (is.null(src$want)) NA_integer_ else src$want
    results[[length(results) + 1L]] <-
      data.table(fy = fys, source = src$key, status = "skipped",
                 reason = paste("source zip", src$problem), rows = NA_integer_)
    next
  }

  message("\n", strrep("-", 78))
  message("SOURCE ", si, "/", length(SOURCES), ": ", basename(src$zip),
          if (!is.null(src$want)) paste0("   (years wanted: ",
                                         paste(src$want, collapse = ", "), ")")
          else "   (every fiscal year it contains)")
  message(strrep("-", 78))

  dsrc <- tryCatch(read_source(src), error = function(e) e)
  if (inherits(dsrc, "error")) {
    fys <- if (is.null(src$want)) NA_integer_ else src$want
    message("  !! source failed: ", conditionMessage(dsrc))
    results[[length(results) + 1L]] <-
      data.table(fy = fys, source = src$key, status = "skipped",
                 reason = paste("source failed:", conditionMessage(dsrc)), rows = NA_integer_)
    next
  }

  n_src_rows <- nrow(dsrc)

  # Dates, then the fiscal year each row belongs to. The FY comes from the data,
  # never from a toggle or a filename.
  dsrc[, period_end := mdy(MONITORING_PERIOD_END_DATE)]
  n_bad_date <- sum(is.na(dsrc$period_end))
  if (n_bad_date > 0L)
    message("  unparseable MONITORING_PERIOD_END_DATEs dropped: ",
            format(n_bad_date, big.mark = ","))
  dsrc <- dsrc[!is.na(period_end)]
  dsrc[, fy := fy_of(period_end)]

  fys_present <- sort(unique(dsrc$fy))

  # ASSUMPTION 14: a per-FY zip is held to its own year; stray rows are counted
  # as out-of-window and dropped, not spun into another year's file.
  if (!is.na(src$nominal_fy)) {
    stray <- dsrc[fy != src$nominal_fy]
    if (nrow(stray)) {
      message("  outside FY", src$nominal_fy, " window, dropped: ",
              format(nrow(stray), big.mark = ","), "   (fiscal years: ",
              paste(sprintf("FY%d=%s", sort(unique(stray$fy)),
                            format(stray[, .N, by = fy][order(fy)]$N, big.mark = ",")),
                    collapse = ", "), ")")
    }
    fys_todo <- src$nominal_fy
  } else {
    # prefy2009: every year it holds, intersected with what was asked for.
    fys_todo <- if (is.null(src$want)) fys_present else intersect(fys_present, src$want)
    message("  fiscal years present in this member: ", length(fys_present),
            "  (", min(fys_present), "-", max(fys_present), ")")
    missing_want <- setdiff(src$want, fys_present)
    if (length(missing_want))
      for (fy in missing_want)
        results[[length(results) + 1L]] <-
          data.table(fy = as.integer(fy), source = src$key, status = "skipped",
                     reason = "no rows for this FY in the source member", rows = 0L)
  }

  # `this_fy`, not `fy`: `fy` is also a column of dsrc, and a filter written
  # `dsrc[fy == fy]` would compare the column with itself and match every row.
  for (this_fy in sort(fys_todo)) {
    this_fy <- as.integer(this_fy)
    key <- as.character(this_fy)
    # ASSUMPTION 14: two sources must not write the same file in one run.
    if (!is.na(claimed_by[key]))
      stop("FY", this_fy, " is produced by two sources in this run: ", claimed_by[key],
           " and ", src$key, ".\n  ", sprintf(OUTPUT_NAME_FMT, this_fy),
           " would be written twice. Narrow YEARS, or investigate the overlap",
           "\n  (see ASSUMPTION 14).")
    claimed_by[key] <- src$key

    d_fy <- dsrc[fy == this_fy]
    d_fy[, fy := NULL]      # the grouping column has done its job
    res <- tryCatch(process_fy(d_fy, this_fy, src, n_src_rows),
                    error = function(e) e)
    if (inherits(res, "error")) {
      message("  !! FY", this_fy, " failed: ", conditionMessage(res))
      res <- data.table(fy = this_fy, source = src$key, status = "skipped",
                        reason = conditionMessage(res), rows = NA_integer_)
    } else if (identical(res$status, "skipped")) {
      message("  -- FY", this_fy, " skipped: ", res$reason)
    }
    results[[length(results) + 1L]] <- res
    rm(d_fy)
  }

  rm(dsrc); invisible(gc())
}

# ---- closing summary ---------------------------------------------------------
res <- rbindlist(results, fill = TRUE)
built   <- res[status == "built"][order(fy)]
skipped <- res[status == "skipped"][order(fy, na.last = TRUE)]

message("\n", strrep("=", 78))
message("=== all-years summary: ", length(SOURCES), " source(s), ",
        nrow(built), " fiscal year(s) built, ", nrow(skipped), " skipped ===")
message(strrep("=", 78))
message("Elapsed: ", round(as.numeric(difftime(Sys.time(), t_all, units = "mins")), 1), " min")

if (nrow(built)) {
  message("\n-- built --")
  print(built[, .(FY = fy, source, rows_written = rows)])
  message("Total rows written: ", format(sum(built$rows), big.mark = ","),
          " across ", nrow(built), " file(s) in ", OUTPUT_DIR)
}
if (nrow(skipped)) {
  message("\n-- SKIPPED --")
  print(skipped[, .(FY = fy, source, reason)])
}

# Non-zero exit if anything the user asked for did not get built, so a wrapper
# or a cron job notices (ASSUMPTION 10).
unbuilt <- if (is.null(REQUESTED_FYS)) integer(0) else setdiff(REQUESTED_FYS, built$fy)
if (length(unbuilt) || nrow(skipped)) {
  message("\nExiting non-zero: ",
          if (length(unbuilt))
            paste0(length(unbuilt), " requested year(s) not built (",
                   paste(unbuilt, collapse = ", "), "); ") else "",
          nrow(skipped), " skip(s) reported above.")
  quit(save = "no", status = 1L)
}
message("\nAll requested years built.")
