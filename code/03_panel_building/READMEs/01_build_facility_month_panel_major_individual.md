# README — `01_build_facility_month_panel_major_individual.R`

** verified by Ali 7/17 **

**updated 7/21:** the panel is now **balanced**, not unbalanced (see Overview and
Assumption 9 below) — every qualifying facility now gets a row for **every** month
2005–2025, with a `FACILITY_OPERATING_PERMIT_WINDOW` flag marking which rows fall
inside vs. outside its own permit-dates-only active window.

**updated 7/23: the operating-window correction moved into this script.** It
previously ran as a separate post-processing step (07, deleted) because it needed
every event type already assembled — but it only ever needed to know *whether and
when* a facility had *any* real event, not the full detailed counts, so that check now
runs here directly. `FACILITY_OPERATING` (the name downstream scripts use) is the
**corrected** flag from the moment it's created; the original permit-only flag is
preserved as `FACILITY_OPERATING_PERMIT_WINDOW`. See Assumptions 10–13 below. The
retired step 07 found: 12.66% of `FACILITY_OPERATING==0` rows carried a real event
anyway (32,033 of 253,028), 2,381 of 7,511 facilities (32%) affected, root cause =
permits in Administrative Continuance (`PERMIT_STATUS_CODE == "ADC"`). This script now
reproduces those exact same corrected numbers by construction, verified by a full
column-by-column diff against the retired step-07 output (zero differences).

**Bug found and fixed 7/21:** the spine-building `CJ()` call was passed the full,
non-unique `all_months$YEAR`/`$MONTH` columns (252 values each, not 21/12 distinct
values) instead of their unique values. `CJ()` does not deduplicate its inputs, so this
squared the year-month dimension (252×252 instead of 21×12), attempting to build
~477M rows instead of the correct ~1.89M and exceeding R's vector memory limit. Fixed
to use `unique(all_months$YEAR)` / `unique(all_months$MONTH)`. Row/facility counts are
unaffected (7,511 facilities, 1,892,772 rows, matching every count reported elsewhere
in this project) — the bug only affected the (never-successfully-run) balanced-panel
version of this script, not any panel actually delivered before 7/21.

*Step 1 of the facility-by-month panel build. Input: raw ICIS-NPDES permit, facility,
inspection, violation, and enforcement files, plus the pre-built condensed effluent
panel. Output: the base facility × month spine with facility attributes and both
operating flags — the corrected one is ready to use from this step onward.*

## Overview

This script constructs the **balanced facility-by-month spine** (Jan 2005 – Dec 2025)
that every later step attaches to. A facility is included if it was ever linked to at
least one **individual** (`NPD`) permit that was flagged **major** at any point in its
permit history. Every qualifying facility contributes a row for **every** calendar
month 2005–2025 — not just the months it was actually open. Two operating flags are
computed: `FACILITY_OPERATING_PERMIT_WINDOW` (1/0, from permit dates only) and
`FACILITY_OPERATING` (1/0, that window **extended to cover any month with a real
recorded event** — inspections, PS/CS/SE violations, formal/informal enforcement, or
effluent violations, checked for *existence* only here; full detailed counts remain
the job of scripts 02/04/05/06). No detailed behavioral count columns are added here —
only the spine, both operating flags, and time-invariant facility attributes.

## Data Availability and Provenance Statements

All inputs are EPA ECHO / ICIS-NPDES national bulk data files
(<https://echo.epa.gov/tools/data-downloads>), U.S. Government works in the public
domain, plus one project-derived intermediate (the condensed effluent panel, built
externally — see below). `TODO:` record download date / ECHO refresh version.

- **Statement about rights:** the author has legitimate access; the data are public
  and redistributable. `TODO:` confirm in `LICENSE.txt`.
- **Summary of availability:** ☒ All data are publicly available.

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `data/raw/npdes_downloads/ICIS_PERMITS.csv` | `.csv` | `EXTERNAL_PERMIT_NMBR`, `PERMIT_TYPE_CODE`, `MAJOR_MINOR_STATUS_FLAG`, `EFFECTIVE_DATE`, `ISSUE_DATE`, `ORIGINAL_ISSUE_DATE`, `EXPIRATION_DATE`, `TERMINATION_DATE`, `RETIREMENT_DATE` (one row per permit **version**) |
| `data/raw/npdes_downloads/ICIS_FACILITIES.csv` | `.csv` | `NPDES_ID`, `FACILITY_UIN`, `FACILITY_TYPE_CODE`, `FACILITY_NAME`, `LOCATION_ADDRESS`, `CITY`, `STATE_CODE`, `ZIP`, `COUNTY_CODE`, `GEOCODE_LATITUDE`, `GEOCODE_LONGITUDE` (one row per `NPDES_ID`); also read a **second, unrestricted** time for the event-existence crosswalk (see Assumption 13) |
| `data/raw/npdes_downloads/NPDES_INSPECTIONS.csv` | `.csv` | `NPDES_ID`, `ACTUAL_BEGIN_DATE`, `ACTUAL_END_DATE` — existence only |
| `data/raw/npdes_downloads/NPDES_PS_VIOLATIONS.csv`, `NPDES_CS_VIOLATIONS.csv` | `.csv` | `NPDES_ID`, `SCHEDULE_DATE` — existence only |
| `data/raw/npdes_downloads/NPDES_SE_VIOLATIONS.csv` | `.csv` | `NPDES_ID`, `SINGLE_EVENT_VIOLATION_DATE` — existence only |
| `data/raw/npdes_downloads/NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv` | `.csv` | `NPDES_ID`, `SETTLEMENT_ENTERED_DATE` — existence only |
| `data/raw/npdes_downloads/NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv` | `.csv` | `NPDES_ID`, `ACHIEVED_DATE` — existence only |
| `data/processed/effluent_violations_npdes_month_panel_2005_2025.csv` | `.csv` (derived; built by `build_effluent_violations_npdes_month_panel.R` — a prerequisite that must run before this step) | `NPDES_ID`, `month`, `n_D80`/`n_D90`/`n_E90` — existence only (`> 0`) |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `ICIS_PERMITS.csv`, `ICIS_FACILITIES.csv` | input (raw) | permit-version / permit-facility | via ECHO |
| `NPDES_INSPECTIONS.csv`, `NPDES_PS/CS/SE_VIOLATIONS.csv`, `NPDES_FORMAL/INFORMAL_ENFORCEMENT_ACTIONS.csv` | input (raw), existence only | event | via ECHO |
| `effluent_violations_npdes_month_panel_2005_2025.csv` | input (derived, external), existence only | permit × month | derived |
| `data/processed/01_facility_month_panel_major_individual_2005_2025.csv` | **output** | facility × year × month | derived |

> **Resolved 7/21:** the filename mismatch previously noted here (this script writing
> without an `01_` prefix while step 02 expected one) no longer exists — the script's
> `OUT_PATH` already includes the `01_` prefix. No manual rename needed between steps
> 01 and 02.

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `lubridate`.
- **Controlled randomness:** none — no PRNG, no seed.
- **No `python3`/`unzip` needed** — unlike step 06, this script never streams the raw
  ~16 GB `NPDES_EFF_VIOLATIONS.csv`; it uses only the pre-built condensed effluent
  panel (see Assumption 12).
- **Memory/runtime:** measured ~1:48 wall time (8 GB-RAM machine) — heavier than
  before the 7/23 change (was a few minutes) since it now also reads the five
  additional raw event sources, but far cheaper than re-running the full 02–06 chain
  the old step 07 depended on. `TODO:` exact OS/timing on other machines.

## Description of program

1. Read `ICIS_PERMITS`; derive each permit-version's opening and closing dates and
   its major flag; keep only individual (`NPD`) permits.
2. Collapse permit-versions to one row per permit (`NPDES_ID`).
3. Crosswalk permits to facilities via `ICIS_FACILITIES`; apply the blank-UIN fallback.
4. Determine facility eligibility and each facility's permit-only window; also build a
   **second, unrestricted** `NPDES_ID → facility_id` crosswalk from a fresh read of
   `ICIS_FACILITIES` (every permit type, not just individual/major-eligible — see
   Assumption 13) for routing the event-existence scan.
5. Build the facility attribute snapshot (unchanged from before 7/23).
6. Scan the five raw event sources and the condensed effluent panel for
   *existence only*; extend each facility's window to cover any real event, both
   directions.
7. Build the complete facility × month grid, clip to the panel window, and compute
   both `FACILITY_OPERATING` (corrected) and `FACILITY_OPERATING_PERMIT_WINDOW`
   (original) plus the time-invariant facility attributes.
8. Write the spine to `data/processed/`.

## Decisions and Assumptions

The script states thirteen numbered assumptions (1–9 predate the 7/23 change; 10–13
are new):

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
9. **`FACILITY_OPERATING_PERMIT_WINDOW` = 1 iff the calendar month falls within the
   facility's own `[spine_start_month, spine_end_month]`** (the same earliest-open/
   latest-close window, unioned across permits and clipped to the panel window, used
   to decide facility eligibility in Assumptions 2–4). Preserved for traceability —
   **not** the column downstream scripts should use; see Assumption 10.
10. **Why there's a second, corrected flag — measured, not hypothetical.** On the
    build that used Assumption 9's flag directly as `FACILITY_OPERATING`, 12.66% of
    its `FACILITY_OPERATING==0` rows (32,033 of 253,028) still carried a real
    recorded event downstream — direct proof the facility was active. 75.9% of those
    were >12 months outside the computed window (median 31, max 250 months); 2,381 of
    7,511 facilities (32%) were affected. **Root cause (confirmed):** permits with
    `PERMIT_STATUS_CODE == "ADC"` (Administrative Continuance — legally still active
    past the nominal `EXPIRATION_DATE` while a renewal is pending) have that
    `EXPIRATION_DATE` read as a real closing date by Assumption 2 anyway, since
    `ICIS_PERMITS` carries no field marking a facility's true open/close independent
    of permit paperwork. Example: facility `110006619212` / permit `NH0100455`,
    `EXPIRATION_DATE = 01/29/2005`, `PERMIT_STATUS_CODE = "ADC"`, no
    `TERMINATION_DATE`/`RETIREMENT_DATE` — its permit-only window closes at the start
    of the panel even though it has real recorded events up to 250 months later. 86.7%
    of the 8,007 permits linked to this panel's facilities carry `ADC` status at some
    point.
11. **The fix: extend the window to cover any real event, both directions** (per PI
    decision). Per facility: `new_start = min(permit-window start, first month with a
    real event)`, `new_end = max(permit-window end, last month with a real event)`.
    `FACILITY_OPERATING = 1` iff the month falls in `[new_start, new_end]`. This can
    only grow a window, never shrink one — a facility with zero recorded events
    anywhere keeps its Assumption-9 window unchanged.
12. **"Real event" means existence, not the detailed counts.** This script only needs
    to know *whether and when* a facility had any inspection, PS/CS/SE violation,
    formal/informal enforcement action, or effluent violation — not the type/agency/
    code breakdowns scripts 02/04/05/06 still compute in full, and not exact counts.
    Same date fields/rules those scripts use (see Dataset list above). Deliberately
    does **not** stream the raw ~16 GB `NPDES_EFF_VIOLATIONS.csv` that script 06 uses
    for its TSS-specific subset: **verified empirically** (on the panel this
    correction was originally developed against) that zero facility-months have a
    positive TSS-subset violation while the condensed all-parameter panel
    (`n_D80`/`n_D90`/`n_E90`) shows nothing — the condensed panel is already a
    complete proxy for "any effluent event," so this script needs neither `python3`
    nor `unzip`.
13. **Routed by a crosswalk built from the FULL, unrestricted `ICIS_FACILITIES`** —
    every `NPDES_ID` (any permit type), not the narrower crosswalk implicit in this
    script's own `permits`-filtered facility table. **Bug caught during
    implementation:** an earlier version derived the event-routing crosswalk from the
    already-individual/major-restricted facility table, which silently dropped events
    recorded under a qualifying facility's *other* (general/minor) permits — this
    undercounted the correction (2,305 facilities extended instead of 2,381). Fixed by
    reading `ICIS_FACILITIES` a second, unrestricted time for this crosswalk,
    matching exactly how scripts 02/04/05/06 each build theirs. Verified: reproduces
    the originally-measured 2,381/1,749,567/143,205 figures exactly.

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
  (**balanced**, not clipped per facility; see Assumption 9). Both operating flags are
  then computed per row from each facility's own window(s); this does not change which
  rows exist, only how a row is labeled.

**Rows dropped (and why)** — all reported in the run log, none silent:
- Permit-versions with no usable opening date (cannot be placed in time).
- Facilities whose window has zero overlap with 2005–2025 even after clipping.
- Non-individual or never-major permits; facilities outside the 48+DC scope.

**Hardcoded parameters:** `YEAR_MIN = 2005`, `YEAR_MAX = 2025`; ZIP format `"%05s"`;
state exclusion set `{AK, HI, PR, VI, GU, AS, MP}`.

## Output columns (17)

`FACILITY_UIN`, `YEAR`, `MONTH`, `NPDES_ID` (semicolon list of linked individual
permits), `MAJOR_MINOR_FLAG` (semicolon list), `PERMIT_TYPE_FLAG`, `FACILITY_OPERATING`
(1/0, corrected — see Assumptions 10–13), `FACILITY_OPERATING_PERMIT_WINDOW` (1/0,
original — see Assumption 9), `FACILITY_TYPE_CODE`, `FACILITY_NAME`, `LOCATION_ADDRESS`,
`CITY`, `STATE_CODE`, `ZIP`, `COUNTY_CODE`, `FAC_LAT`, `FAC_LONG`.

## Instructions to run

```bash
Rscript "code/03_panel_building/01_build_facility_month_panel_major_individual.R"
```
First step — has no upstream *panel* dependency (it does now read several raw event
files and the condensed effluent panel, but nothing produced downstream in this
pipeline). No manual rename needed before running step 02 (see the resolved filename
note above).

## Notes / edge cases

- A facility may enter minor, become major once (qualifies), then leave — all its
  months are kept (ever-major).
- A permit with no opening date is dropped; with no closing date, treated as active
  through Dec 2025.
- The panel is **balanced**: every qualifying facility has a row for every month
  2005–2025 (252 months each), regardless of when it actually held an active permit.
  `FACILITY_OPERATING_PERMIT_WINDOW` (Assumption 9) distinguishes months inside vs.
  outside the facility's *permit-only* window — 1,639,744 rows are inside it, 253,028
  are not, out of 1,892,772 total. The **corrected** `FACILITY_OPERATING` (Assumptions
  10–11) instead shows 1,749,567 operating / 143,205 not.
- Downstream, a real recorded event (inspection, violation, enforcement action,
  effluent violation) always wins over `FACILITY_OPERATING`: verified there are now
  **zero** rows where `FACILITY_OPERATING == 0` and a real event is recorded — the
  correction is a mathematical guarantee of the Assumption-11 construction, not just
  an empirical result.
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
