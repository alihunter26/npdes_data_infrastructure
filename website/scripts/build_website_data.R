# ==============================================================================
# build_website_data.R — regenerate every JSON the static site reads.
# ------------------------------------------------------------------------------
# The website (website/*.html) shows data from website/data/*.json, which is NOT
# produced by the panel build. This script is the single entry point for that
# refresh: it runs the per-dataset summaries + year-coverage + panel QA summary,
# then converts each to JSON. run_all.R calls it as its final stage (behind
# BUILD_WEBSITE); it also runs standalone:
#
#   Rscript website/scripts/build_website_data.R
#
# Each step runs in its OWN Rscript process, for two reasons: (1) memory --
# the `limits` summary loads a ~7 GB file, so isolating it keeps peak memory to
# one dataset at a time; (2) fail-soft -- a step that errors is logged and the
# rest continue, so one heavy/failed summary can't sink the whole site build.
# The JSON converters skip any dataset whose workbook is missing (see
# xlsx_to_json.R), so a partial run still refreshes what succeeded.
#
# Heads-up: a full run is slow. `limits` reads a multi-GB CSV in memory and the
# two eff_violations states each stream a ~2.9 GB zip. Skip individual summaries
# by commenting out their run_step() lines if you only need some pages refreshed.
# ==============================================================================

# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

RSCRIPT <- file.path(R.home("bin"), "Rscript")

# Run one Rscript step. shQuote the script path (the repo path can contain
# spaces); dataset args are plain tokens. Returns TRUE on exit code 0.
run_step <- function(label, script, args = character(0)) {
  message("\n----- ", label, " -----")
  st <- system2(RSCRIPT, c(shQuote(file.path(CWA_ROOT, script)), args),
                stdout = "", stderr = "")
  ok <- identical(st, 0L)
  if (!ok) message("  !! FAILED (exit ", st, "): ", label, " -- continuing.")
  ok
}

SUM <- "code/summary/summarize.R"

# Order matters: all summaries first, then the converters that read them.
results <- c(
  # ── Per-dataset summary workbooks -> output/*_summary_*.xlsx ──
  run_step("summary: npdes (every core table)", SUM, c("npdes", "all")),
  run_step("summary: dmrs",                     SUM, "dmrs"),
  run_step("summary: attains",                  SUM, "attains"),
  run_step("summary: limits (multi-GB)",        SUM, "limits"),
  run_step("summary: master_general_permits",   SUM, "master_general_permits"),
  run_step("summary: outfalls_layer",           SUM, "outfalls_layer"),
  run_step("summary: eff_violations (VA)",      SUM, c("eff_violations_state", "VA")),
  run_step("summary: eff_violations (NY)",      SUM, c("eff_violations_state", "NY")),
  run_step("year coverage cross-tab",           "code/summary/summarize_year_coverage.R"),
  run_step("panel QA summary",                  "code/summary/summarize_panel.R"),

  # ── Convert workbooks -> website/data/*.json ──
  run_step("convert: dataset summaries -> JSON", "website/scripts/xlsx_to_json.R"),
  run_step("convert: year coverage -> JSON",     "website/scripts/year_coverage_to_json.R"),
  run_step("convert: panel summary -> JSON",     "website/scripts/panel_to_json.R")
)

message(sprintf("\n=== website data build: %d/%d steps OK ===", sum(results), length(results)))
if (!all(results))
  message("Some steps failed (see log above). JSON for successful steps was still refreshed; ",
          "existing JSON for failed steps is unchanged.")
message("Serve the site over HTTP to view it, e.g.:  cd website && python3 -m http.server 8000")
