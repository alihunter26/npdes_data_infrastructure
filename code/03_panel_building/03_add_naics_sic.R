# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# 03_add_naics_sic.R
# ------------------------------------------------------------------------------
# THIRD STEP in the facility-by-month pipeline. Reads the panel produced by
# 02_add_inspections.R and attaches each facility's industry codes: its NAICS
# code and its SIC code.
#
#   Input  : data/processed/02_facility_month_panel_major_individual_inspections_2005_2025.csv
#            (one row per FACILITY_UIN x YEAR x MONTH; built by scripts 01-02)
#   Output : data/processed/03_facility_month_panel_major_individual_naics_sic_2005_2025.csv
#            (the same panel + 2 new industry-code columns)
#
# COLUMNS ADDED:
#   NAICS_CODE  - the facility's NAICS industry code(s)   (text; may be blank)
#   SIC_CODE    - the facility's SIC industry code(s)      (text; may be blank)
#
# ------------------------------------------------------------------------------
# LABELED ASSUMPTIONS (read before using results):
#
#   1. INDUSTRY CODE IS TIME-INVARIANT. NPDES_NAICS.csv and NPDES_SICS.csv have
#      NO date or permit-version field -- each is just (permit -> code). So a
#      facility's industry code is a single fixed attribute, and we broadcast
#      the SAME code across every one of that facility's months. (Unlike the
#      inspection counts in script 02, it does not vary month to month.)
#
#   2. CODES ARE KEYED TO THE PERMIT, THE PANEL TO THE FACILITY. The code files
#      key on NPDES_ID (a permit). The panel's unit is FACILITY_UIN, and its
#      NPDES_ID column is the semicolon-separated LIST of every individual
#      permit that script 01 linked to that facility. We therefore split that
#      list back into individual permits, look up each permit's code, and
#      recombine to the facility (STEP 2-4). We attach codes only from the
#      permits the panel already assigned to the facility -- never from other
#      permits that merely share the site.
#
#   3. ALL CODES, PRIMARY FIRST. A single permit can carry several NAICS (or
#      SIC) codes. We keep EVERY code (not just the one flagged primary), but
#      order each permit's codes so its PRIMARY_INDICATOR_FLAG == "Y" code
#      comes first, followed by its remaining codes. (Prior to 2026-07-21 this
#      script kept only the primary code, matching the rule in
#      the external ../EIL Summer/build/04_build_permit_panel_major_continuous.R; per Ali's
#      2026-07-17 question in this step's README -- "should it include all?"
#      -- it now does.)
#
#   4. MULTI-VALUE FACILITIES -> SEMICOLON LIST, PRIMARY-FIRST, DEDUPED. Most
#      facilities have exactly one individual permit with exactly one code, so
#      they get exactly one code. For the rest -- a permit with >1 code, a
#      facility with >1 permit, or both -- we combine every non-blank code
#      across all of the facility's permits into one semicolon-separated
#      string, ordered primary-code(s) first and de-duplicated (order
#      preserved, not alphabetical) -- exactly the "; "-join convention script
#      01 uses for the NPDES_ID column itself, so a facility-month stays a
#      single row.
#
#   5. "MISSING" MEANS NO ROW IN THE CODE FILE. A facility whose permit(s) never
#      appear in NPDES_NAICS.csv gets a blank NAICS_CODE (same for SIC). This
#      matches how code coverage/"missingness" has been measured elsewhere in
#      this project. NAICS in particular is blank for a large share of
#      facilities; SIC coverage is near-complete for this major population.
#
#   6. PANEL DEFINES THE OBSERVATION SET. Codes are attached by LEFT-JOINING onto
#      the existing panel spine, so no panel row is added or dropped.
#
# Deterministic (no stochastic steps); rebuilt entirely from raw + scripts 01-02
# output + this script. Non-destructive: writes a NEW file, leaves script 02's
# panel untouched, and is safe to re-run.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)   # fast CSV reads + table joins
})

## ---- Config (edit here if file locations ever change) ------------------------
RAW_DIR  <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
IN_PATH  <- file.path(CWA_ROOT, "data/processed/02_facility_month_panel_major_individual_inspections_2005_2025.csv")
OUT_PATH <- file.path(CWA_ROOT, "data/processed/03_facility_month_panel_major_individual_naics_sic_2005_2025.csv")

# Small helper: read only the columns we need, everything as plain text
# (character) so ID and code columns are never silently reinterpreted as numbers
# (e.g. leading zeros in SIC codes or permit numbers).
rd <- function(file, cols) {
  class_map <- setNames(rep("character", length(cols)), cols)
  fread(file.path(RAW_DIR, file), select = cols,
        colClasses = class_map, showProgress = FALSE)
}

# Small helper: from a code file, return EVERY (NPDES_ID, code) row -- no
# collapsing -- with an explicit IS_PRIMARY flag so downstream steps can order
# primary-first without losing the other codes a permit carries.
all_codes <- function(file, code_col) {
  d <- rd(file, c("NPDES_ID", code_col, "PRIMARY_INDICATOR_FLAG"))
  d[, NPDES_ID := trimws(NPDES_ID)]
  d[, (code_col) := trimws(get(code_col))]
  d[, IS_PRIMARY := PRIMARY_INDICATOR_FLAG == "Y"]
  d[, c("NPDES_ID", code_col, "IS_PRIMARY"), with = FALSE]
}

# ------------------------------------------------------------------------------
# STEP 1: Read the facility-by-month panel (output of script 02).
# ------------------------------------------------------------------------------
# One row per FACILITY_UIN x YEAR x MONTH. Read as character so all IDs/codes
# already in the panel stay exactly as written.
panel <- fread(IN_PATH, colClasses = "character", showProgress = FALSE)

# ------------------------------------------------------------------------------
# STEP 2: Get the facility -> individual-permit(s) map from the panel itself.
# ------------------------------------------------------------------------------
# NPDES_ID is a facility-level attribute (identical across all of a facility's
# months), so one unique row per facility is enough. Then split the semicolon-
# separated permit list into one row PER (facility, permit) so we can look each
# permit up in the code files (ASSUMPTION 2).
fac_permits <- unique(panel[, .(FACILITY_UIN, NPDES_ID)])
fac_long <- fac_permits[, .(NPDES_ID = trimws(unlist(strsplit(NPDES_ID, ";")))),
                        by = FACILITY_UIN]
fac_long <- fac_long[NPDES_ID != ""]      # drop any empty pieces

# ------------------------------------------------------------------------------
# STEP 3: Look up every permit's NAICS and SIC codes (all of them, not just
# the primary one).
# ------------------------------------------------------------------------------
naics <- all_codes("NPDES_NAICS.csv", "NAICS_CODE")
sic   <- all_codes("NPDES_SICS.csv",  "SIC_CODE")

# Attach the codes to each (facility, permit) row -- NAICS and SIC joined
# SEPARATELY, not into one shared table. A permit can carry >1 of each now, so
# joining both onto the same table would cross-join its N naics codes against
# its M sic codes and fabricate N*M rows; keeping them apart avoids that.
# Left joins: every permit row is kept; permits absent from a code file get NA
# (ASSUMPTION 5). allow.cartesian: a permit legitimately fans out to >1 row now.
fac_naics <- naics[fac_long, on = "NPDES_ID", allow.cartesian = TRUE]
fac_sic   <- sic[fac_long,   on = "NPDES_ID", allow.cartesian = TRUE]

# ------------------------------------------------------------------------------
# STEP 4: Collapse back to ONE row per facility (ASSUMPTION 4).
# ------------------------------------------------------------------------------
# For each facility, order its codes so IS_PRIMARY rows sort first, drop blanks,
# de-duplicate (keeping first occurrence -- i.e. primary stays first, order is
# NOT re-sorted alphabetically), then join with "; ".
collapse_primary_first <- function(code, is_primary) {
  code <- code[order(!is_primary)]   # IS_PRIMARY (TRUE) rows first; NA sorts last
  code <- code[!is.na(code) & code != ""]
  code <- unique(code)
  if (length(code) == 0) "" else paste(code, collapse = "; ")
}
fac_codes_naics <- fac_naics[, .(NAICS_CODE = collapse_primary_first(NAICS_CODE, IS_PRIMARY)), by = FACILITY_UIN]
fac_codes_sic   <- fac_sic[,   .(SIC_CODE   = collapse_primary_first(SIC_CODE,   IS_PRIMARY)), by = FACILITY_UIN]
fac_codes <- merge(fac_codes_naics, fac_codes_sic, by = "FACILITY_UIN", all = TRUE)

# ------------------------------------------------------------------------------
# STEP 5: Attach the facility-level codes onto every panel row.
# ------------------------------------------------------------------------------
new_cols <- c("NAICS_CODE", "SIC_CODE")

# Left-join onto the panel by facility (ASSUMPTION 6: panel defines the rows).
panel <- fac_codes[panel, on = "FACILITY_UIN"]

# Any facility with no code row at all came through as NA -> normalize to blank
# text, so the columns are clean and consistent.
for (c in new_cols)
  panel[is.na(get(c)), (c) := ""]

# Put the new columns at the end, after the existing panel columns, and restore
# the panel's row order.
setcolorder(panel, c(setdiff(names(panel), new_cols), new_cols))
setorder(panel, FACILITY_UIN, YEAR, MONTH)

fwrite(panel, OUT_PATH)

# ------------------------------------------------------------------------------
# STEP 6: Run log (sanity checks; coverage should match earlier findings).
# ------------------------------------------------------------------------------
# Coverage is a FACILITY property, so compute it over distinct facilities, not
# over the (much larger) count of facility-month rows.
fac_level <- unique(panel[, .(FACILITY_UIN, NAICS_CODE, SIC_CODE)])
has_naics <- fac_level$NAICS_CODE != ""
has_sic   <- fac_level$SIC_CODE   != ""
message("=== 03_add_naics_sic: industry codes attached to month panel ===")
message("Distinct facilities in panel                   : ", nrow(fac_level))
message("...with a NAICS code                            : ",
        sum(has_naics), " (", round(100 * mean(has_naics), 1), "%)")
message("...with a SIC   code                            : ",
        sum(has_sic), " (", round(100 * mean(has_sic), 1), "%)")
message("Panel rows: ", nrow(panel), " | columns: ", ncol(panel))
message("Written to: ", OUT_PATH)
