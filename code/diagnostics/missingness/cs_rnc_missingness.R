# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# cs_rnc_missingness.R
# ------------------------------------------------------------------------------
# Why is RNC_DETECTION_CODE (the "was this a reportable noncompliance?" field)
# ~61% blank in NPDES_CS_VIOLATIONS? This script tests one candidate
# explanation: does whether RNC gets recorded track the PERMIT's own
# major/minor status, or its RNC_TRACKING_FLAG -- i.e., are permits that
# aren't tracked for RNC purposes simply never given an RNC code on their
# violations, which would explain the blanks as structural, not accidental?
#
#   Method: for every violation row, look up its permit's MAJOR_MINOR_STATUS_FLAG
#   and RNC_TRACKING_FLAG, then report what % of violations have a non-blank
#   RNC_DETECTION_CODE ("RNC-present"), broken out by each of those two flags.
#
# LABELED ASSUMPTION: the permit lookup (STEP 2 below) uses base R's match(),
#   which returns the FIRST matching row for a given NPDES_ID in ICIS_PERMITS.csv.
#   ICIS_PERMITS has one row per permit VERSION (a permit can be reissued many
#   times), so this is whichever version happens to appear first in the raw
#   file -- NOT guaranteed to be the permit's current version. That's fine for
#   this exploratory question (is there ANY association at all), but this
#   script should NOT be used as a source of "current" permit status; see
#   other scripts in this repo (e.g. naics_california.R) for the
#   VERSION_NMBR == 0 convention used when current status actually matters.
#
# Inputs : data/raw/npdes_downloads/NPDES_CS_VIOLATIONS.csv, ICIS_PERMITS.csv
# Output : console only (no file written) -- exploratory read, not a saved extract.
# Read-only on raw data.
# ==============================================================================

raw_dir <- file.path(CWA_ROOT, "data/raw/npdes_downloads")

# Read both files as plain text so codes/flags compare exactly as stored,
# with no numeric or factor coercion.
violations <- read.csv(file.path(raw_dir, "NPDES_CS_VIOLATIONS.csv"), colClasses = "character")
permits    <- read.csv(file.path(raw_dir, "ICIS_PERMITS.csv"),        colClasses = "character")

# ------------------------------------------------------------------------------
# STEP 1: Flag whether each violation row has a non-blank RNC_DETECTION_CODE.
# ------------------------------------------------------------------------------
# A value counts as "blank" if it's a true NA, or (after trimming whitespace)
# an empty string -- either way, no RNC code was recorded for that row.
is_blank <- function(x) is.na(x) | trimws(x) == ""
violations$rnc_present <- !is_blank(violations$RNC_DETECTION_CODE)

# ------------------------------------------------------------------------------
# STEP 2: Attach each violation's permit-level MAJOR_MINOR_STATUS_FLAG and
# RNC_TRACKING_FLAG (see LABELED ASSUMPTION above on which permit row this uses).
# ------------------------------------------------------------------------------
major_minor_flag  <- permits$MAJOR_MINOR_STATUS_FLAG[match(violations$NPDES_ID, permits$EXTERNAL_PERMIT_NMBR)]
rnc_tracking_flag <- permits$RNC_TRACKING_FLAG[match(violations$NPDES_ID, permits$EXTERNAL_PERMIT_NMBR)]

# Turns a raw flag value into a human-readable label for the report below:
# a true NA (no permit match found at all) vs. an empty string (permit found,
# but that field itself was blank) are different situations worth telling apart.
format_label <- function(flag_value) {
  if (is.na(flag_value)) "(no match)"
  else if (flag_value == "") "(blank)"
  else flag_value
}

# ------------------------------------------------------------------------------
# STEP 3: For a given grouping flag (major/minor, or RNC tracking), print the
# RNC-present rate within each distinct value of that flag.
# ------------------------------------------------------------------------------
report_rnc_rate_by_group <- function(group_values, title) {
  cat("\n===", title, "===\n")
  # table() silently drops NAs by default, so give NA its own placeholder
  # string first -- otherwise rows with no permit match would vanish from
  # the breakdown instead of showing up as their own "(no match)" category.
  group_values[is.na(group_values)] <- "__NA__"
  for (val in names(sort(table(group_values), decreasing = TRUE))) {
    in_group <- group_values == val
    cat(sprintf("  %-10s n=%6d  RNC-present %5.1f%%\n",
                format_label(if (val == "__NA__") NA else val),
                sum(in_group),
                100 * mean(violations$rnc_present[in_group])))
  }
}

report_rnc_rate_by_group(major_minor_flag,  "RNC-present rate by permit MAJOR/MINOR status")
report_rnc_rate_by_group(rnc_tracking_flag, "RNC-present rate by permit RNC_TRACKING_FLAG")
