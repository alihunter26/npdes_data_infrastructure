# README — `06_add_effluent_violations.R`

*Step 6 of the facility-by-month panel build (final assembly step). Input: step-05
panel + a pre-built condensed effluent panel. Output: the panel with all-parameter
effluent violation codes.*

## Overview

Attaches per-facility-month counts of effluent (DMR) violations broken out by code
(**D80, D90, E90**), taken from a **pre-built condensed monthly panel** rather than
re-streaming the 16 GB raw effluent file. These are **all-parameter** counts — a
superset of step 04's TSS-only columns — and are kept as separate columns on purpose.

## Data Availability and Provenance Statements

The condensed source is derived from EPA ECHO / ICIS-NPDES public data (public domain).
`TODO:` download date of the underlying effluent file. ☒ All data publicly available.

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `data/processed/05_..._enforcement_2005_2025.csv` | `.csv` | step-05 panel |
| `data/processed/effluent_violations_npdes_month_panel_2005_2025.csv` | `.csv` | `NPDES_ID`, `month` (`YYYY-MM-01`), `n_D80`, `n_D90`, `n_E90` |
| `ICIS_FACILITIES.csv` | `.csv` | crosswalk |

> **External dependency:** the condensed panel is built by
> `scripts/build/build_effluent_violations_npdes_month_panel.R`, which lives **outside**
> this seven-step folder. Run that script first; it is not part of the 01→06 chain.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| step-05 panel | input | facility × month | derived |
| `effluent_violations_npdes_month_panel_2005_2025.csv` | input (derived, external) | permit × month | derived |
| `data/processed/06_..._effluent_2005_2025.csv` | **output (final panel)** | facility × year × month | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `lubridate`.
- **Controlled randomness:** none. **Memory/runtime:** ~2.7 M source rows; minutes. `TODO:` OS/timing.

## Description of program

Parse the source `month` to year/month; crosswalk permits to facilities; sum the three
code counts across all of a facility's permits per month; left-join onto the panel and
fill absent facility-months with 0.

## Decisions and Assumptions

1. **All-parameter counts, distinct from step 04's TSS columns.** The source counts
   D80/D90/E90 across **every** parameter/feature/location. Step 04's `N_TSS_EFF_*`
   count the same codes but only for the TSS / effluent-gross / monthly-average subset.
   So `n_D80 ≥ N_TSS_EFF_D80`, etc. Both sets are kept — neither replaces the other.
2. **Counts are already de-duplicated at source** (distinct underlying violations, latest
   DMR resubmission version only). This step does not re-dedupe — only re-key and sum.
3. **Date = DMR monitoring-period month.** Source `month` is the calendar month of
   `MONITORING_PERIOD_END_DATE`; split into year/month integers (same date basis as step 04).
4. **Routed by `NPDES_ID` via the step-01 crosswalk** (`FACILITY_UIN` else `NPDES_ID`);
   counts are **summed** across all permits resolving to the facility.
5. **The panel defines the observation set; missing = true zero.** Left-join; the source
   lists only months with a violation, so any panel facility-month not present had no
   D80/D90/E90 that month → filled with **0**. Source rows for permits/months outside the
   panel (minors, general permits, pre-entry) drop out.

**Filters / drops:** parse `month` via `as.Date`; window 2005–2025; inner-join to the
crosswalk drops unroutable `NPDES_ID`s; per-facility-month `sum` over `n_D80/n_D90/n_E90`.

**Hardcoded parameters:** `YEAR_MIN = 2005`, `YEAR_MAX = 2025`;
`new_cols = c("n_D80","n_D90","n_E90")`.

## Output columns (3)

`n_D80`, `n_D90`, `n_E90` (integer, all-parameter effluent violation counts).

## Instructions to run

```bash
Rscript "updated panel/06_add_effluent_violations.R"
```
Run **after** step 05, and **after** building the condensed source with
`scripts/build/build_effluent_violations_npdes_month_panel.R`.

## Notes / edge cases

- Because step 04 dedupes on distinct `NPDES_VIOLATION_ID` while the condensed source
  uses a more aggressive de-dup key, a *vanishingly small* number of facility-months can
  show `n_D* < N_TSS_EFF_*`; the run log reports these as dedup-key differences rather
  than asserting a strict inequality.
- The step-04 TSS columns and these all-parameter columns are both retained in the final
  panel for transparency (different scopes, not redundant).

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
