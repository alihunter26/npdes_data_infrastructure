# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, PROC_DIR, OUT_DIR, ...)
# Walks up from THIS FILE's location, not getwd() (same block as build_dmr_clean_panel.R).
source(local({
  this <- NULL
  m <- grep("^--file=", commandArgs(FALSE), value = TRUE)            # Rscript
  if (length(m)) this <- sub("^--file=", "", m[[1]])
  if (is.null(this))                                                 # source() / RStudio Source
    for (i in rev(seq_len(sys.nframe()))) {
      of <- get0("ofile", envir = sys.frame(i), inherits = FALSE)
      if (is.character(of) && length(of) == 1L && nzchar(of)) { this <- of; break }
    }
  d <- if (is.null(this)) normalizePath(getwd(), mustWork = FALSE)    # console: last resort
       else dirname(normalizePath(this, mustWork = FALSE))
  while (!file.exists(file.path(d, "_paths.R")) && dirname(d) != d) d <- dirname(d)
  if (!file.exists(file.path(d, "_paths.R")))
    stop("Could not find _paths.R above ", if (is.null(this)) getwd() else this,
         " -- run this script from inside the CWA repo.", call. = FALSE)
  file.path(d, "_paths.R")
}))

# ==============================================================================
# build_permit_month_panels.R
# ------------------------------------------------------------------------------
# Permit-month panels built from the cleaned intermediate DMR panel, following
# CWA_Data_shared/Cleaned_Intermediate_DMR_TSS.docx.
#
#   1  permits that only ever have one row per month        -> all their rows
#   2  permits that only ever have one Q row per month      -> their Q rows only
#   3  permits that only ever have one C row per month      -> their C rows only
#      (1-3 balanced: each panel's permits x every month of the window; a month
#      without a row in the panel has blank row columns)
#   4  every permit x every month of the window (balanced) -> the one row with
#      the max value/limit ratio; a month with no rows has N_ROWS = 0
#   5  every permit x every month of the window (balanced) -> one aggregated row
#      (counts, ratios, flags, Q/C totals); a month with no rows has N_ROWS = 0
#
# Each output is one row per permit x YEAR x MONTH by construction (asserted).
#
# Definitions (Philip, 2026-11-09):
#   - Window FY2009-FY2025 by default; "only ever" is pooled over the whole
#     window, so one month with two rows anywhere excludes the permit.
#   - Month = YEAR/MONTH of MONITORING_PERIOD_END_DATE. Every row counts,
#     NODI-only rows included.
#   - Q = VALUE_TYPE_CODE Q1/Q2; C = C1/C2/C3. Panel 2 needs at least one Q row
#     (permits with no Q row ever are not in it); likewise panel 3 for C.
#     A month where a panel-2 permit has only C rows has a blank row in panel 2
#     with N_ROWS > 0.
#   - Facility = FACILITY_ID (FRS FACILITY_UIN, else the permit number).
#
# Panels 4 and 5 (Philip, 2026-11-09):
#   - Each row gets one STATUS: discharged (value other than 0; the few
#     negative values are kept at face value, see section 5); no_discharge (value = 0,
#     or blank value with NODI C); below_dl (blank value with NODI B, "Below
#     Detection Limit/No Detection"); no_report (blank value, any other NODI
#     code or none). The four add up to the row count.
#   - Ratio, discharging points = value / limit for discharged rows with a
#     limit > 0. Ratio, all points = the same, plus 0 for no_discharge rows
#     (and below_dl rows while B_AS_ZERO is TRUE) with a limit > 0. A blank
#     limit always gives NA. A limit of 0 is left out of every ratio, total and
#     average, and a discharge on one sets FLAG_ZERO_LIMIT_DISCHARGE.
#   - Panel 4 keeps the row with the max all-points ratio (ties: first row in
#     the cleaned panel's sort order). With no ratio in the month it keeps the
#     max Q value, else the max C value, else the first Q row, else the first C
#     row. SELECTED_BY says which rule picked the row.
#   - Exceedance = value > limit, limit > 0 (our calculation, '<' values
#     included). Number of violations counts codes (D90;E90 = 2).
#   - Q totals: discharged over Q rows with a value (no_discharge as 0);
#     permitted over Q rows with a limit > 0; TOTAL_Q_RATIO over Q rows having
#     both. Averages of discharge over rows with a value; of limit over limits > 0.
#   - Permit-month flags = any row in the month carries the row flag.
#
# All five panels are balanced (Philip, 2026-11-09):
#   - Panels 1-3: every permit in the panel gets every month of the requested
#     FYs. A month without a row in the panel has blank row columns (its two
#     row flags FALSE). N_ROWS = the cleaned panel's rows for the permit-month,
#     all bases, as in panels 4 and 5: 0 = nothing in the cleaned panel; > 0 on
#     a blank row = rows of the other basis only (panels 2 and 3).
#   - Panels 4 and 5: every permit in the window gets every month of the requested FYs
#     (FY2009-FY2025: 204 months), whether or not it existed then. A month with
#     no rows has N_ROWS = 0, every count 0, blank strings, NA ratios, totals and
#     averages, and FALSE flags. FY, FACILITY_ID and STATE_CODE come from the
#     permit (one value per permit, asserted), YEAR and MONTH from the month.
#     In panel 4 every other cleaned-panel column is blank (its two row flags
#     FALSE), and so are SELECTED_BY and ROW_STATUS.
#   - FLAG_MULTI_MONTH_COVERED: N_ROWS = 0, and the month lies inside the
#     monitoring period of a multi-month report (NMBR_OF_REPORT > 1, the number
#     of months the period covers) that the cleaned panel dates to a later month.
#   - Panel 5's row counts (Philip, 2026-11-09): N_DISCHARGED (value other
#     than 0), N_NO_DISCHARGE (value 0, or blank value with NODI C),
#     N_OTHER_NODI (blank value, any other NODI code, B included), N_NO_NODI
#     (blank value, no NODI code). The four add up to N_ROWS. N_BELOW_DL still
#     counts the below_dl rows on their own.
#
#   Input  : data/processed/clean_dmr_<FY>.csv for the years requested
#   Output : data/processed/dmr_pm{1_one_row,2_one_q,3_one_c}_fy<first>_<last>.csv
#            (balanced: FY column first, then the cleaned panel's 26 columns, all
#            text, then N_ROWS and FLAG_MULTI_MONTH_COVERED)
#            data/processed/dmr_pm4_max_ratio_fy<first>_<last>.csv  (balanced: the
#            same 27 columns for the selected row, then RATIO ... FLAG_MULTI_MONTH_COVERED)
#            data/processed/dmr_pm5_aggregate_fy<first>_<last>.csv  (balanced:
#            permits x months, 35 columns)
#   Run   : Rscript code/clean_dmr/build_permit_month_panels.R            # FY2009-FY2025
#            Rscript code/clean_dmr/build_permit_month_panels.R 2017       # any list of FYs
# ==============================================================================

suppressMessages(library(data.table))

args  <- commandArgs(trailingOnly = TRUE)
YEARS <- if (length(args)) as.integer(args) else 2009:2025
SPAN  <- sprintf("fy%d_%d", min(YEARS), max(YEARS))

fmt <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
of  <- function(a, b, what) sprintf("%s (%.2f%% of %s %s)", fmt(a), 100 * a / b, fmt(b), what)
say <- function(...) cat(..., "\n", sep = "")
KEY <- c("EXTERNAL_PERMIT_NMBR", "yr", "mo")

# ------------------------------------------------------------------------------
# 1. Load the cleaned panel
# ------------------------------------------------------------------------------
files <- file.path(PROC_DIR, sprintf("clean_dmr_%d.csv", YEARS))
if (any(!file.exists(files))) stop("Missing: ", paste(basename(files[!file.exists(files)]), collapse = ", "))
d <- rbindlist(lapply(seq_along(YEARS), function(i) {
  x <- fread(files[i], colClasses = "character")
  x[, FY := as.character(YEARS[i])]
  x
}), use.names = TRUE)
setcolorder(d, "FY")
OUT_COLS <- copy(names(d))
stopifnot(!anyNA(d))                       # every field read as text; blanks are ""

d[, `:=`(yr = as.integer(YEAR), mo = as.integer(MONTH), QC = substr(VALUE_TYPE_CODE, 1, 1))]
stopifnot(all(d$QC %in% c("Q", "C")))

say("==============================================================================")
say("Permit-month panels 1-5, ", SPAN, "  (", format(Sys.time(), "%Y-%m-%d %H:%M"), ")")
say("==============================================================================")

# ------------------------------------------------------------------------------
# 2. The parent: the cleaned panel over the window
# ------------------------------------------------------------------------------
pm <- d[, .(n = .N, nQ = sum(QC == "Q"), nC = sum(QC == "C"), nFY = uniqueN(FY)), by = KEY]
stopifnot(all(pm$nFY == 1L))               # no permit-month is split across FY files

U <- list(rows = nrow(d), perm = uniqueN(d$EXTERNAL_PERMIT_NMBR), pm = nrow(pm),
          rowsQ = sum(d$QC == "Q"), rowsC = sum(d$QC == "C"),
          permQ = uniqueN(d[QC == "Q", EXTERNAL_PERMIT_NMBR]),
          permC = uniqueN(d[QC == "C", EXTERNAL_PERMIT_NMBR]),
          pmQ = sum(pm$nQ > 0), pmC = sum(pm$nC > 0),
          fac = uniqueN(d$FACILITY_ID))

say("\n-- Cleaned panel over the window (the parent of every panel) --")
say("rows                ", fmt(U$rows), "  (Q ", fmt(U$rowsQ), ", C ", fmt(U$rowsC), ")")
say("permits             ", fmt(U$perm), "  (with any Q row ", fmt(U$permQ), ", with any C row ", fmt(U$permC), ")")
say("permit-months       ", fmt(U$pm), "  (with a Q row ", fmt(U$pmQ), ", with a C row ", fmt(U$pmC), ")")
say("facilities          ", fmt(U$fac))

# Facility facts (reported every run)
fb  <- d[FACILITY_ID == EXTERNAL_PERMIT_NMBR, uniqueN(EXTERNAL_PERMIT_NMBR)]
pf  <- d[, .(nf = uniqueN(FACILITY_ID)), by = EXTERNAL_PERMIT_NMBR][nf > 1L]
say("\n-- FACILITY_ID --")
say("permits whose FACILITY_ID falls back to the permit number (no FRS id): ", of(fb, U$perm, "permits"))
say("permits carrying more than one FACILITY_ID: ", fmt(nrow(pf)))

multi_fac <- function(x) {
  fm <- x[, .(np = uniqueN(EXTERNAL_PERMIT_NMBR)), by = .(FACILITY_ID, yr, mo)]
  list(fm = nrow(fm), fm_multi = sum(fm$np > 1L), fac = uniqueN(fm$FACILITY_ID),
       fac_multi = uniqueN(fm[np > 1L, FACILITY_ID]), ids = sort(unique(fm[np > 1L, FACILITY_ID])))
}
mfU <- multi_fac(d)
say("whole cleaned panel: facilities with >1 permit in some month: ",
    of(mfU$fac_multi, mfU$fac, "facilities"), "; facility-months with >1 permit: ",
    of(mfU$fm_multi, mfU$fm, "facility-months"))

# Checks promised in the scoping round
lid <- d[LIMIT_ID != "", .(ns = uniqueN(LIMIT_SET_ID)), by = LIMIT_ID][ns > 1L]
say("\n-- Checks --")
say("LIMIT_IDs that appear under more than one LIMIT_SET_ID: ", fmt(nrow(lid)),
    "  (rows with a blank LIMIT_ID: ", fmt(sum(d$LIMIT_ID == "")), ")")
both <- d[DMR_VALUE_STANDARD_UNITS != "" & NODI_CODE != ""]
say("rows with both a value and a NODI code: ", fmt(nrow(both)))
if (nrow(both))
  print(both[, .(FY, EXTERNAL_PERMIT_NMBR, PERM_FEATURE_NMBR, MONITORING_PERIOD_END_DATE,
                 VALUE_TYPE_CODE, DMR_VALUE_STANDARD_UNITS, NODI_CODE, LIMIT_VALUE_STANDARD_UNITS)])

# ------------------------------------------------------------------------------
# 3. Qualifying permits and the three panels
# ------------------------------------------------------------------------------
pp <- pm[, .(max_n = max(n), max_Q = max(nQ), max_C = max(nC)), by = EXTERNAL_PERMIT_NMBR]
P <- list(
  p1 = d[EXTERNAL_PERMIT_NMBR %in% pp[max_n == 1L, EXTERNAL_PERMIT_NMBR]],
  p2 = d[QC == "Q" & EXTERNAL_PERMIT_NMBR %in% pp[max_Q == 1L, EXTERNAL_PERMIT_NMBR]],   # max 1 => has Q, never 2+
  p3 = d[QC == "C" & EXTERNAL_PERMIT_NMBR %in% pp[max_C == 1L, EXTERNAL_PERMIT_NMBR]]
)
for (p in P) stopifnot(!anyDuplicated(p, by = KEY))

LAB <- c(p1 = "Panel 1: permits with only ever one row per month (all rows)",
         p2 = "Panel 2: permits with only ever one Q row per month (Q rows only)",
         p3 = "Panel 3: permits with only ever one C row per month (C rows only)")

report <- function(k) {
  p  <- P[[k]]; N <- nrow(p); np <- uniqueN(p$EXTERNAL_PERMIT_NMBR)
  say("\n==============================================================================")
  say(LAB[[k]])
  say("==============================================================================")
  say("permits recovered        ", of(np, U$perm, "permits in the cleaned panel"))
  if (k == "p2") say("                         ", of(np, U$permQ, "permits with any Q row"))
  if (k == "p3") say("                         ", of(np, U$permC, "permits with any C row"))
  say("observations recovered   ", of(N, U$rows, "cleaned-panel rows"))
  say("  (1 row = 1 permit-month) ", of(N, U$pm, "cleaned-panel permit-months"))
  if (k == "p2") say("                         ", of(N, U$rowsQ, "Q rows in the cleaned panel"))
  if (k == "p3") say("                         ", of(N, U$rowsC, "C rows in the cleaned panel"))
  if (k == "p1") {
    sw <- p[, uniqueN(QC), by = EXTERNAL_PERMIT_NMBR][V1 > 1L, .N]
    say("permits whose single row is Q in some months and C in others: ", of(sw, np, "panel-1 permits"))
  }

  mf <- multi_fac(p)
  say("facilities with >1 permit in a single month: ", of(mf$fac_multi, mf$fac, "facilities in this panel"))
  say("  facility-months with >1 permit:             ", of(mf$fm_multi, mf$fm, "facility-months in this panel"))
  if (mf$fac_multi > 0L && mf$fac_multi <= 10L) say("  FACILITY_IDs: ", paste(mf$ids, collapse = ", "))

  v <- p$DMR_VALUE_STANDARD_UNITS; nd <- p$NODI_CODE; lm <- p$LIMIT_VALUE_STANDARD_UNITS
  limn <- suppressWarnings(as.numeric(lm)); stopifnot(!anyNA(limn[lm != ""]))
  say("discharge info (share of the ", fmt(N), " rows in this panel)")
  say("  value reported                    ", of(sum(v != ""), N, "rows"))
  say("  blank value, NODI C (no discharge) ", of(sum(v == "" & nd == "C"), N, "rows"))
  say("  blank value, other NODI code      ", of(sum(v == "" & !nd %in% c("", "C")), N, "rows"))
  say("  blank value, no NODI code         ", of(sum(v == "" & nd == ""), N, "rows"))
  say("limit info (share of the ", fmt(N), " rows in this panel)")
  say("  limit > 0                         ", of(sum(lm != "" & limn > 0), N, "rows"))
  say("  limit = 0                         ", of(sum(lm != "" & limn == 0), N, "rows"))
  say("  limit blank                       ", of(sum(lm == ""), N, "rows"))
}
for (k in names(P)) report(k)

# ------------------------------------------------------------------------------
# Balancing, shared by all five panels: every permit x every month of the
# requested FYs (FY y = Oct y-1 .. Sep y). zk = the months with no rows.
# ------------------------------------------------------------------------------
pa   <- unique(d[, .(EXTERNAL_PERMIT_NMBR, FACILITY_ID, STATE_CODE)])
stopifnot(!anyDuplicated(pa$EXTERNAL_PERMIT_NMBR))                 # one facility and state per permit
mons <- rbindlist(lapply(YEARS, function(y) data.table(yr = c(rep(y - 1L, 3L), rep(y, 9L)), mo = c(10:12, 1:9))))
grid <- CJ(EXTERNAL_PERMIT_NMBR = pa$EXTERNAL_PERMIT_NMBR, i = seq_len(nrow(mons)))
grid[, `:=`(yr = mons$yr[i], mo = mons$mo[i])][, i := NULL]
stopifnot(nrow(pm[!grid, on = KEY]) == 0L)                         # every observed month is in the grid
zk <- pa[grid[!pm, on = KEY], on = "EXTERNAL_PERMIT_NMBR"]
zk[, `:=`(FY = as.character(yr + (mo >= 10L)), FLAG_MULTI_MONTH_COVERED = FALSE)]
# Months inside a multi-month report's period, before the month it is dated to
cv <- unique(d[as.integer(NMBR_OF_REPORT) > 1L, .(EXTERNAL_PERMIT_NMBR, m = yr * 12L + mo - 1L, nrep = as.integer(NMBR_OF_REPORT))])
cv <- unique(cv[, .(cm = m - seq_len(nrep - 1L)), by = .(EXTERNAL_PERMIT_NMBR, m, nrep)][
  , .(EXTERNAL_PERMIT_NMBR, yr = cm %/% 12L, mo = cm %% 12L + 1L)])
zk[cv, FLAG_MULTI_MONTH_COVERED := TRUE, on = KEY]
stopifnot(nrow(zk) + U$pm == U$perm * nrow(mons))
rm(grid, cv)

# ------------------------------------------------------------------------------
# 4. Balance panels 1-3 (each over its own permits) and write
# ------------------------------------------------------------------------------
P13_COLS <- c(OUT_COLS, "N_ROWS", "FLAG_MULTI_MONTH_COVERED")
balance13 <- function(p) {
  perm <- unique(p$EXTERNAL_PERMIT_NMBR)
  g <- CJ(EXTERNAL_PERMIT_NMBR = perm, i = seq_len(nrow(mons)))
  g[, `:=`(yr = mons$yr[i], mo = mons$mo[i])][, i := NULL]
  stopifnot(nrow(p[!g, on = KEY]) == 0L, all(p$YEAR == as.character(p$yr)), all(p$MONTH == as.character(p$mo)))
  e <- pa[g[!p, on = KEY], on = "EXTERNAL_PERMIT_NMBR"]
  e[, `:=`(FY = as.character(yr + (mo >= 10L)), YEAR = as.character(yr), MONTH = as.character(mo))]
  for (v in setdiff(OUT_COLS, names(e))) set(e, j = v, value = "")
  e[, `:=`(FLAG_MULTI_LIMIT_ID = "FALSE", FLAG_MULTI_LIMIT_SET = "FALSE")]
  cols <- unique(c(KEY, OUT_COLS))
  b <- rbind(p[, ..cols], e[, ..cols])
  b <- pm[, .(EXTERNAL_PERMIT_NMBR, yr, mo, N_ROWS = n)][b, on = KEY]      # rows in the cleaned panel, all bases
  b[is.na(N_ROWS), N_ROWS := 0L]
  b[, FLAG_MULTI_MONTH_COVERED := FALSE][zk[FLAG_MULTI_MONTH_COVERED == TRUE], FLAG_MULTI_MONTH_COVERED := TRUE, on = KEY]
  setorderv(b, KEY)
  stopifnot(nrow(b) == length(perm) * nrow(mons), !anyDuplicated(b, by = KEY),
            sum(b$VALUE_TYPE_CODE != "") == nrow(p), all(b[VALUE_TYPE_CODE != ""]$N_ROWS >= 1L))
  b
}
NAMES <- c(p1 = "1_one_row", p2 = "2_one_q", p3 = "3_one_c")
say("\n==============================================================================")
say("Panels 1-3 balanced: each panel's permits x ", nrow(mons), " months")
say("==============================================================================")
for (k in names(P)) {
  b <- balance13(P[[k]])
  n <- nrow(b); row <- b$VALUE_TYPE_CODE != ""
  say(k, ": ", fmt(n), " permit-months = ", fmt(uniqueN(b$EXTERNAL_PERMIT_NMBR)), " permits x ", nrow(mons),
      "; with a row ", of(sum(row), n, "permit-months"))
  say("    no row, N_ROWS = 0 (nothing in the cleaned panel) ", of(sum(!row & b$N_ROWS == 0L), n, "permit-months"),
      "; of which FLAG_MULTI_MONTH_COVERED ", fmt(sum(b$FLAG_MULTI_MONTH_COVERED)))
  say("    no row, N_ROWS > 0 (rows of the other basis only)  ", of(sum(!row & b$N_ROWS > 0L), n, "permit-months"),
      " in ", fmt(uniqueN(b[!row & N_ROWS > 0L]$EXTERNAL_PERMIT_NMBR)), " permits")
  f <- file.path(PROC_DIR, sprintf("dmr_pm%s_%s.csv", NAMES[[k]], SPAN))
  fwrite(b[, ..P13_COLS], f)
  say("    wrote ", fmt(n), " rows -> ", sub(paste0(CWA_ROOT, "/"), "", f))
}
rm(P, b)

# ==============================================================================
# 5. Row classification shared by panels 4 and 5
# ==============================================================================
# Toggle: NODI B rows take ratio 0, like no_discharge rows, in the all-points
# ratio, in panel 4's selection and in TOTAL_DISCHARGED_Q. Whatever this is
# set to, they keep STATUS "below_dl", and panel 5 counts them in
# N_OTHER_NODI and on their own in N_BELOW_DL.
B_AS_ZERO <- TRUE

num <- function(x) { y <- suppressWarnings(as.numeric(x)); stopifnot(!anyNA(y[x != ""])); y }
d[, `:=`(val = num(DMR_VALUE_STANDARD_UNITS), lim = num(LIMIT_VALUE_STANDARD_UNITS),
         nrep = as.integer(NMBR_OF_REPORT), rowid = .I)]          # rowid = cleaned-panel sort order
stopifnot(all(d$lim >= 0, na.rm = TRUE), !anyNA(d$nrep),
          all(d$FLAG_MULTI_LIMIT_SET %in% c("TRUE", "FALSE")), all(d$FLAG_MULTI_LIMIT_ID %in% c("TRUE", "FALSE")),
          d[, uniqueN(STATE_CODE), by = EXTERNAL_PERMIT_NMBR][, max(V1)] == 1L)

# A negative value (rare; possibly a net-of-intake value, unchecked) is not
# covered by the agreed rules. It is treated as a reported discharge and kept
# at face value in ratios and averages; the log counts these rows.
d[, STATUS := fcase(!is.na(val) & val != 0,                                     "discharged",
                    (!is.na(val) & val == 0) | (is.na(val) & NODI_CODE == "C"), "no_discharge",
                    is.na(val) & NODI_CODE == "B",                              "below_dl",
                    default =                                                   "no_report")]
d[, limpos  := !is.na(lim) & lim > 0]
d[, as_zero := STATUS == "no_discharge" | (B_AS_ZERO & STATUS == "below_dl")]
d[, r_dis   := fifelse(STATUS == "discharged" & limpos, val / lim, NA_real_)]
d[, r_all   := fifelse(!is.na(r_dis), r_dis, fifelse(as_zero & limpos, 0, NA_real_))]
d[, dval    := fifelse(!is.na(val), val, fifelse(as_zero, 0, NA_real_))]   # discharge, no_discharge as 0
d[, exc     := !is.na(val) & limpos & val > lim]
d[, exc_pct := fifelse(exc, 100 * (val - lim) / lim, NA_real_)]
d[, n_viol  := fifelse(VIOLATION_CODE == "", 0L,
                       nchar(VIOLATION_CODE) - nchar(gsub(";", "", VIOLATION_CODE, fixed = TRUE)) + 1L)]
d[, `:=`(is_dis = as.integer(STATUS == "discharged"), is_nd = as.integer(STATUS == "no_discharge"),
         is_bdl = as.integer(STATUS == "below_dl"),
         is_on  = as.integer(is.na(val) & !NODI_CODE %in% c("", "C")),   # other NODI code, B included
         is_nn  = as.integer(is.na(val) & NODI_CODE == ""),              # no value, no NODI code
         is_lim = as.integer(!is.na(lim)),            is_exc = as.integer(exc),
         is_zld = as.integer(STATUS == "discharged" & !is.na(lim) & lim == 0),
         is_mls = as.integer(FLAG_MULTI_LIMIT_SET == "TRUE"), is_mli = as.integer(FLAG_MULTI_LIMIT_ID == "TRUE"))]

say("\n==============================================================================")
say("Row status, used by panels 4 and 5 (B_AS_ZERO = ", B_AS_ZERO, ")")
say("==============================================================================")
for (s in c("discharged", "no_discharge", "below_dl", "no_report"))
  say(sprintf("  %-13s ", s), of(sum(d$STATUS == s), U$rows, "cleaned-panel rows"))
say("  discharged rows with a NEGATIVE value (kept at face value): ", fmt(d[!is.na(val) & val < 0, .N]),
    " rows, ", fmt(d[!is.na(val) & val < 0, uniqueN(EXTERNAL_PERMIT_NMBR)]), " permits")
say("  no_discharge split: reported 0 ", fmt(d[STATUS == "no_discharge" & !is.na(val), .N]),
    ", NODI C ", fmt(d[STATUS == "no_discharge" & is.na(val), .N]))
nr <- d[STATUS == "no_report", .N, by = NODI_CODE][order(-N)]
say("  no_report by NODI code (blank = none): ",
    paste(sprintf("%s %s", fifelse(nr$NODI_CODE == "", "blank", nr$NODI_CODE), fmt(nr$N)), collapse = ", "))
say("  below_dl rows with a limit > 0 (ratio 0 while B_AS_ZERO, else NA): ", fmt(d[STATUS == "below_dl" & limpos, .N]))

# ------------------------------------------------------------------------------
# Month-level pieces (computed on subsets, so an empty subset gives NA, not -Inf)
# ------------------------------------------------------------------------------
agg <- d[, .(N_ROWS = .N, N_DISCHARGED = sum(is_dis), N_NO_DISCHARGE = sum(is_nd),
             N_OTHER_NODI = sum(is_on), N_NO_NODI = sum(is_nn), N_BELOW_DL = sum(is_bdl), N_LIMITED = sum(is_lim),
             N_VIOLATIONS = sum(n_viol), N_EXCEEDANCES = sum(is_exc),
             mls = max(is_mls), mli = max(is_mli), zld = max(is_zld),
             MEDIAN_NMBR_OF_REPORT = median(nrep), MIN_NMBR_OF_REPORT = min(nrep)), by = KEY]
stopifnot(nrow(agg) == U$pm, sum(agg$N_ROWS) == U$rows,
          with(agg, all(N_DISCHARGED + N_NO_DISCHARGE + N_OTHER_NODI + N_NO_NODI == N_ROWS)),
          with(agg, all(N_BELOW_DL <= N_OTHER_NODI)))
pieces <- list(
  d[NODI_CODE != "",      .(NODI_STRING = paste(NODI_CODE, collapse = ";")), by = KEY],
  d[!is.na(r_dis),        .(MAX_RATIO_DISCH = max(r_dis), MEAN_RATIO_DISCH = mean(r_dis)), by = KEY],
  d[!is.na(r_all),        .(MAX_RATIO_ALL = max(r_all), MEAN_RATIO_ALL = mean(r_all)), by = KEY],
  d[VIOLATION_CODE != "", .(VIOLATION_STRING = paste(VIOLATION_CODE, collapse = ";")), by = KEY],
  d[exc == TRUE,          .(AVG_EXCEEDANCE_PCT = mean(exc_pct)), by = KEY],
  d[QC == "Q" & !is.na(dval),           .(TOTAL_DISCHARGED_Q = sum(dval)), by = KEY],
  d[QC == "Q" & limpos,                 .(TOTAL_PERMITTED_Q = sum(lim)), by = KEY],
  d[QC == "Q" & !is.na(dval) & limpos,  .(TOTAL_Q_RATIO = sum(dval) / sum(lim)), by = KEY],
  d[QC == "Q" & !is.na(val),            .(AVG_DISCHARGE_Q = mean(val)), by = KEY],
  d[QC == "Q" & limpos,                 .(AVG_LIMIT_Q = mean(lim)), by = KEY],
  d[QC == "C" & !is.na(val),            .(AVG_DISCHARGE_C = mean(val)), by = KEY],
  d[QC == "C" & limpos,                 .(AVG_LIMIT_C = mean(lim)), by = KEY])
for (p in pieces) agg <- merge(agg, p, by = KEY, all.x = TRUE)
agg[is.na(NODI_STRING), NODI_STRING := ""][is.na(VIOLATION_STRING), VIOLATION_STRING := ""]
rm(pieces)


# ==============================================================================
# 6. Panel 4: one selected row per permit-month
# ==============================================================================
SEL <- c("max_ratio", "max_Q_value", "max_C_value", "no_value_first_Q", "no_value_first_C")
d[, tier  := fcase(!is.na(r_all), 1L, QC == "Q" & !is.na(val), 2L, QC == "C" & !is.na(val), 3L,
                   QC == "Q", 4L, default = 5L)]
d[, score := fcase(tier == 1L, r_all, tier <= 3L, val, default = 0)]
p4 <- unique(d[order(EXTERNAL_PERMIT_NMBR, yr, mo, tier, -score, rowid)], by = KEY)
stopifnot(nrow(p4) == U$pm)
p4[, `:=`(RATIO = r_all, SELECTED_BY = SEL[tier], ROW_STATUS = STATUS)]
p4 <- agg[, .(EXTERNAL_PERMIT_NMBR, yr, mo, N_ROWS, ANY_DISCHARGED = N_DISCHARGED > 0L,
              NODI_STRING_MONTH = NODI_STRING, FLAG_ZERO_LIMIT_DISCHARGE = zld == 1L)][p4, on = KEY]
P4_COLS <- c(OUT_COLS, "RATIO", "SELECTED_BY", "ROW_STATUS", "N_ROWS", "ANY_DISCHARGED",
             "NODI_STRING_MONTH", "FLAG_ZERO_LIMIT_DISCHARGE", "FLAG_MULTI_MONTH_COVERED")
p4[, FLAG_MULTI_MONTH_COVERED := FALSE]
stopifnot(all(p4$YEAR == as.character(p4$yr)), all(p4$MONTH == as.character(p4$mo)))

M <- U$pm
say("\n==============================================================================")
say("Panel 4: one row per permit-month, the max value/limit ratio")
say("==============================================================================")
say("permit-months            ", fmt(nrow(p4)), " (all of the cleaned panel's ", fmt(M), "); permits ",
    fmt(uniqueN(p4$EXTERNAL_PERMIT_NMBR)))
say("row picked by (share of the ", fmt(M), " permit-months)")
for (i in seq_along(SEL)) say(sprintf("  %-17s ", SEL[i]), of(sum(p4$tier == i), M, "permit-months"))
nt <- d[!is.na(r_all), .(nmax = sum(r_all == max(r_all))), by = KEY]
say("  ties at the max ratio, broken by sort order: ", of(sum(nt$nmax > 1L), nrow(nt), "permit-months with a ratio"),
    "; at ratio 0: ", fmt(sum(nt$nmax > 1L & p4[nt, on = KEY]$RATIO == 0)))
ob <- d[!is.na(r_all), .(onlyB = all(STATUS == "below_dl")), by = KEY]
say("  ratio rests on below_dl rows alone (NA if B_AS_ZERO were FALSE): ", fmt(sum(ob$onlyB)), " permit-months")
say("RATIO NA                 ", of(sum(is.na(p4$RATIO)), M, "permit-months"))
say("RATIO > 1 (above limit)  ", of(sum(p4$RATIO > 1, na.rm = TRUE), M, "permit-months"))
say("discharge info on the selected row (share of the ", fmt(M), " permit-months)")
for (s in c("discharged", "no_discharge", "below_dl", "no_report"))
  say(sprintf("  %-13s ", s), of(sum(p4$ROW_STATUS == s), M, "permit-months"))
say("  ANY_DISCHARGED (some row in the month is discharged): ", of(sum(p4$ANY_DISCHARGED), M, "permit-months"))
say("  selected row not discharged, yet ANY_DISCHARGED:     ",
    of(sum(p4$ROW_STATUS != "discharged" & p4$ANY_DISCHARGED), M, "permit-months"))
say("limit info on the selected row (share of the ", fmt(M), " permit-months)")
say("  limit > 0 ", of(sum(p4$limpos), M, "permit-months"), "; limit = 0 ",
    of(sum(!is.na(p4$lim) & p4$lim == 0), M, "permit-months"), "; limit blank ", of(sum(is.na(p4$lim)), M, "permit-months"))
say("FLAG_ZERO_LIMIT_DISCHARGE ", of(sum(p4$FLAG_ZERO_LIMIT_DISCHARGE), M, "permit-months"))

# Balance panel 4: one row per zero month, the selected-row columns blank
z4 <- copy(zk)[, `:=`(YEAR = as.character(yr), MONTH = as.character(mo))]
for (v in setdiff(OUT_COLS, names(z4))) set(z4, j = v, value = "")
z4[, `:=`(FLAG_MULTI_LIMIT_ID = "FALSE", FLAG_MULTI_LIMIT_SET = "FALSE", RATIO = NA_real_, SELECTED_BY = "",
          ROW_STATUS = "", N_ROWS = 0L, ANY_DISCHARGED = FALSE, NODI_STRING_MONTH = "", FLAG_ZERO_LIMIT_DISCHARGE = FALSE)]
p4w <- rbind(p4[, unique(c(KEY, P4_COLS)), with = FALSE], z4[, unique(c(KEY, P4_COLS)), with = FALSE])
setorderv(p4w, KEY)
stopifnot(nrow(p4w) == U$perm * nrow(mons), !anyDuplicated(p4w, by = KEY), sum(p4w$N_ROWS > 0L) == U$pm)
say("balanced: ", fmt(nrow(p4w)), " permit-months = ", fmt(U$perm), " permits x ", nrow(mons), " months; N_ROWS = 0 ",
    of(nrow(z4), nrow(p4w), "permit-months"), "; FLAG_MULTI_MONTH_COVERED ", fmt(sum(z4$FLAG_MULTI_MONTH_COVERED)))
say("  (every line above counts the ", fmt(M), " permit-months with rows)")
rm(z4)

# ==============================================================================
# 7. Panel 5: one aggregated row per permit-month
# ==============================================================================
p5 <- p4[, .(EXTERNAL_PERMIT_NMBR, yr, mo, FY, FACILITY_ID, STATE_CODE)][agg, on = KEY]
p5[, `:=`(FLAG_MULTI_LIMIT_SET = mls == 1L, FLAG_MULTI_LIMIT_ID = mli == 1L, FLAG_ZERO_LIMIT_DISCHARGE = zld == 1L,
          FLAG_MULTI_MONTH_COVERED = FALSE)][, c("mls", "mli", "zld") := NULL]
stopifnot(all(p5$FY == as.character(p5$yr + (p5$mo >= 10L))))     # file FY = FY of the month

# Balance with the shared zero months
z <- copy(zk)
for (v in c("N_ROWS", "N_DISCHARGED", "N_NO_DISCHARGE", "N_OTHER_NODI", "N_NO_NODI", "N_BELOW_DL", "N_LIMITED",
            "N_VIOLATIONS", "N_EXCEEDANCES")) set(z, j = v, value = 0L)
z[, `:=`(NODI_STRING = "", VIOLATION_STRING = "", FLAG_MULTI_LIMIT_SET = FALSE, FLAG_MULTI_LIMIT_ID = FALSE,
         FLAG_ZERO_LIMIT_DISCHARGE = FALSE)]
p5 <- rbind(p5, z, fill = TRUE)
setorderv(p5, KEY)
rm(z)

setnames(p5, c("yr", "mo"), c("YEAR", "MONTH"))
P5_COLS <- c("FY", "FACILITY_ID", "EXTERNAL_PERMIT_NMBR", "STATE_CODE", "YEAR", "MONTH",
             "N_ROWS", "N_DISCHARGED", "N_NO_DISCHARGE", "N_OTHER_NODI", "N_NO_NODI", "N_BELOW_DL", "N_LIMITED",
             "NODI_STRING", "MAX_RATIO_DISCH", "MEAN_RATIO_DISCH", "MAX_RATIO_ALL", "MEAN_RATIO_ALL",
             "N_VIOLATIONS", "VIOLATION_STRING", "N_EXCEEDANCES", "AVG_EXCEEDANCE_PCT",
             "FLAG_MULTI_LIMIT_SET", "FLAG_MULTI_LIMIT_ID", "FLAG_ZERO_LIMIT_DISCHARGE", "FLAG_MULTI_MONTH_COVERED",
             "TOTAL_DISCHARGED_Q", "TOTAL_PERMITTED_Q", "TOTAL_Q_RATIO", "AVG_DISCHARGE_Q", "AVG_LIMIT_Q",
             "AVG_DISCHARGE_C", "AVG_LIMIT_C", "MEDIAN_NMBR_OF_REPORT", "MIN_NMBR_OF_REPORT")
stopifnot(setequal(P5_COLS, names(p5)), nrow(p5) == U$perm * nrow(mons), sum(p5$N_ROWS > 0L) == U$pm,
          !anyDuplicated(p5, by = c("EXTERNAL_PERMIT_NMBR", "YEAR", "MONTH")))
po <- p5[N_ROWS > 0L]                                              # the observed permit-months

perm_ever <- function(flag) uniqueN(po[get(flag) == TRUE, EXTERNAL_PERMIT_NMBR])
BN <- nrow(p5)
say("\n==============================================================================")
say("Panel 5: one aggregated row per permit x month, balanced")
say("==============================================================================")
say("permit-months            ", fmt(BN), " = ", fmt(U$perm), " permits x ", nrow(mons), " months")
say("  with rows (observed)   ", of(nrow(po), BN, "permit-months"))
say("  N_ROWS = 0             ", of(BN - nrow(po), BN, "permit-months"))
say("    FLAG_MULTI_MONTH_COVERED ", of(sum(p5$FLAG_MULTI_MONTH_COVERED), BN - nrow(po), "N_ROWS = 0 permit-months"))
say("rows by type (cleaned-panel rows; the four add up to ", fmt(U$rows), ")")
for (v in c("N_DISCHARGED", "N_NO_DISCHARGE", "N_OTHER_NODI", "N_NO_NODI"))
  say(sprintf("  %-15s ", v), of(sum(p5[[v]]), U$rows, "rows"), "; permit-months with >= 1: ",
      of(sum(p5[[v]] > 0L), BN, "permit-months"))
say(sprintf("  %-15s ", "N_BELOW_DL"), of(sum(p5$N_BELOW_DL), U$rows, "rows"), " (inside N_OTHER_NODI)")
# Which of the four row types a month has: D discharged, N no_discharge, O other NODI, X no NODI; ---- = no rows
pat <- with(p5, paste0(fifelse(N_DISCHARGED > 0L, "D", "-"), fifelse(N_NO_DISCHARGE > 0L, "N", "-"),
                       fifelse(N_OTHER_NODI > 0L, "O", "-"), fifelse(N_NO_NODI > 0L, "X", "-")))
pt <- data.table(pat)[, .N, by = pat][order(-N)]
say("row types present in the month (D discharged, N no_discharge, O other NODI, X no NODI; ---- no rows):")
for (i in seq_len(nrow(pt))) say(sprintf("  %s  ", pt$pat[i]), of(pt$N[i], BN, "permit-months"))
stopifnot(sum(pt$N) == BN)
say("\nobserved permit-months only from here (", fmt(nrow(po)), ")")
M <- nrow(po)
for (f in c("FLAG_MULTI_LIMIT_SET", "FLAG_MULTI_LIMIT_ID", "FLAG_ZERO_LIMIT_DISCHARGE")) {
  say(f)
  say("  permit-months flagged  ", of(sum(po[[f]]), M, "permit-months"))
  say("  permits ever flagged   ", of(perm_ever(f), U$perm, "permits"))
}
say("both limit flags in the same permit-month: ", fmt(sum(po$FLAG_MULTI_LIMIT_SET & po$FLAG_MULTI_LIMIT_ID)))
say("discharge info (share of the ", fmt(M), " permit-months)")
say("  every row no value, no NODI code  ", of(sum(po$N_NO_NODI == po$N_ROWS), M, "permit-months"))
say("  every row no value (any NODI code but C, or none) ",
    of(sum(po$N_OTHER_NODI + po$N_NO_NODI == po$N_ROWS), M, "permit-months"))
say("  no discharged row      ", of(sum(po$N_DISCHARGED == 0L), M, "permit-months"))
say("limit info (share of the ", fmt(M), " permit-months)")
say("  no row has a limit     ", of(sum(po$N_LIMITED == 0L), M, "permit-months"))
say("  at least one row without a limit ", of(sum(po$N_LIMITED < po$N_ROWS), M, "permit-months"))
say("ratios NA (share of the ", fmt(M), " permit-months)")
say("  MAX_RATIO_DISCH NA     ", of(sum(is.na(po$MAX_RATIO_DISCH)), M, "permit-months"))
say("  MAX_RATIO_ALL NA       ", of(sum(is.na(po$MAX_RATIO_ALL)), M, "permit-months"))
pq <- po[pm[nQ > 0L], on = c(EXTERNAL_PERMIT_NMBR = "EXTERNAL_PERMIT_NMBR", YEAR = "yr", MONTH = "mo")]
stopifnot(nrow(pq) == U$pmQ)
say("  TOTAL_Q_RATIO NA       ", of(sum(is.na(pq$TOTAL_Q_RATIO)), U$pmQ, "permit-months with a Q row"))
say("exceedances (ours: value > limit > 0, '<' included): ", fmt(sum(po$N_EXCEEDANCES)), " rows in ",
    fmt(sum(po$N_EXCEEDANCES > 0L)), " permit-months")
say("  of which '<' values: ", fmt(d[exc == TRUE & DMR_VALUE_QUALIFIER_CODE == "<", .N]))
say("  vs EPA EXCEEDENCE_PCT filled (", fmt(sum(d$EXCEEDENCE_PCT != "")), " rows): both ",
    fmt(d[exc == TRUE & EXCEEDENCE_PCT != "", .N]), ", ours only ", fmt(d[exc == TRUE & EXCEEDENCE_PCT == "", .N]),
    ", EPA only ", fmt(d[exc == FALSE & EXCEEDENCE_PCT != "", .N]), "  <- EPA-only rows: open item")
say("violation codes: ", fmt(sum(po$N_VIOLATIONS)), " in ", fmt(sum(po$N_VIOLATIONS > 0L)), " permit-months")

# ------------------------------------------------------------------------------
# 8. Write panels 4 and 5
# ------------------------------------------------------------------------------
say("")
f4 <- file.path(PROC_DIR, sprintf("dmr_pm4_max_ratio_%s.csv", SPAN))
fwrite(p4w[, ..P4_COLS], f4)
say("wrote ", fmt(nrow(p4w)), " rows -> ", sub(paste0(CWA_ROOT, "/"), "", f4))
f5 <- file.path(PROC_DIR, sprintf("dmr_pm5_aggregate_%s.csv", SPAN))
fwrite(p5[, ..P5_COLS], f5)
say("wrote ", fmt(nrow(p5)), " rows -> ", sub(paste0(CWA_ROOT, "/"), "", f5))
