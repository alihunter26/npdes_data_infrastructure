# README — `outfall_count_breakdown.R`

*A standalone **diagnostic** (not a panel-building step). Input: the built
major-individual panel + raw `NPDES_LIMITS.csv`. Output: two timestamped CSVs.*

## Diagnostic Context

**1. What issue is this script designed to give us information about?**
Is "one facility = one outfall" a safe simplifying assumption, or do many major-individual
facilities have several discharge points — which matters for any per-outfall (vs.
per-facility) analysis?

**2. What do we learn from the information created by this script?**
Of 7,511 panel facilities (`output/tables/outfall_count_distribution_2026-07-17_1630.csv`):
5.7% have zero current EXO outfalls, 45.3% have exactly one, and 48.9% of all facilities
(51.9% of those with &ge;1) have more than one. Along the way, the script found and
fixed a real measurement bug: naively counting outfall IDs across *all* permit versions
(rather than just the current one) inflates the apparent multi-outfall rate from ~62%
to ~92%, because `PERM_FEATURE_ID` regenerates at every permit reissuance.

*How fully have we dug in?* ~90% for the current snapshot — the bug was found and
fixed within the same script, not left as a caveat. ~0% on how this changes over
time — it's explicitly a snapshot; ~31% of panel facilities had their outfall count
change at least once across 2005&ndash;2025 (`docs/data_issues.md`), and that isn't
re-derived here.

**3. What are the implications of what we learned for our issue?**
"One facility = one outfall" is unsafe — roughly half of facilities with any outfall
have more than one, so any per-outfall metric (from `NPDES_LIMITS` or DMR) needs
explicit aggregation logic to roll up to the facility level. But because this is a
snapshot, it can't yet answer what a facility's outfall count was in an earlier
panel-month — that would require redoing this at the version level across time.

## Overview

For every facility in the major-individual facility-month panel, counts its current
number of external discharge points (outfalls) and reports the 1&ndash;10 breakdown.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. &boxtimes; All data publicly available.

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv` | `.csv` (derived) | `FACILITY_UIN`, `NPDES_ID` (semicolon-joined for multi-permit facilities) |
| `data/raw/NPDES_LIMITS.csv` | `.csv` (raw, **~7GB**) | `EXTERNAL_PERMIT_NMBR`, `VERSION_NMBR`, `PERM_FEATURE_ID`, `PERM_FEATURE_TYPE_CODE` |

`NPDES_LIMITS.csv` is queried via DuckDB (`read_csv_auto(..., all_varchar=true)`), not
`fread` — see Computational Requirements.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| final panel (06) | input (derived) | facility &times; month | derived |
| `NPDES_LIMITS.csv` | input (raw) | permit &times; version &times; feature &times; parameter | via ECHO |
| `output/tables/outfall_count_per_facility_<timestamp>.csv` | **output** | one row per `FACILITY_UIN` | derived |
| `output/tables/outfall_count_distribution_<timestamp>.csv` | **output** | one row per `n_outfalls` value | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `DBI`, `duckdb`.
- **Controlled randomness:** none.
- **Memory/runtime:** `NPDES_LIMITS.csv` (~7GB) is queried out-of-core via DuckDB
  (`PRAGMA memory_limit='4GB'`) rather than read into R — important on the
  memory-constrained (8GB RAM) machine this repo is developed on (see project memory
  on the effluent file's size). `TODO:` OS/timing.

## Description of program

Split the panel's semicolon-joined `NPDES_ID` into one row per permit per facility;
query `NPDES_LIMITS.csv` in DuckDB for distinct (permit, version, `PERM_FEATURE_ID`)
combinations where `PERM_FEATURE_TYPE_CODE = 'EXO'` and the feature ID is non-null;
restrict to each permit's **latest** `VERSION_NMBR`; join outfalls to panel facilities
via the permit map (allowing a cartesian join for multi-permit facilities); count
distinct `PERM_FEATURE_ID` per `FACILITY_UIN`, filling facilities with none to `0`;
print summary statistics and the 1&ndash;10 breakdown; write both output tables.

## Decisions and Assumptions

1. **Identifier choice: `PERM_FEATURE_ID`, not `PERM_FEATURE_NMBR`.**
   `PERM_FEATURE_ID` is ICIS's internal key; `PERM_FEATURE_NMBR` is the permit's
   human-readable label (`"001"`, `"002"`, &hellip;). They are **not** interchangeable
   across a permit's full history — `PERM_FEATURE_ID` is regenerated at every
   reissuance. Example from the header comment (permit `AL0023400`, outfall label
   `"001"` throughout): version 0 &rarr; ID `3600771428`, version 2 &rarr;
   `1600002540`, version 3 &rarr; `3000004222`, version 4 &rarr; `3600227497` — same
   physical outfall, four different IDs. Counting distinct IDs across *all* versions
   would count (outfall &times; version) pairs, inflating the multi-outfall rate from
   ~62% to ~92% (measured).
2. **Fix: restrict to each permit's latest `VERSION_NMBR` before counting distinct
   `PERM_FEATURE_ID`.** Within one version, ID and NMBR agree almost perfectly (2 of
   147,646 permits differ — measured), making this a clean "outfalls the facility
   currently has" snapshot count.
3. **Scope: `PERM_FEATURE_TYPE_CODE = 'EXO'` (external outfall) only,** all
   parameters — not restricted to any single pollutant. Facilities are the 7,511 in
   the major-individual panel; the 427 multi-permit facilities count distinct
   outfalls across all their permits.
4. **This is a current-version snapshot, not a facility-month time series.** A
   facility's outfall roster can and does change over its history — ~31% of panel
   facilities had their TSS-outfall count change at least once across 2005&ndash;2025
   (see `docs/data_issues.md`). This script answers "how many outfalls does the
   facility have on its current permit," not "how many did it have in a given past
   year."

**Hardcoded parameters:** DuckDB `PRAGMA memory_limit='4GB'`; feature-type filter
`'EXO'`; breakdown table shown for `n_outfalls` 1&ndash;10 (11+ bucketed).

## Output columns

- **`outfall_count_per_facility_<timestamp>.csv`:** `FACILITY_UIN`, `n_outfalls`
  (integer; `0` for facilities with no current EXO feature — every panel facility is
  present, verified by a `stopifnot(nrow(result) == nrow(facilities))` check).
- **`outfall_count_distribution_<timestamp>.csv`:** `n_outfalls`, `N` (facility count),
  `pct_of_all` (1 dp).

## Instructions to run

```bash
Rscript "code/diagnostics/outfalls/outfall_count_breakdown.R"
```
Requires the final panel (`data/processed/06_..._effluent_2005_2025.csv`) to already
exist — run after `run_all.R`'s panel-building steps.

## Notes / edge cases

- This is the only diagnostic in `code/diagnostics/` that uses DuckDB for out-of-core
  processing; the exemplar diagnostic (`missingness_audit_major_individual.R`) instead
  streams the ~16GB effluent file in manual R-side chunks — two different strategies
  for the same "big raw file on a constrained-memory machine" problem.
- `PERM_FEATURE_NMBR` vs. `PERM_FEATURE_ID` inflation is the single most important
  caveat for anyone reusing this script's approach elsewhere in the repo.
- Output correctly follows the repo's `output/tables/<name>_<timestamp>.csv` convention.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
