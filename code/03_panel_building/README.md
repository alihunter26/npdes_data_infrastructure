# `code/03_panel_building/` — facility-by-month panel pipeline

The six numbered scripts that build the **facility-by-month panel** of major,
individually-permitted NPDES facilities, 2005–2025, from the raw ECHO/ICIS-NPDES data
in `data/raw/`. Each step reads the prior step's CSV from `data/processed/` and writes
the next.

> This is distinct from this repo's own root-level `build/` sibling folder (see
> `code/README.md`).

## Steps

| Step | Script | Adds |
|---|---|---|
| 01 | `01_build_facility_month_panel_major_individual.R` | base facility × month spine + facility attributes + corrected `FACILITY_OPERATING` |
| 02 | `02_add_inspections.R` | inspection counts by type & conductor |
| 03 | `03_add_naics_sic.R` | NAICS / SIC industry codes |
| 04 | `04_add_violations.R` | PS/CS/SE violation counts |
| 05 | `05_add_enforcement.R` | formal/informal enforcement counts + penalty $ |
| 06 | `06_add_effluent_violations.R` | all effluent-violation counts: TSS subset + all-parameter D80/D90/E90 (final panel) |

> The missingness audit that used to occupy the "step 07" name is now a diagnostic:
> [`../diagnostics/missingness/missingness_audit_major_individual.R`](../diagnostics/missingness/missingness_audit_major_individual.R).

> **2026-07-23: retired a separate step 07.** `FACILITY_OPERATING` used to be corrected
> by a standalone post-processing script (step 07, run after step 06). That correction
> now runs **inside step 01** — it only ever needed to know whether/when a facility had
> *any* real event (not the full detailed counts), so it doesn't need to wait for
> steps 02–06 to run first. See [`READMEs/01_build_facility_month_panel_major_individual.md`](READMEs/01_build_facility_month_panel_major_individual.md),
> Assumptions 10–13.

**Per-script documentation** — inputs, outputs, and every decision/assumption — lives in
[`READMEs/`](READMEs/README.md) (SSDE-style, one file per script).

## Prerequisite (not one of the six numbered steps)

- `build_effluent_violations_npdes_month_panel.R` — must run **before step 01**, not
  just before step 06: both steps read its output,
  `data/processed/effluent_violations_npdes_month_panel_2005_2025.csv`. Streams the raw
  effluent file (via DuckDB) into a condensed permit×month summary of both all-parameter
  and TSS-subset violation counts. See [`READMEs/build_effluent_violations_npdes_month_panel.md`](READMEs/build_effluent_violations_npdes_month_panel.md).

## Helper scripts (not part of the numbered chain)

- `summarize_violation_types.R` — tabulates violation-type frequencies → `output/tables/`.

> **Removed 2026-07-23:** `restrict_06_to_fy2025.R` (the federal-FY2025 row filter) was
> deleted. Its outputs (`data/processed/07_..._operating_corrected_fy2025.csv` and the
> earlier `data/processed/06_..._effluent_fy2025.csv`) remain on disk as static files —
> **no longer regenerable by any script.** Neither should be treated as a source of
> truth; filter the current 06 panel directly for a fresh FY2025 (or other) extract.

## Run order

```bash
Rscript "code/03_panel_building/01_build_facility_month_panel_major_individual.R"
Rscript "code/03_panel_building/02_add_inspections.R"
# … 03, 04, 05, 06 in order (06 = final panel)
Rscript "code/diagnostics/missingness/missingness_audit_major_individual.R"   # diagnostic, after 06
```

Or simply `Rscript run_all.R` from the repo root, which builds the condensed effluent
panel first (if it's not already on disk) and then runs all six steps in order.

Neither step 01 nor step 06 needs `python3` or `unzip` — both read only the pre-built
condensed effluent panel at
`data/processed/effluent_violations_npdes_month_panel_2005_2025.csv`. That file's own
build script (`build_effluent_violations_npdes_month_panel.R`, see above) is what needs
`unzip` and `gzip` on `PATH`, plus the DuckDB R package, since it's the one that
actually streams the raw ~16 GB effluent file.

> Step 01's `OUT_PATH` already writes the `01_`-prefixed name step 02 expects — a
> previously-documented mismatch here has been verified resolved in code. See
> [`READMEs/`](READMEs/README.md).

## Conventions

- Unit = FRS facility (`FACILITY_UIN`, or `NPDES_ID` when blank); grain = facility × year
  × month; window 2005–2025.
- Sources `_paths.R`; reads as character; deterministic (no seeds); permit→facility
  crosswalk rebuilt identically in steps 02/04/05/06 (and twice, for two different
  purposes, within step 01 itself — see its README).
