# README — `naics_california.R`

*A standalone **diagnostic** (not a panel-building step). Input: raw NAICS, facility,
and permit files. Output: one timestamped CSV of California NAICS records.*

## Diagnostic Context

**1. What issue is this script designed to give us information about?**
Whether having a NAICS code on file correlates with permit type (Individual vs.
General) or major/minor status — using California as a manageable test case before
running this at national scale.

**2. What do we learn from the information created by this script?**
Of 150 CA NAICS records (145 distinct permits, from the 2026-07-22 run): 126 are
General permits vs. only 7 Individual; 136 are Minor, 0 confirmed Major (14
blank/unmatched). Facilities that *do* have a NAICS code skew overwhelmingly toward
General/Minor — the opposite end of the population from where the panel actually
lives.

*How fully have we dug in?* ~50%. This is explicitly a single-state spot check, built
as a "see at a glance" tool, never extended to a systematic state-by-state or national
test of this specific association (permit type vs. NAICS presence — a related but
distinct question from the *coverage rate* answered nationally by
`naics_sic_coverage_by_state_year.R`).

**3. What are the implications of what we learned for our issue?**
Suggestive, not conclusive at national scale. If the CA pattern holds broadly, NAICS
presence isn't missing-at-random — it's tied to permit type — reinforcing
`docs/missingness.md`'s guidance that NAICS shouldn't be used as a covariate without
controlling for permit vehicle. This should not be treated as a settled national
finding.

## Overview

Subsets `NPDES_NAICS.csv` to California facilities, annotated with each permit's
current type (Individual/General/&hellip;) and major/minor status, so it's easy to see
at a glance whether CA permits carrying a NAICS code are general/minor/non-NPDES
permits or major individual dischargers.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. &boxtimes; All data publicly available.

### Details on each data source

| File | Key fields used |
|---|---|
| `data/raw/npdes_downloads/NPDES_NAICS.csv` | `NPDES_ID`, `NAICS_CODE`, `NAICS_DESC`, `PRIMARY_INDICATOR_FLAG` |
| `data/raw/npdes_downloads/ICIS_FACILITIES.csv` | `NPDES_ID`, `STATE_CODE` (`NPDES_NAICS.csv` has no state field of its own) |
| `data/raw/npdes_downloads/ICIS_PERMITS.csv` | `EXTERNAL_PERMIT_NMBR`, `VERSION_NMBR`, `PERMIT_TYPE_CODE`, `MAJOR_MINOR_STATUS_FLAG` |

All three read via `fread(select = ..., colClasses = "character")`.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `NPDES_NAICS.csv`, `ICIS_FACILITIES.csv`, `ICIS_PERMITS.csv` | input (raw) | various | via ECHO |
| `output/tables/npdes_naics_california_<timestamp>.csv` | **output** | one NAICS record for a CA `NPDES_ID` | derived |

## Computational Requirements

- **R** 4.4.2. Package: `data.table`.
- **Controlled randomness:** none (output filename timestamp is the only
  non-deterministic part).
- **Memory/runtime:** all three inputs selectively column-read; small/fast. `TODO:` OS/timing.

## Description of program

Read the three files with only the needed columns; join `STATE_CODE` onto the NAICS
records via `NPDES_ID` and filter to `"CA"`; join in each permit's **current version**
(`VERSION_NMBR == "0"`) `PERMIT_TYPE_CODE` and `MAJOR_MINOR_STATUS_FLAG`; derive a
friendlier `PERMIT_VEHICLE` label from the type code; print rollups by vehicle and by
major/minor, then write the full annotated table.

## Decisions and Assumptions

1. **"Current version" means `VERSION_NMBR == 0`.** Both `PERMIT_TYPE_CODE` and
   `MAJOR_MINOR_STATUS_FLAG` are read from that one row per permit, not reconstructed
   across the permit's full version history — this is a present-day snapshot, not a
   time series.

**`PERMIT_TYPE_CODE` &rarr; `PERMIT_VEHICLE` lookup:** `NPD`&rarr;"Individual",
`GPC`&rarr;"General", `IIU`/`SIN`&rarr;"Individual (non-NPDES)",
`NGP`&rarr;"General (non-NPDES)", `UFT`/`APR`&rarr;"Not a permit",
`SNN`&rarr;"Other (non-NPDES)".

## Output columns

One row per NAICS record for a California `NPDES_ID` (not deduplicated to one row per
facility — a facility with 2 NAICS codes appears twice): `NPDES_ID`, `STATE_CODE`,
`PERMIT_TYPE_CODE`, `PERMIT_VEHICLE`, `MAJOR_MINOR_STATUS_FLAG`, `NAICS_CODE`,
`NAICS_DESC`, `PRIMARY_INDICATOR_FLAG`.

## Instructions to run

```bash
Rscript "code/diagnostics/naics_sic/naics_california.R"
```
No dependency on other scripts; reads raw data directly.

## Notes / edge cases

- A facility whose `NPDES_ID` doesn't match any row in `ICIS_PERMITS.csv` with
  `VERSION_NMBR == 0` gets `NA` for `PERMIT_TYPE_CODE`/`PERMIT_VEHICLE`/
  `MAJOR_MINOR_STATUS_FLAG` rather than being dropped.
- Output correctly follows the repo's `output/tables/<name>_<timestamp>.csv`
  convention (unlike `check_naics_sic_mapping.R` in the same folder, which does not).

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
