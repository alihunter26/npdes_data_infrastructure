# `output/` — generated results

Everything written by the summary and diagnostic scripts: Excel summary workbooks,
flagged/extract CSVs, and a few drill-down folders. **All regenerable** — nothing here
is a source of truth; delete freely and re-run the producing script.

## Contents

| Item | Produced by |
|---|---|
| `*_summary_*.xlsx` (npdes, dmrs, attains, eff_violations[_state], master_general_permits, outfalls_layer, npdes_limits, panel_summary_…) | `scripts/summary/summarize.R` (and legacy `summarize_*.R`) |
| `year_coverage_*.xlsx`, `dmr_coverage_major_minor_*.xlsx` | `scripts/summary/summarize_year_coverage.R`, `…dmr_coverage_major_minor.R` |
| `eff_flagged_<state>_*.csv` | `scripts/diagnostics/eff_flagged.R` |
| `eff_violations_<state>_*.csv` | `scripts/summary/summarize_eff_violations_state.R` |
| Diagnostic extracts (`enforcement_by_permit_type.csv`, `facility_uin_multiple_npdes*.csv`, `formal_actions_same_fine_date.csv`, `*_multi_*`, `naics_*`, `sic_*`, `dropped_no_open_date_*`) | loose `scripts/*.R` and `scripts/diagnostics/*.R` |
| `tables/` | Diagnostic CSV extracts (duplicates, NAICS/SIC coverage, violation-type summaries) |
| `figures/` | Generated figures (currently empty) |
| `UIN_110070099629/` | Single-facility drill-down: every ICIS table filtered to one `FACILITY_UIN` (catchments, dmr, eff_violations, enforcement, facilities, informal_enforcement, inspections, limits, outfalls, perm_feature_coords, permits, qncr_history) — a worked example for validating joins |

## Conventions

- **Timestamped, append-only.** Files are named `*_YYYY-MM-DD_HHMM.{xlsx,csv}`; each run
  writes a new dated file rather than overwriting, so multiple vintages accumulate. Use
  the newest; prune old ones as needed.
- **Untracked.** `output/*.xlsx`, `output/*.csv`, and the nested `output/**` extracts are
  gitignored (regenerable). `~$…` files are Excel lock files — ignore/delete them.
- Nothing here should be hand-edited; fix the script and re-run.
