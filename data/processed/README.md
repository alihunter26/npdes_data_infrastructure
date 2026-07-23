# `data/processed/` — derived, analysis-ready data

Cleaned panels and extracts **built entirely from code** out of `data/raw/`. Nothing
here is a source of truth or hand-edited: delete any file and rebuild it by re-running
the script that produces it.

## What's here (by producer)

| File(s) | Built by | Grain |
|---|---|---|
| `01_…`→`06_facility_month_panel_major_individual_*_2005_2025.csv` | `code/03_panel_building/01…06_*.R` (run in order) | facility × month (majors, individual) |
| `07_facility_month_panel_major_individual_operating_corrected_2005_2025.csv` | `code/03_panel_building/07_extend_facility_operating.R` | the 06 panel with `FACILITY_OPERATING` corrected (see its README) — **current final panel** |
| `07_facility_month_panel_major_individual_operating_corrected_fy2025.csv` | `code/03_panel_building/restrict_06_to_fy2025.R` (repointed to 07 on 2026-07-23) | the 07 panel restricted to federal FY2025 (Oct 2024–Sep 2025) — **current FY2025 extract** |
| `06_facility_month_panel_major_individual_effluent_fy2025.csv` | superseded — was `restrict_06_to_fy2025.R`'s output before it was repointed to 07 | ⚠️ pre-correction `FACILITY_OPERATING`; kept on disk unchanged, don't use going forward |
| `facility_month_panel_major_individual_2005_2025.csv` | `code/03_panel_building/01_*.R` (⚠️ 02 expects the `01_`-prefixed name — see `code/03_panel_building/READMEs/`) | facility × month |
| `npdes_enforcement_panel_*_2005_2025.csv`, `permit_panel_major_individual_*_2005_2025.csv`, `facility_panel_major_individual_2005_2025.csv` | the external `01…05_*.R` in **`../EIL Summer/build/`** (outside this repo — not this repo's own `build/`) | facility-year / permit panels |
| `effluent_violations_npdes_month_panel_2005_2025.csv` | the external `build_effluent_violations_npdes_month_panel.R` in **`../EIL Summer/build/`** | permit × month (D80/D90/E90) |
| `dmr_fy2025_exo_00530_effgross_monthlyavg.csv` | the external `filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R` in **`../EIL Summer/build/`** | DMR rows (TSS / effluent-gross / monthly-avg) |
| `facility_uin_multiple_npdes.csv` | `code/diagnostics/facility_structure/facility_uin_multiple_npdes.R` | facilities with >1 permit |

## Conventions

- **Regenerable, not tracked.** Excluded from version control (`data/processed/*.csv`
  in `.gitignore`) due to size. Rebuild with `Rscript run_all.R` and the
  `code/03_panel_building/` scripts (see their READMEs).
- **No hand-editing.** Every value is traceable to a script and a logged run.
- **Two distinct panel families:** the facility-**month** pipeline lives in
  `code/03_panel_building/` (documented in `code/03_panel_building/READMEs/`); the
  facility-**year** / permit panels come from the external `../EIL Summer/build/`
  (`01…05`) — a different folder from this repo's own root-level `build/`. Keep them straight.
- IDs/codes stored as text; ZIP zero-padded.

Paths resolve via `_paths.R` (`PROC_DIR`).
