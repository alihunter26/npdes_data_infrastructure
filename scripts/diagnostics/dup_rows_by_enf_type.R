# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# Show duplicate rows in NPDES_FORMAL_ENFORCEMENT_ACTIONS that are identical on
# every column EXCEPT ENF_TYPE_CODE and ENF_TYPE_DESC.
#
# These are single enforcement actions (same ACTIVITY_ID / case / date / penalty)
# recorded once per statutory authority cited -> the multi-statute repeats.
# Read-only on raw data. Writes a timestamped CSV to output/tables/.

data_dir <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
out_dir  <- file.path(CWA_ROOT, "output/tables")
f <- file.path(data_dir, "NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv")

x <- read.csv(f, colClasses = "character")  # no coercion of IDs/codes/amounts

# Columns that define "the same row" for this purpose: everything except the
# two enforcement-type fields we expect to vary.
vary_cols <- c("ENF_TYPE_CODE", "ENF_TYPE_DESC")
key_cols  <- setdiff(names(x), vary_cols)

# Build a group key from all the "should-be-identical" columns.
x$.key <- do.call(paste, c(x[key_cols], sep = ""))

# Keep only keys that appear on more than one row.
dup_keys <- names(which(table(x$.key) > 1))
dups <- x[x$.key %in% dup_keys, ]

# Order so duplicate rows sit together, then drop the helper column.
dups <- dups[order(dups$.key), ]
dups$.key <- NULL

# Stable group id for readability (1..N over the duplicated sets).
dups$dup_group <- match(do.call(paste, c(dups[key_cols], sep = "")),
                        dup_keys)
dups <- dups[, c("dup_group", names(x)[names(x) != ".key"])]

cat("Total rows in file:", nrow(x), "\n")
cat("Duplicated sets (identical except ENF_TYPE_CODE/DESC):", length(dup_keys), "\n")
cat("Rows belonging to a duplicated set:", nrow(dups), "\n\n")

# Console preview: NPDES_ID, ENF_IDENTIFIER, ACTIVITY_ID, and the two varying cols
print(utils::head(
  dups[, c("dup_group", "NPDES_ID", "ENF_IDENTIFIER", "ACTIVITY_ID",
           "ENF_TYPE_CODE", "ENF_TYPE_DESC", "SETTLEMENT_ENTERED_DATE",
           "FED_PENALTY_ASSESSED_AMT")],
  20), row.names = FALSE)

# Save full result, timestamped (traceable run).
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
stamp <- format(Sys.time(), "%Y-%m-%d_%H%M")
out_f <- file.path(out_dir, paste0("dup_rows_by_enf_type_", stamp, ".csv"))
write.csv(dups, out_f, row.names = FALSE)
cat("\nFull result written to:", out_f, "\n")
