# ==============================================================================
# summarize_clean_dmr_by_year.R
# ------------------------------------------------------------------------------
# Per-fiscal-year summary of the cleaned intermediate DMR panels, BOD beside TSS.
# Every share is a share of ROWS, not of reports or outfall-months: rows are not
# additive (slots, limit sets, bases, locations and LIMIT_IDs each add rows).
#
#   Input : data/processed/clean_dmr_<FY>.csv      (TSS, 00530)
#           data/processed/clean_dmr_bod_<FY>.csv  (BOD5 00310 + CBOD5 80082)
#           both built by code/clean_dmr/build_dmr_clean_panel.R
#   Output: the log (stdout) and output/summary_clean_dmr_by_year_<span>.csv
#   Run   : Rscript code/summary/summarize_clean_dmr_by_year.R \
#             > output/summarize_clean_dmr_by_year_fy2009_2025.log 2>&1
#           Optional args: fiscal years, e.g. `... 2017 2018` (default 2009-2025).
#
# Definitions
#   value / limit present : DMR_VALUE_STANDARD_UNITS / LIMIT_VALUE_STANDARD_UNITS
#                           non-blank.
#   exceedance            : value > limit, limit > 0, '<' values included (the
#                           rule in code/clean_dmr/build_permit_month_panels.R).
#   E90 / D90 / D80       : the code appears in VIOLATION_CODE (which can hold
#                           'D90;E90').
#   censored              : DMR_VALUE_QUALIFIER_CODE is '<' or '<='.
# ==============================================================================
suppressMessages(library(data.table))
ROOT <- local({ d <- normalizePath(getwd()); while (!file.exists(file.path(d, ".git")) && dirname(d) != d) d <- dirname(d); d })
P    <- file.path(ROOT, "data", "processed")

args  <- commandArgs(trailingOnly = TRUE)
YEARS <- if (length(args)) as.integer(args) else 2009:2025
stopifnot(!anyNA(YEARS))
SPAN  <- if (length(YEARS) > 1L) sprintf("fy%d_%d", min(YEARS), max(YEARS)) else sprintf("fy%d", YEARS)
SETS  <- c(tss = "clean_dmr_%d.csv", bod = "clean_dmr_bod_%d.csv")

COLS <- c("FACILITY_ID", "EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_NMBR", "STATE_CODE", "YEAR", "MONTH",
          "PARAMETER_CODE", "VALUE_TYPE_CODE", "STATISTICAL_BASE_CODE",
          "LIMIT_VALUE_STANDARD_UNITS", "DMR_VALUE_STANDARD_UNITS", "DMR_VALUE_QUALIFIER_CODE",
          "NODI_CODE", "VIOLATION_CODE", "NMBR_OF_REPORT", "FLAG_MULTI_LIMIT_ID", "FLAG_MULTI_LIMIT_SET")
num <- function(x) suppressWarnings(as.numeric(x))
pct <- function(a, b) round(100 * a / b, 2)

one <- function(set, fy) {
  f <- file.path(P, sprintf(SETS[[set]], fy))
  if (!file.exists(f)) stop("missing input: ", f)
  d <- fread(f, colClasses = "character", select = COLS)
  val <- num(d$DMR_VALUE_STANDARD_UNITS); lim <- num(d$LIMIT_VALUE_STANDARD_UNITS)
  hv  <- d$DMR_VALUE_STANDARD_UNITS != ""; hl <- d$LIMIT_VALUE_STANDARD_UNITS != ""
  vl  <- hv & !is.na(lim) & lim > 0
  exc <- vl & val > lim
  e90 <- grepl("E90", d$VIOLATION_CODE, fixed = TRUE)
  N   <- nrow(d)
  # Outfall-months reporting more than one code of the set (always 0 for TSS).
  om  <- unique(d[, .(EXTERNAL_PERMIT_NMBR, PERM_FEATURE_NMBR, YEAR, MONTH, PARAMETER_CODE)])
  om  <- om[, .N, by = .(EXTERNAL_PERMIT_NMBR, PERM_FEATURE_NMBR, YEAR, MONTH)]
  pc  <- d[, .(n = uniqueN(PARAMETER_CODE)), by = EXTERNAL_PERMIT_NMBR]
  list(
    stats = data.table(
      set = set, FY = fy,
      rows = N, facilities = uniqueN(d$FACILITY_ID), permits = uniqueN(d$EXTERNAL_PERMIT_NMBR),
      outfalls = uniqueN(d[, paste(EXTERNAL_PERMIT_NMBR, PERM_FEATURE_NMBR)]),
      states = uniqueN(d$STATE_CODE),
      rows_00310 = sum(d$PARAMETER_CODE == "00310"), rows_80082 = sum(d$PARAMETER_CODE == "80082"),
      permits_00310 = uniqueN(d[PARAMETER_CODE == "00310", EXTERNAL_PERMIT_NMBR]),
      permits_80082 = uniqueN(d[PARAMETER_CODE == "80082", EXTERNAL_PERMIT_NMBR]),
      permits_both_codes = sum(pc$n > 1L), outfall_months = nrow(om),
      outfall_months_both_codes = sum(om$N > 1L),
      pct_Q_slot = pct(sum(substr(d$VALUE_TYPE_CODE, 1, 1) == "Q"), N),
      pct_MK = pct(sum(d$STATISTICAL_BASE_CODE == "MK"), N),
      pct_DB = pct(sum(d$STATISTICAL_BASE_CODE == "DB"), N),
      pct_multi_month = pct(sum(d$NMBR_OF_REPORT != "1"), N),
      pct_value = pct(sum(hv), N), pct_limit = pct(sum(hl), N),
      pct_nodi = pct(sum(d$NODI_CODE != ""), N), pct_nodi_C = pct(sum(d$NODI_CODE == "C"), N),
      pct_nodi_B = pct(sum(d$NODI_CODE == "B"), N),
      pct_censored = pct(sum(d$DMR_VALUE_QUALIFIER_CODE %in% c("<", "<=")), N),
      n_blank_value_and_nodi = sum(!hv & d$NODI_CODE == ""),
      n_negative = sum(hv & !is.na(val) & val < 0),
      pct_any_violation = pct(sum(d$VIOLATION_CODE != ""), N),
      pct_E90 = pct(sum(e90), N),
      pct_D90 = pct(sum(grepl("D90", d$VIOLATION_CODE, fixed = TRUE)), N),
      pct_D80 = pct(sum(grepl("D80", d$VIOLATION_CODE, fixed = TRUE)), N),
      rows_value_and_limit = sum(vl), n_exceed = sum(exc), pct_exceed_of_value_limit = pct(sum(exc), sum(vl)),
      n_exceed_without_E90 = sum(exc & !e90), n_E90_without_exceed = sum(e90 & !exc),
      n_flag_multi_limit_id = sum(d$FLAG_MULTI_LIMIT_ID == "TRUE"),
      n_flag_multi_limit_set = sum(d$FLAG_MULTI_LIMIT_SET == "TRUE"),
      pct_flag_multi_limit_set = pct(sum(d$FLAG_MULTI_LIMIT_SET == "TRUE"), N)),
    permits = unique(d$EXTERNAL_PERMIT_NMBR))
}

res <- list()
for (fy in YEARS) for (s in names(SETS)) res[[paste(s, fy)]] <- one(s, fy)
S <- rbindlist(lapply(res, `[[`, "stats"))

# Permit overlap between the two panels, per year.
ov <- rbindlist(lapply(YEARS, function(fy) {
  t <- res[[paste("tss", fy)]]$permits; b <- res[[paste("bod", fy)]]$permits
  data.table(FY = fy, both = length(intersect(t, b)), tss_only = length(setdiff(t, b)),
             bod_only = length(setdiff(b, t)))
}))

options(width = 220, datatable.print.nrows = 200, datatable.print.class = FALSE)
side <- function(cols, title) {
  cat("\n== ", title, " ==\n", sep = "")
  w <- dcast(S[, c("FY", "set", cols), with = FALSE], FY ~ set, value.var = cols)
  setcolorder(w, c("FY", as.vector(t(outer(cols, c("tss", "bod"), paste, sep = "_")))))
  setkey(w, NULL)
  print(w)
}
cat("Cleaned intermediate DMR panels, BOD (00310 + 80082) beside TSS (00530), ",
    min(YEARS), "-", max(YEARS), "\nAll shares are % of ROWS.\n", sep = "")

side(c("rows", "permits", "outfalls"), "coverage: rows / permits / outfalls")
side(c("facilities", "states"), "coverage: facilities / states")
cat("\n== permits in each panel ==\n"); print(ov)
cat("\n== BOD: the two codes ==\n")
print(S[set == "bod", .(FY, rows_00310, rows_80082, permits_00310, permits_80082, permits_both_codes,
                        outfall_months, outfall_months_both_codes)])
side(c("pct_Q_slot", "pct_MK", "pct_DB", "pct_multi_month"), "composition: Q slot / MK / DB / multi-month (% of rows)")
side(c("pct_value", "pct_limit", "pct_censored"), "completeness: value / limit / censored (% of rows)")
side(c("pct_nodi", "pct_nodi_C", "pct_nodi_B"), "NODI: any / C no discharge / B below detection (% of rows)")
side(c("n_blank_value_and_nodi", "n_negative"), "data quality: blank value AND blank NODI / negative values (rows)")
side(c("pct_any_violation", "pct_E90", "pct_D90", "pct_D80"), "violation codes (% of rows)")
side(c("n_exceed", "pct_exceed_of_value_limit"), "exceedance, value > limit > 0 (rows; % of rows with value and limit > 0)")
side(c("n_exceed_without_E90", "n_E90_without_exceed"), "exceedance vs E90 disagreement (rows)")
side(c("n_flag_multi_limit_id", "pct_flag_multi_limit_set"), "flags: FLAG_MULTI_LIMIT_ID rows / FLAG_MULTI_LIMIT_SET % of rows")

cat("\n== totals over ", length(YEARS), " years ==\n", sep = "")
print(S[, .(rows = sum(rows), flag_multi_limit_id = sum(n_flag_multi_limit_id),
            flag_multi_limit_set = sum(n_flag_multi_limit_set),
            min_permits = min(permits), max_permits = max(permits)), by = set])

out <- file.path(ROOT, "output", sprintf("summary_clean_dmr_by_year_%s.csv", SPAN))
fwrite(merge(S, ov, by = "FY"), out)
cat("\nTable written to ", out, "\n", sep = "")
