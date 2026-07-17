# README — `05_add_enforcement.R`

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
| `data/processed/04_..._violations_2005_2025.csv` | `.csv` | step-04 panel |
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

Rebuild the crosswalk; for each file, date the actions, place them in a month,
de-duplicate to one row per action, and count distinct actions per facility-month
overall and by type/activity/agency/official-flag. De-duplicate penalties to one value
per action, then sum per facility-month with NA-preserving aggregators. Left-join onto
the panel; count columns get 0 where nothing occurred, penalty-dollar columns get NA.

## Decisions and Assumptions

1. **Action grain = `ENF_IDENTIFIER`.** Raw files have multiple rows per action (per
   permit and/or per type). Every count uses **distinct `ENF_IDENTIFIER`** (formal:
   ~112 k rows → ~104 k actions).
2. **Type/activity breakouts can overlap** (PI naming). An action with several
   `ENF_TYPE_CODE`s is counted in each matching column, so the type columns are **not** a
   partition and needn't sum to the total (many codes aren't broken out). `AGENCY` and
   `OFFICIAL_FLG` **do** partition their totals — the run log verifies both identities.
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
   the number of distinct actions carrying a non-blank amount.
6. **Routed by `NPDES_ID` via the step-01 crosswalk** (`FACILITY_UIN` else `NPDES_ID`);
   an action on any permit resolving to the facility is counted.
7. **The panel defines the observation set.** Left-join; a facility-month with no action
   gets true **0** for every count column, but **NA** for the two penalty-dollar columns
   (no information to record).

**Code → column mappings**
- Formal activity (`ACTIVITY_TYPE_CODE`): `N_AFR`←`"AFR"` (administrative formal),
  `N_JDC`←`"JDC"` (judicial).
- Formal type (`ENF_TYPE_CODE`): `N_SCWAAPO`←`"SCWAAPO"`, `N_STAOCO`←`"STAOCO"`,
  `N_SCWAAO`←`"SCWAAO"`, `N_309A`←`"309A"`.
- Formal agency (`AGENCY`): `N_STATE_FORMAL`←`"State"`, `N_EPA_FORMAL`←`"EPA"`.
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

## Output columns (20)

- **Formal counts:** `N_FORMAL_ACTIONS`, `N_AFR`, `N_JDC`, `N_SCWAAPO`, `N_STAOCO`,
  `N_SCWAAO`, `N_309A`, `N_STATE_FORMAL`, `N_EPA_FORMAL`.
- **Formal penalties:** `FED_PENALTY` (sum $ or NA), `N_FED_PENALTY_ASSESSED`,
  `STATE_PENALTY` (sum $ or NA), `N_STATE_PENALTY_ASSESSED`.
- **Informal counts:** `N_INFORMAL_ACTIONS`, `N_LOVWL`, `N_NOV`, `N_NONC`, `N_AER`,
  `N_OFFICIAL_INFORMAL`, `N_UNOFFICIAL_INFORMAL`.

## Instructions to run

```bash
Rscript "updated panel/05_add_enforcement.R"
```
Run **after** step 04.

## Notes / edge cases

- A facility-month with a formal action but no assessed amount: `N_FORMAL_ACTIONS > 0`
  yet `FED_PENALTY`/`STATE_PENALTY` = NA and `N_*_PENALTY_ASSESSED` = 0.
- Run-log identities: `N_STATE_FORMAL + N_EPA_FORMAL == N_FORMAL_ACTIONS`;
  `N_OFFICIAL_INFORMAL + N_UNOFFICIAL_INFORMAL == N_INFORMAL_ACTIONS`.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
