# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# summarize_dmr_coverage_major_minor.R
# ------------------------------------------------------------------------------
# DMR reporting coverage for MAJOR vs. MINOR facilities, fiscal years 2015-2020.
# One green-gradient table (mirrors summarize_year_coverage.R): rows = metric x
# class, columns = fiscal year, cells = the count, shaded by a YlGn gradient.
#
# Metrics per class (Major = M, Minor = N in ICIS_PERMITS):
#   - Facilities reporting : distinct NPDES_IDs with >=1 DMR record that FY
#   - DMR records          : number of DMR rows that FY
#   - Coverage %           : facilities reporting / class size (all-period)
#
# NOTES / LABELED ASSUMPTIONS:
#   1. FISCAL YEAR. Each file is one federal fiscal year (Oct-Sep); columns are
#      labeled FY. We attribute a file wholly to its FY (no per-row date parse).
#   2. COVERAGE DENOMINATOR is the all-period count of distinct major (resp.
#      minor) permits. It is a fixed baseline, so early-year coverage is a
#      "share of ever-major/minor permits reporting," not of that year's
#      active permits. Read the trend, not the absolute level.
#   3. Class is assigned per NPDES_ID: Major if any permit version is "M".
# ------------------------------------------------------------------------------

library(data.table)
library(openxlsx)

# ── Configuration ─────────────────────────────────────────────────────────────
YEARS    <- 2015:2020
DMR_DIR  <- file.path(CWA_ROOT, "data/raw/DMR")
PERMITS  <- file.path(CWA_ROOT, "data/raw/npdes_downloads/ICIS_PERMITS.csv")
OUT_FILE <- sprintf(
  file.path(CWA_ROOT, "output/dmr_coverage_major_minor_%s.xlsx"),
  format(Sys.time(), "%Y-%m-%d_%H%M"))

# ── 1. Major/minor map: one class per NPDES_ID ────────────────────────────────
cat("Building major/minor map from ICIS_PERMITS ...\n")
p <- fread(PERMITS, select = c("EXTERNAL_PERMIT_NMBR", "MAJOR_MINOR_STATUS_FLAG"),
           colClasses = "character", showProgress = FALSE)
p[, `:=`(id = trimws(EXTERNAL_PERMIT_NMBR), flag = trimws(MAJOR_MINOR_STATUS_FLAG))]
p <- p[id != ""]
mm <- p[, .(class = if (any(flag == "M")) "Major"
                    else if (any(flag == "N")) "Minor" else NA_character_), by = id]
mm <- mm[!is.na(class)]
setkey(mm, id)
N_major <- mm[class == "Major", .N]
N_minor <- mm[class == "Minor", .N]
cat("  Major permits:", N_major, "| Minor permits:", N_minor, "\n")

# ── 2. Stream each fiscal-year DMR file, count by class ───────────────────────
res <- list()
for (y in YEARS) {
  zip <- file.path(DMR_DIR, sprintf("npdes_dmrs_fy%d.zip", y))
  csv <- sprintf("NPDES_DMRS_FY%d.csv", y)
  cat("Streaming FY", y, " ...\n", sep = "")
  d <- fread(cmd = sprintf("unzip -p %s %s", shQuote(zip), shQuote(csv)),
             select = "EXTERNAL_PERMIT_NMBR", colClasses = "character",
             showProgress = FALSE)
  setnames(d, "id")
  d[, id := trimws(id)]
  d[mm, class := i.class, on = "id"]          # attach Major/Minor
  agg <- d[!is.na(class), .(n_fac = uniqueN(id), n_rows = .N), by = class]
  agg[, year := y]
  res[[as.character(y)]] <- agg
  rm(d); gc()
}
res <- rbindlist(res)

# ── 3. Shape into the metric x year matrix ────────────────────────────────────
getv <- function(cls, col) sapply(YEARS, function(y) {
  v <- res[class == cls & year == y][[col]]; if (length(v)) v else 0L })

rows <- list(
  "Major - facilities reporting" = getv("Major", "n_fac"),
  "Minor - facilities reporting" = getv("Minor", "n_fac"),
  "Major - DMR records"          = getv("Major", "n_rows"),
  "Minor - DMR records"          = getv("Minor", "n_rows"),
  "Major - coverage %"           = round(100 * getv("Major", "n_fac") / N_major, 1),
  "Minor - coverage %"           = round(100 * getv("Minor", "n_fac") / N_minor, 1))
mat <- do.call(rbind, rows)
colnames(mat) <- paste0("FY", YEARS)
is_pct <- grepl("coverage", rownames(mat))

# ── 4. Styles (mirror summarize_year_coverage.R) ──────────────────────────────
HEADER   <- "#D9E1F2"
GRADIENT <- c("#FFFFCC", "#C2E699", "#78C679", "#31A354", "#006837")
style_header <- createStyle(fontSize = 11, textDecoration = "bold", fgFill = HEADER,
                            halign = "center", valign = "center",
                            border = "TopBottomLeftRight", borderColour = "#BFBFBF")
style_rowlab <- createStyle(fontSize = 11, valign = "center",
                            border = "TopBottomLeftRight", borderColour = "#BFBFBF")
g_int <- lapply(GRADIENT, function(c) createStyle(fgFill = c, numFmt = "#,##0",
                 halign = "center", border = "TopBottomLeftRight", borderColour = "#BFBFBF"))
g_pct <- lapply(GRADIENT, function(c) createStyle(fgFill = c, numFmt = "0.0",
                 halign = "center", border = "TopBottomLeftRight", borderColour = "#BFBFBF"))

# ── 5. Write workbook ─────────────────────────────────────────────────────────
wb <- createWorkbook(); sheet <- "DMR Coverage"; addWorksheet(wb, sheet)
n <- nrow(mat); C0 <- 2; last_col <- C0 + length(YEARS) - 1

writeData(wb, sheet, "Metric", startRow = 1, startCol = 1)
writeData(wb, sheet, t(colnames(mat)), startRow = 1, startCol = C0, colNames = FALSE)
addStyle(wb, sheet, style_header, rows = 1, cols = 1:last_col, gridExpand = TRUE)

writeData(wb, sheet, rownames(mat), startRow = 2, startCol = 1, colNames = FALSE)
addStyle(wb, sheet, style_rowlab, rows = 2:(n + 1), cols = 1)
writeData(wb, sheet, mat, startRow = 2, startCol = C0, colNames = FALSE, rowNames = FALSE)

# Row-wise green gradient (each row bucketed by its own year-to-year range)
for (i in seq_len(n)) {
  vals <- mat[i, ]; nz <- vals[vals > 0]
  styles <- if (is_pct[i]) g_pct else g_int
  if (length(nz) == 0) next
  brks <- quantile(nz, probs = seq(0, 1, length.out = length(GRADIENT) + 1), type = 1)
  for (j in seq_along(YEARS)) {
    b <- if (vals[j] > 0) min(length(GRADIENT), max(1L,
           findInterval(vals[j], brks, rightmost.closed = TRUE))) else 1L
    addStyle(wb, sheet, styles[[b]], rows = i + 1, cols = C0 + j - 1)
  }
}

setColWidths(wb, sheet, cols = 1, widths = 30)
setColWidths(wb, sheet, cols = C0:last_col, widths = 12)
freezePane(wb, sheet, firstActiveRow = 2, firstActiveCol = C0)
saveWorkbook(wb, OUT_FILE, overwrite = TRUE)

# ── 6. Console report ─────────────────────────────────────────────────────────
cat("\nDMR coverage, major vs minor, FY", min(YEARS), "-", max(YEARS), ":\n", sep = "")
print(mat)
cat("\nWritten to:", OUT_FILE, "\n")
