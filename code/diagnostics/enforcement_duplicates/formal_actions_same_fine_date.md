# README — `formal_actions_same_fine_date.R`

*A standalone **diagnostic** (not a panel-building step). Input: raw formal
enforcement actions. Output: one CSV (not timestamped).*

## Diagnostic Context

**1. What issue is this script designed to give us information about?**
Is the same enforcement action (same fine amount + same date) recorded once per
facility it covers, which would silently multiply the true penalty if summed across
facilities?

**2. What do we learn from the information created by this script?**
The most consequential finding in this whole folder (rated "High" severity in
`docs/data_issues.md`): 1,672 records belong to a shared fine+date group. Worst case:
a $6.7M fine (`ENF_IDENTIFIER 04-2006-9037`, 04/09/2008) recorded identically across 76
separate `NPDES_ID`s. Verified all the way into the actual built panel: a $2.2M Houston
sewer-system settlement (`06-2010-1780`) appears identically across 30 in-panel
facilities — naive summing gives $66M vs. the true $2.2M, a 30&times; overstatement.

*How fully have we dug in?* ~100% — traced from the raw pattern all the way into real
panel rows, with the fix's correctness (deduplicating penalties at `ENF_IDENTIFIER`
before summing across facilities) explicitly verified.

**3. What are the implications of what we learned for our issue?**
Penalty dollars can never be summed across facilities/`NPDES_ID`s without deduplicating
at `ENF_IDENTIFIER` first, or any aggregate penalty total will be wildly wrong (the
30&times; example above). This is a standing landmine for any future group-level
(facility-group, state, industry) penalty analysis, not a one-time fix — confirmed as
a live risk in `docs/data_issues.md`, not just a theoretical one.

## Overview

Flags formal-enforcement records whose fine amount **and** date exactly match at least
one other record — a coincidence/possible-duplicate detector, restricted to fines
greater than $1,000 so small fines coinciding by chance aren't flagged.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. &boxtimes; All data publicly available.

### Details on each data source

- `data/raw/npdes_downloads/NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv`, read whole via
  `read.csv(stringsAsFactors = FALSE)`.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv` | input (raw) | one row per formal enforcement action | via ECHO |
| `output/formal_actions_same_fine_date.csv` | **output** | one row per record belonging to a shared fine+date group | derived |

## Computational Requirements

- **R** 4.4.2. Package: `dplyr`.
- **Controlled randomness:** none.
- **Memory/runtime:** whole file read into memory via `read.csv`. `TODO:` OS/timing.

## Description of program

Read the raw file with `stringsAsFactors = FALSE` (note: **not** read as
all-character — see Notes); coerce the fine column to numeric; keep only rows with a
real fine `> 1000` and a non-blank date; group by (fine amount, date) and keep only
groups of 2 or more; annotate each kept row with `n_in_group`; write the result.

## Decisions and Assumptions

No numbered assumption block in the source; the two key parameters are named
constants at the top of the script rather than embedded logic:

- **`FINE_COL <- "FED_PENALTY_ASSESSED_AMT"`** — change to use a different fine column.
- **`DATE_COL <- "SETTLEMENT_ENTERED_DATE"`** — change to use a different date column.
- **Threshold: fine `> 1000`** (1000 itself excluded).
- A row is kept only if **at least one other row** shares its exact fine amount and
  exact date — a lone fine/date combination is not flagged as a coincidence.

## Output columns

All original columns of `NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv`, plus `fine_amount`
(numeric-coerced fine), `fine_date` (copy of the raw date column), and `n_in_group`
(how many rows share this exact fine+date), ordered by descending fine amount then
date.

## Instructions to run

```bash
Rscript "code/diagnostics/enforcement_duplicates/formal_actions_same_fine_date.R"
```
No dependency on other scripts; reads raw data directly.

## Notes / edge cases

- **Not read as all-character**, unlike the repo's general convention (see root
  `README.md`'s "Read CSVs as character" convention) — the fine column is explicitly
  cast with `suppressWarnings(as.numeric(as.character(...)))`, so any genuinely
  non-numeric value (e.g. blank) silently becomes `NA` rather than raising a warning
  per row, and is then dropped by the `!is.na(fine_amount)` filter.
- **Output is a cross-cutting exception to this repo's convention:** written to
  `output/` root (not `output/tables/`) and **not timestamped** — a re-run silently
  overwrites the previous copy.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
