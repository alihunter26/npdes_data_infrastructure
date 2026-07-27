# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# dup_enforcement_pairs.R
# ------------------------------------------------------------------------------
# Diagnostic: why do (NPDES_ID, ENF_IDENTIFIER) pairs repeat in
# NPDES_FORMAL_ENFORCEMENT_ACTIONS? A single enforcement case (one
# NPDES_ID + ENF_IDENTIFIER) should usually appear once, so repeats are worth
# understanding before treating this file as one-row-per-action.
#
# Approach: find every (NPDES_ID, ENF_IDENTIFIER) pair that appears on more
# than one row, then check WHICH columns actually differ across those
# repeated rows. A column that never varies within a duplicate group can't be
# what's causing the repeat; a column that DOES vary is a candidate explanation
# (e.g., multiple statutes cited for the same case, one row per statute).
#
# Inputs : data/raw/npdes_downloads/NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv
# Output : console only (no file written) -- this is an exploratory read, not
#          a saved extract. See dup_rows_by_enf_type.R (same folder) for the
#          version that writes a CSV once the explanation is confirmed.
# Read-only on raw data.
# ==============================================================================

data_dir <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
f <- file.path(data_dir, "NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv")

x <- read.csv(f, colClasses = "character")  # keep IDs/codes as-is, no coercion

cat("Total rows:", nrow(x), "\n")

# ------------------------------------------------------------------------------
# STEP 1: Flag every row whose (NPDES_ID, ENF_IDENTIFIER) pair is duplicated.
# ------------------------------------------------------------------------------
x$pair <- paste(x$NPDES_ID, x$ENF_IDENTIFIER, sep = " | ")
dup_keys <- names(which(table(x$pair) > 1))   # pair-keys occurring more than once
cat("Distinct duplicated (NPDES_ID, ENF_IDENTIFIER) pairs:", length(dup_keys), "\n")

dups <- x[x$pair %in% dup_keys, ]
cat("Total rows belonging to a duplicated pair:", nrow(dups), "\n\n")

# ------------------------------------------------------------------------------
# STEP 2: How many rows does each duplicated pair have (2, 3, 4, ...)?
# ------------------------------------------------------------------------------
cat("=== Rows per duplicated pair ===\n")
print(table(table(dups$pair)))

# ------------------------------------------------------------------------------
# STEP 3: Within a duplicated pair, which columns actually VARY across its rows?
# ------------------------------------------------------------------------------
# If a column holds the SAME value for every row in a duplicate group, it
# can't be the reason those rows are separate -- so we only care about columns
# that take on more than one distinct value within at least one group.
cols <- c("ACTIVITY_ID", "ACTIVITY_TYPE_CODE", "ENF_TYPE_CODE", "ENF_TYPE_DESC",
          "AGENCY", "SETTLEMENT_ENTERED_DATE",
          "FED_PENALTY_ASSESSED_AMT", "STATE_LOCAL_PENALTY_AMT")

varies <- sapply(cols, function(col) {
  # For each duplicate group (identified by `pair`), count 1 if this column
  # takes more than one distinct value in that group, else 0; sum across groups.
  sum(tapply(dups[[col]], dups$pair, function(v) length(unique(v)) > 1))
})
cat("\n=== # of the", length(dup_keys),
    "dup groups in which each column varies ===\n")
print(sort(varies, decreasing = TRUE))

# ------------------------------------------------------------------------------
# STEP 4: Sanity check -- are any of these rows FULL duplicates (identical
# on every original column, not just NPDES_ID/ENF_IDENTIFIER)?
# ------------------------------------------------------------------------------
orig_cols <- setdiff(names(x), "pair")   # exclude the helper column we added above
full_dupe_rows <- sum(duplicated(x[orig_cols]))
cat("\nFully-identical duplicate rows (all columns):", full_dupe_rows, "\n")

# ------------------------------------------------------------------------------
# STEP 5: Print a few example duplicate groups in full, for a manual sanity check.
# ------------------------------------------------------------------------------
cat("\n=== 4 example duplicated pairs (full rows) ===\n")
for (k in head(dup_keys, 4)) {
  cat("\n---", k, "---\n")
  print(dups[dups$pair == k, cols], row.names = FALSE)
}
