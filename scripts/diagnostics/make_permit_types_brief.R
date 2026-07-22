# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# make_permit_types_brief.R
# ------------------------------------------------------------------------------
# Computes every figure and table cited in permit_types_brief.tex, and writes
# them as \input-able LaTeX fragments. Rerun this after any raw-data refresh;
# do not hand-edit the fragments or the compiled PDF.
#
# Sources:
#   data/raw/npdes_downloads/ICIS_PERMITS.csv    -- permit type, major/minor, version
#   data/raw/npdes_downloads/ICIS_FACILITIES.csv -- FACILITY_UIN <-> NPDES_ID
#   output/enforcement_by_permit_type.csv        -- pre-built by
#     scripts/enforcement_by_permit_type.R (formal/informal counts by permit
#     type x major/minor status). Not recomputed here; if that script is rerun,
#     rerun this one after to pick up the refreshed numbers.
#
# Writes to docs/institutional_briefs/:
#   permit_types_numbers.tex        (\newcommand macros, in-prose figures)
#   tab_permit_type_codes_rows.tex  (PERMIT_TYPE_CODE frequency table rows)
#   tab_enforcement_rows.tex        (enforcement-by-type-x-status table rows)
# ==============================================================================

suppressPackageStartupMessages(library(data.table))

OUT_DIR <- file.path(CWA_ROOT, "docs", "institutional_briefs")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

ci <- function(x) formatC(x, format = "d", big.mark = ",")
p1 <- function(x) formatC(x, format = "f", digits = 1)

# ---- 1. Permit-type codes: distinct permits AND raw version-records ----------
pm <- fread(file.path(RAW_DIR, "ICIS_PERMITS.csv"),
            select = c("EXTERNAL_PERMIT_NMBR", "PERMIT_TYPE_CODE",
                       "MAJOR_MINOR_STATUS_FLAG", "VERSION_NMBR"),
            colClasses = "character", showProgress = FALSE)
pm[, id   := trimws(EXTERNAL_PERMIT_NMBR)]
pm[, ptc  := trimws(PERMIT_TYPE_CODE)]
pm[, flag := trimws(MAJOR_MINOR_STATUS_FLAG)]

n_records_by_type <- pm[, .N, by = ptc][order(-N)]

perm <- pm[, .(ptype = ptc[1], ever_major = any(flag == "M"),
               n_versions = uniqueN(VERSION_NMBR)), by = id]
n_distinct_by_type <- perm[, .N, by = ptype][order(-N)]

n_npd_total   <- perm[ptype == "NPD", .N]
n_gpc_total   <- perm[ptype == "GPC", .N]
n_npd_multiv  <- perm[ptype == "NPD" & n_versions > 1, .N]
n_gpc_multiv  <- perm[ptype == "GPC" & n_versions > 1, .N]

n_ever_major       <- perm[ever_major == TRUE, .N]
n_ever_major_indiv <- perm[ever_major == TRUE & ptype == "NPD", .N]

# ---- 2. FACILITY_UIN sharing: dual-permit facilities + max GPC concentration --
fac <- fread(file.path(RAW_DIR, "ICIS_FACILITIES.csv"),
             select = c("NPDES_ID", "FACILITY_UIN"), colClasses = "character",
             showProgress = FALSE)
fac[, NPDES_ID := trimws(NPDES_ID)][, FACILITY_UIN := trimws(FACILITY_UIN)]
fac <- unique(fac[FACILITY_UIN != ""], by = "NPDES_ID")
fac <- perm[, .(id, ptype)][fac, on = c(id = "NPDES_ID")]

by_uin <- fac[!is.na(ptype), .(has_npd = any(ptype == "NPD"),
                               has_gpc = any(ptype == "GPC")), by = FACILITY_UIN]
n_dual <- by_uin[has_npd & has_gpc, .N]

gpc_per_uin <- fac[ptype == "GPC", .N, by = FACILITY_UIN][order(-N)]
max_gpc_uin   <- gpc_per_uin$FACILITY_UIN[1]
max_gpc_count <- gpc_per_uin$N[1]

# ---- 3. Write the permit-type-code table fragment -----------------------------
# Show BOTH framings side by side: distinct permits, and raw version-records.
setnames(n_distinct_by_type, c("ptype", "n_distinct"))
setnames(n_records_by_type,  c("ptype", "n_records"))
tbl <- merge(n_distinct_by_type, n_records_by_type, by = "ptype", all = TRUE)
setorder(tbl, -n_distinct)

code_rows <- sprintf("%s & %s & %s \\\\", tbl$ptype, ci(tbl$n_distinct), ci(tbl$n_records))
writeLines(c(code_rows, "\\bottomrule"),
           file.path(OUT_DIR, "tab_permit_type_codes_rows.tex"))

# ---- 4. Enforcement-by-type table fragment (reads the existing, unmodified ----
#         output of scripts/enforcement_by_permit_type.R) --------------------
enf_path <- file.path(CWA_ROOT, "output", "enforcement_by_permit_type.csv")
if (!file.exists(enf_path))
  stop("Missing ", enf_path, " -- run scripts/enforcement_by_permit_type.R first.")
enf <- fread(enf_path, colClasses = "character", showProgress = FALSE)
enf[, `:=`(Formal = as.integer(Formal), Informal = as.integer(Informal),
           Total = as.integer(Total), pct_informal = as.numeric(pct_informal))]
setorder(enf, -Total)

enf_rows <- sprintf("%s & %s & %s & %s & %s & %s\\%% \\\\",
                    enf$permit_type, enf$facility_status,
                    ci(enf$Formal), ci(enf$Informal), ci(enf$Total), p1(enf$pct_informal))
writeLines(c(enf_rows, "\\bottomrule"),
           file.path(OUT_DIR, "tab_enforcement_rows.tex"))

# Totals by permit type (pooled across status), for the in-prose summary table.
enf_by_type <- enf[, .(Formal = sum(Formal), Informal = sum(Informal)), by = permit_type]
enf_by_type[, Total := Formal + Informal]
enf_by_type[, pct_informal := round(100 * Informal / Total, 1)]
setorder(enf_by_type, -Total)

# ---- 5. Numbers macros (in-prose figures) ------------------------------------
macros <- c(
  sprintf("\\newcommand{\\permitsTotal}{%s}", ci(nrow(perm))),
  sprintf("\\newcommand{\\npdDistinct}{%s}", ci(n_npd_total)),
  sprintf("\\newcommand{\\gpcDistinct}{%s}", ci(n_gpc_total)),
  sprintf("\\newcommand{\\npdRecords}{%s}", ci(n_records_by_type[ptype=="NPD", n_records])),
  sprintf("\\newcommand{\\gpcRecords}{%s}", ci(n_records_by_type[ptype=="GPC", n_records])),
  sprintf("\\newcommand{\\npdMultiVersionPct}{%s}", p1(100 * n_npd_multiv / n_npd_total)),
  sprintf("\\newcommand{\\gpcMultiVersionPct}{%s}", p1(100 * n_gpc_multiv / n_gpc_total)),
  sprintf("\\newcommand{\\everMajorTotal}{%s}", ci(n_ever_major)),
  sprintf("\\newcommand{\\everMajorIndiv}{%s}", ci(n_ever_major_indiv)),
  sprintf("\\newcommand{\\everMajorIndivPct}{%s}", p1(100 * n_ever_major_indiv / n_ever_major)),
  sprintf("\\newcommand{\\dualPermitFacilities}{%s}", ci(n_dual)),
  sprintf("\\newcommand{\\maxGpcUin}{%s}", max_gpc_uin),
  sprintf("\\newcommand{\\maxGpcCount}{%s}", ci(max_gpc_count)),
  sprintf("\\newcommand{\\enfIndivFormalPct}{%s}",
          p1(100 * enf_by_type[permit_type=="Individual", Formal] / enf_by_type[permit_type=="Individual", Total])),
  sprintf("\\newcommand{\\enfIndivInformalPct}{%s}",
          p1(enf_by_type[permit_type=="Individual", pct_informal])),
  sprintf("\\newcommand{\\enfGenFormalPct}{%s}",
          p1(100 * enf_by_type[permit_type=="General", Formal] / enf_by_type[permit_type=="General", Total])),
  sprintf("\\newcommand{\\enfGenInformalPct}{%s}",
          p1(enf_by_type[permit_type=="General", pct_informal])),
  sprintf("\\newcommand{\\enfIndivTotal}{%s}", ci(enf_by_type[permit_type=="Individual", Total])),
  sprintf("\\newcommand{\\enfGenTotal}{%s}", ci(enf_by_type[permit_type=="General", Total]))
)
writeLines(macros, file.path(OUT_DIR, "permit_types_numbers.tex"))

message("Wrote 3 fragments to ", OUT_DIR)
message(sprintf("Distinct permits: NPD %s / GPC %s | version-records: NPD %s / GPC %s",
                ci(n_npd_total), ci(n_gpc_total),
                ci(n_records_by_type[ptype=="NPD", n_records]), ci(n_records_by_type[ptype=="GPC", n_records])))
message(sprintf("Ever-major: %s total, %s individual (%.1f%%)",
                ci(n_ever_major), ci(n_ever_major_indiv), 100*n_ever_major_indiv/n_ever_major))
message(sprintf("Dual-permit facilities: %s | max GPC sharing one UIN: %s (UIN %s)",
                ci(n_dual), ci(max_gpc_count), max_gpc_uin))
