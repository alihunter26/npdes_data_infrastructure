# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# summarize_eff_violations.R
# Produces the same summary-sheet format as summarize_npdes.R, but for the
# (very large) NPDES_EFF_VIOLATIONS.csv file.
#
# Streams the CSV straight from its zip (via `unzip -p`) in chunks, so peak
# memory is roughly one chunk and the ~16 GB CSV is never extracted to disk.
# Categorical frequencies are accumulated across chunks; numeric/date
# quantiles are estimated from a rolling random sample.
#
# Output: one Excel file with a single sheet, matching the look of the
# sheets in npdes_summary_*.xlsx.

library(dplyr)
library(data.table)
library(lubridate)
library(openxlsx)

options(openxlsx.dateFormat = "mm/dd/yyyy")

# ── Configuration ─────────────────────────────────────────────────────────────

# Effluent violations live inside a zip in data/raw/ — stream straight from it
# (via `unzip -p`) rather than extracting the ~16 GB CSV to disk first.
ZIP_PATH    <- list.files(
  file.path(CWA_ROOT, "data/raw/"),
  pattern    = "eff.*zip",
  full.names = TRUE
)[1]
CSV_IN_ZIP  <- "NPDES_EFF_VIOLATIONS.csv"
OUT_FILE    <- sprintf(file.path(CWA_ROOT, "output/eff_violations_summary_%s.xlsx"),
                       format(Sys.time(), "%Y-%m-%d_%H%M"))

# Set to a number (e.g. 1000000) to only read that many rows while testing.
# Set to NULL to read the full file.
NROWS_LIMIT <- NULL

ID_COLS <- c(
  "NPDES_ID", "VERSION_NMBR", "ACTIVITY_ID", "NPDES_VIOLATION_ID",
  "PERM_FEATURE_NMBR", "PERMIT_ACTIVITY_ID", "DMR_FORM_VALUE_ID",
  "DMR_VALUE_ID", "DMR_PARAMETER_ID", "LIMIT_ID"
)

DATE_COLS <- c(
  "MONITORING_PERIOD_END_DATE", "VALUE_RECEIVED_DATE",
  "RNC_DETECTION_DATE", "RNC_RESOLUTION_DATE"
)

DESCRIPTION <- "description of all effluent (DMR) violations"
SHEET_SUMMARY <- "Effluent (Discharge Monitoring Report) violations — one row per parameter/limit violation reported on a facility's DMR, including the parameter, limit, reported value, and any resulting noncompliance detection/resolution."

# ── Styles (same as summarize_npdes.R) ───────────────────────────────────────

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

# ── Helpers (identical logic to summarize_npdes.R) ───────────────────────────

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
      df = data.frame(Variable="", `% Missing`=pct_mis, `n Categories`=0,
                      `Frequent Values`="(all missing)", `%`=NA, n=NA,
                      Description="", `Missing Explanation`="",
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
    `Missing Explanation` = c("", rep("",       n_rows - 1)),
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
             `Missing Explanation`="",
             check.names=FALSE, stringsAsFactors=FALSE)
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
  data.frame(Variable=var_name, `% Missing`=pct_missing(x),
             Min=d[1], `0.05`=d[2], Median=d[3],
             Mean=d[4], `0.95`=d[5], Max=d[6],
             `Missing Explanation`="",
             check.names=FALSE, stringsAsFactors=FALSE)
}

# ── Build summary (reads straight from the zip, no extraction to disk) ──────

build_summary_df <- function(zip_path, csv_name, nrows_limit = NULL, chunk_size = 2000000) {

  # Stream straight from the zip — no extraction to disk. Each fread re-runs
  # this command, so chunks are read by re-streaming and skipping prior rows.
  read_cmd <- sprintf("unzip -p %s %s", shQuote(zip_path), shQuote(csv_name))

  col_names         <- names(fread(cmd = read_cmd, nrows = 0))
  cols_to_summarise <- setdiff(col_names, ID_COLS)
  date_cols_present <- intersect(DATE_COLS, col_names)

  # Detect column types and build code→desc lookup maps from a 200k-row sample.
  cat("Sampling 200,000 rows to detect column types...\n")
  samp <- as.data.frame(fread(cmd = read_cmd, nrows = 200000, na.strings = c("", "NA")))
  for (col in date_cols_present) {
    parsed <- suppressWarnings(as.Date(samp[[col]], format = "%m/%d/%Y"))
    samp[[col]] <- if (sum(!is.na(parsed)) >= sum(!is.na(samp[[col]])) * 0.5) parsed
    else as.Date(suppressWarnings(
      parse_date_time(samp[[col]], orders = c("mdy","ymd","dmy"), quiet = TRUE)))
  }
  cat_cols <- setdiff(
    intersect(cols_to_summarise,
      names(samp)[sapply(samp[cols_to_summarise],
                         function(x) is.character(x) | is.logical(x) | is.factor(x))]),
    DATE_COLS)
  num_cols <- intersect(cols_to_summarise,
    names(samp)[sapply(samp[cols_to_summarise], is.numeric)])

  desc_maps <- list()
  for (v in cat_cols) {
    dc <- find_desc_col(v, col_names)
    if (!is.null(dc) && dc %in% names(samp)) {
      pairs <- unique(data.frame(code = samp[[v]], desc = samp[[dc]],
                                 stringsAsFactors = FALSE))
      pairs <- pairs[!is.na(pairs$code) & !is.na(pairs$desc), ]
      if (nrow(pairs) > 0) desc_maps[[v]] <- setNames(pairs$desc, pairs$code)
    }
  }
  rm(samp); gc()

  # Column class vector passed to every chunk read so fread uses consistent
  # types regardless of the content of individual chunks.
  # Date cols stay "character" here because we parse them ourselves.
  # Positional (unnamed) so fread matches by column position rather than name,
  # which is required when header=FALSE (fread internally uses V1, V2, ... before
  # applying col.names, so a named vector keyed by col.names won't be matched).
  col_classes <- ifelse(col_names %in% num_cols, "numeric", "character")

  # Accumulators
  cat_acc  <- setNames(lapply(cat_cols, function(v)
    data.table(value = character(0), n = integer(0))), cat_cols)

  num_acc  <- setNames(lapply(num_cols, function(v)
    list(min=Inf, max=-Inf, sum=0, count=0L, na_count=0L, total=0L,
         sample=numeric(0))), num_cols)

  date_acc <- setNames(lapply(date_cols_present, function(v)
    list(min=Inf, max=-Inf, sum=0, count=0L, na_count=0L, total=0L,
         sample=numeric(0))), date_cols_present)

  all_years  <- integer(0)
  npdes_ids  <- character(0)
  total_rows <- 0L
  SAMP_N     <- 20000L   # random rows sampled per chunk for quantile estimation

  # ── Chunk loop ──────────────────────────────────────────────────────────────
  skip <- 1L  # skip the header row; each iteration advances by chunk_size
  repeat {
    cat(sprintf("  Reading rows %s – %s ...\n",
        format(total_rows + 1L, big.mark = ","),
        format(total_rows + chunk_size, big.mark = ",")))

    chunk <- suppressWarnings(as.data.frame(fread(
      cmd = read_cmd, nrows = chunk_size, skip = skip,
      header = FALSE, col.names = col_names,
      colClasses = col_classes,
      na.strings = c("", "NA"))))

    if (nrow(chunk) == 0L) break

    if (!is.null(nrows_limit) && total_rows + nrow(chunk) > nrows_limit)
      chunk <- chunk[seq_len(nrows_limit - total_rows), , drop = FALSE]

    nr <- nrow(chunk)

    # fread only upgrades types, never downgrades — if it detects a column as
    # string it ignores a "numeric" colClasses override. Force the coercion here
    # as fread's own warning message recommends ("coerce to the lower type afterwards").
    for (v in num_cols) {
      if (!is.numeric(chunk[[v]]))
        chunk[[v]] <- suppressWarnings(as.numeric(chunk[[v]]))
    }

    # Parse date columns in this chunk
    for (col in date_cols_present) {
      parsed <- suppressWarnings(as.Date(chunk[[col]], format = "%m/%d/%Y"))
      chunk[[col]] <- if (sum(!is.na(parsed)) >= sum(!is.na(chunk[[col]])) * 0.5)
        parsed
      else as.Date(suppressWarnings(
        parse_date_time(chunk[[col]], orders = c("mdy","ymd","dmy"), quiet = TRUE)))
    }

    # Distinct NPDES_ID (approximate: dedup within chunk, then dedup combined)
    if ("NPDES_ID" %in% col_names)
      npdes_ids <- unique(c(npdes_ids,
                            unique(chunk$NPDES_ID[!is.na(chunk$NPDES_ID)])))

    # Year range
    for (col in date_cols_present)
      if (inherits(chunk[[col]], "Date"))
        all_years <- c(all_years,
          as.integer(format(chunk[[col]][!is.na(chunk[[col]])], "%Y")))

    # Categorical frequency accumulation
    for (v in cat_cols) {
      tbl <- table(chunk[[v]], useNA = "no")
      if (length(tbl) > 0L) {
        cat_acc[[v]] <- rbind(cat_acc[[v]],
          data.table(value = names(tbl), n = as.integer(tbl)))
        # Consolidate periodically to cap memory use
        if (nrow(cat_acc[[v]]) > 100000L)
          cat_acc[[v]] <- cat_acc[[v]][, .(n = sum(n)), by = value][order(-n)][
            seq_len(min(.N, 20000L))]
      }
    }

    # Numeric accumulation
    for (v in num_cols) {
      x <- chunk[[v]]; xc <- x[!is.na(x)]
      s <- num_acc[[v]]
      s$total    <- s$total    + nr
      s$na_count <- s$na_count + sum(is.na(x))
      if (length(xc) > 0L) {
        s$min    <- min(s$min, min(xc))
        s$max    <- max(s$max, max(xc))
        s$sum    <- s$sum + sum(as.numeric(xc))
        s$count  <- s$count + length(xc)
        s$sample <- c(s$sample,
          xc[sample.int(length(xc), min(SAMP_N, length(xc)))])
      }
      num_acc[[v]] <- s
    }

    # Date accumulation (work in days-since-epoch)
    for (v in date_cols_present) {
      s <- date_acc[[v]]
      s$total <- s$total + nr
      if (!inherits(chunk[[v]], "Date")) {
        s$na_count <- s$na_count + nr
      } else {
        x <- as.numeric(chunk[[v]]); xc <- x[!is.na(x)]
        s$na_count <- s$na_count + sum(is.na(x))
        if (length(xc) > 0L) {
          s$min    <- min(s$min, min(xc))
          s$max    <- max(s$max, max(xc))
          s$sum    <- s$sum + sum(xc)
          s$count  <- s$count + length(xc)
          s$sample <- c(s$sample,
            xc[sample.int(length(xc), min(SAMP_N, length(xc)))])
        }
      }
      date_acc[[v]] <- s
    }

    total_rows <- total_rows + nr
    rm(chunk); gc()

    if (!is.null(nrows_limit) && total_rows >= nrows_limit) break
    if (nr < chunk_size) break
    skip <- skip + nr
  }

  cat("Finished reading", format(total_rows, big.mark = ","), "rows.\n")

  # ── Finalize meta ────────────────────────────────────────────────────────────
  year_range <- if (length(all_years) > 0L)
    sprintf("%d-%d", min(all_years, na.rm = TRUE), max(all_years, na.rm = TRUE))
  else "N/A"
  fac_count <- if (length(npdes_ids) > 0L)
    format(length(npdes_ids), big.mark = ",") else "N/A"

  meta <- list(
    title     = paste0(csv_name, ": ", DESCRIPTION),
    highlevel = SHEET_SUMMARY,
    summary   = sprintf(
      "Observations: %s, Distinct Facilities: %s, Temporal Range: %s, Duplicate Rows: N/A (chunked read)",
      format(total_rows, big.mark = ",", trim = TRUE), fac_count, year_range),
    columns   = paste(col_names, collapse = ", ")
  )

  # ── Finalize categorical ─────────────────────────────────────────────────────
  cat_result <- if (length(cat_cols) > 0L) {
    results <- lapply(cat_cols, function(v) {
      final   <- cat_acc[[v]][, .(n = sum(n)), by = value][order(-n)]
      n_total <- sum(final$n)
      pct_mis <- round((total_rows - n_total) / total_rows * 100, 1)
      n_cat   <- nrow(final)
      top     <- head(final, 5L)
      n_rows  <- nrow(top)

      if (n_cat == 0L) {
        return(list(
          df = data.frame(Variable = v, `% Missing` = pct_mis, `n Categories` = 0L,
                          `Frequent Values` = "(all missing)", `%` = NA_real_,
                          n = NA_integer_, Description = "",
                          `Missing Explanation` = "",
                          check.names = FALSE, stringsAsFactors = FALSE),
          var_label = v, n_rows = 1L))
      }

      dm    <- desc_maps[[v]]
      descs <- if (!is.null(dm))
        sapply(top$value, function(val)
          if (!is.na(val) && val %in% names(dm)) dm[[val]] else "")
      else rep("", n_rows)

      list(
        df = data.frame(
          Variable          = c(v,       rep("", n_rows - 1L)),
          `% Missing`       = c(pct_mis, rep(NA_real_,    n_rows - 1L)),
          `n Categories`    = c(n_cat,   rep(NA_integer_,  n_rows - 1L)),
          `Frequent Values` = top$value,
          `%`               = round(top$n / n_total * 100, 1),
          n                 = as.integer(top$n),
          Description       = descs,
          `Missing Explanation` = c("", rep("", n_rows - 1L)),
          check.names = FALSE, stringsAsFactors = FALSE),
        var_label = v, n_rows = n_rows)
    })

    desc_cols_used <- sapply(cat_cols, function(v) {
      d <- find_desc_col(v, col_names); if (is.null(d)) "" else d })
    results <- results[!cat_cols %in% desc_cols_used]
    list(df          = do.call(rbind, lapply(results, `[[`, "df")),
         group_sizes = sapply(results, `[[`, "n_rows"))
  } else NULL

  # ── Finalize numeric ─────────────────────────────────────────────────────────
  num_df <- if (length(num_cols) > 0L) {
    do.call(rbind, lapply(num_cols, function(v) {
      s     <- num_acc[[v]]
      samp  <- s$sample[!is.na(s$sample)]
      if (s$count == 0L || length(samp) == 0L) {
        vals <- rep(NA_real_, 6L)
      } else {
        q    <- quantile(samp, c(0.05, 0.5, 0.95))
        vals <- c(s$min, q[1L], q[2L], s$sum / s$count, q[3L], s$max)
      }
      data.frame(Variable = v,
                 `% Missing` = round(s$na_count / s$total * 100, 1),
                 Min = round(vals[1L], 3), `0.05` = round(vals[2L], 3),
                 Median = round(vals[3L], 3), Mean = round(vals[4L], 3),
                 `0.95` = round(vals[5L], 3), Max = round(vals[6L], 3),
                 `Missing Explanation` = "",
                 check.names = FALSE, stringsAsFactors = FALSE)
    }))
  } else NULL

  # ── Finalize dates ───────────────────────────────────────────────────────────
  active_date_cols <- date_cols_present[
    sapply(date_acc[date_cols_present], function(s) s$count > 0L)]
  date_df <- if (length(active_date_cols) > 0L) {
    do.call(rbind, lapply(active_date_cols, function(v) {
      s    <- date_acc[[v]]
      samp <- s$sample[!is.na(s$sample)]
      if (s$count == 0L || length(samp) == 0L) {
        d <- rep(as.Date(NA), 6L)
      } else {
        q    <- quantile(samp, c(0.05, 0.5, 0.95))
        nums <- c(s$min, q[1L], q[2L], s$sum / s$count, q[3L], s$max)
        d    <- as.Date(round(nums), origin = "1970-01-01")
      }
      data.frame(Variable = v,
                 `% Missing` = round(s$na_count / s$total * 100, 1),
                 Min = d[1L], `0.05` = d[2L], Median = d[3L],
                 Mean = d[4L], `0.95` = d[5L], Max = d[6L],
                 `Missing Explanation` = "",
                 check.names = FALSE, stringsAsFactors = FALSE)
    }))
  } else NULL

  list(meta = meta, cat = cat_result, num = num_df, date = date_df)
}

# ── Write worksheet (identical layout to summarize_npdes.R) ─────────────────

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
      ntbl <- summary_list$num
      writeData(wb, sheet_name, x = ntbl, startRow = row, startCol = 1, colNames = FALSE)
      n_data <- nrow(ntbl)
      addStyle(wb, sheet_name, style_body,
               rows = row:(row + n_data - 1), cols = 1:9, gridExpand = TRUE)
      addStyle(wb, sheet_name, style_number,
               rows = row:(row + n_data - 1), cols = 2:8, gridExpand = TRUE, stack = TRUE)
      row <- row + n_data
    }

    if (!is.null(summary_list$date)) {
      dtbl <- summary_list$date
      writeData(wb, sheet_name, x = dtbl, startRow = row, startCol = 1, colNames = FALSE)
      n_data <- nrow(dtbl)
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

    row <- footer_row + 1 + 1
  }

  setColWidths(wb, sheet_name, cols = 1,   widths = 42)
  setColWidths(wb, sheet_name, cols = 2,   widths = 11)
  setColWidths(wb, sheet_name, cols = 3,   widths = 13)
  setColWidths(wb, sheet_name, cols = 4,   widths = 22)
  setColWidths(wb, sheet_name, cols = 5,   widths = 10)
  setColWidths(wb, sheet_name, cols = 6,   widths = 12)
  setColWidths(wb, sheet_name, cols = 7,   widths = 38)
  setColWidths(wb, sheet_name, cols = 8,   widths = 28)
  setColWidths(wb, sheet_name, cols = 9,   widths = 28)
}

# ── Main ──────────────────────────────────────────────────────────────────────

if (is.na(ZIP_PATH) || !file.exists(ZIP_PATH))
  stop("Effluent-violations zip not found in data/raw/ (looked for pattern 'eff.*zip').")

cat("Starting chunked read (2M rows/chunk) from", basename(ZIP_PATH), "\n")
wb <- createWorkbook()
summary_list <- build_summary_df(ZIP_PATH, CSV_IN_ZIP, NROWS_LIMIT)
write_sheet(wb, "NPDES_EFF_VIOLATIONS", summary_list)

saveWorkbook(wb, OUT_FILE, overwrite = TRUE)
cat("\nDone! Output saved to:", OUT_FILE, "\n")
