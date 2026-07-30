# `code/summary/` — dataset summary generators

Scripts that produce **per-dataset Excel summary sheets** — for each variable: percent
missing, distinct-category counts, top frequent values (with code → description
lookups), and numeric/date five-number summaries — plus a few cross-tab and QA
scripts that build a different kind of output entirely. Raw data is never modified;
see each section below for exact output paths (most are timestamped, a few are not).

## [`summarize.R`](summarize.md) — single entry point for per-file variable summaries

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

The FY2025/FY2009 DMR filter-pipeline trio (`build_dmr_raw_summary.R`,
`combine_dmr_summaries.R`, `combine_dmr_summaries_fy2009.R`) and the DMR coverage
cross-tab (`summarize_dmr_coverage_major_minor.R`) moved to `code/dmr/` 2026-07-27 —
see its README.

## Cross-tab scripts (coverage matrices, not per-variable summaries)

| Script | Purpose | Output |
|---|---|---|
| [`summarize_year_coverage.R`](summarize_year_coverage.md) | Which years appear in which raw file's DATE/YEAR-named columns, across all of `data/raw/` (cheap column-only scan, so even multi-GB files like `NPDES_LIMITS.csv` are fast). | `output/year_coverage_<timestamp>.xlsx` |

## [`summarize_panel.R`](summarize_panel.md) — QA check for a *built* panel, not a raw source file

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

## [`summarize_violation_types.R`](summarize_violation_types.md) — violation-type composition of a built panel

Also reads a *built* panel (not a raw source file), but answers a different question
than `summarize_panel.R`'s QA checks: of all violations tallied in the panel, what
percent are permit-schedule vs. compliance-schedule vs. single-event vs. effluent
(TSS gross monthly-average)? The four top-level violation-count columns are mutually
exclusive and sum to the denominator; the effluent total is further broken out by
VIOLATION_CODE (D90/D80/E90) as a share *of* the effluent subset, not added to it.

```bash
Rscript code/summary/summarize_violation_types.R
#   Input : data/processed/04_facility_month_panel_major_individual_violations_2005_2025.csv
```

Prints both tables to the console and writes
`output/tables/violation_type_summary_<timestamp>.csv`.

## Conventions

- Sources `_paths.R`; reads raw as character; whitespace-only cells normalized to `NA`
  so `% Missing` stays consistent; large files streamed from their zips.
- Raw data never modified. Most outputs are timestamped in `output/`.

See the root `README.md` for the input/output table.
