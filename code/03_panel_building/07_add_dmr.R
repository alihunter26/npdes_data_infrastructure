# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, PROC_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# Shared cleaning helpers: rd() (safe raw-file reads) and build_facility_crosswalk()
# (NPDES_ID -> facility_id). See code/02_cleaning/module_README.md.
source(file.path(CWA_ROOT, "code/02_cleaning/cleaning_helpers.R"))

# ==============================================================================
# 07_add_dmr.R
# ------------------------------------------------------------------------------
# SEVENTH STEP in the facility-by-month pipeline, and the first one that reads
# the DMR files themselves rather than a violations extract. Reads the panel
# produced by 06_add_effluent_violations.R and attaches, for every facility-month
# that FY2017 DMR data covers, 20 DISCHARGE AND COMPLIANCE variables plus 6
# bookkeeping columns.
#
# WHY THIS EXISTS: through step 06 the panel knows only whether a facility was
# CITED (n_D80/n_D90/n_E90, N_TSS_EFF_*). It has no measure of HOW MUCH was
# discharged, how much was PERMITTED, or how close to its limit a facility ran.
# Those quantities live only in the DMR files, which the pipeline never opened.
#
#   Input  : code/dmr/03_dmr_fy2017_00530_monloc1.csv
#            (PRE-BUILT by the code/dmr/ row-filter pipeline, steps 1-3 -- see
#            PREREQUISITE below; this script does not build it)
#            data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv
#            data/raw/reference/REF_NODI.csv
#   Output : data/processed/07_facility_month_panel_major_individual_dmr_tss_2005_2025.csv
#            data/processed/dmr_fy2017_tss_effgross_mk_outfall_basis.csv   (intermediate)
#            output/tables/dmr_fy2017_dropped_multiset_permits_<stamp>.csv (diagnostic)
#            output/tables/dmr_fy2017_exceed_disagreements_<stamp>.csv     (diagnostic)
#
# PREREQUISITE (run once, manually, before this script):
#   Rscript code/dmr/filter_dmr_major_individual.R 2017
#   Rscript code/dmr/filter_dmr_00530.R 2017
#   Rscript code/dmr/filter_dmr_monloc1.R 2017
# Step 4 of that pipeline (C1/Q1) is deliberately NOT used -- see ASSUMPTION 2.
#
# NOT PART OF run_all.R: it depends on those manually-run filter steps and on a
# single fiscal year, so wiring it into the full rebuild would make run_all.R
# silently depend on a 45-minute DMR stream for one year of coverage.
#
# ------------------------------------------------------------------------------
# LABELED ASSUMPTIONS (read before using results):
#
#   1. ONE FISCAL YEAR ONLY (FY2017 = Oct 2016 - Sep 2017). Every one of the 20
#      variables is NA outside that window. The column names carry no year, so
#      adding FY2018 later means filling more months -- not renaming anything.
#      There is NO coverage-flag column: a facility-month is covered iff
#      N_OUTFALL_BASIS_TOTAL is non-NA, so a flag would be exactly redundant
#      (verified bit-for-bit). Filter covered rows with
#      !is.na(N_OUTFALL_BASIS_TOTAL). A facility-month inside the
#      window but with no DMR report is ALSO NA, not 0: absence of a DMR report
#      is not a measured zero discharge. This is deliberately UNLIKE step 06,
#      where a missing violation record genuinely does mean zero violations.
#
#   2. THE GRAIN IS OUTFALL x BASIS x MONTH, which requires fixing the
#      statistical base. A monthly-average row and a daily-maximum row for the
#      same outfall-month are different statistics and cannot share a cell, so:
#        STATISTICAL_BASE_CODE == 'MK'  (the literal "Monthly Average" code)
#      "BASIS" is VALUE_TYPE_CODE, which per ECHO's own field description encodes
#      Concentration-vs-Quantity and a slot number -- NOT a statistic (this was
#      established empirically in code/dmr/value_type_vs_statistical_base.R):
#        mass          = VALUE_TYPE_CODE 'Q1' (quantity average, kg/d)
#        concentration = VALUE_TYPE_CODE 'C2' (concentration average, mg/L)
#      Restricting to the Q1/C2 average pair guarantees at most one row per
#      outfall-basis-month before the limit-set problem in ASSUMPTION 4. MK rows
#      carrying only C1/C3/Q2 are dropped and counted in the run log.
#
#   3. "OUTFALL" MEANS EXTERNAL OUTFALL: PERM_FEATURE_TYPE_CODE == 'EXO'.
#      Monitoring location 1 (Effluent Gross) still admits internal outfalls
#      ('INO') and other feature types ('LAS'/'SUM'/'INF'/'INS'); counting those
#      as outfalls would double-count the same water on its way out. Same
#      restriction code/dmr/value_type_vs_statistical_base.R uses.
#      Outfall IDENTITY is (permit, PERM_FEATURE_NMBR), never PERM_FEATURE_NMBR
#      alone -- the outfall number is only unique within a permit
#      (docs/panel_questions_for_pis.md, "Aggregating outfalls up to the facility").
#
#   4. PERMITS WITH MULTI-LIMIT-SET OUTFALLS ARE DROPPED WHOLE. After the
#      latest-version de-dup, a residual duplicate on
#      (permit, outfall, month, basis) means the outfall is governed by two or
#      more LIMIT_SET_IDs at once. There is no settled rule for collapsing those
#      (the open `needs_rule` question in
#      data/processed/fy2017_tss_*_multiset_*.csv), and every sum, count and
#      ratio below depends on the choice -- so per decision 2026-10-07 the whole
#      PERMIT is dropped rather than collapsed under a guess. This is lossy and
#      NOT uniform: the affected permits are large multi-outfall ones, so the
#      share of ROWS lost is several times the share of PERMITS lost. Both are
#      printed in the run log, and every dropped permit is written to
#      output/tables/ so the set is auditable and the decision reversible.
#      A facility holding a dropped permit gets NA for the whole facility-month
#      (flagged DMR_TSS_DROPPED_MULTISET), never a partial total -- a facility
#      can hold several permits, and silently summing the survivors would
#      understate its discharge without saying so.
#
#   5. STANDARD UNITS ONLY. Discharges and limits are read from
#      DMR_VALUE_STANDARD_UNITS / LIMIT_VALUE_STANDARD_UNITS, never the raw
#      *_NMBR columns, which are in permit-specific units and are not comparable
#      across outfalls or facilities.
#      UNITS CAVEAT: Q1 is kg/d -- a daily-average RATE, not a monthly mass.
#      Summing a rate across outfalls is legitimate (rates are additive), but
#      MASS_DISCHARGED_TOTAL is in kg/d and must not be read as kilograms. No
#      multiplication by days-in-month happens anywhere in this script.
#
#   6. EXCEEDANCE IS reported > limit. Safe for TSS because its numeric limits
#      are near-uniformly '<=' ceilings (docs/data_issues.md). The script
#      ASSERTS that on the FY2017 data rather than trusting it, and reports any
#      '>=' (floor) rows instead of silently mis-signing them.
#      Two exceedance counts are produced and kept separate on purpose:
#      N_*_EXCEED_CALC is our own test; N_*_EXCEED_EPA counts
#      VIOLATION_CODE == 'E90'. They agree on all but a handful of rows; the
#      disagreements are written to output/tables/ and reported, not reconciled.
#
#   7. CENSORED VALUES ARE TAKEN AT FACE VALUE. A row with
#      DMR_VALUE_QUALIFIER_CODE '<' or '<=' reports the DETECTION LIMIT, not the
#      actual discharge, so MASS_DISCHARGED_* is an upper bound for those
#      outfalls. We use the reported number as-is (the same convention EPA's own
#      E90 flag uses) and expose N_OUTFALLS_CENSORED_MASS / _CONC so the
#      sensitivity is boundable rather than invisible.
#
#   8. NODI CODES COME FROM A REFERENCE TABLE, NOT FROM CODE. N_OUTFALLS_ACTIVE
#      needs to know which "no data" reasons still imply a live outfall, so
#      data/raw/reference/REF_NODI.csv carries all 33 EPA codes with a curated
#      NODI_ACTIVITY_CLASS (active / no_discharge / inactive / no_data_admin /
#      unclear), sourced from EPA's published DMR NODI code list. Six codes are
#      genuine judgment calls (4, 7, I, J, K, W: discharging-but-elsewhere vs.
#      not-operating) and are left 'unclear' -- they land in
#      N_OUTFALLS_NODI_UNCLASSIFIED instead of being forced into or out of the
#      active count. Change a classification by editing one cell of that CSV.
#      The script STOPS if FY2017 contains a NODI code the reference lacks, so
#      an unknown code can never be silently bucketed.
#      Note B (Below Detection Limit) is classed ACTIVE, not no-discharge: the
#      outfall is discharging, just below the measurable floor.
#
#   9. MULTI-MONTH REPORTS ARE DATED TO THEIR PERIOD-END MONTH, NOT SPREAD.
#      A row with NMBR_OF_REPORT > 1 summarises a quarter/half-year/year. Per
#      docs/panel_questions_for_pis.md it is placed in the month its window
#      ended and NOT spread backwards (spreading would manufacture monitoring
#      events that never happened). N_OUTFALL_BASIS_MULTIMONTH makes the
#      presence of such rows visible per facility-month rather than hidden.
#
#  10. EMPTY-DENOMINATOR AVERAGES ARE NA, NOT 0. MASS_RATIO_*, *_EXCEED_AVG_PROP
#      and CONC_RATIO_AVG are NA when their denominator set is empty; the paired
#      count column (N_*_EXCEED_CALC, N_OUTFALL_BASIS_TOTAL) carries the
#      information. This keeps "no exceedances occurred" distinct from
#      "exceedances averaged zero", which matters for any regression on the
#      average. MASS_EXCEED_TOTAL is the exception: it is a SUM, so an empty set
#      legitimately gives 0.
#
#  11. ROUTED BY NPDES_ID VIA THE SAME CROSSWALK AS STEPS 02/04/05/06
#      (build_facility_crosswalk(): FACILITY_UIN when present, else the
#      NPDES_ID itself), then aggregated across all of the facility's permits.
#      Facility-months present in the DMR data but ABSENT from the panel spine
#      drop in the join -- the panel's membership is narrower than "ever-major
#      individual permit" (step 01 also requires a permit window overlapping
#      2005-2025 or independent proxy evidence). FY2017: 1,073 facility-months
#      across 95 facilities, 1,984 outfall-basis rows. Same behaviour as step
#      06, but counted in the run log rather than assumed away.
#
#  12. THE SPECIFICATION IS EXECUTABLE. The requested variable list came with a
#      hand-worked example, so STEP 1 runs that example as a stopifnot() fixture
#      through the SAME summarise_dmr_outfall_basis() the real data uses, before
#      any file is read. If a definition drifts, the script fails loudly instead
#      of quietly producing different numbers.
#
#  13. NEGATIVE REPORTED VALUES ARE SURFACED, NOT CORRECTED. FY2017 contains 8
#      rows (2 facilities) reporting a NEGATIVE TSS mass or concentration, which
#      is physically impossible. They are counted in N_OUTFALL_BASIS_NEGATIVE,
#      written in full to output/tables/, and otherwise left exactly as reported
#      -- dropping or zeroing them would hide a real data-quality problem (the
#      class of problem code/dmr/eff_flagged.R exists to catch), and what to do
#      about them is a research decision, not this script's. They can drag
#      MASS_RATIO_POOLED / CONC_RATIO_AVG below zero in 8 facility-months;
#      condition on N_OUTFALL_BASIS_NEGATIVE == 0 to exclude them.
#
# Deterministic (no stochastic steps); rebuilt entirely from the pre-built
# filtered DMR file + step 06's panel + this script. Non-destructive: writes NEW
# files, leaves step 06's panel untouched, and is safe to re-run.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)   # fast CSV reads + grouped aggregation
  library(lubridate)    # mdy() date parsing, year()/month() extraction
})

## ---- Config (edit here if the FY or file locations ever change) --------------
FY            <- 2017L
FY_START      <- as.Date("2016-10-01")   # federal FY2017 window, inclusive
FY_END        <- as.Date("2017-09-30")
YEAR_MIN      <- 2005L
YEAR_MAX      <- 2025L

F_PARAM       <- "00530"   # TSS
# BOTH codes mean "Effluent Gross" per EPA's ICIS-NPDES DMR Data Element
# Dictionary (https://echo.epa.gov/node/206), and the upstream
# filter (code/dmr/filter_dmr_monloc1.R) deliberately keeps both -- FY2017 has
# 352,990 rows coded '1' and 1,101 coded 'EG'. Accepting only '1' would silently
# discard the latter.
F_MONLOC      <- c("1", "EG")
F_FEATURE     <- "EXO"     # external outfall            (ASSUMPTION 3)
F_STAT_BASE   <- "MK"      # literal Monthly Average      (ASSUMPTION 2)
BASIS_MASS    <- "Q1"      # quantity average, kg/d       (ASSUMPTION 2)
BASIS_CONC    <- "C2"      # concentration average, mg/L  (ASSUMPTION 2)
CENSOR_CODES  <- c("<", "<=")                           # (ASSUMPTION 7)

DMR_PATH  <- file.path(CWA_ROOT, "code/dmr", sprintf("03_dmr_fy%d_00530_monloc1.csv", FY))
NODI_PATH <- file.path(RAW_ROOT, "reference", "REF_NODI.csv")
IN_PATH   <- file.path(CWA_ROOT, "data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv")
OUT_PATH  <- file.path(CWA_ROOT, "data/processed/07_facility_month_panel_major_individual_dmr_tss_2005_2025.csv")
GRAIN_PATH <- file.path(CWA_ROOT, "data/processed",
                        sprintf("dmr_fy%d_tss_effgross_mk_outfall_basis.csv", FY))
TBL_DIR   <- file.path(CWA_ROOT, "output/tables")
STAMP     <- format(Sys.time(), "%Y-%m-%d_%H%M")

# The 20 requested variables, in panel order, plus the 6 bookkeeping columns.
# Split by fill rule: counts get 0 inside coverage, ratios/averages get NA.
count_cols <- c(
  # N_OUTFALLS_TOTAL is NOT max(MASS, CONC) and NOT their sum: 33,789 of 69,737
  # FY2017 outfall-months report only ONE basis, so the per-basis counts bound
  # the outfall count from neither side. It is supplied explicitly because #21
  # and #22 are counts of distinct outfalls and are uninterpretable without
  # their denominator.
  "N_OUTFALLS_TOTAL",
  "N_OUTFALLS_MASS", "N_OUTFALLS_CONC",
  "N_OUTFALLS_NOLIMIT_ALL", "N_OUTFALLS_NOLIMIT_ANY",
  "N_OUTFALL_BASIS_NOLIMIT", "N_OUTFALL_BASIS_TOTAL",
  "N_MASS_EXCEED_CALC", "N_MASS_EXCEED_EPA",
  "N_CONC_EXCEED_CALC", "N_CONC_EXCEED_EPA",
  "N_OUTFALLS_CENSORED_MASS", "N_OUTFALLS_CENSORED_CONC",
  "N_OUTFALLS_NO_DISCHARGE", "N_OUTFALLS_ACTIVE",
  "N_OUTFALLS_NODI_UNCLASSIFIED",
  "N_OUTFALL_BASIS_MULTIMONTH", "N_OUTFALL_BASIS_UNEXPLAINED_BLANK",
  # Physically impossible reported values, counted but NOT corrected or dropped
  # (ASSUMPTION 13). Condition on this column to exclude them.
  "N_OUTFALL_BASIS_NEGATIVE"
)
sum_cols <- c("MASS_DISCHARGED_TOTAL", "MASS_DISCHARGED_LIMITED",
              "MASS_PERMITTED_TOTAL", "MASS_EXCEED_TOTAL")
avg_cols <- c("MASS_RATIO_POOLED", "MASS_RATIO_AVG", "MASS_EXCEED_AVG_PROP",
              "CONC_RATIO_AVG", "CONC_EXCEED_AVG_PROP")
var_cols <- c(count_cols, sum_cols, avg_cols)
all_new  <- c("DMR_TSS_DROPPED_MULTISET", var_cols)

if (!dir.exists(TBL_DIR)) dir.create(TBL_DIR, recursive = TRUE)

# ------------------------------------------------------------------------------
# safe_mean() / safe_ratio(): the ASSUMPTION 10 rule in one place.
# ------------------------------------------------------------------------------
# An average over an empty set is NA, not 0, and a ratio with a zero or absent
# denominator is NA, not Inf. Writing this once keeps the five average columns
# from drifting apart.
safe_mean <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0L) NA_real_ else mean(x)
}
safe_ratio <- function(num, den) {
  if (!is.finite(den) || den <= 0) NA_real_ else num / den
}

# ==============================================================================
# summarise_dmr_outfall_basis(): the 20 variables, computed from the
# outfall x basis x month grain.
# ------------------------------------------------------------------------------
# Factored into a function for ONE reason: so the user's hand-worked example can
# be run through the exact same code as the real data (STEP 1 below). If a
# definition ever drifts, the fixture fails and the script stops.
#
# EXPECTS a data.table with one row per facility x month x outfall x basis and
# these columns:
#   facility_id, YEAR, MONTH   -- panel keys
#   outfall_uid                -- paste(permit, outfall); see ASSUMPTION 3
#   basis                      -- "MASS" or "CONC"
#   discharge, limit           -- numeric, standard units; NA when absent
#   has_limit, exceeds, censored, reported  -- logical
#   nodi_class                 -- from REF_NODI (ASSUMPTION 8)
#   nmbr_of_report             -- integer
#   e90                        -- logical, EPA's own exceedance flag
#   nodi_blank                 -- logical, NODI_CODE empty
# RETURNS one row per facility_id x YEAR x MONTH with all of var_cols.
# ==============================================================================
summarise_dmr_outfall_basis <- function(obs) {
  stopifnot(all(c("facility_id", "YEAR", "MONTH", "outfall_uid", "basis",
                  "discharge", "limit", "has_limit", "exceeds", "censored",
                  "reported", "nodi_class", "nmbr_of_report", "e90",
                  "nodi_blank") %in% names(obs)))

  # --- Row level: is this outfall-basis a confirmed zero discharge? -----------
  # Either a reported numeric zero, or NODI 'C' (No Discharge). A row that is
  # merely missing for some other reason (lost sample, equipment failure) is
  # NOT a zero -- we don't know what it discharged.
  obs <- copy(obs)
  obs[, zero_discharge := (reported & discharge == 0) | nodi_class == "no_discharge"]
  obs[, positive_discharge := reported & discharge > 0]

  # --- STAGE A: collapse to one row per outfall -------------------------------
  # The nested "every basis / any basis" variables (#5, #6, #21, #22) are
  # outfall-level questions, so they get answered at the outfall level first
  # rather than being squeezed into one grouped expression.
  of <- obs[, .(
    has_mass          = any(basis == "MASS"),
    has_conc          = any(basis == "CONC"),
    all_nolimit       = all(!has_limit),
    any_nolimit       = any(!has_limit),
    all_zero          = all(zero_discharge),
    any_positive      = any(positive_discharge),
    any_active_nodi   = any(nodi_class == "active"),
    any_unclear_nodi  = any(nodi_class == "unclear"),
    censored_mass     = any(basis == "MASS" & censored),
    censored_conc     = any(basis == "CONC" & censored)
  ), by = .(facility_id, YEAR, MONTH, outfall_uid)]

  # #22: discharge > 0 on any basis, OR no discharge but a NODI code that says
  # the outfall is still live (ASSUMPTION 8).
  of[, active := any_positive | any_active_nodi]
  # Outfalls we genuinely cannot classify: nothing positive, nothing that says
  # "active", but at least one of the six unclear codes. Counted, not guessed.
  of[, nodi_unclassified := !active & any_unclear_nodi]

  outfall_lvl <- of[, .(
    N_OUTFALLS_TOTAL             = .N,          # `of` is one row per outfall
    N_OUTFALLS_MASS              = sum(has_mass),
    N_OUTFALLS_CONC              = sum(has_conc),
    N_OUTFALLS_NOLIMIT_ALL       = sum(all_nolimit),
    N_OUTFALLS_NOLIMIT_ANY       = sum(any_nolimit),
    N_OUTFALLS_CENSORED_MASS     = sum(censored_mass),
    N_OUTFALLS_CENSORED_CONC     = sum(censored_conc),
    N_OUTFALLS_NO_DISCHARGE      = sum(all_zero),
    N_OUTFALLS_ACTIVE            = sum(active),
    N_OUTFALLS_NODI_UNCLASSIFIED = sum(nodi_unclassified)
  ), by = .(facility_id, YEAR, MONTH)]

  # --- STAGE B: sums, counts and averages over the outfall-basis rows ---------
  # Note the deliberate asymmetry between MASS_RATIO_POOLED (#10, a ratio of
  # sums) and CONC_RATIO_AVG (#15, an average of ratios): mass is additive
  # across outfalls, concentration is not (docs/panel_questions_for_pis.md).
  # MASS_RATIO_AVG is supplied as the explicit mass-side counterpart so #10's
  # "avg ratio" label is never ambiguous.
  row_lvl <- obs[, {
    m   <- basis == "MASS"
    cc  <- basis == "CONC"
    mL  <- m  & has_limit                  # mass rows carrying a numeric limit
    cL  <- cc & has_limit
    mEx <- m  & exceeds
    cEx <- cc & exceeds

    mass_disch_lim <- sum(discharge[mL], na.rm = TRUE)
    mass_permitted <- sum(limit[mL],     na.rm = TRUE)

    .(
      N_OUTFALL_BASIS_NOLIMIT   = sum(!has_limit),
      N_OUTFALL_BASIS_TOTAL     = .N,
      MASS_DISCHARGED_TOTAL     = sum(discharge[m], na.rm = TRUE),
      MASS_DISCHARGED_LIMITED   = mass_disch_lim,
      MASS_PERMITTED_TOTAL      = mass_permitted,
      MASS_RATIO_POOLED         = safe_ratio(mass_disch_lim, mass_permitted),
      MASS_RATIO_AVG            = safe_mean(discharge[mL] / limit[mL]),
      N_MASS_EXCEED_CALC        = sum(mEx),
      MASS_EXCEED_TOTAL         = sum(discharge[mEx] - limit[mEx]),
      MASS_EXCEED_AVG_PROP      = safe_mean((discharge[mEx] - limit[mEx]) / limit[mEx]),
      N_MASS_EXCEED_EPA         = sum(m  & e90),
      CONC_RATIO_AVG            = safe_mean(discharge[cL] / limit[cL]),
      CONC_EXCEED_AVG_PROP      = safe_mean((discharge[cEx] - limit[cEx]) / limit[cEx]),
      N_CONC_EXCEED_CALC        = sum(cEx),
      N_CONC_EXCEED_EPA         = sum(cc & e90),
      N_OUTFALL_BASIS_MULTIMONTH        = sum(nmbr_of_report > 1L, na.rm = TRUE),
      N_OUTFALL_BASIS_UNEXPLAINED_BLANK = sum(!reported & nodi_blank),
      N_OUTFALL_BASIS_NEGATIVE          = sum(reported & discharge < 0)
    )
  }, by = .(facility_id, YEAR, MONTH)]

  out <- merge(outfall_lvl, row_lvl, by = c("facility_id", "YEAR", "MONTH"))
  setcolorder(out, c("facility_id", "YEAR", "MONTH", var_cols))
  out[]
}

# ==============================================================================
# STEP 1: Self-test against the hand-worked specification.
# ------------------------------------------------------------------------------
# The requested variable list came with a worked example; that example IS the
# spec, so it runs as a test before any real data is touched. Three outfalls,
# each reporting both bases; outfall 003 has a concentration basis with no
# numeric limit and a mass basis that exceeds (20 against a limit of 15).
#   mass:  (10 / 20), (5 / 10), (20 / 15 -> exceeds)   sums: 35 discharged, 45 permitted
#   conc:  (2 / 5), (1 / 3), (4 / no limit)            none exceed
# ==============================================================================
message("=== STEP 1: self-test against the hand-worked example ===")
fixture <- data.table(
  facility_id = "FIX", YEAR = 2017L, MONTH = 1L,
  outfall_uid = c("P-001", "P-002", "P-003", "P-001", "P-002", "P-003"),
  basis       = c("MASS", "MASS", "MASS", "CONC", "CONC", "CONC"),
  discharge   = c(10, 5, 20, 2, 1, 4),
  limit       = c(20, 10, 15, 5, 3, NA_real_),
  censored    = FALSE,
  reported    = TRUE,
  nodi_class  = "none",
  nodi_blank  = TRUE,
  nmbr_of_report = 1L
)
fixture[, has_limit := !is.na(limit)]
fixture[, exceeds   := has_limit & discharge > limit]
fixture[, e90       := exceeds]           # EPA agrees with us in the example
fx <- summarise_dmr_outfall_basis(fixture)

stopifnot(
  nrow(fx) == 1L,
  fx$N_OUTFALLS_TOTAL             == 3L,        #  distinct outfalls
  fx$N_OUTFALLS_MASS              == 3L,        #  3
  fx$N_OUTFALLS_CONC              == 3L,        #  4
  fx$N_OUTFALLS_NOLIMIT_ALL       == 0L,        #  5
  fx$N_OUTFALLS_NOLIMIT_ANY       == 1L,        #  6
  fx$N_OUTFALL_BASIS_NOLIMIT      == 1L,        #  6b
  fx$N_OUTFALL_BASIS_TOTAL        == 6L,
  fx$MASS_DISCHARGED_TOTAL        == 35,        #  7
  fx$MASS_DISCHARGED_LIMITED      == 35,        #  8
  fx$MASS_PERMITTED_TOTAL         == 45,        #  9
  isTRUE(all.equal(fx$MASS_RATIO_POOLED, 35/45)),                     # 10
  isTRUE(all.equal(fx$MASS_RATIO_AVG, mean(c(10/20, 5/10, 20/15)))),  # 10b
  fx$N_MASS_EXCEED_CALC           == 1L,        # 11
  fx$MASS_EXCEED_TOTAL            == 5,         # 12
  isTRUE(all.equal(fx$MASS_EXCEED_AVG_PROP, (20-15)/15)),             # 13
  fx$N_MASS_EXCEED_EPA            == 1L,        # 14
  isTRUE(all.equal(fx$CONC_RATIO_AVG, (2/5 + 1/3)/2)),                # 15
  is.na(fx$CONC_EXCEED_AVG_PROP),               # 16 -- NA, not 0 (ASSUMPTION 10)
  fx$N_CONC_EXCEED_CALC           == 0L,        # 17
  fx$N_CONC_EXCEED_EPA            == 0L,        # 18
  fx$N_OUTFALLS_CENSORED_MASS     == 0L,        # 19
  fx$N_OUTFALLS_CENSORED_CONC     == 0L,        # 20
  fx$N_OUTFALLS_NO_DISCHARGE      == 0L,        # 21
  fx$N_OUTFALLS_ACTIVE            == 3L,        # 22
  fx$N_OUTFALL_BASIS_NEGATIVE     == 0L         #  data-quality counter
)
message("  all 25 expected values match the worked example.")

# ==============================================================================
# STEP 2: Read the filtered FY DMR file and apply the three new filters.
# ==============================================================================
if (!file.exists(DMR_PATH))
  stop("Filtered DMR file not found: ", DMR_PATH,
       "\n  Run the code/dmr/ pipeline steps 1-3 for FY", FY, " first",
       " (see PREREQUISITE in this script's header).")

keep <- c("EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_NMBR", "PERM_FEATURE_TYPE_CODE",
          "LIMIT_SET_ID", "LIMIT_SET_DESIGNATOR", "VERSION_NMBR",
          "MONITORING_PERIOD_END_DATE", "MONITORING_LOCATION_CODE",
          "PARAMETER_CODE", "STATISTICAL_BASE_CODE", "VALUE_TYPE_CODE",
          "NMBR_OF_REPORT",
          "DMR_VALUE_STANDARD_UNITS", "DMR_VALUE_QUALIFIER_CODE",
          "LIMIT_VALUE_STANDARD_UNITS", "LIMIT_VALUE_QUALIFIER_CODE",
          "NODI_CODE", "VIOLATION_CODE")

message("\n=== STEP 2: reading ", basename(DMR_PATH), " ===")
d <- fread(DMR_PATH, select = keep, colClasses = "character", showProgress = FALSE)
n_read <- nrow(d)
for (j in keep) d[[j]] <- trimws(d[[j]])

# Guard: the upstream pipeline is supposed to have already fixed these two.
stopifnot(all(d$PARAMETER_CODE == F_PARAM),
          all(d$MONITORING_LOCATION_CODE %in% F_MONLOC))

n_feat_other <- sum(d$PERM_FEATURE_TYPE_CODE != F_FEATURE)
d <- d[PERM_FEATURE_TYPE_CODE == F_FEATURE]                        # ASSUMPTION 3
n_after_feat <- nrow(d)

n_base_other <- sum(d$STATISTICAL_BASE_CODE != F_STAT_BASE)
d <- d[STATISTICAL_BASE_CODE == F_STAT_BASE]                       # ASSUMPTION 2
n_after_base <- nrow(d)

n_vt_other <- sum(!d$VALUE_TYPE_CODE %in% c(BASIS_MASS, BASIS_CONC))
d <- d[VALUE_TYPE_CODE %in% c(BASIS_MASS, BASIS_CONC)]             # ASSUMPTION 2
n_in_scope <- nrow(d)

if (n_in_scope == 0L) stop("No in-scope rows survived the filters -- check the input file.")

# --- Dates: period-end month (ASSUMPTION 9), restricted to the FY window ------
d[, period_end := mdy(MONITORING_PERIOD_END_DATE)]
n_bad_date <- sum(is.na(d$period_end))
d <- d[!is.na(period_end)]
n_outside_fy <- sum(d$period_end < FY_START | d$period_end > FY_END)
d <- d[period_end >= FY_START & period_end <= FY_END]
d[, `:=`(YEAR = year(period_end), MONTH = month(period_end))]

# ==============================================================================
# STEP 3: De-duplicate to one row per (permit, outfall, month, basis).
# ==============================================================================
message("\n=== STEP 3: de-duplication and the multi-limit-set permit drop ===")
d[, VERSION_NMBR_I := suppressWarnings(as.integer(VERSION_NMBR))]
setkey(d, EXTERNAL_PERMIT_NMBR, PERM_FEATURE_NMBR, period_end, VALUE_TYPE_CODE)
KEYCOLS <- c("EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_NMBR", "period_end", "VALUE_TYPE_CODE")

# 3a. DMR resubmissions: keep the latest VERSION_NMBR within each key. Same
#     intent as the latest-version de-dup in
#     code/02_cleaning/build_effluent_violations_npdes_month_panel.R.
d[, max_ver := max(VERSION_NMBR_I, na.rm = TRUE), by = KEYCOLS]
n_old_version <- sum(d$VERSION_NMBR_I < d$max_ver, na.rm = TRUE)
d <- d[is.na(VERSION_NMBR_I) | VERSION_NMBR_I == max_ver]

# 3b. Exact duplicate rows within a single limit set (same number reported twice).
before <- nrow(d)
d <- unique(d, by = c(KEYCOLS, "LIMIT_SET_ID", "DMR_VALUE_STANDARD_UNITS",
                      "LIMIT_VALUE_STANDARD_UNITS"))
n_exact_dup <- before - nrow(d)

# 3c. ASSUMPTION 4 -- residual duplicates mean two or more limit sets govern the
#     same outfall-basis-month. Drop those PERMITS whole, and log them.
d[, n_sets_in_key := uniqueN(LIMIT_SET_ID), by = KEYCOLS]
multiset_keys   <- d[n_sets_in_key > 1L]
bad_permits     <- unique(multiset_keys$EXTERNAL_PERMIT_NMBR)
n_keys_total    <- uniqueN(d, by = KEYCOLS)
n_keys_multiset <- uniqueN(multiset_keys, by = KEYCOLS)
n_permits_total <- uniqueN(d$EXTERNAL_PERMIT_NMBR)
n_rows_dropped  <- sum(d$EXTERNAL_PERMIT_NMBR %in% bad_permits)

if (length(bad_permits) > 0L) {
  dropped_log <- d[EXTERNAL_PERMIT_NMBR %in% bad_permits, .(
    n_outfalls    = uniqueN(PERM_FEATURE_NMBR),
    n_months      = uniqueN(period_end),
    n_limit_sets  = uniqueN(LIMIT_SET_ID),
    limit_sets    = paste(sort(unique(LIMIT_SET_DESIGNATOR)), collapse = "/"),
    n_rows        = .N,
    n_keys_multiset = uniqueN(.SD[n_sets_in_key > 1L], by = c("PERM_FEATURE_NMBR",
                                "period_end", "VALUE_TYPE_CODE"))
  ), by = EXTERNAL_PERMIT_NMBR][order(-n_rows)]
  dropped_path <- file.path(TBL_DIR,
    sprintf("dmr_fy%d_dropped_multiset_permits_%s.csv", FY, STAMP))
  fwrite(dropped_log, dropped_path)
} else {
  dropped_path <- NA_character_
}

d <- d[!EXTERNAL_PERMIT_NMBR %in% bad_permits]
if (nrow(d) == 0L) stop("Every in-scope permit was dropped by the multi-limit-set rule.")

# Grain is now guaranteed unique -- assert it rather than hope.
stopifnot(!any(duplicated(d, by = KEYCOLS)))

# ==============================================================================
# STEP 4: Derive the row-level fields the summary function needs.
# ==============================================================================
d[, discharge := suppressWarnings(as.numeric(DMR_VALUE_STANDARD_UNITS))]  # ASSUMPTION 5
d[, limit     := suppressWarnings(as.numeric(LIMIT_VALUE_STANDARD_UNITS))]
d[, has_limit := !is.na(limit)]
d[, reported  := !is.na(discharge)]
d[, censored  := DMR_VALUE_QUALIFIER_CODE %in% CENSOR_CODES]              # ASSUMPTION 7
d[, e90       := VIOLATION_CODE == "E90"]
d[, nodi_blank := NODI_CODE == ""]
d[, nmbr_of_report := suppressWarnings(as.integer(NMBR_OF_REPORT))]
d[, basis     := fifelse(VALUE_TYPE_CODE == BASIS_MASS, "MASS", "CONC")]
d[, outfall_uid := paste(EXTERNAL_PERMIT_NMBR, PERM_FEATURE_NMBR, sep = "-")]  # ASSUMPTION 3

# ASSUMPTION 6 -- verify the limit direction instead of trusting it. TSS limits
# are ceilings ('<='); a floor ('>=') would need the opposite exceedance test,
# so we refuse to guess and stop if any appear.
floor_rows <- d[has_limit & LIMIT_VALUE_QUALIFIER_CODE %in% c(">", ">="), .N]
qual_tab   <- d[(has_limit), .N, by = LIMIT_VALUE_QUALIFIER_CODE][order(-N)]
loc_tab    <- d[, .N, by = MONITORING_LOCATION_CODE][order(-N)]
if (floor_rows > 0L) {
  print(qual_tab)
  stop("Found ", floor_rows, " numeric-limit rows with a FLOOR qualifier (>, >=). ",
       "The exceedance test below assumes ceilings. Resolve before proceeding ",
       "(see ASSUMPTION 6).")
}
d[, exceeds := has_limit & reported & discharge > limit]

# ASSUMPTION 13 -- NEGATIVE REPORTED VALUES ARE SURFACED, NOT CORRECTED.
# A negative TSS mass or concentration is physically impossible, but it is what
# the facility reported, and silently dropping or zeroing it would hide a real
# data-quality problem (the same class of problem code/dmr/eff_flagged.R exists
# to catch). The rows stay in, are counted in N_OUTFALL_BASIS_NEGATIVE, and are
# written out in full so the decision of what to do about them stays the PI's.
# Note they can drag MASS_RATIO_POOLED / CONC_RATIO_AVG below zero -- condition
# on N_OUTFALL_BASIS_NEGATIVE == 0 to exclude.
neg <- d[reported & discharge < 0]
n_negative <- nrow(neg)
if (n_negative > 0L) {
  neg_path <- file.path(TBL_DIR, sprintf("dmr_fy%d_negative_values_%s.csv", FY, STAMP))
  fwrite(neg[, .(NPDES_ID = EXTERNAL_PERMIT_NMBR, PERM_FEATURE_NMBR, period_end,
                 basis, VALUE_TYPE_CODE, discharge, limit,
                 DMR_VALUE_QUALIFIER_CODE, NODI_CODE, LIMIT_SET_DESIGNATOR)], neg_path)
} else neg_path <- NA_character_

# ASSUMPTION 8 -- NODI classes from the reference table; stop on an unknown code.
nodi <- fread(NODI_PATH, colClasses = "character", showProgress = FALSE)
nodi[, NODI_CODE := trimws(NODI_CODE)]
unknown_nodi <- setdiff(unique(d[NODI_CODE != "", NODI_CODE]), nodi$NODI_CODE)
if (length(unknown_nodi) > 0L)
  stop("FY", FY, " contains NODI codes absent from ", basename(NODI_PATH), ": ",
       paste(unknown_nodi, collapse = ", "),
       "\n  Add them (with an explicit NODI_ACTIVITY_CLASS) rather than letting ",
       "them fall through (see ASSUMPTION 8).")
d <- nodi[, .(NODI_CODE, nodi_class = NODI_ACTIVITY_CLASS)][d, on = "NODI_CODE"]
d[NODI_CODE == "", nodi_class := "none"]

# ==============================================================================
# STEP 5: Route permits to facilities, then compute the 20 variables.
# ==============================================================================
message("\n=== STEP 5: routing to facilities and summarising ===")
xwalk <- build_facility_crosswalk(raw_dir = RAW_DIR)                   # ASSUMPTION 11
setnames(d, "EXTERNAL_PERMIT_NMBR", "NPDES_ID")
n_before_route <- nrow(d)
d <- xwalk[d, on = "NPDES_ID", nomatch = 0]
n_unrouted <- n_before_route - nrow(d)

# Facilities touched by a dropped permit are flagged and will be forced to NA:
# a partial facility total would understate discharge silently (ASSUMPTION 4).
flagged_fac <- if (length(bad_permits) > 0L) {
  unique(xwalk[NPDES_ID %in% bad_permits, facility_id])
} else character(0)

# Write the auditable intermediate at the clean outfall x basis x month grain.
# Written AFTER routing so it carries facility_id and can be joined straight
# back to the panel -- every panel cell is reproducible from this file alone.
fwrite(d[, .(facility_id, NPDES_ID, PERM_FEATURE_NMBR, outfall_uid, period_end,
             MONITORING_LOCATION_CODE,
             YEAR, MONTH, basis, VALUE_TYPE_CODE, LIMIT_SET_ID, LIMIT_SET_DESIGNATOR,
             discharge, limit, has_limit, reported, censored, exceeds, e90,
             NODI_CODE, nodi_class, nmbr_of_report)], GRAIN_PATH)

summ <- summarise_dmr_outfall_basis(d)

# ==============================================================================
# STEP 6: Attach to the panel.
# ==============================================================================
message("\n=== STEP 6: attaching to the step-06 panel ===")
panel <- fread(IN_PATH, colClasses = "character", showProgress = FALSE)
panel[, `:=`(YEAR = as.integer(YEAR), MONTH = as.integer(MONTH))]
n_panel_rows_in <- nrow(panel)
n_panel_cols_in <- ncol(panel)

# Facility-months present in the DMR data but ABSENT from the panel spine drop
# silently in the left join below -- the panel's membership is narrower than
# "ever-major individual permit in ICIS_PERMITS" (step 01 additionally requires
# a permit window overlapping 2005-2025 or independent proxy evidence). Same
# behaviour as step 06, but measured here rather than assumed away.
spine <- unique(panel[, .(facility_id = FACILITY_UIN, YEAR, MONTH)])
unmatched     <- unique(summ[, .(facility_id, YEAR, MONTH)])[!spine, on = .(facility_id, YEAR, MONTH)]
n_unmatched_fm <- nrow(unmatched)
n_unmatched_fac <- uniqueN(unmatched$facility_id)
n_summ_fm      <- nrow(summ)

panel <- summ[panel, on = c(facility_id = "FACILITY_UIN", "YEAR", "MONTH")]
setnames(panel, "facility_id", "FACILITY_UIN")

# Coverage (ASSUMPTION 1): inside the FY window, and the facility was not
# compromised by the multi-limit-set drop.
panel[, in_fy := (YEAR == 2016L & MONTH >= 10L) | (YEAR == 2017L & MONTH <= 9L)]
panel[, DMR_TSS_DROPPED_MULTISET := as.integer(FACILITY_UIN %in% flagged_fac)]
# `covered_` is INTERNAL ONLY -- it drives the fill rules below and is dropped
# before the panel is written. It is not an output column because it is exactly
# recoverable: !is.na(N_OUTFALL_BASIS_TOTAL) is bit-for-bit identical to it
# (verified), since every covered facility-month has N_OUTFALL_BASIS_TOTAL >= 1
# and every uncovered one has NA in all 28 variables.
panel[, covered_ := in_fy & !is.na(N_OUTFALL_BASIS_TOTAL) &
                    DMR_TSS_DROPPED_MULTISET == 0L]

# Inside coverage a reported-but-absent quantity is a true 0 for COUNTS only;
# every ratio/average keeps the NA that summarise_dmr_outfall_basis() produced.
# Outside coverage EVERYTHING is NA -- no DMR report is not a measured zero.
for (cl in c(count_cols, sum_cols)) {
  panel[(covered_) & is.na(get(cl)), (cl) := 0]
}
for (cl in var_cols) {
  panel[(!covered_), (cl) := NA]
}
n_covered <- sum(panel$covered_)
panel[, c("in_fy", "covered_") := NULL]

# New block goes at the very end, after n_E90.
setcolorder(panel, c(setdiff(names(panel), all_new), all_new))
setorder(panel, FACILITY_UIN, YEAR, MONTH)

stopifnot(nrow(panel) == n_panel_rows_in,
          n_covered == nrow(panel[!is.na(N_OUTFALL_BASIS_TOTAL)]),
          !any(duplicated(panel, by = c("FACILITY_UIN", "YEAR", "MONTH"))))

fwrite(panel, OUT_PATH)

# ==============================================================================
# STEP 7: Run log (sanity checks).
# ==============================================================================
# Our exceedance test vs EPA's E90 flag -- reported, never reconciled
# (ASSUMPTION 6 and the project's "don't silently fix changing results" rule).
disagree <- d[exceeds != e90]
if (nrow(disagree) > 0L) {
  dis_path <- file.path(TBL_DIR, sprintf("dmr_fy%d_exceed_disagreements_%s.csv", FY, STAMP))
  fwrite(disagree[, .(NPDES_ID, PERM_FEATURE_NMBR, period_end, basis,
                      discharge, limit, exceeds, e90, VIOLATION_CODE,
                      DMR_VALUE_QUALIFIER_CODE, NODI_CODE)], dis_path)
} else dis_path <- NA_character_

# Covered rows, identified the same way a downstream user would:
cov <- panel[!is.na(N_OUTFALL_BASIS_TOTAL)]

message("\n=== 07_add_dmr: FY", FY, " DMR variables attached to the month panel ===")
message("Rows read from filtered DMR file          : ", format(n_read, big.mark = ","))
message("  dropped, not ", F_FEATURE, " (internal/other feature) : ", format(n_feat_other, big.mark = ","),
        "  -> ", format(n_after_feat, big.mark = ","))
message("  dropped, STATISTICAL_BASE_CODE != ", F_STAT_BASE, "    : ", format(n_base_other, big.mark = ","),
        "  -> ", format(n_after_base, big.mark = ","))
message("  dropped, VALUE_TYPE_CODE not ", BASIS_MASS, "/", BASIS_CONC, "    : ", format(n_vt_other, big.mark = ","),
        "  -> ", format(n_in_scope, big.mark = ","), " in scope")
message("  unparseable period-end dates            : ", n_bad_date)
message("  outside FY", FY, " (", FY_START, " .. ", FY_END, ")      : ", format(n_outside_fy, big.mark = ","))
message("De-dup: superseded versions removed       : ", format(n_old_version, big.mark = ","))
message("De-dup: exact duplicate rows removed      : ", format(n_exact_dup, big.mark = ","))
message("Multi-limit-set keys                      : ", format(n_keys_multiset, big.mark = ","),
        " of ", format(n_keys_total, big.mark = ","),
        sprintf(" (%.2f%%)", 100 * n_keys_multiset / n_keys_total))
message("Permits dropped whole (ASSUMPTION 4)      : ", format(length(bad_permits), big.mark = ","),
        " of ", format(n_permits_total, big.mark = ","),
        sprintf(" (%.2f%%)", 100 * length(bad_permits) / n_permits_total))
message("  ...rows lost to that drop               : ", format(n_rows_dropped, big.mark = ","),
        sprintf(" (%.2f%% of in-scope rows)", 100 * n_rows_dropped / n_in_scope))
message("  ...facilities flagged (forced to NA)    : ", length(flagged_fac))
message("Rows with no facility match (dropped)     : ", format(n_unrouted, big.mark = ","))
message("Facility-months in DMR but NOT in the panel spine: ",
        format(n_unmatched_fm, big.mark = ","), " of ", format(n_summ_fm, big.mark = ","),
        " (", n_unmatched_fac, " facilities) -- dropped by the join, see STEP 6 comment")
message("NEGATIVE reported values (impossible, kept): ", format(n_negative, big.mark = ","),
        if (!is.na(neg_path)) paste0("  -> ", basename(neg_path)) else "",
        "\n  (ASSUMPTION 13: counted in N_OUTFALL_BASIS_NEGATIVE, not corrected;",
        " they can push ratio columns below zero)")
message("Clean outfall-basis-month rows            : ", format(nrow(d), big.mark = ","))
message("  by MONITORING_LOCATION_CODE             : ",
        paste(sprintf("%s=%s", loc_tab$MONITORING_LOCATION_CODE,
                      format(loc_tab$N, big.mark = ",")), collapse = "  "),
        "   (both decode to Effluent Gross -- ASSUMPTION 2b)")
message("  distinct outfalls                       : ", format(uniqueN(d$outfall_uid), big.mark = ","))
message("  distinct facilities                     : ", format(uniqueN(d$facility_id), big.mark = ","))
message("Limit-qualifier breakdown (numeric limits):")
print(qual_tab)
message("Covered facility-months (BASIS_TOTAL non-NA): ", format(nrow(cov), big.mark = ","))
message("  of ", format(n_panel_rows_in, big.mark = ","), " panel rows (",
        sprintf("%.2f%%", 100 * nrow(cov) / n_panel_rows_in), ")")
message("MASS_DISCHARGED_TOTAL (kg/d, summed)      : ",
        format(round(sum(as.numeric(cov$MASS_DISCHARGED_TOTAL), na.rm = TRUE), 1), big.mark = ","))
message("MASS_PERMITTED_TOTAL  (kg/d, summed)      : ",
        format(round(sum(as.numeric(cov$MASS_PERMITTED_TOTAL), na.rm = TRUE), 1), big.mark = ","))
message("Mass exceedances  (ours / EPA E90)        : ",
        sum(as.integer(cov$N_MASS_EXCEED_CALC), na.rm = TRUE), " / ",
        sum(as.integer(cov$N_MASS_EXCEED_EPA),  na.rm = TRUE))
message("Conc exceedances  (ours / EPA E90)        : ",
        sum(as.integer(cov$N_CONC_EXCEED_CALC), na.rm = TRUE), " / ",
        sum(as.integer(cov$N_CONC_EXCEED_EPA),  na.rm = TRUE))
message("Row-level exceedance disagreements        : ", nrow(disagree),
        " of ", format(nrow(d), big.mark = ","),
        if (!is.na(dis_path)) paste0("  -> ", basename(dis_path)) else "")
message("Outfall-MONTHS: active / no-disch / unclear : ",
        sum(as.integer(cov$N_OUTFALLS_ACTIVE), na.rm = TRUE), " / ",
        sum(as.integer(cov$N_OUTFALLS_NO_DISCHARGE), na.rm = TRUE), " / ",
        sum(as.integer(cov$N_OUTFALLS_NODI_UNCLASSIFIED), na.rm = TRUE))
message("Outfall-basis cells with no numeric limit : ",
        sum(as.integer(cov$N_OUTFALL_BASIS_NOLIMIT), na.rm = TRUE), " of ",
        sum(as.integer(cov$N_OUTFALL_BASIS_TOTAL), na.rm = TRUE))
message("Multi-month (NMBR_OF_REPORT > 1) cells    : ",
        sum(as.integer(cov$N_OUTFALL_BASIS_MULTIMONTH), na.rm = TRUE))
message("Unexplained blank cells (no value, no NODI): ",
        sum(as.integer(cov$N_OUTFALL_BASIS_UNEXPLAINED_BLANK), na.rm = TRUE))
message("Censored outfalls (mass / conc)           : ",
        sum(as.integer(cov$N_OUTFALLS_CENSORED_MASS), na.rm = TRUE), " / ",
        sum(as.integer(cov$N_OUTFALLS_CENSORED_CONC), na.rm = TRUE),
        "   (ASSUMPTION 7: discharge sums are upper bounds for these)")
message("Panel rows: ", format(nrow(panel), big.mark = ","),
        " (unchanged) | columns: ", n_panel_cols_in, " -> ", ncol(panel))
if (!is.na(dropped_path)) message("Dropped-permit log : ", dropped_path)
message("Grain intermediate : ", GRAIN_PATH)
message("Written to         : ", OUT_PATH)
