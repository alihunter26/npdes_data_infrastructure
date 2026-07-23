# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# combine_dmr_summaries.R
# ------------------------------------------------------------------------------
# Builds ONE Excel workbook with 4 tabs -- one per stage of the DMR filter
# pipeline in "dmr analysis/" (01 -> 04). This is the multi-tab equivalent of
# running code/summary/summarize.R's `dmrs` dataset four times (once per
# CSV_PATH, which is how output/DMR/01-04_dmr_summary.xlsx were each produced
# as separate files): same styling, same summary logic, copied verbatim, but
# all 4 written into ONE shared workbook instead of 4 separate files.
# (openxlsx's cloneWorksheet() only copies a sheet WITHIN a
# single workbook -- style indices aren't safely mergeable across two
# independently-built workbook objects -- so re-running the summarizer once
# per stage into a shared `wb` is the robust way to combine them, not a
# post-hoc file merge.)
#
# A single combined file is also what you want if uploading to Google Sheets:
# importing one multi-sheet .xlsx preserves every sheet as its own tab.
#
# Output: output/DMR/dmr_summaries_combined_<timestamp>.xlsx

library(dplyr)
library(data.table)
library(lubridate)
library(openxlsx)

options(openxlsx.dateFormat = "mm/dd/yyyy")

# ── Configuration ─────────────────────────────────────────────────────────────

DMR_ANALYSIS_DIR <- file.path(CWA_ROOT, "dmr analysis")
OUT_DIR  <- file.path(CWA_ROOT, "output/DMR")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
OUT_FILE <- file.path(OUT_DIR, "2025_dmr_summaries_combined.xlsx")

# Raw (unfiltered) FY2025 summary, built by code/summary/build_dmr_raw_summary.R
# via DuckDB (the raw file is too large to safely fread on this 8GB machine).
# Prepended as this workbook's FIRST sheet, before any of the filtered stages.
RAW_SUMMARY_RDS <- file.path(OUT_DIR, "raw_summary_fy2025.rds")

# One entry per pipeline stage: csv path, tab name (<=31 chars, Excel limit),
# and a stage-specific description (unlike summarize.R's `dmrs` entry, which has a single hardcoded
# DESCRIPTION/SHEET_SUMMARY, each stage here describes what THAT file actually
# is, since the 4 stages are progressively narrower row filters, not 4
# unrelated files).
STAGES <- list(
  list(csv = "01_dmr_fy2025.csv",
       tab = "01_MajorIndividual",
       description = "Ever-major individual (NPD) permits, FY2025 DMR records -- all parameters, outfall types, and monitoring locations kept (broad base file).",
       summary     = "One row per DMR parameter/limit submission for FY2025, restricted to permits that are individual (NPD) and were major in at least one permit version. No parameter, feature-type, or monitoring-location restriction applied yet."),
  list(csv = "02_dmr_fy2025_00530.csv",
       tab = "02_TSS_00530",
       description = "Stage 01, further restricted to PARAMETER_CODE = '00530' (Total Suspended Solids).",
       summary     = "Same population as 01_MajorIndividual, narrowed to TSS records only. Feature type and monitoring location are not yet restricted."),
  list(csv = "03_dmr_fy2025_00530_monloc1.csv",
       tab = "03_EffluentGross",
       description = "Stage 02, further restricted to MONITORING_LOCATION_CODE IN ('1','EG') (Effluent Gross, per EPA's REF_MONITORING_LOCATION table).",
       summary     = "Same population as 02_TSS_00530, narrowed to effluent-gross monitoring locations only."),
  list(csv = "04_dmr_fy2025_00530_monloc1_c1q1.csv",
       tab = "04_C1Q1",
       description = "Stage 03, further restricted to LIMIT_VALUE_TYPE_CODE IN ('C1','Q1') (concentration and quantity/mass value slots).",
       summary     = "Same population as 03_EffluentGross, narrowed to the C1/Q1 limit-value-type rows only.")
)

# Set to a number (e.g. 500000) to read only that many rows while testing.
# Set to NULL to read each full file.
NROWS_LIMIT <- NULL

# Columns that are identifiers — skip them (summary stats are not meaningful).
# Identical list to summarize.R's `dmrs` dataset entry.
ID_COLS <- c(
  "ACTIVITY_ID", "EXTERNAL_PERMIT_NMBR",
  "PERM_FEATURE_ID",
  "LIMIT_SET_ID", "LIMIT_SET_DESIGNATOR", "LIMIT_SET_SCHEDULE_ID",
  "LIMIT_ID", "LIMIT_VALUE_ID", "DMR_EVENT_ID",
  "DMR_FORM_VALUE_ID", "DMR_VALUE_ID", "NPDES_VIOLATION_ID"
)

FORCE_CHAR_COLS <- c("VERSION_NMBR")

DATE_COLS <- c(
  "LIMIT_BEGIN_DATE", "LIMIT_END_DATE",
  "MONITORING_PERIOD_END_DATE", "VALUE_RECEIVED_DATE",
  "RNC_DETECTION_DATE", "RNC_RESOLUTION_DATE"
)

# ── Styles (identical to summarize.R's, so all 4 tabs look consistent) ───────

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

# ── Helper functions (identical to summarize.R's) ─────────────────────────────

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

# ── Read the CSV and build the summary (identical logic to summarize.R's `dmrs` entry,
#    parameterized by description/summary text per stage) ────────────────────

build_summary_df <- function(csv_path, description, sheet_summary, nrows_limit = NULL) {

  csv_name <- basename(csv_path)

  cat("Scanning columns...\n")
  all_col_names <- names(fread(csv_path, nrows = 0))
  cols_to_read  <- setdiff(all_col_names, setdiff(ID_COLS, "EXTERNAL_PERMIT_NMBR"))

  cat("Reading", csv_name, "(", length(cols_to_read), "of", length(all_col_names),
      "columns) ...\n")

  df <- fread(
    file       = csv_path,
    select     = cols_to_read,
    na.strings = c("", "NA"),
    nrows      = if (is.null(nrows_limit)) Inf else nrows_limit
  )

  n_rows <- nrow(df)
  cat("Read", format(n_rows, big.mark = ","), "rows.\n")

  for (col in intersect(FORCE_CHAR_COLS, names(df)))
    if (!is.character(df[[col]])) set(df, j = col, value = as.character(df[[col]]))

  cols_to_summarise <- setdiff(names(df), ID_COLS)

  permit_count <- if ("EXTERNAL_PERMIT_NMBR" %in% names(df))
    format(uniqueN(df[["EXTERNAL_PERMIT_NMBR"]], na.rm = TRUE), big.mark = ",")
  else "N/A"
  if ("EXTERNAL_PERMIT_NMBR" %in% names(df))
    set(df, j = "EXTERNAL_PERMIT_NMBR", value = NULL)

  date_cols_present <- intersect(DATE_COLS, names(df))
  for (col in date_cols_present) {
    parsed <- suppressWarnings(as.Date(df[[col]], format = "%m/%d/%Y"))
    if (sum(!is.na(parsed)) >= sum(!is.na(df[[col]])) * 0.5)
      set(df, j = col, value = parsed)
    else
      set(df, j = col, value = as.Date(suppressWarnings(
        parse_date_time(df[[col]], orders = c("mdy", "ymd", "dmy"), quiet = TRUE))))
  }

  all_years <- unlist(lapply(date_cols_present, function(col) {
    if (inherits(df[[col]], "Date")) as.integer(format(df[[col]], "%Y"))
  }))
  year_range <- if (length(all_years) > 0)
    sprintf("%d-%d", min(all_years, na.rm = TRUE), max(all_years, na.rm = TRUE))
  else "N/A"

  meta <- list(
    title     = paste0(csv_name, ": ", description),
    highlevel = sheet_summary,
    summary   = sprintf(
      "Observations: %s, Distinct Permits: %s, Temporal Range: %s",
      format(n_rows, big.mark = ",", trim = TRUE),
      permit_count, year_range
    ),
    columns = paste(all_col_names, collapse = ", ")
  )

  cat_vars <- cols_to_summarise[
    vapply(cols_to_summarise, function(v)
      is.character(df[[v]]) || is.logical(df[[v]]) || is.factor(df[[v]]), logical(1))]
  cat_vars <- setdiff(cat_vars, DATE_COLS)

  cat_result <- if (length(cat_vars) > 0) {
    results        <- list()
    desc_cols_used <- character(0)
    for (v in cat_vars) {
      if (v %in% desc_cols_used || !v %in% names(df)) next
      desc_col      <- find_desc_col(v, names(df))
      results[[length(results) + 1]] <- cat_rows(
        df[[v]], v,
        if (!is.null(desc_col)) df[[desc_col]] else NULL
      )
      if (!is.null(desc_col)) desc_cols_used <- c(desc_cols_used, desc_col)
      set(df, j = v, value = NULL)
    }
    for (dc in desc_cols_used)
      if (dc %in% names(df)) set(df, j = dc, value = NULL)
    gc()
    list(
      df          = do.call(rbind, lapply(results, `[[`, "df")),
      group_sizes = sapply(results, `[[`, "n_rows")
    )
  } else NULL

  num_present <- intersect(cols_to_summarise, names(df))
  num_vars    <- num_present[vapply(num_present, function(v) is.numeric(df[[v]]), logical(1))]

  num_df <- if (length(num_vars) > 0) {
    res <- do.call(rbind, lapply(num_vars, function(v) {
      r <- num_summary_row(df[[v]], v)
      set(df, j = v, value = NULL)
      r
    }))
    gc()
    res
  } else NULL

  date_present <- intersect(cols_to_summarise, names(df))
  date_vars    <- date_present[vapply(date_present, function(v) inherits(df[[v]], "Date"), logical(1))]

  date_df <- if (length(date_vars) > 0) {
    res <- do.call(rbind, lapply(date_vars, function(v) {
      r <- date_summary_row(df[[v]], v)
      set(df, j = v, value = NULL)
      r
    }))
    gc()
    res
  } else NULL

  list(meta = meta, cat = cat_result, num = num_df, date = date_df)
}

# ── Write one summary to one worksheet (identical to summarize.R's) ──────────

write_sheet <- function(wb, sheet_name, summary_list) {

  addWorksheet(wb, sheet_name)
  row <- 1

  writeData(wb, sheet_name, x = summary_list$meta$title, startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_title, rows = row, cols = 1)
  row <- row + 1

  writeData(wb, sheet_name, x = summary_list$meta$highlevel, startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_highlevel, rows = row, cols = 1)
  row <- row + 1

  writeData(wb, sheet_name, x = summary_list$meta$summary, startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_meta, rows = row, cols = 1)
  row <- row + 1

  writeData(wb, sheet_name, x = paste("Columns:", summary_list$meta$columns),
            startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_meta, rows = row, cols = 1)
  row <- row + 2

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

# ── Main: raw sheet first, then loop all 4 stages into ONE shared workbook ────

wb <- createWorkbook()

if (!file.exists(RAW_SUMMARY_RDS))
  stop("Raw summary not found: ", RAW_SUMMARY_RDS,
       " -- run code/summary/build_dmr_raw_summary.R 2025 first.")
cat("\n=== 00_RawAllPermits (raw, unfiltered FY2025 DMR) ===\n")
raw_summary <- readRDS(RAW_SUMMARY_RDS)
write_sheet(wb, "00_RawAllPermits", raw_summary)

for (stage in STAGES) {
  csv_path <- file.path(DMR_ANALYSIS_DIR, stage$csv)
  if (!file.exists(csv_path)) stop("CSV file not found: ", csv_path)

  cat("\n=== ", stage$tab, " (", stage$csv, ") ===\n", sep = "")
  summary_list <- build_summary_df(csv_path, stage$description, stage$summary, NROWS_LIMIT)
  write_sheet(wb, stage$tab, summary_list)
}

saveWorkbook(wb, OUT_FILE, overwrite = TRUE)
cat("\nDone! Combined workbook (", length(STAGES), " tabs) saved to:\n  ", OUT_FILE, "\n", sep = "")
