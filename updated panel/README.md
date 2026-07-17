# `updated panel/` — facility-by-month panel pipeline

The seven numbered scripts that build the **facility-by-month panel** of major,
individually-permitted NPDES facilities, 2005–2025, from the raw ECHO/ICIS-NPDES data
in `data/raw/`. Each step reads the prior step's CSV from `data/processed/` and writes
the next; step 07 is a standalone missingness diagnostic.

> This is distinct from `scripts/build/`, which builds the facility-**year** and permit
> panels.

## Steps

| Step | Script | Adds |
|---|---|---|
| 01 | `01_build_facility_month_panel_major_individual.R` | base facility × month spine + facility attributes |
| 02 | `02_add_inspections.R` | inspection counts by type & conductor |
| 03 | `03_add_naics_sic.R` | NAICS / SIC industry codes |
| 04 | `04_add_violations.R` | PS/CS/SE + TSS effluent violation counts |
| 05 | `05_add_enforcement.R` | formal/informal enforcement counts + penalty $ |
| 06 | `06_add_effluent_violations.R` | all-parameter effluent codes D80/D90/E90 (final panel) |
| 07 | `07_missingness_audit_major_individual.R` | missingness audit (diagnostic) |

**Per-script documentation** — inputs, outputs, and every decision/assumption — lives in
[`READMEs/`](READMEs/README.md) (SSDE-style, one file per script).

## Helper scripts (not part of the numbered chain)

- `read_permits.R` — small helper for reading the permits table.
- `summarize_violation_types.R` — tabulates violation-type frequencies → `output/tables/`.

## Run order

```bash
Rscript "updated panel/01_build_facility_month_panel_major_individual.R"
Rscript "updated panel/02_add_inspections.R"
# … 03, 04, 05, 06 in order
Rscript "updated panel/07_missingness_audit_major_individual.R"   # diagnostic, after 06
```

Step 04 also needs `python3` and `unzip` on `PATH`; step 06 needs the condensed
effluent panel from `scripts/build/build_effluent_violations_npdes_month_panel.R`.

> ⚠️ **Known issue:** step 01 writes `facility_month_panel_major_individual_2005_2025.csv`
> (no prefix) but step 02 reads the `01_`-prefixed name. Rename 01's output (or change
> its `OUT_PATH`) before running 02. See [`READMEs/`](READMEs/README.md).

## Conventions

- Unit = FRS facility (`FACILITY_UIN`, or `NPDES_ID` when blank); grain = facility × year
  × month; window 2005–2025.
- Sources `_paths.R`; reads as character; deterministic (no seeds); permit→facility
  crosswalk rebuilt identically in steps 02/04/05/06.
