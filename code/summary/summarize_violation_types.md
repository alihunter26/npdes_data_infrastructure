# README — `summarize_violation_types.R`

*Violation-type composition of a **built** panel, not a raw source file or a QA check.
Input: `data/processed/04_facility_month_panel_major_individual_violations_2005_2025.csv`.
Output: console tables + a timestamped CSV in `output/tables/`.*

## Overview

Answers a different question than `summarize_panel.R`'s QA checks: of all violations
tallied in the panel, what percent are permit-schedule vs. compliance-schedule vs.
single-event vs. effluent (TSS gross monthly-average)? This is a composition/share
breakdown for interpretation, not a bug-catching check.

## Data Availability and Provenance Statements

Not applicable in the usual sense — this script's input is **derived data** (step 04
of the panel build), not a raw EPA download. See
`code/03_panel_building/READMEs/04_add_violations.md` for the raw source provenance.

### Details on each data source

| File | Key fields used |
|---|---|
| `data/processed/04_facility_month_panel_major_individual_violations_2005_2025.csv` | `N_PS_VIOLATIONS`, `N_CS_VIOLATIONS`, `N_SE_VIOLATIONS`, `N_TSS_EFF_VIOLATIONS`, `N_TSS_EFF_D90`, `N_TSS_EFF_D80`, `N_TSS_EFF_E90` — only these seven columns are read. |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| the 04 panel (see above) | input (derived) | facility × month | derived, from `code/03_panel_building/04_add_violations.R` |
| `output/tables/violation_type_summary_<timestamp>.csv` | **output** | one row per top-level violation type | derived |

## Computational Requirements

- **R** 4.4.2. Package: `data.table`.
- **Controlled randomness:** none.
- **Memory/runtime:** reads only 7 of the 04 panel's columns via `fread(select = ...)`
  — small and fast regardless of the panel's total column count. `TODO:` OS/timing.

## Description of program

Reads just the violation-count columns from the 04 panel. Sums each of the four
top-level columns across the whole panel (every facility-month, 2005–2025; each
violation is an event counted once, in the month it occurred) to get the total by
type, then computes each type's percent share of the four-type sum. Separately sums
the three effluent sub-codes and reports them as a share *of the effluent total*, not
of the four-type grand total. Prints both tables to console with a sanity line
comparing the effluent sub-code sum to the effluent total, then writes the top-level
table to a timestamped CSV.

## Decisions and Assumptions

1. **The four top-level violation-count columns are mutually exclusive and partition
   the denominator.** `N_PS_VIOLATIONS` + `N_CS_VIOLATIONS` + `N_SE_VIOLATIONS` +
   `N_TSS_EFF_VIOLATIONS` is the "all violations" total that every top-level
   percentage is a share of.
2. **`N_TSS_EFF_D90`/`_D80`/`_E90` are a sub-breakdown of `N_TSS_EFF_VIOLATIONS` by
   `VIOLATION_CODE`, not separate types.** They are **not** added to the four-type
   total — doing so would double-count the effluent row. They're reported as a percent
   of the effluent subset (`pct_of_eff`) and, separately, as a percent of the grand
   total (`pct_of_all`) for reference.
3. **`N_TSS_EFF_VIOLATIONS` is restricted to Total Suspended Solids, gross-effluent
   location, monthly-average statistical base** — see step 04's own notes for why that
   specific restriction, not "all effluent violations."
4. **Percentages are pooled over the whole panel** (all facilities, all 252 months),
   not computed per-facility or per-year.

## Output columns

- **Console/CSV top-level table (`type_tbl`):** `violation_type` (human label),
  `column` (source column name), `n_violations`, `pct_of_all` — sorted descending by
  count. Only this table is written to CSV.
- **Console-only effluent sub-breakdown (`eff_tbl`, not written to CSV):**
  `effluent_code`, `column`, `n_violations`, `pct_of_eff`, `pct_of_all` — sorted
  descending by count.
- **Console sanity line:** compares `D90+D80+E90` against `N_TSS_EFF_VIOLATIONS`,
  flagging whether they're exactly equal or whether other, unlisted violation codes
  are also present in the effluent total.

## Instructions to run

```bash
Rscript code/summary/summarize_violation_types.R
#   Input : data/processed/04_facility_month_panel_major_individual_violations_2005_2025.csv
```
No arguments. Requires step 04 of `code/03_panel_building/` to have already run.

## Notes / edge cases

- If the effluent sub-code sum comes in *under* `N_TSS_EFF_VIOLATIONS`, that's
  expected and reported, not an error — some effluent violation codes other than
  D90/D80/E90 can be present but aren't broken out individually here.
- Only the top-level table is persisted to disk; if you need the effluent
  sub-breakdown for later reference, capture the console output or extend the script
  to write `eff_tbl` too.

## References

Panel construction: `code/03_panel_building/READMEs/04_add_violations.md`.
