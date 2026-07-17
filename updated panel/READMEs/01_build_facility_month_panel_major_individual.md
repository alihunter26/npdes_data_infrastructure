# README — `01_build_facility_month_panel_major_individual.R`

** verified by Ali 7/17 **

*Step 1 of the facility-by-month panel build. Input: raw ICIS-NPDES permit &
facility files. Output: the base facility × month spine with facility attributes.*

## Overview

This script constructs the **unbalanced facility-by-month spine** (Jan 2005 – Dec
2025) that every later step attaches to. A facility is included if it was ever linked
to at least one **individual** (`NPD`) permit that was flagged **major** at any point
in its permit history. Each qualifying facility contributes one row per calendar month
between its earliest permit opening and latest permit closing (clipped to the panel
window). No behavioral variables are added here — only the spine and time-invariant
facility attributes.

## Data Availability and Provenance Statements

All inputs are EPA ECHO / ICIS-NPDES national bulk data files
(<https://echo.epa.gov/tools/data-downloads>), U.S. Government works in the public
domain. `TODO:` record download date / ECHO refresh version.

- **Statement about rights:** the author has legitimate access; the data are public
  and redistributable. `TODO:` confirm in `LICENSE.txt`.
- **Summary of availability:** ☒ All data are publicly available.

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `data/raw/npdes_downloads/ICIS_PERMITS.csv` | `.csv` | `EXTERNAL_PERMIT_NMBR`, `PERMIT_TYPE_CODE`, `MAJOR_MINOR_STATUS_FLAG`, `EFFECTIVE_DATE`, `ISSUE_DATE`, `ORIGINAL_ISSUE_DATE`, `EXPIRATION_DATE`, `TERMINATION_DATE`, `RETIREMENT_DATE` (one row per permit **version**) |
| `data/raw/npdes_downloads/ICIS_FACILITIES.csv` | `.csv` | `NPDES_ID`, `FACILITY_UIN`, `FACILITY_TYPE_CODE`, `FACILITY_NAME`, `LOCATION_ADDRESS`, `CITY`, `STATE_CODE`, `ZIP`, `COUNTY_CODE`, `GEOCODE_LATITUDE`, `GEOCODE_LONGITUDE` (one row per `NPDES_ID`) |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `ICIS_PERMITS.csv` | input (raw) | permit-version | via ECHO |
| `ICIS_FACILITIES.csv` | input (raw) | permit / facility | via ECHO |
| `data/processed/facility_month_panel_major_individual_2005_2025.csv` | **output** | facility × year × month | derived |

> ⚠️ **Filename mismatch:** this script writes the output **without** a numeric
> prefix (`facility_month_panel_major_individual_2005_2025.csv`,
> `01_...R:84`), but step 02 reads it **with** an `01_` prefix
> (`01_facility_month_panel_major_individual_2005_2025.csv`). Rename 01's output (or
> change its `OUT_PATH`) before running 02. Unresolved — see the folder index.

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `lubridate`.
- **Controlled randomness:** none — no PRNG, no seed.
- **Memory/runtime:** inputs are ~1–2 M rows; runs in minutes on a laptop.
  `TODO:` exact OS / timing.

## Description of program

1. Read `ICIS_PERMITS`; derive each permit-version's opening and closing dates and
   its major flag; keep only individual (`NPD`) permits.
2. Collapse permit-versions to one row per permit (`NPDES_ID`).
3. Crosswalk permits to facilities via `ICIS_FACILITIES`; apply the blank-UIN fallback.
4. Determine facility eligibility and each facility's active window.
5. Build the complete facility × month grid, clip to the panel window, and attach the
   time-invariant facility attributes.
6. Write the spine to `data/processed/`.

## Decisions and Assumptions

The script states eight numbered assumptions:

1. **Ever-major, not always-major.** A facility qualifies if *any* linked individual
   permit bore the `M` (major) flag in *any* version — not a requirement that it was
   always major. (875 facilities shift beween major and minor at some point in time period -- they are all included)
2. **Permit window = earliest open × latest close.** Opening date = earliest
   non-missing of {`EFFECTIVE_DATE`, `ISSUE_DATE`, `ORIGINAL_ISSUE_DATE`}; closing
   date = latest non-missing of {`EXPIRATION_DATE`, `TERMINATION_DATE`,
   `RETIREMENT_DATE`}. Widest defensible window.
3. **No closing date ⇒ still active.** A permit-version with all three closing fields
   missing is treated as active through `WINDOW_END` (2025-12-01).
4. **Facility window = union across *all* its individual permits** (not just the major
   ones): earliest opening to latest closing across every linked individual permit.
5. **Blank `FACILITY_UIN` ⇒ use `NPDES_ID`** as the facility identifier. No rows are
   silently dropped; such facilities appear with `FACILITY_UIN` = the `NPDES_ID` value. (all rows without FACILITY_UIN get filtered out later -- not a large issue)
6. **Multiple permits per facility ⇒ semicolon list.** All individual `NPDES_ID`s ever
   linked to a qualifying facility are `paste(sort(unique(...)), collapse = "; ")` into
   one string; the facility-month remains a single row.
7. **Snapshot (time-invariant) attributes.** `FACILITY_TYPE_CODE`, `FACILITY_NAME`,
   address, county, lat/long come from one snapshot per facility (ICIS carries no
   history). When a facility has >1 linked permit, the record with a non-blank
   `FACILITY_NAME` is preferred; that one row is broadcast to all the facility's
   months. Real location changes over time are **not** tracked.
8. **ZIP kept as text**, padded to 5 characters with leading zeros (`sprintf("%05s", ZIP)`).

**Sample / filter definitions**
- *Major:* `MAJOR_MINOR_STATUS_FLAG == "M"` at least once in the permit's version history.
- *Individual:* `PERMIT_TYPE_CODE == "NPD"`.
- *Window:* 2005–2025 (`WINDOW_START = 2005-01-01`, `WINDOW_END = 2025-12-01`).
- *Geography:* excludes AK, HI, PR, VI, GU, AS, MP → 48 continental states + DC only.

**Deduplication / collapse**
- Permit-versions → permit (`.by = NPDES_ID`): `permit_open = min(open)`,
  `permit_close = max(close)` (or `WINDOW_END` if none), `ever_major = any(is_major)`.
- Permit → facility: `facility_open = min(permit_open)`, `facility_close =
  max(permit_close)`, `facility_ever_major = any(ever_major)`; keep only
  `facility_ever_major`.
- Spine via `CJ(facilities, months)`; join attributes (fills NA outside the active
  window); clip with `pmax(open, WINDOW_START)` / `pmin(close, WINDOW_END)`, drop if start > end.

**Rows dropped (and why)** — all reported in the run log, none silent:
- Permit-versions with no usable opening date (cannot be placed in time).
- Facilities with no overlap with 2005–2025 after clipping.
- Non-individual or never-major permits; facilities outside the 48+DC scope.

**Hardcoded parameters:** `YEAR_MIN = 2005`, `YEAR_MAX = 2025`; ZIP format `"%05s"`;
state exclusion set `{AK, HI, PR, VI, GU, AS, MP}`.

## Output columns (15)

`FACILITY_UIN`, `YEAR`, `MONTH`, `NPDES_ID` (semicolon list of linked individual
permits), `MAJOR_MINOR_FLAG` (semicolon list), `PERMIT_TYPE_FLAG`, `FACILITY_TYPE_CODE`,
`FACILITY_NAME`, `LOCATION_ADDRESS`, `CITY`, `STATE_CODE`, `ZIP`, `COUNTY_CODE`,
`FAC_LAT`, `FAC_LONG`.

## Instructions to run

```bash
Rscript "updated panel/01_build_facility_month_panel_major_individual.R"
```
First step — has no upstream dependency. **Rename its output to add the `01_` prefix
before running step 02** (see the mismatch note above).

## Notes / edge cases

- A facility may enter minor, become major once (qualifies), then leave — all its
  months are kept (ever-major).
- A permit with no opening date is dropped; with no closing date, treated as active
  through Dec 2025.
- The panel is **unbalanced**: each facility spans only its own active window.

## References

U.S. Environmental Protection Agency, Enforcement and Compliance History Online
(ECHO), ICIS-NPDES national data downloads. <https://echo.epa.gov/tools/data-downloads>.
Accessed `TODO`.
