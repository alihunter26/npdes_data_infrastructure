# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# count_informal_exact_duplicates.R
# ------------------------------------------------------------------------------
# Count EXACT duplicate rows (every single column identical) in
# NPDES_INFORMAL_ENFORCEMENT_ACTIONS, and write out every row that belongs to
# a duplicate set so they can be reviewed side by side.
#
#   "Exact duplicate" here means the base R function duplicated() flags the
#   2nd, 3rd, ... copy of a row that is byte-for-byte identical to an earlier
#   row (every column, not just an ID). So for the whole file:
#     total rows        = distinct rows + redundant copies
#     redundant copies  = sum(duplicated(x))   <- the "exact duplicate" count
#
# LABELED ASSUMPTION: the duplicate-set KEY (see STEP 2 below) is built by
#   pasting every column together with NO separator between them. This is fast
#   and fine in practice for this file, but is not perfectly collision-proof in
#   principle -- e.g. columns "AB" + "C" would paste to the same string as "A"
#   + "BC". We rely on this being vanishingly unlikely across this file's real
#   column values, rather than guaranteeing it structurally.
#
# Inputs : data/raw/npdes_downloads/NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv
# Output : output/tables/informal_exact_duplicates_<timestamp>.csv
# Read-only on raw data; deterministic except for the output filename's timestamp.
# ==============================================================================

data_dir <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
out_dir  <- file.path(CWA_ROOT, "output/tables")
f <- file.path(data_dir, "NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv")

# Read every column as plain text (character) -- no numeric/date coercion --
# so two rows compare as duplicates only if their raw text matches exactly.
x <- read.csv(f, colClasses = "character")

# ------------------------------------------------------------------------------
# STEP 1: Headline counts -- how many rows are exact duplicates overall?
# ------------------------------------------------------------------------------
total       <- nrow(x)
dup_copies  <- sum(duplicated(x))   # redundant exact copies (all columns equal)
unique_rows <- total - dup_copies   # equivalent to nrow(unique(x)), computed cheaply

cat("File:", basename(f), "\n")
cat("Total rows:                 ", format(total,       big.mark = ","), "\n")
cat("Exact duplicate rows:       ", format(dup_copies,  big.mark = ","),
    sprintf("(%.1f%% of file)\n", 100 * dup_copies / total))
cat("Distinct (unique) rows:     ", format(unique_rows, big.mark = ","), "\n")

# ------------------------------------------------------------------------------
# STEP 2: Build a full-row key so we can find and group the duplicate SETS
# (not just count them), for a human-reviewable output file.
# ------------------------------------------------------------------------------
# Paste every column together into one string per row (see LABELED ASSUMPTION
# above on the collision caveat); two rows land on the same key iff every
# column is identical.
key      <- do.call(paste, c(x, sep = ""))
key_freq <- table(key)                          # how many rows share each key
dup_keys <- names(key_freq[key_freq > 1])        # keys that occur more than once

# Keep only the rows whose key is one of those duplicated keys.
dups <- x[key %in% dup_keys, , drop = FALSE]
dup_key <- key[key %in% dup_keys]

# ------------------------------------------------------------------------------
# STEP 3: Order and label for easy human review -- identical rows sit next to
# each other, each tagged with which duplicate group it's in and its copy number.
# ------------------------------------------------------------------------------
ord  <- order(dup_key)
dups <- dups[ord, , drop = FALSE]
dup_key <- dup_key[ord]

out <- cbind(
  dup_group  = match(dup_key, unique(dup_key)),              # 1..N, same value => same group
  copy_no    = ave(seq_along(dup_key), dup_key, FUN = seq_along),  # 1st copy, 2nd copy, ...
  group_size = as.integer(key_freq[dup_key]),                # how many rows are in this group
  dups
)

# ------------------------------------------------------------------------------
# STEP 4: Write the full duplicate-row extract (timestamped, so every run is
# traceable) and print a short summary.
# ------------------------------------------------------------------------------
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
stamp <- format(Sys.time(), "%Y-%m-%d_%H%M")
out_f <- file.path(out_dir, paste0("informal_exact_duplicates_", stamp, ".csv"))
write.csv(out, out_f, row.names = FALSE)

cat("\nRows belonging to a duplicate set:", format(nrow(out), big.mark = ","), "\n")
cat("Duplicate sets (groups):          ", format(length(dup_keys), big.mark = ","), "\n")
cat("Written to:", out_f, "\n")
