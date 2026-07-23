# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# check_naics_sic_mapping.R
# ------------------------------------------------------------------------------
# Diagnose NAICS <-> SIC coding issues in the NPDES industry-code files:
#   (A) facilities that carry MULTIPLE NAICS and/or MULTIPLE SIC codes, and
#   (B) the observed NAICS <-> SIC mapping, flagging codes that map to more than
#       one code on the other side (the many-to-many ambiguity).
#
# There is NO official crosswalk in these files: the mapping is DERIVED from
# co-occurrence at facilities (each facility's PRIMARY NAICS paired with its
# PRIMARY SIC). NAICS and SIC are independent classification systems, so their
# descriptions are EXPECTED to differ; the diagnostic is whether a single code
# on one side corresponds to several on the other.
#
# LABELED ASSUMPTIONS:
#   1. The mapping (Part B) is built from PRIMARY codes (PRIMARY_INDICATOR_FLAG
#      == "Y"; first row if several or none) -> one NAICS and one SIC per
#      facility. So a many-to-one reflects DIFFERENT facilities, not a within-
#      facility cross-product of codes.
#   2. Facility multiplicity (Part A) uses ALL codes, not just primary.
#   3. All NPDES facilities are included (not restricted to any panel). Change
#      the reads to a facility subset if you only want your sample.
#
# Inputs : data/raw/npdes_downloads/NPDES_NAICS.csv, NPDES_SICS.csv
# Outputs (in output/):
#   facilities_multiple_codes.csv  - facilities with >1 NAICS or >1 SIC
#   naics_sic_crosswalk.csv        - every observed primary NAICS<->SIC pair
#   naics_with_multiple_sic.csv    - NAICS codes mapping to >1 SIC
#   sic_with_multiple_naics.csv    - SIC codes mapping to >1 NAICS
# Deterministic; reads raw only, writes to output/.
# ==============================================================================

suppressPackageStartupMessages(library(data.table))

RAW <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
OUT <- file.path(CWA_ROOT, "output")

naics <- fread(file.path(RAW, "NPDES_NAICS.csv"), colClasses = "character")
sic   <- fread(file.path(RAW, "NPDES_SICS.csv"),  colClasses = "character")
naics[, NPDES_ID := trimws(NPDES_ID)]
sic[,   NPDES_ID := trimws(NPDES_ID)]

# ---- A. Facilities carrying multiple NAICS and/or SIC codes -------------------
naics_n <- naics[, .(n_naics = uniqueN(NAICS_CODE)), by = NPDES_ID]
sic_n   <- sic[,   .(n_sic   = uniqueN(SIC_CODE)),   by = NPDES_ID]
mult <- merge(naics_n, sic_n, by = "NPDES_ID", all = TRUE)
mult[is.na(n_naics), n_naics := 0L]
mult[is.na(n_sic),   n_sic   := 0L]
mult_flagged <- mult[n_naics > 1 | n_sic > 1][order(-n_naics, -n_sic)]
fwrite(mult_flagged, file.path(OUT, "facilities_multiple_codes.csv"))

# ---- B. NAICS <-> SIC mapping from PRIMARY codes ------------------------------
# One primary code per facility (PRIMARY_INDICATOR_FLAG "Y" first, else first row)
pick_primary <- function(dt, code_col, desc_col) {
  d <- dt[order(NPDES_ID, PRIMARY_INDICATOR_FLAG != "Y")]
  d <- unique(d, by = "NPDES_ID")
  d[, .(NPDES_ID, CODE = get(code_col), DESC = get(desc_col))]
}
np <- pick_primary(naics, "NAICS_CODE", "NAICS_DESC")
sp <- pick_primary(sic,   "SIC_CODE",   "SIC_DESC")
setnames(np, c("NPDES_ID", "NAICS_CODE", "NAICS_DESC"))
setnames(sp, c("NPDES_ID", "SIC_CODE",   "SIC_DESC"))

xwalk <- merge(np, sp, by = "NPDES_ID")   # facilities with BOTH a primary NAICS and SIC
pairs <- xwalk[, .(n_facilities = .N),
               by = .(NAICS_CODE, NAICS_DESC, SIC_CODE, SIC_DESC)][
               order(NAICS_CODE, -n_facilities)]
fwrite(pairs, file.path(OUT, "naics_sic_crosswalk.csv"))

# NAICS codes that map to more than one SIC (and vice versa)
naics_multi <- pairs[, .(n_distinct_sic = uniqueN(SIC_CODE),
                         sic_codes = paste(sort(unique(SIC_CODE)), collapse = "; ")),
                     by = .(NAICS_CODE, NAICS_DESC)][n_distinct_sic > 1][order(-n_distinct_sic)]
sic_multi   <- pairs[, .(n_distinct_naics = uniqueN(NAICS_CODE),
                         naics_codes = paste(sort(unique(NAICS_CODE)), collapse = "; ")),
                     by = .(SIC_CODE, SIC_DESC)][n_distinct_naics > 1][order(-n_distinct_naics)]
fwrite(naics_multi, file.path(OUT, "naics_with_multiple_sic.csv"))
fwrite(sic_multi,   file.path(OUT, "sic_with_multiple_naics.csv"))

# ---- Report ------------------------------------------------------------------
cat("=== NAICS / SIC mapping diagnostic ===\n")
cat("Facilities with a NAICS:", uniqueN(naics$NPDES_ID),
    "| with a SIC:", uniqueN(sic$NPDES_ID),
    "| with both (primary):", nrow(xwalk), "\n\n")

cat("(A) Facilities carrying MULTIPLE codes:\n")
cat("    >1 NAICS:", mult[n_naics > 1, .N], "|  >1 SIC:", mult[n_sic > 1, .N],
    "|  either:", nrow(mult_flagged), "\n\n")

cat("(B) NAICS<->SIC mapping (from primary codes):\n")
cat("    distinct NAICS:", uniqueN(pairs$NAICS_CODE),
    "| distinct SIC:", uniqueN(pairs$SIC_CODE),
    "| distinct pairs:", nrow(pairs), "\n")
cat("    NAICS mapping to >1 SIC :", nrow(naics_multi), "\n")
cat("    SIC mapping to >1 NAICS :", nrow(sic_multi), "\n\n")

cat("Top NAICS codes that map to multiple SIC codes:\n")
print(head(naics_multi, 12))
cat("\nTop SIC codes that map to multiple NAICS codes:\n")
print(head(sic_multi, 12))
cat("\nWritten 4 CSVs to:", OUT, "\n")
