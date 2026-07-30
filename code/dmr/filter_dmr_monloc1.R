# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# filter_dmr_monloc1.R
# ------------------------------------------------------------------------------
# Parameterized replacement for filter_dmr_fy2025_monloc1.R / filter_dmr_fy2009_
# monloc1.R -- same logic, FY taken as a command-line argument. Further
# restricts the majors-under-individual, TSS-only FY<year> DMR file
# (02_dmr_fy<year>_00530.csv) to Effluent Gross monitoring locations:
# MONITORING_LOCATION_CODE IN ('1', 'EG') (both map to "Effluent Gross" per
# EPA's REF_MONITORING_LOCATION reference table -- see data/raw/reference/).
# Pure row filter: all 57 columns kept.
#
# Usage:
#   Rscript code/dmr/filter_dmr_monloc1.R <FY>
#
# Moved in from the root-level `dmr analysis/` folder 2026-07-29 -- script AND its
# input/output CSVs both now live in code/dmr/, git-ignored via `code/dmr/*.csv`
# (see code/dmr/README.md). The old `dmr analysis/` folder is gone.
#
# Input : code/dmr/02_dmr_fy<year>_00530.csv         (majors-under-individual, TSS only)
# Output: code/dmr/03_dmr_fy<year>_00530_monloc1.csv  (+ MONITORING_LOCATION_CODE IN ('1','EG'))
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
  stop("Usage: Rscript filter_dmr_monloc1.R <FY>  (e.g. 2025)")
FY <- as.integer(args[1])

## ---- Config ----
DMR_FILTER_DIR <- file.path(CWA_ROOT, "code", "dmr")
IN_PATH   <- file.path(DMR_FILTER_DIR, sprintf("02_dmr_fy%d_00530.csv", FY))
OUT_PATH  <- file.path(DMR_FILTER_DIR, sprintf("03_dmr_fy%d_00530_monloc1.csv", FY))
MON_LOC   <- c("1", "EG")   # both = "Effluent Gross" per EPA reference

MEM_LIMIT <- "5GB"
DUCK_TMP  <- file.path(Sys.getenv("CWA_SCRATCH", tempdir()), sprintf("cwa_dmr_03_fy%d_spill", FY))
dir.create(DUCK_TMP, showWarnings = FALSE, recursive = TRUE)

if (!file.exists(IN_PATH))
  stop("Input file not found: ", IN_PATH, " -- run filter_dmr_00530.R ", FY, " first.")

con <- dbConnect(duckdb::duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, sprintf("SET memory_limit='%s';", MEM_LIMIT))
dbExecute(con, sprintf("SET temp_directory='%s';", DUCK_TMP))
dbExecute(con, "SET preserve_insertion_order=false;")

READ_CSV <- sprintf("read_csv('%s', all_varchar=true, header=true, sample_size=-1)", IN_PATH)
MON_LOC_SQL <- paste(sprintf("'%s'", MON_LOC), collapse = ", ")

message("FY: ", FY)
mon_dist <- dbGetQuery(con, sprintf("
  SELECT MONITORING_LOCATION_CODE, count(*) AS n
  FROM %s GROUP BY 1 ORDER BY n DESC", READ_CSV))
message("MONITORING_LOCATION_CODE distribution in input:")
print(mon_dist, row.names = FALSE)

message("\nFiltering ", IN_PATH, " to MONITORING_LOCATION_CODE IN (", MON_LOC_SQL, ") -> ", OUT_PATH)
dbExecute(con, sprintf("
  COPY (SELECT * FROM %s WHERE MONITORING_LOCATION_CODE IN (%s))
  TO '%s' (HEADER, DELIMITER ',');",
  READ_CSV, MON_LOC_SQL, OUT_PATH))

OUT_CSV <- sprintf("read_csv('%s', all_varchar=true, header=true, sample_size=-1)", OUT_PATH)

in_ncol  <- length(dbGetQuery(con, sprintf("SELECT * FROM %s LIMIT 0", READ_CSV)))
out_ncol <- length(dbGetQuery(con, sprintf("SELECT * FROM %s LIMIT 0", OUT_CSV)))

n_in <- dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s", READ_CSV))$n

chk <- dbGetQuery(con, sprintf("
  SELECT count(*)                             AS n_rows,
         count(DISTINCT EXTERNAL_PERMIT_NMBR)  AS n_permits,
         count(DISTINCT MONITORING_LOCATION_CODE) AS n_monloc
  FROM %s", OUT_CSV))

message("\n=== DONE (FY", FY, ") ===")
message("Input rows (02_dmr_fy", FY, "_00530.csv):                 ", format(n_in, big.mark = ","))
message("Output rows (MONITORING_LOCATION_CODE IN (", MON_LOC_SQL, ")): ", format(chk$n_rows, big.mark = ","))
message("Distinct permits:                                     ", format(chk$n_permits, big.mark = ","))
message("Distinct MONITORING_LOCATION_CODE in output (should be ", length(MON_LOC), "): ", chk$n_monloc)
message("Columns (in / out): ", in_ncol, " / ", out_ncol,
        if (in_ncol == out_ncol) "  (match)" else "  (MISMATCH!)")

if (chk$n_monloc != length(MON_LOC) || in_ncol != out_ncol)
  stop("Verification FAILED -- see mismatches above. Output left in place for inspection.")
message("Verification passed.")

unlink(DUCK_TMP, recursive = TRUE)
