# ==============================================================================
# summarize_clean_dmr_by_year.R
# ------------------------------------------------------------------------------
# Per-fiscal-year summary of the cleaned intermediate DMR panels: TSS, BOD and
# ammonia side by side. Every share is a share of ROWS unless its name says
# permits: rows are not additive (slots, limit sets, bases, locations and
# LIMIT_IDs each add rows).
#
#   Input : data/processed/clean_dmr_tss_<FY>.csv      (TSS, 00530)
#           data/processed/clean_dmr_bod_<FY>.csv      (BOD5 00310 + CBOD5 80082)
#           data/processed/clean_dmr_ammonia_<FY>.csv  (00610 as N + 34726 as NH3)
#           all built by code/clean_dmr/build_dmr_clean_panel.R
#   Output: the log (stdout) and, in output/,
#           summary_clean_dmr_by_year_<span>.csv        one row per set x FY
#           summary_clean_dmr_by_year_codes_<span>.csv  one row per set x FY x code
#           summary_clean_dmr_by_year_overlap_<span>.csv permit overlap per FY
#                                                        (FY = NA: pooled window)
#   Run   : Rscript code/summary/summarize_clean_dmr_by_year.R \
#             > output/summarize_clean_dmr_by_year_fy2009_2025.log 2>&1
#           Optional args: fiscal years, e.g. `... $(seq 1986 2008)` (default
#           2009-2025). A set-year with no file (FY1987 for all; FY1986 for
#           ammonia) is skipped and listed, not an error.
#
# Definitions
#   value / limit present : DMR_VALUE_STANDARD_UNITS / LIMIT_VALUE_STANDARD_UNITS
#                           non-blank.
#   exceedance            : value > limit, limit > 0, '<' values included (the
#                           rule in code/clean_dmr/build_permit_month_panels.R).
#   permits with exceedance: permits with at least one exceedance row in the FY.
#   E90 / D90 / D80       : the code appears in VIOLATION_CODE (which can hold
#                           'D90;E90').
#   censored              : DMR_VALUE_QUALIFIER_CODE is '<' or '<='.
#   overlap pattern       : which panels a permit appears in that FY, e.g. "T B A"
#                           = all three, "T - -" = TSS only.
# ==============================================================================
suppressMessages(library(data.table))
ROOT <- local({ d <- normalizePath(getwd()); while (!file.exists(file.path(d, ".git")) && dirname(d) != d) d <- dirname(d); d })
P    <- file.path(ROOT, "data", "processed")

args  <- commandArgs(trailingOnly = TRUE)
YEARS <- if (length(args)) as.integer(args) else 2009:2025
stopifnot(!anyNA(YEARS))
SPAN  <- if (length(YEARS) > 1L) sprintf("fy%d_%d", min(YEARS), max(YEARS)) else sprintf("fy%d", YEARS)
SETS  <- c(tss = "clean_dmr_tss_%d.csv", bod = "clean_dmr_bod_%d.csv", ammonia = "clean_dmr_ammonia_%d.csv")
ABBR  <- c(tss = "T", bod = "B", ammonia = "A")

COLS <- c("FACILITY_ID", "EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_NMBR", "STATE_CODE", "YEAR", "MONTH",
          "PARAMETER_CODE", "VALUE_TYPE_CODE", "STATISTICAL_BASE_CODE",
          "LIMIT_VALUE_STANDARD_UNITS", "DMR_VALUE_STANDARD_UNITS", "DMR_VALUE_QUALIFIER_CODE",
          "NODI_CODE", "VIOLATION_CODE", "NMBR_OF_REPORT", "FLAG_MULTI_LIMIT_ID", "FLAG_MULTI_LIMIT_SET")
num <- function(x) suppressWarnings(as.numeric(x))
pct <- function(a, b) round(100 * a / b, 2)

one <- function(set, fy) {
  f <- file.path(P, sprintf(SETS[[set]], fy))
  if (!file.exists(f)) return(NULL)
  d <- fread(f, colClasses = "character", select = COLS)
  val <- num(d$DMR_VALUE_STANDARD_UNITS); lim <- num(d$LIMIT_VALUE_STANDARD_UNITS)
  hv  <- d$DMR_VALUE_STANDARD_UNITS != ""; hl <- d$LIMIT_VALUE_STANDARD_UNITS != ""
  vl  <- hv & !is.na(val) & !is.na(lim) & lim > 0
  exc <- vl & val > lim
  e90 <- grepl("E90", d$VIOLATION_CODE, fixed = TRUE)
  N   <- nrow(d); np <- uniqueN(d$EXTERNAL_PERMIT_NMBR)
  # Outfall-months reporting more than one code of the set (always 0 for TSS).
  om  <- unique(d[, .(EXTERNAL_PERMIT_NMBR, PERM_FEATURE_NMBR, YEAR, MONTH, PARAMETER_CODE)])
  om  <- om[, .N, by = .(EXTERNAL_PERMIT_NMBR, PERM_FEATURE_NMBR, YEAR, MONTH)]
  pc  <- d[, .(n = uniqueN(PARAMETER_CODE)), by = EXTERNAL_PERMIT_NMBR]
  pex <- uniqueN(d$EXTERNAL_PERMIT_NMBR[exc])
  list(
    stats = data.table(
      set = set, FY = fy,
      rows = N, facilities = uniqueN(d$FACILITY_ID), permits = np,
      outfalls = uniqueN(d[, paste(EXTERNAL_PERMIT_NMBR, PERM_FEATURE_NMBR)]),
      states = uniqueN(d$STATE_CODE), rows_per_permit = round(N / np, 1),
      permits_multi_code = sum(pc$n > 1L), outfall_months = nrow(om),
      outfall_months_multi_code = sum(om$N > 1L),
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
      permits_any_exceed = pex, pct_permits_any_exceed = pct(pex, np),
      n_exceed_without_E90 = sum(exc & !e90), n_E90_without_exceed = sum(e90 & !exc),
      n_flag_multi_limit_id = sum(d$FLAG_MULTI_LIMIT_ID == "TRUE"),
      n_flag_multi_limit_set = sum(d$FLAG_MULTI_LIMIT_SET == "TRUE"),
      pct_flag_multi_limit_set = pct(sum(d$FLAG_MULTI_LIMIT_SET == "TRUE"), N)),
    codes = d[, .(rows = .N, permits = uniqueN(EXTERNAL_PERMIT_NMBR)), by = .(code = PARAMETER_CODE)][
      , `:=`(set = set, FY = fy)],
    permits = unique(d$EXTERNAL_PERMIT_NMBR))
}

res <- list(); skipped <- character()
for (fy in YEARS) for (s in names(SETS)) {
  r <- one(s, fy)
  if (is.null(r)) skipped <- c(skipped, sprintf("%s FY%d", s, fy)) else res[[paste(s, fy)]] <- r
}
if (!length(res)) stop("no input files found for FY ", paste(range(YEARS), collapse = "-"))
S  <- rbindlist(lapply(res, `[[`, "stats"))
CD <- rbindlist(lapply(res, `[[`, "codes"))
setcolorder(CD, c("set", "FY", "code"))

# Permit overlap: which of the three panels each permit appears in.
pattern_counts <- function(memb) {
  w <- dcast(memb, p ~ s, fun.aggregate = length, value.var = "s")
  for (s in setdiff(names(SETS), names(w))) set(w, j = s, value = 0L)
  w[, pattern := do.call(paste, lapply(names(SETS), function(s) ifelse(get(s) > 0, ABBR[[s]], "-")))]
  pats <- do.call(CJ, lapply(names(SETS), function(s) c(ABBR[[s]], "-")))
  pats <- setdiff(do.call(paste, pats), paste(rep("-", length(SETS)), collapse = " "))
  # Most panels first; within a tie, in SETS order ("-" sorts after the letters).
  pats <- pats[order(-nchar(gsub("[- ]", "", pats)), chartr("-", "~", pats))]
  out <- data.table(pattern = pats, permits = vapply(pats, function(x) sum(w$pattern == x), 0L))
  rbind(out, data.table(pattern = "any", permits = nrow(w)))
}
membership <- function(fys) rbindlist(lapply(names(SETS), function(s) {
  ps <- unlist(lapply(fys, function(fy) res[[paste(s, fy)]]$permits))
  if (length(ps)) data.table(p = unique(ps), s = s) else NULL
}))
OV <- rbind(
  rbindlist(lapply(YEARS, function(fy) { m <- membership(fy); if (is.null(m) || !nrow(m)) NULL else pattern_counts(m)[, FY := fy] })),
  pattern_counts(membership(YEARS))[, FY := NA_integer_])
setcolorder(OV, c("FY", "pattern", "permits"))

options(width = 250, datatable.print.nrows = 500, datatable.print.class = FALSE)
present <- intersect(names(SETS), unique(S$set))
side <- function(cols, title) {
  cat("\n== ", title, " ==\n", sep = "")
  w <- dcast(S[, c("FY", "set", cols), with = FALSE], FY ~ set, value.var = cols)
  want <- as.vector(t(outer(cols, present, paste, sep = "_")))
  if (length(cols) == 1L) setnames(w, present, want, skip_absent = TRUE)
  setcolorder(w, c("FY", intersect(want, names(w))))
  setkey(w, NULL)
  print(w)
}
cat("Cleaned intermediate DMR panels: TSS (00530), BOD (00310 + 80082), ammonia (00610 + 34726), FY",
    min(YEARS), "-FY", max(YEARS), "\nShares are % of ROWS unless named permits.\n", sep = "")
cat("Skipped (no file): ", if (length(skipped)) paste(skipped, collapse = ", ") else "none", "\n", sep = "")

side(c("rows", "permits", "outfalls"), "coverage: rows / permits / outfalls")
side(c("facilities", "states", "rows_per_permit"), "coverage: facilities / states / rows per permit")
cat("\n== permit overlap per FY (T = TSS, B = BOD, A = ammonia; FY NA = pooled over the window) ==\n")
ovw <- dcast(OV, FY ~ factor(pattern, levels = unique(OV$pattern)), value.var = "permits")
print(setkey(ovw, NULL)[order(is.na(FY), FY)])
cat("\n== codes inside each set: rows / permits ==\n")
print(setkey(dcast(CD, FY ~ set + code, value.var = c("rows", "permits")), NULL))
side(c("permits_multi_code", "outfall_months_multi_code"), "permits / outfall-months with more than one code of the set")
side(c("pct_Q_slot", "pct_MK", "pct_DB", "pct_multi_month"), "composition: Q slot / MK / DB / multi-month (% of rows)")
side(c("pct_value", "pct_limit", "pct_censored"), "completeness: value / limit / censored (% of rows)")
side(c("pct_nodi", "pct_nodi_C", "pct_nodi_B"), "NODI: any / C no discharge / B below detection (% of rows)")
side(c("n_blank_value_and_nodi", "n_negative"), "data quality: blank value AND blank NODI / negative values (rows)")
side(c("pct_any_violation", "pct_E90", "pct_D90", "pct_D80"), "violation codes (% of rows)")
side(c("n_exceed", "pct_exceed_of_value_limit"), "exceedance, value > limit > 0 (rows; % of rows with value and limit > 0)")
side(c("permits_any_exceed", "pct_permits_any_exceed"), "permits with at least one exceedance (permits; % of permits)")
side(c("n_exceed_without_E90", "n_E90_without_exceed"), "exceedance vs E90 disagreement (rows)")
side(c("n_flag_multi_limit_id", "pct_flag_multi_limit_set"), "flags: FLAG_MULTI_LIMIT_ID rows / FLAG_MULTI_LIMIT_SET % of rows")

cat("\n== totals over FY", min(YEARS), "-FY", max(YEARS), " ==\n", sep = "")
print(S[, .(years = .N, rows = sum(rows), flag_multi_limit_id = sum(n_flag_multi_limit_id),
            flag_multi_limit_set = sum(n_flag_multi_limit_set),
            exceed_rows = sum(n_exceed), value_limit_rows = sum(rows_value_and_limit),
            min_permits = min(permits), max_permits = max(permits)), by = set])

o <- function(stem) file.path(ROOT, "output", sprintf("%s_%s.csv", stem, SPAN))
fwrite(S, o("summary_clean_dmr_by_year"))
fwrite(CD, o("summary_clean_dmr_by_year_codes"))
fwrite(OV, o("summary_clean_dmr_by_year_overlap"))
cat("\nTables written to output/: ", paste(basename(c(o("summary_clean_dmr_by_year"),
    o("summary_clean_dmr_by_year_codes"), o("summary_clean_dmr_by_year_overlap"))), collapse = ", "), "\n", sep = "")
