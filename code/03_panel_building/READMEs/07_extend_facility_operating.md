# README — `07_extend_facility_operating.R`

**added 7/23**, in response to a direct question about whether `FACILITY_OPERATING`
mislabels genuinely-operating-but-quiet months as `NA`.

*Step 7 of the facility-by-month panel build (post-processing correction, not part of
the original six-step chain). Input: the step-06 final panel only. Output: the same
panel with `FACILITY_OPERATING` corrected and one new column.*

> Not to be confused with the **old, pre-7/21 "step 07"** — a missingness-audit
> diagnostic that has since moved to
> [`code/diagnostics/missingness/`](../../diagnostics/missingness/missingness_audit_major_individual.md)
> and is unrelated to this script. The number was vacant and is reused here for a real
> pipeline step.

## Overview

`FACILITY_OPERATING` (script 01) is computed purely from `ICIS_PERMITS` date fields —
it has no independent knowledge of whether a facility was actually active. This step
checks that assumption against the panel's own event data and corrects it: any month
with a real recorded event (inspection, violation, enforcement action, or effluent
violation) proves the facility was operating, regardless of what the permit dates say.
Each facility's window is extended (never shrunk) to cover every such month, and the
previously-`NA` count columns in the newly-covered months are filled with `0` — the
same "operating, no event = 0" rule script 01 established, just applied where the
original window undercounted.

## Data Availability and Provenance Statements

Reads only the already-derived step-06 panel — no raw ICIS files. ☒ All data publicly
available (inherited from steps 01–06).

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv` | `.csv` | all 57 columns |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| step-06 panel | input (only input) | facility × month | derived |
| `data/processed/07_..._operating_corrected_2005_2025.csv` | **output (final panel)** | facility × year × month | derived |

## Computational Requirements

- **R** 4.4.2. Package: `data.table` (only).
- **Controlled randomness:** none.
- **Memory/runtime:** single ~430 MB CSV in, no crosswalk rebuild, no raw-file
  streaming — a few seconds to run (measured: ~9s wall time including read/write of
  ~1.9M rows × 58 columns). Far cheaper than re-running 01–06.

## Description of program

1. Read the step-06 panel. Convert `YEAR`/`MONTH`/`FACILITY_OPERATING` and every
   `N_*`/`n_*` count column to integer (everything else stays character, unchanged).
2. Flag each row with a real recorded event: any of 10 top-level total columns
   (`N_INSPECTIONS_TOTAL`, `N_PS_VIOLATIONS`, `N_CS_VIOLATIONS`, `N_SE_VIOLATIONS`,
   `N_TSS_EFF_VIOLATIONS`, `N_FORMAL_ACTIONS`, `N_INFORMAL_ACTIONS`, `n_D80`, `n_D90`,
   `n_E90`) is non-`NA` and `> 0`.
3. Per facility, compute the extended window: `new_start = min(original spine start,
   first real-event month)`, `new_end = max(original spine end, last real-event
   month)`. A facility with no recorded events anywhere is unaffected.
4. Rename the original flag to `FACILITY_OPERATING_PERMIT_WINDOW` (preserved,
   unchanged); write the corrected flag as the new `FACILITY_OPERATING`.
5. Every `N_*`/`n_*` column that is `NA` in a row newly covered by the extension
   becomes `0`. Cells that already held a real value are never touched.
6. Restore column order (`FACILITY_OPERATING_PERMIT_WINDOW` immediately after
   `FACILITY_OPERATING`) and row order; write the output.

## Decisions and Assumptions

1. **Why this step exists — measured, not hypothetical.** On the step-06 panel,
   12.66% of `FACILITY_OPERATING == 0` rows (32,033 of 253,028) carried a real
   recorded event anyway — direct proof the facility was active. These are not
   boundary noise: 75.9% are more than 12 months outside the computed window (median
   31, max 250 months). 2,381 of 7,511 facilities (32%) are affected — 2,132 on the
   close side, 413 on the open side.
2. **Root cause, confirmed.** Permits with `PERMIT_STATUS_CODE == "ADC"`
   (Administrative Continuance — legally still active past the nominal
   `EXPIRATION_DATE` while a renewal is pending) have that `EXPIRATION_DATE` read as a
   real closing date by script 01 anyway, since script 01 has no `ADC` special case.
   Example: facility `110006619212` / permit `NH0100455` — `EXPIRATION_DATE =
   01/29/2005`, `PERMIT_STATUS_CODE = "ADC"`, no `TERMINATION_DATE`/`RETIREMENT_DATE`
   — its computed window closes at the very start of the panel even though it has real
   recorded events up to 250 months later. 86.7% of the 8,007 permits linked to this
   panel's facilities carry `ADC` status at some point in their version history. This
   quirk was already flagged in general terms in `docs/data_quirks.md` (the
   `PERMIT_STATUS_CODE`/`EXPIRATION_DATE` row) before this step existed to act on it.
3. **"Real event" = one of 10 top-level total columns, not all ~37 count columns.**
   Every other `N_*`/`n_*` breakout column is a subset of one of these ten and shares
   its NA/0 status (each of steps 02/04/05/06 fills its whole block of count columns
   from one joined source row per facility-month — see those scripts' READMEs), so a
   breakout is never real while its parent total is `NA`. Checking the ten totals is
   sufficient and avoids redundant work.
4. **Extend both directions (PI decision).** The close-side effect dominates by far
   (2,132 vs. 413 facilities) and is the one with a confirmed mechanism (`ADC`), but
   both directions use the identical min/max rule for consistency, and the open-side
   fix is essentially free to include.
5. **Never shrinks a window, only grows it.** A facility with zero recorded events
   anywhere in the panel keeps its original script-01 window exactly. This step cannot
   make any row that was `FACILITY_OPERATING == 1` become `0`.
6. **A newly-covered quiet month is a true zero, not a guess.** This is the same
   inference script 01 already makes for months inside its own computed window — this
   step only extends *which* months qualify, not the underlying "operating + no
   matched event = 0" logic itself.
7. **Penalty dollar columns are untouched.** `FED_PENALTY`/`STATE_PENALTY` are `NA`
   whenever no formal action carried a dollar amount, independent of operating status
   (script 05, Assumption 5) — extending the operating window changes nothing about
   how those two columns should be read.
8. **`FACILITY_OPERATING` is redefined in this output file (PI decision).** In the
   07 panel, `FACILITY_OPERATING` carries the *corrected* value — least surprise for
   anyone using the column by name going forward. The original permit-window-only
   definition is fully preserved under the new name
   `FACILITY_OPERATING_PERMIT_WINDOW`, so nothing is silently lost; `docs/codebook.md`
   documents both columns explicitly.
9. **Non-destructive.** Writes a new file; `06_..._effluent_2005_2025.csv` is
   untouched and remains on disk for comparison/audit.

**Hardcoded parameters:** none — fully data-driven from the step-06 panel.

## Output columns (58 total: 57 unchanged + 1 new)

- **New:** `FACILITY_OPERATING_PERMIT_WINDOW` (integer 0/1) — the original script-01
  flag, unchanged, placed immediately after `FACILITY_OPERATING`.
- **Redefined in place:** `FACILITY_OPERATING` (integer 0/1) — now the corrected/
  extended flag.
- **Value-corrected only where newly covered:** every `N_*`/`n_*` count column — `NA`
  → `0` in rows that are newly operating; every other cell is byte-identical to the
  step-06 panel.
- **Unchanged:** every other column (all facility attributes, `FED_PENALTY`,
  `STATE_PENALTY`, and the `N_*_PENALTY_ASSESSED` companion counts, which behave like
  any other count column here).

## Instructions to run

```bash
Rscript "code/03_panel_building/07_extend_facility_operating.R"
```

Run **after** step 06. Does not require `python3`/`unzip` or any raw ICIS file.

## Notes / edge cases

- **Verified (2026-07-23):** a full column-by-column diff against the step-06 panel
  confirms every text/attribute column, `FED_PENALTY`, `STATE_PENALTY`, and
  `FACILITY_OPERATING_PERMIT_WINDOW` are byte-identical to their step-06 counterparts,
  and every changed cell in every count column is exactly a blank/`NA` → `0` fill —
  zero illegal (non blank-to-zero) changes found.
- **Self-check baked into the run log:** after correction, re-testing "`
  FACILITY_OPERATING == 0` but a real event present" must return exactly 0 rows — this
  is a mathematical guarantee of the min/max construction (Assumption 5), not just an
  empirical result, and the script `stopifnot()`s on it.
- Measured on the actual run: 109,823 rows flip `FACILITY_OPERATING` 0 → 1 (far more
  than the 32,033 rows that directly triggered an extension — extending a facility's
  window to cover one real event also covers every quiet month in between); 3,772,636
  `NA` → `0` fills across all count columns.
- A facility whose entire recorded life shows zero events anywhere (no inspections,
  violations, enforcement, or effluent violations ever) is completely unaffected by
  this step — there's nothing to extend the window against.

## References

Diagnosis conducted directly against `06_facility_month_panel_major_individual_effluent_2005_2025.csv`
and `data/raw/npdes_downloads/ICIS_PERMITS.csv` (`PERMIT_STATUS_CODE` field), 2026-07-23.
EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>.
