# Research Notes

Running notes on data quirks, analytical decisions, and findings.

## Data Quality Issues

### Effluent violations file (2026-07-14)
- **Zip filename has a non-ASCII byte.** `npdes_eff_downloads … .zip` contains a
  non-breaking narrow space (U+202F, bytes `e2 80 af`) between the time and "PM".
  System `unzip` fails to open it; `tar`/`bsdtar` (libarchive) works. Passing the
  path through R's `system()` fails to translate to the session locale, so the
  build script keeps the name out of the shell string (cd into `data/raw` + an
  ASCII glob). Never hardcode this filename — match by pattern.
- **The CSV is a zip64 archive, ~15.9 GB uncompressed.** Too large for whole-file
  `fread` on this 8 GB machine; read out-of-core with DuckDB (see below).
- **A head sample of this file is NOT representative.** The first ~3 M rows are all
  D80/D90 (sorted, no E90). The resubmission de-dup rate looked like ~0.3% there
  but is **4.31% on the full file** — always verify counts on the full data.

## Analytical Decisions

### Effluent-violations NPDES_ID × month panel (2026-07-14)
Script: `scripts/build/build_effluent_violations_npdes_month_panel.R` →
`data/processed/effluent_violations_npdes_month_panel_2005_2025.csv`. Standalone;
not in `run_all.R`. Columns: `NPDES_ID, month, n_D80, n_D90, n_E90`.
- **Month** = calendar month of `MONITORING_PERIOD_END_DATE` (the DMR reporting
  period), not detection or receipt date.
- **Codes** live in `VIOLATION_CODE` (D80, D90, E90); one distinct-count column each.
- **Scope** = observed ID-months only. No zero-filled grid: a missing
  `NPDES_ID × month` means no D80/D90/E90 that month, not a measured zero.
- **Counting** = distinct underlying violation, latest `VERSION_NMBR` only, to drop
  DMR resubmissions. Implemented as `COUNT(DISTINCT vkey)` where `vkey` =
  NPDES_ID + perm feature + limit-set + monitoring location + parameter +
  statistical base + monitoring-period date; this is provably identical to a
  row_number() latest-version dedup for counts, and avoids a DuckDB internal
  planner bug in `row_number() OVER (PARTITION BY …)`.
- **Caveat (not corrected):** counts are over rows already filtered to the three
  codes, so a period corrected to compliant in a later version is not netted out.
- **Engine:** DuckDB out-of-core (5 GB mem cap + disk spill); the zip member is
  streamed to a ~3.9 GB gzip temp once, then parsed. ~15 min end to end.

## Findings

### Effluent D80/D90/E90 counts, 2005–2025 (2026-07-14)
From the panel above: 2,694,316 ID-months across 121,708 distinct NPDES_IDs, all
252 months present. Raw target rows in window 43,317,821 → 41,451,812 after
latest-version de-dup (**1,866,009 resubmissions removed, 4.31%**). Totals:
D80 = 21,073,782 · D90 = 17,814,134 · E90 = 2,563,896 (sum = 41,451,812, matches
the de-duplicated count).

