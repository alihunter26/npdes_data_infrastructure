# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# filter_dmr_00530.R
# ------------------------------------------------------------------------------
# Parameterized replacement for filter_dmr_fy2025_00530.R / filter_dmr_fy2009_
# 00530.R -- same logic, FY taken as a command-line argument. Further
# restricts the majors-under-individual FY<year> DMR file (01_dmr_fy<year>.csv,
# built by filter_dmr_major_individual.R) to PARAMETER_CODE = '00530' (Solids,
# total suspended -- TSS). Pure row filter: all 57 columns kept.
#
# Usage:
#   Rscript code/dmr/filter_dmr_00530.R <FY>
#
# Moved in from the root-level `dmr analysis/` folder 2026-07-29 -- script AND its
# input/output CSVs both now live in code/dmr/, git-ignored via `code/dmr/*.csv`
# (see code/dmr/README.md). The old `dmr analysis/` folder is gone.
#
# Input : code/dmr/01_dmr_fy<year>.csv        (majors-under-individual, all params)
# Output: code/dmr/02_dmr_fy<year>_00530.csv   (+ PARAMETER_CODE = '00530' only)
#
# Engine: DuckDB, out-of-core.
# ==============================================================================

suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
})

## ---- FY from command line ----
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1 || is.na(suppressWarnings(as.integer(args[1]))))
  stop("Usage: Rscript filter_dmr_00530.R <FY>  (e.g. 2025)")
FY <- as.integer(args[1])

## ---- Config ----
DMR_FILTER_DIR <- file.path(CWA_ROOT, "code", "dmr")
IN_PATH   <- file.path(DMR_FILTER_DIR, sprintf("01_dmr_fy%d.csv", FY))
OUT_PATH  <- file.path(DMR_FILTER_DIR, sprintf("02_dmr_fy%d_00530.csv", FY))
PARAM     <- "00530"

MEM_LIMIT <- "5GB"
DUCK_TMP  <- file.path(Sys.getenv("CWA_SCRATCH", tempdir()), sprintf("cwa_dmr_02_fy%d_spill", FY))
dir.create(DUCK_TMP, showWarnings = FALSE, recursive = TRUE)

if (!file.exists(IN_PATH))
  stop("Input file not found: ", IN_PATH,
       " -- run filter_dmr_major_individual.R ", FY, " first.")

con <- dbConnect(duckdb::duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, sprintf("SET memory_limit='%s';", MEM_LIMIT))
dbExecute(con, sprintf("SET temp_directory='%s';", DUCK_TMP))
dbExecute(con, "SET preserve_insertion_order=false;")

READ_CSV <- sprintf("read_csv('%s', all_varchar=true, header=true, sample_size=-1)", IN_PATH)

message("FY: ", FY)
message("Filtering ", IN_PATH, " to PARAMETER_CODE = '", PARAM, "' -> ", OUT_PATH)
dbExecute(con, sprintf("
  COPY (SELECT * FROM %s WHERE PARAMETER_CODE = '%s')
  TO '%s' (HEADER, DELIMITER ',');",
  READ_CSV, PARAM, OUT_PATH))

OUT_CSV <- sprintf("read_csv('%s', all_varchar=true, header=true, sample_size=-1)", OUT_PATH)

in_ncol  <- length(dbGetQuery(con, sprintf("SELECT * FROM %s LIMIT 0", READ_CSV)))
out_ncol <- length(dbGetQuery(con, sprintf("SELECT * FROM %s LIMIT 0", OUT_CSV)))

n_in <- dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s", READ_CSV))$n

chk <- dbGetQuery(con, sprintf("
  SELECT count(*)                             AS n_rows,
         count(DISTINCT EXTERNAL_PERMIT_NMBR)  AS n_permits,
         count(DISTINCT PARAMETER_CODE)        AS n_param
  FROM %s", OUT_CSV))

message("\n=== DONE (FY", FY, ") ===")
message("Input rows (01_dmr_fy", FY, ".csv):   ", format(n_in, big.mark = ","))
message("Output rows (PARAMETER_CODE=", PARAM, "): ", format(chk$n_rows, big.mark = ","))
message("Distinct permits:                 ", format(chk$n_permits, big.mark = ","))
message("Distinct PARAMETER_CODE in output (should be 1): ", chk$n_param)
message("Columns (in / out): ", in_ncol, " / ", out_ncol,
        if (in_ncol == out_ncol) "  (match)" else "  (MISMATCH!)")

if (chk$n_param != 1 || in_ncol != out_ncol)
  stop("Verification FAILED -- see mismatches above. Output left in place for inspection.")
message("Verification passed.")

unlink(DUCK_TMP, recursive = TRUE)
