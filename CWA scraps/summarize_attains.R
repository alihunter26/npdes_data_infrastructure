# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# summarize_attains.R
# Produces the same summary-sheet format as summarize_npdes.R for the
# CSV files in the Attains folder.
# Output: one Excel file with one sheet per CSV (skipping empty files).

library(dplyr)
library(data.table)
library(lubridate)
library(openxlsx)

options(openxlsx.dateFormat = "mm/dd/yyyy")

# ── Configuration ─────────────────────────────────────────────────────────────

DATA_DIR <- file.path(CWA_ROOT, "data/raw/Attains")
OUT_FILE <- sprintf(file.path(CWA_ROOT, "output/attains_summary_%s.xlsx"),
                    format(Sys.time(), "%Y-%m-%d_%H%M"))

# Columns that are identifiers or free-text — skip them
ID_COLS <- c(
  "NPDES_ID", "REGISTRY_ID", "ECHO_DFR_URL", "AU_URL",
  "ASSESSMENTUNITIDENTIFIER", "ASSESSMENTUNITNAME",
  "WATERBODYREPORTLINK", "GNIS_NAME", "WBD_HU12NAME",
  "REACHCODE", "HUC12", "WBD_HU12", "NHDPLUSID", "SUB_ID"
)

# Columns to parse as dates
DATE_COLS <- c("REPORTINGCYCLE")

# Plain-English descriptions for each file's sheet
DESCRIPTIONS <- c(
  "NPDES_ATTAINS_AU_SUMMARIES.csv" =
    "description of all NPDES-ATTAINS assessment unit summaries",
  "ATTAINS_AU_CATCHMENTS.csv" =
    "description of all ATTAINS assessment unit catchments",
  "NPDES_CATCHMENTS.csv" =
    "description of all NPDES permit catchment linkages"
)

SHEET_SUMMARIES <- c(
  "NPDES_ATTAINS_AU_SUMMARIES.csv" =
    "Links each NPDES facility to the ATTAINS water quality assessment unit(s) it discharges into, with the overall water condition, use support status (drinking water, ecological, fish consumption, recreation), and any impairment causes. One row per facility-assessment unit pair.",
  "ATTAINS_AU_CATCHMENTS.csv" =
    "Maps ATTAINS assessment units to NHDPlus catchments, with impairment status, 303(d) listing, TMDL and protection plan flags, and catchment geometry attributes.",
  "NPDES_CATCHMENTS.csv" =
    "Links each NPDES permit to its NHDPlus catchment, including the best-pick catchment selection, geographic coordinates, HUC12 watershed, and catchment/reach characteristics (navigable, headwater, coastal, tidal, Alaskan)."
)

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

# Returns the % of values that are missing, rounded to 1 decimal place
pct_missing <- function(x) round(mean(is.na(x)) * 100, 1)

# If a column ends in _CODE, checks whether a matching _DESC column exists
# and returns its name if so
find_desc_col <- function(var, all_cols) {
  candidate <- sub("_CODE$", "_DESC", var)
  if (candidate != var && candidate %in% all_cols) return(candidate)
  candidate2 <- paste0(var, "_DESC")
  if (candidate2 %in% all_cols) return(candidate2)
  NULL
}

# Builds the rows for one categorical variable: variable name, % missing,
# n unique categories, and the top-N most frequent values with % and count
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

  # Look up description for each code value if a paired _DESC column exists
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

# Builds one summary row for a numeric variable:
# % missing, min, 5th pctile, median, mean, 95th pctile, max
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

# Builds one summary row for a date variable — same stats but output as dates
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

# ── Read one CSV and build its summary ───────────────────────────────────────

build_summary_df <- function(file_path) {

  fname <- basename(file_path)
  cat("Reading", fname, "...\n")

  df <- as.data.frame(fread(file_path, na.strings = c("", "NA")))
  n_rows <- nrow(df)
  cat("Read", format(n_rows, big.mark = ","), "rows.\n")

  cols_to_summarise <- setdiff(names(df), ID_COLS)

  # Parse date columns
  date_cols_present <- intersect(DATE_COLS, names(df))
  for (col in date_cols_present) {
    # REPORTINGCYCLE is a plain year (e.g. 2024) — treat as numeric, not Date
    if (col == "REPORTINGCYCLE") next
    parsed <- suppressWarnings(as.Date(df[[col]], format = "%m/%d/%Y"))
    if (sum(!is.na(parsed)) >= sum(!is.na(df[[col]])) * 0.5)
      df[[col]] <- parsed
    else
      df[[col]] <- as.Date(suppressWarnings(
        parse_date_time(df[[col]], orders = c("mdy", "ymd", "dmy"), quiet = TRUE)))
  }

  # Year range from any parsed date columns
  actual_date_cols <- date_cols_present[vapply(date_cols_present, function(col)
    inherits(df[[col]], "Date"), logical(1))]
  all_years <- unlist(lapply(actual_date_cols, function(col)
    as.integer(format(df[[col]], "%Y"))))

  # Also pull year range from REPORTINGCYCLE if it's numeric
  if ("REPORTINGCYCLE" %in% names(df) && is.numeric(df$REPORTINGCYCLE))
    all_years <- c(all_years, df$REPORTINGCYCLE)

  year_range <- if (length(all_years) > 0)
    sprintf("%d-%d", min(all_years, na.rm = TRUE), max(all_years, na.rm = TRUE))
  else "N/A"

  # Distinct facilities
  fac_count <- if ("NPDES_ID" %in% names(df))
    format(n_distinct(df$NPDES_ID, na.rm = TRUE), big.mark = ",")
  else "N/A"

  cat("Checking for duplicate rows...\n")
  n_dup <- sum(duplicated(df))

  desc      <- DESCRIPTIONS[[fname]]
  if (is.null(desc)) desc <- paste("description of", tolower(tools::file_path_sans_ext(fname)))
  highlevel <- SHEET_SUMMARIES[[fname]]
  if (is.null(highlevel)) highlevel <- ""

  meta <- list(
    title     = paste0(fname, ": ", desc),
    highlevel = highlevel,
    summary   = sprintf(
      "Observations: %s, Distinct Facilities: %s, Temporal Range: %s, Duplicate Rows: %s",
      format(n_rows, big.mark = ",", trim = TRUE),
      fac_count, year_range,
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
    desc_cols_used <- sapply(cat_vars, function(v) {
      d <- find_desc_col(v, names(df)); if (is.null(d)) "" else d
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

# ── Write one summary to an Excel worksheet ───────────────────────────────────

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

  # ── Categorical table ──
  if (!is.null(summary_list$cat)) {
    tbl         <- summary_list$cat$df
    group_sizes <- summary_list$cat$group_sizes

    writeData(wb, sheet_name, x = tbl, startRow = row, startCol = 1,
              colNames = TRUE, rowNames = FALSE)
    addStyle(wb, sheet_name, style_hdr_cat, rows = row, cols = 1:8, gridExpand = TRUE)
    row <- row + 1

    n_data <- nrow(tbl)
    addStyle(wb, sheet_name, style_body,
             rows = row:(row + n_data - 1), cols = 1:8, gridExpand = TRUE)
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

  # ── Numeric + Date table ──
  if (!is.null(summary_list$num) || !is.null(summary_list$date)) {

    hdr_row <- row
    writeData(wb, sheet_name,
              x = t(c("Variable", "% Missing", "Min", "0.05",
                       "Median", "Mean", "0.95", "Max", "Missing Explanation")),
              startRow = hdr_row, startCol = 1, colNames = FALSE)
    writeData(wb, sheet_name, x = 0.05, startRow = hdr_row, startCol = 4)
    writeData(wb, sheet_name, x = 0.95, startRow = hdr_row, startCol = 7)
    addStyle(wb, sheet_name, style_hdr_num, rows = hdr_row, cols = 1:9, gridExpand = TRUE)
    row <- hdr_row + 1

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

    footer_row <- row + 1
    writeData(wb, sheet_name, x = "Notes", startRow = footer_row, startCol = 1)
    addStyle(wb, sheet_name, style_section, rows = footer_row, cols = 1:9, gridExpand = TRUE)
  }

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

csv_files <- list.files(DATA_DIR, pattern = "\\.csv$", full.names = TRUE)

if (length(csv_files) == 0)
  stop("No CSV files found in: ", DATA_DIR)

wb <- createWorkbook()

for (f in csv_files) {

  # Skip empty files (header only)
  if (nrow(fread(f, nrows = 1, na.strings = c("", "NA"))) == 0) {
    cat("Skipping", basename(f), "(empty)\n")
    next
  }

  sheet_name   <- substr(tools::file_path_sans_ext(basename(f)), 1, 31)
  summary_list <- build_summary_df(f)
  write_sheet(wb, sheet_name, summary_list)
}

saveWorkbook(wb, OUT_FILE, overwrite = TRUE)
cat("\nDone! Output saved to:", OUT_FILE, "\n")
