# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# summarize_violation_types.R
# ------------------------------------------------------------------------------
# Summarize the share of each violation TYPE in the facility-by-month violations
# panel produced by 04_add_violations.R. Answers: of all violations tallied in
# the panel, what percent are permit-schedule vs compliance-schedule vs single-
# event vs (TSS gross monthly-average) effluent?
#
#   Input : data/processed/04_facility_month_panel_major_individual_violations_2005_2025.csv
#   Output: console table + a timestamped CSV in output/tables/.
#
# ------------------------------------------------------------------------------
# WHAT COUNTS AS A "TYPE" (read before using -- avoids double counting):
#
#   The panel has four MUTUALLY-EXCLUSIVE top-level violation-count columns:
#       N_PS_VIOLATIONS       permit-schedule
#       N_CS_VIOLATIONS       compliance-schedule
#       N_SE_VIOLATIONS       single-event
#       N_TSS_EFF_VIOLATIONS  effluent (restricted to Total Suspended Solids,
#                             gross-effluent, monthly-average -- see 04's notes)
#   These four partition the panel's violations, so the denominator ("all
#   violations") is their sum, and each type's percent is its share of that sum.
#
#   The columns N_TSS_EFF_D90 / _D80 / _E90 are a SUB-BREAKDOWN of the effluent
#   total by VIOLATION_CODE (D-codes = DMR non-receipt; E90 = numeric-limit
#   exceedance). They are NOT separate types and are NOT added to the total --
#   doing so would double-count effluent. They are reported separately below as
#   shares OF the effluent subset.
#
#   Percentages are pooled over the whole panel (every facility-month, 2005-2025);
#   each violation is an event, counted once in the month it occurred.
# ==============================================================================

suppressPackageStartupMessages(library(data.table))

IN_PATH <- file.path(CWA_ROOT, "data/processed/04_facility_month_panel_major_individual_violations_2005_2025.csv")
OUT_DIR <- file.path(CWA_ROOT, "output/tables")

# The four top-level (mutually exclusive) types, with human labels.
TOP_TYPES <- c(N_PS_VIOLATIONS      = "Permit-schedule",
               N_CS_VIOLATIONS      = "Compliance-schedule",
               N_SE_VIOLATIONS      = "Single-event",
               N_TSS_EFF_VIOLATIONS = "Effluent (TSS gross monthly-avg)")
# The effluent sub-breakdown (a partition of N_TSS_EFF_VIOLATIONS).
EFF_SUB   <- c(N_TSS_EFF_D90 = "D90 (DMR overdue, w/ limit)",
               N_TSS_EFF_D80 = "D80 (DMR overdue, monitor-only)",
               N_TSS_EFF_E90 = "E90 (effluent limit exceedance)")

# ---- 1. Read just the violation-count columns --------------------------------
cols <- c(names(TOP_TYPES), names(EFF_SUB))
d <- fread(IN_PATH, select = cols, showProgress = FALSE)

# ---- 2. Total violations by top-level type (pooled over the panel) -----------
totals <- sapply(names(TOP_TYPES), function(c) sum(d[[c]]))
grand  <- sum(totals)                                   # denominator = the 4 types

type_tbl <- data.table(
  violation_type = TOP_TYPES,
  column         = names(TOP_TYPES),
  n_violations   = as.integer(totals),
  pct_of_all     = round(100 * totals / grand, 1)
)
setorder(type_tbl, -n_violations)

# ---- 3. Effluent sub-breakdown (share OF the effluent subset) ----------------
eff_totals <- sapply(names(EFF_SUB), function(c) sum(d[[c]]))
eff_total  <- totals[["N_TSS_EFF_VIOLATIONS"]]
eff_tbl <- data.table(
  effluent_code = EFF_SUB,
  column        = names(EFF_SUB),
  n_violations  = as.integer(eff_totals),
  pct_of_eff    = round(100 * eff_totals / eff_total, 1),
  pct_of_all    = round(100 * eff_totals / grand, 1)
)
setorder(eff_tbl, -n_violations)

# ---- 4. Console report -------------------------------------------------------
cat("=== Violation-type composition (pooled over the whole panel, 2005-2025) ===\n")
cat("Total violations (PS + CS + SE + TSS effluent):", grand, "\n\n")
print(type_tbl)
cat("\n--- Effluent total broken out by code (a subset of the effluent row above,\n",
    "    NOT added to the total) ---\n", sep = "")
print(eff_tbl)
# Sanity: the three effluent codes should sum to the effluent total (or be <= it).
cat("\nEffluent code check: D90+D80+E90 =", sum(eff_totals),
    " vs N_TSS_EFF_VIOLATIONS =", eff_total,
    if (sum(eff_totals) == eff_total) "  (exact)" else "  (other codes present)", "\n")

# ---- 5. Write timestamped CSV ------------------------------------------------
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)
stamp <- format(Sys.time(), "%Y-%m-%d_%H%M")
out_f <- file.path(OUT_DIR, paste0("violation_type_summary_", stamp, ".csv"))
fwrite(type_tbl, out_f)
cat("\nWritten to:", out_f, "\n")
