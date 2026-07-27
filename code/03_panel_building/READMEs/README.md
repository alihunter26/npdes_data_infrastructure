# READMEs — facility-by-month panel build (`code/03_panel_building/`)

This folder documents the six numbered scripts in `code/03_panel_building/` that build
the **facility-by-month panel** of major, individually-permitted NPDES facilities,
2005–2025. There is one README per script, written to the
[Social Science Data Editors](https://social-science-data-editors.github.io/guidance/)
template (and the Colmer lab
[Making-a-Replication-Package](https://github.com/jonathancolmer/lab-guide/wiki/Making-a-Replication-Package)
guidance). Each file is self-contained; export any of them to PDF from VS Code with
*Markdown PDF: Export (pdf)*.

> The prerequisite script, `build_effluent_violations_npdes_month_panel.R` (condensed
> permit×month effluent-violation panel — must run before step 01), now lives in
> [`code/02_cleaning/`](../../02_cleaning/) (moved 2026-07-27), not here — see
> [`../../02_cleaning/build_effluent_violations_npdes_month_panel.md`](../../02_cleaning/build_effluent_violations_npdes_month_panel.md)
> for its README.

| Step | Script | README | Adds |
|---|---|---|---|
| 01 | `01_build_facility_month_panel_major_individual.R` | [01](01_build_facility_month_panel_major_individual.md) | base facility×month spine + facility attributes + corrected `FACILITY_OPERATING` |
| 02 | `02_add_inspections.R` | [02](02_add_inspections.md) | inspection counts by type & conductor |
| 03 | `03_add_naics_sic.R` | [03](03_add_naics_sic.md) | NAICS / SIC industry codes |
| 04 | `04_add_violations.R` | [04](04_add_violations.md) | PS/CS/SE violation counts |
| 05 | `05_add_enforcement.R` | [05](05_add_enforcement.md) | formal/informal enforcement counts + penalty $ |
| 06 | `06_add_effluent_violations.R` | [06](06_add_effluent_violations.md) | all effluent-violation counts: TSS subset + all-parameter D80/D90/E90 (final panel) |

The missingness audit that used to occupy the "step 07" name lives in
[`code/diagnostics/missingness/`](../../diagnostics/missingness/missingness_audit_major_individual.md).

> **2026-07-23: retired a separate step 07.** A `FACILITY_OPERATING`-correction script
> briefly existed as step 07 (it had to run after step 06 because it needed every event
> type already assembled). It turned out only to need *existence*, not full counts, so
> it now runs **inside step 01** instead — `FACILITY_OPERATING` is correct from the
> moment it's first created. See step 01's README (Assumptions 10–13) for the full
> story, including a routing bug caught and fixed during the move (Assumption 13).
>
> **2026-07-27: that correction's scanning/extension logic moved again**, this time out
> of step 01's own body and into `use_operating_proxies.R` (still called by step 01,
> now with an on/off switch per proxy source). See `../use_operating_proxies.R` and
> step 01's README.

## Pipeline order and conventions (shared by all steps)

- **Run in order 01 → 02 → … → 06.** Each step reads the prior step's CSV from
  `data/processed/` and writes the next. Step 01 additionally reads several raw event
  files directly (existence only — see its README) to correct `FACILITY_OPERATING`
  before anything downstream uses it. The missingness audit
  (`code/diagnostics/missingness/missingness_audit_major_individual.R`) is a standalone
  diagnostic that reads the final panel and the raw files.
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
  `NPDES_ID` itself when the UIN is blank. Step 01 itself now builds this crosswalk
  **twice**: once restricted to individual/major-eligible permits (for the spine), and
  once unrestricted (for routing the event-existence scan) — see its README,
  Assumption 13.

## Resolved: 01 → 02 filename mismatch

This folder's READMEs previously flagged a mismatch where step 01 wrote
`facility_month_panel_major_individual_2005_2025.csv` (no numeric prefix) while step 02
read the `01_`-prefixed name. Verified against the current source
(`01_build_facility_month_panel_major_individual.R`'s `OUT_PATH`,
`code/03_panel_building/01_build_facility_month_panel_major_individual.R`): step 01
already writes the `01_`-prefixed name, so the mismatch no longer exists in code. No
action needed — see `run_all.R`'s output for confirmation that a fresh 01→02→…→06 run
completes without a "file not found" error.

## Data source (all steps)

All raw inputs are **EPA ECHO / ICIS-NPDES national bulk data files**, downloaded
from <https://echo.epa.gov/tools/data-downloads>. They are U.S. Government works in
the public domain. `TODO:` record the exact download date and, if available, the ECHO
data-refresh/version stamp for the copy used.
