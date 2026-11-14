# summarize_dmr_nesting.R
#
# How rows nest inside a permit-month in the cleaned intermediate DMR files
# (clean_dmr_<set>_<FY>.csv): the stats on the first page of
# CWA_Data_shared/DMR_TSS_panel_building.docx, for any parameter set, one row
# per fiscal year plus a pooled row.
#
# Usage, from the repo root:
#   Rscript code/summary/summarize_dmr_nesting.R tss              # every FY file found
#   Rscript code/summary/summarize_dmr_nesting.R bod 2009:2025    # a range
#   Rscript code/summary/summarize_dmr_nesting.R ammonia 2017 2024
#
# Output: OUT_DIR/dmr_nesting_<set>_fy<first>_<last>.csv, long format, one row
# per FY x stat: numerator n, denominator d, pct = 100 * n / d. FY "pooled"
# stacks the loaded years. The pct table is also printed.
#
# Reporting: for now, quote each stat as the range of its per-year values over
# FY2009-FY2025 (min-max across the FY rows), and say that it covers
# FY2009-FY2025. Example, TSS: 20.3-21.8% of permits have >= 2 outfalls in some
# permit-month. Don't quote the pooled row's permit counts (permits_*): a permit
# counts if it qualifies in any loaded year, so they grow with the window
# (TSS permits_multi_outfall: 27.2% pooled over FY2009-FY2025, 29.1% over all
# years). Pre-FY2009 years cover far fewer permits, so leave them out of ranges.
#
# Levels (each one splits the unit above it):
#   permit-month (permit x YEAR x MONTH)
#   > outfall
#   > parameter code (TSS has one; BOD 00310/80082; ammonia 00610/34726)
#   > statistical base > monitoring location > limit set
#   > value types (Q, C) x LIMIT_ID
# Stats:
#   permits_multi_outfall   permits with >= 2 outfalls in at least one
#                           permit-month (pooled: in any loaded year)
#   pm_multi_outfall        permit-months with >= 2 outfalls
#   om_in_multi_pm          outfall-months in those permit-months (the doc's ~45%)
#   rows_in_multi_pm        rows in those permit-months
#   om_multi_param          outfall-months with >= 2 parameter codes, and rows in them
#   *_multi_sb              outfall-month-parameters with >= 2 statistical bases;
#                           _permits counts permits (pooled: distinct over years);
#                           _also_multi_ls is the share of those with >= 2 limit sets;
#                           _top_pair is the most common pair of bases (note column)
#   *_multi_loc             statistical-base units with >= 2 monitoring locations
#   *_multi_ls              location units with >= 2 limit sets
#   units_/rows_<class>     limit-set units by what they report: Q only, C only or
#                           both, on one LIMIT_ID (single) or several (multi)
#
# The doc's own figures are mostly pooled over FY2009-FY2025 (its limit-set line
# is a per-year range). They reproduce on every line except the
# multiple-LIMIT_ID ones: 0.02/0.07% of units and 0.03/0.10% of rows here,
# against 0.03/0.11% and 0.03/0.17% in the doc. Cause not found.
#
# Reads only the columns it needs. Values are not used, so blanks don't matter.
# Needs data.table.

suppressPackageStartupMessages(library(data.table))

# ---- Settings --------------------------------------------------------------
DATA_DIR <- "data/processed"   # where clean_dmr_<set>_<FY>.csv live
OUT_DIR  <- "output"

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript summarize_dmr_nesting.R <set> [FY ...]")
SET    <- args[1]
PREFIX <- sprintf("clean_dmr_%s_", SET)
found  <- as.integer(sub(".*_(\\d{4})\\.csv$", "\\1",
            list.files(DATA_DIR, pattern = sprintf("^%s\\d{4}\\.csv$", PREFIX))))
YEARS  <- if (length(args) > 1) unlist(lapply(args[-1], function(a) eval(parse(text = a)))) else found
YEARS  <- sort(as.integer(YEARS))
if (!length(YEARS)) stop("No ", PREFIX, "<FY>.csv files in ", DATA_DIR)
missing_fy <- setdiff(YEARS, found)
if (length(missing_fy)) stop("No file for FY ", paste(missing_fy, collapse = ", "))

COLS <- c(permit = "EXTERNAL_PERMIT_NMBR", YEAR = "YEAR", MONTH = "MONTH",
          outfall = "PERM_FEATURE_NMBR", param = "PARAMETER_CODE",
          sb = "STATISTICAL_BASE_CODE", loc = "MONITORING_LOCATION_CODE",
          ls = "LIMIT_SET_ID", lid = "LIMIT_ID", vt = "VALUE_TYPE_CODE")

read_fy <- function(fy) {
  d <- fread(file.path(DATA_DIR, sprintf("%s%d.csv", PREFIX, fy)),
             colClasses = "character", select = unname(COLS))
  setnames(d, unname(COLS), names(COLS))
  # Every value type is Q* (mass) or C* (concentration)
  stopifnot(all(substr(d$vt, 1, 1) %in% c("Q", "C")))
  d[, is_q := as.integer(startsWith(vt, "Q"))]
  d[, FY := fy]
}

# Unit keys. YEAR/MONTH lie inside one FY, so units never cross years.
PM  <- c("permit", "YEAR", "MONTH")
OM  <- c(PM, "outfall")
OMP <- c(OM, "param")
SB  <- c(OMP, "sb")
LOC <- c(SB, "loc")
LS  <- c(LOC, "ls")

# One row per unit (`by`): its rows and its number of distinct `child` values.
# Counting via unique() and .N keeps every step inside data.table (fast).
units <- function(d, by, child) {
  u <- d[, .(rows = .N), keyby = by]
  k <- unique(d, by = c(by, child))[, .(k = .N), keyby = by]
  u[k, k := i.k, on = by]
  u
}

nest_stats <- function(d) {
  N <- nrow(d)
  s <- list()
  add <- function(stat, n, den, note = "") s[[length(s) + 1]] <<- data.table(stat, n, d = den, note)

  # Outfalls per permit-month
  u <- units(d, PM, "outfall")
  add("permits_multi_outfall", uniqueN(u[k > 1, permit]), uniqueN(u$permit))
  add("pm_multi_outfall", u[k > 1, .N], nrow(u))
  add("om_in_multi_pm", u[k > 1, sum(k)], sum(u$k))
  add("rows_in_multi_pm", u[k > 1, sum(rows)], N)

  # Parameter codes per outfall-month
  u <- units(d, OM, "param")
  add("om_multi_param", u[k > 1, .N], nrow(u))
  add("rows_in_multi_param", u[k > 1, sum(rows)], N)

  # Statistical bases per outfall-month-parameter
  u <- units(d, OMP, "sb")
  u[units(d, OMP, "ls"), nls := i.k, on = OMP]
  m <- u[k > 1]
  add("units_multi_sb", nrow(m), nrow(u))
  add("rows_in_multi_sb", sum(m$rows), N)
  add("permits_multi_sb", uniqueN(m$permit), uniqueN(u$permit))
  add("multi_sb_also_multi_ls", m[nls > 1, .N], nrow(m))
  if (nrow(m)) {
    pairs <- unique(d[m, on = OMP, c(OMP, "sb"), with = FALSE])[order(sb)][
      , .(pair = paste(sb, collapse = "+")), by = OMP][, .N, by = pair][order(-N)]
    add("multi_sb_top_pair", pairs$N[1], nrow(m), pairs$pair[1])
  } else add("multi_sb_top_pair", 0L, 0L)

  # Monitoring locations per statistical-base unit
  u <- units(d, SB, "loc")
  add("units_multi_loc", u[k > 1, .N], nrow(u))
  add("rows_in_multi_loc", u[k > 1, sum(rows)], N)

  # Limit sets per location unit
  u <- units(d, LOC, "ls")
  add("units_multi_ls", u[k > 1, .N], nrow(u))
  add("rows_in_multi_ls", u[k > 1, sum(rows)], N)

  # Value types x LIMIT_ID per limit-set unit
  u <- units(d, LS, "lid")
  u[d[, .(q = max(is_q), c = max(1L - is_q)), keyby = LS], `:=`(q = i.q, c = i.c), on = LS]
  u[, cls := paste0(fifelse(q & c, "both", fifelse(q == 1L, "Q", "C")),
                    fifelse(k > 1, "_multi", "_single"))]
  for (cl in c("Q_single", "C_single", "both_single", "Q_multi", "C_multi", "both_multi")) {
    add(paste0("units_", cl), u[cls == cl, .N], nrow(u))
    add(paste0("rows_", cl), u[cls == cl, sum(rows)], N)
  }

  add("rows", N, N)
  rbindlist(s)
}

dmr <- rbindlist(lapply(YEARS, read_fy))
cat(sprintf("%s: %d rows, FY %s\n", SET, nrow(dmr), paste(range(YEARS), collapse = "-")))

res <- rbindlist(c(
  lapply(YEARS, function(y) nest_stats(dmr[FY == y])[, FY := as.character(y)]),
  list(nest_stats(dmr)[, FY := "pooled"])))
res[, pct := round(100 * n / d, 2)]
setcolorder(res, c("FY", "stat", "n", "d", "pct", "note"))

dir.create(OUT_DIR, showWarnings = FALSE)
out <- file.path(OUT_DIR, sprintf("dmr_nesting_%s_fy%d_%d.csv", SET, min(YEARS), max(YEARS)))
fwrite(res, out)

wide <- dcast(res[stat != "rows"], stat ~ FY, value.var = "pct")
setcolorder(wide, c("stat", setdiff(names(wide), c("stat", "pooled")), "pooled"))
wide <- wide[match(unique(res$stat), stat)][!is.na(stat)]
options(width = 250)
print(wide, nrows = 100)
cat("\npermits_multi_sb (counts):", paste(res[stat == "permits_multi_sb", paste0(FY, "=", n)], collapse = " "), "\n")
cat("multi_sb_top_pair:", res[stat == "multi_sb_top_pair" & FY == "pooled", note], "\n")
cat("Wrote", out, "\n")
