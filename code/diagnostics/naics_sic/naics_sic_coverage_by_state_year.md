# README — `naics_sic_coverage_by_state_year.R`

*A standalone **diagnostic** (not part of `run_all.R`). Input: raw permits, facilities,
NAICS/SIC files. Output: one timestamped state&times;year coverage CSV, feeding
`make_naics_sic_coverage_brief.R`.*

## Diagnostic Context

**1. What issue is this script designed to give us information about?**
Among major-individual permits specifically — the population the panel actually
studies — what share have a NAICS code on file vs. a SIC code, and does that coverage
vary meaningfully by state or over time (2005&ndash;2025)?

**2. What do we learn from the information created by this script?**
Across 139,992 major-individual permit-years, 56 states/territories: SIC coverage is
98.7% nationally, but NAICS coverage is only 35.9%. 10 states have NAICS coverage
&ge;95%; 16 states have essentially 0% NAICS coverage; 2 states (ND, VT) fall below 90%
SIC coverage (all figures confirmed in
`docs/institutional_briefs/naics_sic_coverage_numbers.tex`).

*How fully have we dug in?* ~100% — this is the one diagnostic chain in the whole
folder carried all the way through: raw data &rarr; coverage table &rarr; LaTeX brief
&rarr; published PDF (`docs/institutional_briefs/naics_sic_coverage_by_state.pdf`).

**3. What are the implications of what we learned for our issue?**
Directly operationalizes `docs/missingness.md`'s guidance: SIC, not NAICS, is the
panel's industry variable (~99% vs. ~36%), confirmed at every level (national, and
near-uniform >90% SIC coverage across states except ND/VT). The 16 near-zero-NAICS
states would make any NAICS-based state-level analysis undefined for roughly a sixth
of the sample — this closes off NAICS entirely as a usable covariate, not just
"mostly missing."

## Overview

For major-individual permits, reconstructed year by year 2005&ndash;2025, computes what
share had a NAICS code on file and what share had a SIC code, broken out by state and
year.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. &boxtimes; All data publicly available.

### Details on each data source

| File | Key fields used |
|---|---|
| `data/raw/npdes_downloads/ICIS_PERMITS.csv` | `EXTERNAL_PERMIT_NMBR`, `PERMIT_TYPE_CODE`, `MAJOR_MINOR_STATUS_FLAG`, `PERMIT_STATUS_CODE`, `VERSION_NMBR`, `EFFECTIVE_DATE`, `ISSUE_DATE`, `ORIGINAL_ISSUE_DATE`, `EXPIRATION_DATE`, `TERMINATION_DATE` |
| `data/raw/npdes_downloads/ICIS_FACILITIES.csv` | `NPDES_ID`, `STATE_CODE` |
| `data/raw/npdes_downloads/NPDES_NAICS.csv` | `NPDES_ID` only (existence test) |
| `data/raw/npdes_downloads/NPDES_SICS.csv` | `NPDES_ID` only (existence test) |

All read via `fread(select = ..., colClasses = "character")`.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `ICIS_PERMITS.csv`, `ICIS_FACILITIES.csv`, `NPDES_NAICS.csv`, `NPDES_SICS.csv` | input (raw) | various | via ECHO |
| `output/tables/naics_sic_coverage_by_state_year_<timestamp>.csv` | **output** | one row per (state, year) | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `lubridate`.
- **Controlled randomness:** none.
- **Memory/runtime:** selective-column reads of the permits/facilities/NAICS/SIC
  files; fast. `TODO:` OS/timing.

## Description of program

Restrict `ICIS_PERMITS.csv` to individual permits (`PERMIT_TYPE_CODE == "NPD"`);
determine, from each version's effective date, a per-(permit, effective-year)
major/minor flag (minor wins if any version that year is minor); carry that flag
forward across years with a rolling join, truncated at a status-aware "held through"
year computed from the **current** version (`VERSION_NMBR == 0`); join in state and
NAICS/SIC existence; aggregate counts and percentages by state &times; year; print a
national-by-year sanity check; write the timestamped CSV.

## Decisions and Assumptions

1. **Closure is status-aware, not just "max expiration date."** A permit is held
   through `YEAR_MAX` (2025) unless its current version (`VERSION_NMBR == 0`) is
   `TRM` (terminated &rarr; closes at termination/expiration year) or `EXP` (lapsed
   &rarr; closes at expiration year); any other status (including administratively
   continued, `ADC`) is treated as still active. Using expiration date alone would
   incorrectly drop administratively-continued majors that are still active — ~1,578
   such permits, per the script's header comment. A permit with no `VERSION_NMBR == 0`
   row defaults to active (held through `YEAR_MAX`).
2. **NAICS/SIC coverage is a fixed, time-invariant attribute.** Presence in
   `NPDES_NAICS.csv`/`NPDES_SICS.csv` has no date field, so "has a NAICS code" means
   *ever* has one on file, not "had one in that specific year."
3. **Permits are not required to be major every year** — each year gets its own
   population reconstructed from that year's effective major/minor flag, so a permit
   can enter/exit the major-individual population as its status changes; there is no
   "major in every year" filter.

**Hardcoded parameters:** `YEAR_MIN = 2005L`, `YEAR_MAX = 2025L`.

## Output columns

One row per `STATE_CODE` &times; `year`: `n_permits`, `n_naics`, `pct_naics` (1 dp),
`n_sic`, `pct_sic` (1 dp).

## Instructions to run

```bash
Rscript "code/diagnostics/naics_sic/naics_sic_coverage_by_state_year.R"
```
No dependency on other scripts; reads raw data directly. Its output is a required
input for `code/diagnostics/brief_generators/make_naics_sic_coverage_brief.R` — run
this script first if a fresh brief is needed.

## Notes / edge cases

- Console output prints a national-by-year table and a pooled national percentage as
  an eyeball sanity check before the CSV is written.
- Rows with blank/missing `STATE_CODE` are dropped from the aggregation.
- Output correctly follows the repo's `output/tables/<name>_<timestamp>.csv` convention.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
