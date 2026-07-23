# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# formal_actions_same_fine_date.R
# ------------------------------------------------------------------------------
# From the formal enforcement actions file, keep only records that fall into a
# GROUP of >=2 observations sharing BOTH the same fine amount AND the same date,
# where the fine is greater than 1000 (1000 not included).
#
#   Fine column : FED_PENALTY_ASSESSED_AMT   (change FINE_COL to use another)
#   Date column : SETTLEMENT_ENTERED_DATE    (change DATE_COL to use another)
#
# Output: output/formal_actions_same_fine_date.csv
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

INFILE  <- file.path(CWA_ROOT, "data/raw/npdes_downloads/NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv")
OUTFILE <- file.path(CWA_ROOT, "output/formal_actions_same_fine_date.csv")
FINE_COL <- "FED_PENALTY_ASSESSED_AMT"
DATE_COL <- "SETTLEMENT_ENTERED_DATE"

# 1. Read the file
fe <- read.csv(INFILE, stringsAsFactors = FALSE)

# 2. Coerce the fine to a number and pull the date into a plain column
#    (as.character first so it works whether read.csv gave us text or numbers)
fe$fine_amount <- suppressWarnings(as.numeric(as.character(fe[[FINE_COL]])))
fe$fine_date   <- fe[[DATE_COL]]

# 3. Keep fines > 1000 with a real date, then keep only groups of 2+ that
#    share the same fine AND the same date
groups <- fe %>%
  filter(!is.na(fine_amount), fine_amount > 1000,
         !is.na(fine_date), fine_date != "") %>%
  group_by(fine_amount, fine_date) %>%
  filter(n() > 1) %>%                 # must be a group, not a singleton
  mutate(n_in_group = n()) %>%
  ungroup() %>%
  arrange(desc(fine_amount), fine_date)

# 4. Write the grouped records to their own CSV
write.csv(groups, OUTFILE, row.names = FALSE)

cat("Matching records:", nrow(groups), "\n")
cat("Distinct fine+date groups:", nrow(distinct(groups, fine_amount, fine_date)), "\n")
cat("Written to:", OUTFILE, "\n")
