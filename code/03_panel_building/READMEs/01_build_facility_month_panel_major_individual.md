# README — `01_build_facility_month_panel_major_individual.R`

** verified by Ali 7/28 **

**updated 7/28: panel membership now depends on EITHER permit-window overlap OR**
**proxy evidence, not permit dates alone.** Previously, a facility whose permit
paperwork window didn't overlap 2005–2025 was dropped entirely, before
`use_operating_proxies()` ever ran — proxies only widened an already-admitted
facility's window, never granted admission on their own. Now a facility is kept if
EITHER its permit window overlaps the panel OR it has independent proxy evidence
(inspection, violation, enforcement, effluent) anywhere in 2005–2025. Verified: 16
facilities newly admitted via proxy evidence only (of 7,531 candidates; 1 candidate
still dropped for having neither), bringing the final population to 7,530 and the
panel to 1,897,560 rows (+4,032 = 16 × 252 months). A new third column,
`FACILITY_OPERATING_PROXY_WINDOW`, reports the proxy-only-derived window
independent of permit dates — for a proxy-only-admitted facility this is the only
column showing *why* it's in the panel, since `FACILITY_OPERATING_PERMIT_WINDOW`
correctly reads 0 for every one of its months. See Assumption 1B.

** `USE_PROXIES` config flag.** A single `TRUE`/`FALSE` toggle
near the top of the script (with `YEAR_MIN`/`YEAR_MAX`/etc.) now controls whether the
`use_operating_proxies()` correction runs at all. `TRUE` (default) applies it with all
seven proxy sources on, reproducing the original correction exactly. `FALSE` uses
permit-paperwork dates only — `FACILITY_OPERATING` becomes identical to
`FACILITY_OPERATING_PERMIT_WINDOW`, and the run skips reading all seven proxy sources
entirely (verified: ~33s vs. ~59s wall time on an 8GB-RAM machine; run log prints
"Facilities with window extended: 0 of 7,514" and `FACILITY_OPERATING == 1` matches
`FACILITY_OPERATING_PERMIT_WINDOW == 1` exactly). The flag feeds all seven `use_*`
arguments at once at the call site (STEP 6B/6C); to enable/disable individual proxy
sources instead of all seven together, override the specific `use_*` argument there.

The
event-scanning/window-extension logic lives in `use_operating_proxies.R`, as a function,
`use_operating_proxies()`, with an on/off switch per proxy source (all seven default
`TRUE`). This script now just calls that
function; see `use_operating_proxies.R`'s own header for the full explanation and for
how to try a different mix of evidence without editing this script.

Every qualifying facility gets a row for **every** month
2005–2025, with a `FACILITY_OPERATING_PERMIT_WINDOW` flag marking which rows fall
inside vs. outside its own permit-dates-only active window.

*Step 1 of the facility-by-month panel build. Input: raw ICIS-NPDES permit, facility,
inspection, violation, and enforcement files, plus the pre-built condensed effluent
panel. Output: the base facility × month spine with facility attributes and all
three operating flags — the union (`FACILITY_OPERATING`) is ready to use from this
step onward.*

## Overview

This script constructs the **balanced facility-by-month spine** (Jan 2005 – Dec 2025)
that every later step attaches to. A facility is included if it was ever linked to at
least one **individual** (`NPD`) permit that was flagged **major** at any point in its
permit history, AND (since 2026-07-28) either its permit-paperwork window overlaps
2005–2025 **or** it has independent proxy evidence (inspection, violation,
enforcement, effluent) anywhere in that range — permit dates alone no longer gate
membership (Assumption 1B). Every qualifying facility contributes a row for **every**
calendar month 2005–2025 — not just the months it was actually open. Three operating
flags are computed, each an independent lens on operating status:
`FACILITY_OPERATING_PERMIT_WINDOW` (1/0, from permit dates only — a genuine 0, not NA,
for a facility with no permit-window overlap), `FACILITY_OPERATING_PROXY_WINDOW` (1/0,
from proxy evidence only, with NA where no proxy evidence exists at all), and
`FACILITY_OPERATING` (1/0, the **union** of both — inspections, PS/CS/SE violations,
formal/informal enforcement, or effluent violations, checked for *existence* only
here; full detailed counts remain the job of scripts 02/04/05/06). No detailed
behavioral count columns are added here — only the spine, all three operating flags,
and time-invariant facility attributes. The proxy scan itself is gated behind the
`USE_PROXIES` config flag (default `TRUE`); set it `FALSE` to get
`FACILITY_OPERATING` == `FACILITY_OPERATING_PERMIT_WINDOW` with no proxy evidence
scanned or used at all (which also means membership collapses back to
permit-window-overlap only).

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
| `data/raw/npdes_downloads/ICIS_FACILITIES.csv` | `.csv` | `NPDES_ID`, `FACILITY_UIN`, `FACILITY_TYPE_CODE`, `FACILITY_NAME`, `LOCATION_ADDRESS`, `CITY`, `STATE_CODE`, `ZIP`, `COUNTY_CODE`, `GEOCODE_LATITUDE`, `GEOCODE_LONGITUDE` (one row per `NPDES_ID`); also read a **second, unrestricted** time for the event-existence crosswalk (see Assumption 10) |
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
  panel (see Assumption 10).
- **Memory/runtime:** measured ~1:48 wall time (8 GB-RAM machine) — heavier than
  before the 7/23 change (was a few minutes) since it now also reads the five
  additional raw event sources, but far cheaper than re-running the full 02–06 chain
  the old step 07 depended on. `TODO:` exact OS/timing on other machines.

## Description of program

1. Read `ICIS_PERMITS`; derive each permit-version's opening and closing dates and
   its major flag; keep only individual (`NPD`) permits.
2. Collapse permit-versions to one row per permit (`NPDES_ID`).
3. Crosswalk permits to facilities via `ICIS_FACILITIES`; apply the blank-UIN fallback;
   also build a **second, unrestricted** `NPDES_ID → facility_id` crosswalk from a
   fresh read of `ICIS_FACILITIES` (every permit type, not just individual/
   major-eligible — see Assumption 10) for routing the proxy-evidence scan.
4. Determine the CANDIDATE population (ever-major, ever-individual) and each
   candidate's permit-only window; test whether that window genuinely overlaps
   2005–2025 (Assumption 1B) and compute `spine_start_ym`/`spine_end_ym` only when
   it does (`NA` otherwise). Scan for proxy evidence via `use_operating_proxies()`
   (in `use_operating_proxies.R`) against **every** candidate — not just permit-
   window survivors — which scans the seven raw/derived event sources for
   *existence only* and returns both the proxy-only bounds
   (`proxy_start_ym`/`proxy_end_ym`) and the union bounds
   (`new_start_ym`/`new_end_ym`). Final eligibility: keep a candidate if its permit
   window overlaps OR it has any proxy evidence; drop it otherwise.
5. Build the facility attribute snapshot (unchanged from before 7/23).
6. Build the complete facility × month grid, clip to the panel window, and compute
   all three operating flags — `FACILITY_OPERATING_PERMIT_WINDOW` (permit-only,
   explicit 0 where the permit window doesn't overlap), `FACILITY_OPERATING_PROXY_WINDOW`
   (proxy-only, `NA` where no proxy evidence exists), `FACILITY_OPERATING` (the
   union) — plus the time-invariant facility attributes.
7. Write the spine to `data/processed/`.

## Decisions and Assumptions

The script states twelve numbered assumptions (1–9 predate the 7/23 change; 1B and 11
are new as of 7/28; 10 is new as of 7/23, and as of 7/27 its actual scanning/extension
logic lives in `use_operating_proxies.R` — see that file's own header for the full
explanation):

1. **Ever-major, not always-major.** A facility qualifies if *any* linked individual
   permit bore the `M` (major) flag in *any* version — not a requirement that it was
   always major. (875 facilities shift beween major and minor at some point in time period -- they are all included)
1B. **Temporal eligibility: permit-window overlap OR proxy evidence** (changed 7/28,
   per request; previously permit-window overlap alone). A candidate facility
   (Assumption 1) is kept if EITHER (a) its permit-paperwork window (Assumptions
   2–4) genuinely overlaps 2005–2025 — tested on the raw, unclipped
   `facility_open`/`facility_close`, not the panel-clipped `spine_start`/
   `spine_end`, which would otherwise always "overlap" once clipped to the
   boundary — OR (b) it has independent proxy evidence (Assumption 10's seven
   sources) anywhere in 2005–2025, even if its permit window doesn't reach that
   range. A candidate satisfying neither is dropped entirely. **Verified:** of
   7,531 candidates, 7,514 have permit-window overlap, 16 are admitted solely via
   proxy evidence, and 1 is dropped (neither) — final population 7,530. For a
   proxy-only-admitted facility, `FACILITY_OPERATING_PERMIT_WINDOW` correctly
   reads 0 for every month (Assumption 9), and its `FACILITY_OPERATING` collapses
   to exactly its `FACILITY_OPERATING_PROXY_WINDOW` (Assumption 11) — spot-checked
   on facility `110000311485`. **Prior behavior:** only (a) could grant admission;
   proxy evidence only widened an already-admitted facility's window, never
   granted admission on its own.
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
   to decide facility eligibility in Assumptions 2–4, 1B). **Explicitly 0 (not `NA`)**
   for every month of a facility admitted solely via proxy evidence (Assumption 1B(b))
   — its permit window doesn't reach the panel at all, but that's still a genuine,
   reported zero. Preserved for traceability — **not** the column downstream scripts
   should use; see Assumption 10.
10. **`FACILITY_OPERATING` (the corrected flag) additionally extends this permit-only
    window over any month with independent proof the facility was still operating**
    (an inspection, PS/CS/SE violation, formal/informal enforcement action, or
    effluent violation) — computed by `use_operating_proxies()` in
    `use_operating_proxies.R`, called as
    `use_operating_proxies(qual_fac, xwalk, raw_dir = RAW_DIR, eff_path = EFF_PATH,
    year_min = YEAR_MIN, year_max = YEAR_MAX, use_inspections = USE_PROXIES, ...)`
    with all seven `use_*` switches tied to the single `USE_PROXIES` config flag
    (default `TRUE`, reproducing the original correction exactly — verified: an
    isolated side-by-side run of the old inline code and the new function, on
    identical input, produced `identical()` results for every facility). Set
    `USE_PROXIES <- FALSE` to skip the correction entirely (permit-paperwork dates
    only), or override an individual `use_*` argument at the call site for a mix
    other than all-seven-on/all-seven-off. See `use_operating_proxies.R`'s own
    header for the full explanation, the measured evidence motivating this
    correction (12.66% of `FACILITY_OPERATING==0` rows carrying a real event
    anyway), and its root cause (permits in Administrative Continuance).
11. **`FACILITY_OPERATING_PROXY_WINDOW` = 1 iff the calendar month falls within
    `[proxy_start_ym, proxy_end_ym]`** — the earliest/latest month with independent
    proxy evidence (Assumption 10's seven sources), with **no permit-date
    influence at all**. `NA` (not 0) for a facility with zero qualifying proxy
    events anywhere in 2005–2025 — there is no earliest/latest of an empty set, so
    "not operating per proxies" and "no proxy evidence exists at all" stay
    distinguishable (same NA-for-undefined philosophy used throughout this
    project). Added 7/28 alongside Assumption 1B — for a proxy-only-admitted
    facility this is the *only* column showing why it's in the panel at all; for
    every other facility it's a third, independent lens on operating status,
    no longer just an internal step toward `FACILITY_OPERATING`'s union.
    **Verified identity:** `FACILITY_OPERATING >= FACILITY_OPERATING_PROXY_WINDOW`
    holds for every row (ignoring `NA`).

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
- Permit-window overlap tested on the **raw, unclipped** `facility_open`/
  `facility_close` (Assumption 1B); only when it overlaps are `spine_start`/
  `spine_end` computed via `pmax(open, WINDOW_START)`/`pmin(close, WINDOW_END)` —
  `NA` otherwise (not a clipped fake bound). A candidate is **dropped entirely**
  only if it has neither permit-window overlap nor any proxy evidence (Assumption
  1B) — this, not permit-window overlap alone, is now the only place a facility's
  row *count* is affected by its window(s).
- Spine via `CJ(facility_id = unique(...), YEAR = unique(all_months$YEAR), MONTH =
  unique(all_months$MONTH))` — every surviving facility × **every** month 2005–2025
  (**balanced**, not clipped per facility; see Assumption 9). All three operating
  flags are then computed per row from each facility's own window(s); this does
  not change which rows exist, only how a row is labeled.

**Rows dropped (and why)** — all reported in the run log, none silent:
- Permit-versions with no usable opening date (cannot be placed in time).
- Candidates with **neither** permit-window overlap **nor** any proxy evidence
  anywhere in 2005–2025 (Assumption 1B) — verified: 1 of 7,531 candidates.
- Non-individual or never-major permits; facilities outside the 48+DC scope.

**Hardcoded parameters:** `YEAR_MIN = 2005`, `YEAR_MAX = 2025`; ZIP format `"%05s"`;
state exclusion set `{AK, HI, PR, VI, GU, AS, MP}`.

**Config flag:** `USE_PROXIES` (default `TRUE`) — see Assumption 10. When `FALSE`,
also collapses eligibility (Assumption 1B) back to permit-window-overlap only,
since no proxy evidence is scanned at all.

## Output columns (18)

`FACILITY_UIN`, `YEAR`, `MONTH`, `NPDES_ID` (semicolon list of linked individual
permits), `MAJOR_MINOR_FLAG` (semicolon list), `PERMIT_TYPE_FLAG`, `FACILITY_OPERATING`
(1/0, the union — see Assumption 10), `FACILITY_OPERATING_PERMIT_WINDOW` (1/0,
permit-only — see Assumption 9), `FACILITY_OPERATING_PROXY_WINDOW` (1/0 or `NA`,
proxy-only — see Assumption 11), `FACILITY_TYPE_CODE`, `FACILITY_NAME`,
`LOCATION_ADDRESS`, `CITY`, `STATE_CODE`, `ZIP`, `COUNTY_CODE`, `FAC_LAT`, `FAC_LONG`.
Physical CSV column order confirmed via `head -1`: `FACILITY_OPERATING_PROXY_WINDOW`
is column 9.

## Instructions to run

```bash
Rscript "code/03_panel_building/01_build_facility_month_panel_major_individual.R"
```
To skip the proxy correction (permit-paperwork dates only), set `USE_PROXIES <- FALSE`
near the top of the script before running — this also collapses eligibility back to
permit-window-overlap only (Assumption 1B).

## Notes / edge cases

- A facility may enter minor, become major once (qualifies), then leave — all its
  months are kept (ever-major).
- A permit with no opening date is dropped; with no closing date, treated as active
  through Dec 2025.
- **16 facilities are in the panel solely because of proxy evidence** — their permit
  paperwork window never overlaps 2005–2025 at all (Assumption 1B). Spot-checked
  facility `110000311485`: `FACILITY_OPERATING_PERMIT_WINDOW` is 0 for all 252
  months, `FACILITY_OPERATING_PROXY_WINDOW` is well-defined (243 months operating,
  9 not, 0 `NA`), and `FACILITY_OPERATING` matches `FACILITY_OPERATING_PROXY_WINDOW`
  exactly everywhere — the union collapses to the proxy-only bound when there's no
  permit bound to union it with.
- The panel is **balanced**: every qualifying facility has a row for every month
  2005–2025 (252 months each), regardless of when it actually held an active permit.
  `FACILITY_OPERATING_PERMIT_WINDOW` (Assumption 9) distinguishes months inside vs.
  outside the facility's *permit-only* window — 1,643,607 rows are inside it, 253,953
  are not, out of 1,897,560 total (7,530 facilities × 252 months). The **corrected**
  `FACILITY_OPERATING` (Assumption 10) instead shows 1,754,214 operating / 143,346 not.
- Downstream, a real recorded event (inspection, violation, enforcement action,
  effluent violation) always wins over `FACILITY_OPERATING`: verified there are now
  **zero** rows where `FACILITY_OPERATING == 0` and a real event is recorded — the
  correction is a mathematical guarantee of the Assumption-10 construction, not just
  an empirical result.
- **Verified `USE_PROXIES <- FALSE`:** re-running with the flag off gives 0 of 7,514
  facilities extended, and `FACILITY_OPERATING == 1` (1,643,607) exactly matches
  `FACILITY_OPERATING_PERMIT_WINDOW == 1` (1,643,607) — confirming the flag genuinely
  disables the correction rather than just hiding it.
- `FACILITY_UIN` reads in as `integer64`** (via `fread`).
  `data.table`'s `by =` grouping on an `integer64` column silently breaks (returns
  wrong/`NA` groups) unless the `bit64` package is loaded — this produced a bogus "0
  facilities with multiple NPDES_IDs" result before being caught. Cast to character
  first (`colClasses = c(FACILITY_UIN = "character")` in `fread`, or `as.character()`)
  before grouping on it.

## References

U.S. Environmental Protection Agency, Enforcement and Compliance History Online
(ECHO), ICIS-NPDES national data downloads. <https://echo.epa.gov/tools/data-downloads>.
Accessed `TODO`.
