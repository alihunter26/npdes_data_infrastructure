# `code/02_cleaning/` — shared cleaning helpers for the panel pipeline

** verified by Ali 7/27 **

**What's here:** primarily one file, [`cleaning_helpers.R`](cleaning_helpers.R)
(README: [`cleaning_helpers.md`](cleaning_helpers.md)), holding the pieces of
"cleaning" logic that used to be copy-pasted into every one of the six scripts in
`code/03_panel_building/` (`01` through `06`). Each of those scripts now sources this
file (via `CWA_ROOT`, right after it sources `_paths.R`) instead of carrying its own
local copy.

**Also here**:
[`build_effluent_violations_npdes_month_panel.R`](build_effluent_violations_npdes_month_panel.R)
— see "`build_effluent_violations_npdes_month_panel.R`" below.

## What moved here, and why

| Function | Replaces | Why it's here and not left duplicated |
|---|---|---|
| `rd(file, cols, raw_dir)` | An identical, word-for-word `fread()` wrapper defined separately in all six panel-building scripts | Guarantees every script reads raw CSVs the same way: only the requested columns, all forced to `character` so that ID-like fields (ZIP codes, facility IDs, ...) don't silently lose leading zeros to R's automatic type-guessing. |
| `build_facility_crosswalk(raw_dir)` | The permit → facility (`NPDES_ID` → `facility_id`) lookup table, rebuilt identically in `01` (as `fac_all`), `02`, `04`, `05`, and `06` (as `fac`/`xwalk`) | This is the single most safety-critical piece of shared logic in the pipeline: every raw data source (inspections, violations, enforcement, effluent) gets routed to a facility through this same table. Five near-identical copies is exactly the kind of duplication where one gets fixed and the others don't. |
| `coalesce_date_priority(dt, date_cols)` | The `fcoalesce(mdy(...), mdy(...), ...)` pattern used to pick a single event date from several candidate columns, in `01`'s own `event_months()` helper, and in `02`, `04`, `05`, `06` | Generic mechanic: "take the first of these columns that isn't blank." |
| `coalesce_date_extreme(dt, date_cols, which)` | The `pmin(mdy(...), ..., na.rm = TRUE)` / `pmax(...)` pattern used only in `01`, for a permit's opening/closing window | A *different* generic mechanic from the one above: "take the earliest (or latest) of whichever of these columns are actually filled in," used only when defining a permit's active window. |

**What deliberately did *not* move here:** the actual research decisions — e.g. *which*
three columns count as a permit's opening date, or what it means when a permit has no
closing date at all — are labeled, PI-guided assumptions that stay inline in
`code/03_panel_building/01_build_facility_month_panel_major_individual.R`, right next
to the comments that justify them. This module only holds the reusable mechanics
(*how* to combine date columns), never the domain-specific choices (*which* columns,
and what a missing value means). See that script's "LABELED ASSUMPTIONS" section.

## `build_effluent_violations_npdes_month_panel.R`

**Not** a shared helper function like everything above — it's a standalone,
executable script. Full
details: [`build_effluent_violations_npdes_month_panel.md`](build_effluent_violations_npdes_month_panel.md).

- **What it does:** reads EPA's raw effluent-violations file (`NPDES_EFF_VIOLATIONS.csv`,
  ~15.9 GB uncompressed, inside a zip in `data/raw/`) via DuckDB out-of-core, and
  condenses it into one row per (`NPDES_ID`, calendar month) with two count sets: all-
  parameter violation counts (`n_D80`/`n_D90`/`n_E90`) and a TSS/gross-effluent/monthly-
  average subset (`N_TSS_EFF_VIOLATIONS`, `N_TSS_EFF_D90`/`_D80`/`_E90`). Both are
  computed in a single pass over the raw file.
- **Output:** `data/processed/effluent_violations_npdes_month_panel_2005_2025.csv`.
- **Genuine prerequisite, not an optional step.** `01_build_facility_month_panel_
  major_individual.R` and `06_add_effluent_violations.R` both read its output, so it
  must run *before step 01* — not just before step 06. `run_all.R` runs it
  automatically if that output file isn't already on disk (~15-20 min if it has to
  rebuild).
- **Not sourced by, and doesn't source, `cleaning_helpers.R`** — it uses its own
  DuckDB pipeline rather than `rd()`/`build_facility_crosswalk()`, since it never
  needs to route rows to a facility (it stays keyed by `NPDES_ID`, not `facility_id`,
  until `01`/`06` join it in).

## Conventions

- Every function assumes the calling script has already run `library(data.table)`
  (and `library(lubridate)`, for the date functions) — this file only *defines*
  functions, so it doesn't need those packages loaded at the time it's sourced, only
  by the time its functions are actually called.
- No cleaning here for `code/dmr/`'s two filter pipelines (the DMR row-filter chain
  or the FY2025 mini-pipeline) — those are separate, standalone pipelines and out
  of scope for this extraction.
