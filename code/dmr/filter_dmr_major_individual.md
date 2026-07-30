# README — `filter_dmr_major_individual.R`

*Step 1 of the DMR row-filter pipeline. Input: a raw per-fiscal-year DMR zip in
`data/raw/DMR/` + `ICIS_PERMITS.csv`. Output: `code/dmr/01_dmr_fy<FY>.csv`.*

## Overview

Row-filters the full raw FY`<year>` DMR file down to permits that are **ever-major,
individually-permitted (NPD)** — the same population the facility panels use. Does
**not** narrow by parameter, feature type, monitoring location, or statistical base:
every row for an eligible permit is kept, all 57 original columns. First of four
FY-parameterized steps; see `code/dmr/README.md`'s "DMR row-filter pipeline" section
for the full chain.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. ☒ All data publicly available.

### Details on each data source

| File | Key fields used |
|---|---|
| `data/raw/DMR/npdes_dmrs_fy<year>.zip` (member `NPDES_DMRS_FY<year>.csv`) | all 57 columns; filtered on `EXTERNAL_PERMIT_NMBR` |
| `data/raw/npdes_downloads/ICIS_PERMITS.csv` | `EXTERNAL_PERMIT_NMBR`, `PERMIT_TYPE_CODE`, `MAJOR_MINOR_STATUS_FLAG` — a static, current-state extract, not FY-specific, so the eligible-permit set is the same regardless of which FY's DMR is being filtered |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `NPDES_DMRS_FY<year>.csv` (in its zip) | input (raw) | permit × outfall × parameter × period | via ECHO |
| `ICIS_PERMITS.csv` | input (raw) | permit × version | via ECHO |
| `code/dmr/01_dmr_fy<year>.csv` | **output** | same grain as input, row-filtered | derived (git-ignored, `code/dmr/*.csv`) |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `DBI`, `duckdb`.
- **Controlled randomness:** none.
- **Memory/runtime:** DuckDB out-of-core — the raw FY file is multi-GB, too large for
  this 8 GB-RAM machine to `fread` whole. The zip member is decompressed once to a
  per-FY gzip scratch file (reused across re-runs if present), then DuckDB streams +
  spills to disk from there. `TODO:` OS/timing.

## Description of program

1. Build the eligible-permit set from `ICIS_PERMITS.csv`: restrict to
   `PERMIT_TYPE_CODE == "NPD"`, then flag each permit `ever_major` if **any** version
   row has `MAJOR_MINOR_STATUS_FLAG == "M"`.
2. Decompress the FY zip's one CSV member to a gzip scratch file via
   `tar -xOf ... | gzip -1 > ...` (reused on subsequent runs if `REUSE_GZ`).
3. DuckDB `INNER JOIN` the raw file against the eligible-permit set on
   `trim(EXTERNAL_PERMIT_NMBR)`, streaming the result straight to
   `01_dmr_fy<year>.csv`.
4. Verify: input/output column-count parity, and that every output permit is a member
   of the eligible set (should be 0 exceptions) — stops with an error if either check
   fails, leaving the output in place for inspection.

## Decisions and Assumptions

1. **"Ever major" pools across all permit versions**, not "major in this specific
   fiscal year" — a permit that was ever flagged `M` in any reissuance stays eligible
   for every FY run against this script.
2. **`ICIS_PERMITS.csv` is read once per run, not cached across FYs** — since it's a
   static current-state file, the eligible-permit set is identical for every FY;
   re-running this script for a different year recomputes the same join key from
   scratch rather than assuming yesterday's set is still valid (cheap enough not to
   matter — the file is small relative to the DMR data).
3. **The gzip scratch temp is per-FY and reusable** (`REUSE_GZ <- TRUE` by default) —
   speeds up repeated runs/debugging at the cost of that scratch file's disk space
   until manually cleared.

## Output columns

Same 57 columns as the source `NPDES_DMRS_FY<year>.csv` — this is a pure row filter,
no column selection or renaming.

## Instructions to run

```bash
Rscript code/dmr/filter_dmr_major_individual.R <FY>
#   <FY>: fiscal year, e.g. 2025
```
No dependency on other scripts; reads raw data directly. Must run before
`filter_dmr_00530.R` for the same FY.

## Notes / edge cases

- Moved in from the root-level `dmr analysis/` folder 2026-07-29 — see
  `code/dmr/README.md` for that history. Script and its output CSV both live in
  `code/dmr/` now; the CSVs are git-ignored (`code/dmr/*.csv`).
- This is a **different, standalone pipeline** from the FY2025-hardcoded mini-pipeline
  (`filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R` etc.) — same underlying raw
  data, different logic and output location. Don't confuse the two `01`-style outputs.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
