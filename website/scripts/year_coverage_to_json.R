# Converts summarize_year_coverage.R's cross-tab workbook (output/year_coverage_*.xlsx)
# into JSON for the public website. Unlike the per-dataset summary sheets, this is a
# single (file, variable) x year matrix, not the title/categorical/numeric layout — see
# xlsx_to_json.R for that one.
#
# Usage: Rscript website/scripts/year_coverage_to_json.R
#   Writes website/data/year_coverage.json

library(openxlsx)
library(jsonlite)

CWA_ROOT <- "/Users/alihunter/Library/CloudStorage/Dropbox/CWA"
OUT_DIR  <- file.path(CWA_ROOT, "output")
JSON_DIR <- file.path(CWA_ROOT, "website/data")
dir.create(JSON_DIR, showWarnings = FALSE, recursive = TRUE)

latest_file <- function(pattern) {
  files <- list.files(OUT_DIR, pattern = pattern, full.names = TRUE)
  files <- files[!grepl("/~\\$", files)]
  if (length(files) == 0) stop("No files matching: ", pattern)
  files[order(file.info(files)$mtime, decreasing = TRUE)][1]
}

path <- latest_file("^year_coverage_.*\\.xlsx$")
cat("Converting year_coverage <-", basename(path), "\n")

# fillMergedCells recovers the File column's value in continuation rows (merged
# in the source sheet across each file's variable rows).
raw <- readWorkbook(path, sheet = "Year Coverage", colNames = FALSE,
                     skipEmptyRows = FALSE, fillMergedCells = TRUE)

years <- as.character(as.integer(unlist(raw[1, 3:ncol(raw)])))
n <- nrow(raw)

rows <- lapply(2:n, function(r) {
  counts <- raw[r, 3:ncol(raw)]
  counts <- lapply(counts, function(v) if (is.na(v)) NULL else as.integer(v))
  names(counts) <- years
  counts <- counts[!vapply(counts, is.null, logical(1))]
  list(file = raw[r, 1], variable = raw[r, 2], counts = counts)
})

out <- list(source_file = basename(path), years = years, rows = rows)
write(toJSON(out, auto_unbox = TRUE, na = "null"),
      file.path(JSON_DIR, "year_coverage.json"))

cat("Done. JSON written to", file.path(JSON_DIR, "year_coverage.json"), "\n")
cat("Rows:", n - 1, "| Years:", length(years), "\n")
