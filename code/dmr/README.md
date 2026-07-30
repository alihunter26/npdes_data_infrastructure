# `code/dmr/` — DMR-specific summary, diagnostic & filter scripts

Scripts whose primary subject is the raw per-fiscal-year DMR (Discharge Monitoring
Report) file itself, rather than the broader ICIS-NPDES tables or the built panel.
Grouped here 2026-07-27 — the seven summary/diagnostic scripts previously lived split
across `code/summary/` and `code/diagnostics/` (in `brief_generators/`, `outfalls/`,
and `effluent_qc/`, the last of which is now empty and was removed); the two filter
scripts below moved in the same day from a root-level `build/` folder (also now
removed).

None of these build the facility-month panel; they summarize, diagnose, or QC the
DMR data on the side.

## All scripts in this folder

| Script | Category (see below) |
|---|---|
| [`build_dmr_raw_summary.R`](build_dmr_raw_summary.md) | FY2025/FY2009 filter-pipeline trio |
| [`combine_dmr_summaries.R`](combine_dmr_summaries.md) | FY2025/FY2009 filter-pipeline trio |
| [`combine_dmr_summaries_fy2009.R`](combine_dmr_summaries_fy2009.md) | FY2025/FY2009 filter-pipeline trio |
| [`summarize_dmr_coverage_major_minor.R`](summarize_dmr_coverage_major_minor.md) | Coverage, funnel, and outfall diagnostics |
| [`make_dmr_funnel_fig.R`](make_dmr_funnel_fig.md) | Coverage, funnel, and outfall diagnostics |
| [`outfall_count_breakdown_dmr.R`](outfall_count_breakdown_dmr.md) | Coverage, funnel, and outfall diagnostics |
| [`eff_flagged.R`](eff_flagged.md) | Effluent-violation value QC |
| [`filter_dmr_major_individual.R`](filter_dmr_major_individual.md) | DMR row-filter pipeline (step 1) |
| [`filter_dmr_00530.R`](filter_dmr_00530.md) | DMR row-filter pipeline (step 2) |
| [`filter_dmr_monloc1.R`](filter_dmr_monloc1.md) | DMR row-filter pipeline (step 3) |
| [`filter_dmr_c1q1.R`](filter_dmr_c1q1.md) | DMR row-filter pipeline (step 4) |
| [`filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R`](filter_dmr_fy2025_exo_00530_effgross_monthlyavg.md) | FY2025 DMR filter mini-pipeline (step 1) |
| [`filter_dmr_fy2025_effgross_major_individual.R`](filter_dmr_fy2025_effgross_major_individual.md) | FY2025 DMR filter mini-pipeline (step 2) |

## The FY2025 / FY2009 DMR filter-pipeline trio

These three build a *multi-tab* comparison across the stages of the DMR row-filter
pipeline below (01 Major-Individual → 02 TSS(00530) → 03 Effluent Gross → 04 C1/Q1):

| Script | Purpose | Output |
|---|---|---|
| [`build_dmr_raw_summary.R`](build_dmr_raw_summary.md) | Summarizes the **raw, unfiltered** FY DMR file (every permit/parameter, no restriction at all). Uses DuckDB out-of-core — the raw file is 4.7-27M rows, too large to safely `fread` whole on an 8GB machine. Usage: `Rscript build_dmr_raw_summary.R <FY>` | `output/DMR/raw_summary_fy<FY>.rds` — **not** an `.xlsx`; a serialized summary object meant to be prepended into the workbooks below without recomputing. |
| [`combine_dmr_summaries.R`](combine_dmr_summaries.md) | One workbook, one tab per FY2025 pipeline stage, with the raw-file summary above spliced in as tab 0. | `output/DMR/2025_dmr_summaries_combined.xlsx` — fixed filename, overwritten each run (not timestamped). |
| [`combine_dmr_summaries_fy2009.R`](combine_dmr_summaries_fy2009.md) | Identical logic and styling, pointed at the FY2009 pipeline stages instead (a comparison/baseline year). | `output/DMR/2009_dmr_summaries_combined.xlsx` — fixed filename, overwritten each run. |

## Coverage, funnel, and outfall diagnostics

| Script | Purpose | Output |
|---|---|---|
| [`summarize_dmr_coverage_major_minor.R`](summarize_dmr_coverage_major_minor.md) | FY2015-2020: how many Major vs. Minor permits (per `ICIS_PERMITS.csv`) actually reported DMR data each year — counts and coverage %, shaded by a green gradient. | `output/dmr_coverage_major_minor_<timestamp>.xlsx` |
| [`make_dmr_funnel_fig.R`](make_dmr_funnel_fig.md) | Plots the DMR row/permit "filter funnel" (major-individual → +TSS(00530) → +effluent gross → +C1/Q1) for FY2009 vs. FY2025 side by side. Figures cited in `docs/institutional_briefs/`. | `docs/institutional_briefs/fig/dmr_filter_funnel.pdf` |
| [`outfall_count_breakdown_dmr.R`](outfall_count_breakdown_dmr.md) | Companion to `code/diagnostics/outfalls/outfall_count_breakdown.R`: that script counts outfalls a facility is *permitted* for (`NPDES_LIMITS.csv`); this one counts outfalls that actually *reported* at least one monitoring result in the fiscal year, from the DMR file itself. DuckDB out-of-core (~9.7GB FY file, streamed from its zip). Default FY2025. | timestamped output (see script header) |

## DMR row-filter pipeline (FY-parameterized, general)

Four-step, FY-parameterized row filter narrowing a raw per-fiscal-year DMR file down
to major/individual permits → TSS (00530) → effluent-gross monitoring location →
C1/Q1 limit-value types. Moved in from the root-level `dmr analysis/` folder
2026-07-29 — the folder is gone now; both the scripts and their input/output CSVs
live in `code/dmr/` (the CSVs are git-ignored via `code/dmr/*.csv` in `.gitignore`,
same treatment the old folder gave them). Run manually per FY, not part of
`run_all.R`:

| Step | Script | Output |
|---|---|---|
| 1 | [`filter_dmr_major_individual.R`](filter_dmr_major_individual.md) `<FY>` | `code/dmr/01_dmr_fy<FY>.csv` — FY DMR rows restricted to ever-major, individually-permitted permits |
| 2 | [`filter_dmr_00530.R`](filter_dmr_00530.md) `<FY>` | `code/dmr/02_dmr_fy<FY>_00530.csv` — step 1 restricted to PARAMETER_CODE = 00530 (TSS) |
| 3 | [`filter_dmr_monloc1.R`](filter_dmr_monloc1.md) `<FY>` | `code/dmr/03_dmr_fy<FY>_00530_monloc1.csv` — step 2 restricted to Effluent Gross monitoring locations |
| 4 | [`filter_dmr_c1q1.R`](filter_dmr_c1q1.md) `<FY>` | `code/dmr/04_dmr_fy<FY>_00530_monloc1_c1q1.csv` — step 3 restricted to LIMIT_VALUE_TYPE_CODE IN ('C1','Q1') |

```bash
Rscript code/dmr/filter_dmr_major_individual.R <FY>
Rscript code/dmr/filter_dmr_00530.R <FY>
Rscript code/dmr/filter_dmr_monloc1.R <FY>
Rscript code/dmr/filter_dmr_c1q1.R <FY>
#   <FY>: fiscal year, e.g. 2025 — each step requires the previous step's output
```

This is a separate, standalone pipeline from the FY2025 DMR filter mini-pipeline
below — different logic (FY-parameterized vs. FY2025-hardcoded), different output
naming/convention (numbered CSVs directly in `code/dmr/` vs. named CSVs in
`data/processed/`). The FY2025/FY2009 filter-pipeline trio above
(`build_dmr_raw_summary.R` etc.) summarizes *this* pipeline's stages, not the
mini-pipeline's.

## [`eff_flagged.R`](eff_flagged.md) — effluent-violation value QC

Flags suspicious rows in the effluent-violations data for one state (negative
`DMR_VALUE_NMBR`/`DMR_VALUE_STANDARD_UNITS`, implausible dates/magnitudes).

```bash
Rscript code/dmr/eff_flagged.R <state>
#   <state>: two-letter state code, e.g. Rscript eff_flagged.R va
```

Output: `output/eff_flagged_<state>_<timestamp>.csv`.

## FY2025 DMR filter mini-pipeline

A small two-step pipeline, run manually (not part of `run_all.R`), that filters the
raw FY2025 DMR file down to the rows the DMR row-filter pipeline above and
`06_add_effluent_violations.R` actually need:

| Step | Script | Output |
|---|---|---|
| 1 | [`filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R`](filter_dmr_fy2025_exo_00530_effgross_monthlyavg.md) (moved in from the external EIL Summer folder 2026-07-27) | `data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg.csv` — FY2025 DMR rows filtered to TSS / effluent-gross / monthly-average |
| 2 | [`filter_dmr_fy2025_effgross_major_individual.R`](filter_dmr_fy2025_effgross_major_individual.md) | `data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg_major_individual.csv` — step 1's output restricted to major, individually-permitted facilities |

## Conventions

- Sources `_paths.R`; deterministic; read-only with respect to `data/raw/`.
- Large raw DMR files are streamed from their zips (DuckDB out-of-core or chunked
  `fread`), never fully extracted to disk — the FY DMR CSV is multi-GB and this
  machine has 8GB RAM.
- Most outputs are timestamped in `output/`; the FY2025/FY2009 combined workbooks
  are the exception (fixed filenames, overwritten each run — see table above).
