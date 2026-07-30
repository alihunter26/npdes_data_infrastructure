# README — `count_informal_exact_duplicates.R`

*A standalone **diagnostic** (not a panel-building step). Input: raw informal
enforcement actions. Output: one timestamped CSV of duplicate-row sets.*

## Diagnostic Context

**1. What issue is this script designed to give us information about?**
Whether `NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv` is one-row-per-action, or contains
redundant exact-duplicate rows that would double-count informal enforcement if used
naively.

**2. What do we learn from the information created by this script?**
345,822 of 821,977 rows (42%) are byte-for-byte exact duplicates; the extracted
duplicate-set file has 691,644 rows, meaning virtually every duplicate set is a simple
pair (1 original + 1 duplicate) rather than a larger cluster.

*How fully have we dug in?* ~90% on scale — an exhaustive, deterministic full-file
scan, not a sample. ~0% on root cause — why EPA's export contains exact duplicates in
the first place (presumably a data-pull/database-export artifact) was never
investigated, only worked around.

**3. What are the implications of what we learned for our issue?**
Directly shaped the panel-building code (`docs/data_issues.md`): any row-level reuse of
this raw file must call `unique()` first, or informal-action counts inflate ~1.7&times;.
This is exactly why the panel counts informal actions "per raw row by design"
(`05_add_enforcement.R`) rather than treating raw rows as literal distinct actions.

## Overview

Counts exact duplicate rows (every column byte-for-byte identical) in
`NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv`, and writes out every row belonging to a
duplicate set so they can be reviewed side by side.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. &boxtimes; All data publicly available.

### Details on each data source

- `data/raw/npdes_downloads/NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv`, read whole via
  `read.csv(colClasses = "character")` (every column, no restriction).

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv` | input (raw) | one row per informal enforcement action | via ECHO |
| `output/tables/informal_exact_duplicates_<timestamp>.csv` | **output** | one row per original record belonging to a duplicate set | derived |

## Computational Requirements

- **R** base only — no non-base packages loaded.
- **Controlled randomness:** none.
- **Memory/runtime:** whole file read into memory via `read.csv`. `TODO:` OS/timing.

## Description of program

Read the file with every column as character; use base R's `duplicated()` for the
headline exact-duplicate count (`total - unique = redundant copies`); separately build
a full-row string key (`paste()` of all columns with no separator) to find and group
duplicate *sets*, not just count them; order rows so each set sits together, tag each
with a `dup_group`/`copy_no`/`group_size`, and write the timestamped extract.

## Decisions and Assumptions

1. **The duplicate-set key pastes every column together with no separator between
   them.** This is fast and works in practice for this file, but is not perfectly
   collision-proof in principle (e.g. columns `"AB"`+`"C"` paste to the same string as
   `"A"`+`"BC"`). The script relies on this being vanishingly unlikely across this
   file's real column values rather than guaranteeing it structurally.

## Output columns

One row per original record belonging to a duplicate set, ordered so identical rows
sit adjacent, with three columns prepended to all original columns: `dup_group`
(1..N, same value = same duplicate set), `copy_no` (1st copy, 2nd copy, &hellip;
within its set), `group_size` (how many rows are in that set).

## Instructions to run

```bash
Rscript "code/diagnostics/enforcement_duplicates/count_informal_exact_duplicates.R"
```
No dependency on other scripts; reads raw data directly.

## Notes / edge cases

- "Exact duplicate" here means every column matches, not just a subset of key fields —
  see `dup_enforcement_pairs.R` / `dup_rows_by_enf_type.R` in this same folder for the
  companion diagnostics on the *formal* enforcement file, which look at a narrower key
  ((`NPDES_ID`, `ENF_IDENTIFIER`) pairs) rather than full-row equality.
- Output correctly follows the repo's `output/tables/<name>_<timestamp>.csv` convention.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
