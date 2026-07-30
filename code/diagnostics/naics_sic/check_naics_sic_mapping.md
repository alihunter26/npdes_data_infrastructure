# README — `check_naics_sic_mapping.R`

*A standalone **diagnostic** (not a panel-building step). Input: raw ICIS-NPDES
industry-code files. Output: four CSVs on NAICS/SIC code multiplicity and mapping.*

## Diagnostic Context

**1. What issue is this script designed to give us information about?**
Whether there's a reliable crosswalk between NAICS and SIC industry codes, and whether
facilities carry ambiguous/multiple codes that would break a "one industry per
facility" assumption.

**2. What do we learn from the information created by this script?**
52,415 facilities carry >1 NAICS or >1 SIC code (`output/facilities_multiple_codes.csv`).
The primary-code crosswalk is many-to-many, not 1:1 — NAICS 221320 (Sewage Treatment)
maps to 88 different SIC codes, SIC 1542 (Nonresidential Construction) maps to 115
NAICS codes, and 722 NAICS codes overall map to more than one SIC
(`naics_with_multiple_sic.csv`, `naics_sic_crosswalk.csv`).

*How fully have we dug in?* ~80% on "is there a clean crosswalk?" — exhaustively
confirmed (no) over every facility in both files. ~20% on *why* specific codes are so
ambiguous (e.g. sewage treatment spans nearly every downstream industry that
discharges through a municipal system) — that qualitative follow-up was never
attempted.

**3. What are the implications of what we learned for our issue?**
No NAICS&harr;SIC conversion is possible. Confirmed in `docs/data_issues.md`: pick one
system and use its primary code — SIC, since it's ~99% covered in the major-individual
panel vs. NAICS ~65% missing. This closes the door on any analysis design that assumed
a clean industry crosswalk.

## Overview

Diagnoses NAICS &harr; SIC coding issues in the NPDES industry-code files: (A) facilities
that carry multiple NAICS and/or multiple SIC codes, and (B) the NAICS &harr; SIC mapping
*observed* by co-occurrence at facilities, flagging codes that map to more than one code
on the other side (many-to-many ambiguity). There is no official crosswalk in these
files — the mapping is derived, not authoritative.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. &boxtimes; All data publicly available.

### Details on each data source

| File | Key fields used |
|---|---|
| `data/raw/npdes_downloads/NPDES_NAICS.csv` | `NPDES_ID`, `NAICS_CODE`, `NAICS_DESC`, `PRIMARY_INDICATOR_FLAG` |
| `data/raw/npdes_downloads/NPDES_SICS.csv` | `NPDES_ID`, `SIC_CODE`, `SIC_DESC`, `PRIMARY_INDICATOR_FLAG` |

Both read via `fread(colClasses = "character")`. No panel restriction — every NPDES
facility in either file is included.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `NPDES_NAICS.csv`, `NPDES_SICS.csv` | input (raw) | one row per facility &times; code | via ECHO |
| `output/facilities_multiple_codes.csv` | **output** | one row per `NPDES_ID` flagged with >1 NAICS or >1 SIC | derived |
| `output/naics_sic_crosswalk.csv` | **output** | one row per observed (primary NAICS, primary SIC) pair | derived |
| `output/naics_with_multiple_sic.csv` | **output** | one row per NAICS code mapping to >1 SIC code | derived |
| `output/sic_with_multiple_naics.csv` | **output** | one row per SIC code mapping to >1 NAICS code | derived |

## Computational Requirements

- **R** 4.4.2. Package: `data.table`.
- **Controlled randomness:** none.
- **Memory/runtime:** both input files read whole; small relative to the raw NPDES
  bulk files. `TODO:` OS/timing.

## Description of program

Read both files as character; for Part A, count distinct `NAICS_CODE`/`SIC_CODE` per
`NPDES_ID` and flag facilities with more than one of either. For Part B, reduce each
file to one **primary** code per facility (`PRIMARY_INDICATOR_FLAG == "Y"`, else first
row), inner-join the two on `NPDES_ID`, and tabulate the resulting (NAICS, SIC) pairs
and which codes are ambiguous on the other side.

## Decisions and Assumptions

1. **The mapping (Part B) is built from primary codes only** &mdash; one NAICS and one
   SIC per facility. A many-to-one in the crosswalk therefore reflects *different
   facilities* sharing a code, not a within-facility cross-product of all codes a
   facility carries.
2. **Facility multiplicity (Part A) uses all codes, not just primary** &mdash; a
   facility can be flagged in Part A even if its primary codes alone would map cleanly.
3. **All NPDES facilities are included**, not restricted to any panel or sample; edit
   the reads if you want a subset.

**Primary-code selection (`pick_primary()`):** sorts by `NPDES_ID`, then
`PRIMARY_INDICATOR_FLAG != "Y"` (so `"Y"` sorts first), then keeps the first row per
`NPDES_ID` — i.e., the flagged primary if one exists, otherwise whichever row happens
to come first in the raw file.

## Output columns

- **`facilities_multiple_codes.csv`:** `NPDES_ID`, `n_naics`, `n_sic` (rows where
  `n_naics > 1 | n_sic > 1`, ordered descending).
- **`naics_sic_crosswalk.csv`:** `NAICS_CODE`, `NAICS_DESC`, `SIC_CODE`, `SIC_DESC`,
  `n_facilities` (count of facilities sharing that primary NAICS+SIC pair).
- **`naics_with_multiple_sic.csv`:** `NAICS_CODE`, `NAICS_DESC`, `n_distinct_sic`,
  `sic_codes` (semicolon-joined list).
- **`sic_with_multiple_naics.csv`:** `SIC_CODE`, `SIC_DESC`, `n_distinct_naics`,
  `naics_codes` (semicolon-joined list).

## Instructions to run

```bash
Rscript "code/diagnostics/naics_sic/check_naics_sic_mapping.R"
```
No dependency on other scripts; reads raw data directly.

## Notes / edge cases

- **Output location is an exception to this repo's convention.** All four CSVs write
  to `output/` directly (not `output/tables/`) and are **not timestamped** — a re-run
  silently overwrites the previous copy, unlike the timestamped-output convention used
  by most other diagnostics in this folder (e.g. `naics_california.R`).
- NAICS and SIC are independent classification systems, so differing descriptions for
  a mapped pair are expected and not themselves a data issue — the diagnostic signal
  is *multiplicity* (one code mapping to several on the other side), not description
  mismatch.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
