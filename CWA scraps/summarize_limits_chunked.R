# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# summarize_limits_chunked.R
# Memory-bounded version of summarize_limits.R for NPDES_LIMITS.csv (~6.8 GB /
# 16.6M rows), designed to run in ~8 GB RAM. Produces the same workbook.
#
# Strategy: MULTI-PASS by COLUMN GROUP. fread parses the whole file each pass but
# materializes only a few columns, so memory stays bounded — and fread (not us)
# handles the file's quoting and ~3% embedded-newline records, so it's exact and
# robust. Every kept column is read in exactly one pass; each pass also emits a
# 60-bit row-hash of its columns into a fingerprint table, and the duplicate-row
# count is duplicated() over those fingerprint columns (= duplicates over all
# columns, with negligible hash-collision risk).

library(data.table)
library(openxlsx)
library(digest)
library(bit64)

options(openxlsx.dateFormat = "mm/dd/yyyy")

# ── Configuration ─────────────────────────────────────────────────────────────

DATA_FILE <- file.path(CWA_ROOT, "data/raw/NPDES_LIMITS.csv")
OUT_FILE  <- sprintf(file.path(CWA_ROOT, "output/npdes_limits_summary_%s.xlsx"),
                     format(Sys.time(), "%Y-%m-%d_%H%M"))

COL_BATCH <- 12L      # character columns read per categorical pass (memory knob)
DEV_NROWS <- NULL     # NULL = whole file; set to e.g. 1e6 for a fast dev run

DROP_COLS <- c(
  "ACTIVITY_ID", "PERM_FEATURE_ID", "LIMIT_SET_ID", "LIMIT_SET_SCHEDULE_ID",
  "LIMIT_ID", "LIMIT_VALUE_ID", "LIMIT_SEASON_ID", "LIMIT_SET_NAME",
  "DMR_COMMENT_TEXT")
ID_COLS       <- c("EXTERNAL_PERMIT_NMBR", "VERSION_NMBR", "PERM_FEATURE_NMBR")
NUMERIC_COLS  <- c("NMBR_OF_SUBMISSION", "NMBR_OF_REPORT", "LIMIT_VALUE_NMBR",
                   "LIMIT_VALUE_STANDARD_UNITS", "STAY_VALUE_NMBR")
DATE_COLS     <- c("LIMIT_BEGIN_DATE", "LIMIT_END_DATE")
PERMIT_ID_COL <- "EXTERNAL_PERMIT_NMBR"

TITLE_DESC <- "the numeric discharge limits written into each permit"
HIGHLEVEL  <- paste(
  "One row per permit limit: a specific numeric limit for one pollutant, at one",
  "discharge point (outfall), under one permit, during one effective period. Carries",
  "the limit value, units, statistical basis (e.g. daily max vs monthly average),",
  "monitoring frequency, effective date range, and seasonal applicability by month",
  "(the JAN-DEC flags). It does NOT contain the facility's reported discharge —",
  "pair with the DMR data for actual-vs-allowed.")

# ── Styles (identical to summarize_npdes.R) ───────────────────────────────────

style_title    <- createStyle(fontSize = 11, textDecoration = "bold")
style_meta     <- createStyle(fontSize = 10)
style_highlevel <- createStyle(fontSize = 10, textDecoration = "italic")
style_hdr_cat  <- createStyle(fontSize = 10, textDecoration = "bold",
                               fgFill = "#D9E1F2", border = "Bottom", borderStyle = "medium")
style_hdr_num  <- createStyle(fontSize = 10, textDecoration = "bold",
                               fgFill = "#F4B942", border = "Bottom", borderStyle = "medium")
style_body     <- createStyle(fontSize = 10)
style_number   <- createStyle(fontSize = 10, numFmt = "#,##0.###")
style_int      <- createStyle(fontSize = 10, numFmt = "#,##0")
style_date     <- createStyle(fontSize = 10, numFmt = "mm/dd/yyyy")
style_valign   <- createStyle(fontSize = 10, valign = "top")

# ── Helpers ───────────────────────────────────────────────────────────────────

find_desc_col <- function(var, all_cols) {
  candidate <- sub("_CODE$", "_DESC", var)
  if (candidate != var && candidate %in% all_cols) return(candidate)
  candidate2 <- paste0(var, "_DESC")
  if (candidate2 %in% all_cols) return(candidate2)
  NULL
}

# xxhash64 hex -> integer64 using low 60 bits (15 hex chars). 64 bits would exceed
# signed int64 and bit64 turns that into NA; 60 bits is safe and collisions over
# ~17M rows are ~1e-4. Pieces (3+4+4+4 hex) each fit strtoi's integer range.
hex2i64 <- function(hx) {
  a <- as.integer64(strtoi(substr(hx, 1, 3), 16L))
  b <- strtoi(substr(hx, 4, 7), 16L)
  c <- strtoi(substr(hx, 8, 11), 16L)
  d <- strtoi(substr(hx, 12, 15), 16L)
  ((a * 65536L + b) * 65536L + c) * 65536L + d
}
vdig <- getVDigest(algo = "xxhash64")
row_hash <- function(dt) hex2i64(vdig(do.call(paste, c(as.list(dt), sep = "\x1f")), serialize = FALSE))

# Robust whole-file read of selected columns (fread handles quotes/newlines).
read_cols <- function(cols) {
  dt <- fread(DATA_FILE, select = cols, colClasses = "character",
              na.strings = c("", "NA"), nrows = if (is.null(DEV_NROWS)) Inf else DEV_NROWS,
              showProgress = FALSE)
  dt[, (cols) := lapply(.SD, function(z) { z[trimws(z) == ""] <- NA; z })]  # " " -> NA
  dt[]
}

cat_block <- function(freq, na, n_rows, var, desc_map = NULL, top_n = 5) {
  n_total <- sum(freq); n_cat <- length(freq); pct_mis <- round(100 * na / n_rows, 1)
  if (n_cat == 0)
    return(list(df = data.frame(Variable="", `% Missing`=pct_mis, `n Categories`=0,
                  `Frequent Values`="(all missing)", `%`=NA, n=NA, Description="",
                  check.names=FALSE, stringsAsFactors=FALSE), n_rows = 1))
  top  <- head(sort(freq, decreasing = TRUE), top_n)
  vals <- names(top); nr <- length(top)
  desc_vec <- if (!is.null(desc_map)) unname(desc_map[vals]) else rep("", nr)
  desc_vec[is.na(desc_vec)] <- ""
  df <- data.frame(
    Variable=c(var, rep("", nr-1)), `% Missing`=c(pct_mis, rep(NA, nr-1)),
    `n Categories`=c(n_cat, rep(NA, nr-1)), `Frequent Values`=vals,
    `%`=round(as.numeric(top)/n_total*100, 1), n=as.integer(top), Description=desc_vec,
    check.names=FALSE, stringsAsFactors=FALSE)
  list(df = df, n_rows = nr)
}

num_row <- function(vals, n_rows, var) {
  na <- n_rows - length(vals)
  v <- if (length(vals) == 0) rep(NA_real_, 6) else
    c(min(vals), unname(quantile(vals, .05)), median(vals),
      mean(vals), unname(quantile(vals, .95)), max(vals))
  data.frame(Variable=var, `% Missing`=round(100*na/n_rows, 1),
             Min=round(v[1],3), `0.05`=round(v[2],3), Median=round(v[3],3),
             Mean=round(v[4],3), `0.95`=round(v[5],3), Max=round(v[6],3),
             check.names=FALSE, stringsAsFactors=FALSE)
}

date_row <- function(numvals, n_rows, var) {
  na <- n_rows - length(numvals)
  d <- if (length(numvals) == 0) rep(as.Date(NA), 6) else {
    s <- c(min(numvals), unname(quantile(numvals, .05)), median(numvals),
           mean(numvals), unname(quantile(numvals, .95)), max(numvals))
    as.Date(round(s), origin = "1970-01-01")
  }
  data.frame(Variable=var, `% Missing`=round(100*na/n_rows, 1),
             Min=d[1], `0.05`=d[2], Median=d[3], Mean=d[4], `0.95`=d[5], Max=d[6],
             check.names=FALSE, stringsAsFactors=FALSE)
}

# ── Plan columns and passes ───────────────────────────────────────────────────

hdr  <- names(fread(DATA_FILE, nrows = 0))
keep <- setdiff(hdr, DROP_COLS)
num_cols  <- intersect(NUMERIC_COLS, keep)
date_cols <- intersect(DATE_COLS, keep)
cat_all   <- setdiff(keep, c(ID_COLS, num_cols, date_cols))
code_cols <- cat_all[vapply(cat_all, function(v) !is.null(find_desc_col(v, keep)), logical(1))]
desc_part <- setNames(lapply(code_cols, find_desc_col, all_cols = keep), code_cols)
cat_vars  <- setdiff(cat_all, unlist(desc_part))   # displayed cats (drop _DESC partners)

# Columns handled in the categorical/other passes = everything except num/date.
# Pack into batches of <= COL_BATCH columns, keeping each code+desc pair together.
others <- setdiff(keep, c(num_cols, date_cols))
units <- list(); seen <- character(0)
for (col in others) {
  if (col %in% seen) next
  d <- if (col %in% code_cols) desc_part[[col]] else NULL
  unit <- if (!is.null(d) && d %in% others) c(col, d) else col
  units[[length(units) + 1]] <- unit; seen <- c(seen, unit)
}
cat_batches <- list(); cur <- character(0)
for (u in units) {
  if (length(cur) + length(u) > COL_BATCH && length(cur) > 0) { cat_batches[[length(cat_batches)+1]] <- cur; cur <- character(0) }
  cur <- c(cur, u)
}
if (length(cur) > 0) cat_batches[[length(cat_batches)+1]] <- cur

# ── Accumulators ──────────────────────────────────────────────────────────────

n_rows   <- 0L
freq     <- setNames(vector("list", length(cat_vars)), cat_vars)
na_cat   <- setNames(integer(length(cat_vars)), cat_vars)
desc_map <- setNames(vector("list", length(code_cols)), code_cols)
numvals  <- setNames(vector("list", length(num_cols)), num_cols)
datevals <- setNames(vector("list", length(date_cols)), date_cols)
perm_set <- character(0)
fp <- NULL; hp <- 0L

add_fp <- function(dt) { hp <<- hp + 1L; if (is.null(fp)) fp <<- data.table(.r = seq_len(nrow(dt))); fp[[paste0("h", hp)]] <<- row_hash(dt) }

# ── Pass 1: numeric ───────────────────────────────────────────────────────────

if (length(num_cols)) {
  cat("pass numeric:", paste(num_cols, collapse=", "), "\n")
  dt <- read_cols(num_cols); n_rows <- nrow(dt)
  for (nc in num_cols) { x <- suppressWarnings(as.numeric(dt[[nc]])); numvals[[nc]] <- x[!is.na(x)] }
  add_fp(dt); rm(dt); gc(FALSE)
}

# ── Pass 2: dates ─────────────────────────────────────────────────────────────

if (length(date_cols)) {
  cat("pass dates:", paste(date_cols, collapse=", "), "\n")
  dt <- read_cols(date_cols); n_rows <- nrow(dt)
  for (dc in date_cols) { x <- as.Date(dt[[dc]], format = "%m/%d/%Y"); datevals[[dc]] <- as.numeric(x[!is.na(x)]) }
  add_fp(dt); rm(dt); gc(FALSE)
}

# ── Passes 3+: categorical / id batches ───────────────────────────────────────

for (bi in seq_along(cat_batches)) {
  b <- cat_batches[[bi]]
  cat(sprintf("pass cat %d/%d: %s\n", bi, length(cat_batches), paste(b, collapse=", ")))
  dt <- read_cols(b); n_rows <- nrow(dt)
  for (v in intersect(b, cat_vars)) {
    x <- dt[[v]]; na_cat[v] <- sum(is.na(x)); freq[[v]] <- table(x[!is.na(x)])
  }
  for (cc in intersect(b, code_cols)) {
    dcol <- desc_part[[cc]]
    tab <- dt[!is.na(get(cc)) & !is.na(get(dcol)), .N, by = .(val = get(cc), descv = get(dcol))]
    if (nrow(tab)) { m <- tab[order(-N)][, .(descv = descv[1]), by = val]; desc_map[[cc]] <- setNames(m$descv, m$val) }
  }
  if (PERMIT_ID_COL %in% b) perm_set <- unique(dt[[PERMIT_ID_COL]])
  add_fp(dt); rm(dt); gc(FALSE)
}

# ── Finalize ──────────────────────────────────────────────────────────────────

fp[, .r := NULL]
n_dup   <- sum(duplicated(fp))
permits <- format(length(setdiff(perm_set, NA)), big.mark = ",")

all_days <- unlist(datevals)
year_range <- if (length(all_days)) {
  sprintf("%d-%d", as.integer(format(as.Date(min(all_days), origin="1970-01-01"), "%Y")),
                   as.integer(format(as.Date(max(all_days), origin="1970-01-01"), "%Y")))
} else "N/A"

cat_results <- lapply(cat_vars, function(v)
  cat_block(freq[[v]], na_cat[v], n_rows, v, desc_map = if (v %in% code_cols) desc_map[[v]] else NULL))
cat_df <- do.call(rbind, lapply(cat_results, `[[`, "df"))
group_sizes <- vapply(cat_results, `[[`, integer(1), "n_rows")

num_df  <- if (length(num_cols))  do.call(rbind, lapply(num_cols,  function(v) num_row(numvals[[v]],  n_rows, v))) else NULL
date_df <- if (length(date_cols)) do.call(rbind, lapply(date_cols, function(v) date_row(datevals[[v]], n_rows, v))) else NULL

meta <- list(
  title     = paste0(basename(DATA_FILE), ": ", TITLE_DESC),
  highlevel = HIGHLEVEL,
  summary   = sprintf("Observations: %s, Distinct Permits: %s, Temporal Range: %s, Duplicate Rows: %s",
                      format(n_rows, big.mark=",", trim=TRUE), permits, year_range,
                      format(n_dup, big.mark=",", trim=TRUE)),
  columns   = paste(keep, collapse = ", "))

# ── Write worksheet (same layout as summarize_npdes.R) ────────────────────────

wb <- createWorkbook(); sheet <- "NPDES_LIMITS"; addWorksheet(wb, sheet); row <- 1
writeData(wb, sheet, meta$title, startRow=row, startCol=1); addStyle(wb, sheet, style_title, row, 1); row <- row+1
writeData(wb, sheet, meta$highlevel, startRow=row, startCol=1); addStyle(wb, sheet, style_highlevel, row, 1); row <- row+1
writeData(wb, sheet, meta$summary, startRow=row, startCol=1); addStyle(wb, sheet, style_meta, row, 1); row <- row+1
writeData(wb, sheet, paste("Columns:", meta$columns), startRow=row, startCol=1); addStyle(wb, sheet, style_meta, row, 1); row <- row+2

writeData(wb, sheet, cat_df, startRow=row, startCol=1, colNames=TRUE, rowNames=FALSE)
addStyle(wb, sheet, style_hdr_cat, rows=row, cols=1:7, gridExpand=TRUE); row <- row+1
n_data <- nrow(cat_df)
addStyle(wb, sheet, style_body, rows=row:(row+n_data-1), cols=1:7, gridExpand=TRUE)
addStyle(wb, sheet, style_number, rows=row:(row+n_data-1), cols=c(2,5), gridExpand=TRUE, stack=TRUE)
addStyle(wb, sheet, style_int, rows=row:(row+n_data-1), cols=6, gridExpand=TRUE, stack=TRUE)
cur_row <- row
for (g in group_sizes) {
  if (g > 1) for (col in c(1,2,3)) {
    mergeCells(wb, sheet, cols=col, rows=cur_row:(cur_row+g-1))
    addStyle(wb, sheet, style_valign, rows=cur_row:(cur_row+g-1), cols=col, gridExpand=TRUE, stack=TRUE)
  }
  cur_row <- cur_row + g
}
row <- row + n_data + 2

hdr_row <- row
writeData(wb, sheet, x=t(c("Variable","% Missing","Min","0.05","Median","Mean","0.95","Max")),
          startRow=hdr_row, startCol=1, colNames=FALSE)
writeData(wb, sheet, x=0.05, startRow=hdr_row, startCol=4)
writeData(wb, sheet, x=0.95, startRow=hdr_row, startCol=7)
addStyle(wb, sheet, style_hdr_num, rows=hdr_row, cols=1:8, gridExpand=TRUE); row <- hdr_row+1
if (!is.null(num_df)) {
  writeData(wb, sheet, num_df, startRow=row, startCol=1, colNames=FALSE)
  nd <- nrow(num_df); addStyle(wb, sheet, style_body, rows=row:(row+nd-1), cols=1:8, gridExpand=TRUE)
  addStyle(wb, sheet, style_number, rows=row:(row+nd-1), cols=2:8, gridExpand=TRUE, stack=TRUE); row <- row+nd
}
if (!is.null(date_df)) {
  writeData(wb, sheet, date_df, startRow=row, startCol=1, colNames=FALSE)
  nd <- nrow(date_df); addStyle(wb, sheet, style_body, rows=row:(row+nd-1), cols=1:8, gridExpand=TRUE)
  addStyle(wb, sheet, style_number, rows=row:(row+nd-1), cols=2, gridExpand=TRUE, stack=TRUE)
  addStyle(wb, sheet, style_date, rows=row:(row+nd-1), cols=3:8, gridExpand=TRUE, stack=TRUE); row <- row+nd
}

setColWidths(wb, sheet, cols=1, widths=42); setColWidths(wb, sheet, cols=2, widths=11)
setColWidths(wb, sheet, cols=3, widths=13); setColWidths(wb, sheet, cols=4, widths=22)
setColWidths(wb, sheet, cols=5, widths=10); setColWidths(wb, sheet, cols=6, widths=12)
setColWidths(wb, sheet, cols=7, widths=38); setColWidths(wb, sheet, cols=8, widths=28)

saveWorkbook(wb, OUT_FILE, overwrite = TRUE)
cat(sprintf("\nDone! Observations: %s | Distinct Permits: %s | Duplicate Rows: %s\nSaved: %s\n",
            format(n_rows, big.mark=","), permits, format(n_dup, big.mark=","), OUT_FILE))
