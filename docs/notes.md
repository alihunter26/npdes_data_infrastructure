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

### Effluent-violations NPDES_ID × month panel (2026-07-14; rebuilt in-repo 2026-07-27)
Produces `data/processed/effluent_violations_npdes_month_panel_2005_2025.csv`.
**Update 2026-07-27:** this file's producing script now lives in this repo --
`code/02_cleaning/build_effluent_violations_npdes_month_panel.R` (moved again,
same day, from `code/03_panel_building/` to `code/02_cleaning/`, per request --
path-only, no logic change) -- and `run_all.R` builds it automatically if it's
missing (it's a prerequisite for steps 01 and 06, not an optional step). The
rebuild also folds in the TSS
gross-effluent-subset counts (`N_TSS_EFF_VIOLATIONS`/`_D90`/`_D80`/`_E90`) that
`06_add_effluent_violations.R` used to compute separately via a second,
python3-driven stream of the raw file -- both count sets are now produced in
one pass. Columns: `NPDES_ID, month, n_D80, n_D90, n_E90, N_TSS_EFF_VIOLATIONS,
N_TSS_EFF_D90, N_TSS_EFF_D80, N_TSS_EFF_E90`. The original all-parameter
construction logic below is unchanged.
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

### FY2025 DMR TSS/effluent-gross/monthly-avg filter moved into repo (2026-07-27)
Script: `code/dmr/filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R` (moved from the
external EIL Summer working folder, same precedent as the effluent panel above; an
untouched copy remains there). Produces
`data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg.csv` — the input
`code/dmr/filter_dmr_fy2025_effgross_major_individual.R` restricts to major/individual
permits. Not part of `code/03_panel_building/` or `run_all.R`; a manually-run
mini-pipeline (see `code/README.md`).
**Update 2026-07-27 (later same day):** both scripts moved again, from a root-level
`build/` folder (now removed) into `code/dmr/`, alongside this repo's other
DMR-specific summary/diagnostic scripts — path-only, no logic change.
- **No path changes needed.** The script already used this repo's exact `_paths.R`
  constants (`DMR_DIR`, `PROC_DIR`) and portable header, unlike the effluent panel
  script, which needed real adaptation.
- **Verified by running it end to end from its new location:** 754,033 rows, 34,797
  distinct permits, 57/57 columns, zero filter-violation rows, internal assertions
  (`n_param`/`n_feat`/`n_stat` each `== 1`) passed. ~24.5 min wall time (~9.68 GB raw
  file streamed once).

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
  a general risk in `docs/data_issues.md` (the `PERMIT_STATUS_CODE`/`EXPIRATION_DATE`
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

### `FACILITY_OPERATING` correction relocated into step 01 (2026-07-23)
Per request, step 07 above was retired and its logic folded directly into
`code/03_panel_building/01_build_facility_month_panel_major_individual.R`
(Assumptions 10–13 there). The findings and numbers in the entry above are unchanged
and still accurate — only *where* the correction runs changed, not what it does or
what it produces.
- **Why this was possible:** the correction only ever needed event *existence*
  (whether/when a facility had any real event), not the full detailed counts steps
  02/04/05/06 compute — so it doesn't actually need to wait until step 06 finishes.
  Verified empirically first: zero facility-months have a positive TSS-subset
  violation while the condensed all-parameter effluent panel shows nothing, so step 01
  can use just the condensed panel and skip streaming the raw 16 GB effluent file
  entirely (no `python3`/`unzip` needed in step 01).
- **Bug caught and fixed during the move:** an early version of the relocated logic
  derived its event-routing crosswalk from `01`'s own individual/major-restricted
  facility table, rather than a full, unrestricted `ICIS_FACILITIES` read (as
  02/04/05/06 each independently do) — this silently dropped events recorded under a
  qualifying facility's *other* (general/minor) permits, undercounting the correction
  (2,305 facilities extended instead of 2,381). Fixed by reading `ICIS_FACILITIES` a
  second, unrestricted time inside step 01.
- **Verified:** the new panel — `06_facility_month_panel_major_individual_effluent_2005_2025.csv`,
  rebuilt via a full 01→06 run — is **byte-for-byte identical** (full column diff,
  zero differences) to the retired step-07 output. Final counts unchanged: 2,381
  facilities extended, 1,749,567 operating / 143,205 not.
- `07_extend_facility_operating.R` and its README were deleted; the file
  `07_facility_month_panel_major_individual_operating_corrected_2005_2025.csv` remains
  on disk as an orphaned, superseded artifact (see `data/processed/README.md`).

**Update 2026-07-27: the correction's scanning/extension logic factored out into
`use_operating_proxies.R`.** What used to be step 01's Assumptions 10–13 (STEP 6B/6C,
written inline) is now one function, `use_operating_proxies()`, in its own file
(`code/03_panel_building/use_operating_proxies.R`), with an on/off switch per proxy
source (all seven default `TRUE`, reproducing this same correction exactly — verified
via an isolated side-by-side run of the old inline code and the new function on
identical input, `identical()` for every facility). Step 01's own header is now just
Assumptions 1–9 (unchanged) plus a single Assumption 10 pointing here; all the
measured evidence, root cause, and worked example above now live in
`use_operating_proxies.R`'s header instead of being duplicated in both places.
Purely a refactor — reasons: (1) letting a different mix of evidence be tried without
editing script 01 itself, (2) not duplicating a large block of explanation across two
files that were drifting out of sync with each other's edits.

**Update 2026-07-28: `USE_PROXIES` config flag added, then panel membership itself**
**changed from permit-dates-only to permit-window-overlap OR proxy evidence.** Two
separate changes, same day:
- A single `USE_PROXIES` flag (default `TRUE`) now feeds all seven `use_operating_
  proxies()` switches at once — `FALSE` skips the proxy scan entirely (permit-
  paperwork dates only, ~45% faster since no proxy source is read).
- Per request: previously, a facility whose permit-paperwork window didn't overlap
  2005–2025 was dropped from the panel entirely, before `use_operating_proxies()`
  ever ran — proxy evidence only widened an *already-admitted* facility's window,
  never granted admission on its own. Now a facility is admitted if EITHER its
  permit window overlaps 2005–2025 OR it has independent proxy evidence anywhere in
  that range (step 01's new Assumption 1B). Required restructuring the eligibility
  test to run on the raw, unclipped permit dates (not the panel-clipped ones, which
  would otherwise always "overlap" once clipped to the boundary) and moving the
  proxy scan earlier, against the full candidate population rather than an
  already-filtered one.
- A new third column, `FACILITY_OPERATING_PROXY_WINDOW`, exposes the proxy-only
  bounds `use_operating_proxies()` was already computing internally (previously
  discarded before returning, used only as a step toward the union). For a
  proxy-only-admitted facility, `FACILITY_OPERATING_PERMIT_WINDOW` correctly reads
  0 for every month (a genuine zero, not NA), and `FACILITY_OPERATING` collapses to
  exactly `FACILITY_OPERATING_PROXY_WINDOW`.
- **Verified** (full 01→06 rebuild): of 7,531 "ever major, ever individual"
  candidates, 7,514 have permit-window overlap, 16 are admitted solely via proxy
  evidence, 1 is dropped (neither) — final population 7,530 (was 7,514), panel rows
  1,897,560 (was 1,893,528; +4,032 = 16 × 252 months). Spot-checked facility
  `110000311485`: `FACILITY_OPERATING_PERMIT_WINDOW` 0/252 months,
  `FACILITY_OPERATING_PROXY_WINDOW` well-defined (243/252 operating), `FACILITY_
  OPERATING` matches it exactly everywhere. Re-running with `USE_PROXIES <- FALSE`
  correctly collapses membership back to permit-window-overlap only (7,514
  facilities, 0 admitted via proxy-only) — confirmed, then restored to `TRUE` and
  re-run so the on-disk panel reflects normal default behavior.
- Final panel is now 59 columns (was 58); `FACILITY_OPERATING_PROXY_WINDOW` is
  physical column 9, confirmed via `head -1`. `docs/codebook.md` renumbered
  columns 9–58 → 10–59 accordingly (these are literal physical CSV positions, not
  just documentation ordinals, so the renumbering reflects the real file, not a
  stylistic choice).

## Findings

### Effluent D80/D90/E90 counts, 2005–2025 (2026-07-14)
From the panel above: 2,694,316 ID-months across 121,708 distinct NPDES_IDs, all
252 months present. Raw target rows in window 43,317,821 → 41,451,812 after
latest-version de-dup (**1,866,009 resubmissions removed, 4.31%**). Totals:
D80 = 21,073,782 · D90 = 17,814,134 · E90 = 2,563,896 (sum = 41,451,812, matches
the de-duplicated count).

