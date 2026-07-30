# README — `summarize.R`

*The single registry-driven entry point for per-dataset variable summaries — not a
panel-building step. Input: a raw ICIS-NPDES bulk file (selected via a `DATASETS`
registry entry). Output: a timestamped Excel workbook, one sheet per input table.*

## Overview

One script that builds the per-dataset summary workbook for any of 8 raw datasets
(`npdes`, `dmrs`, `attains`, `eff_violations`, `eff_violations_state`, `limits`,
`master_general_permits`, `outfalls_layer`) instead of 8 separate copy-pasted scripts.
For every variable it reports: percent missing, distinct-category count and top-5
frequent values (with a code → description lookup when a paired `_DESC` column
exists), and a numeric/date five-number summary (min / 5th pct / median / mean / 95th
pct / max). This describes an **input dataset**; it does not touch the built panel —
see `summarize_panel.R` and `summarize_violation_types.R` for that.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. ☒ All data publicly available.

### Details on each data source

| Dataset key | Source file(s) | Mode |
|---|---|---|
| `npdes` | one CSV in `data/raw/npdes_downloads/` (default `NPDES_QNCR_HISTORY.csv`; `arg = "all"` runs every CSV in the folder, one sheet each) | memory |
| `attains` | every non-empty CSV in `data/raw/Attains/` | memory |
| `limits` | `data/raw/NPDES_LIMITS.csv` (~7 GB; several ID columns dropped before reading — see Decisions) | memory |
| `master_general_permits` | `data/raw/Master General Permits/ICIS_MASTER_GENERAL_PERMITS.csv` | memory |
| `outfalls_layer` | `data/raw/npdes_outfalls_layer.csv` | memory |
| `dmrs` | `NPDES_DMRS_FY2025.csv`, streamed from its zip in `data/raw/DMR/` via `unzip -p` (not extracted to disk) | memory (whole file after streaming) |
| `eff_violations` | `NPDES_EFF_VIOLATIONS.csv` (~16 GB), streamed from its zip in `data/raw/` (matched by pattern `eff.*zip`, since the real filename has a non-ASCII space) | **chunked** (2M rows/chunk) |
| `eff_violations_state` | same effluent zip, but filtered by `NPDES_ID` prefix to one two-letter state code (`arg`, default `NY`) while streaming | memory (post-filter) |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| raw ICIS-NPDES / DMR / ATTAINS / effluent files (see table above) | input (raw) | one row per record in the source table | via ECHO |
| `output/<out_prefix>_summary_<timestamp>.xlsx` | **output** | one sheet per input table, one row per variable within each sheet | derived |
| `output/eff_violations_<state>_<timestamp>.csv` | **output** (side effect of `eff_violations_state` only) | the filtered raw rows for that state | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `dplyr`, `data.table`, `lubridate`, `openxlsx`.
- **Controlled randomness:** the chunked reader (`eff_violations`) estimates numeric/date
  quantiles from a rolling random sample (`sample.int`) rather than the full column;
  **seeded (`set.seed(1)`)** so the reported 5th/95th percentiles are exactly reproducible
  run to run. Every other dataset (`memory` mode) computes exact quantiles over the full
  column — no randomness involved.
- **Memory/runtime:** `npdes`/`attains`/`master_general_permits`/`outfalls_layer` are
  small enough to read whole (the `MEMORY_SAFE` set `Rscript summarize.R all` runs).
  `limits` (~7 GB) and `dmrs` (streamed from its zip) are read whole after streaming —
  larger but still bounded. `eff_violations` (~16 GB) is the one dataset too large for
  this to be safe on an 8 GB-RAM machine, so it alone uses `build_summary_chunked()`:
  peak memory is ~one 2M-row chunk, not the whole file. `TODO:` OS/timing.

## Description of program

Shared machinery (styles, `pct_missing()`, `cat_rows()`/`num_summary_row()`/
`date_summary_row()`, `write_sheet()`) lives once at the top. `summarize_columns()`
routes each non-ID column to the categorical, numeric, or date summarizer and drops it
from the in-memory table immediately after (`set(dt, j = v, value = NULL)`) so peak
memory stays close to the input size rather than doubling. `build_summary()` handles
every in-memory dataset; `build_summary_chunked()` is the one out-of-core path
(streams via `unzip -p`, accumulates categorical counts and numeric/date running
statistics + a reservoir sample per chunk, finalizes at the end). Each dataset is one
entry in the `DATASETS` registry (id/date columns, descriptions, output prefix, and an
`inputs()` function returning what to load); `run_dataset()` dispatches on `cfg$mode`
and calls `write_sheet()` once per input item. `csv_item()`, `read_zip_csv()`, and
`read_state_rows()` are the shared file readers.

## Decisions and Assumptions

1. **Standardized layout (LABELED ASSUMPTION 1 in the script header).** Every sheet —
   regardless of dataset — now uses the fuller 9-column numeric / 8-column categorical
   layout (a trailing, always-blank **Missing Explanation** annotation column), matching
   what `dmrs`/`attains` already used before this script consolidated the old
   per-dataset scripts. No summary statistic changes value; this is a cosmetic column,
   empty in every original script too.
2. **The "Columns:" metadata line always lists the file's full header**, even for
   datasets (like `limits`) that drop some ID columns via `drop_cols` before reading —
   the full header is scanned separately so nothing looks silently omitted.
3. **Whitespace-only character cells are treated as missing**, not a category, for
   datasets with `trim_ws = TRUE` (`npdes`, `limits`) — some ICIS files use a literal
   space for "blank."
4. **`VERSION_NMBR` is force-coerced to character** for `dmrs`/`eff_violations`-family
   datasets (`force_char_cols`) so it lands in the categorical section (top values/
   distinct count) rather than getting a meaningless five-number numeric summary — it's
   a small discrete reissuance counter (~9 distinct values), not a continuous quantity.
5. **`eff_violations_state`'s output CSV is a side effect**, not just a summary — the
   filtered state rows are written to `output/eff_violations_<state>_<timestamp>.csv`
   as `read_state_rows()` runs, in addition to the workbook.
6. **`Rscript summarize.R all` only runs `MEMORY_SAFE`** (`npdes`, `dmrs`, `attains`,
   `master_general_permits`, `outfalls_layer`) — `limits`, `eff_violations`, and
   `eff_violations_state` are excluded from the batch run (too slow / need an `arg`) and
   must be run individually.

## Output columns

- **Categorical table (8 columns):** `Variable`, `% Missing`, `n Categories`,
  `Frequent Values` (top 5), `%`, `n`, `Description` (from a paired `_DESC` column when
  one exists), `Missing Explanation` (always blank).
- **Numeric/date table (9 columns):** `Variable`, `% Missing`, `Min`, `0.05`, `Median`,
  `Mean`, `0.95`, `Max`, `Missing Explanation` (always blank). Date columns keep `Min`
  through `Max` as actual dates rather than epoch numbers.

## Instructions to run

```bash
Rscript code/summary/summarize.R <dataset> [arg]
#   <dataset>: npdes | dmrs | attains | eff_violations | eff_violations_state
#              limits | master_general_permits | outfalls_layer   (or "all")
#   [arg]:     state code for eff_violations_state (default NY);
#              a single filename for npdes (default: NPDES_QNCR_HISTORY.csv),
#              or "all" to summarize every CSV in npdes_downloads/ in one workbook
```
No dependency on the built panel or other steps; reads raw data directly. Setting the
environment variable `SUMMARIZE_NO_MAIN=1` sources the file for its functions without
running the CLI (used by a verification harness).

## Notes / edge cases

- The effluent zip is located by **pattern match** (`eff.*zip` in `data/raw/`), not a
  hardcoded filename, because the real ECHO filename contains a non-ASCII space —
  never hardcode it (see `docs/notes.md`).
- `eff_violations`'s chunked quantiles are *estimated* from a reservoir sample, not
  exact — seeded for reproducibility, but treat the 5th/95th percentiles as
  approximate, unlike every other dataset's exact quantiles.
- `attains` silently skips any raw CSV that is header-only (0 data rows) — a known
  state of at least one file in `data/raw/Attains/` (see the field notes in
  `website/data-documentation.html`).

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
