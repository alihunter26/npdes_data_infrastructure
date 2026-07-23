# ==============================================================================
# 01_download_echo_bulk_files.R — scripted download of EPA ECHO / ICIS-NPDES
# bulk data files into data/raw/.
# ------------------------------------------------------------------------------
# Replaces the previously-manual step of visiting
# https://echo.epa.gov/tools/data-downloads and clicking through each bulk file
# by hand. One config-table-driven loop (same pattern as
# code/summary/summarize.R's DATASETS registry) downloads every source, so
# adding/adjusting a source means editing one table row, not writing a new
# script.
#
# Inputs:  none (fetches from echo.epa.gov over HTTP).
# Outputs: files under data/raw/ (see SOURCES below); a running manifest at
#          data/raw/_download_log.csv (timestamp, name, url, dest_path, status,
#          bytes) — this is what resolves the "record the ECHO download date"
#          TODO repeated across several READMEs.
#
# LABELED ASSUMPTIONS:
#   1. Six of the seven non-DMR URLs below were confirmed by directly fetching
#      the live https://echo.epa.gov/tools/data-downloads page. The per-fiscal-
#      year DMR URLs are NOT confirmed the same way -- that page's DMR section
#      is a JS-driven dropdown with no static href to read. The DMR URL pattern
#      below is inferred from (a) every other confirmed URL following
#      https://echo.epa.gov/files/echodownloads/<exact-local-filename>, and
#      (b) the local files already on disk being named exactly
#      npdes_dmrs_fy2009.zip ... npdes_dmrs_fy2025.zip. Confirmed sources hard-
#      fail this script on error; inferred (DMR) sources log a failure and let
#      the loop continue, so one bad guessed year can't take down the other 16.
#   2. REF_STATISTICAL_BASE.csv (data/raw/reference/) is deliberately NOT in the
#      SOURCES table below -- no bulk-zip source for it was found anywhere on
#      the ECHO downloads page or its linked summary pages. It stays a manual
#      placement; see the message printed at the end of this script.
#   3. Zips are downloaded and (where extract_to is set) extracted, but the
#      zip itself is also kept -- several downstream scripts
#      (code/03_panel_building/06_add_effluent_violations.R,
#      code/diagnostics/missingness/missingness_audit_major_individual.R, etc.)
#      read specific member CSVs straight out of the zip via `unzip -p`, so
#      deleting zips after extraction would break them.
#   4. Raw data is immutable (CLAUDE.md / data/raw/README.md): by default this
#      script will NOT overwrite a destination that already exists. Set
#      REFRESH <- TRUE below to force a re-download of everything.
# ==============================================================================

source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# Set TRUE to re-download and overwrite files that already exist locally.
REFRESH <- FALSE

MIN_BYTES   <- 10 * 1024        # anything smaller than this isn't a real bulk file
ZIP_MAGIC   <- list(as.raw(c(0x50, 0x4B, 0x03, 0x04)),   # normal zip
                     as.raw(c(0x50, 0x4B, 0x05, 0x06)))  # empty zip
LOG_PATH    <- file.path(RAW_ROOT, "_download_log.csv")
BASE_URL    <- "https://echo.epa.gov/files/echodownloads"

# ------------------------------------------------------------------------------
# Confirmed sources (fetched directly from the live ECHO data-downloads page)
# ------------------------------------------------------------------------------
confirmed <- list(
  list(name = "npdes_downloads",
       url  = file.path(BASE_URL, "npdes_downloads.zip"),
       dest_zip   = file.path(RAW_ROOT, "_zips", "npdes_downloads.zip"),
       extract_to = RAW_DIR,
       mandatory  = TRUE),
  list(name = "npdes_eff_downloads",
       url  = file.path(BASE_URL, "npdes_eff_downloads.zip"),
       dest_zip   = file.path(RAW_ROOT, "npdes_eff_downloads.zip"),
       extract_to = NULL,   # stays zipped -- 06_add_effluent_violations.R streams it
       mandatory  = TRUE),
  list(name = "npdes_limits",
       url  = file.path(BASE_URL, "npdes_limits.zip"),
       dest_zip   = file.path(RAW_ROOT, "_zips", "npdes_limits.zip"),
       extract_to = RAW_ROOT,   # expected member: NPDES_LIMITS.csv
       mandatory  = TRUE),
  list(name = "npdes_outfalls_layer",
       url  = file.path(BASE_URL, "npdes_outfalls_layer.zip"),
       dest_zip   = file.path(RAW_ROOT, "_zips", "npdes_outfalls_layer.zip"),
       extract_to = RAW_ROOT,   # expected member: npdes_outfalls_layer.csv
       mandatory  = TRUE),
  list(name = "npdes_master_general_permits",
       url  = file.path(BASE_URL, "npdes_master_general_permits.zip"),
       dest_zip   = file.path(RAW_ROOT, "Master General Permits", "npdes_master_general_permits.zip"),
       extract_to = file.path(RAW_ROOT, "Master General Permits"),
       mandatory  = TRUE),
  list(name = "npdes_attains_downloads",
       url  = file.path(BASE_URL, "npdes_attains_downloads.zip"),
       dest_zip   = file.path(RAW_ROOT, "_zips", "npdes_attains_downloads.zip"),
       extract_to = file.path(RAW_ROOT, "Attains"),
       mandatory  = TRUE)
)

# ------------------------------------------------------------------------------
# DMR per-fiscal-year sources -- INFERRED URL pattern, not confirmed (see
# LABELED ASSUMPTION 1). mandatory = FALSE: a failure here is logged and
# skipped, not fatal to the run.
# ------------------------------------------------------------------------------
dmr_years <- 2009:2025
dmr_sources <- lapply(dmr_years, function(yr) {
  list(name = sprintf("npdes_dmrs_fy%d", yr),
       url  = file.path(BASE_URL, sprintf("npdes_dmrs_fy%d.zip", yr)),
       dest_zip   = file.path(DMR_DIR, sprintf("npdes_dmrs_fy%d.zip", yr)),
       extract_to = NULL,   # stays zipped -- read via `unzip -p` elsewhere
       mandatory  = FALSE)
})
dmr_prefy2009 <- list(
  list(name = "npdes_dmrs_prefy2009",
       url  = file.path(BASE_URL, "npdes_dmrs_prefy2009.zip"),
       dest_zip   = file.path(DMR_DIR, "npdes_dmrs_prefy2009.zip"),
       extract_to = NULL,
       mandatory  = FALSE)
)

SOURCES <- c(confirmed, dmr_sources, dmr_prefy2009)

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
is_valid_zip <- function(path) {
  if (!file.exists(path) || file.info(path)$size < MIN_BYTES) return(FALSE)
  head4 <- readBin(path, what = "raw", n = 4)
  any(vapply(ZIP_MAGIC, function(m) identical(head4, m), logical(1)))
}

log_attempt <- function(name, url, dest, status, bytes) {
  row <- data.frame(timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                     name = name, url = url, dest_path = dest,
                     status = status, bytes = bytes, stringsAsFactors = FALSE)
  write.table(row, LOG_PATH, sep = ",", row.names = FALSE,
              col.names = !file.exists(LOG_PATH), append = file.exists(LOG_PATH))
}

download_one <- function(src) {
  dir.create(dirname(src$dest_zip), showWarnings = FALSE, recursive = TRUE)

  if (file.exists(src$dest_zip) && !REFRESH) {
    message("SKIPPED-EXISTS: ", src$name, " -> ", src$dest_zip)
    log_attempt(src$name, src$url, src$dest_zip, "SKIPPED-EXISTS",
                file.info(src$dest_zip)$size)
    return(invisible(TRUE))
  }

  message("Downloading ", src$name, " ...")
  status <- tryCatch(
    download.file(src$url, src$dest_zip, mode = "wb", method = "libcurl", quiet = TRUE),
    error = function(e) { message("  error: ", conditionMessage(e)); -1L }
  )

  ok <- identical(status, 0L) && is_valid_zip(src$dest_zip)
  bytes <- if (file.exists(src$dest_zip)) file.info(src$dest_zip)$size else NA_real_

  if (!ok) {
    log_attempt(src$name, src$url, src$dest_zip,
                if (src$mandatory) "FAILED" else "FAILED-inferred-url", bytes)
    msg <- sprintf("Download failed or not a valid zip: %s (%s)", src$name, src$url)
    if (src$mandatory) {
      stop(msg)
    } else {
      message("  ", msg,
              " -- inferred URL, verify manually at ",
              "https://echo.epa.gov/tools/data-downloads#downloads")
      return(invisible(FALSE))
    }
  }

  log_attempt(src$name, src$url, src$dest_zip, "OK", bytes)

  if (!is.null(src$extract_to)) {
    dir.create(src$extract_to, showWarnings = FALSE, recursive = TRUE)
    utils::unzip(src$dest_zip, exdir = src$extract_to, overwrite = REFRESH)
    message("  extracted to ", src$extract_to)
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# Run
# ------------------------------------------------------------------------------
results <- vector("logical", length(SOURCES))
for (i in seq_along(SOURCES)) {
  results[i] <- isTRUE(download_one(SOURCES[[i]]))
  if (grepl("^npdes_dmrs_fy", SOURCES[[i]]$name)) Sys.sleep(2)  # don't hammer the host
}

n_failed_inferred <- sum(!results & !vapply(SOURCES, `[[`, logical(1), "mandatory"))
message(sprintf("\nDone: %d/%d sources OK or already present.", sum(results), length(SOURCES)))
if (n_failed_inferred > 0) {
  message(n_failed_inferred, " inferred-URL (DMR) source(s) failed -- see ",
          LOG_PATH, " and verify manually if those years are needed.")
}
message("\nNOTE: REF_STATISTICAL_BASE.csv is not fetched by this script -- no bulk-zip",
        "\nsource for it was found. Place it manually at",
        "\ndata/raw/reference/REF_STATISTICAL_BASE.csv per data/raw/README.md.")
