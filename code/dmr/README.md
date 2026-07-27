# `code/dmr/` — DMR-specific summary, diagnostic & filter scripts

Scripts whose primary subject is the raw per-fiscal-year DMR (Discharge Monitoring
Report) file itself, rather than the broader ICIS-NPDES tables or the built panel.
Grouped here 2026-07-27 — the seven summary/diagnostic scripts previously lived split
across `code/summary/` and `code/diagnostics/` (in `brief_generators/`, `outfalls/`,
and `effluent_qc/`, the last of which is now empty and was removed); the two filter
scripts below moved in the same day from a root-level `build/` folder (also now
removed).

None of these build the facility-month panel; they summarize, diagnose, or QC the
DMR data on the side. See the root `code/README.md` for how this folder relates to
`../dmr analysis/` (the sibling filter pipeline that also reads the raw DMR files).

## The FY2025 / FY2009 DMR filter-pipeline trio

These three build a *multi-tab* comparison across the stages of the DMR filter
pipeline in `../../dmr analysis/` (01 Major-Individual → 02 TSS(00530) → 03 Effluent
Gross → 04 C1/Q1):

| Script | Purpose | Output |
|---|---|---|
| `build_dmr_raw_summary.R` | Summarizes the **raw, unfiltered** FY DMR file (every permit/parameter, no restriction at all). Uses DuckDB out-of-core — the raw file is 4.7-27M rows, too large to safely `fread` whole on an 8GB machine. Usage: `Rscript build_dmr_raw_summary.R <FY>` | `output/DMR/raw_summary_fy<FY>.rds` — **not** an `.xlsx`; a serialized summary object meant to be prepended into the workbooks below without recomputing. |
| `combine_dmr_summaries.R` | One workbook, one tab per FY2025 pipeline stage, with the raw-file summary above spliced in as tab 0. | `output/DMR/2025_dmr_summaries_combined.xlsx` — fixed filename, overwritten each run (not timestamped). |
| `combine_dmr_summaries_fy2009.R` | Identical logic and styling, pointed at the FY2009 pipeline stages instead (a comparison/baseline year). | `output/DMR/2009_dmr_summaries_combined.xlsx` — fixed filename, overwritten each run. |

## Coverage, funnel, and outfall diagnostics

| Script | Purpose | Output |
|---|---|---|
| `summarize_dmr_coverage_major_minor.R` | FY2015-2020: how many Major vs. Minor permits (per `ICIS_PERMITS.csv`) actually reported DMR data each year — counts and coverage %, shaded by a green gradient. | `output/dmr_coverage_major_minor_<timestamp>.xlsx` |
| `make_dmr_funnel_fig.R` | Plots the DMR row/permit "filter funnel" (major-individual → +TSS(00530) → +effluent gross → +C1/Q1) for FY2009 vs. FY2025 side by side. Figures cited in `docs/institutional_briefs/`. | `docs/institutional_briefs/fig/dmr_filter_funnel.pdf` |
| `outfall_count_breakdown_dmr.R` | Companion to `code/diagnostics/outfalls/outfall_count_breakdown.R`: that script counts outfalls a facility is *permitted* for (`NPDES_LIMITS.csv`); this one counts outfalls that actually *reported* at least one monitoring result in the fiscal year, from the DMR file itself. DuckDB out-of-core (~9.7GB FY file, streamed from its zip). Default FY2025. | timestamped output (see script header) |

## `eff_flagged.R` — effluent-violation value QC

Flags suspicious rows in the effluent-violations data for one state (negative
`DMR_VALUE_NMBR`/`DMR_VALUE_STANDARD_UNITS`, implausible dates/magnitudes).

```bash
Rscript code/dmr/eff_flagged.R <state>
#   <state>: two-letter state code, e.g. Rscript eff_flagged.R va
```

Output: `output/eff_flagged_<state>_<timestamp>.csv`.

## FY2025 DMR filter mini-pipeline

A small two-step pipeline, run manually (not part of `run_all.R`), that filters the
raw FY2025 DMR file down to the rows `../../dmr analysis/` and `06_add_effluent_violations.R`
actually need:

| Step | Script | Output |
|---|---|---|
| 1 | `filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R` (moved in from the external EIL Summer folder 2026-07-27) | `data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg.csv` — FY2025 DMR rows filtered to TSS / effluent-gross / monthly-average |
| 2 | `filter_dmr_fy2025_effgross_major_individual.R` | `data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg_major_individual.csv` — step 1's output restricted to major, individually-permitted facilities |

## Conventions

- Sources `_paths.R`; deterministic; read-only with respect to `data/raw/`.
- Large raw DMR files are streamed from their zips (DuckDB out-of-core or chunked
  `fread`), never fully extracted to disk — the FY DMR CSV is multi-GB and this
  machine has 8GB RAM.
- Most outputs are timestamped in `output/`; the FY2025/FY2009 combined workbooks
  are the exception (fixed filenames, overwritten each run — see table above).
