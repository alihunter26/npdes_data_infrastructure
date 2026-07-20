# README — `02_add_inspections.R`

** verified by Ali 7/17 **

*Step 2 of the facility-by-month panel build. Input: step-01 spine + raw inspections.
Output: the panel with per-facility-month inspection counts.*

## Overview

Attaches counts of compliance **inspections** — by monitoring type and by conductor
(state vs. EPA) — to each facility-month of the step-01 spine.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. ☒ All data publicly available.

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `data/processed/01_facility_month_panel_major_individual_2005_2025.csv` | `.csv` | `FACILITY_UIN`, `YEAR`, `MONTH` (step-01 spine) |
| `data/raw/npdes_downloads/ICIS_FACILITIES.csv` | `.csv` | `NPDES_ID`, `FACILITY_UIN` (to rebuild the crosswalk) |
| `data/raw/npdes_downloads/NPDES_INSPECTIONS.csv` | `.csv` | `NPDES_ID`, `ACTIVITY_ID`, `COMP_MONITOR_TYPE_CODE`, `STATE_EPA_FLAG`, `ACTUAL_BEGIN_DATE`, `ACTUAL_END_DATE` |

> ⚠️ This script reads `01_facility_month_panel_major_individual_2005_2025.csv`
> (with the `01_` prefix), but step 01 writes the file **without** it. Rename 01's
> output before running this step. See the folder index.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| step-01 panel | input | facility × month | derived |
| `NPDES_INSPECTIONS.csv` | input (raw) | inspection-component | via ECHO |
| `data/processed/02_facility_month_panel_major_individual_inspections_2005_2025.csv` | **output** | facility × year × month | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `lubridate`.
- **Controlled randomness:** none.
- **Memory/runtime:** ~1.9 M inspection rows; minutes on a laptop. `TODO:` OS/timing.

## Description of program

Rebuild the permit→facility crosswalk (identical to step 01); parse inspection dates
and place each in a month; count distinct inspections per facility-month overall, by
type, and by conductor; left-join onto the spine, filling absent months with 0.

## Decisions and Assumptions

1. **Inspection grain = `ACTIVITY_ID`.** The raw file has multiple rows per inspection
   (one per monitoring component). Counts use **distinct `ACTIVITY_ID`**, never raw
   rows (raw rows would over-count multi-component visits by ~6%).
2. **Type counts can overlap.** One inspection may carry several monitoring types, so
   `N_CEI + N_ROS + N_SA1 + N_AU1` may exceed `N_INSPECTIONS_TOTAL`. These are **not** a
   partition, and rarer types are not broken out.
3. **Conductor is one per inspection and *does* partition the total:**
   `N_STATE_INSPECTIONS + N_EPA_INSPECTIONS == N_INSPECTIONS_TOTAL` (verified in the run log).
4. **Routed by `NPDES_ID` via the step-01 crosswalk** (`FACILITY_UIN` if present, else
   `NPDES_ID`). `REGISTRY_ID` is deliberately *not* used (it can disagree with
   `FACILITY_UIN` and cannot reproduce the fallback).
5. **The panel defines the observation set.** Left-join onto the spine; inspections in
   facility-months not in the panel (pre-entry, post-exit, non-major months) are
   excluded. Facility-months with no inspection get **0**, not NA.
6. **Inspection date = begin date.** `fcoalesce(mdy(ACTUAL_BEGIN_DATE),
   mdy(ACTUAL_END_DATE))`; rows with neither date are dropped.

**Monitoring-type mapping** (`TYPE_CODES`): `N_CEI`←`"CEI"` (Compliance Evaluation
Inspection), `N_ROS`←`"ROS"` (Reconnaissance w/o Sampling), `N_SA1`←`"SA1"` (Sampling),
`N_AU1`←`"AU1"` (Audit).

**Filters / drops:** window 2005–2025 (`YEAR_MIN`/`YEAR_MAX`); inner-join to the
crosswalk drops inspections whose `NPDES_ID` isn't a qualifying permit; rows with no
parseable date are dropped. Empty facility-months are filled with `0L`.

**Hardcoded parameters:** `YEAR_MIN = 2005`, `YEAR_MAX = 2025`;
`TYPE_CODES = c(N_CEI="CEI", N_ROS="ROS", N_SA1="SA1", N_AU1="AU1")`.

## Output columns (7)

`N_INSPECTIONS_TOTAL`, `N_CEI`, `N_ROS`, `N_SA1`, `N_AU1`, `N_STATE_INSPECTIONS`,
`N_EPA_INSPECTIONS` (integer counts).

| Code | Description |
|------|-------------|
| CEI | Evaluation |
| ROS | Reconnaissance without Sampling |
| SA1 | Sampling |
| AU1 | Audit |

## Instructions to run

```bash
Rscript "scripts/build panel/02_add_inspections.R"
```
Run **after** step 01 (and after resolving the `01_` filename mismatch).

## Notes / edge cases

- An inspection carrying both `CEI` and `SA1` is counted in both columns.
- Run-log identity check: `N_STATE + N_EPA == N_TOTAL` (catches missing conductor flags).

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
