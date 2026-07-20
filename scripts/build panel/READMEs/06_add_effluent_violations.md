# README — `06_add_effluent_violations.R`

*Step 6 of the facility-by-month panel build (final assembly step). Input: step-05
panel + the condensed effluent panel + the raw effluent file. Output: the panel with
**all** effluent-violation columns.*

## Overview

This step owns **every effluent-violation count** in the panel:

- **All-parameter** codes (`n_D80`, `n_D90`, `n_E90`) from a **pre-built condensed
  monthly panel** (fast; no re-streaming of the 16 GB file).
- **TSS gross-effluent monthly-average** subset (`N_TSS_EFF_VIOLATIONS`,
  `N_TSS_EFF_D90/D80/E90`) by **streaming the raw `NPDES_EFF_VIOLATIONS.csv`** — this
  block **moved here from step 04**.

The all-parameter counts are broadly a superset of the TSS counts; both are kept on
purpose. Moving the TSS block here did not change the final panel's columns or values —
only the step that adds them.

## Data Availability and Provenance Statements

Derived from EPA ECHO / ICIS-NPDES public data (public domain). `TODO:` download date of
the underlying effluent file. ☒ All data publicly available.

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `data/processed/05_..._enforcement_2005_2025.csv` | `.csv` | step-05 panel |
| `data/processed/effluent_violations_npdes_month_panel_2005_2025.csv` | `.csv` | `NPDES_ID`, `month` (`YYYY-MM-01`), `n_D80`, `n_D90`, `n_E90` (all-parameter) |
| `NPDES_EFF_VIOLATIONS.csv` (inside its zip in `data/raw/`) | `.csv` in `.zip`, ~16 GB unzipped | `NPDES_ID`, `NPDES_VIOLATION_ID`, `VIOLATION_CODE`, `PARAMETER_CODE`, `MONITORING_LOCATION_CODE`, `STATISTICAL_BASE_MONTHLY_AVG`, `MONITORING_PERIOD_END_DATE` (TSS subset) |
| `ICIS_FACILITIES.csv` | `.csv` | crosswalk |

> **External dependency:** the condensed panel is built by
> `build_effluent_violations_npdes_month_panel.R`, which was **moved to
> `../EIL Summer/build/`** (outside this repository). Run it there first; its output CSV
> lands in `data/processed/`.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| step-05 panel | input | facility × month | derived |
| `effluent_violations_npdes_month_panel_2005_2025.csv` | input (derived, external) | permit × month | derived |
| `NPDES_EFF_VIOLATIONS.csv` (zip) | input (raw) | violation | via ECHO |
| `data/processed/06_..._effluent_2005_2025.csv` | **output (final panel)** | facility × year × month | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `lubridate`.
- **External tools:** `python3` and `unzip` on `PATH` (stream + filter the raw effluent
  file; moved here from step 04).
- **Controlled randomness:** none.
- **Memory/runtime:** the condensed source is ~2.7 M rows (fast); the raw effluent file
  is ~16 GB uncompressed but is pre-filtered in a streaming pipe, so peak memory stays
  low — important on the 8 GB-RAM machine. This step now carries the single raw-effluent
  stream that used to run in step 04. `TODO:` OS/timing.

## Description of program

Rebuild the crosswalk. **(A)** Read the condensed panel, date/route it, and sum
`n_D80/n_D90/n_E90` per facility-month. **(B)** Stream the raw effluent file out of its
zip through a Python filter (TSS subset), date/route it, and count distinct violations
per facility-month (`N_TSS_EFF_*`). Merge both onto the panel, fill absent months with 0,
and restore the original column order (TSS block after `N_SE_VIOLATIONS`, all-parameter
block at the end).

## Decisions and Assumptions

1. **Two effluent count sets, kept separate.** `n_D*` count those codes across **every**
   parameter/feature/location; `N_TSS_EFF_*` count the **same codes** but only for the
   TSS / effluent-gross / monthly-average subset. So `n_D80 ≥ N_TSS_EFF_D80`, etc.
2. **All-parameter counts are already de-duplicated at source** (distinct underlying
   violations, latest DMR resubmission version only). Not re-deduped — only re-keyed and summed.
3. **Date = DMR monitoring-period month** for both sources.
4. **Routed by `NPDES_ID` via the step-01 crosswalk** (`FACILITY_UIN` else `NPDES_ID`);
   aggregated across all permits resolving to the facility (all-parameter counts are
   summed; TSS counts distinct violation IDs).
5. **The panel defines the observation set; missing = true zero.** Left-join; absent
   facility-months → **0**. Source rows outside the panel drop out.
6. **The TSS subset is a single specific limit** (PI guidance): keep a raw row only if
   `PARAMETER_CODE == "00530"` (TSS) **and** `MONITORING_LOCATION_CODE == "1"` (effluent
   gross) **and** `STATISTICAL_BASE_MONTHLY_AVG == "A"` (monthly-average). `N_TSS_EFF_*`
   count **distinct `NPDES_VIOLATION_ID`** (total, and by code D90/D80/E90).
7. **The raw effluent file is streamed once and pre-filtered in Python.**
   `unzip -p <zip> NPDES_EFF_VIOLATIONS.csv | python3 <filter> 00530 1 A` → `fread` reads
   only the small filtered subset. The zip's non-ASCII-space filename requires an ASCII
   **symlink** first. **Requires `python3` and `unzip` on `PATH`.**

**Filters / drops:** window 2005–2025; unparseable-date rows dropped; inner-join to the
crosswalk drops unroutable `NPDES_ID`s; NA → `0L`.

**Hardcoded parameters:** `YEAR_MIN = 2005`, `YEAR_MAX = 2025`; `TSS_PARAM_CODE = "00530"`,
`GROSS_LOC_CODE = "1"`, `MONTHLY_AVG = "A"`.

## Output columns (7)

- **TSS subset:** `N_TSS_EFF_VIOLATIONS`, `N_TSS_EFF_D90`, `N_TSS_EFF_D80`, `N_TSS_EFF_E90`
  (placed right after `N_SE_VIOLATIONS`, their original positions).
- **All-parameter:** `n_D80`, `n_D90`, `n_E90` (at the end of the panel).

## Instructions to run

```bash
Rscript "scripts/build panel/06_add_effluent_violations.R"
```
Run **after** step 05, **after** building the condensed source with
`build_effluent_violations_npdes_month_panel.R` (now in `../EIL Summer/build/`), and with
`python3`/`unzip` on `PATH` and the effluent zip present in `data/raw/`.

## Notes / edge cases

- The run log cross-checks: the all-parameter `n_D*` should be ≥ the TSS `N_TSS_EFF_*`
  cell-by-cell, except a vanishingly small number of facility-months where the condensed
  source's more aggressive de-dup makes it 1–2 lower — these are reported, not asserted away.
- The TSS and all-parameter columns are both retained in the final panel (different scopes).

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
