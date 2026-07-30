# README — `filter_dmr_00530.R`

*Step 2 of the DMR row-filter pipeline. Input: `code/dmr/01_dmr_fy<FY>.csv`. Output:
`code/dmr/02_dmr_fy<FY>_00530.csv`.*

## Overview

Further restricts the majors-under-individual FY`<year>` DMR file (built by
`filter_dmr_major_individual.R`) to `PARAMETER_CODE = '00530'` (Solids, total
suspended — TSS). Pure row filter: all 57 columns kept.

## Data Availability and Provenance Statements

Input is **derived data** from step 1 of this same pipeline, not a raw EPA download
directly — see `filter_dmr_major_individual.md` for the underlying raw provenance.

### Details on each data source

| File | Key fields used |
|---|---|
| `code/dmr/01_dmr_fy<year>.csv` | all 57 columns; filtered on `PARAMETER_CODE` |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `code/dmr/01_dmr_fy<year>.csv` | input (derived) | majors-under-individual, all params | from step 1 |
| `code/dmr/02_dmr_fy<year>_00530.csv` | **output** | same, restricted to TSS | derived (git-ignored) |

## Computational Requirements

- **R** 4.4.2. Packages: `DBI`, `duckdb`.
- **Controlled randomness:** none.
- **Memory/runtime:** DuckDB out-of-core, reading directly from the step-1 CSV (already
  much smaller than the raw FY file). `TODO:` OS/timing.

## Description of program

DuckDB `COPY (SELECT * FROM read_csv(...) WHERE PARAMETER_CODE = '00530') TO ...` —
a single-condition row filter, streamed straight to the output CSV.

## Decisions and Assumptions

1. **No parameter other than `00530` (TSS) is considered** — this pipeline is
   TSS-specific from this step onward; a different pollutant would need a parallel
   run with a different `PARAM` value edited into the script.
2. **Requires step 1's output to already exist** — errors out with a clear message
   pointing at `filter_dmr_major_individual.R <FY>` if `01_dmr_fy<year>.csv` is
   missing, rather than silently doing nothing.

## Output columns

Same 57 columns as `01_dmr_fy<year>.csv` — pure row filter, no column changes.

## Instructions to run

```bash
Rscript code/dmr/filter_dmr_00530.R <FY>
#   <FY>: fiscal year, e.g. 2025 — requires 01_dmr_fy<FY>.csv to exist already
```

## Notes / edge cases

- Verification step checks column-count parity and that the output contains exactly
  one distinct `PARAMETER_CODE` — errors out (leaving the output in place for
  inspection) if either fails.
- Moved in from the root-level `dmr analysis/` folder 2026-07-29 — see
  `code/dmr/README.md`.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
