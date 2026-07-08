# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# Diagnostic: why do (NPDES_ID, ENF_IDENTIFIER) pairs repeat in
# NPDES_FORMAL_ENFORCEMENT_ACTIONS? Read-only on raw data.

data_dir <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
f <- file.path(data_dir, "NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv")

x <- read.csv(f, colClasses = "character")  # keep IDs/codes as-is, no coercion

cat("Total rows:", nrow(x), "\n")

# Flag duplicated pair keys
x$pair <- paste(x$NPDES_ID, x$ENF_IDENTIFIER, sep = " | ")
dup_keys <- names(which(table(x$pair) > 1))
cat("Distinct duplicated (NPDES_ID, ENF_IDENTIFIER) pairs:", length(dup_keys), "\n")

dups <- x[x$pair %in% dup_keys, ]
cat("Total rows belonging to a duplicated pair:", nrow(dups), "\n\n")

# How many rows per duplicated pair (2, 3, ...)?
cat("=== Rows per duplicated pair ===\n")
print(table(table(dups$pair)))

# Within a duplicated pair, which columns actually VARY?
# (If a column is constant within every dup group, it can't be what distinguishes them.)
cols <- c("ACTIVITY_ID", "ACTIVITY_TYPE_CODE", "ENF_TYPE_CODE", "ENF_TYPE_DESC",
          "AGENCY", "SETTLEMENT_ENTERED_DATE",
          "FED_PENALTY_ASSESSED_AMT", "STATE_LOCAL_PENALTY_AMT")

varies <- sapply(cols, function(col) {
  # number of dup groups in which this column takes >1 distinct value
  sum(tapply(dups[[col]], dups$pair, function(v) length(unique(v)) > 1))
})
cat("\n=== # of the", length(dup_keys),
    "dup groups in which each column varies ===\n")
print(sort(varies, decreasing = TRUE))

# Are any rows TRUE full duplicates (identical on every original column)?
orig_cols <- setdiff(names(x), "pair")
full_dupe_rows <- sum(duplicated(x[orig_cols]))
cat("\nFully-identical duplicate rows (all columns):", full_dupe_rows, "\n")

# Show a few example dup groups in full
cat("\n=== 4 example duplicated pairs (full rows) ===\n")
for (k in head(dup_keys, 4)) {
  cat("\n---", k, "---\n")
  print(dups[dups$pair == k, cols], row.names = FALSE)
}
