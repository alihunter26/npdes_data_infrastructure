# README — `filter_dmr_monloc1.R`

*Step 3 of the DMR row-filter pipeline. Input: `code/dmr/02_dmr_fy<FY>_00530.csv`.
Output: `code/dmr/03_dmr_fy<FY>_00530_monloc1.csv`.*

## Overview

Further restricts the majors-under-individual, TSS-only FY`<year>` DMR file to
Effluent Gross monitoring locations: `MONITORING_LOCATION_CODE IN ('1', 'EG')` (both
map to "Effluent Gross" per EPA's `REF_MONITORING_LOCATION` reference table). Pure row
filter: all 57 columns kept.

## Data Availability and Provenance Statements

Input is **derived data** from step 2 of this same pipeline — see
`filter_dmr_00530.md` and `filter_dmr_major_individual.md` for the underlying raw
provenance.

### Details on each data source

| File | Key fields used |
|---|---|
| `code/dmr/02_dmr_fy<year>_00530.csv` | all 57 columns; filtered on `MONITORING_LOCATION_CODE` |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `code/dmr/02_dmr_fy<year>_00530.csv` | input (derived) | majors-under-individual, TSS only | from step 2 |
| `code/dmr/03_dmr_fy<year>_00530_monloc1.csv` | **output** | same, restricted to effluent-gross | derived (git-ignored) |

## Computational Requirements

- **R** 4.4.2. Packages: `DBI`, `duckdb`.
- **Controlled randomness:** none.
- **Memory/runtime:** DuckDB out-of-core, reading from step 2's already-narrowed CSV.
  `TODO:` OS/timing.

## Description of program

Prints the `MONITORING_LOCATION_CODE` distribution of the step-2 input to console
first (so both codes' relative volume is visible before filtering), then DuckDB
`COPY (SELECT * FROM read_csv(...) WHERE MONITORING_LOCATION_CODE IN ('1','EG')) TO
...`.

## Decisions and Assumptions

1. **Both `'1'` and `'EG'` are accepted as "Effluent Gross"** — the bulk DMR files
   predominantly use `'1'`, but EPA's own reference table maps both codes to the same
   meaning, so both are kept rather than picking one and silently dropping rows coded
   the other way.
2. **Requires step 2's output to already exist** — errors out pointing at
   `filter_dmr_00530.R <FY>` if `02_dmr_fy<year>_00530.csv` is missing.

## Output columns

Same 57 columns as `02_dmr_fy<year>_00530.csv` — pure row filter, no column changes.

## Instructions to run

```bash
Rscript code/dmr/filter_dmr_monloc1.R <FY>
#   <FY>: fiscal year, e.g. 2025 — requires 02_dmr_fy<FY>_00530.csv to exist already
```

## Notes / edge cases

- Verification step checks column-count parity and that the output contains exactly
  2 distinct `MONITORING_LOCATION_CODE` values (`'1'` and `'EG'`) — errors out if
  either fails.
- Moved in from the root-level `dmr analysis/` folder 2026-07-29 — see
  `code/dmr/README.md`.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
