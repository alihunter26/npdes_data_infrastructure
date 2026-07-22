# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# summarize_outfalls_layer.R
# Produces the same summary-sheet format as summarize_npdes.R for the
# npdes_outfalls_layer.csv file.
# Output: one Excel file with a single sheet.

library(dplyr)
library(data.table)
library(lubridate)
library(openxlsx)

options(openxlsx.dateFormat = "mm/dd/yyyy")

# ── Configuration ─────────────────────────────────────────────────────────────

CSV_PATH <- file.path(CWA_ROOT, "data/raw/npdes_outfalls_layer.csv")
OUT_FILE <- sprintf(file.path(CWA_ROOT, "output/outfalls_layer_summary_%s.xlsx"),
                    format(Sys.time(), "%Y-%m-%d_%H%M"))

# Columns that are identifiers or free-text — skip them
ID_COLS <- c(
  "EXTERNAL_PERMIT_NMBR", "FACILITY_NAME", "LOCATION_ADDRESS",
  "CITY", "ZIP", "PERMIT_NAME", "STATE_WATER_BODY_NAME",
  "SIC_CODES", "SIC_DESCRIPTIONS", "NAICS_CODES",
  "FAC_DERIVED_TRIBES", "PERMIT_COMPONENTS", "PERM_FEATURE_NMBR"
)

# Columns to parse as dates
DATE_COLS <- c(
  "CWP_DATE_LAST_INSPECTION", "DATE_LAST_FORMAL_EA",
  "PERMIT_EFFECTIVE_DATE", "PERMIT_EXPIRATION_DATE", "PERMIT_TERMINATION_DATE"
)

DESCRIPTION   <- "description of all NPDES outfall locations"
SHEET_SUMMARY <- "One row per permitted outfall (discharge point) in the NPDES program, with facility location, permit type and status, compliance indicators, and geographic coordinates. This is the spatial/GIS layer of NPDES permits and is often used to map facilities and join location data to other NPDES tables."

# ── Styles ────────────────────────────────────────────────────────────────────

style_title     <- createStyle(fontSize = 11, textDecoration = "bold")
style_meta      <- createStyle(fontSize = 10)
style_highlevel <- createStyle(fontSize = 10, textDecoration = "italic")
style_hdr_cat   <- createStyle(fontSize = 10, textDecoration = "bold",
                                fgFill = "#D9E1F2", border = "Bottom",
                                borderStyle = "medium")
style_hdr_num   <- createStyle(fontSize = 10, textDecoration = "bold",
                                fgFill = "#F4B942", border = "Bottom",
                                borderStyle = "medium")
style_section   <- createStyle(fontSize = 10, textDecoration = "bold",
                                fgFill = "#F2F2F2")
style_body      <- createStyle(fontSize = 10)
style_number    <- createStyle(fontSize = 10, numFmt = "#,##0.###")
style_int       <- createStyle(fontSize = 10, numFmt = "#,##0")
style_date      <- createStyle(fontSize = 10, numFmt = "mm/dd/yyyy")
style_valign    <- createStyle(fontSize = 10, valign = "top")

# ── Helper functions ──────────────────────────────────────────────────────────

# Returns the % of values that are missing (NA), rounded to 1 decimal place
pct_missing <- function(x) round(mean(is.na(x)) * 100, 1)

# If a column is named e.g. PERMIT_TYPE_CODE, checks whether a matching
# PERMIT_TYPE_DESC column also exists and returns its name if so
find_desc_col <- function(var, all_cols) {
  candidate <- sub("_CODE$", "_DESC", var)
  if (candidate != var && candidate %in% all_cols) return(candidate)
  candidate2 <- paste0(var, "_DESC")
  if (candidate2 %in% all_cols) return(candidate2)
  NULL
}

# Builds the rows for one categorical variable in the summary table.
# Returns one row per top-N value, with the variable name, % missing,
# number of unique categories, and the most common values + their counts.
cat_rows <- function(x, var_name, desc_x = NULL, top_n = 5) {
  tbl     <- sort(table(x, useNA = "no"), decreasing = TRUE)
  n_total <- sum(!is.na(x))
  n_cat   <- length(tbl)
  pct_mis <- pct_missing(x)

  if (n_cat == 0) {
    return(list(
      df = data.frame(
        Variable = "", `% Missing` = pct_mis, `n Categories` = 0,
        `Frequent Values` = "(all missing)", `%` = NA, n = NA,
        Description = "", `Missing Explanation` = "",
        check.names = FALSE, stringsAsFactors = FALSE),
      var_label = var_name, n_rows = 1
    ))
  }

  top    <- head(tbl, top_n)
  n_rows <- length(top)
  vals   <- names(top)

  # If a paired description column exists, look up the description for each value
  desc_vec <- if (!is.null(desc_x)) {
    sapply(vals, function(v) {
      matches <- desc_x[!is.na(x) & x == v & !is.na(desc_x)]
      if (length(matches) == 0) return("")
      names(sort(table(matches), decreasing = TRUE))[1]
    })
  } else rep("", n_rows)

  df <- data.frame(
    Variable          = c(var_name, rep("", n_rows - 1)),
    `% Missing`       = c(pct_mis,  rep(NA,       n_rows - 1)),
    `n Categories`    = c(n_cat,    rep(NA,        n_rows - 1)),
    `Frequent Values` = vals,
    `%`               = round(as.numeric(top) / n_total * 100, 1),
    n                 = as.integer(top),
    Description       = desc_vec,
    `Missing Explanation` = c("", rep("", n_rows - 1)),
    check.names = FALSE, stringsAsFactors = FALSE
  )

  list(df = df, var_label = var_name, n_rows = n_rows)
}

# Builds one summary row for a numeric variable: % missing, min, 5th pctile,
# median, mean, 95th pctile, max
num_summary_row <- function(x, var_name) {
  xc <- x[!is.na(x)]
  if (length(xc) == 0)
    vals <- rep(NA_real_, 6)
  else
    vals <- c(min(xc), unname(quantile(xc, 0.05)), median(xc),
              mean(xc), unname(quantile(xc, 0.95)), max(xc))
  data.frame(
    Variable = var_name, `% Missing` = pct_missing(x),
    Min = round(vals[1], 3), `0.05` = round(vals[2], 3),
    Median = round(vals[3], 3), Mean = round(vals[4], 3),
    `0.95` = round(vals[5], 3), Max = round(vals[6], 3),
    `Missing Explanation` = "",
    check.names = FALSE, stringsAsFactors = FALSE
  )
}

# Builds one summary row for a date variable: same stats as numeric, but
# the output values are formatted as dates (mm/dd/yyyy in Excel)
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
  data.frame(
    Variable = var_name, `% Missing` = pct_missing(x),
    Min = d[1], `0.05` = d[2], Median = d[3],
    Mean = d[4], `0.95` = d[5], Max = d[6],
    `Missing Explanation` = "",
    check.names = FALSE, stringsAsFactors = FALSE
  )
}

# ── Read and summarise the CSV ────────────────────────────────────────────────

build_summary_df <- function(csv_path) {

  cat("Reading", basename(csv_path), "...\n")
  df <- as.data.frame(fread(csv_path, na.strings = c("", "NA")))
  n_rows <- nrow(df)
  cat("Read", format(n_rows, big.mark = ","), "rows.\n")

  # Figure out which columns to summarise (everything except ID/free-text cols)
  cols_to_summarise <- setdiff(names(df), ID_COLS)

  # Parse date columns from character to Date
  date_cols_present <- intersect(DATE_COLS, names(df))
  for (col in date_cols_present) {
    parsed <- suppressWarnings(as.Date(df[[col]], format = "%m/%d/%Y"))
    if (sum(!is.na(parsed)) >= sum(!is.na(df[[col]])) * 0.5)
      df[[col]] <- parsed
    else
      df[[col]] <- as.Date(suppressWarnings(
        parse_date_time(df[[col]], orders = c("mdy", "ymd", "dmy"), quiet = TRUE)))
  }

  # Get the overall year range from all date columns combined
  all_years <- unlist(lapply(date_cols_present, function(col) {
    if (inherits(df[[col]], "Date")) as.integer(format(df[[col]], "%Y"))
  }))
  year_range <- if (length(all_years) > 0)
    sprintf("%d-%d", min(all_years, na.rm = TRUE), max(all_years, na.rm = TRUE))
  else "N/A"

  # Count distinct permits (using EXTERNAL_PERMIT_NMBR as the facility ID here)
  permit_count <- if ("EXTERNAL_PERMIT_NMBR" %in% names(df))
    format(n_distinct(df$EXTERNAL_PERMIT_NMBR, na.rm = TRUE), big.mark = ",")
  else "N/A"

  cat("Checking for duplicate rows...\n")
  n_dup <- sum(duplicated(df))

  # The meta info that appears at the top of the sheet
  meta <- list(
    title     = paste0(basename(csv_path), ": ", DESCRIPTION),
    highlevel = SHEET_SUMMARY,
    summary   = sprintf(
      "Observations: %s, Distinct Permits: %s, Temporal Range: %s, Duplicate Rows: %s",
      format(n_rows, big.mark = ",", trim = TRUE),
      permit_count, year_range,
      format(n_dup, big.mark = ",", trim = TRUE)
    ),
    columns = paste(names(df), collapse = ", ")
  )

  # ── Categorical variables ──
  cat_vars <- cols_to_summarise[sapply(df[cols_to_summarise], function(x)
    is.character(x) | is.logical(x) | is.factor(x))]
  cat_vars <- setdiff(cat_vars, DATE_COLS)

  cat_result <- if (length(cat_vars) > 0) {
    results <- lapply(cat_vars, function(v) {
      desc_col <- find_desc_col(v, names(df))
      cat_rows(df[[v]], v, if (!is.null(desc_col)) df[[desc_col]] else NULL)
    })
    # Don't show _DESC columns as their own rows (they're already used as lookups)
    desc_cols_used <- sapply(cat_vars, function(v) {
      d <- find_desc_col(v, names(df))
      if (is.null(d)) "" else d
    })
    results <- results[!cat_vars %in% desc_cols_used]
    list(
      df          = do.call(rbind, lapply(results, `[[`, "df")),
      group_sizes = sapply(results, `[[`, "n_rows")
    )
  } else NULL

  # ── Numeric variables ──
  num_vars <- cols_to_summarise[sapply(df[cols_to_summarise], is.numeric)]
  num_df   <- if (length(num_vars) > 0)
    do.call(rbind, lapply(num_vars, function(v) num_summary_row(df[[v]], v)))
  else NULL

  # ── Date variables ──
  date_vars <- cols_to_summarise[sapply(df[cols_to_summarise], inherits, "Date")]
  date_df   <- if (length(date_vars) > 0)
    do.call(rbind, lapply(date_vars, function(v) date_summary_row(df[[v]], v)))
  else NULL

  list(meta = meta, cat = cat_result, num = num_df, date = date_df)
}

# ── Write the summary to an Excel worksheet ───────────────────────────────────

write_sheet <- function(wb, sheet_name, summary_list) {

  addWorksheet(wb, sheet_name)
  row <- 1   # tracks the current row as we write downward

  # Title row
  writeData(wb, sheet_name, x = summary_list$meta$title, startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_title, rows = row, cols = 1)
  row <- row + 1

  # Plain-English description of the file
  writeData(wb, sheet_name, x = summary_list$meta$highlevel, startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_highlevel, rows = row, cols = 1)
  row <- row + 1

  # Observations / duplicates / year range line
  writeData(wb, sheet_name, x = summary_list$meta$summary, startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_meta, rows = row, cols = 1)
  row <- row + 1

  # Full column list
  writeData(wb, sheet_name, x = paste("Columns:", summary_list$meta$columns),
            startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_meta, rows = row, cols = 1)
  row <- row + 2   # blank spacer before the tables

  # ── Categorical table ──
  if (!is.null(summary_list$cat)) {
    tbl         <- summary_list$cat$df
    group_sizes <- summary_list$cat$group_sizes

    # Write header + data
    writeData(wb, sheet_name, x = tbl, startRow = row, startCol = 1,
              colNames = TRUE, rowNames = FALSE)
    addStyle(wb, sheet_name, style_hdr_cat, rows = row, cols = 1:8, gridExpand = TRUE)
    row <- row + 1

    n_data <- nrow(tbl)
    addStyle(wb, sheet_name, style_body,
             rows = row:(row + n_data - 1), cols = 1:8, gridExpand = TRUE)
    # "% Missing" (col 2) and "%" (col 5) as decimals; "n" (col 6) as whole number
    addStyle(wb, sheet_name, style_number,
             rows = row:(row + n_data - 1), cols = c(2, 5),
             gridExpand = TRUE, stack = TRUE)
    addStyle(wb, sheet_name, style_int,
             rows = row:(row + n_data - 1), cols = 6,
             gridExpand = TRUE, stack = TRUE)

    # Merge cells for Variable / % Missing / n Categories across the multiple
    # value rows that belong to the same variable
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

    row <- row + n_data + 2   # blank spacer
  }

  # ── Numeric + Date table (shared header row) ──
  if (!is.null(summary_list$num) || !is.null(summary_list$date)) {

    # Write the header manually so 0.05 / 0.95 appear as numbers, not text
    hdr_row <- row
    writeData(wb, sheet_name,
              x = t(c("Variable", "% Missing", "Min", "0.05",
                       "Median", "Mean", "0.95", "Max", "Missing Explanation")),
              startRow = hdr_row, startCol = 1, colNames = FALSE)
    writeData(wb, sheet_name, x = 0.05, startRow = hdr_row, startCol = 4)
    writeData(wb, sheet_name, x = 0.95, startRow = hdr_row, startCol = 7)
    addStyle(wb, sheet_name, style_hdr_num, rows = hdr_row, cols = 1:9, gridExpand = TRUE)
    row <- hdr_row + 1

    # Numeric rows
    if (!is.null(summary_list$num)) {
      ntbl   <- summary_list$num
      n_data <- nrow(ntbl)
      writeData(wb, sheet_name, x = ntbl, startRow = row, startCol = 1, colNames = FALSE)
      addStyle(wb, sheet_name, style_body,
               rows = row:(row + n_data - 1), cols = 1:9, gridExpand = TRUE)
      addStyle(wb, sheet_name, style_number,
               rows = row:(row + n_data - 1), cols = 2:8, gridExpand = TRUE, stack = TRUE)
      row <- row + n_data
    }

    # Date rows (formatted as mm/dd/yyyy)
    if (!is.null(summary_list$date)) {
      dtbl   <- summary_list$date
      n_data <- nrow(dtbl)
      writeData(wb, sheet_name, x = dtbl, startRow = row, startCol = 1, colNames = FALSE)
      addStyle(wb, sheet_name, style_body,
               rows = row:(row + n_data - 1), cols = 1:9, gridExpand = TRUE)
      addStyle(wb, sheet_name, style_number,
               rows = row:(row + n_data - 1), cols = 2, gridExpand = TRUE, stack = TRUE)
      addStyle(wb, sheet_name, style_date,
               rows = row:(row + n_data - 1), cols = 3:8, gridExpand = TRUE, stack = TRUE)
      row <- row + n_data
    }

    # Notes footer row
    footer_row <- row + 1
    writeData(wb, sheet_name, x = "Notes", startRow = footer_row, startCol = 1)
    addStyle(wb, sheet_name, style_section, rows = footer_row, cols = 1:9, gridExpand = TRUE)
  }

  # Set column widths to match the other summary sheets
  setColWidths(wb, sheet_name, cols = 1, widths = 42)
  setColWidths(wb, sheet_name, cols = 2, widths = 11)
  setColWidths(wb, sheet_name, cols = 3, widths = 13)
  setColWidths(wb, sheet_name, cols = 4, widths = 22)
  setColWidths(wb, sheet_name, cols = 5, widths = 10)
  setColWidths(wb, sheet_name, cols = 6, widths = 12)
  setColWidths(wb, sheet_name, cols = 7, widths = 38)
  setColWidths(wb, sheet_name, cols = 8, widths = 28)
  setColWidths(wb, sheet_name, cols = 9, widths = 28)
}

# ── Main ──────────────────────────────────────────────────────────────────────

if (!file.exists(CSV_PATH))
  stop("File not found: ", CSV_PATH)

wb           <- createWorkbook()
summary_list <- build_summary_df(CSV_PATH)
write_sheet(wb, "NPDES_OUTFALLS_LAYER", summary_list)

saveWorkbook(wb, OUT_FILE, overwrite = TRUE)
cat("\nDone! Output saved to:", OUT_FILE, "\n")
