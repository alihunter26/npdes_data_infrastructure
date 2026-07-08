# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# facility_uin_multiple_npdes.R
# ------------------------------------------------------------------------------
# Extract every ICIS facility row whose FACILITY_UIN is shared by more than one
# distinct NPDES_ID. In the ICIS data model NPDES_ID identifies a *permit* and
# FACILITY_UIN (an FRS Unique Identifier Number) identifies a *physical site*,
# so a UIN tied to multiple NPDES_IDs is one site holding several permits
# (commonly general-permit rollups, or one site with multiple discharge permits).
#
# Source: EPA ECHO bulk "ICIS-NPDES" download
#   https://echo.epa.gov/files/echodownloads/npdes_downloads.zip
#
# Output: data/processed/facility_uin_multiple_npdes.csv
#
# ASSUMPTION (labeled): a blank/whitespace FACILITY_UIN is treated as missing,
# not as a distinct facility value, so empty UINs are never grouped together or
# counted toward the "more than one NPDES_ID" test.
# ==============================================================================

# ---- 0. Setup ----------------------------------------------------------------
suppressPackageStartupMessages({
  library(data.table)   # fast read of the large (~1.2M row) ICIS_FACILITIES file
  library(dplyr)
})

## ---- Config (edit here) ----
DATA_DIR <- file.path(CWA_ROOT, "data")
RAW_DIR  <- file.path(DATA_DIR, "raw", "npdes_downloads")
PROC_DIR <- file.path(DATA_DIR, "processed")
IN_PATH  <- file.path(RAW_DIR,  "ICIS_FACILITIES.csv")
OUT_PATH <- file.path(PROC_DIR, "facility_uin_multiple_npdes.csv")

dir.create(PROC_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- 1. Read raw facilities (read all columns as character to preserve IDs) ---
facilities <- fread(IN_PATH, colClasses = "character", showProgress = FALSE)
cat("Rows read:", nrow(facilities), "\n")

# Treat blank/whitespace FACILITY_UIN as missing (see labeled ASSUMPTION above)
facilities[trimws(FACILITY_UIN) == "", FACILITY_UIN := NA_character_]

# ---- 2. Flag FACILITY_UINs tied to more than one distinct NPDES_ID -----------
flagged <- facilities %>%
  filter(!is.na(FACILITY_UIN)) %>%
  group_by(FACILITY_UIN) %>%
  summarise(n_npdes = n_distinct(NPDES_ID), .groups = "drop") %>%
  filter(n_npdes > 1)

# ---- 3. Pull all rows for those FACILITY_UINs (grouped by NPDES_ID) ----------
result <- facilities %>%
  filter(FACILITY_UIN %in% flagged$FACILITY_UIN) %>%
  arrange(NPDES_ID, FACILITY_UIN)

# ---- 4. Report what was found ------------------------------------------------
cat("FACILITY_UINs mapping to >1 NPDES_ID:", nrow(flagged), "\n")
cat("Rows extracted:", nrow(result), "\n")
cat("Max NPDES_IDs under a single FACILITY_UIN:",
    if (nrow(flagged)) max(flagged$n_npdes) else 0L, "\n")

# ---- 5. Write derived output -------------------------------------------------
write.csv(result, OUT_PATH, row.names = FALSE, na = "")
cat("Written to:", OUT_PATH, "\n")
