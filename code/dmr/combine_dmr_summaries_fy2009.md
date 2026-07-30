# README — `combine_dmr_summaries_fy2009.R`

*Third of the FY2025/FY2009 filter-pipeline trio — the FY2009 counterpart of
`combine_dmr_summaries.R`. Input: `code/dmr/01-04_dmr_fy2009*.csv` +
`output/DMR/raw_summary_fy2009.rds`. Output:
`output/DMR/2009_dmr_summaries_combined.xlsx`.*

## Overview

Identical logic and styling to `combine_dmr_summaries.R`, pointed at the FY2009
row-filter pipeline stages instead of FY2025's — a comparison/baseline year. Builds
one Excel workbook with 5 tabs (raw + 4 stages). See `combine_dmr_summaries.md` for
the full description of program logic, which is not repeated here since it's
identical; this README covers only what differs.

## Data Availability and Provenance Statements

Inputs are **derived data** — the FY2009 row-filter pipeline's four stage outputs
plus the raw-file summary object. See `filter_dmr_major_individual.md` through
`filter_dmr_c1q1.md` (run with `<FY> = 2009`) and `build_dmr_raw_summary.md` for the
underlying raw EPA provenance.

### Details on each data source

| File | Role |
|---|---|
| `output/DMR/raw_summary_fy2009.rds` | pre-computed raw-file summary, spliced in as tab 0 |
| `code/dmr/01_dmr_fy2009.csv` … `code/dmr/04_dmr_fy2009_00530_monloc1_c1q1.csv` | the four FY2009 row-filter pipeline stages |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `raw_summary_fy2009.rds` | input (derived) | serialized summary object | from `build_dmr_raw_summary.R 2009` |
| `01`–`04_dmr_fy2009*.csv` | input (derived) | permit × outfall × parameter × period, progressively filtered | from the row-filter pipeline run for FY2009 |
| `output/DMR/2009_dmr_summaries_combined.xlsx` | **output** | 5 sheets | derived — **fixed filename, overwritten each run, not timestamped** |

## Computational Requirements

Same as `combine_dmr_summaries.R` — **R** 4.4.2, packages `dplyr`, `data.table`,
`lubridate`, `openxlsx`; no randomness; reads each stage CSV whole with `fread`.

## Description of program

Same as `combine_dmr_summaries.R` — see that README. Only the fiscal year (2009
throughout), file paths, and output filename differ.

## Decisions and Assumptions

Same four points as `combine_dmr_summaries.R` apply identically (per-stage
descriptions, one shared workbook object, fixed non-timestamped filename,
`NROWS_LIMIT` testing switch). FY2009 was chosen as the comparison/baseline year
against FY2025 — see `make_dmr_funnel_fig.R`, which plots exactly this FY2009-vs-
FY2025 comparison.

## Output columns

Same shape as `combine_dmr_summaries.R`'s output: 5 sheets (`00_RawAllPermits`,
`01_MajorIndividual`, `02_TSS_00530`, `03_EffluentGross`, `04_C1Q1`), same 8-column
categorical / 9-column numeric layout.

## Instructions to run

```bash
Rscript code/dmr/combine_dmr_summaries_fy2009.R
```
No arguments. Requires `build_dmr_raw_summary.R 2009` and all four FY2009 stages of
the row-filter pipeline to have already run.

## Notes / edge cases

- **A stale comment remains in this script's own header**: its "Output:" line says
  `output/DMR/dmr_summaries_combined_fy2009_<timestamp>.xlsx` (timestamped), but the
  actual `OUT_FILE` in the code is the fixed, non-timestamped
  `2009_dmr_summaries_combined.xlsx` — the header comment disagrees with the code
  that follows it. Trust the code (and this README), not that line.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
