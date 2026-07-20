# READMEs — facility-by-month panel build (`scripts/build panel/`)

This folder documents the seven numbered scripts in `scripts/build panel/` that build the
**facility-by-month panel** of major, individually-permitted NPDES facilities,
2005–2025. There is one README per script, written to the
[Social Science Data Editors](https://social-science-data-editors.github.io/guidance/)
template (and the Colmer lab
[Making-a-Replication-Package](https://github.com/jonathancolmer/lab-guide/wiki/Making-a-Replication-Package)
guidance). Each file is self-contained; export any of them to PDF from VS Code with
*Markdown PDF: Export (pdf)*.

| Step | Script | README | Adds |
|---|---|---|---|
| 01 | `01_build_facility_month_panel_major_individual.R` | [01](01_build_facility_month_panel_major_individual.md) | base facility×month spine + facility attributes |
| 02 | `02_add_inspections.R` | [02](02_add_inspections.md) | inspection counts by type & conductor |
| 03 | `03_add_naics_sic.R` | [03](03_add_naics_sic.md) | NAICS / SIC industry codes |
| 04 | `04_add_violations.R` | [04](04_add_violations.md) | PS/CS/SE violation counts |
| 05 | `05_add_enforcement.R` | [05](05_add_enforcement.md) | formal/informal enforcement counts + penalty $ |
| 06 | `06_add_effluent_violations.R` | [06](06_add_effluent_violations.md) | all effluent-violation counts: TSS subset + all-parameter D80/D90/E90 |
| 07 | `07_missingness_audit_major_individual.R` | [07](07_missingness_audit_major_individual.md) | missingness audit (diagnostic, not a panel step) |

## Pipeline order and conventions (shared by all steps)

- **Run in order 01 → 02 → … → 06.** Each step reads the prior step's CSV from
  `data/processed/` and writes the next. Step 07 is a standalone diagnostic that
  reads the final panel (06) and the raw files.
- **Unit of analysis:** the FRS facility (`FACILITY_UIN`), or `NPDES_ID` when
  `FACILITY_UIN` is blank. Panel grain is one row per **facility × year × month**.
- **Panel window:** January 2005 – December 2025 (`YEAR_MIN = 2005`, `YEAR_MAX = 2025`).
- **Portable paths:** every script sources `_paths.R` at the repo root to resolve
  `CWA_ROOT`; all paths below are relative to that root.
- **Determinism:** no random number generation and no seeds anywhere — the pipeline
  is fully reproducible.
- **ID/code columns are read as text** (`colClasses`/`na.strings`) so leading zeros
  in ZIP, NPDES_ID, and numeric-looking codes are preserved.
- **Permit → facility crosswalk (used by 02, 04, 05, 06):** rebuilt from
  `ICIS_FACILITIES.csv` exactly as in step 01 — map `NPDES_ID → FACILITY_UIN`, or to
  `NPDES_ID` itself when the UIN is blank.

## ⚠️ Known issue: 01 → 02 filename mismatch

Step 01 **writes** `data/processed/facility_month_panel_major_individual_2005_2025.csv`
(no numeric prefix), but step 02 **reads**
`data/processed/01_facility_month_panel_major_individual_2005_2025.csv` (with the
`01_` prefix). Only the prefixed file is present in `data/processed/`. A replicator
running 01 then 02 verbatim will hit a "file not found" at step 02 unless the output
of 01 is renamed to add the `01_` prefix. **This is unresolved** — decide whether to
(a) change 01's `OUT_PATH` to include `01_`, or (b) add an explicit rename/copy step.
See the 01 and 02 READMEs.

## Data source (all steps)

All raw inputs are **EPA ECHO / ICIS-NPDES national bulk data files**, downloaded
from <https://echo.epa.gov/tools/data-downloads>. They are U.S. Government works in
the public domain. `TODO:` record the exact download date and, if available, the ECHO
data-refresh/version stamp for the copy used.
