# README — `filter_dmr_c1q1.R`

*Step 4 (final) of the DMR row-filter pipeline. Input:
`code/dmr/03_dmr_fy<FY>_00530_monloc1.csv`. Output:
`code/dmr/04_dmr_fy<FY>_00530_monloc1_c1q1.csv`.*

## Overview

Further restricts the majors-under-individual, TSS-only, effluent-gross FY`<year>`
DMR file to `LIMIT_VALUE_TYPE_CODE IN ('C1', 'Q1')`. Pure row filter: all 57 columns
kept. `C1`/`C2`/`C3` are concentration-type limits (mg/L); `Q1`/`Q2` are
quantity/mass-type limits (lb/d, kg/d, g/d) — no EPA `REF_*` lookup table for this
exact code was found in `data/raw/reference/` to confirm the precise avg/max/min slot
each suffix maps to.

## Data Availability and Provenance Statements

Input is **derived data** from step 3 of this same pipeline — see
`filter_dmr_monloc1.md`, `filter_dmr_00530.md`, and `filter_dmr_major_individual.md`
for the chain back to the raw provenance.

### Details on each data source

| File | Key fields used |
|---|---|
| `code/dmr/03_dmr_fy<year>_00530_monloc1.csv` | all 57 columns; filtered on `LIMIT_VALUE_TYPE_CODE` |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `code/dmr/03_dmr_fy<year>_00530_monloc1.csv` | input (derived) | majors-under-individual, TSS, effluent-gross | from step 3 |
| `code/dmr/04_dmr_fy<year>_00530_monloc1_c1q1.csv` | **output** | same, restricted to C1/Q1 | derived (git-ignored) |

## Computational Requirements

- **R** 4.4.2. Packages: `DBI`, `duckdb`.
- **Controlled randomness:** none.
- **Memory/runtime:** DuckDB out-of-core, reading from step 3's already-narrowed CSV
  (this is the final, smallest stage of the four). `TODO:` OS/timing.

## Description of program

Prints the `LIMIT_VALUE_TYPE_CODE` × `STANDARD_UNIT_DESC` distribution of the step-3
input to console first, then DuckDB
`COPY (SELECT * FROM read_csv(...) WHERE LIMIT_VALUE_TYPE_CODE IN ('C1','Q1')) TO ...`.

## Decisions and Assumptions

1. **Only `C1` and `Q1` are kept**, not the fuller `C1/C2/C3`/`Q1/Q2` families — this
   is a deliberate narrowing to one concentration slot and one mass slot per the
   pipeline's design, not an attempt to capture every limit-value-type variant.
2. **The exact avg/max/min semantics of the `1` suffix are not independently
   confirmed against an EPA reference table** — flagged in the script's own header as
   an open item, not silently assumed.
3. **Requires step 3's output to already exist** — errors out pointing at
   `filter_dmr_monloc1.R <FY>` if `03_dmr_fy<year>_00530_monloc1.csv` is missing.

## Output columns

Same 57 columns as `03_dmr_fy<year>_00530_monloc1.csv` — pure row filter, no column
changes.

## Instructions to run

```bash
Rscript code/dmr/filter_dmr_c1q1.R <FY>
#   <FY>: fiscal year, e.g. 2025 — requires 03_dmr_fy<FY>_00530_monloc1.csv to exist already
```

## Notes / edge cases

- Verification step checks column-count parity and that the output contains exactly
  2 distinct `LIMIT_VALUE_TYPE_CODE` values (`C1` and `Q1`) — errors out if either
  fails.
- This is the final stage of the four; `build_dmr_raw_summary.R` /
  `combine_dmr_summaries*.R` (in the FY2025/FY2009 filter-pipeline trio) summarize
  this stage alongside the other three.
- Moved in from the root-level `dmr analysis/` folder 2026-07-29 — see
  `code/dmr/README.md`.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
