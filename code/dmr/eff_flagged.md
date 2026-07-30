# README — `eff_flagged.R`

*A standalone value-QC diagnostic (not a panel-building step). Input: the newest
`output/eff_violations_<state>_*.csv` for a chosen state. Output:
`output/eff_flagged_<state>_<timestamp>.csv`.*

## Overview

Reads a state's effluent-violation extract and writes out only the **suspicious**
rows, so they're easy to review by hand, with a `FLAG_REASON` column explaining which
check(s) each row tripped.

## Data Availability and Provenance Statements

Input is **derived data** — a per-state extract produced as a side effect of
`code/summary/summarize.R`'s `eff_violations_state` dataset — not a raw EPA download
read directly by this script.

### Details on each data source

| File | Notes |
|---|---|
| `output/eff_violations_<state>_*.csv` | The **newest** file matching this pattern for the chosen state (by file modification time) is used automatically; produced by `Rscript code/summary/summarize.R eff_violations_state <state>` (see `code/summary/summarize.md`). |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `output/eff_violations_<state>_*.csv` | input (derived) | one row per parameter/limit violation for that state | from `summarize.R`'s `eff_violations_state` dataset |
| `output/eff_flagged_<state>_<timestamp>.csv` | **output** | subset of the input, flagged rows only, + `FLAG_REASON` | derived |

## Computational Requirements

- **R** 4.4.2. Package: `data.table`.
- **Controlled randomness:** none.
- **Memory/runtime:** reads the whole per-state CSV (already a small state-level
  extract, not the multi-GB national file) with `fread(colClasses = "character")`.
  `TODO:` OS/timing.

## Description of program

Locates the most recently modified `eff_violations_<state>_*.csv` in `output/` for
the chosen state and reads it whole, as text. Runs four independent checks (any one
flags the row) and concatenates a plain-English reason for every row that trips at
least one, then writes just the flagged subset with its `FLAG_REASON` column added.

## Decisions and Assumptions

1. **A row is flagged if ANY of four checks trip:**
   1. `DMR_VALUE_NMBR` is negative
   2. `DMR_VALUE_STANDARD_UNITS` is negative
   3. any of 4 date columns (`MONITORING_PERIOD_END_DATE`, `VALUE_RECEIVED_DATE`,
      `RNC_DETECTION_DATE`, `RNC_RESOLUTION_DATE`) has a year before 1984
   4. any value over 1,000,000 appears in a non-ID column
2. **Check 4 explicitly skips ID-like columns** (`ACTIVITY_ID`,
   `NPDES_VIOLATION_ID`, `PERMIT_ACTIVITY_ID`, `DMR_FORM_VALUE_ID`, `DMR_VALUE_ID`,
   `DMR_PARAMETER_ID`, `LIMIT_ID`) — those hold large arbitrary ID numbers, not
   measurements, so treating them as "values" would flag nearly every row for no
   substantive reason. Edit the `id_cols` list in the script to change which columns
   are exempted.
3. **A blank/unparseable value is treated as "not a violation" for every check**
   (`NA` flags coerced to `FALSE`), not as suspicious in itself.
4. **A row failing multiple checks still appears once**, with all applicable reasons
   concatenated into one `FLAG_REASON` string (e.g. "negative DMR_VALUE_NMBR; year
   before 1984 (RNC_DETECTION_DATE); ").
5. **Read-only and deterministic except for the output filename's timestamp** — this
   script does not alter the input file or the panel.

## Output columns

All original columns from the input CSV, unchanged, **plus** `FLAG_REASON` (text) —
only for the rows that tripped at least one check; non-flagged rows are dropped
entirely from the output.

## Instructions to run

```bash
Rscript code/dmr/eff_flagged.R <state>
#   <state>: two-letter state code, e.g. Rscript eff_flagged.R va
#   Defaults to "va" if omitted.
```
Requires an `output/eff_violations_<state>_*.csv` to already exist for that state —
run `Rscript code/summary/summarize.R eff_violations_state <state>` first if it
doesn't (errors out naming the missing pattern if none is found).

## Notes / edge cases

- **Always uses the newest matching file by modification time** — if multiple
  `eff_violations_<state>_*.csv` extracts exist from different runs, this picks the
  most recently modified one, not the most recently *named* (timestamp-sorted) one;
  these normally agree but could diverge if an older file were touched/copied later.
- The "year before 1984" threshold and the "over 1,000,000" magnitude threshold are
  both hardcoded, not derived from the data's own distribution — edit the script
  directly to change either.

## References

Depends on `code/summary/summarize.R`'s `eff_violations_state` dataset — see
`code/summary/summarize.md`.
