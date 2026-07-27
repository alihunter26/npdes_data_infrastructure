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

# ---- STEP 1: Read the raw file (as-is; no factor conversion) -----------------
fe <- read.csv(INFILE, stringsAsFactors = FALSE)

# ---- STEP 2: Get the fine into a comparable numeric column -------------------
# as.character() first so this works whether read.csv gave us the fine column
# as text or as numbers; suppressWarnings() because any genuinely non-numeric
# value (e.g. blank) becomes NA here rather than raising a warning per row.
fe$fine_amount <- suppressWarnings(as.numeric(as.character(fe[[FINE_COL]])))
fe$fine_date   <- fe[[DATE_COL]]

# ---- STEP 3: Keep only the rows we care about, then group ---------------------
# We only want fines that are (a) a real number greater than $1,000 (small
# fines coinciding by chance are not interesting) and (b) have a real,
# non-blank date. Among those, keep a row ONLY if at least one OTHER row
# shares its exact fine amount AND exact date -- a lone fine/date combo isn't
# a "coincidence" worth flagging.
groups <- fe %>%
  filter(!is.na(fine_amount), fine_amount > 1000,
         !is.na(fine_date), fine_date != "") %>%
  group_by(fine_amount, fine_date) %>%
  filter(n() > 1) %>%                 # must be a group of >=2, not a singleton
  mutate(n_in_group = n()) %>%        # record how many rows share this fine+date
  ungroup() %>%
  arrange(desc(fine_amount), fine_date)

# ---- STEP 4: Write the grouped records to their own CSV for manual review ----
write.csv(groups, OUTFILE, row.names = FALSE)

cat("Matching records:", nrow(groups), "\n")
cat("Distinct fine+date groups:", nrow(distinct(groups, fine_amount, fine_date)), "\n")
cat("Written to:", OUTFILE, "\n")
