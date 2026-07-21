# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# summarize.R — one script that builds every per-dataset summary workbook.
# ------------------------------------------------------------------------------
# Replaces the seven near-identical scripts that each mirrored summarize_npdes.R
# (npdes, dmrs, attains, eff_violations, eff_violations_state, limits,
# master_general_permits, outfalls_layer). The shared machinery — styles, the
# per-variable helpers, and the worksheet writer — lives here ONCE; each dataset
# is a config entry in the DATASETS registry near the bottom.
#
# Usage (from anywhere inside the repo):
#   Rscript scripts/summary/summarize.R <dataset> [arg]
#
#   <dataset>  one of:  npdes  dmrs  attains  eff_violations
#                       eff_violations_state  limits  master_general_permits
#                       outfalls_layer      (or "all" for the memory-safe ones)
#   [arg]      eff_violations_state -> two-letter state code (default NY)
#              npdes                -> a single filename to summarize (default:
#                                      the dataset's only_file), or "all" to
#                                      summarize every CSV in npdes_downloads/
#                                      (one sheet per table, incl. ICIS_FACILITIES,
#                                      ICIS_PERMITS, etc.) instead of just only_file
#
# Output: a timestamped .xlsx in output/ (one sheet per input table), identical
# in format to what the old per-dataset scripts produced. See "Standardized
# layout" below for the one intentional layout change.
#
# ------------------------------------------------------------------------------
# Standardized layout (the single deliberate difference vs. the old scripts):
#   Every sheet now uses the fuller 9-column numeric table and 8-column
#   categorical table that dmrs/attains already used — i.e. a trailing, blank
#   "Missing Explanation" annotation column. Sheets that previously lacked it
#   (npdes, limits, master_general_permits, outfalls_layer, eff_violations,
#   eff_violations_state) gain that blank column. No SUMMARY STATISTIC changes
#   value — this is a cosmetic column, empty in every original script too.
#   The "Columns:" metadata line now always lists the file's full header.
# ==============================================================================

library(dplyr)
library(data.table)
library(lubridate)
library(openxlsx)

options(openxlsx.dateFormat = "mm/dd/yyyy")

# ── Styles (shared by every sheet) ────────────────────────────────────────────

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

# ── Per-variable helpers (shared) ─────────────────────────────────────────────

# Percent (0-100) of values that are missing, rounded to 1 decimal.
pct_missing <- function(x) round(mean(is.na(x)) * 100, 1)

# For a code column, find its paired description column (ENF_TYPE_CODE -> _DESC).
find_desc_col <- function(var, all_cols) {
  candidate <- sub("_CODE$", "_DESC", var)
  if (candidate != var && candidate %in% all_cols) return(candidate)
  candidate2 <- paste0(var, "_DESC")
  if (candidate2 %in% all_cols) return(candidate2)
  NULL
}

# One block of rows for a categorical variable: the top-N values, their share,
# count, and (when a paired _DESC column exists) a human-readable description.
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
    `n Categories`    = c(n_cat,    rep(NA,       n_rows - 1)),
    `Frequent Values` = vals,
    `%`               = round(as.numeric(top) / n_total * 100, 1),
    n                 = as.integer(top),
    Description       = desc_vec,
    `Missing Explanation` = c("", rep("", n_rows - 1)),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  list(df = df, var_label = var_name, n_rows = n_rows)
}

# One summary row for a numeric variable: % missing + five-number summary + mean.
num_summary_row <- function(x, var_name) {
  xc <- x[!is.na(x)]
  if (length(xc) == 0)
    vals <- rep(NA_real_, 6)
  else
    vals <- c(min(xc), unname(quantile(xc, 0.05)), median(xc),
              mean(xc), unname(quantile(xc, 0.95)), max(xc))
  data.frame(Variable = var_name, `% Missing` = pct_missing(x),
             Min = round(vals[1], 3), `0.05` = round(vals[2], 3),
             Median = round(vals[3], 3), Mean = round(vals[4], 3),
             `0.95` = round(vals[5], 3), Max = round(vals[6], 3),
             `Missing Explanation` = "",
             check.names = FALSE, stringsAsFactors = FALSE)
}

# One summary row for a date variable — same stats, kept as Date objects so they
# display as month/day/year (mean/median of dates are themselves dates).
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

# Parse a character column to Date: try mm/dd/yyyy first, fall back to a tolerant
# multi-order parse only if that leaves more than half of the non-blank values
# unparsed. Returns a Date vector.
parse_date_col <- function(x) {
  parsed <- suppressWarnings(as.Date(x, format = "%m/%d/%Y"))
  if (sum(!is.na(parsed)) >= sum(!is.na(x)) * 0.5) return(parsed)
  as.Date(suppressWarnings(
    parse_date_time(x, orders = c("mdy", "ymd", "dmy"), quiet = TRUE)))
}

# Look up per-file text from a config field that may be a named vector (keyed by
# filename) or a single string that applies to every file.
lookup_text <- function(field, fname) {
  if (is.null(field)) return(NULL)
  if (length(field) == 1 && is.null(names(field))) return(unname(field))
  field[[fname]]
}

# ── The categorical/numeric/date engine (shared by all builders) ──────────────
#
# Given a data.table `dt`, the config `cfg`, and the set of already-computed meta
# fields, produce the {cat, num, date} tables. Columns are dropped with set()
# once summarized so peak memory stays close to the input rather than doubling.
summarize_columns <- function(dt, cfg) {

  all_cols          <- names(dt)
  cols_to_summarise <- setdiff(all_cols, cfg$id_cols)

  # ── Categorical ──  (compute a block for every categorical var, then drop the
  # blocks that belong to _DESC columns already shown beside their _CODE column)
  cat_vars <- cols_to_summarise[vapply(cols_to_summarise, function(v)
    is.character(dt[[v]]) || is.logical(dt[[v]]) || is.factor(dt[[v]]), logical(1))]
  cat_vars <- setdiff(cat_vars, cfg$date_cols)

  cat_result <- if (length(cat_vars) > 0) {
    results <- lapply(cat_vars, function(v) {
      desc_col <- find_desc_col(v, all_cols)
      cat_rows(dt[[v]], v, if (!is.null(desc_col)) dt[[desc_col]] else NULL)
    })
    desc_cols_used <- vapply(cat_vars, function(v) {
      d <- find_desc_col(v, all_cols); if (is.null(d)) "" else d }, character(1))
    results <- results[!cat_vars %in% desc_cols_used]
    for (v in cat_vars) if (v %in% names(dt)) set(dt, j = v, value = NULL)
    gc()
    list(df          = do.call(rbind, lapply(results, `[[`, "df")),
         group_sizes = sapply(results, `[[`, "n_rows"))
  } else NULL

  # ── Numeric ──
  num_present <- intersect(cols_to_summarise, names(dt))
  num_vars    <- num_present[vapply(num_present, function(v) is.numeric(dt[[v]]), logical(1))]
  num_df <- if (length(num_vars) > 0) {
    res <- do.call(rbind, lapply(num_vars, function(v) {
      r <- num_summary_row(dt[[v]], v); set(dt, j = v, value = NULL); r
    }))
    gc(); res
  } else NULL

  # ── Date ──
  date_present <- intersect(cols_to_summarise, names(dt))
  date_vars    <- date_present[vapply(date_present, function(v) inherits(dt[[v]], "Date"), logical(1))]
  date_df <- if (length(date_vars) > 0) {
    res <- do.call(rbind, lapply(date_vars, function(v) {
      r <- date_summary_row(dt[[v]], v); set(dt, j = v, value = NULL); r
    }))
    gc(); res
  } else NULL

  list(cat = cat_result, num = num_df, date = date_df)
}

# Assemble the metadata block (title / high-level sentence / summary line /
# columns line) shared across builders. `stats` carries the pre-computed counts.
build_meta <- function(cfg, fname, all_cols, stats) {
  desc <- lookup_text(cfg$descriptions, fname)
  if (is.null(desc) || is.na(desc)) {
    desc <- if (isTRUE(cfg$derive_desc))
      paste("description of all",
            tolower(gsub("_", " ", sub("^(NPDES|ICIS)_", "",
                                       tools::file_path_sans_ext(fname)))))
    else "data summary"
  }
  highlevel <- lookup_text(cfg$summaries, fname)
  if (is.null(highlevel) || is.na(highlevel)) highlevel <- ""

  title <- if (!is.null(cfg$title_fn)) cfg$title_fn(fname, desc)
           else paste0(fname, ": ", desc)

  # Summary line: Observations, <id_label>, Temporal Range, [Duplicate Rows]
  parts <- c(sprintf("Observations: %s", format(stats$n_rows, big.mark = ",", trim = TRUE)),
             sprintf("%s: %s", stats$id_label, stats$id_count),
             sprintf("Temporal Range: %s", stats$year_range))
  if (identical(cfg$dup_mode, "compute"))
    parts <- c(parts, sprintf("Duplicate Rows: %s", format(stats$n_dup, big.mark = ",", trim = TRUE)))
  else if (identical(cfg$dup_mode, "na_chunked"))
    parts <- c(parts, "Duplicate Rows: N/A (chunked read)")
  summary_line <- paste0(paste(parts, collapse = ", "), stats$note)

  list(title = title, highlevel = highlevel, summary = summary_line,
       columns = paste(all_cols, collapse = ", "))
}

# ── In-memory builder (npdes / dmrs / attains / limits / mgp / outfalls / state)
#
# `df` is the already-loaded table; `all_cols` is the file's full header (may
# include columns dropped at read time, e.g. limits DROP_COLS). Returns the
# list(meta, cat, num, date) consumed by write_sheet().
build_summary <- function(df, cfg, fname, all_cols = NULL, id_label = NULL, note = "") {

  dt <- as.data.table(df)
  if (is.null(all_cols)) all_cols <- names(dt)

  # Treat whitespace-only character cells (" ") as missing, not a category. Some
  # ICIS files (e.g. QNCR HLRNC) use a literal space for "blank".
  if (isTRUE(cfg$trim_ws)) {
    char_cols <- names(dt)[vapply(dt, is.character, logical(1))]
    for (cc in char_cols) {
      idx <- which(trimws(dt[[cc]]) == "")
      if (length(idx)) set(dt, i = idx, j = cc, value = NA_character_)
    }
  }

  # Coerce explicitly-listed numeric columns that arrived as character.
  for (col in intersect(cfg$num_cols, names(dt)))
    if (!is.numeric(dt[[col]])) set(dt, j = col, value = suppressWarnings(as.numeric(dt[[col]])))

  # Coerce explicitly-listed columns to character so they land in the
  # CATEGORICAL section rather than numeric. Needed for small discrete codes
  # that fread reads as integer (e.g. VERSION_NMBR: only ~9 values, a permit
  # re-issuance counter) where a five-number numeric summary would be
  # meaningless -- top-value/frequency counts are the useful view instead.
  for (col in intersect(cfg$force_char_cols, names(dt)))
    if (!is.character(dt[[col]])) set(dt, j = col, value = as.character(dt[[col]]))

  # Parse date columns. `year_cols` (e.g. attains REPORTINGCYCLE) are plain
  # integer years listed in date_cols: leave them numeric (so they're summarized
  # as numbers) but still fold them into the temporal range.
  year_cols  <- intersect(cfg$year_cols, names(dt))
  parse_cols <- setdiff(intersect(cfg$date_cols, names(dt)), year_cols)
  for (col in parse_cols) set(dt, j = col, value = parse_date_col(dt[[col]]))

  n_rows <- nrow(dt)
  all_years <- unlist(lapply(parse_cols, function(col)
    if (inherits(dt[[col]], "Date")) as.integer(format(dt[[col]], "%Y"))))
  for (col in year_cols) if (is.numeric(dt[[col]])) all_years <- c(all_years, dt[[col]])
  year_range <- if (length(all_years) > 0)
    sprintf("%d-%d", min(all_years, na.rm = TRUE), max(all_years, na.rm = TRUE)) else "N/A"

  id_count <- if (!is.null(cfg$id_col) && cfg$id_col %in% names(dt))
    format(n_distinct(dt[[cfg$id_col]], na.rm = TRUE), big.mark = ",") else "N/A"
  n_dup <- if (identical(cfg$dup_mode, "compute")) sum(duplicated(dt)) else NA

  meta <- build_meta(cfg, fname, all_cols, list(
    n_rows = n_rows, id_count = id_count, year_range = year_range, n_dup = n_dup,
    id_label = if (!is.null(id_label)) id_label else cfg$id_label, note = note))

  cnd <- summarize_columns(dt, cfg)
  list(meta = meta, cat = cnd$cat, num = cnd$num, date = cnd$date)
}

# ── Chunked builder (eff_violations only) ─────────────────────────────────────
#
# Streams the CSV straight from its zip (via `unzip -p`) in `chunk_size`-row
# chunks so peak memory is ~one chunk. Categorical frequencies are accumulated
# exactly; numeric/date quantiles are estimated from a rolling random sample.
build_summary_chunked <- function(cfg, fname, nrows_limit = NULL, chunk_size = 2000000) {

  read_cmd <- sprintf("unzip -p %s %s", shQuote(cfg$zip_path), shQuote(cfg$member))

  col_names         <- names(fread(cmd = read_cmd, nrows = 0))
  cols_to_summarise <- setdiff(col_names, cfg$id_cols)
  date_cols_present <- intersect(cfg$date_cols, col_names)

  cat("Sampling 200,000 rows to detect column types...\n")
  samp <- as.data.frame(fread(cmd = read_cmd, nrows = 200000, na.strings = c("", "NA")))
  for (col in date_cols_present) samp[[col]] <- parse_date_col(samp[[col]])
  cat_cols <- setdiff(
    intersect(cols_to_summarise,
      names(samp)[sapply(samp[cols_to_summarise],
                         function(x) is.character(x) | is.logical(x) | is.factor(x))]),
    cfg$date_cols)
  num_cols <- intersect(cols_to_summarise,
    names(samp)[sapply(samp[cols_to_summarise], is.numeric)])

  desc_maps <- list()
  for (v in cat_cols) {
    dc <- find_desc_col(v, col_names)
    if (!is.null(dc) && dc %in% names(samp)) {
      pairs <- unique(data.frame(code = samp[[v]], desc = samp[[dc]], stringsAsFactors = FALSE))
      pairs <- pairs[!is.na(pairs$code) & !is.na(pairs$desc), ]
      if (nrow(pairs) > 0) desc_maps[[v]] <- setNames(pairs$desc, pairs$code)
    }
  }
  rm(samp); gc()

  # Positional (unnamed) classes so fread matches by position under header=FALSE.
  col_classes <- ifelse(col_names %in% num_cols, "numeric", "character")

  cat_acc  <- setNames(lapply(cat_cols, function(v)
    data.table(value = character(0), n = integer(0))), cat_cols)
  num_acc  <- setNames(lapply(num_cols, function(v)
    list(min=Inf, max=-Inf, sum=0, count=0L, na_count=0L, total=0L, sample=numeric(0))), num_cols)
  date_acc <- setNames(lapply(date_cols_present, function(v)
    list(min=Inf, max=-Inf, sum=0, count=0L, na_count=0L, total=0L, sample=numeric(0))), date_cols_present)

  all_years  <- integer(0)
  id_vals    <- character(0)
  total_rows <- 0L
  SAMP_N     <- 20000L

  skip <- 1L  # skip the header row; each iteration advances by chunk_size
  repeat {
    cat(sprintf("  Reading rows %s - %s ...\n",
        format(total_rows + 1L, big.mark = ","),
        format(total_rows + chunk_size, big.mark = ",")))

    chunk <- suppressWarnings(as.data.frame(fread(
      cmd = read_cmd, nrows = chunk_size, skip = skip, header = FALSE,
      col.names = col_names, colClasses = col_classes, na.strings = c("", "NA"))))
    if (nrow(chunk) == 0L) break
    if (!is.null(nrows_limit) && total_rows + nrow(chunk) > nrows_limit)
      chunk <- chunk[seq_len(nrows_limit - total_rows), , drop = FALSE]
    nr <- nrow(chunk)

    # fread only upgrades types; force the numeric coercion it may have skipped.
    for (v in num_cols)
      if (!is.numeric(chunk[[v]])) chunk[[v]] <- suppressWarnings(as.numeric(chunk[[v]]))
    for (col in date_cols_present) chunk[[col]] <- parse_date_col(chunk[[col]])

    if (!is.null(cfg$id_col) && cfg$id_col %in% col_names)
      id_vals <- unique(c(id_vals, unique(chunk[[cfg$id_col]][!is.na(chunk[[cfg$id_col]])])))
    for (col in date_cols_present)
      if (inherits(chunk[[col]], "Date"))
        all_years <- c(all_years, as.integer(format(chunk[[col]][!is.na(chunk[[col]])], "%Y")))

    for (v in cat_cols) {
      tbl <- table(chunk[[v]], useNA = "no")
      if (length(tbl) > 0L) {
        cat_acc[[v]] <- rbind(cat_acc[[v]], data.table(value = names(tbl), n = as.integer(tbl)))
        if (nrow(cat_acc[[v]]) > 100000L)
          cat_acc[[v]] <- cat_acc[[v]][, .(n = sum(n)), by = value][order(-n)][seq_len(min(.N, 20000L))]
      }
    }
    for (v in num_cols) {
      x <- chunk[[v]]; xc <- x[!is.na(x)]; s <- num_acc[[v]]
      s$total <- s$total + nr; s$na_count <- s$na_count + sum(is.na(x))
      if (length(xc) > 0L) {
        s$min <- min(s$min, min(xc)); s$max <- max(s$max, max(xc))
        s$sum <- s$sum + sum(as.numeric(xc)); s$count <- s$count + length(xc)
        s$sample <- c(s$sample, xc[sample.int(length(xc), min(SAMP_N, length(xc)))])
      }
      num_acc[[v]] <- s
    }
    for (v in date_cols_present) {
      s <- date_acc[[v]]; s$total <- s$total + nr
      if (!inherits(chunk[[v]], "Date")) {
        s$na_count <- s$na_count + nr
      } else {
        x <- as.numeric(chunk[[v]]); xc <- x[!is.na(x)]
        s$na_count <- s$na_count + sum(is.na(x))
        if (length(xc) > 0L) {
          s$min <- min(s$min, min(xc)); s$max <- max(s$max, max(xc))
          s$sum <- s$sum + sum(xc); s$count <- s$count + length(xc)
          s$sample <- c(s$sample, xc[sample.int(length(xc), min(SAMP_N, length(xc)))])
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

  year_range <- if (length(all_years) > 0L)
    sprintf("%d-%d", min(all_years, na.rm = TRUE), max(all_years, na.rm = TRUE)) else "N/A"
  id_count <- if (length(id_vals) > 0L) format(length(id_vals), big.mark = ",") else "N/A"

  meta <- build_meta(cfg, fname, col_names, list(
    n_rows = total_rows, id_count = id_count, year_range = year_range, n_dup = NA,
    id_label = cfg$id_label, note = ""))

  # Finalize categorical
  cat_result <- if (length(cat_cols) > 0L) {
    results <- lapply(cat_cols, function(v) {
      final   <- cat_acc[[v]][, .(n = sum(n)), by = value][order(-n)]
      n_total <- sum(final$n)
      pct_mis <- round((total_rows - n_total) / total_rows * 100, 1)
      n_cat   <- nrow(final); top <- head(final, 5L); n_rows <- nrow(top)
      if (n_cat == 0L) {
        return(list(df = data.frame(Variable = v, `% Missing` = pct_mis, `n Categories` = 0L,
                      `Frequent Values` = "(all missing)", `%` = NA_real_, n = NA_integer_,
                      Description = "", `Missing Explanation` = "",
                      check.names = FALSE, stringsAsFactors = FALSE),
                    var_label = v, n_rows = 1L))
      }
      dm    <- desc_maps[[v]]
      descs <- if (!is.null(dm))
        sapply(top$value, function(val) if (!is.na(val) && val %in% names(dm)) dm[[val]] else "")
      else rep("", n_rows)
      list(df = data.frame(
             Variable          = c(v,       rep("", n_rows - 1L)),
             `% Missing`       = c(pct_mis, rep(NA_real_,    n_rows - 1L)),
             `n Categories`    = c(n_cat,   rep(NA_integer_, n_rows - 1L)),
             `Frequent Values` = top$value,
             `%`               = round(top$n / n_total * 100, 1),
             n                 = as.integer(top$n),
             Description       = descs,
             `Missing Explanation` = c("", rep("", n_rows - 1L)),
             check.names = FALSE, stringsAsFactors = FALSE),
           var_label = v, n_rows = n_rows)
    })
    desc_cols_used <- vapply(cat_cols, function(v) {
      d <- find_desc_col(v, col_names); if (is.null(d)) "" else d }, character(1))
    results <- results[!cat_cols %in% desc_cols_used]
    list(df = do.call(rbind, lapply(results, `[[`, "df")),
         group_sizes = sapply(results, `[[`, "n_rows"))
  } else NULL

  # Finalize numeric
  num_df <- if (length(num_cols) > 0L) do.call(rbind, lapply(num_cols, function(v) {
    s <- num_acc[[v]]; samp <- s$sample[!is.na(s$sample)]
    if (s$count == 0L || length(samp) == 0L) vals <- rep(NA_real_, 6L)
    else { q <- quantile(samp, c(0.05, 0.5, 0.95)); vals <- c(s$min, q[1L], q[2L], s$sum / s$count, q[3L], s$max) }
    data.frame(Variable = v, `% Missing` = round(s$na_count / s$total * 100, 1),
               Min = round(vals[1L], 3), `0.05` = round(vals[2L], 3), Median = round(vals[3L], 3),
               Mean = round(vals[4L], 3), `0.95` = round(vals[5L], 3), Max = round(vals[6L], 3),
               `Missing Explanation` = "", check.names = FALSE, stringsAsFactors = FALSE)
  })) else NULL

  # Finalize dates
  active_date_cols <- date_cols_present[vapply(date_acc[date_cols_present], function(s) s$count > 0L, logical(1))]
  date_df <- if (length(active_date_cols) > 0L) do.call(rbind, lapply(active_date_cols, function(v) {
    s <- date_acc[[v]]; samp <- s$sample[!is.na(s$sample)]
    if (s$count == 0L || length(samp) == 0L) d <- rep(as.Date(NA), 6L)
    else { q <- quantile(samp, c(0.05, 0.5, 0.95))
           d <- as.Date(round(c(s$min, q[1L], q[2L], s$sum / s$count, q[3L], s$max)), origin = "1970-01-01") }
    data.frame(Variable = v, `% Missing` = round(s$na_count / s$total * 100, 1),
               Min = d[1L], `0.05` = d[2L], Median = d[3L], Mean = d[4L], `0.95` = d[5L], Max = d[6L],
               `Missing Explanation` = "", check.names = FALSE, stringsAsFactors = FALSE)
  })) else NULL

  list(meta = meta, cat = cat_result, num = num_df, date = date_df)
}

# ── Worksheet writer (shared) ─────────────────────────────────────────────────

write_sheet <- function(wb, sheet_name, s) {

  addWorksheet(wb, sheet_name)
  row <- 1

  writeData(wb, sheet_name, x = s$meta$title, startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_title, rows = row, cols = 1); row <- row + 1

  if (nzchar(s$meta$highlevel)) {
    writeData(wb, sheet_name, x = s$meta$highlevel, startRow = row, startCol = 1)
    addStyle(wb, sheet_name, style_highlevel, rows = row, cols = 1); row <- row + 1
  }

  writeData(wb, sheet_name, x = s$meta$summary, startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_meta, rows = row, cols = 1); row <- row + 1

  writeData(wb, sheet_name, x = paste("Columns:", s$meta$columns), startRow = row, startCol = 1)
  addStyle(wb, sheet_name, style_meta, rows = row, cols = 1); row <- row + 2

  # ── Categorical table (8 columns) ──
  if (!is.null(s$cat)) {
    tbl <- s$cat$df; group_sizes <- s$cat$group_sizes
    writeData(wb, sheet_name, x = tbl, startRow = row, startCol = 1, colNames = TRUE, rowNames = FALSE)
    addStyle(wb, sheet_name, style_hdr_cat, rows = row, cols = 1:8, gridExpand = TRUE); row <- row + 1

    n_data <- nrow(tbl)
    addStyle(wb, sheet_name, style_body,   rows = row:(row + n_data - 1), cols = 1:8, gridExpand = TRUE)
    addStyle(wb, sheet_name, style_number, rows = row:(row + n_data - 1), cols = c(2, 5), gridExpand = TRUE, stack = TRUE)
    addStyle(wb, sheet_name, style_int,    rows = row:(row + n_data - 1), cols = 6, gridExpand = TRUE, stack = TRUE)

    cur_row <- row
    for (g in group_sizes) {
      if (g > 1) for (col in c(1, 2, 3)) {
        mergeCells(wb, sheet_name, cols = col, rows = cur_row:(cur_row + g - 1))
        addStyle(wb, sheet_name, style_valign, rows = cur_row:(cur_row + g - 1), cols = col, gridExpand = TRUE, stack = TRUE)
      }
      cur_row <- cur_row + g
    }
    row <- row + n_data + 2
  }

  # ── Numeric + Date table (9 columns) ──
  if (!is.null(s$num) || !is.null(s$date)) {
    hdr_row <- row
    writeData(wb, sheet_name,
              x = t(c("Variable", "% Missing", "Min", "0.05", "Median", "Mean", "0.95", "Max", "Missing Explanation")),
              startRow = hdr_row, startCol = 1, colNames = FALSE)
    writeData(wb, sheet_name, x = 0.05, startRow = hdr_row, startCol = 4)
    writeData(wb, sheet_name, x = 0.95, startRow = hdr_row, startCol = 7)
    addStyle(wb, sheet_name, style_hdr_num, rows = hdr_row, cols = 1:9, gridExpand = TRUE); row <- hdr_row + 1

    if (!is.null(s$num)) {
      ntbl <- s$num; n_data <- nrow(ntbl)
      writeData(wb, sheet_name, x = ntbl, startRow = row, startCol = 1, colNames = FALSE)
      addStyle(wb, sheet_name, style_body,   rows = row:(row + n_data - 1), cols = 1:9, gridExpand = TRUE)
      addStyle(wb, sheet_name, style_number, rows = row:(row + n_data - 1), cols = 2:8, gridExpand = TRUE, stack = TRUE)
      row <- row + n_data
    }
    if (!is.null(s$date)) {
      dtbl <- s$date; n_data <- nrow(dtbl)
      writeData(wb, sheet_name, x = dtbl, startRow = row, startCol = 1, colNames = FALSE)
      addStyle(wb, sheet_name, style_body,   rows = row:(row + n_data - 1), cols = 1:9, gridExpand = TRUE)
      addStyle(wb, sheet_name, style_number, rows = row:(row + n_data - 1), cols = 2, gridExpand = TRUE, stack = TRUE)
      addStyle(wb, sheet_name, style_date,   rows = row:(row + n_data - 1), cols = 3:8, gridExpand = TRUE, stack = TRUE)
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

# ── Readers ───────────────────────────────────────────────────────────────────

# Read one CSV straight from a zip member via `unzip -p` (no extraction to disk).
# `drop_ids` keeps `id_col` but drops the other identifier columns to save memory.
read_zip_csv <- function(zip_path, member, id_cols = NULL, id_col = NULL, nrows = NULL) {
  read_cmd <- sprintf("unzip -p %s %s", shQuote(zip_path), shQuote(member))
  all_cols <- names(fread(cmd = read_cmd, nrows = 0))
  sel <- if (!is.null(id_cols)) setdiff(all_cols, setdiff(id_cols, id_col)) else all_cols
  df <- fread(cmd = read_cmd, select = sel, na.strings = c("", "NA"),
              nrows = if (is.null(nrows)) Inf else nrows)
  list(df = df, all_cols = all_cols)
}

# Read a zipped CSV in chunks, keeping only rows whose `id_col` starts with the
# two-letter state code. Streams via `unzip -p`; peak memory is ~one chunk.
read_state_rows <- function(zip_path, member, id_col, state, chunk_size = 1000000) {
  read_cmd  <- sprintf("unzip -p %s %s", shQuote(zip_path), shQuote(member))
  col_names <- names(fread(cmd = read_cmd, nrows = 0))
  kept <- list(); skip_rows <- 0; total_read <- 0; chunk_num <- 0
  repeat {
    chunk_num <- chunk_num + 1
    cat(sprintf("Reading chunk %d (rows %s - %s)...\n", chunk_num,
                format(skip_rows + 1, big.mark = ","), format(skip_rows + chunk_size, big.mark = ",")))
    chunk <- fread(cmd = read_cmd, skip = skip_rows, nrows = chunk_size,
                   col.names = col_names, header = FALSE, na.strings = c("", "NA"))
    n_read <- nrow(chunk); total_read <- total_read + n_read
    hit <- chunk[startsWith(as.character(chunk[[id_col]]), state)]
    cat(sprintf("  Read %s rows; kept %s.\n", format(n_read, big.mark = ","), format(nrow(hit), big.mark = ",")))
    if (nrow(hit) > 0) kept[[length(kept) + 1]] <- hit
    rm(chunk); gc()
    if (n_read < chunk_size) break
    skip_rows <- skip_rows + chunk_size
  }
  cat(sprintf("\nTotal rows read: %s\n", format(total_read, big.mark = ",")))
  if (length(kept) == 0) stop(sprintf("No rows found for state '%s'.", state))
  df <- rbindlist(kept)
  list(df = as.data.frame(df), all_cols = col_names)
}

# ── Dataset registry ──────────────────────────────────────────────────────────
#
# Each entry is a config list read by the dispatcher. Common fields:
#   mode        "memory" | "chunked"
#   id_cols     identifier columns excluded from per-variable summaries
#   date_cols   columns parsed as dates
#   num_cols    columns force-coerced to numeric (optional)
#   trim_ws     TRUE to blank whitespace-only character cells (npdes/limits)
#   id_col      column for the distinct-entity meta count
#   id_label    label for that count ("Distinct Facilities" / "Distinct Permits")
#   dup_mode    "compute" | "none" | "na_chunked"
#   descriptions / summaries   single string, or named-by-filename vector
#   derive_desc TRUE to synthesize a title description from the filename (npdes)
#   out_prefix  output file stem -> output/<out_prefix>_<timestamp>.xlsx
#   inputs      function(cfg, arg) -> list of items, each:
#                 list(sheet = <31-char sheet name>, load = function() list(df, all_cols),
#                      id_label = <optional per-item override>, note = <optional>)

npdes_descriptions <- c(
  "ICIS_FACILITIES.csv" = "description of all facilities",
  "ICIS_PERMITS.csv" = "description of all permits",
  "NPDES_CS_VIOLATIONS.csv" = "description of all compliance schedule violations",
  "NPDES_DATA_GROUPS.csv" = "description of all data groups",
  "NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv" = "description of all formal enforcement actions",
  "NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv" = "description of all informal enforcement actions",
  "NPDES_INSPECTIONS.csv" = "description of all inspections",
  "NPDES_NAICS.csv" = "description of all NAICS codes",
  "NPDES_PERM_COMPONENTS.csv" = "description of all permit components",
  "NPDES_PERM_FEATURE_COORDS.csv" = "description of all permit feature coordinates",
  "NPDES_PS_VIOLATIONS.csv" = "description of all permit schedule violations",
  "NPDES_QNCR_HISTORY.csv" = "description of all quarterly non-compliance report history",
  "NPDES_SE_VIOLATIONS.csv" = "description of all single event violations",
  "NPDES_SICS.csv" = "description of all SIC codes",
  "NPDES_VIOLATION_ENFORCEMENTS.csv" = "description of all violation enforcements"
)
npdes_summaries <- c(
  "ICIS_FACILITIES.csv" = "One row per regulated NPDES facility, with identifying information, location, and current permitted/active status. Serves as the central reference table for joining facility-level attributes to permits, violations, and enforcement records.",
  "ICIS_PERMITS.csv" = "One row per NPDES permit issued to a facility, including permit type, issuing agency, and key dates (issuance, effective, expiration). Links facilities to their permitted limits and components.",
  "NPDES_CS_VIOLATIONS.csv" = "Compliance schedule violations, i.e. instances where a facility missed a required milestone in an agreed-upon compliance schedule. Each row is one violation tied to a specific scheduled requirement.",
  "NPDES_DATA_GROUPS.csv" = "Groupings used to organize related monitoring parameters and limits within a permit. Used to relate individual parameters back to the broader limit set they belong to.",
  "NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv" = "Formal enforcement actions taken against facilities for permit violations, including the enforcement type, responsible agency, and any penalties assessed. Each row is one enforcement action.",
  "NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv" = "Informal enforcement actions (e.g. warning letters, notices of violation) issued to facilities, generally less severe than formal actions. Each row is one informal action.",
  "NPDES_INSPECTIONS.csv" = "Facility inspections conducted by regulatory agencies, including inspection type, date, and the agency responsible. Each row is one inspection event.",
  "NPDES_NAICS.csv" = "Maps facilities to their North American Industry Classification System (NAICS) code(s), describing the industry sector(s) each facility operates in.",
  "NPDES_PERM_COMPONENTS.csv" = "Individual components (e.g. outfalls or limit sets) defined within each NPDES permit. Links permits to their specific monitoring and limit requirements.",
  "NPDES_PERM_FEATURE_COORDS.csv" = "Geographic coordinates for permitted features (such as outfalls) associated with each facility's permit.",
  "NPDES_PS_VIOLATIONS.csv" = "Permit schedule violations, where a facility missed a scheduled permit requirement outside of a formal compliance schedule. Each row is one such violation.",
  "NPDES_QNCR_HISTORY.csv" = "Quarterly Noncompliance Report (QNCR) history, tracking a facility's reported compliance status across successive quarters.",
  "NPDES_SE_VIOLATIONS.csv" = "Single-event violations, i.e. one-time violations not tied to a recurring monitoring schedule. Each row is one violation event.",
  "NPDES_SICS.csv" = "Maps facilities to their Standard Industrial Classification (SIC) code(s), an older industry classification system still used alongside NAICS.",
  "NPDES_VIOLATION_ENFORCEMENTS.csv" = "Links individual violations to the enforcement action(s) taken in response, allowing violations and enforcement records to be cross-referenced."
)

# Helper: build an in-memory input item that reads a plain CSV from disk.
csv_item <- function(path, id_cols = NULL, drop_cols = NULL, nrows = NULL,
                     sheet = NULL, id_label = NULL, note = "") {
  fname <- basename(path)
  list(sheet = if (!is.null(sheet)) sheet else substr(tools::file_path_sans_ext(fname), 1, 31),
       fname = fname, id_label = id_label, note = note,
       load = function() {
         args <- list(file = path, na.strings = c("", "NA"), showProgress = FALSE)
         if (!is.null(drop_cols)) args$drop <- drop_cols
         if (!is.null(nrows))     args$nrows <- nrows
         df <- as.data.frame(do.call(fread, args))
         list(df = df, all_cols = names(df))
       })
}

DATASETS <- list(

  npdes = list(
    mode = "memory", trim_ws = TRUE, dup_mode = "compute", derive_desc = TRUE,
    id_col = "NPDES_ID", id_label = "Distinct Facilities",
    out_prefix = "npdes",
    only_file = "NPDES_QNCR_HISTORY.csv",
    data_dir = file.path(CWA_ROOT, "data/raw/npdes_downloads"),
    descriptions = npdes_descriptions, summaries = npdes_summaries,
    id_cols = c("NPDES_ID","EXTERNAL_PERMIT_NMBR","MASTER_EXTERNAL_PERMIT_NMBR",
      "ACTIVITY_ID","ENF_IDENTIFIER","NPDES_VIOLATION_ID","COMP_SCHEDULE_EVENT_ID",
      "COMP_SCHEDULE_NMBR","PERM_SCHEDULE_EVENT_ID","PERM_FEATURE_NMBR","PERM_FEATURE_ID",
      "REGISTRY_ID","ICIS_FACILITY_INTEREST_ID","FACILITY_UIN","VERSION_NMBR","RAD_WBD_HUC12S",
      "FACILITY_NAME","LOCATION_ADDRESS","SUPPLEMENTAL_ADDRESS_TEXT","CITY","ZIP",
      "IMPAIRED_WATERS","STATE_WATER_BODY","STATE_WATER_BODY_NAME","PERMIT_NAME"),
    date_cols = c("SETTLEMENT_ENTERED_DATE","ACHIEVED_DATE","ACTUAL_BEGIN_DATE","ACTUAL_END_DATE",
      "SCHEDULE_DATE","ACTUAL_DATE","RNC_DETECTION_DATE","RNC_RESOLUTION_DATE","REPORT_RECEIVED_DATE",
      "SINGLE_EVENT_VIOLATION_DATE","SINGLE_EVENT_END_DATE","ORIGINAL_ISSUE_DATE","ISSUE_DATE",
      "EFFECTIVE_DATE","EXPIRATION_DATE","RETIREMENT_DATE","TERMINATION_DATE","CREATED_DATE","UPDATED_DATE"),
    inputs = function(cfg, arg) {
      # arg == "all" bypasses only_file and processes every CSV in data_dir
      # (e.g. ICIS_FACILITIES.csv, ICIS_PERMITS.csv, ...), one sheet each.
      files <- if (identical(arg, "all")) list.files(cfg$data_dir, pattern = "\\.csv$", full.names = TRUE)
               else if (!is.null(arg)) file.path(cfg$data_dir, arg)
               else if (!is.null(cfg$only_file)) file.path(cfg$data_dir, cfg$only_file)
               else list.files(cfg$data_dir, pattern = "\\.csv$", full.names = TRUE)
      if (length(files) == 0 || !all(file.exists(files)))
        stop("No CSV files found in: ", cfg$data_dir)
      lapply(files, function(f) csv_item(f, id_cols = cfg$id_cols))
    }
  ),

  attains = list(
    mode = "memory", trim_ws = FALSE, dup_mode = "compute",
    id_col = "NPDES_ID", id_label = "Distinct Facilities",
    out_prefix = "attains",
    data_dir = file.path(CWA_ROOT, "data/raw/Attains"),
    id_cols = c("NPDES_ID","REGISTRY_ID","ECHO_DFR_URL","AU_URL","ASSESSMENTUNITIDENTIFIER",
      "ASSESSMENTUNITNAME","WATERBODYREPORTLINK","GNIS_NAME","WBD_HU12NAME","REACHCODE",
      "HUC12","WBD_HU12","NHDPLUSID","SUB_ID"),
    date_cols = c("REPORTINGCYCLE"),
    year_cols = c("REPORTINGCYCLE"),   # a plain year: summarized as a number, not a date
    descriptions = c(
      "NPDES_ATTAINS_AU_SUMMARIES.csv" = "description of all NPDES-ATTAINS assessment unit summaries",
      "ATTAINS_AU_CATCHMENTS.csv" = "description of all ATTAINS assessment unit catchments",
      "NPDES_CATCHMENTS.csv" = "description of all NPDES permit catchment linkages"),
    summaries = c(
      "NPDES_ATTAINS_AU_SUMMARIES.csv" = "Links each NPDES facility to the ATTAINS water quality assessment unit(s) it discharges into, with the overall water condition, use support status (drinking water, ecological, fish consumption, recreation), and any impairment causes. One row per facility-assessment unit pair.",
      "ATTAINS_AU_CATCHMENTS.csv" = "Maps ATTAINS assessment units to NHDPlus catchments, with impairment status, 303(d) listing, TMDL and protection plan flags, and catchment geometry attributes.",
      "NPDES_CATCHMENTS.csv" = "Links each NPDES permit to its NHDPlus catchment, including the best-pick catchment selection, geographic coordinates, HUC12 watershed, and catchment/reach characteristics (navigable, headwater, coastal, tidal, Alaskan)."),
    inputs = function(cfg, arg) {
      files <- list.files(cfg$data_dir, pattern = "\\.csv$", full.names = TRUE)
      # Skip empty files (header-only or truly empty), matching the old script.
      files <- Filter(function(f) nrow(fread(f, nrows = 1, na.strings = c("", "NA"))) > 0, files)
      lapply(files, function(f) csv_item(f, id_cols = cfg$id_cols))
    }
  ),

  limits = list(
    mode = "memory", trim_ws = TRUE, dup_mode = "compute",
    id_col = "EXTERNAL_PERMIT_NMBR", id_label = "Distinct Permits",
    out_prefix = "npdes_limits",
    data_file = file.path(CWA_ROOT, "data/raw/NPDES_LIMITS.csv"),
    sample_n = NULL,   # set to e.g. 2e6 for a fast, approximate preview run
    drop_cols = c("ACTIVITY_ID","PERM_FEATURE_ID","LIMIT_SET_ID","LIMIT_SET_SCHEDULE_ID",
      "LIMIT_ID","LIMIT_VALUE_ID","LIMIT_SEASON_ID","LIMIT_SET_NAME","DMR_COMMENT_TEXT"),
    id_cols = c("EXTERNAL_PERMIT_NMBR","VERSION_NMBR","PERM_FEATURE_NMBR"),
    date_cols = c("LIMIT_BEGIN_DATE","LIMIT_END_DATE"),
    descriptions = c("NPDES_LIMITS.csv" = "the numeric discharge limits written into each permit"),
    summaries = c("NPDES_LIMITS.csv" = "One row per permit limit: a specific numeric limit for one pollutant, at one discharge point (outfall), under one permit, during one effective period. Carries the limit value, units, statistical basis (e.g. daily max vs monthly average), monitoring frequency, effective date range, and seasonal applicability by month (the JAN-DEC columns). It does NOT contain the facility's reported discharge - pair with the DMR data for actual-vs-allowed."),
    inputs = function(cfg, arg) {
      note <- if (!is.null(cfg$sample_n))
        sprintf(" [SAMPLE: first %s rows - approximate]", format(as.integer(cfg$sample_n), big.mark = ",")) else ""
      # Note: DROP_COLS shrink the loaded table but the "Columns:" line still
      # lists the file's full header (scanned below) for completeness.
      full_hdr <- names(fread(cfg$data_file, nrows = 0))
      item <- csv_item(cfg$data_file, drop_cols = cfg$drop_cols, nrows = cfg$sample_n,
                       sheet = "NPDES_LIMITS", note = note)
      loader <- item$load
      item$load <- function() { r <- loader(); r$all_cols <- full_hdr; r }
      list(item)
    }
  ),

  master_general_permits = list(
    mode = "memory", trim_ws = FALSE, dup_mode = "compute",
    id_col = "NPDES_ID", id_label = "Distinct Facilities",
    out_prefix = "master_general_permits",
    csv_path = file.path(CWA_ROOT, "data/raw/Master General Permits/ICIS_MASTER_GENERAL_PERMITS.csv"),
    nrows_limit = NULL,
    id_cols = c("NPDES_ID","EXTERNAL_PERMIT_NMBR","MASTER_EXTERNAL_PERMIT_NMBR","ACTIVITY_ID",
      "VERSION_NMBR","RAD_WBD_HUC12S","STATE_WATER_BODY","STATE_WATER_BODY_NAME","PERMIT_NAME"),
    date_cols = c("ORIGINAL_ISSUE_DATE","ISSUE_DATE","EFFECTIVE_DATE","EXPIRATION_DATE",
      "RETIREMENT_DATE","TERMINATION_DATE"),
    descriptions = "description of all ICIS master general permits",
    summaries = "One row per NPDES master general permit (e.g. stormwater or CAFO general permits), with permit type, issuing agency, status, and key dates. Master general permits serve as the template that individual facilities certify coverage under, rather than receiving their own individual permit.",
    inputs = function(cfg, arg)
      list(csv_item(cfg$csv_path, nrows = cfg$nrows_limit))
  ),

  outfalls_layer = list(
    mode = "memory", trim_ws = FALSE, dup_mode = "compute",
    id_col = "EXTERNAL_PERMIT_NMBR", id_label = "Distinct Permits",
    out_prefix = "outfalls_layer",
    csv_path = file.path(CWA_ROOT, "data/raw/npdes_outfalls_layer.csv"),
    id_cols = c("EXTERNAL_PERMIT_NMBR","FACILITY_NAME","LOCATION_ADDRESS","CITY","ZIP",
      "PERMIT_NAME","STATE_WATER_BODY_NAME","SIC_CODES","SIC_DESCRIPTIONS","NAICS_CODES",
      "FAC_DERIVED_TRIBES","PERMIT_COMPONENTS","PERM_FEATURE_NMBR"),
    date_cols = c("CWP_DATE_LAST_INSPECTION","DATE_LAST_FORMAL_EA","PERMIT_EFFECTIVE_DATE",
      "PERMIT_EXPIRATION_DATE","PERMIT_TERMINATION_DATE"),
    descriptions = "description of all NPDES outfall locations",
    summaries = "One row per permitted outfall (discharge point) in the NPDES program, with facility location, permit type and status, compliance indicators, and geographic coordinates. This is the spatial/GIS layer of NPDES permits and is often used to map facilities and join location data to other NPDES tables.",
    inputs = function(cfg, arg)
      list(csv_item(cfg$csv_path, sheet = "NPDES_OUTFALLS_LAYER"))
  ),

  dmrs = list(
    mode = "memory", trim_ws = FALSE, dup_mode = "none",
    id_col = "EXTERNAL_PERMIT_NMBR", id_label = "Distinct Permits",
    out_prefix = "dmrs",
    zip_path = file.path(CWA_ROOT, "data/raw/DMR/npdes_dmrs_fy2025.zip"),
    member = "NPDES_DMRS_FY2025.csv", sheet = "NPDES_DMRS_FY2025", nrows_limit = NULL,
    # PERM_FEATURE_NMBR (the outfall/pipe label, e.g. "001", "001A") and
    # VERSION_NMBR (permit re-issuance counter, ~9 distinct values) are
    # deliberately NOT in id_cols: both are treated as categorical variables
    # (top values + distinct count), unlike PERM_FEATURE_ID (the high-
    # cardinality internal integer64 system id, which stays excluded below).
    # PERM_FEATURE_NMBR is already read as character; VERSION_NMBR reads as
    # integer, so it's force-coerced to character via force_char_cols below
    # (otherwise it would land in the numeric five-number-summary section).
    id_cols = c("ACTIVITY_ID","EXTERNAL_PERMIT_NMBR","PERM_FEATURE_ID",
      "LIMIT_SET_ID","LIMIT_SET_DESIGNATOR","LIMIT_SET_SCHEDULE_ID",
      "LIMIT_ID","LIMIT_VALUE_ID","DMR_EVENT_ID","DMR_FORM_VALUE_ID","DMR_VALUE_ID","NPDES_VIOLATION_ID"),
    force_char_cols = c("VERSION_NMBR"),
    date_cols = c("LIMIT_BEGIN_DATE","LIMIT_END_DATE","MONITORING_PERIOD_END_DATE",
      "VALUE_RECEIVED_DATE","RNC_DETECTION_DATE","RNC_RESOLUTION_DATE"),
    descriptions = c("NPDES_DMRS_FY2025.csv" = "description of all DMR (Discharge Monitoring Report) records, FY2025"),
    summaries = c("NPDES_DMRS_FY2025.csv" = "One row per DMR parameter/limit submission for FY2025, linking each facility's reported discharge values to the applicable permit limits. Includes the reported value, limit, unit, exceedance %, violation code, and noncompliance detection/resolution dates."),
    inputs = function(cfg, arg) {
      if (!file.exists(cfg$zip_path)) stop("Zip file not found: ", cfg$zip_path)
      list(list(sheet = cfg$sheet, fname = cfg$member, id_label = NULL, note = "",
                load = function() read_zip_csv(cfg$zip_path, cfg$member,
                                               id_cols = cfg$id_cols, id_col = cfg$id_col,
                                               nrows = cfg$nrows_limit)))
    }
  ),

  eff_violations_state = list(
    mode = "memory", trim_ws = FALSE, dup_mode = "compute",
    id_col = "NPDES_ID",   # id_label set dynamically per state below
    out_prefix = "eff_violations",   # actual prefix gets the state code appended
    member = "NPDES_EFF_VIOLATIONS.csv", chunk_size = 1000000,
    id_cols = c("NPDES_ID","VERSION_NMBR","ACTIVITY_ID","NPDES_VIOLATION_ID","PERM_FEATURE_NMBR",
      "PERMIT_ACTIVITY_ID","DMR_FORM_VALUE_ID","DMR_VALUE_ID","DMR_PARAMETER_ID","LIMIT_ID"),
    num_cols = c("DMR_VALUE_NMBR","LIMIT_VALUE_STANDARD_UNITS","EXCEEDENCE_PCT","DAYS_LATE","DMR_VALUE_STANDARD_UNITS"),
    date_cols = c("MONITORING_PERIOD_END_DATE","VALUE_RECEIVED_DATE","RNC_DETECTION_DATE","RNC_RESOLUTION_DATE"),
    # `configure` bakes the per-state text/naming into cfg so the dispatcher's
    # local cfg (and thus out_prefix, title, descriptions) reflects the state.
    configure = function(cfg, arg) {
      state <- toupper(if (!is.null(arg)) arg else "NY")
      state_lc   <- tolower(state)
      state_name <- if (state %in% state.abb) state.name[match(state, state.abb)] else state
      cfg$zip_path <- list.files(file.path(CWA_ROOT, "data/raw/"), pattern = "eff.*zip", full.names = TRUE)[1]
      if (is.na(cfg$zip_path) || !file.exists(cfg$zip_path))
        stop("Effluent-violations zip not found in data/raw/ (pattern 'eff.*zip').")
      cfg$state <- state; cfg$state_name <- state_name
      cfg$out_prefix   <- sprintf("eff_violations_%s", state_lc)
      cfg$id_label     <- sprintf("Distinct %s Permits", state)
      cfg$descriptions <- sprintf("description of effluent (DMR) violations for %s facilities (NPDES_ID starting with '%s')", state_name, state)
      cfg$summaries    <- sprintf("One row per parameter/limit violation reported on a %s facility's DMR. Filtered from the full national NPDES_EFF_VIOLATIONS file to NPDES_IDs beginning with '%s'. Includes the parameter, violation type, reported vs. limit value, exceedance %%, and noncompliance detection/resolution dates.", state_name, state)
      cfg$title_fn     <- function(fname, desc) paste0(fname, sprintf(" (%s only): ", state_name), desc)
      cfg$csv_out      <- file.path(CWA_ROOT, sprintf("output/eff_violations_%s_%s.csv",
                                    state_lc, format(Sys.time(), "%Y-%m-%d_%H%M")))
      cfg
    },
    inputs = function(cfg, arg)
      list(list(sheet = paste0("EFF_VIOLATIONS_", cfg$state), fname = cfg$member,
                id_label = cfg$id_label, note = "",
                load = function() {
                  r <- read_state_rows(cfg$zip_path, cfg$member, cfg$id_col, cfg$state, cfg$chunk_size)
                  fwrite(r$df, cfg$csv_out); cat("CSV saved to:", cfg$csv_out, "\n")
                  r
                }))
  ),

  eff_violations = list(
    mode = "chunked", dup_mode = "na_chunked",
    id_col = "NPDES_ID", id_label = "Distinct Facilities",
    out_prefix = "eff_violations",
    member = "NPDES_EFF_VIOLATIONS.csv", sheet = "NPDES_EFF_VIOLATIONS", nrows_limit = NULL,
    id_cols = c("NPDES_ID","VERSION_NMBR","ACTIVITY_ID","NPDES_VIOLATION_ID","PERM_FEATURE_NMBR",
      "PERMIT_ACTIVITY_ID","DMR_FORM_VALUE_ID","DMR_VALUE_ID","DMR_PARAMETER_ID","LIMIT_ID"),
    date_cols = c("MONITORING_PERIOD_END_DATE","VALUE_RECEIVED_DATE","RNC_DETECTION_DATE","RNC_RESOLUTION_DATE"),
    descriptions = "description of all effluent (DMR) violations",
    summaries = "Effluent (Discharge Monitoring Report) violations - one row per parameter/limit violation reported on a facility's DMR, including the parameter, limit, reported value, and any resulting noncompliance detection/resolution.",
    configure = function(cfg, arg) {
      cfg$zip_path <- list.files(file.path(CWA_ROOT, "data/raw/"), pattern = "eff.*zip", full.names = TRUE)[1]
      if (is.na(cfg$zip_path) || !file.exists(cfg$zip_path))
        stop("Effluent-violations zip not found in data/raw/ (pattern 'eff.*zip').")
      cfg
    }
  )
)

# ── Dispatcher ────────────────────────────────────────────────────────────────

run_dataset <- function(key, arg = NULL) {
  cfg <- DATASETS[[key]]
  if (is.null(cfg)) stop("Unknown dataset: ", key,
                         "\nKnown: ", paste(names(DATASETS), collapse = ", "))

  out_file <- function(prefix)
    sprintf(file.path(CWA_ROOT, "output/%s_summary_%s.xlsx"),
            prefix, format(Sys.time(), "%Y-%m-%d_%H%M"))

  # Per-run specialization (e.g. state naming, locating a zip) before anything
  # reads cfg fields like out_prefix / descriptions.
  if (!is.null(cfg$configure)) cfg <- cfg$configure(cfg, arg)

  wb <- createWorkbook()

  if (identical(cfg$mode, "chunked")) {
    cat("Starting chunked read from", basename(cfg$zip_path), "...\n")
    s <- build_summary_chunked(cfg, cfg$member, cfg$nrows_limit)
    write_sheet(wb, cfg$sheet, s)
    of <- out_file(cfg$out_prefix)
  } else {
    items <- cfg$inputs(cfg, arg)
    for (it in items) {
      cat("Processing", it$fname, "...\n")
      loaded <- it$load()
      s <- build_summary(loaded$df, cfg, it$fname, all_cols = loaded$all_cols,
                         id_label = it$id_label, note = if (is.null(it$note)) "" else it$note)
      write_sheet(wb, it$sheet, s)
    }
    of <- out_file(cfg$out_prefix)
  }

  dir.create(dirname(of), showWarnings = FALSE, recursive = TRUE)
  saveWorkbook(wb, of, overwrite = TRUE)
  cat("\nDone! Output saved to:", of, "\n")
  invisible(of)
}

# ── Main ──────────────────────────────────────────────────────────────────────

MEMORY_SAFE <- c("npdes", "dmrs", "attains", "master_general_permits", "outfalls_layer")

# Set SUMMARIZE_NO_MAIN=1 to source this file for its functions without running
# the CLI (used by the verification harness).
if (!interactive() && !nzchar(Sys.getenv("SUMMARIZE_NO_MAIN"))) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) == 0L) {
    cat("Usage: Rscript scripts/summary/summarize.R <dataset> [arg]\n",
        "  datasets:", paste(names(DATASETS), collapse = ", "), "\n",
        "  or 'all' for the memory-safe datasets:", paste(MEMORY_SAFE, collapse = ", "), "\n",
        "  npdes all -> every CSV in npdes_downloads/ (ignores only_file)\n",
        sep = " ")
    quit(status = 1L)
  }
  key <- args[[1L]]
  arg <- if (length(args) >= 2L) args[[2L]] else NULL
  if (identical(key, "all")) {
    for (k in MEMORY_SAFE) { cat("\n===== ", k, " =====\n"); run_dataset(k) }
  } else {
    run_dataset(key, arg)
  }
}
