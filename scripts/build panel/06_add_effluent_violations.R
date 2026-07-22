# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, PROC_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# 06_add_effluent_violations.R
# ------------------------------------------------------------------------------
# SIXTH STEP in the facility-by-month pipeline. Reads the panel produced by
# 05_add_enforcement.R and attaches, for every facility-month, ALL effluent (DMR)
# violation columns. This script owns every effluent-violation count in the panel:
#
#   (A) ALL-PARAMETER codes, from the PRE-BUILT condensed month panel (fast):
#         data/processed/effluent_violations_npdes_month_panel_2005_2025.csv
#         (built by build_effluent_violations_npdes_month_panel.R, which was moved to
#          the EIL Summer folder: ../EIL Summer/build/)
#         -- one row per NPDES_ID x month, columns: NPDES_ID, month (YYYY-MM-01),
#            n_D80, n_D90, n_E90.
#
#   (B) TSS gross-effluent monthly-average subset, by streaming the ~16 GB raw
#         NPDES_EFF_VIOLATIONS.csv straight from its zip (moved here from
#         04_add_violations.R; see ASSUMPTIONS 6-7).
#
#   Input  : data/processed/05_facility_month_panel_major_individual_enforcement_2005_2025.csv
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
# NOTE: the TSS columns (N_TSS_EFF_*) were previously added in 04_add_violations.R;
# they moved here so all effluent-violation logic lives in one script. The final
# panel's columns and values are unchanged -- only the step that adds them moved.
#
# ------------------------------------------------------------------------------
# LABELED ASSUMPTIONS (read before using results):
#
#   1. TWO EFFLUENT COUNT SETS, KEPT SEPARATE ON PURPOSE.
#      - n_D80/_D90/_E90 count those codes across EVERY parameter, feature, and
#        monitoring location (from the condensed source).
#      - N_TSS_EFF_D80/_D90/_E90 count the SAME codes but ONLY for the Total-
#        Suspended-Solids gross-effluent monthly-average subset (streamed below).
#      So n_* is broadly a SUPERSET of the TSS counts (n_D80 >= N_TSS_EFF_D80,
#      etc.). Neither replaces the other.
#
#   2. ALL-PARAMETER COUNTS ALREADY DE-DUPLICATED AT SOURCE. The condensed panel
#      counts DISTINCT underlying violations (latest DMR resubmission version only)
#      per NPDES_ID x month x code. We do not re-dedupe; we only re-key and sum.
#
#   3. DATE = DMR MONITORING-PERIOD MONTH. The condensed `month` is the calendar
#      month of MONITORING_PERIOD_END_DATE; the TSS stream is dated the same way.
#      We split into YEAR/MONTH integers to match the panel keys.
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
#   6. THE TSS SUBSET IS A SINGLE, SPECIFIC LIMIT (per PI guidance). From the raw
#      NPDES_EFF_VIOLATIONS.csv (one row per parameter/limit value on a DMR) we keep
#      ONLY rows that are ALL of:
#        - Total Suspended Solids : PARAMETER_CODE == "00530" (EPA's standard TSS
#          code; other suspended-solids synonym codes are excluded).
#        - gross effluent         : MONITORING_LOCATION_CODE == "1" (Effluent Gross;
#          rare variants like "EG"/"E1" are excluded).
#        - monthly average        : STATISTICAL_BASE_MONTHLY_AVG == "A" (EPA's
#          monthly-average-equivalent flag).
#      Each kept violation is dated by MONITORING_PERIOD_END_DATE (100% present in
#      this subset). N_TSS_EFF_VIOLATIONS counts DISTINCT NPDES_VIOLATION_ID across
#      all codes; the D90/D80/E90 break-outs count DISTINCT ids of that code.
#
#   7. THE RAW EFFLUENT FILE IS STREAMED ONCE AND PRE-FILTERED IN PYTHON.
#      NPDES_EFF_VIOLATIONS.csv is ~16 GB uncompressed, so it is never extracted to
#      disk: it is streamed straight out of its zip (via `unzip -p`) and piped
#      through a small Python csv filter that keeps only the tiny TSS/gross/monthly
#      subset and emits just the columns we need, so R never holds the whole file.
#      REQUIRES python3 AND unzip on PATH. NOTE: the file writes empty fields as bare
#      commas but non-empty ones quoted, so it must be parsed by a real CSV reader
#      (Python's csv module here; fread on the R side reads the already-clean subset).
#
# Deterministic (no stochastic steps); rebuilt entirely from the condensed source +
# the raw effluent file + scripts 01-05 output + this script. Non-destructive: writes
# a NEW file, leaves script 05's panel untouched, and is safe to re-run.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)   # fast CSV reads + grouped sums/counts
  library(lubridate)    # date parsing (mdy) and year()/month() extraction
})

## ---- Config (edit here if the panel window or file locations ever change) ----
YEAR_MIN <- 2005L
YEAR_MAX <- 2025L
RAW_DIR  <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
EFF_PATH <- file.path(CWA_ROOT, "data/processed/effluent_violations_npdes_month_panel_2005_2025.csv")
IN_PATH  <- file.path(CWA_ROOT, "data/processed/05_facility_month_panel_major_individual_enforcement_2005_2025.csv")
OUT_PATH <- file.path(CWA_ROOT, "data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv")

# Raw effluent-violations source for the TSS subset: a ~16 GB CSV inside a zip in
# data/raw/ (streamed, never extracted). Filter constants define the single limit
# we keep (see ASSUMPTION 6): TSS parameter code, gross-effluent location code, and
# the monthly-average flag.
EFF_ZIP        <- list.files(file.path(CWA_ROOT, "data/raw"),
                             pattern = "eff.*zip", full.names = TRUE)[1]
EFF_CSV        <- "NPDES_EFF_VIOLATIONS.csv"
TSS_PARAM_CODE <- "00530"       # Solids, total suspended (standard EPA TSS code)
GROSS_LOC_CODE <- "1"           # MONITORING_LOCATION_CODE for Effluent Gross
MONTHLY_AVG    <- "A"           # STATISTICAL_BASE_MONTHLY_AVG flag = monthly average

# New columns, in their FINAL panel order: TSS block first (it sits right after the
# schedule/event violations from 04), then the all-parameter block at the very end.
tss_cols <- c("N_TSS_EFF_VIOLATIONS", "N_TSS_EFF_D90", "N_TSS_EFF_D80", "N_TSS_EFF_E90")
nd_cols  <- c("n_D80", "n_D90", "n_E90")

# Small helper: read only the columns we need, everything as plain text
# (character) so ID columns are never silently reinterpreted as numbers.
rd <- function(file, cols) {
  class_map <- setNames(rep("character", length(cols)), cols)
  fread(file.path(RAW_DIR, file), select = cols,
        colClasses = class_map, showProgress = FALSE)
}

# ------------------------------------------------------------------------------
# STEP 1: Read the facility-by-month panel (output of script 05).
# ------------------------------------------------------------------------------
# One row per FACILITY_UIN x YEAR x MONTH. Read YEAR/MONTH as integers so they
# align with the values we derive from the sources below.
panel <- fread(IN_PATH, colClasses = "character", showProgress = FALSE)
panel[, `:=`(YEAR = as.integer(YEAR), MONTH = as.integer(MONTH))]

# ------------------------------------------------------------------------------
# STEP 2: Rebuild the NPDES_ID -> facility_id crosswalk (same rule as scripts 01-05).
# ------------------------------------------------------------------------------
# A facility's id is its FACILITY_UIN when present, else the permit's own NPDES_ID.
# We reproduce that EXACTLY so each source row resolves to the same id the panel is
# keyed on (ASSUMPTION 4).
fac <- rd("ICIS_FACILITIES.csv", c("NPDES_ID", "FACILITY_UIN"))
fac[, NPDES_ID     := trimws(NPDES_ID)]
fac[, FACILITY_UIN := trimws(FACILITY_UIN)]
fac[, facility_id  := fifelse(FACILITY_UIN != "", FACILITY_UIN, NPDES_ID)]
xwalk <- unique(fac[NPDES_ID != "", .(NPDES_ID, facility_id)])

# ------------------------------------------------------------------------------
# STEP 3: ALL-PARAMETER counts from the condensed effluent month panel.
# ------------------------------------------------------------------------------
# Codes read as integer counts; NPDES_ID/month as text. `month` is YYYY-MM-01.
eff <- fread(EFF_PATH, showProgress = FALSE,
             colClasses = list(character = c("NPDES_ID", "month"),
                               integer   = nd_cols))
eff[, NPDES_ID := trimws(NPDES_ID)]
eff[, mdate := as.Date(month)]
eff <- eff[!is.na(mdate)]
eff[, `:=`(YEAR = year(mdate), MONTH = month(mdate))]
eff <- eff[YEAR >= YEAR_MIN & YEAR <= YEAR_MAX]
n_rows_read <- nrow(eff)

# Route NPDES_ID -> facility_id (inner join drops permits with no facility record),
# then SUM each code across the facility's permits (ASSUMPTION 4).
eff <- xwalk[eff, on = "NPDES_ID", nomatch = 0]
eff_month <- eff[, lapply(.SD, sum), by = .(facility_id, YEAR, MONTH), .SDcols = nd_cols]

# ------------------------------------------------------------------------------
# STEP 3B: TSS gross monthly-average subset, streamed from the raw effluent file.
# ------------------------------------------------------------------------------
# Streams NPDES_EFF_VIOLATIONS.csv straight from its zip, pre-filtering to the small
# TSS/gross/monthly subset in Python before the data reaches R, then dates, routes,
# and counts DISTINCT violations per facility-month (total + D90/D80/E90 break-outs).
count_effluent_violations <- function() {
  # The raw zip's real filename contains a non-ASCII space (a narrow no-break
  # space) that fread(cmd=) cannot encode into its shell command. Point an
  # ASCII-named temporary symlink at the zip -- this neither copies nor modifies
  # the immutable raw file -- and stream through that instead.
  link <- file.path(tempdir(), "npdes_eff_downloads.zip")
  unlink(link, force = TRUE)                 # no-op if absent; clears a stale link
  file.symlink(EFF_ZIP, link)
  on.exit(unlink(link, force = TRUE), add = TRUE)

  # Pre-filter the ~16 GB stream in Python BEFORE it reaches R, so peak memory
  # stays tiny on a memory-constrained machine. Python's csv module parses the
  # file's quoting correctly (empty fields are bare commas, non-empty ones are
  # quoted -- a naive awk/`cut` split would misalign columns), keeps only the
  # TSS / gross-effluent / monthly-average rows, and emits just the four columns
  # we need. fread then reads that small result. The filter values are passed as
  # arguments so the TSS/gross/monthly definition lives in ONE place (the config
  # constants above). Column positions are located by header name, so the filter
  # survives any future column re-ordering in the source file.
  python <- Sys.which("python3")
  if (python == "") stop("python3 not found on PATH; it is required to stream the effluent file.")
  py_code <- '
import csv, sys
param_code, loc_code, monthly_flag = sys.argv[1], sys.argv[2], sys.argv[3]
reader = csv.reader(sys.stdin)
writer = csv.writer(sys.stdout)
header = next(reader)
i_param = header.index("PARAMETER_CODE")
i_loc   = header.index("MONITORING_LOCATION_CODE")
i_ma    = header.index("STATISTICAL_BASE_MONTHLY_AVG")
out_cols = ["NPDES_ID", "NPDES_VIOLATION_ID", "VIOLATION_CODE", "MONITORING_PERIOD_END_DATE"]
out_idx  = [header.index(c) for c in out_cols]
need_max = max(i_param, i_loc, i_ma, *out_idx)
writer.writerow(out_cols)
for row in reader:
    if len(row) <= need_max:
        continue
    if row[i_param] == param_code and row[i_loc] == loc_code and row[i_ma] == monthly_flag:
        writer.writerow([row[j] for j in out_idx])
'
  py_file <- tempfile(fileext = ".py")
  writeLines(py_code, py_file)
  on.exit(unlink(py_file, force = TRUE), add = TRUE)

  read_cmd <- sprintf("unzip -p %s %s | %s %s %s %s %s",
                      shQuote(link), shQuote(EFF_CSV),
                      shQuote(python), shQuote(py_file),
                      shQuote(TSS_PARAM_CODE), shQuote(GROSS_LOC_CODE), shQuote(MONTHLY_AVG))

  # The Python step already applied the TSS/gross/monthly filter (ASSUMPTION 6),
  # so fread receives only the small matching subset (its 4 columns, named).
  eff <- fread(cmd = read_cmd, colClasses = "character", showProgress = FALSE)
  stopifnot(nrow(eff) > 0)          # guard against a silent pipe/filter failure
  eff[, NPDES_ID := trimws(NPDES_ID)]

  # Date by the DMR monitoring period, keep the window, route to facility.
  eff[, vdate := mdy(MONITORING_PERIOD_END_DATE, quiet = TRUE)]
  eff <- eff[!is.na(vdate)]
  eff[, `:=`(YEAR = year(vdate), MONTH = month(vdate))]
  eff <- eff[YEAR >= YEAR_MIN & YEAR <= YEAR_MAX]
  eff <- xwalk[eff, on = "NPDES_ID", nomatch = 0]

  # DISTINCT violations per facility-month: total, then broken out by code.
  eff[, .(
      N_TSS_EFF_VIOLATIONS = uniqueN(NPDES_VIOLATION_ID),
      N_TSS_EFF_D90        = uniqueN(NPDES_VIOLATION_ID[VIOLATION_CODE == "D90"]),
      N_TSS_EFF_D80        = uniqueN(NPDES_VIOLATION_ID[VIOLATION_CODE == "D80"]),
      N_TSS_EFF_E90        = uniqueN(NPDES_VIOLATION_ID[VIOLATION_CODE == "E90"])
    ), by = .(facility_id, YEAR, MONTH)]
}

eff_tss <- count_effluent_violations()

# ------------------------------------------------------------------------------
# STEP 4: Combine both count sets, attach to the panel, fill absent months with 0.
# ------------------------------------------------------------------------------
# Full outer merge so a facility-month present in either source is kept; kinds not
# present come through as NA and are set to 0 below.
all_new <- c(nd_cols, tss_cols)
counts  <- merge(eff_month, eff_tss, by = c("facility_id", "YEAR", "MONTH"), all = TRUE)
for (c in all_new) counts[is.na(get(c)), (c) := 0L]

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
