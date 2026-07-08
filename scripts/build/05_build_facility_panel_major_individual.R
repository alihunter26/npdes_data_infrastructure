# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# build_facility_panel_major_individual.R
# ------------------------------------------------------------------------------
# Build a FACILITY-by-YEAR panel of facilities that were MAJOR their entire
# permitted life under an INDIVIDUAL permit, and that had at least one
# enforcement action while active. Facilities may ENTER and EXIT the window.
#
#   Unit of analysis : FRS facility (FACILITY_UIN)
#   Population        : facilities whose INDIVIDUAL (NPD) permits were MAJOR in
#                       every year they were permitted during 2005-2025 and
#                       NEVER minor (major "their whole life"). Entry after 2005
#                       and exit before 2025 are allowed -> NOT survival-selected.
#   Inclusion rule    : >=1 enforcement action (formal OR informal) during the
#                       facility's active-major years
#   Spine            : UNBALANCED = each included facility x the years it was an
#                       active major individual permit (its held-major years)
#
# LABELED ASSUMPTIONS (read before using results):
#   1. SELECTED SAMPLE. Conditioned on enforcement -> supports descriptive claims
#      about *enforced* always-major facilities, NOT population-level or causal
#      inference about all such facilities.
#   2. MAJOR-BY-YEAR, NEVER MINOR. Major/minor status is reconstructed per year
#      from ICIS_PERMITS version dates (most recent version effective by each
#      year, carried forward, held until the latest expiration). A facility
#      qualifies iff it is never minor in any held year and is major at least
#      once. Entry/exit allowed; no requirement to span the full window.
#   3. FACILITY-LEVEL STATUS. A facility-year is "major" if AT LEAST ONE of its
#      individual permits is major that year; "minor" only if it is permitted but
#      has NO major permit. So a facility that keeps one always-major permit is
#      NOT disqualified by another permit going minor. (Affects only the ~1% of
#      facilities with >1 permit.)
#   4. SNAPSHOT ATTRIBUTES. Location, NAICS, SIC are taken from one representative
#      record / primary code and broadcast across the facility's years.
#   5. ENFORCEMENT SCOPE. Only actions on the facility's individual permits are
#      counted (not any general-permit coverage the site also holds), and only
#      those occurring in the facility's active-major years.
#
# Source: EPA ECHO bulk "ICIS-NPDES" download (files already unzipped locally).
# Output: data/processed/facility_panel_major_individual_2005_2025.csv
# Deterministic (no stochastic steps); rebuilt entirely from raw + this script.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)   # fast reads + rolling join for the by-year reconstruction
  library(lubridate)    # date parsing
})

## ---- Config (edit here) ----
YEAR_MIN <- 2005L
YEAR_MAX <- 2025L
RAW_DIR  <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
OUT_PATH <- file.path(CWA_ROOT, "data/processed/facility_panel_major_individual_2005_2025.csv")

# Read only the columns we need, everything as character.
rd <- function(file, cols) fread(file.path(RAW_DIR, file), select = cols,
                                 colClasses = "character", showProgress = FALSE)

# ---- 1. Reconstruct major/minor status by year (individual permits) ----------
pv <- rd("ICIS_PERMITS.csv",
         c("EXTERNAL_PERMIT_NMBR", "PERMIT_TYPE_CODE", "MAJOR_MINOR_STATUS_FLAG",
           "EFFECTIVE_DATE", "ISSUE_DATE", "ORIGINAL_ISSUE_DATE",
           "EXPIRATION_DATE", "TERMINATION_DATE"))
pv <- pv[trimws(PERMIT_TYPE_CODE) == "NPD"]
pv[, id   := trimws(EXTERNAL_PERMIT_NMBR)]
pv[, flag := trimws(MAJOR_MINOR_STATUS_FLAG)]
pv[, eff_year := year(fcoalesce(mdy(EFFECTIVE_DATE, quiet = TRUE),
                                mdy(ISSUE_DATE, quiet = TRUE),
                                mdy(ORIGINAL_ISSUE_DATE, quiet = TRUE)))]
pv[, exp_year := year(fcoalesce(mdy(EXPIRATION_DATE, quiet = TRUE),
                                mdy(TERMINATION_DATE, quiet = TRUE)))]
pv <- pv[!is.na(eff_year) & flag %in% c("M", "N")]

held_end <- pv[, .(held_end = max(fifelse(is.na(exp_year), YEAR_MAX, exp_year))), by = id]
vf <- pv[, .(flag = if (any(flag == "N")) "N" else "M"), by = .(id, eff_year)]  # minor wins in-year
setkey(vf, id, eff_year)
grid   <- CJ(id = unique(vf$id), year = YEAR_MIN:YEAR_MAX)
status <- vf[grid, on = .(id, eff_year = year), roll = Inf]     # carry-forward
setnames(status, "eff_year", "year")
status <- held_end[status, on = "id"]
status[, ymm := fifelse(!is.na(flag) & year <= held_end, flag, NA_character_)]
status <- status[!is.na(ymm), .(NPDES_ID = id, year, ymm)]      # held permit-years only

# ---- 2. Crosswalk NPDES_ID -> FACILITY_UIN + facility attributes --------------
fac <- rd("ICIS_FACILITIES.csv",
          c("NPDES_ID", "FACILITY_UIN", "FACILITY_NAME", "LOCATION_ADDRESS",
            "CITY", "STATE_CODE", "ZIP", "COUNTY_CODE",
            "GEOCODE_LATITUDE", "GEOCODE_LONGITUDE"))
fac[, `:=`(NPDES_ID = trimws(NPDES_ID), FACILITY_UIN = trimws(FACILITY_UIN))]
fac <- fac[FACILITY_UIN != "" & NPDES_ID %in% status$NPDES_ID]   # individual permits only
xwalk <- unique(fac[, .(NPDES_ID, FACILITY_UIN)])

# ---- 3. Facility-year status -> qualifying facilities + unbalanced spine ------
fstat <- xwalk[status, on = "NPDES_ID", nomatch = 0]
# Major dominates: a facility-year is major if ANY individual permit is major
# that year; "minor" only if permitted with no major permit. (So one always-major
# permit is not disqualified by another permit at the facility going minor.)
fac_year <- fstat[, .(fac = if (any(ymm == "M")) "M" else "N"), by = .(FACILITY_UIN, year)]

qual_fac <- fac_year[, .(never_minor = !any(fac == "N"),
                         ever_major  =  any(fac == "M")), by = FACILITY_UIN
                    ][never_minor & ever_major, FACILITY_UIN]

spine_all <- fac_year[fac == "M" & FACILITY_UIN %in% qual_fac, .(FACILITY_UIN, year)]

# ---- 4. Enforcement actions -> facility-year ---------------------------------
formal <- rd("NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv",
             c("NPDES_ID", "SETTLEMENT_ENTERED_DATE", "ENF_TYPE_DESC",
               "FED_PENALTY_ASSESSED_AMT", "STATE_LOCAL_PENALTY_AMT"))
formal <- formal[, .(NPDES_ID = trimws(NPDES_ID),
                     year = year(mdy(SETTLEMENT_ENTERED_DATE, quiet = TRUE)),
                     enf_type = ENF_TYPE_DESC,
                     fed_pen = suppressWarnings(as.numeric(FED_PENALTY_ASSESSED_AMT)),
                     sl_pen  = suppressWarnings(as.numeric(STATE_LOCAL_PENALTY_AMT)),
                     kind = "formal")]
informal <- rd("NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv",
               c("NPDES_ID", "ACHIEVED_DATE", "ENF_TYPE_DESC"))
informal <- informal[, .(NPDES_ID = trimws(NPDES_ID),
                         year = year(mdy(ACHIEVED_DATE, quiet = TRUE)),
                         enf_type = ENF_TYPE_DESC, fed_pen = NA_real_, sl_pen = NA_real_,
                         kind = "informal")]
actions <- rbind(formal, informal)[!is.na(year) & year >= YEAR_MIN & year <= YEAR_MAX]
actions <- xwalk[actions, on = "NPDES_ID", nomatch = 0]        # route to facility (individual permits)

enf_year <- actions[, .(
    n_formal_actions    = sum(kind == "formal"),
    n_informal_actions  = sum(kind == "informal"),
    n_enf_actions_total = .N,
    fed_penalty         = sum(fed_pen, na.rm = TRUE),
    state_local_penalty = sum(sl_pen,  na.rm = TRUE),
    enf_type_list       = paste(sort(unique(na.omit(enf_type))), collapse = "; ")),
  by = .(FACILITY_UIN, year)]
enf_year[, total_penalty := fed_penalty + state_local_penalty]

# ---- 5. Inclusion: >=1 action within active-major years; final spine ---------
enf_in   <- enf_year[spine_all, on = c("FACILITY_UIN", "year"), nomatch = 0]
included <- unique(enf_in$FACILITY_UIN)
spine    <- spine_all[FACILITY_UIN %in% included]

# ---- 6. Facility attributes (one representative record; primary NAICS/SIC) ----
fac[, has_name := as.integer(!is.na(FACILITY_NAME) & FACILITY_NAME != "")]
setorder(fac, FACILITY_UIN, -has_name)
fac_attr <- unique(fac, by = "FACILITY_UIN")[
  , .(FACILITY_UIN, FACILITY_NAME, LOCATION_ADDRESS, CITY, STATE_CODE, ZIP,
      COUNTY_CODE, FAC_LAT = GEOCODE_LATITUDE, FAC_LONG = GEOCODE_LONGITUDE)]

n_permits <- xwalk[, .(n_individual_permits = uniqueN(NPDES_ID)), by = FACILITY_UIN]

primary <- function(f, col) {
  d <- rd(f, c("NPDES_ID", col, "PRIMARY_INDICATOR_FLAG"))
  d[, NPDES_ID := trimws(NPDES_ID)]
  d <- d[order(NPDES_ID, PRIMARY_INDICATOR_FLAG != "Y")]        # "Y" first
  unique(d, by = "NPDES_ID")[, c("NPDES_ID", col), with = FALSE]
}
naics_fac <- unique(xwalk[primary("NPDES_NAICS.csv", "NAICS_CODE"), on = "NPDES_ID", nomatch = 0]
                    [!is.na(NAICS_CODE), .(FACILITY_UIN, NAICS_CODE)], by = "FACILITY_UIN")
sic_fac   <- unique(xwalk[primary("NPDES_SICS.csv",  "SIC_CODE"),  on = "NPDES_ID", nomatch = 0]
                    [!is.na(SIC_CODE),  .(FACILITY_UIN, SIC_CODE)],  by = "FACILITY_UIN")

# ---- 7. Assemble the panel ----------------------------------------------------
panel <- enf_year[spine, on = c("FACILITY_UIN", "year")]
panel <- fac_attr[panel,  on = "FACILITY_UIN"]
panel <- n_permits[panel, on = "FACILITY_UIN"]
panel <- naics_fac[panel, on = "FACILITY_UIN"]
panel <- sic_fac[panel,   on = "FACILITY_UIN"]
for (c in c("n_formal_actions", "n_informal_actions", "n_enf_actions_total"))
  panel[is.na(get(c)), (c) := 0L]
for (c in c("fed_penalty", "state_local_penalty", "total_penalty"))
  panel[is.na(get(c)), (c) := 0]
panel[is.na(enf_type_list), enf_type_list := ""]
panel[, any_enforcement := as.integer(n_enf_actions_total > 0)]
setcolorder(panel, c("FACILITY_UIN", "year", "FACILITY_NAME", "LOCATION_ADDRESS",
                     "CITY", "STATE_CODE", "ZIP", "COUNTY_CODE", "FAC_LAT", "FAC_LONG",
                     "NAICS_CODE", "SIC_CODE", "n_individual_permits", "any_enforcement",
                     "n_formal_actions", "n_informal_actions", "n_enf_actions_total",
                     "fed_penalty", "state_local_penalty", "total_penalty", "enf_type_list"))
setorder(panel, FACILITY_UIN, year)
fwrite(panel, OUT_PATH)

# ---- 8. Run log --------------------------------------------------------------
yrs_per_fac <- panel[, .N, by = FACILITY_UIN]$N
message("=== facility panel: always-major (never minor), entry/exit allowed ===")
message("Qualifying facilities (never minor, ever major): ", length(qual_fac))
message("Included facilities (>=1 action while active)  : ", length(included))
message("Panel rows (unbalanced)                        : ", nrow(panel))
message("Years per facility: min ", min(yrs_per_fac), " max ", max(yrs_per_fac),
        " (entry/exit -> not all 21)")
message("Written to: ", OUT_PATH)
