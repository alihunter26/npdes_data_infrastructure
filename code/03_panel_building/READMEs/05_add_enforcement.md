# README — `05_add_enforcement.R`

** verified by Ali 07/28 **

**updated 7/28: formal and informal now counted the SAME way — per raw row.**
Previously formal counted **distinct actions** (`uniqueN(ENF_IDENTIFIER)`) while
informal counted **raw rows** (`.N`/`sum(<flag>)`) — the two were deliberately on
different grains. Per request, formal switched to the same per-row style informal
already used: `N_FORMAL_ACTIONS` and its breakouts (`N_AFR`, `N_JDC`, `N_SCWAAPO`,
`N_STAOCO`, `N_SCWAAO`, `N_309A`, `N_STATE_AFR`, `N_EPA_AFR`, `N_STATE_JDC`,
`N_EPA_JDC`) now use `.N`/`sum(<condition>)` instead of `uniqueN(ENF_IDENTIFIER[...])`.
**Consequence:** `N_FORMAL_ACTIONS` now over-counts relative to distinct actions for
any action spanning more than one permit or `ENF_TYPE_CODE` (the formal file has 0
exact-duplicate rows, so — unlike informal — this over-count is entirely
multi-permit/multi-type fan-out, not literal duplication). **The penalty dollar
columns are unaffected** (`FED_PENALTY`, `STATE_PENALTY`, `N_FED_PENALTY_ASSESSED`,
`N_STATE_PENALTY_ASSESSED` still de-duplicate to one row per action before summing —
see Assumption 5) — they are now on a **different grain** than `N_FORMAL_ACTIONS` and
should not be compared 1:1 against it. See Assumption 1 below; verified by an actual
run (2005–2025 panel): 13,348 formal action-rows placed on the panel, run-log
identities (`N_STATE_AFR + N_EPA_AFR == N_AFR`, etc.) still hold.

*Step 5 of the facility-by-month panel build. Input: step-04 panel + raw enforcement
files. Output: the panel with formal/informal enforcement counts and penalty dollars.*

## Overview

Attaches per-facility-month counts of **formal** and **informal** NPDES enforcement
actions, broken out by type/activity/agency, plus federal and state **penalty dollars**.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. ☒ All data publicly available.

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `data/processed/04_..._violations_2005_2025.csv` | `.csv` | step-04 panel (incl. `FACILITY_OPERATING`, passed through from step 01) |
| `data/raw/npdes_downloads/NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv` | `.csv` | `NPDES_ID`, `ENF_IDENTIFIER`, `ACTIVITY_TYPE_CODE`, `ENF_TYPE_CODE`, `AGENCY`, `SETTLEMENT_ENTERED_DATE`, `FED_PENALTY_ASSESSED_AMT`, `STATE_LOCAL_PENALTY_AMT` |
| `data/raw/npdes_downloads/NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv` | `.csv` | `NPDES_ID`, `ENF_IDENTIFIER`, `ENF_TYPE_CODE`, `ACHIEVED_DATE`, `OFFICIAL_FLG` |
| `ICIS_FACILITIES.csv` | `.csv` | crosswalk |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| step-04 panel | input | facility × month | derived |
| formal / informal enforcement files | input (raw) | action × permit/type | via ECHO |
| `data/processed/05_..._enforcement_2005_2025.csv` | **output** | facility × year × month | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `lubridate`.
- **Controlled randomness:** none. **Memory/runtime:** formal ~112 k rows; minutes. `TODO:` OS/timing.

## Description of program

Rebuild the crosswalk; for each file, date the actions and place them in a month. Both
files are counted the **same way, per raw row** (`.N` / `sum(<condition>)`, never
`uniqueN(ENF_IDENTIFIER)`) — each row, including formal's multi-permit/multi-type
fan-out rows and informal's exact-duplicate rows, counts as one action (see
Assumption 1). Penalty dollars are the one exception: de-duplicate penalties to one
value per action first (a different grain than the counts above), then sum per
facility-month with NA-preserving aggregators. Left-join onto the panel: a count column
gets `0` where nothing occurred **and** the facility was operating, `NA` where nothing
occurred and it wasn't operating, and its real value where something *did* occur
regardless of operating status (see Assumption 7); the two penalty-dollar columns
always get NA where no action carried an amount, whether or not the facility was
operating.

## Decisions and Assumptions

1. **Both formal and informal are counted PER RAW ROW** (changed 7/28, per request;
   formal previously counted distinct `ENF_IDENTIFIER` instead). Every row of either
   file counts as one action — `N_FORMAL_ACTIONS`/`N_INFORMAL_ACTIONS = .N`; breakouts
   via `sum(<condition>)`; never `uniqueN(ENF_IDENTIFIER[...])`. **Consequences:**
   formal's file has multiple rows per action (one per permit and/or per
   `ENF_TYPE_CODE`) — 111,816 rows → 103,989 actions, with **0 exact-duplicate rows** —
   so `N_FORMAL_ACTIONS` now over-counts relative to distinct actions for any action
   spanning >1 permit or >1 type, entirely multi-permit/multi-type fan-out, not literal
   duplication; informal's file is 821,977 rows but only 474,600 distinct
   `ENF_IDENTIFIER`s, because **345,822 rows (42%) are byte-identical duplicates** (all
   11 fields equal), so an action recorded 3× identically counts as **3**, inflating
   informal totals ≈1.7× vs. distinct-action counting (on an earlier panel build:
   93,470 informal rows vs. 56,356 distinct actions). **Prior behavior (before 7/28):**
   formal counted distinct `ENF_IDENTIFIER` (to avoid the multi-permit/multi-type
   over-count above) while informal counted raw rows (PI decision, to include the
   exact-duplicate rows) — the two were deliberately on *different* grains; to revert
   to that asymmetry, switch `N_FORMAL_ACTIONS`/its breakouts in STEP 3a back to
   `uniqueN(ENF_IDENTIFIER[<condition>])`, matching the comment at STEP 4 for the
   informal-side equivalent. **Does not affect penalty dollars:** `FED_PENALTY`,
   `STATE_PENALTY`, `N_FED_PENALTY_ASSESSED`, `N_STATE_PENALTY_ASSESSED` still
   de-duplicate to one row per action (Assumption 5) — summing a shared penalty across
   an action's raw rows would multiply it — so these four columns are on a
   **different grain** than `N_FORMAL_ACTIONS` and should not be compared 1:1 against it.
2. **Type/activity breakouts can overlap** (PI naming). An action with several
   `ENF_TYPE_CODE`s is counted in each matching column, so the type columns are **not** a
   partition and needn't sum to the total (many codes aren't broken out). `AGENCY` **does**
   partition — but only within each activity type, not across all formal actions:
   `N_STATE_AFR + N_EPA_AFR` partitions `N_AFR`, and `N_STATE_JDC + N_EPA_JDC` partitions
   `N_JDC`, separately. `OFFICIAL_FLG` partitions `N_INFORMAL_ACTIONS` directly. The run log
   verifies all three identities.
3. **Exact `ENF_TYPE_CODE` match.** e.g. `N_AER` matches `"AER"` exactly; the `"AERS"`
   ("-S" significant variant) is **not** folded in (same for `LOVWL`/`NOV`/`NONC`).
   `TODO:` decide whether "-S" variants should be included.
4. **Date = when the action was entered/achieved.** Formal: `SETTLEMENT_ENTERED_DATE`
   (~97% present); informal: `ACHIEVED_DATE` (~99% present). Actions with no parseable
   date are dropped, and the count is reported (not silent).
5. **Penalties counted once per action; "not assessed" ≠ "$0"** (PI guidance). The
   penalty is de-duplicated to one value per (facility, month, action) **before**
   summing, so a shared penalty is never multiplied across an action's rows. A **blank**
   amount means the penalty was never assessed / does not apply → stays **NA**, distinct
   from a genuine assessed **$0** (blanks vastly outnumber true zeros: ~107 k vs 72
   federal, ~64 k vs 768 state). `FED_PENALTY` / `STATE_PENALTY` are **NA** for any
   facility-month where no action carried an amount, and 0 only when $0 was actually
   assessed. Companion counts `N_FED_PENALTY_ASSESSED` / `N_STATE_PENALTY_ASSESSED` give
   the number of distinct actions carrying a non-blank amount — since 7/28 this is a
   **different grain** than `N_FORMAL_ACTIONS` (per-row; Assumption 1), so the two are
   not directly comparable.
6. **Routed by `NPDES_ID` via the step-01 crosswalk** (`FACILITY_UIN` else `NPDES_ID`);
   an action on any permit resolving to the facility is counted.
7. **The panel defines the observation set; a real match always wins over
   `FACILITY_OPERATING`.** Left-join; a facility-month with no action gets **0** for
   every count column only while the facility was actually operating
   (`FACILITY_OPERATING == 1`, from step 01); if it wasn't operating and no action
   matched, count columns get **NA** — undefined, not zero. If an action *did*
   match, its value is kept even when `FACILITY_OPERATING == 0` (e.g. administrative
   lag near a permit boundary). The two penalty-dollar columns are unaffected by
   `FACILITY_OPERATING` — they already get **NA** whenever no action carried an
   amount (Assumption 5), which is automatically true for a non-operating month
   with no action.

**Code → column mappings**
- Formal activity (`ACTIVITY_TYPE_CODE`): `N_AFR`←`"AFR"` (administrative formal),
  `N_JDC`←`"JDC"` (judicial).
- Formal type (`ENF_TYPE_CODE`): `N_SCWAAPO`←`"SCWAAPO"`, `N_STAOCO`←`"STAOCO"`,
  `N_SCWAAO`←`"SCWAAO"`, `N_309A`←`"309A"`.
- Formal agency × activity (`AGENCY` within each `ACTIVITY_TYPE_CODE`): `N_STATE_AFR`←`AFR`+`"State"`,
  `N_EPA_AFR`←`AFR`+`"EPA"`, `N_STATE_JDC`←`JDC`+`"State"`, `N_EPA_JDC`←`JDC`+`"EPA"`. There is no
  single state/EPA split of *all* formal actions — agency is broken out separately within `AFR` and
  within `JDC`, so `N_STATE_AFR + N_EPA_AFR` partitions `N_AFR` (not `N_FORMAL_ACTIONS`), and likewise
  `N_STATE_JDC + N_EPA_JDC` partitions `N_JDC`.
- Informal type (`ENF_TYPE_CODE`): `N_LOVWL`←`"LOVWL"`, `N_NOV`←`"NOV"`,
  `N_NONC`←`"NONC"`, `N_AER`←`"AER"`.
- Informal official (`OFFICIAL_FLG`): `N_OFFICIAL_INFORMAL`←`"Y"`,
  `N_UNOFFICIAL_INFORMAL`←`"N"`.

**Penalty parsing:** `to_dollars()` strips `[$, ]` then `as.numeric` (NA if
blank/non-numeric); `sum_assessed()` / `max_assessed()` return NA when all inputs are NA,
else ignore NAs — so "not assessed" stays NA and a genuine $0 stays 0.

**Filters / drops:** window 2005–2025; unparseable-date actions dropped (counts logged);
inner-join to the crosswalk drops unroutable `NPDES_ID`s.

**Hardcoded parameters:** `YEAR_MIN = 2005`, `YEAR_MAX = 2025`; dollar strip `gsub("[$, ]","")`.

## Output columns (22)

- **Formal counts (per raw row — see Assumption 1):** `N_FORMAL_ACTIONS`, `N_AFR`,
  `N_JDC`, `N_SCWAAPO`, `N_STAOCO`, `N_SCWAAO`, `N_309A`, `N_STATE_AFR`, `N_EPA_AFR`,
  `N_STATE_JDC`, `N_EPA_JDC`.
- **Formal penalties (distinct-action grain — see Assumption 5, NOT the same grain as**
  **the counts above):** `FED_PENALTY` (sum $ or NA), `N_FED_PENALTY_ASSESSED`,
  `STATE_PENALTY` (sum $ or NA), `N_STATE_PENALTY_ASSESSED`.
- **Informal counts (per raw row — see Assumption 1):** `N_INFORMAL_ACTIONS`, `N_LOVWL`,
  `N_NOV`, `N_NONC`, `N_AER`, `N_OFFICIAL_INFORMAL`, `N_UNOFFICIAL_INFORMAL`.

## Instructions to run

```bash
Rscript "code/03_panel_building/05_add_enforcement.R"
```
Run **after** step 04.

## Notes / edge cases

- A facility-month with a formal action but no assessed amount: `N_FORMAL_ACTIONS > 0`
  yet `FED_PENALTY`/`STATE_PENALTY` = NA and `N_*_PENALTY_ASSESSED` = 0.
- Run-log identities: `N_STATE_AFR + N_EPA_AFR == N_AFR`; `N_STATE_JDC + N_EPA_JDC ==
  N_JDC`; `N_OFFICIAL_INFORMAL + N_UNOFFICIAL_INFORMAL == N_INFORMAL_ACTIONS`; all
  computed with `na.rm = TRUE` since non-operating/no-data rows are now legitimately NA.
- A non-operating facility-month can still show a real, non-NA count if an action
  was genuinely recorded then (Assumption 7) — `FACILITY_OPERATING == 0` does not by
  itself imply NA.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
