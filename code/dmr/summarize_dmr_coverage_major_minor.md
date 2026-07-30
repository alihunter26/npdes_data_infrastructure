# README — `summarize_dmr_coverage_major_minor.R`

*A standalone diagnostic (not a panel-building step). Input: `ICIS_PERMITS.csv` +
6 fiscal years of raw DMR zips. Output: one green-gradient Excel workbook.*

## Overview

DMR reporting coverage for Major vs. Minor facilities, fiscal years 2015–2020. One
table (mirroring `summarize_year_coverage.R`'s style): rows = metric × class,
columns = fiscal year, cells shaded by a green (YlGn) gradient. Answers: how many
major/minor permits actually reported DMR data each year, and what share of the
all-time major/minor population does that represent?

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. ☒ All data publicly available.

### Details on each data source

| File | Key fields used |
|---|---|
| `data/raw/npdes_downloads/ICIS_PERMITS.csv` | `EXTERNAL_PERMIT_NMBR`, `MAJOR_MINOR_STATUS_FLAG` — builds the one-class-per-permit map |
| `data/raw/DMR/npdes_dmrs_fy<year>.zip` for `year` in 2015:2020 | `EXTERNAL_PERMIT_NMBR` only, streamed via `unzip -p` |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `ICIS_PERMITS.csv` | input (raw) | permit × version | via ECHO |
| 6 fiscal years of DMR zips (2015–2020) | input (raw) | one column streamed per file | via ECHO |
| `output/dmr_coverage_major_minor_<timestamp>.xlsx` | **output** | 6 metric rows × 6 fiscal-year columns | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `openxlsx`.
- **Controlled randomness:** none.
- **Memory/runtime:** each fiscal year's DMR file is streamed via `unzip -p` and only
  `EXTERNAL_PERMIT_NMBR` is read — one column of a multi-GB file, not the whole
  thing — then discarded (`rm(d); gc()`) before moving to the next year. `TODO:`
  OS/timing.

## Description of program

Build a one-class-per-`NPDES_ID` map from `ICIS_PERMITS.csv` (`"Major"` if any
version row is flagged `"M"`, `"Minor"` if any is `"N"` and none is `"M"`, dropped if
neither). For each of the 6 fiscal years, stream just the permit-ID column from that
year's DMR zip, attach the major/minor class, and tabulate distinct reporting
facilities and total DMR rows per class. Shape into a 6-row × 6-column matrix (3
metrics × 2 classes) and write it as one green-gradient-shaded sheet, each row
bucketed by its own year-to-year range (same row-wise gradient technique as
`summarize_year_coverage.R`).

## Decisions and Assumptions

1. **Each DMR file is attributed wholly to its fiscal year** — no per-row date
   parsing; a federal fiscal year runs Oct–Sep, and the whole file is treated as
   that FY's data.
2. **The coverage-percent denominator is a fixed, all-period count** of distinct
   major (resp. minor) permits from `ICIS_PERMITS.csv` — not that year's active
   permit count. This means early-year coverage reads as "share of *ever*-major/minor
   permits reporting that year," not "share of that year's active population." Read
   the year-over-year *trend*, not the absolute coverage level, as the meaningful
   signal.
3. **Class is assigned once per `NPDES_ID`, pooled across all permit versions** — a
   permit that is `"M"` in any version is `"Major"` for every year in this table,
   never split by year.
4. **Permits with no `"M"` or `"N"` flag anywhere (blank in every version) are
   excluded entirely** from both the denominator and the per-year counts, rather than
   being folded into either class.

## Output columns

One worksheet ("DMR Coverage"): `Metric` (row label) × `FY2015`…`FY2020` (columns).
Six metric rows: `Major/Minor - facilities reporting`, `Major/Minor - DMR records`,
`Major/Minor - coverage %` — each cell's fill color is a green-gradient bucket
computed from that row's own values across the 6 years (not a global scale).

## Instructions to run

```bash
Rscript code/dmr/summarize_dmr_coverage_major_minor.R
```
No arguments. `YEARS <- 2015:2020` is hardcoded at the top of the script — edit
there to change the range. No dependency on the row-filter pipeline or the built
panel.

## Notes / edge cases

- The FY2015–2020 window is hardcoded, not derived from what DMR files happen to be
  present in `data/raw/DMR/` — running it with a year outside that range absent from
  disk will error on the missing zip rather than silently skipping it.
- Percentage rows and count rows use different number formats in the workbook
  (`0.0` vs. `#,##0`) even though they share the same green-gradient coloring logic.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
