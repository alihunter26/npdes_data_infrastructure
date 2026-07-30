# README — `build_dmr_raw_summary.R`

*First of the FY2025/FY2009 filter-pipeline trio. Input: a raw per-fiscal-year DMR
zip in `data/raw/DMR/`. Output: `output/DMR/raw_summary_fy<FY>.rds`.*

## Overview

Computes the same kind of per-variable summary (categorical top-5 tables, numeric
five-number summaries, date ranges) that `combine_dmr_summaries*.R` produce for the
**filtered** row-filter-pipeline stages (01–04) — but for the **raw, unfiltered** FY
DMR file (every permit, every parameter, no restriction at all). This is the "stage
0" comparison point the combined workbooks splice in ahead of stage 1.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. ☒ All data publicly available.

### Details on each data source

| File | Key fields used |
|---|---|
| `data/raw/DMR/npdes_dmrs_fy<year>.zip` (member `NPDES_DMRS_FY<year>.csv`, 4.7–26.9M rows) | all 57 columns, classified into categorical/numeric/date groups (hardcoded — see Decisions) |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `NPDES_DMRS_FY<year>.csv` (in its zip) | input (raw) | permit × outfall × parameter × period | via ECHO |
| `output/DMR/raw_summary_fy<year>.rds` | **output** | a serialized `summary_list` (meta/cat/num/date), not a CSV or workbook | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `DBI`, `duckdb`, `data.table`.
- **Controlled randomness:** none — every statistic is computed by exact SQL
  aggregation (`quantile_cont`, `avg`, `min`/`max`, `mode`), not sampled.
- **Memory/runtime:** DuckDB out-of-core — the raw file (4.7–26.9M rows × 57 columns)
  risks an OOM crash if fully materialized in R on this 8 GB machine. The raw data is
  loaded into a DuckDB table (spills to disk beyond `MEM_LIMIT`) and never pulled into
  R as a data.frame; only the small aggregated results are. `TODO:` OS/timing.

## Description of program

Decompress the zip's CSV member to a gzip scratch temp (reused across runs if
present), load the whole file into one DuckDB table (`CREATE TABLE raw AS SELECT *
FROM read_csv(..., all_varchar=true)`), then compute every statistic via SQL:
categorical top-5 + category count + % missing per column (with paired `_DESC`
lookups via `mode()`), numeric five-number summary via one combined single-pass
query for all numeric columns, and date ranges the same way after parsing with
`try_strptime`. Assembles the result into the exact `list(meta, cat, num, date)`
structure `combine_dmr_summaries*.R`'s `write_sheet()` expects, and serializes it
with `saveRDS()` rather than writing a workbook itself.

## Decisions and Assumptions

1. **Column classification (categorical/numeric/date) is hardcoded**, not inferred
   at runtime — it was extracted from what `fread`/`combine_dmr_summaries.R` already
   inferred for the filtered `01_dmr_fy2025.csv`, on the reasoning that the raw and
   filtered files share the same schema, so the same classification applies to the
   unfiltered file too.
2. **All-varchar read, cast per-statistic in SQL** — the raw file is loaded into
   DuckDB with every column as text (`all_varchar=true`), then each numeric/date
   value is `try_cast`/`try_strptime` at query time rather than relying on DuckDB's
   own type sniffing, matching this repo's `colClasses = "character"` convention
   elsewhere.
3. **`DESC_PAIR` is a list, not a named atomic vector** — deliberately, so that `[[`
   on a code with no paired description column returns `NULL` (atomic-vector `[[`
   would instead throw "subscript out of bounds").
4. **Output is an `.rds`, not a workbook** — this script never writes an Excel file
   itself; it's meant to be loaded by `combine_dmr_summaries*.R` and spliced in as
   that workbook's first sheet, so the raw-file summary is computed once and reused,
   not recomputed inside each combined-workbook build.

## Output columns

Not a flat table — a serialized R list with four elements: `meta` (title/high-level
sentence/summary line/full column list), `cat` (categorical top-5 data frame +
group sizes), `num` (numeric five-number-summary data frame), `date` (date-range
data frame). Same shape `combine_dmr_summaries*.R`'s `write_sheet()` consumes for
every other stage.

## Instructions to run

```bash
Rscript code/dmr/build_dmr_raw_summary.R <FY>
#   <FY>: fiscal year, e.g. 2025
```
No dependency on the row-filter pipeline's own output — reads the raw zip directly.
Must run before `combine_dmr_summaries.R`/`combine_dmr_summaries_fy2009.R` for the
same FY, since those load this script's `.rds` rather than recomputing it.

## Notes / edge cases

- Reuses an existing gzip scratch temp across runs if present (`REUSE_GZ <- TRUE`) —
  same convention as the row-filter pipeline scripts.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
