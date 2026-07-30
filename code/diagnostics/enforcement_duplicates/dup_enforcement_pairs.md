# README — `dup_enforcement_pairs.R`

*A standalone, **exploratory** diagnostic (not a panel-building step). Input: raw
formal enforcement actions. Output: console only — precursor to
`dup_rows_by_enf_type.R`.*

## Diagnostic Context

**1. What issue is this script designed to give us information about?**
Do repeated (`NPDES_ID`, `ENF_IDENTIFIER`) pairs in the *formal* enforcement file
represent duplicate rows, separate actions, or one case cited under multiple statutes?

**2. What do we learn from the information created by this script?**
This is the first half of a two-step arc completed by `dup_rows_by_enf_type.R` (same
folder): it found that only `ENF_TYPE_CODE`/`ENF_TYPE_DESC` actually vary within
duplicated pairs — every other field (dates, penalties, `ACTIVITY_ID`) is identical —
and confirmed zero full-row exact duplicates exist in this file (unlike the informal
file, see `count_informal_exact_duplicates.R`).

*How fully have we dug in?* ~100% for this script's own question, as part of the
combined arc with `dup_rows_by_enf_type.R` — together they form the most complete
investigative arc in this folder: an open question, run to a confirmed, quantified,
extracted mechanism.

**3. What are the implications of what we learned for our issue?**
Established the statute-fan-out mechanism that `dup_rows_by_enf_type.R` then extracted
and quantified at scale — see that script's README for the resulting implications for
formal-action counting.

## Overview

Investigates why (`NPDES_ID`, `ENF_IDENTIFIER`) pairs repeat in
`NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv` — a single enforcement case should usually
appear once, so repeats are worth understanding before treating the file as
one-row-per-action. Finds every repeated pair, then checks *which columns actually
differ* across the repeated rows, to narrow down a candidate explanation.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. &boxtimes; All data publicly available.

### Details on each data source

- `data/raw/npdes_downloads/NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv`, read whole via
  `read.csv(colClasses = "character")`.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv` | input (raw) | one row per formal enforcement action | via ECHO |

**Output: console only — no file written.** This is an exploratory read, not a saved
extract; see `dup_rows_by_enf_type.R` (same folder) for the version that writes a CSV
once the explanation below was confirmed.

## Computational Requirements

- **R** base only — no non-base packages loaded.
- **Controlled randomness:** none.
- **Memory/runtime:** whole file read into memory via `read.csv`. `TODO:` OS/timing.

## Description of program

Build a pair key `paste(NPDES_ID, ENF_IDENTIFIER, sep = " | ")`; find pair-keys that
occur more than once; for a fixed list of candidate columns, check per duplicate group
whether that column takes more than one distinct value (a column that never varies
within a group can't explain the repeat); separately check whether any of these rows
are full duplicates on every column; print 4 example duplicate groups in full for
manual review.

## Decisions and Assumptions

No numbered assumption block in the source; the approach is stated as the header
comment's own framing (see Overview above) rather than a labeled list.

**Candidate columns checked for variation:** `ACTIVITY_ID`, `ACTIVITY_TYPE_CODE`,
`ENF_TYPE_CODE`, `ENF_TYPE_DESC`, `AGENCY`, `SETTLEMENT_ENTERED_DATE`,
`FED_PENALTY_ASSESSED_AMT`, `STATE_LOCAL_PENALTY_AMT`.

## Output: console only

Prints: total rows; count of distinct duplicated pairs; total rows in a duplicated
pair; a table of "rows per duplicated pair" (2, 3, 4, &hellip;); for each candidate
column, the number of duplicate groups in which it varies (sorted descending); the
count of rows that are full duplicates on every column; 4 example duplicate groups
printed in full.

## Instructions to run

```bash
Rscript "code/diagnostics/enforcement_duplicates/dup_enforcement_pairs.R"
```
No dependency on other scripts; reads raw data directly. Run this **before**
`dup_rows_by_enf_type.R` if you want to see the exploratory reasoning that motivated it.

## Notes / edge cases

- This script's finding (that `ENF_TYPE_CODE`/`ENF_TYPE_DESC` are the columns that vary
  within duplicated pairs) is the basis for `dup_rows_by_enf_type.R`'s narrower,
  file-writing follow-up in the same folder.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
