# `data/processed/` — derived, analysis-ready data

Cleaned panels and extracts **built entirely from code** out of `data/raw/`. Nothing
here is a source of truth or hand-edited: delete any file and rebuild it by re-running
the script that produces it.

## What's here (by producer)

| File(s) | Built by | Grain |
|---|---|---|
| `01_…`→`06_facility_month_panel_major_individual_*_2005_2025.csv` | `code/03_panel_building/01…06_*.R` (run in order) | facility × month (majors, individual) — **06 is the current final panel**, with `FACILITY_OPERATING` corrected inside step 01 (see its README, Assumption 10, and `code/03_panel_building/use_operating_proxies.R`) |
| `07_facility_month_panel_major_individual_operating_corrected_2005_2025.csv` | **orphaned** — was `code/03_panel_building/07_extend_facility_operating.R`, retired 2026-07-23 when its logic moved into step 01 | ⚠️ static file, no longer regenerable; superseded by the current 06 panel (verified byte-identical in content) |
| `07_facility_month_panel_major_individual_operating_corrected_fy2025.csv` | **orphaned** — was `code/03_panel_building/restrict_06_to_fy2025.R`, deleted 2026-07-23 | ⚠️ static file, no longer regenerable by any script |
| `06_facility_month_panel_major_individual_effluent_fy2025.csv` | **orphaned** — same removed script, older pre-correction output | ⚠️ static file, no longer regenerable; also pre-correction `FACILITY_OPERATING`. Kept on disk unchanged, don't use going forward |
| `facility_month_panel_major_individual_2005_2025.csv` | `code/03_panel_building/01_*.R` (⚠️ 02 expects the `01_`-prefixed name — see `code/03_panel_building/READMEs/`) | facility × month |
| `effluent_violations_npdes_month_panel_2005_2025.csv` | `code/02_cleaning/build_effluent_violations_npdes_month_panel.R` (moved from `code/03_panel_building/` 2026-07-27) — prerequisite for steps 01 and 06, not a numbered step itself; `run_all.R` builds it automatically if missing | permit (`NPDES_ID`) × month |
| `facility_uin_multiple_npdes.csv` | `code/diagnostics/facility_structure/facility_uin_multiple_npdes.R` | facilities with >1 permit |

## Conventions

- **Regenerable, not tracked.** Excluded from version control (`data/processed/*.csv`
  in `.gitignore`) due to size. Rebuild with `Rscript run_all.R` and the
  `code/03_panel_building/` scripts (see their READMEs). **Exception:** the two
  `*_fy2025.csv` files above are now orphaned — their producing script was deleted
  2026-07-23, so they can no longer be rebuilt; they're stale by construction and
  should not be relied on.
- **No hand-editing.** Every value is traceable to a script and a logged run.
- IDs/codes stored as text; ZIP zero-padded.

Paths resolve via `_paths.R` (`PROC_DIR`).
