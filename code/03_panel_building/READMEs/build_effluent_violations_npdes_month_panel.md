# README — `build_effluent_violations_npdes_month_panel.R`

*Prerequisite for the facility-by-month panel build, not one of its six numbered steps.
Must run before step 01 (not just before step 06) — both read its output. Input: the raw
`NPDES_EFF_VIOLATIONS.csv`. Output: one small condensed permit×month summary file.*

## Overview

Reads EPA's raw effluent-violations file (~15.9 GB uncompressed, inside a zip) and
condenses it into one row per (`NPDES_ID`, calendar month), with both:

- **All-parameter** violation counts (`n_D80`, `n_D90`, `n_E90`) — across every
  pollutant, discharge point, and monitoring location a permit has.
- **TSS gross-effluent monthly-average subset** counts (`N_TSS_EFF_VIOLATIONS`,
  `N_TSS_EFF_D90`/`_D80`/`_E90`) — the same three codes, restricted to one specific,
  narrow slice (Assumption 3).

Both count sets are computed together in a **single pass** over the raw file (via
DuckDB), which is why this script produces one combined output file rather than two.

## Data Availability and Provenance Statements

Derived from EPA ECHO / ICIS-NPDES public data (public domain). `TODO:` download date of
the underlying effluent file. ☒ All data publicly available.

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `NPDES_EFF_VIOLATIONS.csv` (inside its zip in `data/raw/`) | `.csv` in `.zip`, ~15.9 GB unzipped | `NPDES_ID`, `NPDES_VIOLATION_ID`, `VIOLATION_CODE`, `PARAMETER_CODE`, `MONITORING_LOCATION_CODE`, `STATISTICAL_BASE_MONTHLY_AVG`, `STATISTICAL_BASE_CODE`, `PERM_FEATURE_NMBR`, `LIMIT_SET_DESIGNATOR`, `MONITORING_PERIOD_END_DATE` |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `NPDES_EFF_VIOLATIONS.csv` (zip) | input (raw) | violation | via ECHO |
| `effluent_violations_npdes_month_panel_2005_2025.csv` | **output** | permit × month | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `DBI`, `duckdb`.
- **External tools:** `unzip` and `gzip` on `PATH` (stream the zip member out and
  re-compress it once; no `python3` needed).
- **Controlled randomness:** none.
- **Memory/runtime:** the raw file is far too large to read into memory whole on this
  (RAM-constrained) machine, so DuckDB processes it out-of-core, spilling to disk as
  needed (`memory_limit` capped at 5 GB). Roughly 15-20 minutes end to end: ~1-2 min to
  stream+gzip the zip member once, then a few minutes each for the filter/tag pass and
  the two aggregation queries.

## Description of program

1. Locate the raw effluent zip (matched by filename pattern, since its real name has a
   non-ASCII space) and stream its one CSV member out to a gzip-compressed scratch file,
   once (reused on subsequent runs if already present).
2. In DuckDB: read the gzip file, keep only rows with `VIOLATION_CODE IN ('D80','D90',
   'E90')`, tag each row with whether it falls in the TSS subset (Assumption 3) and with
   its de-dup key `vkey` (Assumption 5), compute its calendar month, and keep only rows
   in the 2005-2025 window. Materialize this as one temp table so the ~16 GB file is
   scanned only once, not once per query below.
3. Aggregate to one row per (`NPDES_ID`, month): all-parameter counts as `COUNT(DISTINCT
   vkey)` per code; TSS counts as `COUNT(DISTINCT NPDES_VIOLATION_ID)` per code
   (Assumption 4 explains why these two rules are deliberately different).
4. Also compute grand summary totals (raw rows in window, distinct-`vkey` count, per-code
   totals) for the run log, to cross-check against the exact figures already on record in
   `docs/notes.md` from this file's original 2026-07-14 construction.
5. Write the combined result.

## Decisions and Assumptions

1. **One row per permit-month; no zero-fill.** A (`NPDES_ID`, month) combination only
   appears if that permit had at least one D80/D90/E90 violation (of any kind) that
   month. Downstream scripts (01, 06) decide what "no row here" means once this table is
   joined onto their own panels.
2. **Month = monitoring-period month**, not detection or receipt date — `date_trunc`ed
   from `MONITORING_PERIOD_END_DATE` to the first of the month.
3. **The TSS subset is one specific, narrow slice** (per PI guidance): a row counts
   toward the TSS columns only if **all** of `PARAMETER_CODE == "00530"` (Total
   Suspended Solids), `MONITORING_LOCATION_CODE == "1"` (Effluent Gross), and
   `STATISTICAL_BASE_MONTHLY_AVG == "A"` (monthly-average limit).
4. **Two different de-dup rules, kept deliberately different.** A DMR resubmission
   creates an *additional* row with a brand-new `NPDES_VIOLATION_ID` rather than
   overwriting the original, so naively counting distinct `NPDES_VIOLATION_ID` can
   over-count. All-parameter counts use `COUNT(DISTINCT vkey)` (Assumption 5) to collapse
   resubmissions; TSS counts use `COUNT(DISTINCT NPDES_VIOLATION_ID)`, matching exactly
   how the TSS logic worked before it was moved into this script (not "fixed" to match
   the other rule, which would silently change a downstream number). Consequence: in a
   vanishingly small number of permit-months the two can disagree by 1-2 —
   `06_add_effluent_violations.R`'s run log reports this, it does not hide it.
5. **`vkey` identifies what a violation is about, independent of which submission
   produced the row:** `NPDES_ID + PERM_FEATURE_NMBR + LIMIT_SET_DESIGNATOR +
   MONITORING_LOCATION_CODE + PARAMETER_CODE + STATISTICAL_BASE_CODE +
   MONITORING_PERIOD_END_DATE`. Two rows agreeing on all seven are the same underlying
   violation reported more than once; two rows differing in any of the seven are
   genuinely different violations. Counting `DISTINCT vkey` is equivalent to keeping only
   the latest-version row per group and counting what's left, without needing to
   actually identify which row is "latest."
6. **Only the three schedule-type codes are kept** (`D80`, `D90`, `E90`) — the raw file's
   `VIOLATION_CODE` has other values for other kinds of DMR issues, filtered out here.
7. **Windowed to the panel's range.** Only violations with a parseable
   `MONITORING_PERIOD_END_DATE` in Jan 2005 - Dec 2025 are kept; the drop count is
   reported in the run log.

**Hardcoded parameters:** `YEAR_MIN = 2005`, `YEAR_MAX = 2025`; `TSS_PARAM_CODE =
"00530"`, `GROSS_LOC_CODE = "1"`, `MONTHLY_AVG = "A"`.

## Output columns (8)

`NPDES_ID`, `month` (`YYYY-MM-01`), `n_D80`, `n_D90`, `n_E90`, `N_TSS_EFF_VIOLATIONS`,
`N_TSS_EFF_D90`, `N_TSS_EFF_D80`, `N_TSS_EFF_E90`.

## Instructions to run

```bash
Rscript "code/03_panel_building/build_effluent_violations_npdes_month_panel.R"
```
Needs `unzip`/`gzip` on `PATH` and the raw effluent zip present in `data/raw/`. Also
runs automatically from `run_all.R` if its output isn't already on disk.

## Notes / edge cases

- The run log prints its summary totals alongside the exact figures already on record
  in `docs/notes.md` from this file's original 2026-07-14 build (43,317,821 raw rows in
  window / 41,451,812 distinct `vkey` / D80 21,073,782 / D90 17,814,134 / E90 2,563,896 /
  2,694,316 permit-months across 121,708 distinct `NPDES_ID`s) — a correct rebuild should
  match these exactly.
- Re-running reuses the gzip scratch file if one already exists (`REUSE_GZ`); delete it
  (path printed in the run log, under `$TMPDIR` or `$CWA_SCRATCH`) to force a fresh
  extraction.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
