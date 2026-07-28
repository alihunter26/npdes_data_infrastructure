# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# Shared cleaning helpers (rd(), coalesce_date_priority()) used below. See
# code/02_cleaning/module_README.md.
source(file.path(CWA_ROOT, "code/02_cleaning/cleaning_helpers.R"))

# ==============================================================================
# use_operating_proxies.R
# ------------------------------------------------------------------------------
# Defines one function, use_operating_proxies(), which is "Layer 2" of the
# FACILITY_OPERATING correction in
# 01_build_facility_month_panel_major_individual.R (that script's LABELED
# ASSUMPTION 10). It used to be written inline inside that script; it was
# pulled out here so that WHICH sources of evidence count as "real activity"
# can be turned on or off from wherever this function is called, without
# editing script 01 itself.
#
# THE PROBLEM THIS SOLVES, IN PLAIN TERMS: a permit's own paperwork dates
# (effective date, expiration date, etc.) can say a facility "closed" years
# before it actually stopped operating. The most common reason is
# PERMIT_STATUS_CODE == "ADC" (Administrative Continuance): the permit is
# legally still active past its nominal expiration date while a renewal
# application is pending, but ICIS has no field that records a facility's TRUE
# open/close dates independent of that paperwork. So instead of trusting the
# paperwork dates alone, this function looks for INDEPENDENT PROOF that a
# facility was still operating -- did anyone inspect it, cite it, or fine it,
# or did it report an effluent violation -- in a month outside its
# paperwork-based window? If so, that month (and everything between it and the
# original window) gets folded in.
#
# MEASURED EVIDENCE THIS IS BASED ON (not hypothetical). On an earlier build of
# 01_build_facility_month_panel_major_individual.R that used the permit-only
# window directly as FACILITY_OPERATING, 12.66% of its FACILITY_OPERATING==0
# rows (32,033 of 253,028) still carried a real recorded event downstream --
# direct proof the facility was active. 75.9% of those were >12 months outside
# the computed window (median 31, max 250 months); 2,381 of 7,511 facilities
# (32%) were affected. ROOT CAUSE (confirmed): permits with PERMIT_STATUS_CODE
# == "ADC" have their EXPIRATION_DATE read as a real closing date by that
# script's ASSUMPTION 2 anyway, since ICIS_PERMITS carries no field marking a
# facility's true open/close independent of permit paperwork. Example:
# facility 110006619212 / permit NH0100455, EXPIRATION_DATE = 01/29/2005,
# PERMIT_STATUS_CODE = "ADC", no TERMINATION_DATE/RETIREMENT_DATE -- its
# permit-only window closes at the start of the panel even though it has real
# recorded events up to 250 months later. 86.7% of the 8,007 permits linked to
# this panel's facilities carry ADC status at some point.
#
# THE FIX, PER FACILITY (per PI decision): extend the window to cover any real
# event, in both directions --
#   new_start = min(permit-window start, first month with a real event)
#   new_end   = max(permit-window end,   last month with a real event)
# FACILITY_OPERATING = 1 iff the month falls in [new_start, new_end]. This can
# only GROW a window, never shrink one -- a facility with zero recorded events
# anywhere keeps its permit-only window unchanged.
#
# WHAT "PROXIES" MEANS HERE: none of these seven sources directly measure
# whether a facility is operating -- they're all indirect evidence
# ("proxies") that it must have been, since none of them can happen at a
# facility that doesn't exist or isn't active. That's also why this function
# is configurable: different proxies carry different amounts of evidentiary
# weight, and different projects may reasonably want to lean on some more than
# others (for example, an inspection is a deliberate visit by a regulator,
# while an effluent violation is self-reported by the facility itself --
# reasonable people could weigh those differently). Turning a source off
# doesn't change the RAW DATA -- it just means this function won't treat
# that source's timing as proof of continued operation.
#
# WHAT THIS FUNCTION DOES NOT DO: it never SHRINKS a facility's permit-based
# window, only grows it -- a facility with no qualifying event from any
# ENABLED source simply keeps its original, permit-only window. And it only
# asks EXISTENCE questions ("did anything happen this month, yes or no") --
# never the full type/agency/code breakdowns scripts 02/04/05/06 go on to
# compute in detail from these same raw sources.
#
# UPDATED 2026-07-28: the proxy-only bounds (`proxy_start_ym`/`proxy_end_ym`)
# used to be a purely internal step toward the union (`new_start_ym`/
# `new_end_ym`) and were discarded before returning. They're now a first-class
# part of the return value -- 01_build_facility_month_panel_major_individual.R
# uses them directly for its own FACILITY_OPERATING_PROXY_WINDOW column, AND
# (since this same date) to decide whether a facility with no permit-window
# overlap should still be admitted to the panel at all. This function's own
# logic is unchanged by that -- it was already computing these bounds, just
# not exposing them.
# ==============================================================================


# ------------------------------------------------------------------------------
# use_operating_proxies(): extend each facility's permit-only active window to
# also cover any month with a real recorded event, from whichever of the seven
# available sources you choose to trust.
# ------------------------------------------------------------------------------
# ARGUMENTS:
#   qual_fac  -- the per-facility candidate table, carrying `facility_id`,
#                `spine_start_ym`, and `spine_end_ym` (the permit-only window,
#                expressed as an integer YEAR*12+MONTH key -- see
#                01_build_facility_month_panel_major_individual.R's STEP 5,
#                where this table is built). As of 2026-07-28, this is called
#                against the FULL candidate population (every "ever major,
#                ever individual" facility), not just facilities whose permit
#                window already overlaps the panel -- so `spine_start_ym`/
#                `spine_end_ym` can legitimately be NA here (permit window
#                doesn't reach 2005-2025 at all). That's fine: the pmin()/
#                pmax() arithmetic below already treats NA as "no permit bound
#                to consider," falling back cleanly to the proxy-only bound.
#   xwalk     -- the NPDES_ID -> facility_id crosswalk (from
#                build_facility_crosswalk() in code/02_cleaning/cleaning_helpers.R).
#   raw_dir   -- folder holding the raw ICIS-NPDES CSVs. Defaults to RAW_DIR.
#   eff_path  -- path to the pre-built condensed effluent panel (see
#                build_effluent_violations_npdes_month_panel.R). Defaults to
#                the project's standard location for that file.
#   year_min, year_max -- the panel's window (default 2005 and 2025, the fixed
#                window this whole project uses -- hardcoded here rather than
#                inherited from a caller's variable, since a bare default
#                referencing e.g. YEAR_MIN could silently fail to find it when
#                this function is called from a script that was itself sourced
#                inside an isolated environment, as run_all.R does for each
#                pipeline step).
#
#   use_inspections, use_ps_violations, use_cs_violations, use_se_violations,
#   use_formal_enforcement, use_informal_enforcement, use_effluent
#     -- one on/off switch per proxy source, ALL DEFAULT TRUE (matching the
#        behavior this function replaced -- calling it with every argument
#        left at its default reproduces script 01's original correction
#        exactly). Turn any of them off to see how much the corrected window
#        depends on that particular kind of evidence, e.g.:
#           use_operating_proxies(qual_fac, xwalk, use_effluent = FALSE)
#        answers "what would the corrected window look like if we didn't
#        trust effluent violations as proof a facility was still operating?"
#
# RETURNS: a COPY of qual_fac (the table you passed in is left untouched) with
# four new columns added, all integer YEAR*12+MONTH keys:
#   proxy_start_ym, proxy_end_ym -- the PROXY-ONLY bounds: earliest/latest month
#     with a real event from any ENABLED source, with NO permit-date influence
#     at all. NA for a facility with zero qualifying events from any enabled
#     source (there is no "earliest/latest" of an empty set) -- this is the
#     column 01_build_facility_month_panel_major_individual.R uses for its own
#     FACILITY_OPERATING_PROXY_WINDOW, and (since 2026-07-28) for deciding
#     whether a facility with no permit-window overlap still belongs in the
#     panel at all.
#   new_start_ym, new_end_ym -- the UNION bounds: `pmin`/`pmax` of the permit
#     window (`spine_start_ym`/`spine_end_ym`) and the proxy-only bounds above,
#     `na.rm = TRUE` throughout so a facility missing EITHER bound (no permit
#     overlap, or no proxy evidence) falls back cleanly to whichever bound it
#     does have. A facility with no qualifying event from any ENABLED source
#     keeps `new_start_ym == spine_start_ym` and `new_end_ym == spine_end_ym`
#     exactly (nothing to extend with); a facility with no permit-window
#     overlap instead keeps `new_start_ym == proxy_start_ym` and
#     `new_end_ym == proxy_end_ym` exactly (nothing to union WITH).
use_operating_proxies <- function(qual_fac, xwalk,
                                   raw_dir = RAW_DIR,
                                   eff_path = file.path(CWA_ROOT, "data/processed/effluent_violations_npdes_month_panel_2005_2025.csv"),
                                   year_min = 2005L,
                                   year_max = 2025L,
                                   use_inspections = TRUE,
                                   use_ps_violations = TRUE,
                                   use_cs_violations = TRUE,
                                   use_se_violations = TRUE,
                                   use_formal_enforcement = TRUE,
                                   use_informal_enforcement = TRUE,
                                   use_effluent = TRUE) {

  # Generic existence-only scan of one raw file: read (NPDES_ID, date
  # column(s)), parse the date the same way the script that later counts this
  # source in full does, keep only the panel window, route NPDES_ID ->
  # facility_id via the crosswalk, and collapse to the distinct set of
  # (facility_id, YEAR, MONTH) that had ANY row -- no counting, no type/
  # agency/code breakouts (those are scripts 02/04/05's job, not this one's).
  event_months <- function(file, date_cols) {
    d <- rd(file, c("NPDES_ID", date_cols), raw_dir = raw_dir)
    d[, NPDES_ID := trimws(NPDES_ID)]
    d[, edate := coalesce_date_priority(d, date_cols)]
    d <- d[!is.na(edate)]
    d[, `:=`(YEAR = year(edate), MONTH = month(edate))]
    d <- d[YEAR >= year_min & YEAR <= year_max]
    d <- xwalk[d, on = "NPDES_ID", nomatch = 0]
    unique(d[, .(facility_id, YEAR, MONTH)])
  }

  # Only scan the sources that are actually switched on -- an R list, built up
  # one entry at a time, so a disabled source costs nothing (its raw file is
  # never even read).
  sources <- list()
  if (use_inspections)
    sources$inspections <- event_months("NPDES_INSPECTIONS.csv",
                                         c("ACTUAL_BEGIN_DATE", "ACTUAL_END_DATE"))
  if (use_ps_violations)
    sources$ps_violations <- event_months("NPDES_PS_VIOLATIONS.csv", "SCHEDULE_DATE")
  if (use_cs_violations)
    sources$cs_violations <- event_months("NPDES_CS_VIOLATIONS.csv", "SCHEDULE_DATE")
  if (use_se_violations)
    sources$se_violations <- event_months("NPDES_SE_VIOLATIONS.csv", "SINGLE_EVENT_VIOLATION_DATE")
  if (use_formal_enforcement)
    sources$formal_enforcement <- event_months("NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv", "SETTLEMENT_ENTERED_DATE")
  if (use_informal_enforcement)
    sources$informal_enforcement <- event_months("NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv", "ACHIEVED_DATE")

  # Effluent is read differently from the other six: it comes from the
  # pre-built condensed panel (one row per NPDES_ID x month, already telling
  # us whether any D80/D90/E90 violation occurred), not a raw file streamed
  # and dated the same way as the other sources. Verified empirically (when
  # this correction was first built) that this condensed panel is a complete
  # proxy for "any effluent event" here, so this function -- like the rest of
  # this pipeline's steps 01-05 -- never needs to stream the raw ~16 GB
  # effluent file directly.
  if (use_effluent) {
    eff <- fread(eff_path, showProgress = FALSE,
                 colClasses = list(character = c("NPDES_ID", "month"),
                                   integer   = c("n_D80", "n_D90", "n_E90")))
    eff[, NPDES_ID := trimws(NPDES_ID)]
    eff[, mdate := as.Date(month)]
    eff <- eff[!is.na(mdate)]
    eff[, `:=`(YEAR = year(mdate), MONTH = month(mdate))]
    eff <- eff[YEAR >= year_min & YEAR <= year_max]
    eff <- eff[n_D80 > 0 | n_D90 > 0 | n_E90 > 0]
    eff <- xwalk[eff, on = "NPDES_ID", nomatch = 0]
    sources$effluent <- unique(eff[, .(facility_id, YEAR, MONTH)])
  }

  # Never modify the caller's own qual_fac by surprise: data.tables are
  # passed around by reference in R, so without this copy(), the `:=` calls
  # below would silently rewrite the ORIGINAL table the caller passed in too.
  qual_fac <- copy(qual_fac)

  if (length(sources) == 0) {
    # No proxy source enabled at all: there is no independent evidence to
    # extend the window with, so the "corrected" window is simply identical
    # to the permit-only one from Layer 1, and there are no proxy-only bounds
    # at all (NA for every facility -- matches the "zero qualifying events"
    # case in the main path below, just for the whole population at once).
    qual_fac[, proxy_start_ym := NA_integer_]
    qual_fac[, proxy_end_ym   := NA_integer_]
    qual_fac[, new_start_ym := spine_start_ym]
    qual_fac[, new_end_ym   := spine_end_ym]
    return(qual_fac[])
  }

  # Combine whichever sources were enabled into one list of (facility_id,
  # YEAR, MONTH) rows -- any row from any enabled source counts as "this
  # facility had SOME real event this month" -- then collapse to the
  # earliest and latest such month per facility.
  event_ym <- unique(rbindlist(sources))
  event_ym[, ym := YEAR * 12L + MONTH]
  event_bounds <- event_ym[, .(event_start = min(ym), event_end = max(ym)), by = facility_id]

  # Attach the proxy-only bounds. Facilities with no event from any enabled
  # source get NA from this join -- kept as NA (not deleted) since, as of
  # 2026-07-28, the caller uses these bounds directly (FACILITY_OPERATING_
  # PROXY_WINDOW, and the eligibility test for facilities with no permit-
  # window overlap), not just as an internal step toward the union below.
  qual_fac <- event_bounds[qual_fac, on = "facility_id"]
  setnames(qual_fac, c("event_start", "event_end"), c("proxy_start_ym", "proxy_end_ym"))

  # Extend the window (per facility) to cover any real event, in both
  # directions. na.rm = TRUE means a facility missing EITHER bound (no permit
  # overlap, or no proxy evidence) falls back cleanly to whichever bound it
  # does have -- this can only GROW a window relative to the permit-only one,
  # never shrink it.
  qual_fac[, new_start_ym := pmin(spine_start_ym, proxy_start_ym, na.rm = TRUE)]
  qual_fac[, new_end_ym   := pmax(spine_end_ym,   proxy_end_ym,   na.rm = TRUE)]
  qual_fac[]
}
