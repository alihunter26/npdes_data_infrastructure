# `scripts/summary/` — dataset summary generators

Scripts that produce **per-dataset Excel summary sheets** — for each variable: percent
missing, distinct-category counts, top frequent values (with code → description
lookups), and numeric/date five-number summaries. Output is a timestamped `.xlsx` in
`output/`.

## `summarize.R` — single entry point

One registry-driven script builds any dataset's summary, so the shared styles, helpers,
and worksheet writer live in one place:

```bash
Rscript scripts/summary/summarize.R <dataset> [arg]
#   <dataset>: npdes | dmrs | attains | eff_violations | eff_violations_state
#              limits | master_general_permits | outfalls_layer   (or "all")
#   [arg]:     state code for eff_violations_state (default NY);
#              a single filename for npdes (default: NPDES_QNCR_HISTORY.csv),
#              or "all" to summarize every CSV in npdes_downloads/ in one workbook
#              (one sheet per table, incl. ICIS_FACILITIES.csv, ICIS_PERMITS.csv, ...)
```

Each dataset is a config entry in the `DATASETS` list (id/date columns, descriptions,
distinct-count label, reader). Output was verified byte-identical to the legacy
per-dataset scripts, except every sheet now uses the fuller 8-column categorical /
9-column numeric layout (a trailing, always-blank **Missing Explanation** column).

## Legacy per-dataset scripts (moved to `CWA scraps/`)

`summarize_npdes.R` (the template the others mirror), `summarize_dmrs.R`,
`summarize_eff_violations.R`, `summarize_eff_violations_state.R`,
`summarize_master_general_permits.R`, `summarize_outfalls_layer.R`,
`summarize_attains.R`, `summarize_limits.R`, `summarize_limits_chunked.R` are fully
superseded by `summarize.R` and were moved to `CWA scraps/` (repo root) to keep this
folder to the maintained scripts. They still run as-is if needed (same `_paths.R`
sourcing, unaffected by location) but are no longer the recommended way to generate
these summaries. Two cross-tab scripts (`summarize_dmr_coverage_major_minor.R`,
`summarize_year_coverage.R`) build a different kind of output (coverage matrices), are
still current, and remain in this folder.

## Conventions

- Sources `_paths.R`; reads raw as character; whitespace-only cells normalized to `NA`
  so `% Missing` stays consistent; large files streamed from their zips.
- Outputs timestamped to `output/`; raw data never modified.

See the root `README.md` for the input/output table.
