# `data/processed/` — derived, analysis-ready data

Cleaned panels and extracts **built entirely from code** out of `data/raw/`. Nothing
here is a source of truth or hand-edited: delete any file and rebuild it by re-running
the script that produces it.

## What's here (by producer)

| File(s) | Built by | Grain |
|---|---|---|
| `01_…`→`06_facility_month_panel_major_individual_*_2005_2025.csv` | `updated panel/01…06_*.R` (run in order) | facility × month (majors, individual) |
| `06_facility_month_panel_major_individual_effluent_fy2025.csv` | `updated panel/restrict_06_to_fy2025.R` | the 06 panel restricted to federal FY2025 (Oct 2024–Sep 2025) |
| `facility_month_panel_major_individual_2005_2025.csv` | `updated panel/01_*.R` (⚠️ 02 expects the `01_`-prefixed name — see `updated panel/READMEs/`) | facility × month |
| `npdes_enforcement_panel_*_2005_2025.csv`, `permit_panel_major_individual_*_2005_2025.csv`, `facility_panel_major_individual_2005_2025.csv` | `scripts/build/01…05_*.R` (via `run_all.R`) | facility-year / permit panels |
| `effluent_violations_npdes_month_panel_2005_2025.csv` | `scripts/build/build_effluent_violations_npdes_month_panel.R` | permit × month (D80/D90/E90) |
| `dmr_fy2025_exo_00530_effgross_monthlyavg.csv` | `scripts/build/filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R` | DMR rows (TSS / effluent-gross / monthly-avg) |
| `facility_uin_multiple_npdes.csv` | `scripts/facility_uin_multiple_npdes.R` | facilities with >1 permit |

## Conventions

- **Regenerable, not tracked.** Excluded from version control (`data/processed/*.csv`
  in `.gitignore`) due to size. Rebuild with `Rscript run_all.R` and the
  `updated panel/` scripts (see their READMEs).
- **No hand-editing.** Every value is traceable to a script and a logged run.
- **Two distinct panel families:** the facility-**month** pipeline lives in
  `updated panel/` (documented in `updated panel/READMEs/`); the facility-**year** /
  permit panels come from `scripts/build/` (`01…05`). Keep them straight.
- IDs/codes stored as text; ZIP zero-padded.

Paths resolve via `_paths.R` (`PROC_DIR`).
