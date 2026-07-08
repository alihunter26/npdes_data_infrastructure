# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# summarize_eff_violations_state.R
# Reads NPDES_EFF_VIOLATIONS.csv from its zip in chunks, keeps only rows whose
# NPDES_ID starts with the two-letter STATE code set in the config block below,
# then produces the standard summary sheet.
#
# Reading in chunks avoids loading the full ~16 GB file into memory.

library(dplyr)
library(data.table)
library(lubridate)
library(openxlsx)

options(openxlsx.dateFormat = "mm/dd/yyyy")

# ── Configuration ─────────────────────────────────────────────────────────────

# STATE to summarize — set the two-letter NPDES/state code (e.g. "NY", "VA", "PR").
STATE      <- "NY"
state_lc   <- tolower(STATE)
state_name <- if (STATE %in% state.abb) state.name[match(STATE, state.abb)] else STATE

ZIP_PATH   <- list.files(
  file.path(CWA_ROOT, "data/raw/"),
  pattern    = "eff.*zip",
  full.names = TRUE
)[1]
CSV_IN_ZIP <- "NPDES_EFF_VIOLATIONS.csv"
OUT_FILE   <- file.path(CWA_ROOT, sprintf("output/eff_violations_%s_summary_%s.xlsx",
                    state_lc, format(Sys.time(), "%Y-%m-%d_%H%M")))
OUT_CSV    <- file.path(CWA_ROOT, sprintf("output/eff_violations_%s_%s.csv",
                    state_lc, format(Sys.time(), "%Y-%m-%d_%H%M")))

CHUNK_SIZE <- 1000000   # rows per chunk — adjust down if memory is tight

ID_COLS <- c(
  "NPDES_ID", "VERSION_NMBR", "ACTIVITY_ID", "NPDES_VIOLATION_ID",
  "PERM_FEATURE_NMBR", "PERMIT_ACTIVITY_ID",
  "DMR_FORM_VALUE_ID", "DMR_VALUE_ID", "DMR_PARAMETER_ID", "LIMIT_ID"
)

NUM_COLS <- c(
  "DMR_VALUE_NMBR", "LIMIT_VALUE_STANDARD_UNITS", "EXCEEDENCE_PCT", "DAYS_LATE", "DMR_VALUE_STANDARD_UNITS"
  # Add column names here for quantitative variables to summarize (mean/median)
  # that may not be auto-detected as numeric (e.g. arrive as character in CSV)
)

DATE_COLS <- c(
  "MONITORING_PERIOD_END_DATE", "VALUE_RECEIVED_DATE",
  "RNC_DETECTION_DATE", "RNC_RESOLUTION_DATE"
)

DESCRIPTION   <- sprintf("description of effluent (DMR) violations for %s facilities (NPDES_ID starting with '%s')", state_name, STATE)
SHEET_SUMMARY <- sprintf("One row per parameter/limit violation reported on a %s facility's DMR. Filtered from the full national NPDES_EFF_VIOLATIONS file to NPDES_IDs beginning with '%s'. Includes the parameter, violation type, reported vs. limit value, exceedance %%, and noncompliance detection/resolution dates.", state_name, STATE)

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

# ── Helpers ───────────────────────────────────────────────────────────────────

pct_missing <- function(x) round(mean(is.na(x)) * 100, 1)

find_desc_col <- function(var, all_cols) {
  candidate <- sub("_CODE$", "_DESC", var)
  if (candidate != var && candidate %in% all_cols) return(candidate)
  candidate2 <- paste0(var, "_DESC")
  if (candidate2 %in% all_cols) return(candidate2)
  NULL
}

cat_rows <- function(x, var_name, desc_x = NULL, top_n = 5) {
  tbl     <- sort(table(x, useNA = "no"), decreasing = TRUE)
  n_total <- sum(!is.na(x))
  n_cat   <- length(tbl)
  pct_mis <- pct_missing(x)

  if (n_cat == 0) {
    return(list(
      df = data.frame(Variable = "", `% Missing` = pct_mis, `n Categories` = 0,
                      `Frequent Values` = "(all missing)", `%` = NA, n = NA,
                      Description = "", `Missing Explanation` = "",
                      check.names = FALSE, stringsAsFactors = FALSE),
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

num_summary_row <- function(x, var_name) {
  xc <- x[!is.na(x)]
  if (length(xc) == 0) vals <- rep(NA_real_, 6)
  else vals <- c(min(xc), unname(quantile(xc, 0.05)), median(xc),
                 mean(xc), unname(quantile(xc, 0.95)), max(xc))
  data.frame(Variable = var_name, `% Missing` = pct_missing(x),
             Min = round(vals[1], 3), `0.05` = round(vals[2], 3),
             Median = round(vals[3], 3), Mean = round(vals[4], 3),
             `0.95` = round(vals[5], 3), Max = round(vals[6], 3),
             `Missing Explanation` = "",
             check.names = FALSE, stringsAsFactors = FALSE)
}

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
  data.frame(Variable = var_name, `% Missing` = pct_missing(x),
             Min = d[1], `0.05` = d[2], Median = d[3],
             Mean = d[4], `0.95` = d[5], Max = d[6],
             `Missing Explanation` = "",
             check.names = FALSE, stringsAsFactors = FALSE)
}

# ── Read zip in chunks, keep only the selected state's rows ────────────────────────────────────

read_state_rows <- function(zip_path, csv_name, chunk_size) {

  # Stream directly from the zip — no extraction to disk
  read_cmd <- sprintf("unzip -p %s %s", shQuote(zip_path), shQuote(csv_name))

  col_names <- names(fread(cmd = read_cmd, nrows = 0))
  cat("Columns:", paste(col_names, collapse = ", "), "\n\n")

  state_chunks <- list()
  chunk_num  <- 0
  skip_rows  <- 0   # rows already consumed (excluding header)
  total_read <- 0

  repeat {
    chunk_num <- chunk_num + 1
    cat(sprintf("Reading chunk %d (rows %s – %s)...\n",
                chunk_num,
                format(skip_rows + 1,              big.mark = ","),
                format(skip_rows + chunk_size,     big.mark = ",")))

    chunk <- fread(
      cmd        = read_cmd,
      skip       = skip_rows,     # skip already-read rows
      nrows      = chunk_size,
      col.names  = col_names,
      header     = FALSE,
      na.strings = c("", "NA")
    )

    n_read <- nrow(chunk)
    total_read <- total_read + n_read
    cat(sprintf("  Read %s rows; ", format(n_read, big.mark = ",")))

    va <- chunk[startsWith(as.character(chunk$NPDES_ID), STATE)]
    cat(sprintf("kept %s rows.\n", format(nrow(va), big.mark = ",")))

    if (nrow(va) > 0) state_chunks[[length(state_chunks) + 1]] <- va
    rm(chunk); gc()

    if (n_read < chunk_size) break   # last chunk — we're done
    skip_rows <- skip_rows + chunk_size
  }

  cat(sprintf("\nTotal rows read: %s\n", format(total_read, big.mark = ",")))

  if (length(state_chunks) == 0) stop(sprintf("No rows found for state '%s'.", STATE))

  df <- rbindlist(state_chunks)
  cat(sprintf("Total rows: %s\n\n", format(nrow(df), big.mark = ",")))
  as.data.frame(df)
}

# ── Build the summary from the filtered state data ───────────────────────────────

build_summary <- function(df) {

  n_rows            <- nrow(df)
  cols_to_summarise <- setdiff(names(df), ID_COLS)

  # Coerce explicitly listed numeric columns
  num_cols_present <- intersect(NUM_COLS, names(df))
  for (col in num_cols_present) {
    if (!is.numeric(df[[col]]))
      df[[col]] <- suppressWarnings(as.numeric(df[[col]]))
  }

  # Parse date columns
  date_cols_present <- intersect(DATE_COLS, names(df))
  for (col in date_cols_present) {
    parsed <- suppressWarnings(as.Date(df[[col]], format = "%m/%d/%Y"))
    if (sum(!is.na(parsed)) >= sum(!is.na(df[[col]])) * 0.5)
      df[[col]] <- parsed
    else
      df[[col]] <- as.Date(suppressWarnings(
        parse_date_time(df[[col]], orders = c("mdy", "ymd", "dmy"), quiet = TRUE)))
  }

  all_years <- unlist(lapply(date_cols_present, function(col) {
    if (inherits(df[[col]], "Date")) as.integer(format(df[[col]], "%Y"))
  }))
  year_range <- if (length(all_years) > 0)
    sprintf("%d-%d", min(all_years, na.rm = TRUE), max(all_years, na.rm = TRUE))
  else "N/A"

  n_permits <- format(n_distinct(df$NPDES_ID, na.rm = TRUE), big.mark = ",")
  n_dup     <- sum(duplicated(df))

  meta <- list(
    title     = paste0(CSV_IN_ZIP, sprintf(" (%s only): ", state_name), DESCRIPTION),
    highlevel = SHEET_SUMMARY,
    summary   = sprintf(
      "Observations: %s, Distinct %s Permits: %s, Temporal Range: %s, Duplicate Rows: %s",
      format(n_rows, big.mark = ",", trim = TRUE),
      STATE, n_permits, year_range,
      format(n_dup, big.mark = ",", trim = TRUE)
    ),
    columns = paste(names(df), collapse = ", ")
  )

  # Categorical variables
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

  # Numeric variables
  num_vars <- cols_to_summarise[sapply(df[cols_to_summarise], is.numeric)]
  num_df   <- if (length(num_vars) > 0)
    do.call(rbind, lapply(num_vars, function(v) num_summary_row(df[[v]], v)))
  else NULL

  # Date variables
  date_vars <- cols_to_summarise[sapply(df[cols_to_summarise], inherits, "Date")]
  date_df   <- if (length(date_vars) > 0)
    do.call(rbind, lapply(date_vars, function(v) date_summary_row(df[[v]], v)))
  else NULL

  list(meta = meta, cat = cat_result, num = num_df, date = date_df)
}

# ── Write to Excel ────────────────────────────────────────────────────────────

write_sheet <- function(wb, sheet_name, s) {

  addWorksheet(wb, sheet_name)
  row <- 1

  writeData(wb, sheet_name, x = s$meta$title, startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_title, rows = row, cols = 1)
  row <- row + 1

  writeData(wb, sheet_name, x = s$meta$highlevel, startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_highlevel, rows = row, cols = 1)
  row <- row + 1

  writeData(wb, sheet_name, x = s$meta$summary, startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_meta, rows = row, cols = 1)
  row <- row + 1

  writeData(wb, sheet_name, x = paste("Columns:", s$meta$columns),
            startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_meta, rows = row, cols = 1)
  row <- row + 2

  # Categorical table
  if (!is.null(s$cat)) {
    tbl         <- s$cat$df
    group_sizes <- s$cat$group_sizes

    writeData(wb, sheet_name, x = tbl, startRow = row, startCol = 1,
              colNames = TRUE, rowNames = FALSE)
    addStyle(wb, sheet_name, style_hdr_cat, rows = row, cols = 1:8, gridExpand = TRUE)
    row <- row + 1

    n_data <- nrow(tbl)
    addStyle(wb, sheet_name, style_body,
             rows = row:(row + n_data - 1), cols = 1:8, gridExpand = TRUE)
    addStyle(wb, sheet_name, style_number,
             rows = row:(row + n_data - 1), cols = c(2, 5), gridExpand = TRUE, stack = TRUE)
    addStyle(wb, sheet_name, style_int,
             rows = row:(row + n_data - 1), cols = 6, gridExpand = TRUE, stack = TRUE)

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

  # Numeric + Date table
  if (!is.null(s$num) || !is.null(s$date)) {
    hdr_row <- row
    writeData(wb, sheet_name,
              x = t(c("Variable", "% Missing", "Min", "0.05",
                       "Median", "Mean", "0.95", "Max", "Missing Explanation")),
              startRow = hdr_row, startCol = 1, colNames = FALSE)
    writeData(wb, sheet_name, x = 0.05, startRow = hdr_row, startCol = 4)
    writeData(wb, sheet_name, x = 0.95, startRow = hdr_row, startCol = 7)
    addStyle(wb, sheet_name, style_hdr_num, rows = hdr_row, cols = 1:9, gridExpand = TRUE)
    row <- hdr_row + 1

    if (!is.null(s$num)) {
      ntbl <- s$num
      writeData(wb, sheet_name, x = ntbl, startRow = row, startCol = 1, colNames = FALSE)
      addStyle(wb, sheet_name, style_body,
               rows = row:(row + nrow(ntbl) - 1), cols = 1:9, gridExpand = TRUE)
      addStyle(wb, sheet_name, style_number,
               rows = row:(row + nrow(ntbl) - 1), cols = 2:8, gridExpand = TRUE, stack = TRUE)
      row <- row + nrow(ntbl)
    }

    if (!is.null(s$date)) {
      dtbl <- s$date
      writeData(wb, sheet_name, x = dtbl, startRow = row, startCol = 1, colNames = FALSE)
      addStyle(wb, sheet_name, style_body,
               rows = row:(row + nrow(dtbl) - 1), cols = 1:9, gridExpand = TRUE)
      addStyle(wb, sheet_name, style_number,
               rows = row:(row + nrow(dtbl) - 1), cols = 2, gridExpand = TRUE, stack = TRUE)
      addStyle(wb, sheet_name, style_date,
               rows = row:(row + nrow(dtbl) - 1), cols = 3:8, gridExpand = TRUE, stack = TRUE)
      row <- row + nrow(dtbl)
    }

    writeData(wb, sheet_name, x = "Notes", startRow = row + 1, startCol = 1)
    addStyle(wb, sheet_name, style_section, rows = row + 1, cols = 1:9, gridExpand = TRUE)
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

if (!file.exists(ZIP_PATH)) stop("Zip not found: ", ZIP_PATH)

dir.create(dirname(OUT_FILE), showWarnings = FALSE, recursive = TRUE)

df           <- read_state_rows(ZIP_PATH, CSV_IN_ZIP, CHUNK_SIZE)
fwrite(df, OUT_CSV)
cat("CSV saved to:", OUT_CSV, "\n")
summary_list <- build_summary(df)

wb <- createWorkbook()
write_sheet(wb, paste0("EFF_VIOLATIONS_", STATE), summary_list)
saveWorkbook(wb, OUT_FILE, overwrite = TRUE)

cat("\nDone! Output saved to:", OUT_FILE, "\n")
