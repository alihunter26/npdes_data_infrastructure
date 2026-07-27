# `code/summary/` — dataset summary generators

Scripts that produce **per-dataset Excel summary sheets** — for each variable: percent
missing, distinct-category counts, top frequent values (with code → description
lookups), and numeric/date five-number summaries — plus a few cross-tab and QA
scripts that build a different kind of output entirely. Raw data is never modified;
see each section below for exact output paths (most are timestamped, a few are not).

## `summarize.R` — single entry point for per-file variable summaries

One registry-driven script builds any dataset's summary, so the shared styles, helpers,
and worksheet writer live in one place:

```bash
Rscript code/summary/summarize.R <dataset> [arg]
#   <dataset>: npdes | dmrs | attains | eff_violations | eff_violations_state
#              limits | master_general_permits | outfalls_layer   (or "all")
#   [arg]:     state code for eff_violations_state (default NY);
#              a single filename for npdes (default: NPDES_QNCR_HISTORY.csv),
#              or "all" to summarize every CSV in npdes_downloads/ in one workbook
#              (one sheet per table, incl. ICIS_FACILITIES.csv, ICIS_PERMITS.csv, ...)
```

Each dataset is a config entry in the `DATASETS` list (id/date columns, descriptions,
distinct-count label, reader). Every sheet uses an 8-column categorical / 9-column
numeric layout (a trailing, always-blank **Missing Explanation** column). Output:
timestamped `.xlsx` in `output/`.

## The FY2025 / FY2009 DMR filter-pipeline trio

These three build a *multi-tab* comparison across the stages of the DMR filter
pipeline in `dmr analysis/` (01 Major-Individual → 02 TSS(00530) → 03 Effluent
Gross → 04 C1/Q1) — a report shape `summarize.R`'s one-CSV-per-run registry doesn't
produce, so they stay standalone rather than living in `DATASETS`:

| Script | Purpose | Output |
|---|---|---|
| `build_dmr_raw_summary.R` | Summarizes the **raw, unfiltered** FY DMR file (every permit/parameter, no restriction at all). Uses DuckDB out-of-core — the raw file is 4.7-27M rows, too large to safely `fread` whole on an 8GB machine. Usage: `Rscript build_dmr_raw_summary.R <FY>` | `output/DMR/raw_summary_fy<FY>.rds` — **not** an `.xlsx`; a serialized summary object meant to be prepended into the workbooks below without recomputing. |
| `combine_dmr_summaries.R` | One workbook, one tab per FY2025 pipeline stage, with the raw-file summary above spliced in as tab 0. | `output/DMR/2025_dmr_summaries_combined.xlsx` — fixed filename, overwritten each run (**not** timestamped, unlike most other scripts here). |
| `combine_dmr_summaries_fy2009.R` | Identical logic and styling, pointed at the FY2009 pipeline stages instead (a comparison/baseline year). | `output/DMR/2009_dmr_summaries_combined.xlsx` — fixed filename, overwritten each run. |

## Cross-tab scripts (coverage matrices, not per-variable summaries)

| Script | Purpose | Output |
|---|---|---|
| `summarize_dmr_coverage_major_minor.R` | FY2015-2020: how many Major vs. Minor permits (per `ICIS_PERMITS.csv`) actually reported DMR data each year — counts and coverage %, shaded by a green gradient. | `output/dmr_coverage_major_minor_<timestamp>.xlsx` |
| `summarize_year_coverage.R` | Which years appear in which raw file's DATE/YEAR-named columns, across all of `data/raw/` (cheap column-only scan, so even multi-GB files like `NPDES_LIMITS.csv` are fast). | `output/year_coverage_<timestamp>.xlsx` |

## `summarize_panel.R` — QA check for a *built* panel, not a raw source file

Face-validity / realism check for a facility-month panel already built into
`data/processed/` (the 01..06 panels from `code/03_panel_building/`) — the goal is
catching construction bugs (bad merges, duplicated rows, impossible values, coverage
gaps) before the panel is trusted for analysis, not describing an input dataset:

```bash
Rscript code/summary/summarize_panel.R [panel_filename]
#   [panel_filename]: a file in data/processed (default: the newest
#                      0*_facility_month_panel*.csv). Numeric-summary and
#                      consistency checks auto-adapt to whichever columns are present.
```

Prints all four sections (panel structure/key uniqueness, coverage, numeric summary,
consistency checks) to the console, and writes
`output/panel_summary_<panel_name>_<timestamp>.xlsx`.

## Conventions

- Sources `_paths.R`; reads raw as character; whitespace-only cells normalized to `NA`
  so `% Missing` stays consistent; large files streamed from their zips.
- Raw data never modified. Most outputs are timestamped in `output/`; the DMR
  filter-pipeline trio's combined workbooks are the exception (fixed filenames,
  overwritten each run — see table above).

See the root `README.md` for the input/output table.
