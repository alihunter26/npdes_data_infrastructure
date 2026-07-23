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
Script: `build_effluent_violations_npdes_month_panel.R` (moved to `../EIL Summer/build/`,
outside this repo) → `data/processed/effluent_violations_npdes_month_panel_2005_2025.csv`.
Standalone; not in `run_all.R`. Columns: `NPDES_ID, month, n_D80, n_D90, n_E90`.
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

### `FACILITY_OPERATING` correction — step 07 (2026-07-23)
Script: `code/03_panel_building/07_extend_facility_operating.R` →
`data/processed/07_facility_month_panel_major_individual_operating_corrected_2005_2025.csv`
(new final panel; superseded `06_..._effluent_2005_2025.csv`, which remains on disk
unchanged).
- **Trigger:** a direct question about whether `FACILITY_OPERATING == 0` (hence `NA`
  count columns) could be mislabeling facilities that were genuinely operating but just
  quiet that month.
- **Measured on the 06 panel:** 12.66% of `FACILITY_OPERATING == 0` rows (32,033 of
  253,028) carried a real recorded event anyway. 75.9% of those are >12 months outside
  the computed window (median 31, max 250 months) — not boundary noise. 2,381 of 7,511
  facilities (32%) affected: 2,132 close-side, 413 open-side.
- **Root cause:** permits with `PERMIT_STATUS_CODE == "ADC"` (Administrative
  Continuance) have `EXPIRATION_DATE` read as a real closing date by script 01 even
  though `ADC` means the permit is still legally active pending renewal. Confirmed on
  facility `110006619212` / permit `NH0100455`. 86.7% of the 8,007 permits linked to
  this panel's facilities carry `ADC` status at some point. This was already flagged as
  a general risk in `docs/data_quirks.md` (the `PERMIT_STATUS_CODE`/`EXPIRATION_DATE`
  row) before it was confirmed to actually be realized in the built panel.
- **Fix:** extend each facility's window (both directions, per PI decision) to
  `min/max(computed window, first/last month with a real recorded event)`; fill
  previously-NA count columns with `0` in the newly-covered months. Never shrinks a
  window. `FACILITY_OPERATING` in the new file carries the corrected value; the
  original is preserved as `FACILITY_OPERATING_PERMIT_WINDOW`.
- **Verified:** full column diff against the 06 panel shows zero illegal changes —
  every altered cell is exactly a blank/NA → 0 fill, every other column byte-identical.
  109,823 rows flip `FACILITY_OPERATING` 0→1; 3,772,636 NA→0 fills. Self-check (no
  `FACILITY_OPERATING==0` row may carry a real event after correction) passes and is a
  mathematical guarantee of the construction, not just an empirical result.
- **Not yet regenerated:** `06_facility_month_panel_major_individual_effluent_fy2025.csv`
  (the FY2025 row-filter) still reflects the pre-correction 06 panel.

## Findings

### Effluent D80/D90/E90 counts, 2005–2025 (2026-07-14)
From the panel above: 2,694,316 ID-months across 121,708 distinct NPDES_IDs, all
252 months present. Raw target rows in window 43,317,821 → 41,451,812 after
latest-version de-dup (**1,866,009 resubmissions removed, 4.31%**). Totals:
D80 = 21,073,782 · D90 = 17,814,134 · E90 = 2,563,896 (sum = 41,451,812, matches
the de-duplicated count).

