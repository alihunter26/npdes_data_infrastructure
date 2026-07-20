# README — `04_add_violations.R`

*Step 4 of the facility-by-month panel build. Input: step-03 panel + raw
schedule/event violation files. Output: the panel with PS/CS/SE violation counts.*

## Overview

Attaches per-facility-month counts of three violation types: **permit-schedule (PS)**,
**compliance-schedule (CS)**, and **single-event (SE)**.

> **Effluent (DMR) violations are no longer added here.** The TSS effluent columns
> (`N_TSS_EFF_VIOLATIONS`, `N_TSS_EFF_D90/D80/E90`) moved to
> [`06_add_effluent_violations.R`](06_add_effluent_violations.md), which now owns all
> effluent-violation columns. The final panel is unchanged; only the step that adds
> those columns moved. As a result, step 04 no longer streams the ~16 GB effluent file
> and no longer needs `python3`/`unzip`.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. ☒ All data publicly available.

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `data/processed/03_..._naics_sic_2005_2025.csv` | `.csv` | step-03 panel |
| `data/raw/npdes_downloads/NPDES_PS_VIOLATIONS.csv` | `.csv` | `NPDES_ID`, `NPDES_VIOLATION_ID`, `SCHEDULE_DATE` |
| `data/raw/npdes_downloads/NPDES_CS_VIOLATIONS.csv` | `.csv` | `NPDES_ID`, `NPDES_VIOLATION_ID`, `SCHEDULE_DATE` |
| `data/raw/npdes_downloads/NPDES_SE_VIOLATIONS.csv` | `.csv` | `NPDES_ID`, `NPDES_VIOLATION_ID`, `SINGLE_EVENT_VIOLATION_DATE`, `SINGLE_EVENT_END_DATE` |
| `ICIS_FACILITIES.csv` | `.csv` | crosswalk (`NPDES_ID`, `FACILITY_UIN`) |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| step-03 panel | input | facility × month | derived |
| PS/CS/SE violation files | input (raw) | violation | via ECHO |
| `data/processed/04_..._violations_2005_2025.csv` | **output** | facility × year × month | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `lubridate`.
- **Controlled randomness:** none.
- **Memory/runtime:** PS/CS/SE are small files; minutes on a laptop. `TODO:` OS/timing.

## Description of program

Rebuild the permit→facility crosswalk (identical to step 01); for each of PS/CS/SE,
date each violation, filter to the window, crosswalk to facilities, and count distinct
violation IDs per facility-month. Full-outer-merge the three count tables onto the
panel and fill absent cells with 0.

## Decisions and Assumptions

1. **Violation grain = `NPDES_VIOLATION_ID`.** Count **distinct** IDs, never raw rows
   (SE has rare repeated IDs).
2. **Date = when the violation occurred** (PI guidance):
   - PS & CS: `SCHEDULE_DATE` (the missed-milestone due date; 100% present). Deliberately
     **not** `RNC_DETECTION_DATE` (EPA detection timing, ~54–61% blank).
   - SE: `SINGLE_EVENT_VIOLATION_DATE` (start; 100% present). `SINGLE_EVENT_END_DATE` is
     ignored; the violation is placed in the month it began (mirrors step 02's begin-date rule).
3. **Routed by `NPDES_ID` via the step-01 crosswalk** (`FACILITY_UIN` else `NPDES_ID`).
   A violation on **any** permit resolving to the facility is counted (PI guidance:
   "all permits at facility").
4. **The panel defines the observation set** — left-join; facility-months with no
   violation of a kind get **0**, not NA.

**Filters / drops:** window 2005–2025; rows with unparseable dates dropped (PS/CS 100%
parseable, SE ~100%); inner-join to the crosswalk drops unroutable `NPDES_ID`s. Tables
merged via `Reduce(..., all = TRUE)` (full outer); NA → `0L`.

**Hardcoded parameters:** `YEAR_MIN = 2005`, `YEAR_MAX = 2025`.

## Output columns (3)

`N_PS_VIOLATIONS`, `N_CS_VIOLATIONS`, `N_SE_VIOLATIONS` (integer counts).

## Instructions to run

```bash
Rscript "scripts/build panel/04_add_violations.R"
```
Run **after** step 03.

## Notes / edge cases

- Placement uses violation timing, not EPA detection timing (assumption 2).
- All effluent-violation columns (the TSS subset **and** the all-parameter D80/D90/E90
  counts) are now added in step 06 — see its README.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
