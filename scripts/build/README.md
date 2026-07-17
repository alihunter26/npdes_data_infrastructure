# `scripts/build/` — panel pipeline (facility-year / permit)

Numbered build steps that turn the raw ECHO tables in `data/raw/` into the
facility-year and permit-level analysis panels in `data/processed/`. Rebuild everything
with **`Rscript run_all.R`** (from the repo root), which sources each step in order in
an isolated environment; steps pass data via CSVs on disk. Any step can also be run alone.

> **Not to be confused with `updated panel/`.** That folder builds the facility-**month**
> panel (steps `01…07`, documented in `updated panel/READMEs/`). The scripts here build
> the facility-**year** and permit panels.

## Steps

| Script | Output (in `data/processed/`) |
|---|---|
| `01_build_npdes_panel.R` | base facility-year enforcement panel |
| `02_filter_major_individual_facilities.R` | major + individual filter of the base panel |
| `03_build_facility_panel_major_individual.R` | FRS-facility panel (never-minor, entry/exit) |
| `04_build_permit_panel_major_continuous.R` | permit panel: major every year (balanced) |
| `05_build_permit_panel_major_entryexit.R` | permit panel: never-minor (entry/exit) |

## Helpers (not part of the numbered chain)

| Script | Purpose |
|---|---|
| `build_effluent_violations_npdes_month_panel.R` | Builds `effluent_violations_npdes_month_panel_2005_2025.csv` (permit × month D80/D90/E90 counts), consumed by `updated panel/06_add_effluent_violations.R`. |
| `filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R` | Streams the FY2025 DMR file and keeps only TSS (`00530`) / effluent-gross / monthly-average rows → `dmr_fy2025_exo_00530_effgross_monthlyavg.csv`. |

## Conventions

- Sources `_paths.R`; reads raw as character; deterministic (no seeds).
- Inputs are immutable `data/raw/` files; outputs go to `data/processed/`.

Definitions of "major", "individual", and the panel windows are documented in each
script's header; see the root `README.md` and `docs/` for the shared conventions.
