# README — `filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R`

*Step 1 of the FY2025 DMR filter mini-pipeline (distinct from the general DMR
row-filter pipeline). Input: `data/raw/DMR/npdes_dmrs_fy2025.zip`. Output:
`data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg.csv`.*

## Overview

Row-filters the FY2025 DMR file down to rows matching **all four** of: external
outfall (`PERM_FEATURE_TYPE_CODE = 'EXO'`), TSS (`PARAMETER_CODE = '00530'`),
effluent-gross monitoring location (`MONITORING_LOCATION_CODE IN ('1','EG')`), and
monthly-average statistical base (`STATISTICAL_BASE_CODE = 'MK'`). Pure row filter:
all 57 original columns preserved. Prerequisite for
`filter_dmr_fy2025_effgross_major_individual.R`.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. ☒ All data publicly available.

### Details on each data source

| File | Key fields used |
|---|---|
| `data/raw/DMR/npdes_dmrs_fy2025.zip` (member `NPDES_DMRS_FY2025.csv`, ~9.68 GB uncompressed) | all 57 columns; filtered on `PERM_FEATURE_TYPE_CODE`, `PARAMETER_CODE`, `MONITORING_LOCATION_CODE`, `STATISTICAL_BASE_CODE` |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `NPDES_DMRS_FY2025.csv` (in its zip) | input (raw) | permit × outfall × parameter × period | via ECHO |
| `data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg.csv` | **output** | same grain, row-filtered | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `DBI`, `duckdb`.
- **Controlled randomness:** none.
- **Memory/runtime:** DuckDB out-of-core — the 9.68 GB CSV cannot be held in RAM on
  this 8 GB machine. The zip member is decompressed once to a gzip scratch file
  (~4 GB), then DuckDB streams + spills to disk from there; one full pass takes a few
  minutes. `TODO:` OS/timing.

## Description of program

Decompress the zip's one CSV member to a gzip scratch temp (`tar -xOf ... | gzip -1
> ...`, reused across runs if present). Load into DuckDB and run a diagnostic scan
first — the (monitoring-location, statistical-base, value-type, unit) distribution
within just the EXO + TSS subset — printed to console for traceability *before*
narrowing further, so the realized `MONITORING_LOCATION_CODE` values and the
concentration/mass split are visible. Then apply all four filter conditions (ANDed)
and stream the matching rows to the output CSV. Refuses to write an empty output file
if zero rows match (stops with an error instead).

## Decisions and Assumptions

1. **All four filter conditions are exact ICIS codes, verified against EPA's own
   reference tables — not guessed:** `EXO` (external outfall, per
   `docs/panel_questions_for_pis.md` — a local-only file, not tracked in this repo),
   `00530` (TSS), `'1'`/`'EG'` (both map to "Effluent Gross" per
   `REF_MONITORING_LOCATION`), `MK` (Monthly Average per `REF_STATISTICAL_BASE.csv`).
2. **`STATISTICAL_BASE_CODE = 'MK'` already captures both concentration and mass-load
   forms of a TSS monthly-average limit** — the script does not filter further on
   unit type; the concentration/mass split is reported by the diagnostic scan, not
   discarded.
3. **Refuses to write an empty output** (CLAUDE.md rule: surface unexpected zero
   results rather than silently producing a misleading empty file) — stops with an
   error directing the user to check the diagnostic scan (especially
   `MONITORING_LOCATION_CODE`) before rerunning.
4. **A temp gzip file is required** because DuckDB reads files, not zip members
   directly, and a non-seekable pipe breaks its format sniffer — mirrors the pattern
   in `code/02_cleaning/build_effluent_violations_npdes_month_panel.R`.

## Output columns

Same 57 columns as `NPDES_DMRS_FY2025.csv` — pure row filter, no column selection.

## Instructions to run

```bash
Rscript code/dmr/filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R
```
No arguments (FY is hardcoded to 2025 in this script, unlike the FY-parameterized row-
filter pipeline). Not part of `code/03_panel_building/` or `run_all.R` — run manually.
Must run before `filter_dmr_fy2025_effgross_major_individual.R`.

## Notes / edge cases

- **Moved into this repo 2026-07-27** from an external working folder (`../EIL
  Summer/build/`, where an untouched copy remains) — same precedent as
  `code/02_cleaning/build_effluent_violations_npdes_month_panel.R`'s move. Its path
  handling already used this repo's `_paths.R` constants, so no path changes were
  needed.
- **Verified end to end after the move:** 754,033 rows, 34,797 distinct permits,
  57/57 columns, zero filter-violation rows on a from-scratch run (~24.5 min wall
  time, ~9.68 GB raw file streamed once) — see `docs/notes.md`.
- **This is a separate, standalone pipeline from the general DMR row-filter chain**
  (`filter_dmr_major_individual.R` etc.) — FY2025-hardcoded vs. FY-parameterized,
  different output location (`data/processed/` vs. `code/dmr/`), different exact
  filter conditions (adds `PERM_FEATURE_TYPE_CODE = 'EXO'` and
  `STATISTICAL_BASE_CODE = 'MK'`, which the general pipeline does not filter on).

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
