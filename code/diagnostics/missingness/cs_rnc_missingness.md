# README — `cs_rnc_missingness.R`

*A standalone, **exploratory** diagnostic (not a panel-building step). Input: raw
compliance-schedule violations and permits. Output: console only.*

## Diagnostic Context

**1. What issue is this script designed to give us information about?**
Is the ~61% blank rate in `RNC_DETECTION_CODE` (compliance-schedule violations)
structural — tied to whether a permit is even tracked for RNC purposes, or its
major/minor status — or is it closer to random/accidental missingness?

**2. What do we learn from the information created by this script?**
**Console-only — no saved output, and not referenced anywhere in `docs/`.** I cannot
verify the actual by-group percentages this script would print from any file in this
repo; only the script's logic and its own stated ~61% motivating premise exist.

*How fully have we dug in?* ~10%. The mechanism was built and, per the script's own
comments, apparently run once interactively, but the result was never captured to a
file or written up — the least "closed the loop" diagnostic in this folder. The
script's own header even flags that its permit lookup (`match()`, first-row-found) isn't
current-version-restricted, so even its author treats it as a rough first pass, not a
final answer.

**3. What are the implications of what we learned for our issue?**
None solidified yet — this remains an open question. To resolve it with the same
confidence as the NAICS/SIC coverage finding, this script would need to be re-run with
its output actually saved (the way `naics_sic/naics_sic_coverage_by_state_year.R` was),
and ideally fixed to use current-version permit status rather than `match()`'s
first-row-found behavior.

## Overview

Tests one candidate explanation for why `RNC_DETECTION_CODE` (the "was this a
reportable noncompliance?" field) is ~61% blank in `NPDES_CS_VIOLATIONS.csv`: does
whether RNC gets recorded track the permit's own major/minor status or its
`RNC_TRACKING_FLAG` — i.e., is the blank rate structural (permits not tracked for RNC
purposes simply never get a code) rather than accidental?

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. &boxtimes; All data publicly available.

### Details on each data source

| File | Key fields used |
|---|---|
| `data/raw/npdes_downloads/NPDES_CS_VIOLATIONS.csv` | `NPDES_ID`, `RNC_DETECTION_CODE` |
| `data/raw/npdes_downloads/ICIS_PERMITS.csv` | `EXTERNAL_PERMIT_NMBR`, `MAJOR_MINOR_STATUS_FLAG`, `RNC_TRACKING_FLAG` |

Both read whole via `read.csv(colClasses = "character")`.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `NPDES_CS_VIOLATIONS.csv`, `ICIS_PERMITS.csv` | input (raw) | various | via ECHO |

**Output: console only — no file written.** This is an exploratory read, not a saved
extract.

## Computational Requirements

- **R** base only — no non-base packages loaded.
- **Controlled randomness:** none.
- **Memory/runtime:** both files read whole via `read.csv`. `TODO:` OS/timing.

## Description of program

Flag each violation row's `RNC_DETECTION_CODE` as blank or present (true `NA` or
whitespace-only counts as blank); look up each violation's permit-level
`MAJOR_MINOR_STATUS_FLAG` and `RNC_TRACKING_FLAG` via `match()` on `NPDES_ID` /
`EXTERNAL_PERMIT_NMBR`; print the RNC-present rate broken out by each of those two
flags, giving unmatched rows their own `"(no match)"` bucket rather than dropping them.

## Decisions and Assumptions

1. **The permit lookup uses base R's `match()`,** which returns the **first** matching
   row for a given `NPDES_ID` in `ICIS_PERMITS.csv`. Since `ICIS_PERMITS.csv` has one
   row per permit *version*, this is whichever version happens to appear first in the
   raw file — **not guaranteed to be the permit's current version.** That's acceptable
   for this exploratory question (is there any association at all), but this script
   should **not** be used as a source of "current" permit status; see
   `naics_california.R` (in `naics_sic/`) for the `VERSION_NMBR == 0` convention used
   when current status actually matters.

**"Blank" definition:** `is.na(x) | trimws(x) == ""`.

## Output: console only

Two breakdowns, each printed as `RNC-present rate by permit MAJOR/MINOR status` and
`RNC-present rate by permit RNC_TRACKING_FLAG`: for each distinct flag value
(descending by count), `n=` (row count) and `RNC-present %` (share with a non-blank
`RNC_DETECTION_CODE`). Rows with no permit match are reported under their own
`"(no match)"` label rather than silently dropped; a permit match whose field itself
was blank is reported as `"(blank)"`, distinguishing the two situations.

## Instructions to run

```bash
Rscript "code/diagnostics/missingness/cs_rnc_missingness.R"
```
No dependency on other scripts; reads raw data directly.

## Notes / edge cases

- This complements `missingness_audit_major_individual.R` (same folder) but is a
  narrower, exploratory, console-only companion rather than a saved audit extract —
  see that script's own README for the systematic, saved missingness audit.
- Because the permit lookup isn't current-version-restricted, results here should be
  read as "is there any association at all," not as a definitive current-status
  breakdown.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
