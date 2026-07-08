# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# Keep only MAJOR facilities that are under an INDIVIDUAL permit.
#   - "major"      = MAJOR_MINOR_STATUS == "M"   (already in the panel)
#   - "individual" = PERMIT_TYPE_CODE  == "NPD"  (from the permits dataset)
# In ICIS_PERMITS, "NPD" = individual permit; "GPC" = general permit covered.

# 1. Read the panel
panel_path <- file.path(CWA_ROOT, "data/processed/npdes_enforcement_panel_2005_2025.csv")
panel      <- read.csv(panel_path, stringsAsFactors = FALSE)

# 2. Read the permits dataset and find which facilities have an individual permit
permits_path <- file.path(CWA_ROOT, "data/raw/npdes_downloads/ICIS_PERMITS.csv")
permits      <- read.csv(permits_path, stringsAsFactors = FALSE)

# The permit number in ICIS_PERMITS is the NPDES_ID used in the panel
permits$NPDES_ID <- trimws(permits$EXTERNAL_PERMIT_NMBR)

# List of facilities that hold an individual ("NPD") permit
individual_ids <- unique(permits$NPDES_ID[permits$PERMIT_TYPE_CODE == "NPD"])

# 3. Keep panel rows that are BOTH major AND individual
panel$NPDES_ID <- trimws(panel$NPDES_ID)
keep   <- panel$MAJOR_MINOR_STATUS == "M" &
          !is.na(panel$MAJOR_MINOR_STATUS) &
          panel$NPDES_ID %in% individual_ids
majors <- panel[keep, ]

# 4. Report what changed
cat("Rows before:", nrow(panel), "\n")
cat("Rows after (major + individual):", nrow(majors), "\n")
cat("Distinct facilities kept:", length(unique(majors$NPDES_ID)), "\n")

# 5. Write the filtered panel
out_path <- file.path(CWA_ROOT, "data/processed/npdes_enforcement_panel_major_individual_2005_2025.csv")
write.csv(majors, out_path, row.names = FALSE)
cat("Written to:", out_path, "\n")
