# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# build_permit_panel_major_entryexit.R
# ------------------------------------------------------------------------------
# PERMIT-by-YEAR panel (NPDES_ID x year) of INDIVIDUAL permits that were MAJOR
# their entire permitted life (never minor) during 2005-2025, ALLOWING entry and
# exit. Permit-level analogue of build_facility_panel_major_individual.R.
#
#   Unit of analysis : permit (NPDES_ID)
#   Population        : individual (NPD) permits that were MAJOR in every year
#                       they were permitted during 2005-2025 and NEVER minor
#                       (major "their whole life"). Entry after 2005 and exit
#                       before 2025 are allowed -> NOT survival-selected.
#   Inclusion rule    : >=1 enforcement action (formal OR informal) during the
#                       permit's active-major years
#   Spine            : UNBALANCED = each included permit x the years it was an
#                       active major individual permit
#
# LABELED ASSUMPTIONS (read before using results):
#   1. SELECTED SAMPLE. Conditioned on enforcement -> supports descriptive claims
#      about *enforced* always-major permits, NOT population-level or causal
#      inference about all such permits.
#   2. MAJOR-BY-YEAR, NEVER MINOR. Status is reconstructed per year from
#      ICIS_PERMITS version dates (most recent version effective by each year,
#      carried forward, held until the latest expiration/termination). A permit
#      qualifies iff it is never minor in any held year and major at least once.
#   3. SNAPSHOT ATTRIBUTES. Location, FRS id, NAICS, SIC are taken from one
#      record / primary code and broadcast across the permit's years.
#   4. ENFORCEMENT SCOPE. Only actions occurring in the permit's active-major
#      years are counted (so every included permit has an in-panel action).
#
# Companions: build_permit_panel_major_continuous.R (major EVERY year -> balanced,
# survival-selected) and build_facility_panel_major_individual.R (same rule, FRS
# unit). Deterministic; rebuilt entirely from raw + this script.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
})

YEAR_MIN <- 2005L
YEAR_MAX <- 2025L
RAW  <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
OUT  <- file.path(CWA_ROOT, "data/processed/permit_panel_major_individual_entryexit_2005_2025.csv")

rd <- function(f, cols) fread(file.path(RAW, f), select = cols,
                              colClasses = "character", showProgress = FALSE)

# ---- 1. Reconstruct major/minor status by year (individual permits) -----------
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
vf <- pv[, .(flag = if (any(flag == "N")) "N" else "M"), by = .(id, eff_year)]
setkey(vf, id, eff_year)

grid <- CJ(id = unique(vf$id), year = YEAR_MIN:YEAR_MAX)
status <- vf[grid, on = .(id, eff_year = year), roll = Inf]
setnames(status, "eff_year", "year")
status <- held_end[status, on = "id"]
status[, ymm := fifelse(!is.na(flag) & year <= held_end, flag, NA_character_)]

# ---- 2. Qualifying permits: NEVER minor while permitted, and major at least once
qual <- status[, .(ok = !any(ymm == "N", na.rm = TRUE) & any(ymm == "M", na.rm = TRUE)),
               by = id][ok == TRUE, id]

# ---- 3. Enforcement actions -> permit-year -----------------------------------
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
actions <- actions[NPDES_ID %in% qual]

enf_year <- actions[, .(
    n_formal_actions    = sum(kind == "formal"),
    n_informal_actions  = sum(kind == "informal"),
    n_enf_actions_total = .N,
    fed_penalty         = sum(fed_pen, na.rm = TRUE),
    state_local_penalty = sum(sl_pen,  na.rm = TRUE),
    enf_type_list       = paste(sort(unique(na.omit(enf_type))), collapse = "; ")),
  by = .(NPDES_ID, year)]
enf_year[, total_penalty := fed_penalty + state_local_penalty]

# ---- 4. UNBALANCED spine (active major years) + inclusion on in-window actions
# Spine = each qualifying permit x the years it was an active major permit.
# A permit is INCLUDED only if it had >=1 enforcement action DURING those active
# major years (so every included permit has a real enforcement year in-panel).
spine_all <- status[id %in% qual & ymm == "M", .(NPDES_ID = id, year)]
enf_in    <- enf_year[spine_all, on = c("NPDES_ID", "year"), nomatch = 0]
included  <- unique(enf_in$NPDES_ID)
spine     <- spine_all[NPDES_ID %in% included]

# ---- 5. Permit attributes (location, FRS id, NAICS, SIC) ---------------------
fac <- rd("ICIS_FACILITIES.csv",
          c("NPDES_ID", "FACILITY_UIN", "FACILITY_NAME", "LOCATION_ADDRESS",
            "CITY", "STATE_CODE", "ZIP", "COUNTY_CODE",
            "GEOCODE_LATITUDE", "GEOCODE_LONGITUDE"))
fac[, NPDES_ID := trimws(NPDES_ID)]
setnames(fac, c("FACILITY_UIN", "FACILITY_NAME", "GEOCODE_LATITUDE", "GEOCODE_LONGITUDE"),
              c("REGISTRY_ID", "FAC_NAME", "FAC_LAT", "FAC_LONG"))
fac <- unique(fac, by = "NPDES_ID")

primary <- function(f, col) {
  d <- rd(f, c("NPDES_ID", col, "PRIMARY_INDICATOR_FLAG"))
  d[, NPDES_ID := trimws(NPDES_ID)]
  d <- d[order(NPDES_ID, PRIMARY_INDICATOR_FLAG != "Y")]
  unique(d, by = "NPDES_ID")[, c("NPDES_ID", col), with = FALSE]
}
naics <- primary("NPDES_NAICS.csv", "NAICS_CODE")
sic   <- primary("NPDES_SICS.csv",  "SIC_CODE")

# ---- 6. Assemble --------------------------------------------------------------
panel <- enf_year[spine, on = c("NPDES_ID", "year")]
panel <- fac[panel,   on = "NPDES_ID"]
panel <- naics[panel, on = "NPDES_ID"]
panel <- sic[panel,   on = "NPDES_ID"]
for (c in c("n_formal_actions", "n_informal_actions", "n_enf_actions_total"))
  panel[is.na(get(c)), (c) := 0L]
for (c in c("fed_penalty", "state_local_penalty", "total_penalty"))
  panel[is.na(get(c)), (c) := 0]
panel[is.na(enf_type_list), enf_type_list := ""]
panel[, any_enforcement := as.integer(n_enf_actions_total > 0)]
setcolorder(panel, c("NPDES_ID", "year", "REGISTRY_ID", "FAC_NAME", "LOCATION_ADDRESS",
                     "CITY", "STATE_CODE", "ZIP", "COUNTY_CODE", "FAC_LAT", "FAC_LONG",
                     "NAICS_CODE", "SIC_CODE", "any_enforcement", "n_formal_actions",
                     "n_informal_actions", "n_enf_actions_total", "fed_penalty",
                     "state_local_penalty", "total_penalty", "enf_type_list"))
setorder(panel, NPDES_ID, year)
fwrite(panel, OUT)

message("=== entry/exit (major whenever permitted, never minor) ===")
message("Qualifying individual permits (never minor)    : ", length(qual))
message("Included (>=1 enforcement action)              : ", length(included))
message("Panel rows                                     : ", nrow(panel),
        " (unbalanced; permit-years the permit was an active major)")
message("Written to: ", OUT)
