# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# summarize_year_coverage.R
# ------------------------------------------------------------------------------
# Builds ONE summary table showing which years appear in each data file.
#
#   Rows    : one per (file, date/year variable)
#   Columns : one per year that is referenced in at least one dataset
#   Cells   : green with observation count if year appears, blank otherwise
#   File col: merged across all variables belonging to the same file
#
# Only columns whose NAME contains "DATE" or "YEAR" are read from each CSV, so
# even multi-GB files (e.g. NPDES_LIMITS.csv) are cheap to scan.
#
# The "year" for a value is a run of four consecutive digits, no date parsing:
#   - DATE columns -> the LAST 4-digit run (mm/dd/yyyy -> yyyy; also robust to
#     separator-less "10062005" -> 2005).
#   - YEAR columns -> the FIRST 4-digit run (YEARQTR "19924" -> 1992).
# ------------------------------------------------------------------------------

library(data.table)
library(openxlsx)

# ── Configuration ─────────────────────────────────────────────────────────────

DATA_DIR <- file.path(CWA_ROOT, "data/raw")
OUT_FILE <- sprintf(
  file.path(CWA_ROOT, "output/year_coverage_%s.xlsx"),
  format(Sys.time(), "%Y-%m-%d_%H%M"))

# Which columns count as a "year variable": name contains DATE or YEAR.
YEAR_COL_PATTERN <- "DATE|YEAR"

# Year-column bounds. Default NULL/NULL keeps EVERY year that appears (per your
# "flag but keep" choice). The script still PRINTS any year outside the
# plausible window below so outliers are visible; set these to actually drop
# columns from the table, e.g. YEAR_MIN <- 1950; YEAR_MAX <- 2026.
YEAR_MIN <- NULL
YEAR_MAX <- NULL

# Window used only for the console "outlier" flag (does not filter the table).
# Future expiration dates are legitimate, so the upper bound is generous; this
# flag is meant to surface obvious garbage (e.g. year 1, 2914, 8201).
PLAUSIBLE_MIN <- 1950
PLAUSIBLE_MAX <- 2100

# ── Styles (mirrors the green/merged look of the reference sheet) ──────────────

HEADER   <- "#D9E1F2"   # header band
# YlGn palette: light yellow (low) → dark green (high), 5 row-percentile buckets
GRADIENT <- c("#FFFFCC", "#C2E699", "#78C679", "#31A354", "#006837")

style_header <- createStyle(fontSize = 11, textDecoration = "bold",
                            fgFill = HEADER, halign = "center", valign = "center",
                            border = "TopBottomLeftRight", borderColour = "#BFBFBF")
style_file   <- createStyle(fontSize = 11, valign = "center",
                            border = "TopBottomLeftRight", borderColour = "#BFBFBF")
style_var    <- createStyle(fontSize = 11, valign = "center",
                            border = "TopBottomLeftRight", borderColour = "#BFBFBF")
g_styles     <- lapply(GRADIENT, function(col)
                  createStyle(fgFill = col, border = "TopBottomLeftRight",
                              borderColour = "#BFBFBF", numFmt = "#,##0", halign = "center"))
style_blank  <- createStyle(border = "TopBottomLeftRight", borderColour = "#BFBFBF")

# ── Helpers ───────────────────────────────────────────────────────────────────

# Observation counts by year for a vector. Builds a lookup from unique value →
# year string (last or first 4-digit run), then maps and counts all values.
year_counts <- function(x, which = c("last", "first")) {
  which  <- match.arg(which)
  x      <- x[!is.na(x)]
  if (length(x) == 0) return(integer(0))
  uvals  <- unique(x)
  m      <- regmatches(uvals, gregexpr("\\d{4}", uvals, perl = TRUE))
  yr_for <- vapply(m, function(z) {
    if (length(z) == 0) return(NA_character_)
    if (which == "last") z[length(z)] else z[1]
  }, character(1))
  # fread can strip leading zeros from "0000" → "0"; catch all-zero strings
  yr_for[grepl("^0+$", uvals, perl = TRUE)] <- "0"
  lookup  <- setNames(yr_for, as.character(uvals))
  yr_of_x <- lookup[as.character(x)]
  yr_of_x <- yr_of_x[!is.na(yr_of_x)]
  if (length(yr_of_x) == 0) return(integer(0))
  yr_of_x <- as.character(as.integer(yr_of_x))  # "0007" → "7", matches as.character(all_years)
  tbl <- table(yr_of_x)
  setNames(as.integer(tbl), names(tbl))
}

# ── Scan files ────────────────────────────────────────────────────────────────

csv_files <- list.files(DATA_DIR, pattern = "\\.csv$",
                        full.names = TRUE, recursive = TRUE)
if (length(csv_files) == 0) stop("No CSV files found in: ", DATA_DIR)

records  <- list()  # one entry per (file, variable): list(file, variable, counts)
skipped  <- character(0)
outliers <- list()  # flagged year outliers for the console report

for (f in csv_files) {
  fname  <- tools::file_path_sans_ext(basename(f))
  header <- names(fread(f, nrows = 0))
  ycols  <- header[grepl(YEAR_COL_PATTERN, header, ignore.case = TRUE)]

  if (length(ycols) == 0) {
    skipped <- c(skipped, basename(f))
    next
  }

  cat("Scanning", basename(f), "->", paste(ycols, collapse = ", "), "\n")
  # Read only the year/date columns, as character (no date parsing needed).
  dt <- fread(f, select = ycols, colClasses = "character",
              na.strings = c("", "NA"))

  for (col in ycols) {
    # DATE columns: year is the last 4-digit run; YEAR columns: the first.
    side <- if (grepl("DATE", col, ignore.case = TRUE)) "last" else "first"
    cnts <- year_counts(dt[[col]], which = side)
    if (length(cnts) == 0) next
    records[[length(records) + 1]] <- list(file = fname, variable = col, counts = cnts)

    yrs <- as.integer(names(cnts))
    bad <- yrs[yrs < PLAUSIBLE_MIN | yrs > PLAUSIBLE_MAX]
    if (length(bad) > 0)
      outliers[[length(outliers) + 1]] <-
        sprintf("  %-32s %-26s -> %s", fname, col, paste(bad, collapse = ", "))
  }
}

if (length(records) == 0) stop("No DATE/YEAR columns with parseable years found.")

# ── Assemble the table ────────────────────────────────────────────────────────

all_years <- sort(unique(as.integer(unlist(lapply(records, function(r) names(r$counts))))))
if (!is.null(YEAR_MIN)) all_years <- all_years[all_years >= YEAR_MIN]
if (!is.null(YEAR_MAX)) all_years <- all_years[all_years <= YEAR_MAX]

file_col <- vapply(records, `[[`, character(1), "file")
var_col  <- vapply(records, `[[`, character(1), "variable")
n        <- length(records)

# present[i, j] = observation count for record i in all_years[j] (0 = absent)
present <- matrix(0L, nrow = n, ncol = length(all_years),
                  dimnames = list(NULL, as.character(all_years)))
for (i in seq_len(n)) {
  cnts    <- records[[i]]$counts
  yr_cols <- intersect(names(cnts), as.character(all_years))
  present[i, yr_cols] <- cnts[yr_cols]
}

# ── Write workbook ────────────────────────────────────────────────────────────

wb    <- createWorkbook()
sheet <- "Year Coverage"
addWorksheet(wb, sheet)

YR_C0 <- 3                       # first year column (A=File, B=Variable)
last_col <- YR_C0 + length(all_years) - 1
data_r0  <- 2                    # first data row

# Header row
writeData(wb, sheet, x = "File",     startRow = 1, startCol = 1)
writeData(wb, sheet, x = "Variable", startRow = 1, startCol = 2)
writeData(wb, sheet, x = t(all_years), startRow = 1, startCol = YR_C0, colNames = FALSE)
addStyle(wb, sheet, style_header, rows = 1, cols = 1:last_col, gridExpand = TRUE)

# Variable column
writeData(wb, sheet, x = var_col, startRow = data_r0, startCol = 2, colNames = FALSE)
addStyle(wb, sheet, style_var, rows = data_r0:(data_r0 + n - 1), cols = 2)

# Write observation counts into year cells (0 → blank, counts show as numbers)
display_mat <- present
display_mat[display_mat == 0L] <- NA_integer_
writeData(wb, sheet, x = display_mat, startRow = data_r0, startCol = YR_C0,
          colNames = FALSE, rowNames = FALSE, na.string = "")

# Bordered grid for all year cells
addStyle(wb, sheet, style_blank, rows = data_r0:(data_r0 + n - 1),
         cols = YR_C0:last_col, gridExpand = TRUE)

# File column: write once per file, merge the run of rows, valign centered
rle_files <- rle(file_col)
cur <- data_r0
for (k in seq_along(rle_files$values)) {
  g <- rle_files$lengths[k]
  writeData(wb, sheet, x = rle_files$values[k], startRow = cur, startCol = 1)
  if (g > 1) mergeCells(wb, sheet, cols = 1, rows = cur:(cur + g - 1))
  addStyle(wb, sheet, style_file, rows = cur:(cur + g - 1), cols = 1, gridExpand = TRUE)
  cur <- cur + g
}

# Heatmap: assign each non-zero cell a gradient bucket from row-wise percentiles
n_buckets  <- length(g_styles)
bucket_mat <- matrix(0L, nrow = n, ncol = length(all_years))
for (i in seq_len(n)) {
  vals_i  <- present[i, ]
  nonzero <- vals_i[vals_i > 0L]
  if (length(nonzero) == 0) next
  breaks <- quantile(nonzero, probs = seq(0, 1, length.out = n_buckets + 1), type = 1)
  for (j in which(vals_i > 0L)) {
    b <- findInterval(vals_i[j], breaks, rightmost.closed = TRUE)
    bucket_mat[i, j] <- min(n_buckets, max(1L, b))
  }
}
for (b in seq_len(n_buckets)) {
  for (j in seq_along(all_years)) {
    rows_b <- which(bucket_mat[, j] == b)
    if (length(rows_b) > 0)
      addStyle(wb, sheet, g_styles[[b]],
               rows = rows_b + (data_r0 - 1), cols = YR_C0 + j - 1, gridExpand = TRUE)
  }
}

# Layout
setColWidths(wb, sheet, cols = 1, widths = 20)
setColWidths(wb, sheet, cols = 2, widths = 28)
setColWidths(wb, sheet, cols = YR_C0:last_col, widths = 9)
freezePane(wb, sheet, firstActiveRow = data_r0, firstActiveCol = YR_C0)

saveWorkbook(wb, OUT_FILE, overwrite = TRUE)

# ── Console report ────────────────────────────────────────────────────────────

cat("\nDone! Output saved to:", OUT_FILE, "\n")
cat(sprintf("Files with year/date columns: %d | rows (file x variable): %d | years: %d (%d-%d)\n",
            length(unique(file_col)), n, length(all_years),
            min(all_years), max(all_years)))
if (length(skipped) > 0)
  cat("\nSkipped (no DATE/YEAR columns):\n  ", paste(skipped, collapse = "\n  "), "\n", sep = "")
if (length(outliers) > 0) {
  cat(sprintf("\nFLAGGED year outliers (outside %d-%d, kept in table):\n",
              PLAUSIBLE_MIN, PLAUSIBLE_MAX))
  cat(paste(unlist(outliers), collapse = "\n"), "\n")
}
