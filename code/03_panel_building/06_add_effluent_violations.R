# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, PROC_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# Shared cleaning helpers used by every step of this pipeline: rd() (safe raw-file
# reads), build_facility_crosswalk() (NPDES_ID -> facility_id), and the two
# coalesce_date_*() date-combining functions. See code/02_cleaning/module_README.md.
source(file.path(CWA_ROOT, "code/02_cleaning/cleaning_helpers.R"))

# ==============================================================================
# 06_add_effluent_violations.R
# ------------------------------------------------------------------------------
# SIXTH STEP in the facility-by-month pipeline. Reads the panel produced by
# 05_add_enforcement.R and attaches, for every facility-month, ALL effluent (DMR)
# violation columns -- both count sets described below.
#
#   Input  : data/processed/effluent_violations_npdes_month_panel_2005_2025.csv
#            (PRE-BUILT by build_effluent_violations_npdes_month_panel.R -- see
#            that script for how it's constructed; this script just reads it)
#            data/processed/05_facility_month_panel_major_individual_enforcement_2005_2025.csv
#            (one row per FACILITY_UIN x YEAR x MONTH; built by scripts 01-05)
#   Output : data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv
#            (the same panel + 7 new effluent-violation count columns)
#
# COLUMNS ADDED (all integers, counted within each facility-month):
#   N_TSS_EFF_VIOLATIONS - TSS gross-effluent monthly-average violations (all codes)
#   N_TSS_EFF_D90        - ...of which VIOLATION_CODE D90 (DMR, Limited - Overdue)
#   N_TSS_EFF_D80        - ...of which VIOLATION_CODE D80 (DMR, Monitor Only - Overdue)
#   N_TSS_EFF_E90        - ...of which VIOLATION_CODE E90 (effluent limit exceedance)
#   n_D80  - ALL-PARAMETER effluent violations, VIOLATION_CODE D80 (DMR value overdue)
#   n_D90  - ALL-PARAMETER effluent violations, VIOLATION_CODE D90 (DMR value overdue, limited)
#   n_E90  - ALL-PARAMETER effluent violations, VIOLATION_CODE E90 (numeric limit exceedance)
#
# NOTE (2026-07-27): both count sets used to be computed in two separate places
# (all-parameter from the condensed file; TSS by this script separately
# streaming the raw ~16 GB effluent file through a Python pre-filter). They now
# both come from the SAME pre-built condensed file, computed together in one
# pass by build_effluent_violations_npdes_month_panel.R -- this script no
# longer touches the raw effluent file at all, and no longer needs python3 or
# unzip. The columns and values this script produces are unchanged.
#
# ------------------------------------------------------------------------------
# LABELED ASSUMPTIONS (read before using results):
#
#   1. TWO EFFLUENT COUNT SETS, KEPT SEPARATE ON PURPOSE.
#      - n_D80/_D90/_E90 count those codes across EVERY parameter, feature, and
#        monitoring location.
#      - N_TSS_EFF_D80/_D90/_E90 count the SAME codes but ONLY for the Total-
#        Suspended-Solids gross-effluent monthly-average subset (see
#        build_effluent_violations_npdes_month_panel.R's LABELED ASSUMPTION 3
#        for the exact filter).
#      So n_* is broadly a SUPERSET of the TSS counts (n_D80 >= N_TSS_EFF_D80,
#      etc.). Neither replaces the other.
#
#   2. BOTH COUNT SETS ALREADY DE-DUPLICATED AT SOURCE, BY TWO DIFFERENT RULES
#      (see build_effluent_violations_npdes_month_panel.R's LABELED ASSUMPTION 4
#      for why the two rules are deliberately different, not a bug). This
#      script does not re-dedupe either one -- it only re-keys by facility and
#      sums. As a result, in a vanishingly small number of facility-months the
#      TSS count can exceed the all-parameter count by 1-2 (see the run-log
#      cross-check at the bottom of this script) -- reported, not corrected.
#
#   3. DATE = DMR MONITORING-PERIOD MONTH. The condensed file's `month` is the
#      calendar month of MONITORING_PERIOD_END_DATE. We split into YEAR/MONTH
#      integers to match the panel keys.
#
#   4. ROUTED BY NPDES_ID VIA THE SAME CROSSWALK AS SCRIPTS 02, 04 & 05. Each row
#      is keyed to a permit (NPDES_ID); we map NPDES_ID -> facility exactly the way
#      scripts 01-05 do (FACILITY_UIN when present, else the NPDES_ID itself) and
#      aggregate across all permits that resolve to the facility.
#
#   5. PANEL DEFINES THE OBSERVATION SET; MISSING = TRUE ZERO. Counts are attached
#      by LEFT-JOINING onto the existing panel spine. Rows/months not present in a
#      source had no such violation -> filled with 0. Source rows for permits/months
#      outside the panel (minors, general permits, pre-entry) do not match and drop.
#
# Deterministic (no stochastic steps); rebuilt entirely from the pre-built
# condensed source + scripts 01-05 output + this script. Non-destructive: writes
# a NEW file, leaves script 05's panel untouched, and is safe to re-run.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)   # fast CSV reads + grouped sums/counts
  library(lubridate)    # date parsing (as.Date) and year()/month() extraction
})

## ---- Config (edit here if the panel window or file locations ever change) ----
YEAR_MIN <- 2005L
YEAR_MAX <- 2025L
RAW_DIR  <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
EFF_PATH <- file.path(CWA_ROOT, "data/processed/effluent_violations_npdes_month_panel_2005_2025.csv")
IN_PATH  <- file.path(CWA_ROOT, "data/processed/05_facility_month_panel_major_individual_enforcement_2005_2025.csv")
OUT_PATH <- file.path(CWA_ROOT, "data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv")

# New columns, in their FINAL panel order: TSS block first (it sits right after the
# schedule/event violations from 04), then the all-parameter block at the very end.
tss_cols <- c("N_TSS_EFF_VIOLATIONS", "N_TSS_EFF_D90", "N_TSS_EFF_D80", "N_TSS_EFF_E90")
nd_cols  <- c("n_D80", "n_D90", "n_E90")

# ------------------------------------------------------------------------------
# STEP 1: Read the facility-by-month panel (output of script 05).
# ------------------------------------------------------------------------------
# One row per FACILITY_UIN x YEAR x MONTH. Read YEAR/MONTH as integers so they
# align with the values we derive from the sources below.
panel <- fread(IN_PATH, colClasses = "character", showProgress = FALSE)
panel[, `:=`(YEAR = as.integer(YEAR), MONTH = as.integer(MONTH))]

# ------------------------------------------------------------------------------
# STEP 2: Build the NPDES_ID -> facility_id crosswalk (same rule as scripts
# 01-05; ASSUMPTION 4). See build_facility_crosswalk() in
# code/02_cleaning/cleaning_helpers.R for the full explanation.
# ------------------------------------------------------------------------------
xwalk <- build_facility_crosswalk(raw_dir = RAW_DIR)

# ------------------------------------------------------------------------------
# STEP 3: Read both count sets from the pre-built condensed effluent panel.
# ------------------------------------------------------------------------------
# build_effluent_violations_npdes_month_panel.R computes the all-parameter and
# TSS-subset counts together in one pass over the raw file, so this one read
# gives us everything -- no separate stream of NPDES_EFF_VIOLATIONS.csv here.
# Codes read as integer counts; NPDES_ID/month as text. `month` is YYYY-MM-01.
all_new <- c(nd_cols, tss_cols)
eff <- fread(EFF_PATH, showProgress = FALSE,
             colClasses = list(character = c("NPDES_ID", "month"),
                               integer   = all_new))
eff[, NPDES_ID := trimws(NPDES_ID)]
eff[, mdate := as.Date(month)]
eff <- eff[!is.na(mdate)]
eff[, `:=`(YEAR = year(mdate), MONTH = month(mdate))]
eff <- eff[YEAR >= YEAR_MIN & YEAR <= YEAR_MAX]
n_rows_read <- nrow(eff)

# Route NPDES_ID -> facility_id (inner join drops permits with no facility record),
# then SUM each code across the facility's permits (ASSUMPTION 4).
eff <- xwalk[eff, on = "NPDES_ID", nomatch = 0]
counts <- eff[, lapply(.SD, sum), by = .(facility_id, YEAR, MONTH), .SDcols = all_new]

# ------------------------------------------------------------------------------
# STEP 4: Attach to the panel, fill absent months with 0.
# ------------------------------------------------------------------------------
# Left-join: panel key FACILITY_UIN == source key facility_id, plus YEAR/MONTH.
panel <- counts[panel, on = c(facility_id = "FACILITY_UIN", "YEAR", "MONTH")]
setnames(panel, "facility_id", "FACILITY_UIN")            # restore the panel's name

# A true zero only applies while the facility was actually operating
# (FACILITY_OPERATING == 1, from 01_build_facility_month_panel_major_individual.R);
# months outside its active window get an explicit NA -- undefined, not zero. But
# a REAL matched effluent violation always wins over the operating flag: some
# facilities have genuine recorded violations outside their computed open/close
# window (e.g. administrative lag near permit boundaries) -- NA only means "not
# operating AND no data," never "not operating, so discard real data."
for (c in all_new) {
  panel[is.na(get(c)) & FACILITY_OPERATING == "1", (c) := 0L]
  panel[is.na(get(c)) & FACILITY_OPERATING == "0", (c) := NA]
}

# ------------------------------------------------------------------------------
# STEP 5: Restore the original column order and row order.
# ------------------------------------------------------------------------------
# Keep the final panel identical to the pre-refactor layout: the TSS block sits
# immediately after N_SE_VIOLATIONS (its former position, added by 04), and the
# all-parameter block sits at the very end.
base    <- setdiff(names(panel), all_new)      # everything except the new columns
se_pos  <- match("N_SE_VIOLATIONS", base)
if (is.na(se_pos)) se_pos <- length(base)      # fallback: keep new cols after base
final_order <- c(base[seq_len(se_pos)], tss_cols,
                 if (se_pos < length(base)) base[(se_pos + 1L):length(base)], nd_cols)
setcolorder(panel, final_order)
setorder(panel, FACILITY_UIN, YEAR, MONTH)

fwrite(panel, OUT_PATH)

# ------------------------------------------------------------------------------
# STEP 6: Run log (sanity checks).
# ------------------------------------------------------------------------------
message("=== 06_add_effluent_violations: effluent codes attached to month panel ===")
message("Condensed source ID-months in window (2005-2025) : ", n_rows_read)
# na.rm = TRUE throughout: non-operating months are now legitimately NA
# (FACILITY_OPERATING == 0), so these sums are computed over the operating
# rows only, same as before this change for every operating row.
message("All-parameter violations on panel (D80/D90/E90)  : ",
        sum(panel$n_D80, na.rm = TRUE), " / ", sum(panel$n_D90, na.rm = TRUE), " / ", sum(panel$n_E90, na.rm = TRUE))
message("Facility-months with >=1 D80 / D90 / E90         : ",
        sum(panel$n_D80 > 0, na.rm = TRUE), " / ", sum(panel$n_D90 > 0, na.rm = TRUE), " / ", sum(panel$n_E90 > 0, na.rm = TRUE))
message("TSS gross monthly-avg effluent violations        : ", sum(panel$N_TSS_EFF_VIOLATIONS, na.rm = TRUE),
        "  (D90 ", sum(panel$N_TSS_EFF_D90, na.rm = TRUE),
        " / D80 ", sum(panel$N_TSS_EFF_D80, na.rm = TRUE),
        " / E90 ", sum(panel$N_TSS_EFF_E90, na.rm = TRUE), ")")
message("Facility-months with >=1 TSS effluent violation  : ", sum(panel$N_TSS_EFF_VIOLATIONS > 0, na.rm = TRUE))
# Cross-check: the all-parameter columns count the same codes over ALL parameters,
# so they are overwhelmingly a superset of the TSS-only columns. They are NOT
# guaranteed >= cell-by-cell, though: the TSS counts use DISTINCT NPDES_VIOLATION_ID
# while the condensed source counts DISTINCT vkey (its more aggressive "latest-
# version" de-dup), so in a vanishingly small number of facility-months the
# condensed count can be 1-2 lower. We report the exceptions, not assert inequality.
# (Restricted to operating rows -- non-operating rows are NA on both sides.)
short <- pmax(0L, panel$N_TSS_EFF_D80 - panel$n_D80) +
         pmax(0L, panel$N_TSS_EFF_D90 - panel$n_D90) +
         pmax(0L, panel$N_TSS_EFF_E90 - panel$n_E90)
message("Cells where all-param < TSS subset (dedup-key diff): ",
        sum(short > 0, na.rm = TRUE), " of ", sum(panel$FACILITY_OPERATING == "1"),
        "  (max shortfall ", if (any(short > 0, na.rm = TRUE)) max(short, na.rm = TRUE) else 0L, ")")
message("Facility-months NOT operating (NA counts)         : ", sum(panel$FACILITY_OPERATING == "0"))
message("Panel rows: ", nrow(panel), " | columns: ", ncol(panel))
message("Written to: ", OUT_PATH)
