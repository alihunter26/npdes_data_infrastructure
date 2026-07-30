# README — `combine_dmr_summaries.R`

*Second of the FY2025/FY2009 filter-pipeline trio (this one is FY2025-specific).
Input: `code/dmr/01-04_dmr_fy2025*.csv` + `output/DMR/raw_summary_fy2025.rds`. Output:
`output/DMR/2025_dmr_summaries_combined.xlsx`.*

## Overview

Builds **one** Excel workbook with 5 tabs — the raw-file summary (tab 0, from
`build_dmr_raw_summary.R`'s `.rds`) plus one tab per stage of the FY2025 DMR
row-filter pipeline (01 Major-Individual → 02 TSS(00530) → 03 Effluent Gross →
04 C1/Q1). This is the multi-tab equivalent of running `code/summary/summarize.R`'s
`dmrs` dataset four times — same styling and summary logic, but combined into one
shared workbook instead of four separate files, since `openxlsx`'s style objects
aren't safely mergeable across independently-built workbooks after the fact.

## Data Availability and Provenance Statements

Inputs are **derived data** — the FY2025 row-filter pipeline's four stage outputs
plus the raw-file summary object. See `filter_dmr_major_individual.md` through
`filter_dmr_c1q1.md` and `build_dmr_raw_summary.md` for the underlying raw EPA
provenance.

### Details on each data source

| File | Role |
|---|---|
| `output/DMR/raw_summary_fy2025.rds` | pre-computed raw-file summary, spliced in as tab 0 |
| `code/dmr/01_dmr_fy2025.csv` … `code/dmr/04_dmr_fy2025_00530_monloc1_c1q1.csv` | the four row-filter pipeline stages, read fresh in this script |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `raw_summary_fy2025.rds` | input (derived) | serialized summary object | from `build_dmr_raw_summary.R` |
| `01`–`04_dmr_fy2025*.csv` | input (derived) | permit × outfall × parameter × period, progressively filtered | from the row-filter pipeline |
| `output/DMR/2025_dmr_summaries_combined.xlsx` | **output** | 5 sheets (one per stage + raw) | derived — **fixed filename, overwritten each run, not timestamped** |

## Computational Requirements

- **R** 4.4.2. Packages: `dplyr`, `data.table`, `lubridate`, `openxlsx`.
- **Controlled randomness:** none.
- **Memory/runtime:** reads each of the 4 stage CSVs whole with `fread` (already
  narrowed by the row-filter pipeline, so far smaller than the raw file); the raw-file
  tab is loaded pre-computed from the `.rds`, not recomputed. `TODO:` OS/timing.

## Description of program

Loads `raw_summary_fy2025.rds` and writes it as tab `00_RawAllPermits` first. Then,
for each of the 4 `STAGES` entries (csv path, tab name, stage-specific
description/summary text), reads the CSV, computes the categorical/numeric/date
summary (identical helper functions to `code/summary/summarize.R`'s `dmrs` entry,
copied rather than shared — see Decisions), and writes it as its own tab into the
same shared `wb` workbook object. Saves once at the end.

## Decisions and Assumptions

1. **Each stage gets its own hardcoded description/summary text**, unlike
   `summarize.R`'s `dmrs` entry (a single description for one file) — because the 4
   stages are progressively narrower row filters of the *same* underlying file, not 4
   unrelated datasets, so each tab needs to say specifically what *that* stage
   represents.
2. **One shared workbook object, not a post-hoc file merge** — `openxlsx`'s
   `cloneWorksheet()` only copies a sheet within a single workbook; style indices
   aren't safely mergeable across two independently-built workbook objects. Rerunning
   the summarizer once per stage into one shared `wb` is the robust way to combine
   them.
3. **Fixed output filename, not timestamped** — `2025_dmr_summaries_combined.xlsx` is
   overwritten on every run, unlike almost every other output in this repo. This is
   the deliberate exception noted in `code/dmr/README.md`'s Conventions section.
4. **`NROWS_LIMIT` can be set to a number** (e.g. `500000`) to read only that many
   rows per stage while testing; `NULL` (default) reads each file in full.

## Output columns

Not a flat table — an Excel workbook, 5 sheets total: `00_RawAllPermits` (from the
`.rds`) plus `01_MajorIndividual`, `02_TSS_00530`, `03_EffluentGross`, `04_C1Q1`. Each
sheet has the same layout as `code/summary/summarize.R`'s output (8-column
categorical / 9-column numeric, trailing blank "Missing Explanation" column).

## Instructions to run

```bash
Rscript code/dmr/combine_dmr_summaries.R
```
No arguments. Requires `build_dmr_raw_summary.R 2025` and all four FY2025 stages of
the row-filter pipeline (`filter_dmr_major_individual.R 2025` through
`filter_dmr_c1q1.R 2025`) to have already run — stops with a clear error naming the
missing file if any stage's CSV or the `.rds` isn't found.

## Notes / edge cases

- Uploading this single multi-sheet `.xlsx` to Google Sheets preserves every sheet as
  its own tab — noted in the script's own header as a reason for combining rather
  than shipping 5 separate files.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
