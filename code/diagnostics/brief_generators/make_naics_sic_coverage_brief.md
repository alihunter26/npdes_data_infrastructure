# README — `make_naics_sic_coverage_brief.R`

*A standalone **brief generator** (not a panel-building step). Input: the newest
`naics_sic_coverage_by_state_year_*.csv`. Output: three LaTeX fragments, machine-generated.*

## Diagnostic Context

**1. What issue is this script designed to give us information about?**
Not a new empirical question — this converts
`naics_sic/naics_sic_coverage_by_state_year.R`'s findings into a citable, traceable
written brief for institutional/PI-facing use.

**2. What do we learn from the information created by this script?**
Same substantive findings as the source coverage script, restated as reproducible
LaTeX macros and tables — confirmed present in `docs/institutional_briefs/`
(`naics_sic_coverage_by_state.pdf`, `naics_sic_coverage_numbers.tex`): 139,992
permit-years, 56 states, 35.9% national NAICS coverage, 98.7% SIC, 10 high-NAICS
states, 16 near-zero-NAICS states, ND/VT below 90% SIC.

*How fully have we dug in?* ~100% — this is the one script in the folder carried
through not just to a saved CSV but to a finished, published PDF brief. Note: the
script's own declared output folder (`output/briefs/`) doesn't currently exist on this
machine — the finished artifacts live in `docs/institutional_briefs/` instead, so
where the script says it writes and where the real deliverable ended up living have
diverged.

**3. What are the implications of what we learned for our issue?**
This is the fully "closed" end state that other diagnostics in this folder (e.g.
`missingness/cs_rnc_missingness.R`, `outfalls/feature_ids_per_permit.R`) have not yet
reached — it demonstrates the intended full pipeline (diagnostic script &rarr; saved
table &rarr; brief generator &rarr; published PDF) and is the template other
unresolved diagnostics should be brought to if their findings are meant to inform PIs
formally rather than stay as ad hoc console output.

## Overview

Generates the LaTeX table fragments and macros `\input` by the NAICS/SIC coverage
institutional brief (`output/briefs/naics_sic_coverage_by_state.tex`), from
`naics_sic_coverage_by_state_year.R`'s output. Pools and re-keys the per-(state, year)
coverage table into per-state and per-year LaTeX rows plus headline in-prose figures.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain, via a derived intermediate. `TODO:` download date. &boxtimes; All data
publicly available.

### Details on each data source

- The **newest** file matching `output/tables/naics_sic_coverage_by_state_year_*.csv`
  (selected via `which.max(file.mtime(csvs))`), produced by
  `code/diagnostics/naics_sic/naics_sic_coverage_by_state_year.R` (see its README).
  The script `stop()`s with an instruction to run that script first if no matching
  file exists.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| newest `naics_sic_coverage_by_state_year_*.csv` | input (derived) | one row per (state, year) | derived, via `naics_sic_coverage_by_state_year.R` |
| `output/briefs/tab_naics_sic_by_state_rows.tex` | **output** | one LaTeX row per state, plus a bolded "All" total row | derived |
| `output/briefs/tab_naics_sic_by_year_rows.tex` | **output** | one LaTeX row per year | derived |
| `output/briefs/naics_sic_coverage_numbers.tex` | **output** | `\newcommand` macros for in-prose figures | derived |

## Computational Requirements

- **R** 4.4.2. Package: `data.table`.
- **Controlled randomness:** none.
- **Memory/runtime:** reads a single small, already-aggregated CSV; fast. `TODO:`
  OS/timing.

## Description of program

Load the newest coverage CSV; pool counts to one row per state (summing `n_permits`/
`n_naics`/`n_sic` across years, then *recomputing* percentages from the summed
counts); build a national "All" total row; separately pool to one row per year
(national); emit each as LaTeX table-row fragments via small formatting helpers
(`ci()` for comma-formatted integers, `p1()` for 1-decimal percentages); compute
headline figures and write them as LaTeX `\newcommand` macros so in-prose numbers stay
traceable to their source file.

## Decisions and Assumptions

No numbered assumption block in the source, but one methodological choice is called
out explicitly in-line: **per-state and national percentages are recomputed from
summed counts, not averaged from the per-year percentages** — i.e.
`pct_naics = 100 * sum(n_naics) / sum(n_permits)`, not `mean(pct_naics)` — to avoid the
averaging-percentages-across-unequal-denominators error.

**Hardcoded thresholds for headline figures:** `pct_naics >= 95` &rarr; "hi_naics"
(high-coverage states); `pct_sic < 90` &rarr; "lo_sic" (low-coverage states, listed by
name); `round(pct_naics, 1) == 0` &rarr; "n0_naics" (near-zero-coverage states).

## Output columns

- **`tab_naics_sic_by_state_rows.tex`:** LaTeX table rows, one per state:
  `STATE_CODE & N & n_naics & pct_naics & n_sic & pct_sic \\`, ending in `\midrule`
  then a bolded "All" total row, then `\bottomrule`.
- **`tab_naics_sic_by_year_rows.tex`:** LaTeX table rows, one per year:
  `year & N & pct_naics & pct_sic \\`, ending in `\bottomrule`.
- **`naics_sic_coverage_numbers.tex`:** macros `\covYearMin`, `\covYearMax`,
  `\covNStates`, `\covPermitYears`, `\covNatNaics`, `\covNatSic`, `\covZeroNaics`,
  `\covHiNaics`, `\covLoSicList`, `\covSrcFile` (records which source CSV was used, for
  traceability).

## Instructions to run

```bash
Rscript "code/diagnostics/brief_generators/make_naics_sic_coverage_brief.R"
```
**Requires** `code/diagnostics/naics_sic/naics_sic_coverage_by_state_year.R` to have
already been run at least once (the script errors out with a clear message naming
that script if no matching input CSV is found in `output/tables/`).

## Notes / edge cases

- **These three `.tex` files are machine-generated — do not hand-edit them.** Per the
  script's own header comment, if the numbers need to change, rerun this script (after
  regenerating the source coverage CSV if the underlying data changed), don't edit the
  `.tex` output directly.
- **LaTeX gotcha:** the state-rows fragment deliberately ends on `\bottomrule`, not a
  row-ending `\\`, because a `\input`-ed fragment ending on `\\` immediately before the
  parent table's `\noalign` rule triggers a "Misplaced \noalign" LaTeX error.
- If multiple `naics_sic_coverage_by_state_year_*.csv` files exist in
  `output/tables/` (e.g. from repeated re-runs), only the most recently modified one
  is used — older copies are silently ignored, not merged.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
