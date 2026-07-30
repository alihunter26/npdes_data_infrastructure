# README — `make_dmr_funnel_fig.R`

*A standalone figure-generation script (not a panel-building step). Input: the 8 DMR
row-filter pipeline output files in `code/dmr/` (01–04, FY2009 and FY2025). Output:
`docs/institutional_briefs/fig/dmr_filter_funnel.pdf`.*

## Overview

Plots the DMR row/permit "filter funnel" — major-individual → +TSS(00530) →
+effluent gross → +C1/Q1 — for FY2009 vs. FY2025 side by side: rows on a log scale
(they shrink by orders of magnitude across the 4 stages), distinct permits on a
linear scale (they only shrink by roughly 30% end to end, so log would visually
exaggerate a small relative change). The figure is cited in
`docs/institutional_briefs/`.

## Data Availability and Provenance Statements

Inputs are **derived data** — the 8 output files of the DMR row-filter pipeline
(steps 1–4, run for both FY2009 and FY2025) — not a raw EPA download read directly.
See `filter_dmr_major_individual.md` through `filter_dmr_c1q1.md` for the underlying
raw provenance.

### Details on each data source

| File | Key fields used |
|---|---|
| `code/dmr/01_dmr_fy<year>.csv` … `04_dmr_fy<year>_00530_monloc1_c1q1.csv`, for `<year>` in `{2009, 2025}` (8 files total) | `EXTERNAL_PERMIT_NMBR` only — row count and distinct-permit count per file |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| the 8 pipeline-stage CSVs (see above) | input (derived) | permit × outfall × parameter × period, progressively filtered | from the DMR row-filter pipeline, run for both FY2009 and FY2025 |
| `docs/institutional_briefs/fig/dmr_filter_funnel.pdf` | **output** | one two-panel figure | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `ggplot2`, `scales`, `cowplot`, `data.table`.
- **Controlled randomness:** none.
- **Memory/runtime:** reads only the `EXTERNAL_PERMIT_NMBR` column from each of the 8
  files via `fread(select = ...)` — even the largest (`01_dmr_fy2025.csv`, ~1.3 GB)
  is fast this way. Verified end-to-end run: a few seconds for all 8 files combined.

## Description of program

For each fiscal year, for each of the 4 pipeline stages: read just the
`EXTERNAL_PERMIT_NMBR` column, record the row count and the distinct-permit count.
Assemble the resulting 8 (fy × stage) rows into one table, then build two `ggplot2`
panels sharing one color mapping (2009 vs. 2025) and x-axis (the 4 funnel stages):
rows (log-scale y-axis) and distinct permits (linear-scale y-axis, floored at 0). The
shared legend is extracted from one panel (`get_legend()`) and placed once beneath
both panels via `cowplot::plot_grid()`, rather than repeating a legend under each.
Saved as a 9×4.3 inch PDF.

## Decisions and Assumptions

1. **Row/permit counts are computed directly from the 8 pipeline output files on
   every run, not hardcoded.** **Fixed 2026-07-30:** this script previously plotted a
   literal `data.table` typed in by hand, with a comment asserting the values were
   "verified directly... via DuckDB" — a verification that lived nowhere in the repo,
   so the numbers weren't independently traceable to a logged run (flagged as a
   `TODO` in the script's own header). Re-verified after the fix: the newly computed
   values are **byte-identical** to the old hardcoded ones (e.g. FY2025 stage 1:
   4,703,897 rows / 6,701 permits), confirming the original numbers were correct —
   this change doesn't alter the figure, only how it's produced.
2. **Requires all 8 pipeline output files to exist first** — stops with a clear error
   naming exactly which file(s) are missing for which fiscal year, rather than
   plotting a partial or stale funnel.
3. **Log scale for rows, linear scale for permits** — a deliberate, different choice
   per panel, because rows shrink by orders of magnitude across the funnel while
   permit counts only shrink by a modest fraction; using the same scale for both
   would either compress the row story or exaggerate the permit story.
4. **One shared color mapping and one shared legend** across both panels — so the
   figure reads as a single comparison, not two unrelated charts.

## Output columns

Not a table — a single PDF figure, two side-by-side panels (rows; distinct permits),
4 x-axis tick marks per panel (the funnel stages), one line/point series per fiscal
year, one shared legend beneath both panels. The intermediate computed table (`d`:
`fy`, `stage`, `rows`, `permits`) is also printed to console for each run.

## Instructions to run

```bash
Rscript code/dmr/make_dmr_funnel_fig.R
```
No arguments. Requires all four DMR row-filter pipeline steps
(`filter_dmr_major_individual.R` through `filter_dmr_c1q1.R`) to have already run for
**both** FY2009 and FY2025.

## Notes / edge cases

- **Now correctly picks up a pipeline rerun.** If the row-filter pipeline is rerun
  and produces different counts (data refresh, logic change), this script's next run
  reflects that automatically — the previous hardcoded-table version would have
  silently kept plotting the old numbers.

## References

Figure cited in `docs/institutional_briefs/`.
