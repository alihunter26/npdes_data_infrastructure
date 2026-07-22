# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# missingness_audit_major_individual.R
# ------------------------------------------------------------------------------
# For every core ICIS-NPDES bulk file already used to build the major-individual
# facility-month panel (scripts 01-06 in scripts/build panel/), compute what share of
# each column is missing -- RESTRICTED to the same population as that panel:
# NPDES_IDs that are individual ("NPD") permits ever flagged MAJOR at some
# point in their history.
#
#   Population source : the NPDES_ID column of
#                        06_facility_month_panel_major_individual_effluent_2005_2025.csv
#                        (semicolon-separated where a facility has >1 permit),
#                        split back out into one qualifying NPDES_ID per row.
#                        This is the exact same population the panel uses, so
#                        results here are traceable to, and consistent with,
#                        the existing panel-building scripts.
#   Files covered     : ICIS_FACILITIES, ICIS_PERMITS, NPDES_INSPECTIONS,
#                        NPDES_FORMAL_ENFORCEMENT_ACTIONS,
#                        NPDES_INFORMAL_ENFORCEMENT_ACTIONS, NPDES_NAICS,
#                        NPDES_SICS, NPDES_CS_VIOLATIONS, NPDES_PS_VIOLATIONS,
#                        NPDES_SE_VIOLATIONS, NPDES_QNCR_HISTORY,
#                        NPDES_VIOLATION_ENFORCEMENTS, NPDES_EFF_VIOLATIONS.
#                        (Deliberately excludes NPDES_LIMITS.csv (7GB), Attains,
#                        DMR fiscal-year files, and the outfalls layer -- out of
#                        scope for this audit.)
#   "Missing"         : blank string, literal "NA", or a true NA -- same
#                        na.strings convention used elsewhere in this repo.
#   "Chronically
#    missing"         : flagged if >=25% of a variable's values are missing
#                        within the restricted population.
#
# LABELED ASSUMPTIONS:
#   1. NPDES_VIOLATION_ENFORCEMENTS.csv has no NPDES_ID column of its own -- it
#      links NPDES_VIOLATION_ID to an enforcement action (ENF_IDENTIFIER). To
#      restrict it to the major-individual population, we first collect every
#      qualifying NPDES_VIOLATION_ID from the CS/PS/SE/EFF violations files
#      (all of which DO have NPDES_ID), then filter this file to that set.
#   2. NPDES_EFF_VIOLATIONS.csv lives inside a ~2.9GB zip (~16GB uncompressed,
#      46.4 million rows) and is read in chunks (chunk_size below) to keep peak
#      memory low, mirroring scripts/summary/summarize_eff_violations.R. Only
#      per-column running totals (n non-missing, n rows) are kept across
#      chunks -- individual rows are discarded after each chunk to bound memory.
#   3. Every other file here is small enough (<600MB) to read whole in one
#      shot, restrict, and tabulate directly.
#   4. The qualitative columns (what's affected / why it's a problem /
#      severity) are analyst judgment, not derived data -- they are written as
#      a literal lookup table below (ANNOTATIONS), keyed to the exact
#      variables this script's own quantitative pass flags as chronically
#      missing, so the final table is still produced by one script run.
#
# Output: output/missingness_audit_major_individual_<timestamp>.csv (full
#         per-variable missingness stats, EVERY column of every file) and
#         output/chronic_missingness_major_individual_<timestamp>.csv (only
#         the >=25%-missing variables, with the qualitative annotations).
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

RAW_DIR <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
PANEL_PATH <- file.path(CWA_ROOT, "data/processed",
                        "06_facility_month_panel_major_individual_effluent_2005_2025.csv")
TS <- format(Sys.time(), "%Y-%m-%d_%H%M")
OUT_FULL    <- file.path(CWA_ROOT, "output", sprintf("missingness_audit_major_individual_%s.csv", TS))
OUT_CHRONIC <- file.path(CWA_ROOT, "output", sprintf("chronic_missingness_major_individual_%s.csv", TS))
CHRONIC_THRESHOLD <- 25   # percent

# ------------------------------------------------------------------------------
# STEP 1: Build the "major, ever-individual" NPDES_ID population from the
# already-built panel (see LABELED ASSUMPTION intro above for why we reuse it
# rather than recomputing the major/individual logic from scratch here).
# ------------------------------------------------------------------------------
panel_ids <- fread(PANEL_PATH, colClasses = "character",
                   select = c("FACILITY_UIN", "NPDES_ID"))
panel_ids <- unique(panel_ids, by = "FACILITY_UIN")
QUAL_IDS  <- sort(unique(unlist(strsplit(panel_ids$NPDES_ID, "; "))))
message("Qualifying facilities             : ", nrow(panel_ids))
message("Qualifying individual NPDES_IDs   : ", length(QUAL_IDS))

# ------------------------------------------------------------------------------
# Helper: given a data.table already restricted to the qualifying population,
# compute % missing (blank / "NA" text / true NA) for every column.
# ------------------------------------------------------------------------------
missingness_table <- function(dt, file_label) {
  n <- nrow(dt)
  rows <- lapply(names(dt), function(v) {
    x <- dt[[v]]
    is_miss <- is.na(x) | trimws(x) == "" | trimws(x) == "NA"
    data.table(file = file_label, variable = v, n_rows = n,
              pct_missing = round(100 * sum(is_miss) / n, 2))
  })
  rbindlist(rows)
}

results <- list()

# ------------------------------------------------------------------------------
# STEP 2: Small/medium files -- read whole, restrict to QUAL_IDS, tabulate.
# ------------------------------------------------------------------------------
read_restrict <- function(file, id_col, ids = QUAL_IDS) {
  dt <- fread(file.path(RAW_DIR, file), colClasses = "character", na.strings = c("", "NA"))
  dt[[id_col]] <- trimws(dt[[id_col]])
  dt[dt[[id_col]] %chin% ids]
}

simple_files <- list(
  list(file = "ICIS_FACILITIES.csv",                 id_col = "NPDES_ID"),
  list(file = "NPDES_INSPECTIONS.csv",                id_col = "NPDES_ID"),
  list(file = "NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv", id_col = "NPDES_ID"),
  list(file = "NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv", id_col = "NPDES_ID"),
  list(file = "NPDES_NAICS.csv",                      id_col = "NPDES_ID"),
  list(file = "NPDES_SICS.csv",                       id_col = "NPDES_ID"),
  list(file = "NPDES_CS_VIOLATIONS.csv",              id_col = "NPDES_ID"),
  list(file = "NPDES_PS_VIOLATIONS.csv",              id_col = "NPDES_ID"),
  list(file = "NPDES_SE_VIOLATIONS.csv",              id_col = "NPDES_ID"),
  list(file = "NPDES_QNCR_HISTORY.csv",               id_col = "NPDES_ID")
)

# NPDES_VIOLATION_ID sets from CS/PS/SE, collected while we already have each
# file in memory (LABELED ASSUMPTION 1) -- needed later for
# NPDES_VIOLATION_ENFORCEMENTS.csv, which has no NPDES_ID of its own.
qual_violation_ids <- character(0)

for (spec in simple_files) {
  cat("Reading + restricting:", spec$file, "...\n")
  dt <- read_restrict(spec$file, spec$id_col)
  cat("  rows in qualifying population:", nrow(dt), "\n")
  results[[spec$file]] <- missingness_table(dt, spec$file)
  if ("NPDES_VIOLATION_ID" %in% names(dt))
    qual_violation_ids <- unique(c(qual_violation_ids, trimws(dt$NPDES_VIOLATION_ID)))
  rm(dt); gc(FALSE)
}

# ICIS_PERMITS.csv uses a different ID column name for the same NPDES_ID concept.
cat("Reading + restricting: ICIS_PERMITS.csv ...\n")
permits <- fread(file.path(RAW_DIR, "ICIS_PERMITS.csv"), colClasses = "character",
                 na.strings = c("", "NA"))
permits[, EXTERNAL_PERMIT_NMBR := trimws(EXTERNAL_PERMIT_NMBR)]
permits <- permits[EXTERNAL_PERMIT_NMBR %chin% QUAL_IDS]
cat("  rows in qualifying population:", nrow(permits), "\n")
results[["ICIS_PERMITS.csv"]] <- missingness_table(permits, "ICIS_PERMITS.csv")
rm(permits); gc(FALSE)

# ------------------------------------------------------------------------------
# STEP 3: NPDES_EFF_VIOLATIONS.csv -- the ~16GB effluent violations file, read
# in chunks straight from its zip (LABELED ASSUMPTION 2). We accumulate running
# per-column (non-missing count, row count) totals rather than keeping rows,
# to bound peak memory on this 8GB machine.
# ------------------------------------------------------------------------------
ZIP_PATH   <- list.files(file.path(CWA_ROOT, "data/raw"), pattern = "eff.*zip", full.names = TRUE)[1]
CSV_IN_ZIP <- "NPDES_EFF_VIOLATIONS.csv"
read_cmd   <- sprintf("unzip -p %s %s", shQuote(ZIP_PATH), shQuote(CSV_IN_ZIP))
eff_cols   <- names(fread(cmd = read_cmd, nrows = 0))

chunk_size <- 2000000L
skip <- 1L
total_rows_qual <- 0L
miss_count <- setNames(rep(0L, length(eff_cols)), eff_cols)

repeat {
  chunk <- fread(cmd = read_cmd, header = FALSE, skip = skip, nrows = chunk_size,
                 col.names = eff_cols, colClasses = "character",
                 na.strings = c("", "NA"), showProgress = FALSE)
  nr <- nrow(chunk)
  if (nr == 0L) break
  chunk[, NPDES_ID := trimws(NPDES_ID)]
  qual <- chunk[NPDES_ID %chin% QUAL_IDS]
  if (nrow(qual) > 0) {
    total_rows_qual <- total_rows_qual + nrow(qual)
    qual_violation_ids <- unique(c(qual_violation_ids, trimws(qual$NPDES_VIOLATION_ID)))
    for (v in eff_cols) {
      x <- qual[[v]]
      miss_count[v] <- miss_count[v] + sum(is.na(x) | trimws(x) == "" | trimws(x) == "NA")
    }
  }
  cat(sprintf("  eff_violations: qualifying rows so far: %s\n", format(total_rows_qual, big.mark = ",")))
  if (nr < chunk_size) break
  skip <- skip + chunk_size
  rm(chunk, qual); gc(FALSE)
}

results[["NPDES_EFF_VIOLATIONS.csv"]] <- data.table(
  file = "NPDES_EFF_VIOLATIONS.csv", variable = eff_cols, n_rows = total_rows_qual,
  pct_missing = round(100 * miss_count[eff_cols] / total_rows_qual, 2))

# ------------------------------------------------------------------------------
# STEP 4: NPDES_VIOLATION_ENFORCEMENTS.csv -- restrict via the qualifying
# NPDES_VIOLATION_ID set collected above (LABELED ASSUMPTION 1), since this
# file has no NPDES_ID of its own.
# ------------------------------------------------------------------------------
cat("Reading + restricting: NPDES_VIOLATION_ENFORCEMENTS.csv ...\n")
ve <- fread(file.path(RAW_DIR, "NPDES_VIOLATION_ENFORCEMENTS.csv"), colClasses = "character",
           na.strings = c("", "NA"))
ve[, NPDES_VIOLATION_ID := trimws(NPDES_VIOLATION_ID)]
ve <- ve[NPDES_VIOLATION_ID %chin% qual_violation_ids]
cat("  rows in qualifying population:", nrow(ve), "\n")
results[["NPDES_VIOLATION_ENFORCEMENTS.csv"]] <- missingness_table(ve, "NPDES_VIOLATION_ENFORCEMENTS.csv")
rm(ve); gc(FALSE)

# ------------------------------------------------------------------------------
# STEP 5: Assemble the full missingness table and write it (every column, every
# file -- for traceability, per CLAUDE.md: every number must trace to a run).
# ------------------------------------------------------------------------------
full_tbl <- rbindlist(results)
setorder(full_tbl, -pct_missing)
fwrite(full_tbl, OUT_FULL)
message("Full per-variable missingness written to: ", OUT_FULL)

# ------------------------------------------------------------------------------
# STEP 6: Flag "chronically missing" variables (>=25%) and attach qualitative
# annotations (analyst judgment -- see LABELED ASSUMPTION 4).
# ------------------------------------------------------------------------------
chronic <- full_tbl[pct_missing >= CHRONIC_THRESHOLD]
setorder(chronic, -pct_missing)

# Lookup table: (file, variable) -> what is affected / why it's a problem / severity.
# Filled in AFTER reviewing which variables the quantitative pass above actually
# flags (kept here, not computed, because these are judgment calls -- see
# LABELED ASSUMPTION 4). Any flagged variable not yet in this lookup prints with
# blank annotation columns rather than silently disappearing, so a re-run after
# a raw-data refresh can't hide a new chronic-missingness case.
ANNOTATIONS <- data.table(
  file = character(0), variable = character(0),
  what_is_affected = character(0), why_problem = character(0), severity = character(0)
)

chronic <- merge(chronic, ANNOTATIONS, by = c("file", "variable"), all.x = TRUE, sort = FALSE)
for (col in c("what_is_affected", "why_problem", "severity"))
  chronic[is.na(get(col)), (col) := ""]
setorder(chronic, -pct_missing)

fwrite(chronic, OUT_CHRONIC)
message("Chronic (>=", CHRONIC_THRESHOLD, "%) missingness written to: ", OUT_CHRONIC)
message("Chronically missing variables found: ", nrow(chronic))
print(chronic[, .(file, variable, n_rows, pct_missing)])
