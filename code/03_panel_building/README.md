# `code/03_panel_building/` — facility-by-month panel pipeline

The seven numbered scripts that build the **facility-by-month panel** of major,
individually-permitted NPDES facilities, 2005–2025, from the raw ECHO/ICIS-NPDES data
in `data/raw/`. Steps 01–06 each read the prior step's CSV from `data/processed/` and
write the next; step 07 is a post-processing correction that reads only step 06's
output.

> This is distinct from the facility-**year** / permit builders, which live in the
> **EIL Summer** working folder (`../EIL Summer/build/`), outside this repo — not to be
> confused with this repo's own root-level `build/` sibling folder (a separate, newer
> addition; see `code/README.md`).

## Steps

| Step | Script | Adds |
|---|---|---|
| 01 | `01_build_facility_month_panel_major_individual.R` | base facility × month spine + facility attributes |
| 02 | `02_add_inspections.R` | inspection counts by type & conductor |
| 03 | `03_add_naics_sic.R` | NAICS / SIC industry codes |
| 04 | `04_add_violations.R` | PS/CS/SE violation counts |
| 05 | `05_add_enforcement.R` | formal/informal enforcement counts + penalty $ |
| 06 | `06_add_effluent_violations.R` | all effluent-violation counts: TSS subset + all-parameter D80/D90/E90 |
| 07 | `07_extend_facility_operating.R` | corrects `FACILITY_OPERATING` (undercounted real activity by up to 250 months for some facilities); **final panel** |

> The missingness audit that used to occupy the "step 07" name is now a diagnostic,
> unrelated to the current step 07 above:
> [`../diagnostics/missingness/missingness_audit_major_individual.R`](../diagnostics/missingness/missingness_audit_major_individual.R).

**Per-script documentation** — inputs, outputs, and every decision/assumption — lives in
[`READMEs/`](READMEs/README.md) (SSDE-style, one file per script).

## Helper scripts (not part of the numbered chain)

- `summarize_violation_types.R` — tabulates violation-type frequencies → `output/tables/`.
- `restrict_06_to_fy2025.R` — restricts the current final panel to **federal FY2025**
  (Oct 2024 – Sep 2025; set `FY_CALENDAR <- TRUE` for calendar 2025). Pure row filter,
  all columns preserved. **Repointed 2026-07-23** from the step-06 panel to the step-07
  panel (its own filename still says "06" for historical reasons) →
  `data/processed/07_..._operating_corrected_fy2025.csv`. Run after step 07. The old
  06-sourced output, `data/processed/06_..._effluent_fy2025.csv`, remains on disk
  unchanged and should not be used going forward.

## Run order

```bash
Rscript "code/03_panel_building/01_build_facility_month_panel_major_individual.R"
Rscript "code/03_panel_building/02_add_inspections.R"
# … 03, 04, 05, 06 in order
Rscript "code/03_panel_building/07_extend_facility_operating.R"               # final panel
Rscript "code/diagnostics/missingness/missingness_audit_major_individual.R"   # diagnostic, after 06
```

Or simply `Rscript run_all.R` from the repo root, which runs all seven steps in order.

Step 06 needs `python3` and `unzip` on `PATH` (it streams the raw effluent file), plus
the condensed effluent panel from `build_effluent_violations_npdes_month_panel.R` — in
the external **EIL Summer** working folder (`../EIL Summer/build/`, outside this repo,
distinct from this repo's own `build/`); its output CSV lives in `data/processed/`.

> Step 01's `OUT_PATH` already writes the `01_`-prefixed name step 02 expects — a
> previously-documented mismatch here has been verified resolved in code. See
> [`READMEs/`](READMEs/README.md).

## Conventions

- Unit = FRS facility (`FACILITY_UIN`, or `NPDES_ID` when blank); grain = facility × year
  × month; window 2005–2025.
- Sources `_paths.R`; reads as character; deterministic (no seeds); permit→facility
  crosswalk rebuilt identically in steps 02/04/05/06.
