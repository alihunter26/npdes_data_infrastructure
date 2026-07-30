# README — `summarize_panel.R`

*A QA check for a **built** facility-month panel, not a raw source file. Input: one of
the `data/processed/0*_facility_month_panel*.csv` files. Output: a console report + a
timestamped 5-sheet Excel workbook.*

## Overview

Face-validity / realism check for a facility-month panel already built by
`code/03_panel_building/`. The purpose is explicitly **not** to produce findings but to
catch panel-construction bugs — bad merges, duplicated keys, impossible values,
coverage gaps — before the panel is trusted for analysis. Every number it reports is
one a human can eyeball and ask "is that plausible?" Works on any of the `01`–`06`
panels; the numeric-summary and consistency-check sections auto-adapt to whichever
columns are actually present in the file passed to it.

## Data Availability and Provenance Statements

Not applicable in the usual sense — this script's input is **derived data** (the built
panel), not a raw EPA download. See `code/03_panel_building/READMEs/` for the raw
source provenance of the panel itself.

### Details on each data source

| File | Notes |
|---|---|
| `data/processed/0[0-9]_facility_month_panel*.csv` | Default: the highest-numbered match by filename in `data/processed/` (i.e. the most-built panel). Can be overridden by passing a filename or path as the first CLI argument. |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| the panel CSV (see above) | input (derived) | facility × year × month | derived, from `code/03_panel_building/` |
| `output/panel_summary_<panel_name>_<timestamp>.xlsx` | **output** | 5 sheets: `1_structure`, `2a_year`, `2b_missing`, `3_numeric`, `4_consistency` | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `openxlsx`.
- **Controlled randomness:** none.
- **Memory/runtime:** reads the whole panel into memory with `fread` (the current `06`
  panel is a few hundred MB — small relative to the multi-GB raw files elsewhere in
  this repo). `TODO:` OS/timing.

## Description of program

Loads the target panel whole. Columns in `ID_COLS` (identifiers, geo, ZIP/county/state
codes, industry codes) are excluded from the numeric-summary and consistency sections
— a mean ZIP or mean latitude is meaningless; everything else numeric is treated as a
count/dollar statistic. Four sections, each written to its own sheet as well as
printed to the console:

1. **Panel structure** — row count, distinct `FACILITY_UIN`/`NPDES_ID`, year/month
   range, and the count of duplicate `(FACILITY_UIN, YEAR, MONTH)` rows (the panel's
   key — should be zero).
2. **Coverage** — rows and distinct facilities per year; percent missing per column
   (console shows the top 15 by missingness).
3. **Numeric summary** — per stat column: N, mean, SD, min, P50, P90, P99, max,
   percent nonzero, percent missing.
4. **Consistency checks** — see Decisions and Assumptions below.

## Decisions and Assumptions

1. **`check_sum()` verifies component-sum identities** — total column equals the sum
   of its listed parts, e.g. `N_AFR == N_STATE_AFR + N_EPA_AFR`,
   `N_JDC == N_STATE_JDC + N_EPA_JDC`, `N_INFORMAL_ACTIONS == N_OFFICIAL_INFORMAL +
   N_UNOFFICIAL_INFORMAL`. **Fixed 2026-07-30:** this check previously referenced
   `N_FORMAL_ACTIONS`/`N_STATE_FORMAL`/`N_EPA_FORMAL` — columns that never existed in
   the built panel (there is no single state/EPA split of *all* formal actions; agency
   is broken out separately within `N_AFR` and within `N_JDC` — see Assumption 2 in
   `code/03_panel_building/READMEs/05_add_enforcement.md`). Because `check_sum()` is
   guarded by a column-existence check, the stale call silently no-op'd on every run
   instead of erroring, giving false confidence the identity had been verified. Now
   split into the two real identities above, matching what `05_add_enforcement.R`'s own
   run log already verifies.
2. **`check_implies()` verifies a penalty implies a matching formal action** — if
   `N_FED_PENALTY_ASSESSED > 0` then `N_EPA_FORMAL > 0` (and the state equivalent). Both
   checks silently no-op the same way if their columns aren't present in the panel
   passed in.
3. **No-negative-values check** scans every stat column (not just the ones named
   above) and fails if *any* count/dollar column ever goes negative.
4. **Every `check_*` call is guarded by a column-existence test**, so running this
   against an early-stage panel (e.g. `01_facility_month_panel_major_individual.csv`,
   before enforcement/effluent columns exist) is safe — those checks are simply
   skipped rather than erroring. This is also exactly the mechanism that let the stale
   check in point 1 hide for as long as it did; a guarded check that silently skips
   gives no signal that it *didn't* run.

## Output columns

- **`1_structure`:** `Metric`, `Value` — 7 rows (row count, unique `FACILITY_UIN`,
  unique `NPDES_ID`, year range, month range, duplicate-key row count, key-uniqueness
  verdict).
- **`2a_year`:** `YEAR`, `Rows`, `Facilities` — one row per calendar year.
- **`2b_missing`:** `Column`, `Pct_Missing` — one row per column, sorted descending.
- **`3_numeric`:** `Variable`, `N`, `Mean`, `SD`, `Min`, `P50`, `P90`, `P99`, `Max`,
  `Pct_Nonzero`, `Pct_Missing` — one row per stat column.
- **`4_consistency`:** `Check`, `Result` (`PASS`/`FAIL`), `Detail` — one row per
  identity/implication/negativity check that had its required columns present.

## Instructions to run

```bash
Rscript code/summary/summarize_panel.R [panel_filename]
#   [panel_filename]: a file in data/processed (default: the newest
#                      0*_facility_month_panel*.csv). Numeric-summary and
#                      consistency checks auto-adapt to whichever columns are present.
```
Run any time after at least step 01 of `code/03_panel_building/` has produced a panel
file; run again after each later step to see the new columns' checks come online.

## Notes / edge cases

- A "PASS" for a consistency check with an empty `Detail` is expected — `Detail` is
  only populated to describe *how many rows* failed, or left blank when the check
  itself was never run (columns absent). Don't mistake a guarded skip for a pass; check
  that the row for a given identity is actually present in `4_consistency` at all.
- The "highest-numbered by filename" default means running this without an argument
  after both a `06_*` and a stray `07_*` file exist in `data/processed/` will pick the
  `07_*` file even if it's an orphaned, non-regenerable artifact (see
  `data/processed/README.md`) — pass the filename explicitly if you want the current
  canonical panel specifically.

## References

Panel construction: `code/03_panel_building/README.md` and its per-step `READMEs/`.
