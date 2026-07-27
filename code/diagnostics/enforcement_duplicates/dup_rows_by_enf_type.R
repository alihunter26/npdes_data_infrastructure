# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# dup_rows_by_enf_type.R
# ------------------------------------------------------------------------------
# Follow-up to dup_enforcement_pairs.R (same folder): that script found that
# ENF_TYPE_CODE / ENF_TYPE_DESC are the columns that vary within duplicated
# (NPDES_ID, ENF_IDENTIFIER) pairs. This script confirms and extracts that
# specific pattern: rows in NPDES_FORMAL_ENFORCEMENT_ACTIONS that are
# IDENTICAL on every column EXCEPT ENF_TYPE_CODE and ENF_TYPE_DESC.
#
#   Interpretation: these are single enforcement actions (same case/date/
#   penalty/ACTIVITY_ID) recorded once per statutory authority cited -- i.e.
#   the "multi-statute repeats" -- not truly separate enforcement actions.
#
# Inputs : data/raw/npdes_downloads/NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv
# Output : output/tables/dup_rows_by_enf_type_<timestamp>.csv
# Read-only on raw data; deterministic except for the output filename's timestamp.
# ==============================================================================

data_dir <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
out_dir  <- file.path(CWA_ROOT, "output/tables")
f <- file.path(data_dir, "NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv")

x <- read.csv(f, colClasses = "character")  # no coercion of IDs/codes/amounts

# ------------------------------------------------------------------------------
# STEP 1: Define "the same row" as every column EXCEPT the two enforcement-type
# fields we expect to vary (that's the whole point of this check).
# ------------------------------------------------------------------------------
vary_cols <- c("ENF_TYPE_CODE", "ENF_TYPE_DESC")
key_cols  <- setdiff(names(x), vary_cols)

# Build one grouping key per row from all the "should-be-identical" columns.
x$.key <- do.call(paste, c(x[key_cols], sep = ""))

# ------------------------------------------------------------------------------
# STEP 2: Keep only rows whose key is shared by more than one row -- these are
# the multi-statute repeats we're looking for.
# ------------------------------------------------------------------------------
dup_keys <- names(which(table(x$.key) > 1))
dups <- x[x$.key %in% dup_keys, ]

# Order so duplicate rows sit together in the output, then drop the helper column.
dups <- dups[order(dups$.key), ]
dups$.key <- NULL

# Give each duplicate SET a stable, readable group id (1..N) instead of the
# long pasted key string, and put it first for easy scanning.
dups$dup_group <- match(do.call(paste, c(dups[key_cols], sep = "")),
                        dup_keys)
dups <- dups[, c("dup_group", names(x)[names(x) != ".key"])]

# ------------------------------------------------------------------------------
# STEP 3: Report + preview -- confirm the scale of the pattern before saving.
# ------------------------------------------------------------------------------
cat("Total rows in file:", nrow(x), "\n")
cat("Duplicated sets (identical except ENF_TYPE_CODE/DESC):", length(dup_keys), "\n")
cat("Rows belonging to a duplicated set:", nrow(dups), "\n\n")

# Console preview: NPDES_ID, ENF_IDENTIFIER, ACTIVITY_ID, and the two varying
# columns, so it's easy to eyeball that only the statute-related fields differ.
print(utils::head(
  dups[, c("dup_group", "NPDES_ID", "ENF_IDENTIFIER", "ACTIVITY_ID",
           "ENF_TYPE_CODE", "ENF_TYPE_DESC", "SETTLEMENT_ENTERED_DATE",
           "FED_PENALTY_ASSESSED_AMT")],
  20), row.names = FALSE)

# ------------------------------------------------------------------------------
# STEP 4: Save the full result, timestamped so every run is traceable.
# ------------------------------------------------------------------------------
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
stamp <- format(Sys.time(), "%Y-%m-%d_%H%M")
out_f <- file.path(out_dir, paste0("dup_rows_by_enf_type_", stamp, ".csv"))
write.csv(dups, out_f, row.names = FALSE)
cat("\nFull result written to:", out_f, "\n")
