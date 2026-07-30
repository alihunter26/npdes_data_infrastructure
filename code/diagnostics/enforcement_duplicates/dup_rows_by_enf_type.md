# README — `dup_rows_by_enf_type.R`

*A standalone **diagnostic** (not a panel-building step). Input: raw formal
enforcement actions. Output: one timestamped CSV. Follow-up to
`dup_enforcement_pairs.R`.*

## Diagnostic Context

**1. What issue is this script designed to give us information about?**
Same duplication question as `dup_enforcement_pairs.R` (same folder): do repeated
(`NPDES_ID`, `ENF_IDENTIFIER`) pairs in the formal enforcement file represent one case
cited under multiple statutes, rather than genuinely separate actions?

**2. What do we learn from the information created by this script?**
Confirms and extracts the pattern `dup_enforcement_pairs.R` found: 690 rows (per the
2026-06-22 run) belong to "same case, multiple statutes cited" duplicate sets —
identical on every column except `ENF_TYPE_CODE`/`ENF_TYPE_DESC`.

*How fully have we dug in?* ~100% — together with `dup_enforcement_pairs.R`, this is a
complete, closed investigative arc: started as an open question, ended with a
confirmed, quantified, extracted mechanism.

**3. What are the implications of what we learned for our issue?**
The formal enforcement file does *not* have informal's duplicate-row contamination
problem, but it does fan out one legal case into multiple rows by statute — and,
separately, across multiple facilities sharing one action (see
`formal_actions_same_fine_date.R`, same folder). Both fan-out patterns had to be
understood and handled before formal-action counts in the panel could be trusted.

## Overview

Confirms and extracts the specific duplication pattern found by
`dup_enforcement_pairs.R` (same folder): rows in
`NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv` that are identical on every column **except**
`ENF_TYPE_CODE`/`ENF_TYPE_DESC`. Interpretation: these are single enforcement actions
(same case/date/penalty/`ACTIVITY_ID`) recorded once per statutory authority cited —
"multi-statute repeats" — not truly separate enforcement actions.

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
| `output/tables/dup_rows_by_enf_type_<timestamp>.csv` | **output** | one row per original record in a multi-statute duplicate set | derived |

## Computational Requirements

- **R** base only — no non-base packages loaded.
- **Controlled randomness:** none.
- **Memory/runtime:** whole file read into memory via `read.csv`. `TODO:` OS/timing.

## Description of program

Define "the same underlying action" as every column except `ENF_TYPE_CODE`/
`ENF_TYPE_DESC`; build a grouping key from those columns; keep only rows whose key is
shared by more than one row; order so each set sits together and assign a stable
`dup_group` id; print a 20-row preview of key identifying columns; write the full
result.

## Decisions and Assumptions

Framed in prose rather than a numbered list in the source: the entire script rests on
the interpretation that rows differing only in `ENF_TYPE_CODE`/`ENF_TYPE_DESC` are
one action cited under multiple statutes, not distinct actions — see Overview above.

**Fixed "should-be-identical" column set:** all columns except `ENF_TYPE_CODE` and
`ENF_TYPE_DESC` (the two columns the script expects, and confirms, to vary).

## Output columns

One row per original record belonging to a multi-statute duplicate set, with
`dup_group` prepended to all original columns.

## Instructions to run

```bash
Rscript "code/diagnostics/enforcement_duplicates/dup_rows_by_enf_type.R"
```
No dependency on other scripts; reads raw data directly. Logically follows
`dup_enforcement_pairs.R` (same folder), whose exploratory finding motivates this
script's fixed column split, but does not require it to have been run first.

## Notes / edge cases

- Console preview shows only `NPDES_ID`, `ENF_IDENTIFIER`, `ACTIVITY_ID`,
  `ENF_TYPE_CODE`, `ENF_TYPE_DESC`, `SETTLEMENT_ENTERED_DATE`,
  `FED_PENALTY_ASSESSED_AMT` — the full output CSV has every original column.
- Output correctly follows the repo's `output/tables/<name>_<timestamp>.csv` convention.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
