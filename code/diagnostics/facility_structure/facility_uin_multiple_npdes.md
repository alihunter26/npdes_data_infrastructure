# README — `facility_uin_multiple_npdes.R`

*A standalone **diagnostic** (not a panel-building step). Input: raw
`ICIS_FACILITIES.csv`. Output: one CSV in `data/processed/` (not timestamped).*

## Diagnostic Context

**1. What issue is this script designed to give us information about?**
Is `FACILITY_UIN` (physical site) really 1:1 with `NPDES_ID` (permit) — i.e., can a UIN
safely stand in for "one facility," or does one physical site sometimes hold multiple
permits?

**2. What do we learn from the information created by this script?**
106,199 distinct `FACILITY_UIN`s (universe-wide) are tied to more than one `NPDES_ID`;
worst case is one North Dakota UIN linked to 361 separate permits — this script's own
output, confirmed by direct inspection of `data/processed/facility_uin_multiple_npdes.csv`.
Restricted to the panel-relevant population: re-deriving the count directly from the
current built panel (`data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv`,
splitting its semicolon-joined `NPDES_ID` field) gives **427** multi-permit facilities
out of 7,530 (one has 7, one has 5, 13 have 4, 34 have 3, 378 have 2) — matching the
"427" figure independently cited in `outfalls/outfall_count_breakdown.R`'s own header
comment.

*How fully have we dug in?* ~90%. Both the universe-wide and panel-restricted numbers
are now directly verified against current data. `docs/data_issues.md` previously
stated a stale count of 84 (predating a panel-membership change); it has been updated
2026-07-30 to the verified 427.

**3. What are the implications of what we learned for our issue?**
Less reassuring than the original "near 1:1" framing suggested: 427 of 7,530 (~5.7%)
still a small minority, but meaningfully more than the earlier 84 (~1.1%) — worth
treating as "Medium," not "Low," severity for the panel population (updated in
`docs/data_issues.md`). This is the number that actually feeds the aggregation logic in
`outfalls/outfall_count_breakdown.R`, so that script's handling of multi-permit
facilities (summing distinct outfalls across all of a facility's permits) now rests on
a verified, not stale, count.

## Overview

Extracts every ICIS facility row whose `FACILITY_UIN` (an FRS Unique Identifier
Number, identifying a *physical site*) is shared by more than one distinct `NPDES_ID`
(identifying a *permit*) — i.e., one site holding several permits, commonly
general-permit rollups or a site with multiple discharge permits.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data
(<https://echo.epa.gov/files/echodownloads/npdes_downloads.zip>), public domain.
`TODO:` download date. &boxtimes; All data publicly available.

### Details on each data source

- `data/raw/npdes_downloads/ICIS_FACILITIES.csv` (~1.2M rows per the script's header
  comment), read whole via `fread(colClasses = "character")`. Key fields:
  `FACILITY_UIN`, `NPDES_ID`.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `ICIS_FACILITIES.csv` | input (raw) | one row per facility record | via ECHO |
| `data/processed/facility_uin_multiple_npdes.csv` | **output** | one original `ICIS_FACILITIES` row for a flagged multi-permit `FACILITY_UIN` | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table` (fast read of the ~1.2M-row file), `dplyr`.
- **Controlled randomness:** none.
- **Memory/runtime:** whole file read via `fread`; fast even at ~1.2M rows. `TODO:`
  OS/timing.

## Description of program

Read the raw facilities file as character; treat blank/whitespace `FACILITY_UIN` as
missing; group by `FACILITY_UIN` and count distinct `NPDES_ID`s per group; keep
`FACILITY_UIN`s with more than one; pull every original row for those UINs
(arranged by `NPDES_ID`, `FACILITY_UIN`); write the result.

## Decisions and Assumptions

1. **A blank/whitespace `FACILITY_UIN` is treated as missing, not as a distinct
   facility value** — empty UINs are never grouped together or counted toward the
   "more than one `NPDES_ID`" test.

## Output columns

All original `ICIS_FACILITIES.csv` columns, one row per record belonging to a
flagged multi-permit `FACILITY_UIN`, written with `na = ""`.

## Instructions to run

```bash
Rscript "code/diagnostics/facility_structure/facility_uin_multiple_npdes.R"
```
No dependency on other scripts; reads raw data directly.

## Notes / edge cases

- **Output location is a cross-cutting exception to this repo's convention:** written
  to `data/processed/` rather than `output/` at all, and **not timestamped** — arguably
  more a derived-data extract than a diagnostic report, since it lives alongside the
  built panel files rather than with the other diagnostic tables.
- Console output reports the max number of `NPDES_ID`s found under a single
  `FACILITY_UIN`, in addition to the flagged-UIN and extracted-row counts.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/files/echodownloads/npdes_downloads.zip>. Accessed `TODO`.
