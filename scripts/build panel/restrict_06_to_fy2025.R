# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, PROC_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# restrict_06_to_fy2025.R
# ------------------------------------------------------------------------------
# Restrict the step-06 facility-by-month panel to Fiscal Year 2025.
#
# Input : data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv
# Output: data/processed/06_facility_month_panel_major_individual_effluent_fy2025.csv
#
# This is a pure ROW filter: every column of the 06 panel is preserved unchanged;
# only facility-months outside FY2025 are dropped. Run after the 01..06 pipeline.
# ==============================================================================

suppressPackageStartupMessages(library(data.table))

# ---- LABELED ASSUMPTION: what "FY 2025" means --------------------------------
# "FY 2025" = the FEDERAL fiscal year 2025 = October 2024 through September 2025,
# matching the DMR FY2025 convention used elsewhere in the project (the FY2025 DMR
# file covers monitoring periods 2024-10 .. 2025-09). To instead keep the calendar
# year (Jan..Dec 2025), set FY_CALENDAR <- TRUE.
FY          <- 2025L
FY_CALENDAR <- FALSE   # FALSE => Oct(FY-1)..Sep(FY);  TRUE => Jan..Dec(FY)

IN_PATH  <- file.path(CWA_ROOT, "data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv")
OUT_PATH <- file.path(CWA_ROOT, "data/processed/06_facility_month_panel_major_individual_effluent_fy2025.csv")

if (!file.exists(IN_PATH)) stop("06 panel not found: ", IN_PATH)

# Read every column as text so IDs, ZIP leading zeros, and the blank-vs-0 penalty
# distinction round-trip exactly; only YEAR/MONTH are coerced (for the filter).
panel <- fread(IN_PATH, colClasses = "character", showProgress = FALSE)
yr <- as.integer(panel$YEAR)
mo <- as.integer(panel$MONTH)

keep <- if (FY_CALENDAR) {
  yr == FY
} else {
  (yr == FY - 1L & mo >= 10L) | (yr == FY & mo <= 9L)
}

fy <- panel[keep]
fwrite(fy, OUT_PATH)

# ---- Run log -----------------------------------------------------------------
ym  <- sprintf("%s-%02d", fy$YEAR, as.integer(fy$MONTH))
span <- if (FY_CALENDAR) {
  sprintf("calendar %d (Jan-Dec)", FY)
} else {
  sprintf("federal FY%d (Oct %d - Sep %d)", FY, FY - 1L, FY)
}
message("Restricted 06 panel to ", span)
message("  rows in    : ", format(nrow(panel), big.mark = ","))
message("  rows out   : ", format(nrow(fy),    big.mark = ","))
message("  months     : ", min(ym), " .. ", max(ym),
        "  (", uniqueN(ym), " distinct)")
message("  facilities : ", format(uniqueN(fy$FACILITY_UIN), big.mark = ","),
        " of ", format(uniqueN(panel$FACILITY_UIN), big.mark = ","))
message("  written    : ", OUT_PATH)
