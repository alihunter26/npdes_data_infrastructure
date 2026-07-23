# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# Count exact duplicate rows (every column identical) in
# NPDES_INFORMAL_ENFORCEMENT_ACTIONS. Read-only.
#
# duplicated() flags the 2nd, 3rd, ... copy of each identical row, so:
#   total rows        = unique rows + redundant copies
#   redundant copies  = sum(duplicated(x))   <- the "exact duplicate" count

data_dir <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
out_dir  <- file.path(CWA_ROOT, "output/tables")
f <- file.path(data_dir, "NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv")

x <- read.csv(f, colClasses = "character")  # no coercion, so every column compares as-is

total       <- nrow(x)
dup_copies  <- sum(duplicated(x))            # redundant exact copies (all columns equal)
unique_rows <- total - dup_copies            # == nrow(unique(x))

cat("File:", basename(f), "\n")
cat("Total rows:                 ", format(total,       big.mark = ","), "\n")
cat("Exact duplicate rows:       ", format(dup_copies,  big.mark = ","),
    sprintf("(%.1f%% of file)\n", 100 * dup_copies / total))
cat("Distinct (unique) rows:     ", format(unique_rows, big.mark = ","), "\n")

# --- Output every row that belongs to a duplicate set, copies sat side by side ---
# Build a key from all columns; keep rows whose key occurs more than once.
key      <- do.call(paste, c(x, sep = ""))   # unit-separator avoids collisions
key_freq <- table(key)
dup_keys <- names(key_freq[key_freq > 1])

dups <- x[key %in% dup_keys, , drop = FALSE]
dup_key <- key[key %in% dup_keys]

# Order so identical rows are contiguous; add a group id + copy number for readability.
ord  <- order(dup_key)
dups <- dups[ord, , drop = FALSE]
dup_key <- dup_key[ord]

out <- cbind(
  dup_group = match(dup_key, unique(dup_key)),               # 1..N, same value => same group
  copy_no   = ave(seq_along(dup_key), dup_key, FUN = seq_along),
  group_size = as.integer(key_freq[dup_key]),
  dups
)

if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
stamp <- format(Sys.time(), "%Y-%m-%d_%H%M")
out_f <- file.path(out_dir, paste0("informal_exact_duplicates_", stamp, ".csv"))
write.csv(out, out_f, row.names = FALSE)

cat("\nRows belonging to a duplicate set:", format(nrow(out), big.mark = ","), "\n")
cat("Duplicate sets (groups):          ", format(length(dup_keys), big.mark = ","), "\n")
cat("Written to:", out_f, "\n")
