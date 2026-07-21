# README — `03_add_naics_sic.R`

** verified by Ali 7/17 **

question (7/17): how many have multiple NAICS or SIC? script currently just does primary code -- should it include all?
**resolved (7/21): yes.** 33 facilities had >1 NAICS code and 132 had >1 SIC code under
the old primary-only rule (out of 7,511) — but that undercounted the true multiplicity,
since it only surfaced multi-*permit* facilities with differing primary codes, not a
single permit carrying >1 code. The script now includes **every** code per facility
(semicolon-joined, primary first); 449 facilities' NAICS_CODE/SIC_CODE changed as a
result (161 now show >1 NAICS code, 466 show >1 SIC code), all other facilities and all
other panel columns are unchanged. Verified: every previously-single code is preserved
as the first entry in its facility's new value; row counts and NAICS/SIC coverage % are
identical to before across steps 03-06.

*Step 3 of the facility-by-month panel build. Input: step-02 panel + raw NAICS/SIC.
Output: the panel with all NAICS and all SIC codes per facility, primary code first.*

## Overview

Attaches each facility's **industry codes** (NAICS and SIC) as time-invariant
attributes, broadcast across all of the facility's months.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. ☒ All data publicly available.

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `data/processed/02_facility_month_panel_major_individual_inspections_2005_2025.csv` | `.csv` | `FACILITY_UIN`, `NPDES_ID` (semicolon list) |
| `data/raw/npdes_downloads/NPDES_NAICS.csv` | `.csv` | `NPDES_ID`, `NAICS_CODE`, `PRIMARY_INDICATOR_FLAG` |
| `data/raw/npdes_downloads/NPDES_SICS.csv` | `.csv` | `NPDES_ID`, `SIC_CODE`, `PRIMARY_INDICATOR_FLAG` |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| step-02 panel | input | facility × month | derived |
| `NPDES_NAICS.csv`, `NPDES_SICS.csv` | input (raw) | permit × code | via ECHO |
| `data/processed/03_facility_month_panel_major_individual_naics_sic_2005_2025.csv` | **output** | facility × year × month | derived |

## Computational Requirements

- **R** 4.4.2. Package: `data.table` (only). No `lubridate` (no dates handled here).
- **Controlled randomness:** none. **Memory/runtime:** trivial; seconds–minutes. `TODO:` OS/timing.

## Description of program

Split each facility's semicolon-separated `NPDES_ID` list back into individual permits;
look up **every** code per permit from each code file (not just the primary); recombine
to one semicolon-joined code string per facility, ordered so primary code(s) come first
and de-duplicated (order preserved, not alphabetical); left-join onto the panel.

## Decisions and Assumptions

1. **Industry code is time-invariant.** The code files carry no date/version, so a
   facility's code is a fixed attribute broadcast to all its months (unlike the
   month-varying inspection counts).
2. **Codes key to the permit, the panel to the facility.** The facility's `NPDES_ID`
   column is a semicolon list; it is split, each permit is looked up, and results are
   recombined to the facility. Codes come only from permits the panel already assigned
   to the facility — never from other permits at the site.
3. **All codes, primary first.** A permit can carry several NAICS (or SIC) codes; all
   are kept, ordered so the row flagged `PRIMARY_INDICATOR_FLAG == "Y"` comes first. (Prior
   to 2026-07-21 this kept only the primary code, same rule as
   `04_build_permit_panel_major_continuous.R`, now in `../EIL Summer/build/` — see the
   resolved question above.)
4. **Multi-value facilities ⇒ semicolon list, primary-first, deduped** — across a
   permit's multiple codes and/or a facility's multiple permits (matching step 01's
   `NPDES_ID` formatting).
5. **"Missing" = no row in the code file** ⇒ blank code (`""`, not NA), matching the
   project's missingness convention. NAICS coverage is sparse; SIC is near-complete for
   the major population.
6. **The panel defines the observation set** — left-join, no rows added or dropped.

**Helper logic:** `all_codes()` reads every (permit, code) row with an `IS_PRIMARY` flag
(no collapsing); NAICS and SIC are joined onto the facility-permit table **separately**
(not combined into one wide table — combining them would cross-join a permit's N naics
codes against its M sic codes and fabricate N×M rows); `collapse_primary_first()` orders
each facility's codes primary-first, drops blanks, de-duplicates preserving that order,
and pastes with `"; "` (empty string if none).

**Hardcoded parameters:** none — fully data-driven.

## Output columns (2)

`NAICS_CODE`, `SIC_CODE` (text; may be blank; semicolon-joined, primary code first, for
facilities with more than one code and/or more than one permit).

## Instructions to run

```bash
Rscript "scripts/build panel/03_add_naics_sic.R"
```
Run **after** step 02.

## Notes / edge cases

- A facility whose permit never appears in a code file → blank code (`""`).
- `PRIMARY_INDICATOR_FLAG == "Y"` rows sort first within a permit; a permit with no row
  flagged primary keeps its codes in the file's original order.
- Multi-code/multi-permit facilities: 161 now show >1 NAICS code, 466 show >1 SIC code
  (up from 33/132 under the old primary-only rule, since that undercounted single-permit
  facilities carrying more than one code).

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
