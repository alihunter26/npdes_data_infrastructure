# README — `03_add_naics_sic.R`

** verified by Ali 7/17 **

question: how many have multiple NAICS or SIC? script currently just does primary code -- should it include all? 

*Step 3 of the facility-by-month panel build. Input: step-02 panel + raw NAICS/SIC.
Output: the panel with one NAICS and one SIC code per facility.*

## Overview

Attaches each facility's **industry codes** (NAICS and SIC) as time-invariant
attributes, broadcast across all of the facility's months.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. ☒ All data publicly available.

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `data/processed/02_facility_month_panel_major_individual_inspections_2005_2025.csv` | `.csv` | `FACILITY_UIN`, `NPDES_ID` (semicolon list) |
| `data/raw/npdes_downloads/NPDES_NAICS.csv` | `.csv` | `NPDES_ID`, `NAICS_CODE`, `PRIMARY_INDICATOR_FLAG` |
| `data/raw/npdes_downloads/NPDES_SICS.csv` | `.csv` | `NPDES_ID`, `SIC_CODE`, `PRIMARY_INDICATOR_FLAG` |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| step-02 panel | input | facility × month | derived |
| `NPDES_NAICS.csv`, `NPDES_SICS.csv` | input (raw) | permit × code | via ECHO |
| `data/processed/03_facility_month_panel_major_individual_naics_sic_2005_2025.csv` | **output** | facility × year × month | derived |

## Computational Requirements

- **R** 4.4.2. Package: `data.table` (only). No `lubridate` (no dates handled here).
- **Controlled randomness:** none. **Memory/runtime:** trivial; seconds–minutes. `TODO:` OS/timing.

## Description of program

Split each facility's semicolon-separated `NPDES_ID` list back into individual permits;
pick one primary code per permit from each code file; recombine to one distinct,
sorted, semicolon-joined code string per facility; left-join onto the panel.

## Decisions and Assumptions

1. **Industry code is time-invariant.** The code files carry no date/version, so a
   facility's code is a fixed attribute broadcast to all its months (unlike the
   month-varying inspection counts).
2. **Codes key to the permit, the panel to the facility.** The facility's `NPDES_ID`
   column is a semicolon list; it is split, each permit is looked up, and results are
   recombined to the facility. Codes come only from permits the panel already assigned
   to the facility — never from other permits at the site.
3. **One "primary" code per permit.** Keep the row flagged `PRIMARY_INDICATOR_FLAG ==
   "Y"`, falling back to the first listed if none is flagged (same rule as
   `04_build_permit_panel_major_continuous.R`, now in `../EIL Summer/build/`).
4. **Multi-permit facilities ⇒ semicolon list** of distinct codes across the facility's
   permits (matching step 01's `NPDES_ID` formatting).
5. **"Missing" = no row in the code file** ⇒ blank code (`""`, not NA), matching the
   project's missingness convention. NAICS coverage is sparse; SIC is near-complete for
   the major population.
6. **The panel defines the observation set** — left-join, no rows added or dropped.

**Helper logic:** `primary_code()` sorts by `PRIMARY_INDICATOR_FLAG != "Y"` and keeps
the first row per permit; `join_distinct()` takes the distinct non-blank codes across a
facility's permits, sorts, and pastes with `"; "` (empty string if none).

**Hardcoded parameters:** none — fully data-driven.

## Output columns (2)

`NAICS_CODE`, `SIC_CODE` (text; may be blank; semicolon-joined for multi-permit facilities).

## Instructions to run

```bash
Rscript "updated panel/03_add_naics_sic.R"
```
Run **after** step 02.

## Notes / edge cases

- A facility whose permit never appears in a code file → blank code (`""`).
- `PRIMARY_INDICATOR_FLAG == "Y"` preferred; first row used when no primary is flagged.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
