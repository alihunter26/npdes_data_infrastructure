# Converts summarize_panel.R's QA workbook (output/panel_summary_*.xlsx) into JSON
# for the public website's Panel page. Unlike the per-dataset summaries
# (xlsx_to_json.R), this workbook is just five plain rectangular sheets
# (structure / rows-per-year / missingness / numeric summary / consistency
# checks), so each sheet maps directly to an array-of-objects table.
#
# Usage: Rscript website/scripts/panel_to_json.R
#   Reads the newest output/panel_summary_*.xlsx, writes website/data/panel.json

# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

suppressMessages({library(openxlsx); library(jsonlite)})

JSON_DIR <- file.path(CWA_ROOT, "website/data")
dir.create(JSON_DIR, showWarnings = FALSE, recursive = TRUE)

# Newest workbook matching a prefix, excluding Excel lock files (~$...).
latest_file <- function(pattern) {
  files <- list.files(OUT_DIR, pattern = pattern, full.names = TRUE)
  files <- files[!grepl("/~\\$", files)]
  if (length(files) == 0) return(NA_character_)
  files[order(file.info(files)$mtime, decreasing = TRUE)][1]
}

path <- latest_file("^panel_summary_.*\\.xlsx$")
if (is.na(path)) {
  message("No panel_summary_*.xlsx in ", OUT_DIR,
          " -- run code/summary/summarize_panel.R first; skipping panel.json.")
  quit(save = "no", status = 0)
}
cat("Converting panel <-", basename(path), "\n")

sheets <- getSheetNames(path)
result <- lapply(sheets, function(s) read.xlsx(path, sheet = s))
names(result) <- sheets

# The panel file the summary describes, recovered from the workbook stem
# (panel_summary_<panel-name>_<timestamp>.xlsx -> <panel-name>).
panel_name <- sub("^panel_summary_(.*)_\\d{4}-\\d{2}-\\d{2}_\\d{4}$", "\\1",
                  tools::file_path_sans_ext(basename(path)))

out <- list(source_file = basename(path), panel = panel_name, sheets = result)
write(toJSON(out, dataframe = "rows", na = "null", auto_unbox = TRUE, pretty = FALSE),
      file.path(JSON_DIR, "panel.json"))

cat("Done. JSON written to", file.path(JSON_DIR, "panel.json"), "\n")
