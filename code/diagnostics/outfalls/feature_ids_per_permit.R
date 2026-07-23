# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, PROC_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# feature_ids_per_permit.R
# ------------------------------------------------------------------------------
# How many distinct PERM_FEATURE_ID does each EXTERNAL_PERMIT_NMBR have, and what
# is the breakdown (how many permits have 1 feature, how many 2, etc.)?
#
# Default input: the filtered eff-gross monthly-average FY2025 file, so counts
# are distinct EXO outfalls that reported TSS (00530) monthly-average. Point
# IN_PATH at another DMR-format CSV to change the scope (the full FY2025 CSV
# needs the out-of-core / DuckDB path, not fread).
# ==============================================================================

suppressPackageStartupMessages(library(data.table))

## ---- Config (edit here) ----
IN_PATH <- file.path(PROC_DIR, "dmr_fy2025_exo_00530_effgross_monthlyavg.csv")

# ---- 1. Read only the two ID columns (as text, to preserve IDs exactly) ------
d <- fread(IN_PATH, select = c("EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_ID"),
           colClasses = "character", showProgress = FALSE)

# ---- 2. Distinct feature IDs per permit --------------------------------------
per_permit <- d[, .(n_features = uniqueN(PERM_FEATURE_ID)), by = EXTERNAL_PERMIT_NMBR]

# ---- 3. Breakdown: how many permits have 1, 2, 3, ... features ---------------
breakdown <- per_permit[, .(n_permits = .N), by = n_features][order(n_features)]
breakdown[, pct_permits := round(100 * n_permits / sum(n_permits), 1)]

# ---- 4. Report ---------------------------------------------------------------
cat("Input:", IN_PATH, "\n")
cat("Distinct permits:", nrow(per_permit),
    " | distinct feature IDs:", uniqueN(d$PERM_FEATURE_ID), "\n")
cat("Features per permit: min", min(per_permit$n_features),
    " median", median(per_permit$n_features),
    " mean", round(mean(per_permit$n_features), 2),
    " max", max(per_permit$n_features), "\n\n")
cat("Breakdown (n_features = distinct PERM_FEATURE_ID per permit):\n")
print(breakdown, row.names = FALSE)
