# README — `summarize_year_coverage.R`

*A cross-tab coverage scan across raw source files, not a per-variable summary or a
panel check. Input: every CSV in `data/raw/` (column-header scan only, cheap even for
multi-GB files). Output: one heatmap-styled Excel workbook.*

## Overview

Answers: which years actually appear in which raw file's DATE/YEAR-named columns,
across the whole of `data/raw/`? Built to be cheap enough to run against every raw
file — including multi-GB ones like `NPDES_LIMITS.csv` — by reading only columns
whose *name* contains `DATE` or `YEAR`, never a full-file scan.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. ☒ All data publicly available.

### Details on each data source

Every `*.csv` found recursively under `data/raw/` (`list.files(..., recursive = TRUE)`)
is a candidate. A file is **skipped** (not an error) if its header contains no column
whose name matches `DATE` or `YEAR` (case-insensitive) — reported in the console at
the end, not silently dropped. For files that do match, only the matching columns are
read (`fread(select = ycols, colClasses = "character")`), never the whole file.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| every `*.csv` in `data/raw/` (recursive) | input (raw) | varies by file | via ECHO |
| `output/year_coverage_<timestamp>.xlsx` | **output** | one row per (file, DATE/YEAR variable), one column per year observed anywhere | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `openxlsx`.
- **Controlled randomness:** none.
- **Memory/runtime:** column-name-only filtering keeps this cheap even for the
  multi-GB files in `data/raw/` — only the matching DATE/YEAR columns are ever read
  into memory, as character, for any given file. `TODO:` OS/timing.

## Description of program

For each raw CSV: read its header, keep only columns whose name contains `DATE` or
`YEAR`; if none match, skip the file. For each matching column, extract a year from
every value via a 4-digit regex (`\d{4}`) — **the last** such run for a `DATE`-named
column (handles `mm/dd/yyyy → yyyy`, and is robust to separator-less dates like
`"10062005" → 2005`), **the first** such run for a `YEAR`-named column (handles
`YEARQTR` values like `"19924" → 1992`). Tabulate observation counts per year for that
(file, variable) pair. Assemble one row per (file, variable) and one column per year
seen anywhere across all files/variables into a single sparse count matrix, then write
it as a merged-file-column, green-gradient-shaded Excel sheet.

## Decisions and Assumptions

1. **Years are never dropped by default** (`YEAR_MIN`/`YEAR_MAX <- NULL`) — every year
   that appears anywhere, however implausible (e.g. `1`, `2914`, `8201`), is kept in the
   table. This is a deliberate "flag but keep" choice: the script still prints any year
   outside a *plausible* window to the console as a warning, but does not filter the
   table itself. Set `YEAR_MIN`/`YEAR_MAX` to actually drop columns if you want that
   instead.
2. **The "plausible" window (`PLAUSIBLE_MIN = 1950`, `PLAUSIBLE_MAX = 2100`) is a
   console-only flag, not a filter.** Future expiration dates are legitimate (permits
   can expire years out), so the upper bound is generous — the flag exists to surface
   obvious garbage values, not to enforce a hard range.
3. **DATE columns use the *last* 4-digit run; YEAR columns use the *first*.** This
   asymmetry is deliberate: a full date's year is at the end (`mm/dd/yyyy`), while a
   composite year field like `YEARQTR` puts the year first and a suffix (quarter)
   after it.
4. **The heatmap coloring is per-row, not global.** Each (file, variable) row's non-zero
   cells are bucketed into the 5-color gradient using **that row's own** quantile
   breaks (`quantile(nonzero, probs = seq(0, 1, length.out = 6), type = 1)`) — so a
   file with 50 rows/year and a file with 5 million rows/year each get a readable
   within-row gradient, rather than the small file washing out entirely under one
   global scale.
5. **A leading-zero year string (`"0000"` read as `"0"` by `fread`) is caught
   explicitly** (`grepl("^0+$", uvals)`) so it doesn't silently vanish from the lookup.

## Output columns

Single worksheet ("Year Coverage"): `File` (merged across each file's variable rows),
`Variable`, then one column per year present anywhere in the scanned data (header =
the year, cell = observation count for that (file, variable, year), blank = zero).
Frozen header row and first two columns; sorted by file, in scan order.

## Instructions to run

```bash
Rscript code/summary/summarize_year_coverage.R
```
No arguments. Scans all of `data/raw/` every run; no dependency on the built panel or
other scripts.

## Notes / edge cases

- **Skipped files** (no DATE/YEAR-named column) are listed by name in the console
  report — check this list if a file you expected to see coverage for is missing from
  the workbook entirely.
- **Flagged year outliers** print to console (file, variable, and the specific
  out-of-window years) but remain in the workbook — cross-check the console output
  after each run rather than assuming the sheet is already clean.
- Column name matching (`DATE|YEAR`) is case-insensitive and matches on substring, so
  a column like `UPDATED_DATE` or `REPORTINGCYCLE`-style year fields are both picked
  up without a per-file allowlist — but also means any future column merely containing
  "date" or "year" in its name (even non-temporal) would be swept in.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
