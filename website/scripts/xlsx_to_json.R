# Converts summarize.R's per-dataset xlsx workbooks (output/<prefix>_summary_*.xlsx)
# into JSON for the public website. Parses the fixed layout write_sheet() produces:
#   title / [highlevel] / summary / columns / blank / categorical table / blank /
#   numeric+date table / Notes
#
# Usage: Rscript website/scripts/xlsx_to_json.R
#   Reads DATASET_FILES below, writes website/data/<key>.json

library(openxlsx)
library(jsonlite)

# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))
JSON_DIR <- file.path(CWA_ROOT, "website/data")
dir.create(JSON_DIR, showWarnings = FALSE, recursive = TRUE)

# Pick the most recently modified file matching a prefix pattern, excluding
# Excel lock files (~$...). Returns NA (not an error) when nothing matches, so a
# partial build -- e.g. the memory-heavy `limits` summary failed this run --
# still refreshes the datasets that DID build and leaves the rest' JSON as-is.
latest_file <- function(pattern) {
  files <- list.files(OUT_DIR, pattern = pattern, full.names = TRUE)
  files <- files[!grepl("/~\\$", files)]
  if (length(files) == 0) {
    warning("No files matching: ", pattern, " -- skipping this dataset.")
    return(NA_character_)
  }
  files[order(file.info(files)$mtime, decreasing = TRUE)][1]
}

DATASET_FILES <- list(
  npdes                  = latest_file("^npdes_summary_.*\\.xlsx$"),
  dmrs                   = latest_file("^dmrs_summary_.*\\.xlsx$"),
  attains                = latest_file("^attains_summary_.*\\.xlsx$"),
  limits                 = latest_file("^npdes_limits_summary_.*\\.xlsx$"),
  master_general_permits = latest_file("^master_general_permits_summary_.*\\.xlsx$"),
  outfalls_layer         = latest_file("^outfalls_layer_summary_.*\\.xlsx$"),
  eff_violations_va      = latest_file("^eff_violations_va_summary_.*\\.xlsx$"),
  eff_violations_ny      = latest_file("^eff_violations_ny_summary_.*\\.xlsx$")
)
# Drop datasets with no workbook this run (keeps their existing JSON untouched).
DATASET_FILES <- DATASET_FILES[!vapply(DATASET_FILES, is.na, logical(1))]
if (length(DATASET_FILES) == 0)
  stop("No summary workbooks found in ", OUT_DIR,
       " -- run code/summary/summarize.R first.")

# Ground truth for which variables are dates, copied from each dataset's
# date_cols in code/summary/summarize.R's DATASETS registry (minus any
# year_cols, which that script deliberately keeps numeric). Needed because
# the numeric and date rows share one 9-column table in the sheet, so
# openxlsx's column-level detectDates can't tell them apart cell-by-cell.
DATE_COLS <- list(
  npdes = c("SETTLEMENT_ENTERED_DATE","ACHIEVED_DATE","ACTUAL_BEGIN_DATE","ACTUAL_END_DATE",
    "SCHEDULE_DATE","ACTUAL_DATE","RNC_DETECTION_DATE","RNC_RESOLUTION_DATE","REPORT_RECEIVED_DATE",
    "SINGLE_EVENT_VIOLATION_DATE","SINGLE_EVENT_END_DATE","ORIGINAL_ISSUE_DATE","ISSUE_DATE",
    "EFFECTIVE_DATE","EXPIRATION_DATE","RETIREMENT_DATE","TERMINATION_DATE","CREATED_DATE","UPDATED_DATE"),
  attains = character(0),
  limits = c("LIMIT_BEGIN_DATE","LIMIT_END_DATE"),
  master_general_permits = c("ORIGINAL_ISSUE_DATE","ISSUE_DATE","EFFECTIVE_DATE","EXPIRATION_DATE",
    "RETIREMENT_DATE","TERMINATION_DATE"),
  outfalls_layer = c("CWP_DATE_LAST_INSPECTION","DATE_LAST_FORMAL_EA","PERMIT_EFFECTIVE_DATE",
    "PERMIT_EXPIRATION_DATE","PERMIT_TERMINATION_DATE"),
  dmrs = c("LIMIT_BEGIN_DATE","LIMIT_END_DATE","MONITORING_PERIOD_END_DATE",
    "VALUE_RECEIVED_DATE","RNC_DETECTION_DATE","RNC_RESOLUTION_DATE"),
  eff_violations_va = c("MONITORING_PERIOD_END_DATE","VALUE_RECEIVED_DATE",
    "RNC_DETECTION_DATE","RNC_RESOLUTION_DATE"),
  eff_violations_ny = c("MONITORING_PERIOD_END_DATE","VALUE_RECEIVED_DATE",
    "RNC_DETECTION_DATE","RNC_RESOLUTION_DATE")
)

# Every read goes through these two options: fillMergedCells propagates a
# merged cell's value into its blank continuation rows (needed for the
# Variable / % Missing / n Categories columns); sep.names=" " stops
# read.xlsx from mangling headers like "% Missing" into "%.Missing".
read_ws <- function(path, sheet, ...) {
  readWorkbook(path, sheet = sheet, fillMergedCells = TRUE, sep.names = " ", ...)
}

parse_sheet <- function(path, sheet, date_cols = character(0)) {
  raw  <- read_ws(path, sheet, colNames = FALSE, skipEmptyRows = FALSE, detectDates = FALSE)
  col1 <- as.character(raw[[1]])
  n    <- nrow(raw)

  # A section-separator blank row has EVERY column empty. Column 1 alone is
  # not reliable: cat_rows() in summarize.R deliberately writes Variable = ""
  # (not the var name) for a wholly-missing categorical variable, so a
  # col1-only check would misread that data row as a section break.
  row_blank <- apply(raw, 1, function(row) all(is.na(row) | trimws(as.character(row)) == ""))

  title <- col1[1]
  r <- 2
  highlevel <- ""
  if (!startsWith(trimws(ifelse(is.na(col1[r]), "", col1[r])), "Observations:")) {
    highlevel <- ifelse(is.na(col1[r]), "", col1[r]); r <- r + 1
  }
  summary_line <- col1[r]; r <- r + 1
  columns_line <- col1[r]; r <- r + 1
  columns <- trimws(strsplit(sub("^Columns:\\s*", "", columns_line), ",")[[1]])

  while (r <= n && row_blank[r]) r <- r + 1

  categorical <- NULL
  if (r <= n && identical(trimws(col1[r]), "Variable")) {
    hdr_row <- r; r <- r + 1
    while (r <= n && !row_blank[r]) r <- r + 1
    end_data <- r - 1
    cat_raw <- read_ws(path, sheet, colNames = TRUE,
                        rows = hdr_row:end_data, detectDates = FALSE)
    if ("Missing Explanation" %in% names(cat_raw)) cat_raw[["Missing Explanation"]] <- NULL
    # summarize.R itself doesn't record the variable name for a wholly-missing
    # categorical variable (Variable = "" in that source code path) - the
    # website's table rendering falls back to a placeholder for these rows.
    categorical <- cat_raw
  }

  while (r <= n && row_blank[r]) r <- r + 1

  numeric_date <- NULL
  if (r <= n && identical(trimws(col1[r]), "Variable")) {
    hdr_row <- r; r <- r + 1
    while (r <= n && !row_blank[r] && !identical(trimws(col1[r]), "Notes")) r <- r + 1
    end_data <- r - 1
    # Read raw (no detectDates): numeric and date rows share these columns,
    # and openxlsx's detectDates works per-column, not per-row, so it would
    # otherwise convert every row's Min/Max to (often bogus) dates.
    nd_raw <- read_ws(path, sheet, colNames = TRUE,
                       rows = hdr_row:end_data, detectDates = FALSE)
    if ("Missing Explanation" %in% names(nd_raw)) nd_raw[["Missing Explanation"]] <- NULL
    is_date_row <- nd_raw[["Variable"]] %in% date_cols
    val_cols <- c("Min", "0.05", "Median", "Mean", "0.95", "Max")
    for (cc in intersect(val_cols, names(nd_raw))) {
      col <- nd_raw[[cc]]
      if (any(is_date_row)) {
        col[is_date_row] <- as.character(convertToDate(as.numeric(col[is_date_row])))
      }
      nd_raw[[cc]] <- col
    }
    numeric_date <- nd_raw
  }

  list(title = title, highlevel = highlevel, summary = summary_line,
       columns = columns, categorical = categorical, numeric_date = numeric_date)
}

for (key in names(DATASET_FILES)) {
  path <- DATASET_FILES[[key]]
  cat("Converting", key, "<-", basename(path), "\n")
  sheets <- getSheetNames(path)
  dcols <- DATE_COLS[[key]]
  result <- lapply(sheets, function(s) parse_sheet(path, s, date_cols = dcols))
  names(result) <- sheets
  out <- list(source_file = basename(path), dataset = key, sheets = result)
  write(toJSON(out, dataframe = "rows", na = "null", auto_unbox = TRUE, pretty = FALSE),
        file.path(JSON_DIR, paste0(key, ".json")))
}

cat("\nDone. JSON written to", JSON_DIR, "\n")
