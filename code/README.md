# `code/` — project code

All R code for downloading raw data, building the facility-by-month panel, summarizing
datasets, and running diagnostics. Every script sources `_paths.R` at the repo root for
portable paths and can be run from anywhere inside the repo. Numbered subfolders encode
execution order; unnumbered subfolders (`summary/`, `diagnostics/`) are reporting/QC,
not build steps.

## Subfolders

| Folder | Role |
|---|---|
| `00_setup/` | Package/directory checks, run first. See its `module_README.md`. |
| `01_data_download/` | Downloads the EPA ECHO / ICIS-NPDES bulk files into `data/raw/`. Off by default in `run_all.R` — see its `module_README.md`. |
| `02_cleaning/` | Shared cleaning helpers (`cleaning_helpers.R`) used by every step of `03_panel_building/`: safe raw-file reads, the permit→facility crosswalk, and date-combining mechanics. See its `module_README.md`. |
| `03_panel_building/` | The core pipeline: builds the facility-by-**month** panel of major, individually-permitted NPDES facilities, 2005–2025. Steps `01`–`06` (`06` = final panel); `01` also corrects `FACILITY_OPERATING` internally. Documented per-script in `03_panel_building/READMEs/`. |
| `summary/` | Per-dataset Excel summary generators. `summarize.R` is the single registry-driven entry point; the legacy `summarize_*.R` scripts are kept for reference. |
| `diagnostics/` | Data-quality checks and one-off analyses, grouped by topic (NAICS/SIC coverage, enforcement duplicates, missingness, outfalls, brief generation, effluent QC). Not part of the panel build — see `diagnostics/README.md`. |

## Sibling pipelines (outside `code/`, at the repo root)

Two other pipelines produce inputs the panel above consumes, but are **not** part of
`code/`'s numbered chain — they predate this reorg and have their own internal
structure, so they stay as clearly-labeled siblings rather than being forced into the
`00`–`03` shape:

- **`../dmr analysis/`** — filters the raw per-fiscal-year DMR files down to TSS /
  effluent-gross / monthly-average rows for major-individual permits. Its output CSVs
  feed `03_panel_building/06_add_effluent_violations.R`.
- **`../build/`** — a small two-step DMR-filtering mini-pipeline (run manually, not
  part of `run_all.R`): `filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R` (moved
  in from the external EIL Summer folder 2026-07-27) filters the raw FY2025 DMR
  file down to the TSS/effluent-gross/monthly-average subset, then
  `filter_dmr_fy2025_effgross_major_individual.R` restricts that to major/
  individual permits. Both read/write `data/processed/`.

## Conventions

- **Portable paths:** source `_paths.R` (defines `CWA_ROOT`, `RAW_DIR`, `PROC_DIR`,
  `OUT_DIR`, …). No absolute paths.
- **Read CSVs as character** so IDs/codes/amounts aren't silently coerced.
- **Deterministic:** no random number generation; no seeds.
- **Outputs timestamped**, written to `output/` or `data/processed/`; raw data is never
  modified.
- **One master script:** `../run_all.R` runs `00_setup/`, optionally
  `01_data_download/`, then the full `03_panel_building/` chain in order.

See the root `README.md` for the per-script tables.
