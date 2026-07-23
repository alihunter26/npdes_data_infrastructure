# README — `01_build_facility_month_panel_major_individual.R`

** verified by Ali 7/17 **

**updated 7/21:** the panel is now **balanced**, not unbalanced (see Overview and
Assumption 9 below) — every qualifying facility now gets a row for **every** month
2005–2025, with a new `FACILITY_OPERATING` flag marking which rows fall inside vs.
outside its own active window. This lets downstream steps (02/04/05/06) tell a true
zero ("operating, no events") apart from an undefined one ("not operating, count is
NA") — see those scripts' READMEs.

**Bug found and fixed 7/21:** the spine-building `CJ()` call was passed the full,
non-unique `all_months$YEAR`/`$MONTH` columns (252 values each, not 21/12 distinct
values) instead of their unique values. `CJ()` does not deduplicate its inputs, so this
squared the year-month dimension (252×252 instead of 21×12), attempting to build
~477M rows instead of the correct ~1.89M and exceeding R's vector memory limit. Fixed
to use `unique(all_months$YEAR)` / `unique(all_months$MONTH)`. Row/facility counts are
unaffected (7,511 facilities, 1,892,772 rows, matching every count reported elsewhere
in this project) — the bug only affected the (never-successfully-run) balanced-panel
version of this script, not any panel actually delivered before 7/21.

*Step 1 of the facility-by-month panel build. Input: raw ICIS-NPDES permit &
facility files. Output: the base facility × month spine with facility attributes.*

## Overview

This script constructs the **balanced facility-by-month spine** (Jan 2005 – Dec 2025)
that every later step attaches to. A facility is included if it was ever linked to at
least one **individual** (`NPD`) permit that was flagged **major** at any point in its
permit history. Every qualifying facility contributes a row for **every** calendar
month 2005–2025 — not just the months it was actually open — and each row carries a
`FACILITY_OPERATING` flag (1/0) marking whether that month falls inside the facility's
own earliest-open/latest-close window (clipped to the panel window). No behavioral
variables are added here — only the spine, the operating flag, and time-invariant
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
| `data/processed/01_facility_month_panel_major_individual_2005_2025.csv` | **output** | facility × year × month | derived |

> **Resolved 7/21:** the filename mismatch previously noted here (this script writing
> without an `01_` prefix while step 02 expected one) no longer exists — the script's
> `OUT_PATH` already includes the `01_` prefix. No manual rename needed between steps
> 01 and 02.

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

The script states nine numbered assumptions:

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
   one string; the facility-month remains a single row. **Checked 7/22:** 427 of the
   7,511 facilities (5.68%) have more than one `NPDES_ID` in this field; the max is 7
   (one Nevada facility, `FACILITY_UIN 110059864179`). Because these are joined into a
   single string rather than separate rows, counting them requires splitting on `"; "`
   — grouping directly on `FACILITY_UIN` to count distinct `NPDES_ID`s (as if one row
   per permit) will silently return 0, since this collapse already happened upstream.
7. **Snapshot (time-invariant) attributes.** `FACILITY_TYPE_CODE`, `FACILITY_NAME`,
   address, county, lat/long come from one snapshot per facility (ICIS carries no
   history). When a facility has >1 linked permit, the record with a non-blank
   `FACILITY_NAME` is preferred; that one row is broadcast to all the facility's
   months. Real location changes over time are **not** tracked.
8. **ZIP kept as text**, padded to 5 characters with leading zeros (`sprintf("%05s", ZIP)`).
9. **`FACILITY_OPERATING` = 1 iff the calendar month falls within the facility's own
   `[spine_start_month, spine_end_month]`** (the same earliest-open/latest-close window,
   unioned across permits and clipped to the panel window, used to decide facility
   eligibility in Assumptions 2–4). This is not a new business rule — it exposes a value
   already implicit in the spine construction, so downstream scripts (02/04/05/06) can
   tell "operating, zero events" (`FACILITY_OPERATING=1`, count=0) apart from "not
   operating, undefined" (`FACILITY_OPERATING=0`, count=NA). Facility ATTRIBUTE columns
   (name, address, `NPDES_ID` list, …) are **not** masked by this flag — they keep
   broadcasting the one representative snapshot across every month (Assumption 7).

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
- Facility open/close clipped with `pmax(open, WINDOW_START)` / `pmin(close, WINDOW_END)`;
  a facility is **dropped entirely** if its clipped window is empty (`start > end`, i.e.
  no overlap with 2005–2025 at all) — this is the only place a facility's row *count*
  is affected by its window.
- Spine via `CJ(facility_id = unique(...), YEAR = unique(all_months$YEAR), MONTH =
  unique(all_months$MONTH))` — every surviving facility × **every** month 2005–2025
  (**balanced**, not clipped per facility; see Assumption 9). `FACILITY_OPERATING` is
  then computed per row from each facility's own window; it does not change which
  rows exist, only how a row is labeled.

**Rows dropped (and why)** — all reported in the run log, none silent:
- Permit-versions with no usable opening date (cannot be placed in time).
- Facilities whose window has zero overlap with 2005–2025 even after clipping.
- Non-individual or never-major permits; facilities outside the 48+DC scope.

**Hardcoded parameters:** `YEAR_MIN = 2005`, `YEAR_MAX = 2025`; ZIP format `"%05s"`;
state exclusion set `{AK, HI, PR, VI, GU, AS, MP}`.

## Output columns (16)

`FACILITY_UIN`, `YEAR`, `MONTH`, `NPDES_ID` (semicolon list of linked individual
permits), `MAJOR_MINOR_FLAG` (semicolon list), `PERMIT_TYPE_FLAG`, `FACILITY_OPERATING`
(1/0; see Assumption 9), `FACILITY_TYPE_CODE`, `FACILITY_NAME`, `LOCATION_ADDRESS`,
`CITY`, `STATE_CODE`, `ZIP`, `COUNTY_CODE`, `FAC_LAT`, `FAC_LONG`.

## Instructions to run

```bash
Rscript "code/03_panel_building/01_build_facility_month_panel_major_individual.R"
```
First step — has no upstream dependency. No manual rename needed before running step
02 (see the resolved filename note above).

## Notes / edge cases

- A facility may enter minor, become major once (qualifies), then leave — all its
  months are kept (ever-major).
- A permit with no opening date is dropped; with no closing date, treated as active
  through Dec 2025.
- The panel is **balanced**: every qualifying facility has a row for every month
  2005–2025 (252 months each), regardless of when it actually held an active permit.
  `FACILITY_OPERATING` (Assumption 9) distinguishes months inside vs. outside the
  facility's own active window — as of 7/21, 1,639,744 rows are operating and 253,028
  are not, out of 1,892,772 total.
- Downstream, a real recorded event (inspection, violation, enforcement action,
  effluent violation) always wins over `FACILITY_OPERATING`: a month can show
  `FACILITY_OPERATING == 0` and still carry a real, non-NA count if one was actually
  recorded (e.g. administrative lag near a permit boundary) — see 02/04/05/06's
  READMEs. `FACILITY_OPERATING == 0` only guarantees NA when there is *also* no
  matched event.
- **Gotcha (found 7/22): `FACILITY_UIN` reads in as `integer64`** (via `fread`).
  `data.table`'s `by =` grouping on an `integer64` column silently breaks (returns
  wrong/`NA` groups) unless the `bit64` package is loaded — this produced a bogus "0
  facilities with multiple NPDES_IDs" result before being caught. Cast to character
  first (`colClasses = c(FACILITY_UIN = "character")` in `fread`, or `as.character()`)
  before grouping on it.

## References

U.S. Environmental Protection Agency, Enforcement and Compliance History Online
(ECHO), ICIS-NPDES national data downloads. <https://echo.epa.gov/tools/data-downloads>.
Accessed `TODO`.
