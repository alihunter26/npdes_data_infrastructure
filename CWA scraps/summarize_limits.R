# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# summarize_limits.R
# Output: one Excel file (npdes_limits_summary.xlsx) with a single sheet
# summarizing NPDES_LIMITS.csv, in the same style as summarize_npdes.R.
#
# NOTE ON SIZE: NPDES_LIMITS.csv is ~6.8 GB / ~17.1M rows. To keep the full read
# in memory, surrogate-key and free-text columns that are never summarized are
# DROPPED at read time (see DROP_COLS). A full run still needs substantial RAM
# (~8-12 GB free). For a quick/low-memory look, set SAMPLE_N to read only the
# first N rows (fast, but NOT representative — the file is ordered by permit).

library(dplyr)
library(data.table)
library(lubridate)
library(openxlsx)

# Render dates as month/day/year throughout the workbook
options(openxlsx.dateFormat = "mm/dd/yyyy")

# ── Configuration ─────────────────────────────────────────────────────────────

DATA_FILE <- file.path(CWA_ROOT, "data/raw/NPDES_LIMITS.csv")
# Timestamped output so each run writes its own file (date + time, to the minute)
OUT_FILE  <- sprintf(file.path(CWA_ROOT, "output/npdes_limits_summary_%s.xlsx"),
                     format(Sys.time(), "%Y-%m-%d_%H%M"))

# NULL = read the full file (exact). Set to e.g. 2e6 for a fast first-N-rows
# preview run (approximate, not representative).
SAMPLE_N <- NULL

# Permit-level key used for the "Distinct Permits" meta count.
PERMIT_ID_COL <- "EXTERNAL_PERMIT_NMBR"

# Surrogate keys and free-text columns that are never summarized — dropped at
# read time purely to save memory on this large file.
DROP_COLS <- c(
  "ACTIVITY_ID", "PERM_FEATURE_ID", "LIMIT_SET_ID", "LIMIT_SET_SCHEDULE_ID",
  "LIMIT_ID", "LIMIT_VALUE_ID", "LIMIT_SEASON_ID", "LIMIT_SET_NAME",
  "DMR_COMMENT_TEXT"
)

# Identifier columns: loaded (used for meta counts) but excluded from per-variable
# summaries, exactly like summarize_npdes.R.
ID_COLS <- c("EXTERNAL_PERMIT_NMBR", "VERSION_NMBR", "PERM_FEATURE_NMBR")

DATE_COLS <- c("LIMIT_BEGIN_DATE", "LIMIT_END_DATE")

DESCRIPTIONS <- c(
  "NPDES_LIMITS.csv" = "the numeric discharge limits written into each permit"
)

SHEET_SUMMARIES <- c(
  "NPDES_LIMITS.csv" =
    "One row per permit limit: a specific numeric limit for one pollutant, at one discharge point (outfall), under one permit, during one effective period. Carries the limit value, units, statistical basis (e.g. daily max vs monthly average), monitoring frequency, effective date range, and seasonal applicability by month (the JAN-DEC columns). It does NOT contain the facility's reported discharge — pair with the DMR data for actual-vs-allowed."
)

# ── Styles ────────────────────────────────────────────────────────────────────

style_title    <- createStyle(fontSize = 11, textDecoration = "bold")
style_meta     <- createStyle(fontSize = 10)
style_highlevel <- createStyle(fontSize = 10, textDecoration = "italic")
style_hdr_cat  <- createStyle(fontSize = 10, textDecoration = "bold",
                               fgFill = "#D9E1F2", border = "Bottom",
                               borderStyle = "medium")
style_hdr_num  <- createStyle(fontSize = 10, textDecoration = "bold",
                               fgFill = "#F4B942", border = "Bottom",
                               borderStyle = "medium")
style_section  <- createStyle(fontSize = 10, textDecoration = "bold",
                               fgFill = "#F2F2F2")
style_body     <- createStyle(fontSize = 10)
style_number   <- createStyle(fontSize = 10, numFmt = "#,##0.###")
style_int      <- createStyle(fontSize = 10, numFmt = "#,##0")
style_date     <- createStyle(fontSize = 10, numFmt = "mm/dd/yyyy")
style_valign   <- createStyle(fontSize = 10, valign = "top")

# ── Helpers (identical logic to summarize_npdes.R) ────────────────────────────

# Percent (0-100) of values that are missing, rounded to 1 decimal.
pct_missing <- function(x) round(mean(is.na(x)) * 100, 1)

# For a code column, look for a paired description column (e.g. LIMIT_UNIT_CODE → LIMIT_UNIT_DESC)
find_desc_col <- function(var, all_cols) {
  candidate <- sub("_CODE$", "_DESC", var)
  if (candidate != var && candidate %in% all_cols) return(candidate)
  candidate2 <- paste0(var, "_DESC")
  if (candidate2 %in% all_cols) return(candidate2)
  NULL
}

# Returns data frame with one row per top-N value
cat_rows <- function(x, var_name, desc_x = NULL, top_n = 5) {
  tbl     <- sort(table(x, useNA = "no"), decreasing = TRUE)
  n_total <- sum(!is.na(x))
  n_cat   <- length(tbl)
  pct_mis <- pct_missing(x)

  if (n_cat == 0) {
    return(list(
      df = data.frame(Variable="", `% Missing`=pct_mis, `n Categories`=0,
                      `Frequent Values`="(all missing)", `%`=NA, n=NA,
                      Description="",
                      check.names=FALSE, stringsAsFactors=FALSE),
      var_label = var_name, n_rows = 1
    ))
  }

  top    <- head(tbl, top_n)
  n_rows <- length(top)
  vals   <- names(top)

  desc_vec <- if (!is.null(desc_x)) {
    sapply(vals, function(v) {
      matches <- desc_x[!is.na(x) & x == v & !is.na(desc_x)]
      if (length(matches) == 0) return("")
      names(sort(table(matches), decreasing = TRUE))[1]
    })
  } else rep("", n_rows)

  df <- data.frame(
    Variable        = c(var_name, rep("", n_rows - 1)),
    `% Missing`     = c(pct_mis,  rep(NA,       n_rows - 1)),
    `n Categories`  = c(n_cat,    rep(NA,        n_rows - 1)),
    `Frequent Values` = vals,
    `%`             = round(as.numeric(top) / n_total * 100, 1),
    n               = as.integer(top),
    Description     = desc_vec,
    check.names = FALSE, stringsAsFactors = FALSE
  )

  list(df = df, var_label = var_name, n_rows = n_rows)
}

num_summary_row <- function(x, var_name) {
  xc <- x[!is.na(x)]
  if (length(xc) == 0)
    vals <- rep(NA_real_, 6)
  else
    vals <- c(min(xc), unname(quantile(xc, 0.05)), median(xc),
              mean(xc), unname(quantile(xc, 0.95)), max(xc))
  data.frame(Variable=var_name, `% Missing`=pct_missing(x),
             Min=round(vals[1], 3), `0.05`=round(vals[2], 3), Median=round(vals[3], 3),
             Mean=round(vals[4], 3), `0.95`=round(vals[5], 3), Max=round(vals[6], 3),
             check.names=FALSE, stringsAsFactors=FALSE)
}

# One row per date variable: stats kept as Date objects so they display as m/d/y.
date_summary_row <- function(x, var_name) {
  xc <- x[!is.na(x)]
  if (length(xc) == 0) {
    d <- rep(as.Date(NA), 6)
  } else {
    nums <- as.numeric(xc)
    s <- c(min(nums), unname(quantile(nums, 0.05)), median(nums),
           mean(nums), unname(quantile(nums, 0.95)), max(nums))
    d <- as.Date(round(s), origin = "1970-01-01")
  }
  data.frame(Variable=var_name, `% Missing`=pct_missing(x),
             Min=d[1], `0.05`=d[2], Median=d[3],
             Mean=d[4], `0.95`=d[5], Max=d[6],
             check.names=FALSE, stringsAsFactors=FALSE)
}

# ── Build summary ─────────────────────────────────────────────────────────────

build_summary_df <- function(file_path) {

  read_args <- list(file = file_path, na.strings = c("", "NA"),
                    drop = DROP_COLS, showProgress = FALSE)
  if (!is.null(SAMPLE_N)) read_args$nrows <- SAMPLE_N
  df <- as.data.frame(do.call(fread, read_args))

  # Treat whitespace-only character cells (e.g. " ") as missing, not a category.
  char_cols <- names(df)[vapply(df, is.character, logical(1))]
  for (cc in char_cols) df[[cc]][trimws(df[[cc]]) == ""] <- NA_character_
  n_rows <- nrow(df)

  # Parse date columns (mm/dd/yyyy, with a tolerant fallback)
  cols_to_summarise <- setdiff(names(df), ID_COLS)
  date_cols_present <- intersect(DATE_COLS, names(df))
  for (col in date_cols_present) {
    parsed <- suppressWarnings(as.Date(df[[col]], format = "%m/%d/%Y"))
    if (sum(!is.na(parsed)) >= sum(!is.na(df[[col]])) * 0.5)
      df[[col]] <- parsed
    else
      df[[col]] <- as.Date(suppressWarnings(
        parse_date_time(df[[col]], orders = c("mdy","ymd","dmy"), quiet = TRUE)))
  }

  # Year range from any date column
  all_years <- unlist(lapply(date_cols_present, function(col) {
    if (inherits(df[[col]], "Date")) as.integer(format(df[[col]], "%Y"))
  }))
  year_range <- if (length(all_years) > 0)
    sprintf("%d-%d", min(all_years, na.rm=TRUE), max(all_years, na.rm=TRUE))
  else "N/A"

  # Distinct permits
  permit_count <- if (PERMIT_ID_COL %in% names(df))
    format(n_distinct(df[[PERMIT_ID_COL]], na.rm=TRUE), big.mark=",")
  else "N/A"

  n_dup <- sum(duplicated(df))

  fname <- basename(file_path)
  desc  <- DESCRIPTIONS[[fname]]
  if (is.null(desc)) desc <- "data summary"
  highlevel <- SHEET_SUMMARIES[[fname]]
  if (is.null(highlevel)) highlevel <- ""

  sampled_note <- if (!is.null(SAMPLE_N))
    sprintf(" [SAMPLE: first %s rows — approximate]", format(as.integer(SAMPLE_N), big.mark=",")) else ""

  meta <- list(
    title     = paste0(fname, ": ", desc),
    highlevel = highlevel,
    summary   = sprintf("Observations: %s, Distinct Permits: %s, Temporal Range: %s, Duplicate Rows: %s%s",
                      format(n_rows, big.mark=",", trim=TRUE), permit_count, year_range,
                      format(n_dup, big.mark=",", trim=TRUE), sampled_note),
    columns   = paste(names(df), collapse=", ")
  )

  # ── Categorical ──
  cat_vars <- cols_to_summarise[sapply(df[cols_to_summarise], function(x)
    is.character(x) | is.logical(x) | is.factor(x))]
  cat_vars <- setdiff(cat_vars, DATE_COLS)

  cat_result <- if (length(cat_vars) > 0) {
    results <- lapply(cat_vars, function(v) {
      desc_col <- find_desc_col(v, names(df))
      cat_rows(df[[v]], v, if (!is.null(desc_col)) df[[desc_col]] else NULL)
    })
    desc_cols_used <- sapply(cat_vars, function(v) {
      d <- find_desc_col(v, names(df)); if (is.null(d)) "" else d })
    results <- results[!cat_vars %in% desc_cols_used]

    group_sizes <- sapply(results, `[[`, "n_rows")
    list(df = do.call(rbind, lapply(results, `[[`, "df")),
         group_sizes = group_sizes)
  } else NULL

  # ── Numeric + Date ──
  num_vars  <- cols_to_summarise[sapply(df[cols_to_summarise], is.numeric)]
  date_vars <- cols_to_summarise[sapply(df[cols_to_summarise], inherits, "Date")]

  num_df <- if (length(num_vars) > 0)
    do.call(rbind, lapply(num_vars, function(v) num_summary_row(df[[v]], v)))
  else NULL

  date_df <- if (length(date_vars) > 0)
    do.call(rbind, lapply(date_vars, function(v) date_summary_row(df[[v]], v)))
  else NULL

  list(meta = meta, cat = cat_result, num = num_df, date = date_df)
}

# ── Write worksheet (identical layout to summarize_npdes.R) ───────────────────

write_sheet <- function(wb, sheet_name, summary_list) {

  addWorksheet(wb, sheet_name)
  row <- 1

  writeData(wb, sheet_name, x = summary_list$meta$title, startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_title, rows = row, cols = 1)
  row <- row + 1

  if (nzchar(summary_list$meta$highlevel)) {
    writeData(wb, sheet_name, x = summary_list$meta$highlevel, startRow = row, startCol = 1)
    addStyle(wb, sheet_name, style_highlevel, rows = row, cols = 1)
    row <- row + 1
  }

  writeData(wb, sheet_name, x = summary_list$meta$summary, startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_meta, rows = row, cols = 1)
  row <- row + 1

  writeData(wb, sheet_name, x = paste("Columns:", summary_list$meta$columns),
            startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_meta, rows = row, cols = 1)
  row <- row + 2

  # ── Categorical section ──
  if (!is.null(summary_list$cat)) {
    tbl         <- summary_list$cat$df
    group_sizes <- summary_list$cat$group_sizes

    writeData(wb, sheet_name, x = tbl, startRow = row, startCol = 1,
              colNames = TRUE, rowNames = FALSE)
    addStyle(wb, sheet_name, style_hdr_cat, rows = row, cols = 1:7, gridExpand = TRUE)
    row <- row + 1

    n_data <- nrow(tbl)
    addStyle(wb, sheet_name, style_body,
             rows = row:(row + n_data - 1), cols = 1:7, gridExpand = TRUE)
    addStyle(wb, sheet_name, style_number,
             rows = row:(row + n_data - 1), cols = c(2, 5),
             gridExpand = TRUE, stack = TRUE)
    addStyle(wb, sheet_name, style_int,
             rows = row:(row + n_data - 1), cols = 6,
             gridExpand = TRUE, stack = TRUE)

    cur_row <- row
    for (g in group_sizes) {
      if (g > 1) {
        for (col in c(1, 2, 3)) {
          mergeCells(wb, sheet_name, cols = col, rows = cur_row:(cur_row + g - 1))
          addStyle(wb, sheet_name, style_valign,
                   rows = cur_row:(cur_row + g - 1), cols = col,
                   gridExpand = TRUE, stack = TRUE)
        }
      }
      cur_row <- cur_row + g
    }

    row <- row + n_data + 2
  }

  # ── Numeric + Date section ──
  if (!is.null(summary_list$num) || !is.null(summary_list$date)) {

    hdr_row <- row
    writeData(wb, sheet_name,
              x = t(c("Variable", "% Missing", "Min", "0.05",
                      "Median", "Mean", "0.95", "Max")),
              startRow = hdr_row, startCol = 1, colNames = FALSE)
    writeData(wb, sheet_name, x = 0.05, startRow = hdr_row, startCol = 4)
    writeData(wb, sheet_name, x = 0.95, startRow = hdr_row, startCol = 7)
    addStyle(wb, sheet_name, style_hdr_num, rows = hdr_row, cols = 1:8, gridExpand = TRUE)
    row <- hdr_row + 1

    if (!is.null(summary_list$num)) {
      ntbl <- summary_list$num
      writeData(wb, sheet_name, x = ntbl, startRow = row, startCol = 1, colNames = FALSE)
      n_data <- nrow(ntbl)
      addStyle(wb, sheet_name, style_body,
               rows = row:(row + n_data - 1), cols = 1:8, gridExpand = TRUE)
      addStyle(wb, sheet_name, style_number,
               rows = row:(row + n_data - 1), cols = 2:8, gridExpand = TRUE, stack = TRUE)
      row <- row + n_data
    }

    if (!is.null(summary_list$date)) {
      dtbl <- summary_list$date
      writeData(wb, sheet_name, x = dtbl, startRow = row, startCol = 1, colNames = FALSE)
      n_data <- nrow(dtbl)
      addStyle(wb, sheet_name, style_body,
               rows = row:(row + n_data - 1), cols = 1:8, gridExpand = TRUE)
      addStyle(wb, sheet_name, style_number,
               rows = row:(row + n_data - 1), cols = 2, gridExpand = TRUE, stack = TRUE)
      addStyle(wb, sheet_name, style_date,
               rows = row:(row + n_data - 1), cols = 3:8, gridExpand = TRUE, stack = TRUE)
      row <- row + n_data
    }
  }

  setColWidths(wb, sheet_name, cols = 1, widths = 42)
  setColWidths(wb, sheet_name, cols = 2, widths = 11)
  setColWidths(wb, sheet_name, cols = 3, widths = 13)
  setColWidths(wb, sheet_name, cols = 4, widths = 22)
  setColWidths(wb, sheet_name, cols = 5, widths = 10)
  setColWidths(wb, sheet_name, cols = 6, widths = 12)
  setColWidths(wb, sheet_name, cols = 7, widths = 38)
  setColWidths(wb, sheet_name, cols = 8, widths = 28)
}

# ── Main ──────────────────────────────────────────────────────────────────────

if (!file.exists(DATA_FILE)) stop("File not found: ", DATA_FILE)

wb <- createWorkbook()
cat("Processing", basename(DATA_FILE), "...\n")
summary_list <- build_summary_df(DATA_FILE)
write_sheet(wb, "NPDES_LIMITS", summary_list)

saveWorkbook(wb, OUT_FILE, overwrite = TRUE)
cat("\nDone! Output saved to:", OUT_FILE, "\n")
