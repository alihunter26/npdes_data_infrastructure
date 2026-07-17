# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# make_naics_sic_coverage_brief.R
# ------------------------------------------------------------------------------
# Generate the LaTeX table fragments \input by output/briefs/naics_sic_coverage_by_state.tex.
#
# Source: the newest naics_sic_coverage_by_state_year_*.csv in output/tables/,
#   itself produced by scripts/diagnostics/naics_sic_coverage_by_state_year.R
#   (major-individual permit-years, 2005-2025; NAICS/SIC presence is a
#   time-invariant permit attribute). We only re-key + pool here.
#
# Writes (machine-generated; do NOT hand-edit -- rerun this script instead):
#   output/briefs/tab_naics_sic_by_state_rows.tex   (per-state pooled rows + total)
#   output/briefs/tab_naics_sic_by_year_rows.tex    (national coverage per year)
#   output/briefs/naics_sic_coverage_numbers.tex    (\newcommand macros for in-prose figures)
# ==============================================================================

suppressPackageStartupMessages(library(data.table))

TAB_DIR <- file.path(CWA_ROOT, "output", "tables")
OUT_DIR <- file.path(CWA_ROOT, "output", "briefs")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- 1. Pick the newest coverage CSV -----------------------------------------
csvs <- list.files(TAB_DIR, pattern = "^naics_sic_coverage_by_state_year_.*\\.csv$",
                   full.names = TRUE)
if (length(csvs) == 0) stop("No coverage CSV in ", TAB_DIR,
                            " -- run naics_sic_coverage_by_state_year.R first.")
src <- csvs[which.max(file.mtime(csvs))]
message("Source coverage CSV: ", src)
d <- fread(src, showProgress = FALSE)

YR_MIN <- min(d$year); YR_MAX <- max(d$year)

# ---- 2. Pool to per-state (recompute % from summed counts, not mean of %) -----
st <- d[, .(N        = sum(n_permits),
            n_naics  = sum(n_naics),
            n_sic    = sum(n_sic)),
        by = STATE_CODE]
st[, pct_naics := 100 * n_naics / N]
st[, pct_sic   := 100 * n_sic   / N]
setorder(st, STATE_CODE)                      # alphabetical, reference-style

tot <- data.table(STATE_CODE = "All", N = sum(st$N),
                  n_naics = sum(st$n_naics), n_sic = sum(st$n_sic))
tot[, pct_naics := 100 * n_naics / N][, pct_sic := 100 * n_sic / N]

# ---- 3. National coverage by year --------------------------------------------
yr <- d[, .(N = sum(n_permits), n_naics = sum(n_naics), n_sic = sum(n_sic)), by = year]
yr[, pct_naics := 100 * n_naics / N][, pct_sic := 100 * n_sic / N]
setorder(yr, year)

# ---- 4. Helpers to emit LaTeX rows -------------------------------------------
ci  <- function(x) formatC(x, format = "d", big.mark = ",")   # comma integer
p1  <- function(x) formatC(x, format = "f", digits = 1)        # 1-dp percent
row_state <- function(r) sprintf("%s & %s & %s & %s & %s & %s \\\\",
                                 r$STATE_CODE, ci(r$N), ci(r$n_naics), p1(r$pct_naics),
                                 ci(r$n_sic), p1(r$pct_sic))

state_lines <- vapply(seq_len(nrow(st)), function(i) row_state(st[i]), character(1))
total_line  <- sub("^All ", "\\\\textbf{All} ", row_state(tot))
writeLines(c(state_lines, "\\midrule", total_line),
           file.path(OUT_DIR, "tab_naics_sic_by_state_rows.tex"))

year_lines <- vapply(seq_len(nrow(yr)), function(i) {
  r <- yr[i]; sprintf("%d & %s & %s & %s \\\\", r$year, ci(r$N), p1(r$pct_naics), p1(r$pct_sic))
}, character(1))
writeLines(year_lines, file.path(OUT_DIR, "tab_naics_sic_by_year_rows.tex"))

# ---- 5. In-prose figures as LaTeX macros (so numbers stay traceable) ---------
n0_naics <- st[round(pct_naics, 1) == 0, .N]           # states with ~0% NAICS
hi_naics <- st[pct_naics >= 95, .N]                    # states with >=95% NAICS
lo_sic   <- st[pct_sic   <  90, sort(STATE_CODE)]      # states below 90% SIC
macros <- c(
  sprintf("\\newcommand{\\covYearMin}{%d}", YR_MIN),
  sprintf("\\newcommand{\\covYearMax}{%d}", YR_MAX),
  sprintf("\\newcommand{\\covNStates}{%d}", nrow(st)),
  sprintf("\\newcommand{\\covPermitYears}{%s}", ci(tot$N)),
  sprintf("\\newcommand{\\covNatNaics}{%s}", p1(tot$pct_naics)),
  sprintf("\\newcommand{\\covNatSic}{%s}",   p1(tot$pct_sic)),
  sprintf("\\newcommand{\\covZeroNaics}{%d}", n0_naics),
  sprintf("\\newcommand{\\covHiNaics}{%d}",   hi_naics),
  sprintf("\\newcommand{\\covLoSicList}{%s}", paste(lo_sic, collapse = ", ")),
  sprintf("\\newcommand{\\covSrcFile}{%s}", gsub("_", "\\\\_", basename(src))))
writeLines(macros, file.path(OUT_DIR, "naics_sic_coverage_numbers.tex"))

message("Wrote 3 fragments to ", OUT_DIR)
message(sprintf("National pooled: NAICS %s%%, SIC %s%% over %s permit-years; %d states/terr.",
                p1(tot$pct_naics), p1(tot$pct_sic), ci(tot$N), nrow(st)))
message(sprintf("States ~0%% NAICS: %d | >=95%% NAICS: %d | <90%% SIC: %s",
                n0_naics, hi_naics, paste(lo_sic, collapse = ", ")))
