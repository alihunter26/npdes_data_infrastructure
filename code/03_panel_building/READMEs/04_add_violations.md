# README — `04_add_violations.R`

** verified by Ali  7/28 **

*Step 4 of the facility-by-month panel build. Input: step-03 panel + raw
schedule/event violation files. Output: the panel with PS/CS/SE violation counts.*

## Overview

Attaches per-facility-month counts of three violation types: **permit-schedule (PS)**,
**compliance-schedule (CS)**, and **single-event (SE)**. Effluent violations are added in a separate file (step 06) because of the much larger file size.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. ☒ All data publicly available.

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `data/processed/03_..._naics_sic_2005_2025.csv` | `.csv` | step-03 panel (incl. `FACILITY_OPERATING`, passed through from step 01) |
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
violation IDs per facility-month. Full-outer-merge the three count tables (0-filled
among themselves — see Assumption 4) onto the panel; a facility-month absent from all
three gets `0` if `FACILITY_OPERATING == 1` or `NA` if `FACILITY_OPERATING == 0`, but a
month with a real matched violation keeps that value regardless of the flag.

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
4. **The panel defines the observation set; a real match always wins over
   `FACILITY_OPERATING`.** Left-join; a facility-month with no violation of a kind
   gets **0** only while the facility was actually operating (`FACILITY_OPERATING
   == 1`, from step 01); if it wasn't operating and nothing matched, it gets **NA**
   — undefined, not zero. But if a real violation *did* match, its value is kept
   even when `FACILITY_OPERATING == 0` (e.g. administrative lag near a permit
   boundary) — NA never overwrites a real count.

**Filters / drops:** window 2005–2025; rows with unparseable dates dropped (PS/CS 100%
parseable, SE ~100%); inner-join to the crosswalk drops unroutable `NPDES_ID`s. Tables
merged via `Reduce(..., all = TRUE)` (full outer) — NA → `0L` at this stage (combining
the three violation sources, unrelated to operating status). After joining onto the
panel: NA → `0L` if operating, NA → `NA` (unchanged) if not operating.

**Hardcoded parameters:** `YEAR_MIN = 2005`, `YEAR_MAX = 2025`.

## Output columns (3)

`N_PS_VIOLATIONS`, `N_CS_VIOLATIONS`, `N_SE_VIOLATIONS` (integer counts).

## Instructions to run

```bash
Rscript "code/03_panel_building/04_add_violations.R"
```
Run **after** step 03.

## Notes / edge cases

- Placement uses violation timing, not EPA detection timing (assumption 2).
- All effluent-violation columns (the TSS subset **and** the all-parameter D80/D90/E90
  counts) are now added in step 06 — see its README.
- Run-log sums/identities use `na.rm = TRUE` since non-operating/no-data rows are now
  legitimately NA.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
