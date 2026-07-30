# README — `outfall_count_breakdown_dmr.R`

*A standalone diagnostic (not a panel-building step). Input: a raw per-fiscal-year
DMR zip + the built facility-month panel (06). Output: two timestamped CSVs in
`output/tables/`.*

## Overview

Companion to `code/diagnostics/outfalls/outfall_count_breakdown.R` (same repo,
different folder): that script counts outfalls a facility is **permitted** for, from
`NPDES_LIMITS.csv` (structural — "how many outfalls is this facility permitted for").
This script counts outfalls that actually **reported** at least one monitoring result
in the fiscal year, from the DMR file itself (realized — "how many outfalls actually
reported this year"). `DMR ≤ LIMITS` always in principle: a permitted outfall can go
a full fiscal year with no required/received DMR event.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain, plus derived panel data. `TODO:` download date. ☒ All data publicly
available.

### Details on each data source

| File | Key fields used |
|---|---|
| `data/raw/DMR/npdes_dmrs_fy<year>.zip` (member `NPDES_DMRS_FY<year>.csv`, ~9.7 GB), default FY2025 | `EXTERNAL_PERMIT_NMBR`, `VERSION_NMBR`, `PERM_FEATURE_ID`, `PERM_FEATURE_TYPE_CODE` |
| `data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv` | `FACILITY_UIN`, `NPDES_ID` — the facility → permit map |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `NPDES_DMRS_FY<year>.csv` (in its zip) | input (raw) | permit × outfall × parameter × period | via ECHO |
| the 06 panel | input (derived) | facility × month | from `code/03_panel_building/` |
| `output/tables/outfall_count_per_facility_dmr_fy<year>_<timestamp>.csv` | **output** | one row per panel facility | derived |
| `output/tables/outfall_count_distribution_dmr_fy<year>_<timestamp>.csv` | **output** | one row per outfall count (0–10+) | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `DBI`, `duckdb`.
- **Controlled randomness:** none.
- **Memory/runtime:** DuckDB out-of-core — the FY DMR CSV (~9.7 GB) lives inside a
  zip; DuckDB can't read a zip member directly (non-seekable pipe breaks its
  sniffer), so it's streamed out with `tar` and re-gzipped to scratch once (the same
  `GZ_TMP` path/convention other DMR scripts use, so an already-extracted gz is
  reused here too, and vice versa). `TODO:` OS/timing.

## Description of program

Stream `EXTERNAL_PERMIT_NMBR`, `VERSION_NMBR`, `PERM_FEATURE_ID` from the FY DMR file
via DuckDB, restricted to `PERM_FEATURE_TYPE_CODE = 'EXO'` and non-null feature IDs.
Restrict each permit to its **latest version observed within this fiscal year's DMR
data** (not its latest version ever issued — a DMR file only spans one year, so this
is the natural in-file analogue of what the companion LIMITS script does across a
permit's full history). Join to the panel's facility→permit map (splitting the
panel's semicolon-joined `NPDES_ID` list), count distinct `PERM_FEATURE_ID` per
facility, and fill facilities with zero reporting outfalls explicitly (not left as
`NA`). Reports a per-facility CSV and a count-distribution CSV.

## Decisions and Assumptions

1. **Keys outfalls on `PERM_FEATURE_ID`, not `PERM_FEATURE_NMBR`** — same reasoning
   as the companion LIMITS script: `PERM_FEATURE_ID` is regenerated at every permit
   reissuance, so `PERM_FEATURE_NMBR` alone (sequential per permit, like "001",
   "002") can collide across reissuances or across permits. This matters *within* a
   single fiscal year's DMR file too, not just across `NPDES_LIMITS`' full history:
   of 34,797 permits with TSS DMR activity in FY2025, 4,045 (11.6%) span more than
   one `VERSION_NMBR` (a mid-year reissuance), and `PERM_FEATURE_ID` disagrees with
   `PERM_FEATURE_NMBR` for 3,993 of those (measured).
2. **Restricts to each permit's latest version *observed within this FY's DMR data***
   before counting distinct outfalls — "latest observed," not "latest ever issued,"
   since a DMR file only contains one year.
3. **Scope: `PERM_FEATURE_TYPE_CODE = 'EXO'` only; all parameters** — an outfall
   counts if it reported *anything* that year, not restricted to TSS or any specific
   pollutant.
4. **Facilities with zero EXO DMR activity get an explicit `0`**, not a missing row —
   distinguishing "permitted but didn't report" from "not covered by the DMR pull at
   all" (see `docs/data_issues.md`'s `NPDES_DMRS` coverage row).
5. **Fiscal year is configurable** (`FY` at the top of the script), default 2025.

## Output columns

- **`outfall_count_per_facility_dmr_fy<year>_<timestamp>.csv`:** `FACILITY_UIN`,
  `n_outfalls` (0 if no reporting EXO outfall that FY).
- **`outfall_count_distribution_dmr_fy<year>_<timestamp>.csv`:** `n_outfalls`, `N`
  (facility count at that outfall count), `pct_of_all`.

## Instructions to run

```bash
Rscript code/dmr/outfall_count_breakdown_dmr.R
#   FY is hardcoded near the top of the script (default 2025) -- edit to change year
```
Requires the 06 panel to already exist in `data/processed/`. No dependency on the DMR
row-filter pipeline.

## Notes / edge cases

- The panel population is **read fresh from `PANEL_FILE` on every run**, not
  hardcoded — currently 7,530 facilities (as of the 2026-07-28 proxy-evidence
  admission of 16 more facilities; see `docs/codebook.md`), and will track whatever
  population the panel actually contains on a future rebuild.
- Multi-permit facilities (427, unchanged by the 7/28 population growth) count
  distinct outfalls across *all* of their linked permits, not just one.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
