# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# build_dmr_raw_summary.R
# ------------------------------------------------------------------------------
# Computes the SAME kind of summary (categorical top-5 tables, numeric 5-number
# summaries, date ranges) that code/summary/combine_dmr_summaries*.R produce
# for the FILTERED pipeline stages (01-04) -- but for the RAW, UNFILTERED FY
# DMR file (every permit, every parameter, no restriction at all).
#
# WHY DUCKDB INSTEAD OF fread: the raw file is ~4.7-26.9M rows (vs. the
# already-filtered 01_dmr_fy<year>.csv, which is restricted to major-individual
# permits and is what combine_dmr_summaries*.R safely reads with fread). Fully
# materializing 26.9M rows x 57 columns in R on this 8GB-RAM machine risks
# an OOM crash. Instead this script loads the raw CSV into a DuckDB table
# (out-of-core, spills to disk) and computes every summary statistic via SQL
# aggregation -- the raw data itself is never pulled into R as a data.frame,
# only the small aggregated results are.
#
# COLUMN CLASSIFICATION: hardcoded below to exactly match what fread/combine_
# dmr_summaries.R already inferred for 01_dmr_fy2025.csv (extracted from its
# generated workbook). Raw and filtered files share the same schema/column
# content, so the same classification applies.
#
# Usage:
#   Rscript code/summary/build_dmr_raw_summary.R <FY>
#
# Output: output/DMR/raw_summary_fy<FY>.rds -- a summary_list (meta/cat/num/
#   date) in the exact structure combine_dmr_summaries*.R's write_sheet()
#   expects, so it can be prepended as that workbook's first sheet without
#   re-deriving any of this.
# ==============================================================================

suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
  library(data.table)
})

## ---- FY from command line ----
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1 || is.na(suppressWarnings(as.integer(args[1]))))
  stop("Usage: Rscript build_dmr_raw_summary.R <FY>  (e.g. 2025)")
FY <- as.integer(args[1])

## ---- Config ----
ZIP_NAME   <- sprintf("npdes_dmrs_fy%d.zip", FY)
CSV_MEMBER <- sprintf("NPDES_DMRS_FY%d.csv", FY)
ZIP_PATH   <- file.path(DMR_DIR, ZIP_NAME)

SCRATCH  <- Sys.getenv("CWA_SCRATCH", "/tmp/cwa_dmr_raw_cache")
GZ_TMP   <- file.path(SCRATCH, sprintf("NPDES_DMRS_FY%d.csv.gz", FY))
DUCK_TMP <- file.path(SCRATCH, sprintf("duckdb_spill_fy%d", FY))
REUSE_GZ <- TRUE
MEM_LIMIT <- "5GB"

OUT_DIR <- file.path(CWA_ROOT, "output/DMR")
OUT_RDS <- file.path(OUT_DIR, sprintf("raw_summary_fy%d.rds", FY))
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(SCRATCH,  showWarnings = FALSE, recursive = TRUE)
dir.create(DUCK_TMP, showWarnings = FALSE, recursive = TRUE)

# ---- 1. Decompress the CSV member -> gzip temp (once, reusable across runs) --
if (REUSE_GZ && file.exists(GZ_TMP) && file.info(GZ_TMP)$size > 0) {
  message("Reusing existing gzip temp: ", GZ_TMP,
          " (", round(file.info(GZ_TMP)$size / 1e9, 2), " GB)")
} else {
  if (!file.exists(ZIP_PATH)) stop("FY", FY, " DMR zip not found: ", ZIP_PATH)
  message("Streaming CSV member out of the zip and re-gzipping to: ", GZ_TMP)
  cmd <- sprintf("tar -xOf %s %s | gzip -1 > %s",
                 shQuote(ZIP_PATH), shQuote(CSV_MEMBER), shQuote(GZ_TMP))
  status <- system(cmd)
  if (status != 0) stop("Extraction pipeline failed (exit ", status, ").")
}

# ---- 2. Load into a DuckDB table (out-of-core; the only "big" step) ----------
con <- dbConnect(duckdb::duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, sprintf("SET memory_limit='%s';", MEM_LIMIT))
dbExecute(con, sprintf("SET temp_directory='%s';", DUCK_TMP))
dbExecute(con, "SET preserve_insertion_order=false;")

message("Loading raw FY", FY, " DMR file into DuckDB (one-time cost for this run) ...")
t0 <- Sys.time()
dbExecute(con, sprintf("
  CREATE OR REPLACE TABLE raw AS
  SELECT * FROM read_csv('%s', all_varchar=true, header=true, sample_size=-1)", GZ_TMP))
message("  loaded in ", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min")

## ---- Column classification (matches fread's inference on the filtered files) ----
CAT_COLS <- c(
  "VERSION_NMBR", "PERM_FEATURE_NMBR", "PERM_FEATURE_TYPE_CODE", "PARAMETER_CODE",
  "MONITORING_LOCATION_CODE", "STAY_TYPE_CODE", "LIMIT_VALUE_TYPE_CODE",
  "LIMIT_UNIT_CODE", "STANDARD_UNIT_CODE", "STATISTICAL_BASE_CODE",
  "STATISTICAL_BASE_TYPE_CODE", "LIMIT_VALUE_QUALIFIER_CODE",
  "OPTIONAL_MONITORING_FLAG", "LIMIT_SAMPLE_TYPE_CODE", "LIMIT_FREQ_OF_ANALYSIS_CODE",
  "LIMIT_TYPE_CODE", "DMR_SAMPLE_TYPE_CODE", "DMR_FREQ_OF_ANALYSIS_CODE",
  "VALUE_TYPE_CODE", "DMR_UNIT_CODE", "DMR_VALUE_QUALIFIER_CODE", "NODI_CODE",
  "VIOLATION_CODE", "RNC_DETECTION_CODE", "RNC_RESOLUTION_CODE"
)
# code -> paired description column (consumed into "Description"; not shown standalone)
# NOTE: a list, not a named atomic vector -- `[[` on an atomic vector throws
# "subscript out of bounds" for a missing name, whereas a list's `[[` returns
# NULL, which the is.null(desc_col) check below relies on.
DESC_PAIR <- list(
  PARAMETER_CODE    = "PARAMETER_DESC",
  LIMIT_UNIT_CODE   = "LIMIT_UNIT_DESC",
  STANDARD_UNIT_CODE = "STANDARD_UNIT_DESC",
  DMR_UNIT_CODE     = "DMR_UNIT_DESC"
)
NUM_COLS <- c(
  "NMBR_OF_SUBMISSION", "NMBR_OF_REPORT", "LIMIT_VALUE_NMBR",
  "LIMIT_VALUE_STANDARD_UNITS", "STAY_VALUE_NMBR", "REPORTED_EXCURSION_NMBR",
  "DMR_VALUE_NMBR", "DMR_VALUE_STANDARD_UNITS", "DAYS_LATE", "EXCEEDENCE_PCT"
)
DATE_COLS <- c(
  "LIMIT_BEGIN_DATE", "LIMIT_END_DATE", "MONITORING_PERIOD_END_DATE",
  "VALUE_RECEIVED_DATE", "RNC_DETECTION_DATE", "RNC_RESOLUTION_DATE"
)
ALL_COLS_ORDER <- c(
  "ACTIVITY_ID", "EXTERNAL_PERMIT_NMBR", "VERSION_NMBR", "PERM_FEATURE_ID",
  "PERM_FEATURE_NMBR", "PERM_FEATURE_TYPE_CODE", "LIMIT_SET_ID",
  "LIMIT_SET_DESIGNATOR", "LIMIT_SET_SCHEDULE_ID", "LIMIT_ID", "LIMIT_BEGIN_DATE",
  "LIMIT_END_DATE", "NMBR_OF_SUBMISSION", "NMBR_OF_REPORT", "PARAMETER_CODE",
  "PARAMETER_DESC", "MONITORING_LOCATION_CODE", "STAY_TYPE_CODE", "LIMIT_VALUE_ID",
  "LIMIT_VALUE_TYPE_CODE", "LIMIT_VALUE_NMBR", "LIMIT_UNIT_CODE", "LIMIT_UNIT_DESC",
  "STANDARD_UNIT_CODE", "STANDARD_UNIT_DESC", "LIMIT_VALUE_STANDARD_UNITS",
  "STATISTICAL_BASE_CODE", "STATISTICAL_BASE_TYPE_CODE", "LIMIT_VALUE_QUALIFIER_CODE",
  "OPTIONAL_MONITORING_FLAG", "LIMIT_SAMPLE_TYPE_CODE", "LIMIT_FREQ_OF_ANALYSIS_CODE",
  "STAY_VALUE_NMBR", "LIMIT_TYPE_CODE", "DMR_EVENT_ID", "MONITORING_PERIOD_END_DATE",
  "DMR_SAMPLE_TYPE_CODE", "DMR_FREQ_OF_ANALYSIS_CODE", "REPORTED_EXCURSION_NMBR",
  "DMR_FORM_VALUE_ID", "VALUE_TYPE_CODE", "DMR_VALUE_ID", "DMR_VALUE_NMBR",
  "DMR_UNIT_CODE", "DMR_UNIT_DESC", "DMR_VALUE_STANDARD_UNITS",
  "DMR_VALUE_QUALIFIER_CODE", "VALUE_RECEIVED_DATE", "DAYS_LATE", "NODI_CODE",
  "EXCEEDENCE_PCT", "NPDES_VIOLATION_ID", "VIOLATION_CODE", "RNC_DETECTION_CODE",
  "RNC_DETECTION_DATE", "RNC_RESOLUTION_CODE", "RNC_RESOLUTION_DATE"
)

# ---- 3. Meta: row count, permit count, temporal range ------------------------
meta_q <- dbGetQuery(con, "
  SELECT count(*) AS n_rows, count(DISTINCT EXTERNAL_PERMIT_NMBR) AS n_permits
  FROM raw")

year_bounds <- rbindlist(lapply(DATE_COLS, function(col) {
  q <- dbGetQuery(con, sprintf("
    SELECT min(year(try_strptime(nullif(%s,''), '%%m/%%d/%%Y'))) AS min_y,
           max(year(try_strptime(nullif(%s,''), '%%m/%%d/%%Y'))) AS max_y
    FROM raw", col, col))
  data.table(col = col, min_y = q$min_y, max_y = q$max_y)
}))
year_range <- sprintf("%d-%d",
                       min(year_bounds$min_y, na.rm = TRUE),
                       max(year_bounds$max_y, na.rm = TRUE))

meta <- list(
  title     = paste0(CSV_MEMBER, ": Raw, unfiltered FY", FY,
                      " DMR records -- every permit (major and minor, individual and general), every parameter, feature type, and monitoring location. No restriction of any kind."),
  highlevel = "One row per DMR parameter/limit submission for the fiscal year, as delivered by EPA ECHO with no row filtering applied. This is the true starting universe every downstream stage (01-04) is filtered from.",
  summary   = sprintf(
    "Observations: %s, Distinct Permits: %s, Temporal Range: %s",
    format(meta_q$n_rows, big.mark = ",", trim = TRUE),
    format(meta_q$n_permits, big.mark = ",", trim = TRUE),
    year_range
  ),
  columns = paste(ALL_COLS_ORDER, collapse = ", ")
)
cat("Rows:", format(meta_q$n_rows, big.mark=","), " Permits:", format(meta_q$n_permits, big.mark=","),
    " Year range:", year_range, "\n")

# ---- 4. Categorical: top-5 + n_categories + %missing, per column -------------
cat_rows_list <- list()
for (col in CAT_COLS) {
  desc_col <- DESC_PAIR[[col]]
  meta_c <- dbGetQuery(con, sprintf("
    SELECT count(*) AS n_total,
           count(DISTINCT nullif(%s,'')) AS n_cat,
           100.0*sum(CASE WHEN nullif(%s,'') IS NULL THEN 1 ELSE 0 END)/count(*) AS pct_missing
    FROM raw", col, col))

  if (is.null(desc_col)) {
    top <- dbGetQuery(con, sprintf("
      SELECT %s AS value, count(*) AS n
      FROM raw WHERE nullif(%s,'') IS NOT NULL
      GROUP BY 1 ORDER BY n DESC LIMIT 5", col, col))
    top$desc <- ""
  } else {
    top <- dbGetQuery(con, sprintf("
      SELECT %s AS value, mode(%s) AS desc, count(*) AS n
      FROM raw WHERE nullif(%s,'') IS NOT NULL
      GROUP BY 1 ORDER BY n DESC LIMIT 5", col, desc_col, col))
  }

  n_rows <- nrow(top)
  if (n_rows == 0) {
    df <- data.frame(
      Variable = "", `% Missing` = round(meta_c$pct_missing, 1), `n Categories` = 0,
      `Frequent Values` = "(all missing)", `%` = NA, n = NA,
      Description = "", `Missing Explanation` = "",
      check.names = FALSE, stringsAsFactors = FALSE)
    n_rows <- 1
  } else {
    n_total_nonmissing <- sum(top$n) # approx; exact denominator is n_total - missing
    denom <- meta_c$n_total - round(meta_c$n_total * meta_c$pct_missing / 100)
    df <- data.frame(
      Variable          = c(col, rep("", n_rows - 1)),
      `% Missing`       = c(round(meta_c$pct_missing, 1), rep(NA, n_rows - 1)),
      `n Categories`    = c(meta_c$n_cat, rep(NA, n_rows - 1)),
      `Frequent Values` = as.character(top$value),
      `%`               = round(100 * top$n / denom, 1),
      n                 = as.integer(top$n),
      Description       = ifelse(is.na(top$desc), "", as.character(top$desc)),
      `Missing Explanation` = c("", rep("", n_rows - 1)),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  cat_rows_list[[length(cat_rows_list) + 1]] <- list(df = df, n_rows = n_rows)
  cat("  categorical:", col, "-", meta_c$n_cat, "categories\n")
}
cat_result <- list(
  df          = do.call(rbind, lapply(cat_rows_list, `[[`, "df")),
  group_sizes = sapply(cat_rows_list, `[[`, "n_rows")
)

# ---- 5. Numeric: one combined single-pass query for all 10 columns -----------
num_select <- unlist(lapply(NUM_COLS, function(col) {
  expr <- sprintf("try_cast(nullif(%s,'') as double)", col)
  c(
    sprintf("100.0*sum(CASE WHEN nullif(%s,'') IS NULL THEN 1 ELSE 0 END)/count(*) AS %s__pctmiss", col, col),
    sprintf("min(%s) AS %s__min", expr, col),
    sprintf("quantile_cont(%s, 0.05) AS %s__p05", expr, col),
    sprintf("median(%s) AS %s__median", expr, col),
    sprintf("avg(%s) AS %s__mean", expr, col),
    sprintf("quantile_cont(%s, 0.95) AS %s__p95", expr, col),
    sprintf("max(%s) AS %s__max", expr, col)
  )
}))
message("Computing numeric summary (single pass over ", format(meta_q$n_rows, big.mark=","), " rows) ...")
num_res <- dbGetQuery(con, sprintf("SELECT %s FROM raw", paste(num_select, collapse = ",\n  ")))

num_df <- rbindlist(lapply(NUM_COLS, function(col) {
  data.frame(
    Variable = col,
    `% Missing` = round(num_res[[paste0(col, "__pctmiss")]], 1),
    Min    = round(num_res[[paste0(col, "__min")]], 3),
    `0.05` = round(num_res[[paste0(col, "__p05")]], 3),
    Median = round(num_res[[paste0(col, "__median")]], 3),
    Mean   = round(num_res[[paste0(col, "__mean")]], 3),
    `0.95` = round(num_res[[paste0(col, "__p95")]], 3),
    Max    = round(num_res[[paste0(col, "__max")]], 3),
    `Missing Explanation` = "",
    check.names = FALSE, stringsAsFactors = FALSE
  )
}))
cat("Numeric columns summarized:", length(NUM_COLS), "\n")

# ---- 6. Dates: one combined single-pass query for all 6 columns -------------
date_select <- unlist(lapply(DATE_COLS, function(col) {
  expr <- sprintf("epoch(try_strptime(nullif(%s,''), '%%m/%%d/%%Y'))/86400.0", col)
  c(
    sprintf("100.0*sum(CASE WHEN nullif(%s,'') IS NULL THEN 1 ELSE 0 END)/count(*) AS %s__pctmiss", col, col),
    sprintf("min(%s) AS %s__min", expr, col),
    sprintf("quantile_cont(%s, 0.05) AS %s__p05", expr, col),
    sprintf("median(%s) AS %s__median", expr, col),
    sprintf("avg(%s) AS %s__mean", expr, col),
    sprintf("quantile_cont(%s, 0.95) AS %s__p95", expr, col),
    sprintf("max(%s) AS %s__max", expr, col)
  )
}))
message("Computing date summary (single pass) ...")
date_res <- dbGetQuery(con, sprintf("SELECT %s FROM raw", paste(date_select, collapse = ",\n  ")))

as_date <- function(days) as.Date(round(days), origin = "1970-01-01")
date_df <- rbindlist(lapply(DATE_COLS, function(col) {
  data.frame(
    Variable = col,
    `% Missing` = round(date_res[[paste0(col, "__pctmiss")]], 1),
    Min    = as_date(date_res[[paste0(col, "__min")]]),
    `0.05` = as_date(date_res[[paste0(col, "__p05")]]),
    Median = as_date(date_res[[paste0(col, "__median")]]),
    Mean   = as_date(date_res[[paste0(col, "__mean")]]),
    `0.95` = as_date(date_res[[paste0(col, "__p95")]]),
    Max    = as_date(date_res[[paste0(col, "__max")]]),
    `Missing Explanation` = "",
    check.names = FALSE, stringsAsFactors = FALSE
  )
}))
cat("Date columns summarized:", length(DATE_COLS), "\n")

# ---- 7. Assemble + save -------------------------------------------------------
summary_list <- list(meta = meta, cat = cat_result, num = as.data.frame(num_df), date = as.data.frame(date_df))
saveRDS(summary_list, OUT_RDS)
cat("\nSaved raw summary_list ->", OUT_RDS, "\n")

unlink(DUCK_TMP, recursive = TRUE)
