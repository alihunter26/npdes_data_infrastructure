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
#              a single filename for npdes (default: NPDES_QNCR_HISTORY.csv)
```

Each dataset is a config entry in the `DATASETS` list (id/date columns, descriptions,
distinct-count label, reader). Output was verified byte-identical to the legacy
per-dataset scripts, except every sheet now uses the fuller 8-column categorical /
9-column numeric layout (a trailing, always-blank **Missing Explanation** column).

## Legacy per-dataset scripts (kept for reference; still run)

`summarize_npdes.R` (the template the others mirror), `summarize_dmrs.R`,
`summarize_eff_violations.R`, `summarize_eff_violations_state.R`,
`summarize_master_general_permits.R`, `summarize_outfalls_layer.R`,
`summarize_attains.R`, `summarize_limits.R`, `summarize_limits_chunked.R`. Two cross-tab
scripts (`summarize_dmr_coverage_major_minor.R`, `summarize_year_coverage.R`) build a
different kind of output (coverage matrices) and are **not** folded into `summarize.R`.

## Conventions

- Sources `_paths.R`; reads raw as character; whitespace-only cells normalized to `NA`
  so `% Missing` stays consistent; large files streamed from their zips.
- Outputs timestamped to `output/`; raw data never modified.

See the root `README.md` for the input/output table.
