# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# 05_add_enforcement.R
# ------------------------------------------------------------------------------
# FIFTH STEP in the facility-by-month pipeline. Reads the panel produced by
# 04_add_violations.R and attaches, for every facility-month, counts of FORMAL
# and INFORMAL NPDES enforcement actions (plus formal penalty dollars).
#
#   NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv   -> formal actions (AOs, judicial, ...)
#   NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv -> informal actions (letters, notices)
#
#   Input  : data/processed/04_facility_month_panel_major_individual_violations_2005_2025.csv
#            (one row per FACILITY_UIN x YEAR x MONTH; built by scripts 01-04)
#   Output : data/processed/05_facility_month_panel_major_individual_enforcement_2005_2025.csv
#            (the same panel + 20 new enforcement columns)
#
# COLUMNS ADDED (integer counts unless noted; counted within each facility-month):
#   -- FORMAL (from NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv) --
#   N_FORMAL_ACTIONS      - distinct formal enforcement actions (ENF_IDENTIFIER)
#   N_AFR                 - ...of ACTIVITY_TYPE_CODE "AFR" (administrative formal)
#   N_JDC                 - ...of ACTIVITY_TYPE_CODE "JDC" (judicial)
#   N_SCWAAPO             - ...of ENF_TYPE_CODE "SCWAAPO" (State CWA Penalty AO)
#   N_STAOCO              - ...of ENF_TYPE_CODE "STAOCO"  (State Admin Order of Consent)
#   N_SCWAAO              - ...of ENF_TYPE_CODE "SCWAAO"  (State CWA Non-Penalty AO)
#   N_309A                - ...of ENF_TYPE_CODE "309A"    (CWA 309A AO for Compliance)
#   N_STATE_FORMAL        - ...led by a STATE agency  (AGENCY == "State")
#   N_EPA_FORMAL          - ...led by EPA             (AGENCY == "EPA")
#   FED_PENALTY           - dollars assessed: sum of FED_PENALTY_ASSESSED_AMT
#                           (once per action). NA if NO action carried a federal
#                           amount; 0 ONLY when an amount was assessed at $0.
#   N_FED_PENALTY_ASSESSED - # distinct actions carrying a (non-blank) federal amount
#   STATE_PENALTY         - dollars assessed: sum of STATE_LOCAL_PENALTY_AMT
#                           (once per action). NA if none assessed; 0 = assessed $0.
#   N_STATE_PENALTY_ASSESSED - # distinct actions carrying a (non-blank) state amount
#
#   -- INFORMAL (from NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv) --
#   N_INFORMAL_ACTIONS    - distinct informal enforcement actions (ENF_IDENTIFIER)
#   N_LOVWL               - ...of ENF_TYPE_CODE "LOVWL" (Letter of Violation/Warning)
#   N_NOV                 - ...of ENF_TYPE_CODE "NOV"   (Notice of Violation)
#   N_NONC                - ...of ENF_TYPE_CODE "NONC"  (Notice of Noncompliance)
#   N_AER                 - ...of ENF_TYPE_CODE "AER"   (Agency Enforcement Review)
#   N_OFFICIAL_INFORMAL   - ...with OFFICIAL_FLG == "Y" (official response)
#   N_UNOFFICIAL_INFORMAL - ...with OFFICIAL_FLG == "N" (unofficial response)
#
# ------------------------------------------------------------------------------
# LABELED ASSUMPTIONS (read before using results):
#
#   1. ACTION GRAIN = ENF_IDENTIFIER. One enforcement action is one ENF_IDENTIFIER.
#      The raw files list SEVERAL rows per action (one per permit and/or per
#      enforcement-type it carries): the formal file has ~112k rows but only
#      ~104k distinct ENF_IDENTIFIERs. So every COUNT below is DISTINCT
#      ENF_IDENTIFIER, never raw rows -- counting rows would over-count multi-
#      permit / multi-type actions.
#
#   2. TYPE / ACTIVITY BREAKOUTS CAN OVERLAP (per PI naming of the columns). A
#      single action may carry more than one ENF_TYPE_CODE across its rows, so an
#      action that is both e.g. SCWAAPO and 309A is counted in BOTH N_SCWAAPO and
#      N_309A. Therefore the type columns are NOT a partition of the action total
#      and may sum to more than N_FORMAL_ACTIONS. The enf-type breakouts also do
#      not cover every code (CIV, COL, 309G*, ...), so they need not sum to the
#      total from below either. AGENCY (State/EPA) and, for informal, OFFICIAL_FLG
#      (Y/N) are expected to be one-per-action and thus to PARTITION the total --
#      the run log verifies whether each identity actually holds.
#
#   3. EXACT ENF_TYPE_CODE MATCH. N_AER matches ENF_TYPE_CODE == "AER" exactly; the
#      "significant" variant "AERS" (and any other "-S" suffixed variants) are
#      NOT folded in. Same for LOVWL / NOV / NONC. Flag if the -S variants should
#      be included.
#
#   4. DATE = WHEN THE ACTION WAS ENTERED / ACHIEVED.
#        - Formal   : SETTLEMENT_ENTERED_DATE (present on ~97% of rows).
#        - Informal : ACHIEVED_DATE           (present on ~99% of rows).
#      Actions with no parseable date cannot be placed in a month and are dropped;
#      the count dropped is reported in the run log (not silently swallowed).
#
#   5. PENALTIES ARE COUNTED ONCE PER ACTION, AND "NOT ASSESSED" != "$0" (per PI
#      guidance). Because an action spans multiple rows, its penalty amount is
#      de-duplicated to one value per (facility, month, ENF_IDENTIFIER) BEFORE
#      summing, so a shared penalty is never multiplied across the action's rows.
#      A BLANK amount means the penalty was never assessed / does not apply -- it
#      is kept as NA, NOT turned into 0, so it stays distinct from a genuine
#      assessed $0 (in the raw file blanks vastly outnumber true zeros: ~107k vs
#      72 federal, ~64k vs 768 state). So FED_PENALTY / STATE_PENALTY are NA for
#      any facility-month in which NO action carried an amount, and 0 ONLY when an
#      amount was assessed and summed to zero. The companion counts
#      N_FED_PENALTY_ASSESSED / N_STATE_PENALTY_ASSESSED give the number of
#      distinct actions that carried a (non-blank) amount, so the three states are
#      always recoverable:
#        no action        -> N_FORMAL_ACTIONS == 0,      penalty NA
#        action, none set -> N_*_PENALTY_ASSESSED == 0,  penalty NA
#        action, assessed -> N_*_PENALTY_ASSESSED  > 0,  penalty 0 or > 0
#      These four are the only non-count / NA-bearing columns added here; every
#      COUNT column is a true zero when nothing occurred (see ASSUMPTION 7).
#
#   6. ROUTED BY NPDES_ID VIA THE SAME CROSSWALK AS SCRIPTS 02 & 04. Each action is
#      keyed to a permit (NPDES_ID); we map NPDES_ID -> facility exactly the way
#      scripts 01-04 do (FACILITY_UIN when present, else the NPDES_ID itself),
#      counting an action on ANY permit that resolves to the facility.
#
#   7. PANEL DEFINES THE OBSERVATION SET. Counts are attached by LEFT-JOINING onto
#      the existing panel spine. Actions in a facility-month not in the panel do
#      not appear. A facility-month with no action gets a true 0 for every COUNT
#      column (we know zero actions occurred), but the two penalty DOLLAR columns
#      get NA, not 0 -- there is no penalty information to record (ASSUMPTION 5).
#
# Deterministic (no stochastic steps); rebuilt entirely from raw + scripts 01-04
# output + this script. Non-destructive: writes a NEW file, leaves script 04's
# panel untouched, and is safe to re-run.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)   # fast CSV reads + grouped counts over the enforcement files
  library(lubridate)    # date parsing (mdy) and year()/month() extraction
})

## ---- Config (edit here if the panel window or file locations ever change) ----
YEAR_MIN <- 2005L
YEAR_MAX <- 2025L
RAW_DIR  <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
IN_PATH  <- file.path(CWA_ROOT, "data/processed/04_facility_month_panel_major_individual_violations_2005_2025.csv")
OUT_PATH <- file.path(CWA_ROOT, "data/processed/05_facility_month_panel_major_individual_enforcement_2005_2025.csv")

# Small helper: read only the columns we need, everything as plain text
# (character) so ID and code columns are never silently reinterpreted as numbers.
rd <- function(file, cols) {
  class_map <- setNames(rep("character", length(cols)), cols)
  fread(file.path(RAW_DIR, file), select = cols,
        colClasses = class_map, showProgress = FALSE)
}

# Parse a text money field to whole-dollar numeric. A BLANK or non-numeric amount
# is NOT $0 -- it means no penalty was assessed / recorded, so it becomes NA and
# stays distinct from a genuine assessed $0 (see ASSUMPTION 5).
to_dollars <- function(x) suppressWarnings(as.numeric(gsub("[$, ]", "", x)))

# Aggregators that PRESERVE the no-information state: return NA (not 0) when EVERY
# value is NA, otherwise ignore the NAs. So an action / facility-month with no
# assessed amount stays NA, while one assessed at $0 stays 0.
max_assessed <- function(v) if (all(is.na(v))) NA_real_ else max(v, na.rm = TRUE)
sum_assessed <- function(v) if (all(is.na(v))) NA_real_ else sum(v, na.rm = TRUE)

# ------------------------------------------------------------------------------
# STEP 1: Read the facility-by-month panel (output of script 04).
# ------------------------------------------------------------------------------
# One row per FACILITY_UIN x YEAR x MONTH. Read YEAR/MONTH as integers so they
# align with the values we derive from the action dates below.
panel <- fread(IN_PATH, colClasses = "character", showProgress = FALSE)
panel[, `:=`(YEAR = as.integer(YEAR), MONTH = as.integer(MONTH))]

# ------------------------------------------------------------------------------
# STEP 2: Rebuild the NPDES_ID -> facility_id crosswalk (same rule as scripts 01-04).
# ------------------------------------------------------------------------------
# A facility's id is its FACILITY_UIN when present, else the permit's own
# NPDES_ID. We reproduce that EXACTLY so each action resolves to the same id the
# panel is keyed on (ASSUMPTION 6).
fac <- rd("ICIS_FACILITIES.csv", c("NPDES_ID", "FACILITY_UIN"))
fac[, NPDES_ID     := trimws(NPDES_ID)]
fac[, FACILITY_UIN := trimws(FACILITY_UIN)]
fac[, facility_id  := fifelse(FACILITY_UIN != "", FACILITY_UIN, NPDES_ID)]
xwalk <- unique(fac[NPDES_ID != "", .(NPDES_ID, facility_id)])

# Shared prep: date each action, keep the window, route NPDES_ID -> facility_id.
# Returns the enforcement table with YEAR/MONTH/facility_id, plus the count of
# rows dropped for an unparseable date (reported in the log, ASSUMPTION 4).
prep_actions <- function(dt, date_col) {
  dt[, NPDES_ID := trimws(NPDES_ID)]
  dt[, adate := mdy(get(date_col), quiet = TRUE)]
  n_no_date <- dt[is.na(adate), .N]
  dt <- dt[!is.na(adate)]
  dt[, `:=`(YEAR = year(adate), MONTH = month(adate))]
  dt <- dt[YEAR >= YEAR_MIN & YEAR <= YEAR_MAX]
  # Inner join (nomatch = 0): drop actions whose permit has no facility record --
  # they can never match a panel row anyway.
  dt <- xwalk[dt, on = "NPDES_ID", nomatch = 0]
  list(dt = dt, n_no_date = n_no_date)
}

# ------------------------------------------------------------------------------
# STEP 3: FORMAL actions -> facility-month counts + penalties.
# ------------------------------------------------------------------------------
f_raw <- rd("NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv",
            c("NPDES_ID", "ENF_IDENTIFIER", "ACTIVITY_TYPE_CODE", "ENF_TYPE_CODE",
              "AGENCY", "SETTLEMENT_ENTERED_DATE",
              "FED_PENALTY_ASSESSED_AMT", "STATE_LOCAL_PENALTY_AMT"))
fp <- prep_actions(f_raw, "SETTLEMENT_ENTERED_DATE")
formal <- fp$dt

# 3a. Distinct-action counts per facility-month (ASSUMPTIONS 1-2).
formal_counts <- formal[, .(
    N_FORMAL_ACTIONS = uniqueN(ENF_IDENTIFIER),
    N_AFR            = uniqueN(ENF_IDENTIFIER[ACTIVITY_TYPE_CODE == "AFR"]),
    N_JDC            = uniqueN(ENF_IDENTIFIER[ACTIVITY_TYPE_CODE == "JDC"]),
    N_SCWAAPO        = uniqueN(ENF_IDENTIFIER[ENF_TYPE_CODE == "SCWAAPO"]),
    N_STAOCO         = uniqueN(ENF_IDENTIFIER[ENF_TYPE_CODE == "STAOCO"]),
    N_SCWAAO         = uniqueN(ENF_IDENTIFIER[ENF_TYPE_CODE == "SCWAAO"]),
    N_309A           = uniqueN(ENF_IDENTIFIER[ENF_TYPE_CODE == "309A"]),
    N_STATE_FORMAL   = uniqueN(ENF_IDENTIFIER[AGENCY == "State"]),
    N_EPA_FORMAL     = uniqueN(ENF_IDENTIFIER[AGENCY == "EPA"])
  ), by = .(facility_id, YEAR, MONTH)]

# 3b. Penalties: one dollar figure per action first (ASSUMPTION 5), then sum.
#     De-duplicate to one row per (facility, month, action) taking the max of any
#     per-row copies of the amount (NA-preserving), so a shared penalty is counted
#     exactly once and an action with no amount stays NA rather than $0. The sum is
#     NA-preserving too: a facility-month becomes NA unless at least one action
#     carried an amount. N_*_PENALTY_ASSESSED counts the actions that did.
formal[, `:=`(fed = to_dollars(FED_PENALTY_ASSESSED_AMT),
              stt = to_dollars(STATE_LOCAL_PENALTY_AMT))]
formal_pen_action <- formal[, .(fed = max_assessed(fed), stt = max_assessed(stt)),
                            by = .(facility_id, YEAR, MONTH, ENF_IDENTIFIER)]
formal_pen <- formal_pen_action[, .(
    FED_PENALTY              = sum_assessed(fed),
    N_FED_PENALTY_ASSESSED   = sum(!is.na(fed)),
    STATE_PENALTY            = sum_assessed(stt),
    N_STATE_PENALTY_ASSESSED = sum(!is.na(stt))
  ), by = .(facility_id, YEAR, MONTH)]

# ------------------------------------------------------------------------------
# STEP 4: INFORMAL actions -> facility-month counts.
# ------------------------------------------------------------------------------
i_raw <- rd("NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv",
            c("NPDES_ID", "ENF_IDENTIFIER", "ENF_TYPE_CODE",
              "ACHIEVED_DATE", "OFFICIAL_FLG"))
ip <- prep_actions(i_raw, "ACHIEVED_DATE")
informal <- ip$dt

informal_counts <- informal[, .(
    N_INFORMAL_ACTIONS    = uniqueN(ENF_IDENTIFIER),
    N_LOVWL               = uniqueN(ENF_IDENTIFIER[ENF_TYPE_CODE == "LOVWL"]),
    N_NOV                 = uniqueN(ENF_IDENTIFIER[ENF_TYPE_CODE == "NOV"]),
    N_NONC                = uniqueN(ENF_IDENTIFIER[ENF_TYPE_CODE == "NONC"]),
    N_AER                 = uniqueN(ENF_IDENTIFIER[ENF_TYPE_CODE == "AER"]),
    N_OFFICIAL_INFORMAL   = uniqueN(ENF_IDENTIFIER[OFFICIAL_FLG == "Y"]),
    N_UNOFFICIAL_INFORMAL = uniqueN(ENF_IDENTIFIER[OFFICIAL_FLG == "N"])
  ), by = .(facility_id, YEAR, MONTH)]

# ------------------------------------------------------------------------------
# STEP 5: Combine the four count/penalty tables into one facility-month table.
# ------------------------------------------------------------------------------
# Full outer merge so a facility-month with any one kind of action is kept; kinds
# not present in that month come through as NA and are set to 0 below.
# Fill rules differ by column KIND: a COUNT is a true 0 when nothing occurred, but
# a penalty DOLLAR column stays NA (no information) -- see ASSUMPTIONS 5 & 7.
count_cols <- c("N_FORMAL_ACTIONS", "N_AFR", "N_JDC",
                "N_SCWAAPO", "N_STAOCO", "N_SCWAAO", "N_309A",
                "N_STATE_FORMAL", "N_EPA_FORMAL",
                "N_FED_PENALTY_ASSESSED", "N_STATE_PENALTY_ASSESSED",
                "N_INFORMAL_ACTIONS", "N_LOVWL", "N_NOV", "N_NONC", "N_AER",
                "N_OFFICIAL_INFORMAL", "N_UNOFFICIAL_INFORMAL")
pen_cols  <- c("FED_PENALTY", "STATE_PENALTY")
# Output order: formal counts, then each penalty next to its "assessed" count,
# then informal counts.
new_cols  <- c("N_FORMAL_ACTIONS", "N_AFR", "N_JDC",
               "N_SCWAAPO", "N_STAOCO", "N_SCWAAO", "N_309A",
               "N_STATE_FORMAL", "N_EPA_FORMAL",
               "FED_PENALTY", "N_FED_PENALTY_ASSESSED",
               "STATE_PENALTY", "N_STATE_PENALTY_ASSESSED",
               "N_INFORMAL_ACTIONS", "N_LOVWL", "N_NOV", "N_NONC", "N_AER",
               "N_OFFICIAL_INFORMAL", "N_UNOFFICIAL_INFORMAL")

adds <- Reduce(function(a, b) merge(a, b, by = c("facility_id", "YEAR", "MONTH"), all = TRUE),
               list(formal_counts, formal_pen, informal_counts))
for (c in count_cols) adds[is.na(get(c)), (c) := 0L]
# penalties: leave NA (no action carried an amount) -- do NOT coerce to 0.

# ------------------------------------------------------------------------------
# STEP 6: Attach to the panel and fill non-action months with 0.
# ------------------------------------------------------------------------------
# Left-join: panel key FACILITY_UIN == action key facility_id, plus YEAR/MONTH.
panel <- adds[panel, on = c(facility_id = "FACILITY_UIN", "YEAR", "MONTH")]
setnames(panel, "facility_id", "FACILITY_UIN")            # restore the panel's name

for (c in count_cols) panel[is.na(get(c)), (c) := 0L]
# penalties stay NA where no formal action carried an assessed amount (ASSUMPTION 5).

# Put the new columns at the end, after the existing panel columns, and restore
# the panel's row order.
setcolorder(panel, c(setdiff(names(panel), new_cols), new_cols))
setorder(panel, FACILITY_UIN, YEAR, MONTH)

fwrite(panel, OUT_PATH)

# ------------------------------------------------------------------------------
# STEP 7: Run log (sanity checks; see ASSUMPTIONS 2 for why type sums differ).
# ------------------------------------------------------------------------------
message("=== 05_add_enforcement: enforcement actions attached to month panel ===")
message("Formal actions dropped for no/parse date         : ", fp$n_no_date)
message("Informal actions dropped for no/parse date       : ", ip$n_no_date)
message("Formal actions placed on panel                   : ", sum(panel$N_FORMAL_ACTIONS),
        "  (AFR ", sum(panel$N_AFR), " / JDC ", sum(panel$N_JDC), ")")
message("  SCWAAPO / STAOCO / SCWAAO / 309A               : ",
        sum(panel$N_SCWAAPO), " / ", sum(panel$N_STAOCO), " / ",
        sum(panel$N_SCWAAO), " / ", sum(panel$N_309A))
message("  State-led / EPA-led formal totals              : ",
        sum(panel$N_STATE_FORMAL), " / ", sum(panel$N_EPA_FORMAL))
message("  Identity state + epa == formal total holds     : ",
        all(panel$N_STATE_FORMAL + panel$N_EPA_FORMAL == panel$N_FORMAL_ACTIONS))
message("Formal penalties ($, assessed only): federal ",
        format(sum(panel$FED_PENALTY, na.rm = TRUE), big.mark = ","),
        " / state ", format(sum(panel$STATE_PENALTY, na.rm = TRUE), big.mark = ","))
message("  Facility-months w/ a fed / state amount assessed : ",
        sum(panel$N_FED_PENALTY_ASSESSED > 0), " / ", sum(panel$N_STATE_PENALTY_ASSESSED > 0))
message("  Of months WITH a formal action, penalty is NA (not assessed) fed / state : ",
        sum(panel$N_FORMAL_ACTIONS > 0 & is.na(panel$FED_PENALTY)), " / ",
        sum(panel$N_FORMAL_ACTIONS > 0 & is.na(panel$STATE_PENALTY)),
        "  (assessed at $0: ",
        sum(panel$FED_PENALTY == 0, na.rm = TRUE), " / ",
        sum(panel$STATE_PENALTY == 0, na.rm = TRUE), ")")
message("Informal actions placed on panel                 : ", sum(panel$N_INFORMAL_ACTIONS),
        "  (LOVWL ", sum(panel$N_LOVWL), " / NOV ", sum(panel$N_NOV),
        " / NONC ", sum(panel$N_NONC), " / AER ", sum(panel$N_AER), ")")
message("  Official / unofficial informal totals          : ",
        sum(panel$N_OFFICIAL_INFORMAL), " / ", sum(panel$N_UNOFFICIAL_INFORMAL))
message("  Identity official + unofficial == informal tot : ",
        all(panel$N_OFFICIAL_INFORMAL + panel$N_UNOFFICIAL_INFORMAL == panel$N_INFORMAL_ACTIONS))
message("Facility-months with >=1 formal / informal action: ",
        sum(panel$N_FORMAL_ACTIONS > 0), " / ", sum(panel$N_INFORMAL_ACTIONS > 0))
message("Panel rows: ", nrow(panel), " | columns: ", ncol(panel))
message("Written to: ", OUT_PATH)
