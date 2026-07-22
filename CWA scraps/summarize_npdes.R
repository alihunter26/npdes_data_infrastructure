# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# summarize_npdes.R
# Output: one Excel file (npdes_summary.xlsx) with one sheet per CSV.

library(dplyr)
library(data.table)
library(lubridate)
library(openxlsx)

# Render dates as month/day/year throughout the workbook
options(openxlsx.dateFormat = "mm/dd/yyyy")

# ── Configuration ─────────────────────────────────────────────────────────────

DATA_DIR <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
# Timestamped output so each run writes its own file (date + time, to the minute)
OUT_FILE <- sprintf(file.path(CWA_ROOT, "output/npdes_summary_%s.xlsx"),
                    format(Sys.time(), "%Y-%m-%d_%H%M"))

# Set to a filename (e.g. "ICIS_PERMITS.csv") to process just that one file, or
# NULL to process every CSV in DATA_DIR.
ONLY_FILE <- "NPDES_QNCR_HISTORY.csv"

ID_COLS <- c(
  "NPDES_ID", "EXTERNAL_PERMIT_NMBR", "MASTER_EXTERNAL_PERMIT_NMBR",
  "ACTIVITY_ID", "ENF_IDENTIFIER", "NPDES_VIOLATION_ID",
  "COMP_SCHEDULE_EVENT_ID", "COMP_SCHEDULE_NMBR", "PERM_SCHEDULE_EVENT_ID",
  "PERM_FEATURE_NMBR", "PERM_FEATURE_ID", "REGISTRY_ID",
  "ICIS_FACILITY_INTEREST_ID", "FACILITY_UIN", "VERSION_NMBR",
  "RAD_WBD_HUC12S", "FACILITY_NAME", "LOCATION_ADDRESS", "SUPPLEMENTAL_ADDRESS_TEXT", "CITY", "ZIP", "IMPAIRED_WATERS", "STATE_WATER_BODY", "STATE_WATER_BODY_NAME", "PERMIT_NAME"
)

DATE_COLS <- c(
  "SETTLEMENT_ENTERED_DATE", "ACHIEVED_DATE",
  "ACTUAL_BEGIN_DATE", "ACTUAL_END_DATE",
  "SCHEDULE_DATE", "ACTUAL_DATE",
  "RNC_DETECTION_DATE", "RNC_RESOLUTION_DATE",
  "REPORT_RECEIVED_DATE",
  "SINGLE_EVENT_VIOLATION_DATE", "SINGLE_EVENT_END_DATE",
  "ORIGINAL_ISSUE_DATE", "ISSUE_DATE", "EFFECTIVE_DATE",
  "EXPIRATION_DATE", "RETIREMENT_DATE", "TERMINATION_DATE",
  "CREATED_DATE", "UPDATED_DATE"
)

# Human-readable description shown next to the filename in the title line.
# Files not listed here fall back to a description derived from the filename.
DESCRIPTIONS <- c(
  "ICIS_FACILITIES.csv"                    = "description of all facilities",
  "ICIS_PERMITS.csv"                       = "description of all permits",
  "NPDES_CS_VIOLATIONS.csv"                = "description of all compliance schedule violations",
  "NPDES_DATA_GROUPS.csv"                  = "description of all data groups",
  "NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv"   = "description of all formal enforcement actions",
  "NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv" = "description of all informal enforcement actions",
  "NPDES_INSPECTIONS.csv"                  = "description of all inspections",
  "NPDES_NAICS.csv"                        = "description of all NAICS codes",
  "NPDES_PERM_COMPONENTS.csv"              = "description of all permit components",
  "NPDES_PERM_FEATURE_COORDS.csv"          = "description of all permit feature coordinates",
  "NPDES_PS_VIOLATIONS.csv"                = "description of all permit schedule violations",
  "NPDES_QNCR_HISTORY.csv"                 = "description of all quarterly non-compliance report history",
  "NPDES_SE_VIOLATIONS.csv"                = "description of all single event violations",
  "NPDES_SICS.csv"                         = "description of all SIC codes",
  "NPDES_VIOLATION_ENFORCEMENTS.csv"       = "description of all violation enforcements"
)

# One-to-two sentence, plain-English summary of what each file contains and how
# it's typically used. Shown near the top of each sheet. Edit freely to match
# your own understanding of the data.
SHEET_SUMMARIES <- c(
  "ICIS_FACILITIES.csv" =
    "One row per regulated NPDES facility, with identifying information, location, and current permitted/active status. Serves as the central reference table for joining facility-level attributes to permits, violations, and enforcement records.",
  "ICIS_PERMITS.csv" =
    "One row per NPDES permit issued to a facility, including permit type, issuing agency, and key dates (issuance, effective, expiration). Links facilities to their permitted limits and components.",
  "NPDES_CS_VIOLATIONS.csv" =
    "Compliance schedule violations, i.e. instances where a facility missed a required milestone in an agreed-upon compliance schedule. Each row is one violation tied to a specific scheduled requirement.",
  "NPDES_DATA_GROUPS.csv" =
    "Groupings used to organize related monitoring parameters and limits within a permit. Used to relate individual parameters back to the broader limit set they belong to.",
  "NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv" =
    "Formal enforcement actions taken against facilities for permit violations, including the enforcement type, responsible agency, and any penalties assessed. Each row is one enforcement action.",
  "NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv" =
    "Informal enforcement actions (e.g. warning letters, notices of violation) issued to facilities, generally less severe than formal actions. Each row is one informal action.",
  "NPDES_INSPECTIONS.csv" =
    "Facility inspections conducted by regulatory agencies, including inspection type, date, and the agency responsible. Each row is one inspection event.",
  "NPDES_NAICS.csv" =
    "Maps facilities to their North American Industry Classification System (NAICS) code(s), describing the industry sector(s) each facility operates in.",
  "NPDES_PERM_COMPONENTS.csv" =
    "Individual components (e.g. outfalls or limit sets) defined within each NPDES permit. Links permits to their specific monitoring and limit requirements.",
  "NPDES_PERM_FEATURE_COORDS.csv" =
    "Geographic coordinates for permitted features (such as outfalls) associated with each facility's permit.",
  "NPDES_PS_VIOLATIONS.csv" =
    "Permit schedule violations, where a facility missed a scheduled permit requirement outside of a formal compliance schedule. Each row is one such violation.",
  "NPDES_QNCR_HISTORY.csv" =
    "Quarterly Noncompliance Report (QNCR) history, tracking a facility's reported compliance status across successive quarters.",
  "NPDES_SE_VIOLATIONS.csv" =
    "Single-event violations, i.e. one-time violations not tied to a recurring monitoring schedule. Each row is one violation event.",
  "NPDES_SICS.csv" =
    "Maps facilities to their Standard Industrial Classification (SIC) code(s), an older industry classification system still used alongside NAICS.",
  "NPDES_VIOLATION_ENFORCEMENTS.csv" =
    "Links individual violations to the enforcement action(s) taken in response, allowing violations and enforcement records to be cross-referenced."
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

# ── Helpers ───────────────────────────────────────────────────────────────────

# Percent (0-100) of values that are missing, rounded to 1 decimal.
pct_missing <- function(x) round(mean(is.na(x)) * 100, 1)

# For a code column, look for a paired description column (e.g. ENF_TYPE_CODE → ENF_TYPE_DESC)
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

  # Description: look up most common desc for each value
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

# One row per date variable: stats computed on the date and kept as Date objects
# so they display as month/day/year (mean/median of dates are themselves dates).
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

  df <- as.data.frame(fread(file_path, na.strings = c("", "NA")))
  # Treat whitespace-only character cells (e.g. " ") as missing, not as a category.
  # Some ICIS files (e.g. QNCR HLRNC) use a literal space for "blank", which would
  # otherwise escape na.strings ("" only) and is.na(), inflating frequent values
  # while reading 0% missing.
  char_cols <- names(df)[vapply(df, is.character, logical(1))]
  for (cc in char_cols) df[[cc]][trimws(df[[cc]]) == ""] <- NA_character_
  n_rows <- nrow(df)

  # Parse date columns
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

  # Distinct facilities
  fac_count <- if ("NPDES_ID" %in% names(df))
    format(n_distinct(df$NPDES_ID, na.rm=TRUE), big.mark=",")
  else "N/A"

  # Number of fully-duplicated rows
  n_dup <- sum(duplicated(df))

  # Title description: lookup table, else derive from the filename
  fname <- basename(file_path)
  desc  <- DESCRIPTIONS[[fname]]
  if (is.null(desc))
    desc <- paste("description of all",
                  tolower(gsub("_", " ",
                    sub("^(NPDES|ICIS)_", "", tools::file_path_sans_ext(fname)))))

  highlevel <- SHEET_SUMMARIES[[fname]]
  if (is.null(highlevel)) highlevel <- ""

  meta <- list(
    title     = paste0(fname, ": ", desc),
    highlevel = highlevel,
    summary   = sprintf("Observations: %s, Distinct Facilities: %s, Temporal Range: %s, Duplicate Rows: %s",
                      format(n_rows, big.mark=",", trim=TRUE), fac_count, year_range,
                      format(n_dup, big.mark=",", trim=TRUE)),
    columns   = paste(names(df), collapse=", ")
  )

  # ── Categorical ──
  cat_vars <- cols_to_summarise[sapply(df[cols_to_summarise], function(x)
    is.character(x) | is.logical(x) | is.factor(x))]
  cat_vars <- setdiff(cat_vars, DATE_COLS)

  cat_result <- if (length(cat_vars) > 0) {
    results     <- lapply(cat_vars, function(v) {
      desc_col <- find_desc_col(v, names(df))
      cat_rows(df[[v]], v, if (!is.null(desc_col)) df[[desc_col]] else NULL)
    })
    # Drop _DESC columns from cat_vars so they don't appear as their own rows
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

  # One row per date variable, stats shown as month/day/year dates
  date_df <- if (length(date_vars) > 0)
    do.call(rbind, lapply(date_vars, function(v) date_summary_row(df[[v]], v)))
  else NULL

  list(meta = meta, cat = cat_result, num = num_df, date = date_df)
}

# ── Write worksheet ───────────────────────────────────────────────────────────

write_sheet <- function(wb, sheet_name, summary_list) {

  addWorksheet(wb, sheet_name)
  row <- 1

  # Title (filename bold)
  writeData(wb, sheet_name, x = summary_list$meta$title, startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_title, rows = row, cols = 1)
  row <- row + 1

  # High-level, plain-English summary (1-2 sentences)
  if (nzchar(summary_list$meta$highlevel)) {
    writeData(wb, sheet_name, x = summary_list$meta$highlevel, startRow = row, startCol = 1)
    addStyle(wb, sheet_name, style_highlevel, rows = row, cols = 1)
    row <- row + 1
  }

  # Summary line
  writeData(wb, sheet_name, x = summary_list$meta$summary, startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_meta, rows = row, cols = 1)
  row <- row + 1

  # Columns line
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
    # Show "% Missing" (col 2) and "%" (col 5) as decimals, "n" (col 6) as a whole number
    addStyle(wb, sheet_name, style_number,
             rows = row:(row + n_data - 1), cols = c(2, 5),
             gridExpand = TRUE, stack = TRUE)
    addStyle(wb, sheet_name, style_int,
             rows = row:(row + n_data - 1), cols = 6,
             gridExpand = TRUE, stack = TRUE)

    cur_row <- row
    for (g in group_sizes) {
      if (g > 1) {
        # Variable, % Missing, n Categories are per-variable
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

    # Header (percentile columns 0.05 / 0.95 written as numbers)
    hdr_row <- row
    writeData(wb, sheet_name,
              x = t(c("Variable", "% Missing", "Min", "0.05",
                      "Median", "Mean", "0.95", "Max")),
              startRow = hdr_row, startCol = 1, colNames = FALSE)
    writeData(wb, sheet_name, x = 0.05, startRow = hdr_row, startCol = 4)
    writeData(wb, sheet_name, x = 0.95, startRow = hdr_row, startCol = 7)
    addStyle(wb, sheet_name, style_hdr_num, rows = hdr_row, cols = 1:8, gridExpand = TRUE)
    row <- hdr_row + 1

    # Numeric variables
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

    # Date variables (one row each, stats as month/day/year)
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

    footer_row <- row + 1
    writeData(wb, sheet_name, x = "Notes", startRow = footer_row, startCol = 1)
    addStyle(wb, sheet_name, style_section, rows = footer_row, cols = 1:8, gridExpand = TRUE)

    mis_row <- footer_row + 2
    writeData(wb, sheet_name, x = "Missing Explanation", startRow = mis_row, startCol = 1)
    addStyle(wb, sheet_name, style_section, rows = mis_row, cols = 1:8, gridExpand = TRUE)

    row <- mis_row + 1
  }

  # Column widths
  setColWidths(wb, sheet_name, cols = 1,   widths = 42)
  setColWidths(wb, sheet_name, cols = 2,   widths = 11)
  setColWidths(wb, sheet_name, cols = 3,   widths = 13)
  setColWidths(wb, sheet_name, cols = 4,   widths = 22)
  setColWidths(wb, sheet_name, cols = 5,   widths = 10)
  setColWidths(wb, sheet_name, cols = 6,   widths = 12)
  setColWidths(wb, sheet_name, cols = 7,   widths = 38)
  setColWidths(wb, sheet_name, cols = 8,   widths = 28)
}

# ── Main ──────────────────────────────────────────────────────────────────────

csv_files <- if (!is.null(ONLY_FILE)) {
  file.path(DATA_DIR, ONLY_FILE)
} else {
  list.files(DATA_DIR, pattern = "\\.csv$", full.names = TRUE)
}

if (length(csv_files) == 0 || !all(file.exists(csv_files)))
  stop("No CSV files found in: ", DATA_DIR)

wb <- createWorkbook()

for (f in csv_files) {
  sheet_name <- substr(tools::file_path_sans_ext(basename(f)), 1, 31)
  cat("Processing", basename(f), "...\n")
  summary_list <- build_summary_df(f)
  write_sheet(wb, sheet_name, summary_list)
}

saveWorkbook(wb, OUT_FILE, overwrite = TRUE)
cat("\nDone! Output saved to:", OUT_FILE, "\n")
