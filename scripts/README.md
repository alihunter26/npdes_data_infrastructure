# `scripts/` — code

All R code for building panels, summarizing datasets, and running diagnostics. Every
script sources `_paths.R` at the repo root for portable paths and can be run from
anywhere inside the repo.

## Subfolders

| Folder | Role |
|---|---|
| `summary/` | Per-dataset Excel summary generators. `summarize.R` is the single registry-driven entry point; the legacy `summarize_*.R` scripts are kept for reference. |
| `diagnostics/` | Data-quality checks and one-off analyses (duplicates, missingness, coverage). Not part of the panel build. |

> **Moved out:** the former `build/` subfolder (facility-year / permit builders `01–05`
> plus `build_effluent_violations_npdes_month_panel.R` and `filter_dmr_...R`) was
> relocated to the **EIL Summer** working folder (`../EIL Summer/build`), outside this
> repo. Its two effluent/DMR builders still produce inputs used by `updated panel/`.

## Loose top-level scripts

A few analysis/diagnostic scripts sit directly in `scripts/`:
`check_naics_sic_mapping.R`, `dup_enforcement_pairs.R`, `enforcement_by_permit_type.R`,
`facility_uin_multiple_npdes.R`, `formal_actions_same_fine_date.R`. These are ad-hoc
checks that write extracts to `output/` (some names overlap with `diagnostics/` — the
`diagnostics/` copies are the maintained versions).

## Related pipeline (elsewhere)

The facility-**month** panel (majors, individual) is built by the numbered scripts in
the top-level **`updated panel/`** folder, documented in `updated panel/READMEs/`. That
is separate from `scripts/build/` (which builds the facility-year / permit panels).

## Conventions

- **Portable paths:** source `_paths.R` (defines `CWA_ROOT`, `RAW_DIR`, `PROC_DIR`,
  `OUT_DIR`, …). No absolute paths.
- **Read CSVs as character** so IDs/codes/amounts aren't silently coerced.
- **Deterministic:** no random number generation; no seeds.
- **Outputs timestamped**, written to `output/` or `data/processed/`; raw data is never
  modified.

See the root `README.md` for the per-script tables.
