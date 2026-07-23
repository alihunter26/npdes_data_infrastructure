# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, PROC_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# filter_dmr_fy2025_effgross_major_individual.R
# ------------------------------------------------------------------------------
# Restrict the EXO / 00530 / effluent-gross / monthly-average FY2025 DMR file
# (built by filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R) to permits that
# are MAJOR under an INDIVIDUAL permit -- the same population the facility panels
# use. The DMR file itself carries no major/minor or permit-type field, so those
# come from ICIS_PERMITS.csv, joined on EXTERNAL_PERMIT_NMBR (= NPDES_ID).
#
# Input  : data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg.csv  (all permits)
# Output : data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg_major_individual.csv
#          (same 57 columns; row-filtered to ever-major individual permits)
#
# ---- Population definition (matches updated panel/01 & the external ------
# ---- ../EIL Summer/build/03_build_facility_panel_major_individual.R) ----------
#   INDIVIDUAL : ICIS_PERMITS PERMIT_TYPE_CODE == "NPD".
#   EVER MAJOR : MAJOR_MINOR_STATUS_FLAG == "M" in AT LEAST ONE version row of the
#                permit (not "major every year"). This is the looser "ever major"
#                rule used in updated panel/01_build_facility_month_panel_major_individual.R.
#
# ---- Labeled assumptions -----------------------------------------------------
#   1. A permit present in the DMR file but ABSENT from ICIS_PERMITS cannot be
#      classified and is DROPPED (reported in the log).
#   2. A blank MAJOR_MINOR_STATUS_FLAG (~3.6% of ICIS_PERMITS rows, per
#      docs/data_quirks.md) is NOT "M": a permit with only blank/minor flags and
#      no "M" in any version is treated as non-major and dropped.
#   3. "Ever major" pools across ALL versions of the permit; it does not require
#      the permit to have been major in FY2025 specifically. Switch to a
#      2025-specific rule if that is what the analysis needs (see NOTE below).
# ==============================================================================

suppressPackageStartupMessages(library(data.table))

## ---- Config (edit here) ----
IN_PATH  <- file.path(PROC_DIR, "dmr_fy2025_exo_00530_effgross_monthlyavg.csv")
OUT_PATH <- file.path(PROC_DIR, "dmr_fy2025_exo_00530_effgross_monthlyavg_major_individual.csv")
PERMITS  <- file.path(RAW_DIR,  "ICIS_PERMITS.csv")

# ---- 1. Ever-major INDIVIDUAL permit set from ICIS_PERMITS --------------------
# skipNul=TRUE: ICIS_PERMITS has embedded NUL bytes (docs/data_quirks.md).
pm <- fread(PERMITS, select = c("EXTERNAL_PERMIT_NMBR", "PERMIT_TYPE_CODE",
                                "MAJOR_MINOR_STATUS_FLAG"),
            colClasses = "character", showProgress = FALSE)
pm[, id   := trimws(EXTERNAL_PERMIT_NMBR)]
pm[, ptc  := trimws(PERMIT_TYPE_CODE)]
pm[, flag := trimws(MAJOR_MINOR_STATUS_FLAG)]
pm <- pm[ptc == "NPD"]                                   # individual permits only
major_ind <- pm[, .(ever_major = any(flag == "M")), by = id][ever_major == TRUE, id]
cat("Individual (NPD) permits in ICIS_PERMITS       :", uniqueN(pm$id), "\n")
cat("...ever major (kept as the eligible permit set):", length(major_ind), "\n")

# ---- 2. Read the restricted DMR file (all columns, as text) ------------------
d <- fread(IN_PATH, colClasses = "character", showProgress = FALSE)
d[, EPN := trimws(EXTERNAL_PERMIT_NMBR)]
n_in       <- nrow(d)
permits_in <- uniqueN(d$EPN)

# ---- 3. Keep only rows whose permit is ever-major individual -----------------
out <- d[EPN %in% major_ind]
out[, EPN := NULL]                                       # drop the helper column

# ---- 4. Write --------------------------------------------------------------
fwrite(out, OUT_PATH)

# ---- 5. Report ---------------------------------------------------------------
cat("\n=== DONE ===\n")
cat("Output:", OUT_PATH, "\n")
cat("Rows:   ", n_in, "->", nrow(out),
    sprintf("(kept %.1f%%)\n", 100 * nrow(out) / n_in))
cat("Permits:", permits_in, "->", uniqueN(out$EXTERNAL_PERMIT_NMBR),
    sprintf("(kept %.1f%%)\n", 100 * uniqueN(out$EXTERNAL_PERMIT_NMBR) / permits_in))
cat("Permits dropped (general / minor / not in ICIS):",
    permits_in - uniqueN(out$EXTERNAL_PERMIT_NMBR), "\n")
