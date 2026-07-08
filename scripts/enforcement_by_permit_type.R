# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# enforcement_by_permit_type.R
# ------------------------------------------------------------------------------
# Breakdown of FORMAL vs. INFORMAL enforcement actions by
#   - permit type    : Individual (NPD) vs. General (GPC) vs. Other
#   - facility status : Major (M) vs. Minor (N)
#
# Each enforcement row = one action record, keyed by NPDES_ID. We attach the
# permit's type and major/minor status from ICIS_PERMITS, then tabulate.
#
# LABELED ASSUMPTIONS:
#   1. Permit attributes are a SNAPSHOT: one type / major-minor value per
#      NPDES_ID (permits collapsed across versions; first value kept).
#   2. Counts are ACTION RECORDS (rows), not distinct facilities.
#   3. Actions whose NPDES_ID is not in ICIS_PERMITS are reported as "Unmatched"
#      rather than dropped (report all).
#   4. No year filter: all actions in the enforcement files are counted.
#
# Output: output/enforcement_by_permit_type.csv
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(dplyr)
  library(tidyr)
})

RAW_DIR  <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
OUT_PATH <- file.path(CWA_ROOT, "output/enforcement_by_permit_type.csv")

read_cols <- function(file, cols) {
  as_tibble(fread(file.path(RAW_DIR, file), select = cols,
                  colClasses = "character", showProgress = FALSE))
}

# ---- 1. Permit attributes: one row per NPDES_ID ------------------------------
permits <- read_cols("ICIS_PERMITS.csv",
                    c("EXTERNAL_PERMIT_NMBR", "PERMIT_TYPE_CODE", "MAJOR_MINOR_STATUS_FLAG")) %>%
  transmute(NPDES_ID = trimws(EXTERNAL_PERMIT_NMBR),
            PERMIT_TYPE_CODE, MAJOR_MINOR_STATUS_FLAG) %>%
  filter(NPDES_ID != "") %>%
  distinct(NPDES_ID, .keep_all = TRUE)   # keep first value per permit number

# ---- 2. Enforcement actions (formal + informal) ------------------------------
formal   <- read_cols("NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv", "NPDES_ID") %>%
  transmute(NPDES_ID = trimws(NPDES_ID), kind = "Formal")
informal <- read_cols("NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv", "NPDES_ID") %>%
  transmute(NPDES_ID = trimws(NPDES_ID), kind = "Informal")

actions <- bind_rows(formal, informal) %>%
  left_join(permits, by = "NPDES_ID") %>%
  mutate(
    permit_type = case_when(
      PERMIT_TYPE_CODE == "NPD" ~ "Individual",
      PERMIT_TYPE_CODE == "GPC" ~ "General",
      is.na(PERMIT_TYPE_CODE)   ~ "Unmatched",
      TRUE                      ~ "Other"),
    facility_status = case_when(
      MAJOR_MINOR_STATUS_FLAG == "M" ~ "Major",
      MAJOR_MINOR_STATUS_FLAG == "N" ~ "Minor",
      TRUE                           ~ "Unknown"))

# ---- 3. Cross-tabulate: formal vs informal by type x status ------------------
breakdown <- actions %>%
  count(permit_type, facility_status, kind) %>%
  pivot_wider(names_from = kind, values_from = n, values_fill = 0) %>%
  mutate(Total        = Formal + Informal,
         pct_informal = round(100 * Informal / Total, 1)) %>%
  arrange(desc(Total))

# ---- 4. Report + write -------------------------------------------------------
cat("Enforcement action records by permit type x facility status:\n\n")
print(as.data.frame(breakdown), row.names = FALSE)

cat("\nTotals by permit type:\n")
actions %>% count(permit_type, kind) %>%
  pivot_wider(names_from = kind, values_from = n, values_fill = 0) %>%
  mutate(Total = Formal + Informal, pct_informal = round(100 * Informal / Total, 1)) %>%
  arrange(desc(Total)) %>% as.data.frame() %>% print(row.names = FALSE)

write.csv(breakdown, OUT_PATH, row.names = FALSE)
cat("\nWritten to:", OUT_PATH, "\n")
