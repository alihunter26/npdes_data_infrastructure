# README — `06_add_effluent_violations.R`

** verified by Ali 7/28 **

*Step 6 of the facility-by-month panel build (final assembly step). Input: step-05
panel + the condensed effluent panel. Output: the panel with **all**
effluent-violation columns. This script reads from the condensed effluent panel from the cleaning step, which pre-compiles total and TSS violation counts*

## Overview

This step owns **every effluent-violation count** in the panel, both read from the same
pre-built source (`build_effluent_violations_npdes_month_panel.R` — see its own README
for how that file is constructed):

- **All-parameter** codes (`n_D80`, `n_D90`, `n_E90`).
- **TSS gross-effluent monthly-average** subset (`N_TSS_EFF_VIOLATIONS`,
  `N_TSS_EFF_D90/D80/E90`).

The all-parameter counts are broadly a superset of the TSS counts; both are kept on
purpose.

## Data Availability and Provenance Statements

Derived from EPA ECHO / ICIS-NPDES public data (public domain). `TODO:` download date of
the underlying effluent file. ☒ All data publicly available.

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `data/processed/05_..._enforcement_2005_2025.csv` | `.csv` | step-05 panel (incl. `FACILITY_OPERATING`, passed through from step 01) |
| `data/processed/effluent_violations_npdes_month_panel_2005_2025.csv` | `.csv` | `NPDES_ID`, `month` (`YYYY-MM-01`), `n_D80`/`n_D90`/`n_E90` (all-parameter), `N_TSS_EFF_VIOLATIONS`/`N_TSS_EFF_D90`/`N_TSS_EFF_D80`/`N_TSS_EFF_E90` (TSS subset) |
| `ICIS_FACILITIES.csv` | `.csv` | crosswalk |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| step-05 panel | input | facility × month | derived |
| `effluent_violations_npdes_month_panel_2005_2025.csv` | input (derived, pre-built) | permit × month | derived |
| `data/processed/06_..._effluent_2005_2025.csv` | **output (final panel)** | facility × year × month | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `lubridate`.
- **External tools:** none — this step no longer touches the raw effluent file.
- **Controlled randomness:** none.
- **Memory/runtime:** the condensed source is ~2.7 M rows; fast (seconds to low minutes).

## Description of program

Rebuild the crosswalk. Read the condensed panel (both count sets), date/route it, and
sum all 7 columns per facility-month. Left-join onto the panel: an absent facility-month
gets `0` if `FACILITY_OPERATING == 1` or `NA` if `FACILITY_OPERATING == 0`, but a real
matched violation keeps its value regardless of the flag (see Assumption 5); restore
the original column order (TSS block after `N_SE_VIOLATIONS`, all-parameter block at
the end).

## Decisions and Assumptions

1. **Two effluent count sets, kept separate.** `n_D*` count those codes across **every**
   parameter/feature/location; `N_TSS_EFF_*` count the **same codes** but only for the
   TSS / effluent-gross / monthly-average subset (defined in
   `build_effluent_violations_npdes_month_panel.R`'s Assumption 3). So `n_D80 ≥
   N_TSS_EFF_D80`, etc.
2. **Both count sets are already de-duplicated at source, by two deliberately different
   rules** (see that script's Assumption 4 for why). Not re-deduped here — only re-keyed
   and summed.
3. **Date = DMR monitoring-period month** for both sources.
4. **Routed by `NPDES_ID` via the step-01 crosswalk** (`FACILITY_UIN` else `NPDES_ID`);
   aggregated across all permits resolving to the facility.
5. **The panel defines the observation set; a real match always wins over
   `FACILITY_OPERATING`.** Left-join; an absent facility-month gets **0** only
   while the facility was actually operating (`FACILITY_OPERATING == 1`, from step
   01); if it wasn't operating and nothing matched, it gets **NA** — undefined, not
   zero. If a real effluent violation *did* match, its value is kept even when
   `FACILITY_OPERATING == 0` (e.g. administrative lag near a permit boundary) — NA
   never overwrites a real count. Source rows outside the panel drop out.

**Filters / drops:** window 2005–2025; unparseable-date rows dropped; inner-join to the
crosswalk drops unroutable `NPDES_ID`s; NA → `0L` if operating, NA → `NA` (unchanged)
if not operating.

**Hardcoded parameters:** `YEAR_MIN = 2005`, `YEAR_MAX = 2025`.

## Output columns (7)

- **TSS subset:** `N_TSS_EFF_VIOLATIONS`, `N_TSS_EFF_D90`, `N_TSS_EFF_D80`, `N_TSS_EFF_E90`
  (placed right after `N_SE_VIOLATIONS`, their original positions).
- **All-parameter:** `n_D80`, `n_D90`, `n_E90` (at the end of the panel).

## Instructions to run

```bash
Rscript "code/03_panel_building/06_add_effluent_violations.R"
```
Run **after** step 05, and after the condensed source at
`data/processed/effluent_violations_npdes_month_panel_2005_2025.csv` exists (built by
`build_effluent_violations_npdes_month_panel.R` — see its README).

## Notes / edge cases

- The run log cross-checks: the all-parameter `n_D*` should be ≥ the TSS `N_TSS_EFF_*`
  cell-by-cell, except a vanishingly small number of facility-months where the two
  different de-dup rules disagree by 1–2 — these are reported, not asserted away.
  Computed over operating rows only (`na.rm = TRUE`; the denominator is the operating
  row count, not the full panel).
- The TSS and all-parameter columns are both retained in the final panel (different scopes).
- A non-operating facility-month can still show a real, non-NA count if a violation
  was genuinely recorded then (Assumption 5) — `FACILITY_OPERATING == 0` does not by
  itself imply NA.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
