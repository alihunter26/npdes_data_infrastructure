# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# NAICS/SIC coverage by state x year, for MAJOR INDIVIDUAL permits, 2005-2025.
#
# Standalone diagnostic (not part of scripts/build/ or run_all.R). Answers:
# among permits that were major + individual in a given year, what share had
# a NAICS code on file, and what share had a SIC code, broken out by state?
#
# Major-individual-by-year reconstruction is adapted from
# scripts/build/04_build_permit_panel_major_continuous.R (individual = NPD;
# major/minor is time-varying, carried forward from each version's effective
# year). Unlike that script, permits are NOT required to be major every year
# here -- each year gets its own population, entry/exit allowed.
#
# CLOSURE is status-aware (see STEP 1): a permit is held through YEAR_MAX unless
# its current version is TRM (terminated) or EXP (lapsed). This DIVERGES from
# scripts/build/04-05, which close on max expiration date alone and thereby drop
# administratively-continued (ADC) majors that are still active -- an undercount
# this diagnostic deliberately avoids.
#
# NAICS_CODE / SIC_CODE presence (NPDES_NAICS.csv / NPDES_SICS.csv) has no
# date field -- it's a fixed permit attribute, not time-varying.
#
# Read-only on raw data. Writes a timestamped CSV to output/tables/.

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
})

YEAR_MIN <- 2005L
YEAR_MAX <- 2025L
RAW <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
OUT_DIR <- file.path(CWA_ROOT, "output/tables")

rd <- function(f, cols) fread(file.path(RAW, f), select = cols,
                              colClasses = "character", showProgress = FALSE)

# ---- 1. Reconstruct major/minor status by year (individual permits) ----------
pv <- rd("ICIS_PERMITS.csv",
         c("EXTERNAL_PERMIT_NMBR", "PERMIT_TYPE_CODE", "MAJOR_MINOR_STATUS_FLAG",
           "PERMIT_STATUS_CODE", "VERSION_NMBR",
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
# Status-aware "held through" year (fixes ADC truncation). A permit's CURRENT
# version (VERSION_NMBR == 0) decides closure, per docs/panel_questions_for_pis.md:
#   TRM -> closed at its termination year; EXP -> closed at its (lapsed) expiration
#   year; anything else (ADC administratively-continued, EFF, ...) -> still active,
#   held through YEAR_MAX. Using EXPIRATION_DATE alone would drop ~1,578 still-active
#   ADC majors from recent years. (This diverges from scripts/build/04-05, which
#   still use the naive max-expiration rule and share this bug.)
# Computed BEFORE the M/N filter below so every current-version row is available.
cur <- pv[trimws(VERSION_NMBR) == "0",
          .(id,
            cur_status  = trimws(PERMIT_STATUS_CODE),
            trm_year    = year(fcoalesce(mdy(TERMINATION_DATE, quiet = TRUE),
                                         mdy(EXPIRATION_DATE,  quiet = TRUE))),
            exp_year_v0 = year(mdy(EXPIRATION_DATE, quiet = TRUE)))]
cur[, close_year := fifelse(cur_status == "TRM", trm_year,
                     fifelse(cur_status == "EXP", exp_year_v0, YEAR_MAX))]
cur[, close_year := fifelse(is.na(close_year), YEAR_MAX, close_year)]  # missing date -> assume active
# Cover every NPD permit; the rare permit with no V0 row defaults to active (YEAR_MAX).
held_end <- cur[unique(pv[, .(id)]), on = "id"]
held_end[is.na(close_year), close_year := YEAR_MAX]
held_end <- held_end[, .(id, held_end = close_year)]

# Now restrict to placeable M/N version-rows for the per-year flag reconstruction.
pv <- pv[!is.na(eff_year) & flag %in% c("M", "N")]
# one flag per (id, effective year): Minor wins if any version that year is N
vf <- pv[, .(flag = if (any(flag == "N")) "N" else "M"), by = .(id, eff_year)]
setkey(vf, id, eff_year)

# carry-forward status for every permit x year
grid <- CJ(id = unique(vf$id), year = YEAR_MIN:YEAR_MAX)
status <- vf[grid, on = .(id, eff_year = year), roll = Inf]
setnames(status, "eff_year", "year")
status <- held_end[status, on = "id"]
status[, ymm := fifelse(!is.na(flag) & year <= held_end, flag, NA_character_)]

# Major-individual population, by year (entry/exit allowed -- no "every year" filter)
maj <- status[ymm == "M", .(id, year)]
cat("Permit-year rows, major-individual, ", YEAR_MIN, "-", YEAR_MAX, ": ", nrow(maj), "\n", sep = "")

# ---- 2. State lookup (time-invariant, one row per NPDES_ID) -------------------
fac <- rd("ICIS_FACILITIES.csv", c("NPDES_ID", "STATE_CODE"))
fac[, NPDES_ID := trimws(NPDES_ID)]
fac <- unique(fac, by = "NPDES_ID")

# ---- 3. NAICS / SIC coverage lookup (time-invariant: any row for that id) -----
naics_ids <- unique(trimws(rd("NPDES_NAICS.csv", "NPDES_ID")$NPDES_ID))
sic_ids   <- unique(trimws(rd("NPDES_SICS.csv",  "NPDES_ID")$NPDES_ID))

# ---- 4. Join state + coverage onto the major-individual permit-year table -----
maj <- fac[maj, on = c("NPDES_ID" = "id")]
setnames(maj, "NPDES_ID", "id")
maj[, has_naics := id %in% naics_ids]
maj[, has_sic   := id %in% sic_ids]
maj <- maj[!is.na(STATE_CODE) & STATE_CODE != ""]

# ---- 5. Aggregate by state x year ----------------------------------------------
cov <- maj[, .(
    n_permits = .N,
    n_naics   = sum(has_naics),
    pct_naics = round(100 * mean(has_naics), 1),
    n_sic     = sum(has_sic),
    pct_sic   = round(100 * mean(has_sic), 1)
  ), by = .(STATE_CODE, year)]
setorder(cov, STATE_CODE, year)

# ---- 6. Console summary: national totals by year (sanity check) ---------------
nat <- maj[, .(
    n_permits = .N,
    pct_naics = round(100 * mean(has_naics), 1),
    pct_sic   = round(100 * mean(has_sic), 1)
  ), by = year][order(year)]
cat("\n=== National major-individual NAICS/SIC coverage by year ===\n")
print(nat)
cat("\nPooled across all years: pct_naics =", round(100 * mean(maj$has_naics), 1),
    " pct_sic =", round(100 * mean(maj$has_sic), 1), "\n")

# ---- 7. Write timestamped CSV ---------------------------------------------------
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)
stamp <- format(Sys.time(), "%Y-%m-%d_%H%M")
out_f <- file.path(OUT_DIR, paste0("naics_sic_coverage_by_state_year_", stamp, ".csv"))
fwrite(cov, out_f)
cat("\nRows (state x year):", nrow(cov), "\n")
cat("Written to:", out_f, "\n")
