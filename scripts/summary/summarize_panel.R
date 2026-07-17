# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, PROC_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# summarize_panel.R — face-validity / realism check for a built facility-month
# panel (the 01..06 panels in data/processed).
# ------------------------------------------------------------------------------
# Purpose: NOT to produce findings, but to catch bugs from panel construction
# (bad merges, duplicated rows, impossible values, coverage gaps) before the
# panel is trusted for analysis. Every number here is one you can eyeball and
# ask "is that plausible?"
#
# Usage (from anywhere inside the repo):
#   Rscript scripts/summary/summarize_panel.R [panel_filename]
#
#   [panel_filename]  a file in data/processed (default: the newest 0*_facility
#                     _month_panel*.csv). Works on any of the 01..06 panels —
#                     the numeric-summary and consistency checks auto-adapt to
#                     whichever columns are present.
#
# Output: prints all four sections to the console AND writes a timestamped
#   .xlsx to output/ with one sheet per section.
#
# Sections:
#   1. Panel structure  — shape, keys, and the KEY UNIQUENESS check
#   2. Coverage         — rows per year + %-missing per column
#   3. Numeric summary  — N, mean, sd, min, p50, p90, p99, max, %nonzero, %missing
#   4. Consistency      — component sums == totals; penalty => formal action
# ==============================================================================

library(data.table)
library(openxlsx)

# ── Which file to summarize ───────────────────────────────────────────────────

args  <- commandArgs(trailingOnly = TRUE)
if (length(args) >= 1 && nzchar(args[1])) {
  panel_file <- if (file.exists(args[1])) args[1] else file.path(PROC_DIR, args[1])
} else {
  cands <- list.files(PROC_DIR, pattern = "^0[0-9]_facility_month_panel.*\\.csv$",
                      full.names = TRUE)
  if (length(cands) == 0) stop("No 0*_facility_month_panel*.csv found in ", PROC_DIR)
  panel_file <- cands[order(basename(cands))][length(cands)]  # highest-numbered
}
if (!file.exists(panel_file)) stop("Panel file not found: ", panel_file)

panel_name <- basename(panel_file)
cat("Summarizing panel:", panel_name, "\n")
cat("Reading", sprintf("%.0f MB", file.info(panel_file)$size / 1e6), "...\n")

dt <- fread(panel_file, showProgress = FALSE)

# ── Column roles ──────────────────────────────────────────────────────────────
# Keys / identifiers / geo / industry codes are NOT summarized as statistics
# (a mean ZIP or mean latitude is meaningless). Everything else numeric is.

ID_COLS <- c("FACILITY_UIN", "NPDES_ID", "YEAR", "MONTH", "ZIP", "COUNTY_CODE",
             "FAC_LAT", "FAC_LONG", "NAICS_CODE", "SIC_CODE",
             "FACILITY_TYPE_CODE", "COUNTY_FIPS", "STATE_FIPS")

is_numeric_col <- function(x) is.numeric(x) || is.integer(x)
num_cols <- names(dt)[vapply(dt, is_numeric_col, logical(1))]
stat_cols <- setdiff(num_cols, ID_COLS)

# ── Section 1: Panel structure ────────────────────────────────────────────────

has_key <- all(c("FACILITY_UIN", "YEAR", "MONTH") %in% names(dt))
n_dup_key <- if (has_key) {
  sum(duplicated(dt, by = c("FACILITY_UIN", "YEAR", "MONTH")))
} else NA_integer_

structure_tbl <- data.table(
  Metric = c("Rows", "Unique FACILITY_UIN", "Unique NPDES_ID",
             "Year range", "Month range",
             "Duplicate (FACILITY_UIN,YEAR,MONTH) rows",
             "Key is unique?"),
  Value = c(
    format(nrow(dt), big.mark = ","),
    if ("FACILITY_UIN" %in% names(dt)) format(uniqueN(dt$FACILITY_UIN), big.mark = ",") else "n/a",
    if ("NPDES_ID"     %in% names(dt)) format(uniqueN(dt$NPDES_ID),     big.mark = ",") else "n/a",
    if ("YEAR"  %in% names(dt)) paste(range(dt$YEAR,  na.rm = TRUE), collapse = " - ") else "n/a",
    if ("MONTH" %in% names(dt)) paste(range(dt$MONTH, na.rm = TRUE), collapse = " - ") else "n/a",
    if (is.na(n_dup_key)) "n/a (missing key cols)" else format(n_dup_key, big.mark = ","),
    if (is.na(n_dup_key)) "n/a" else if (n_dup_key == 0) "YES (pass)" else "NO -- INVESTIGATE"
  )
)

# ── Section 2: Coverage (rows per year + %-missing) ───────────────────────────

year_tbl <- if ("YEAR" %in% names(dt)) {
  yt <- dt[, .(Rows = .N, Facilities = uniqueN(FACILITY_UIN)), by = YEAR][order(YEAR)]
  yt[, Rows := format(Rows, big.mark = ",")]
  yt
} else data.table(Note = "no YEAR column")

miss_tbl <- data.table(
  Column      = names(dt),
  Pct_Missing = round(vapply(dt, function(x) mean(is.na(x)) * 100, numeric(1)), 1)
)[order(-Pct_Missing)]

# ── Section 3: Numeric summary ────────────────────────────────────────────────

q <- function(x, p) as.numeric(quantile(x, p, na.rm = TRUE, names = FALSE))
summ_one <- function(x) {
  n_obs <- sum(!is.na(x))
  data.table(
    N         = n_obs,
    Mean      = round(mean(x, na.rm = TRUE), 4),
    SD        = round(sd(x, na.rm = TRUE), 4),
    Min       = suppressWarnings(min(x, na.rm = TRUE)),
    P50       = q(x, .50),
    P90       = q(x, .90),
    P99       = q(x, .99),
    Max       = suppressWarnings(max(x, na.rm = TRUE)),
    Pct_Nonzero = round(mean(x != 0, na.rm = TRUE) * 100, 2),
    Pct_Missing = round(mean(is.na(x)) * 100, 1)
  )
}
numeric_tbl <- rbindlist(lapply(stat_cols, function(c) cbind(Variable = c, summ_one(dt[[c]]))))

# ── Section 4: Internal-consistency checks ────────────────────────────────────

checks <- list()
add_check <- function(name, ok, detail = "")
  checks[[length(checks) + 1]] <<- list(Check = name,
                                        Result = if (ok) "PASS" else "FAIL",
                                        Detail = detail)

# Component sums == totals
check_sum <- function(total, parts, label) {
  if (all(c(total, parts) %in% names(dt))) {
    lhs <- rowSums(dt[, ..parts], na.rm = TRUE)
    bad <- sum(lhs != dt[[total]], na.rm = TRUE)
    add_check(label, bad == 0, sprintf("%s rows where %s != sum(%s)",
              format(bad, big.mark = ","), total, paste(parts, collapse = "+")))
  }
}
check_sum("N_FORMAL_ACTIONS",   c("N_STATE_FORMAL", "N_EPA_FORMAL"),
          "N_FORMAL_ACTIONS == N_STATE_FORMAL + N_EPA_FORMAL")
check_sum("N_INFORMAL_ACTIONS", c("N_OFFICIAL_INFORMAL", "N_UNOFFICIAL_INFORMAL"),
          "N_INFORMAL_ACTIONS == N_OFFICIAL_INFORMAL + N_UNOFFICIAL_INFORMAL")

# Penalty assessed => a formal action exists in that facility-month
check_implies <- function(cond_col, then_col, label) {
  if (all(c(cond_col, then_col) %in% names(dt))) {
    bad <- sum(dt[[cond_col]] > 0 & !(dt[[then_col]] > 0), na.rm = TRUE)
    add_check(label, bad == 0, sprintf("%s rows with %s>0 but %s==0",
              format(bad, big.mark = ","), cond_col, then_col))
  }
}
check_implies("N_FED_PENALTY_ASSESSED",   "N_EPA_FORMAL",   "Fed penalty => EPA formal action")
check_implies("N_STATE_PENALTY_ASSESSED", "N_STATE_FORMAL", "State penalty => state formal action")

# No negative counts anywhere in the stat columns
neg_cols <- stat_cols[vapply(stat_cols, function(c) any(dt[[c]] < 0, na.rm = TRUE), logical(1))]
add_check("No negative values in count/dollar columns", length(neg_cols) == 0,
          if (length(neg_cols)) paste("negatives in:", paste(neg_cols, collapse = ", ")) else "")

consistency_tbl <- rbindlist(lapply(checks, as.data.table))

# ── Console output ────────────────────────────────────────────────────────────

hr <- function(s) cat("\n", strrep("=", 78), "\n", s, "\n", strrep("=", 78), "\n", sep = "")
hr("1. PANEL STRUCTURE");   print(structure_tbl,   row.names = FALSE)
hr("2a. ROWS PER YEAR");    print(year_tbl,        row.names = FALSE)
hr("2b. %-MISSING (top 15)"); print(head(miss_tbl, 15), row.names = FALSE)
hr("3. NUMERIC SUMMARY");   print(numeric_tbl,     row.names = FALSE)
hr("4. CONSISTENCY CHECKS"); print(consistency_tbl, row.names = FALSE)

# ── Excel workbook ────────────────────────────────────────────────────────────

out_file <- file.path(OUT_DIR, sprintf("panel_summary_%s_%s.xlsx",
                       tools::file_path_sans_ext(panel_name),
                       format(Sys.time(), "%Y-%m-%d_%H%M")))

hdr <- createStyle(textDecoration = "bold", fgFill = "#D9E1F2", border = "Bottom")
wb  <- createWorkbook()
add_sheet <- function(name, tbl) {
  addWorksheet(wb, name)
  writeData(wb, name, tbl, headerStyle = hdr)
  setColWidths(wb, name, cols = seq_along(tbl), widths = "auto")
  freezePane(wb, name, firstRow = TRUE)
}
add_sheet("1_structure",   structure_tbl)
add_sheet("2a_year",       year_tbl)
add_sheet("2b_missing",    miss_tbl)
add_sheet("3_numeric",     numeric_tbl)
add_sheet("4_consistency", consistency_tbl)
saveWorkbook(wb, out_file, overwrite = TRUE)

cat("\nWrote workbook:", out_file, "\n")
