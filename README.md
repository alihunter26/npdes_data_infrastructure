# NPDES Data Infrastructure

Research project exploring facility-level compliance, enforcement, and water-quality
outcomes using National Pollutant Discharge Elimination System (NPDES) data under the 
Clean Water Act (CWA) from EPA's Enforcement and Compliance History Online (ECHO) system.

## Data Sources

All data is from [EPA ECHO Data Downloads](https://echo.epa.gov/tools/data-downloads#downloads).
Raw files live under `data/raw/` and are treated as **immutable** (never edited in place).

| Location | Contents |
|---|---|
| `data/raw/npdes_downloads/` | 15 core ICIS-NPDES tables: facilities, permits, violations (compliance-schedule, permit-schedule, single-event), formal & informal enforcement, inspections, QNCR history, violation–enforcement links, NAICS/SIC, permit components & feature coords, data groups |
| `data/raw/NPDES_LIMITS.csv` | Permit-level effluent limits by parameter and limit set |
| `data/raw/npdes_dmrs_fy2025.zip` | Discharge Monitoring Reports, FY2025 (`NPDES_DMRS_FY2025.csv` inside) |
| `data/raw/npdes_eff_downloads … .zip` | Effluent violations (`NPDES_EFF_VIOLATIONS.csv`, ~16 GB uncompressed) |
| `data/raw/Attains/` | `ATTAINS_AU_CATCHMENTS`, `NPDES_CATCHMENTS`, `NPDES_ATTAINS_AU_SUMMARIES` — links dischargers to receiving-water assessments |
| `data/raw/Master General Permits/` | `ICIS_MASTER_GENERAL_PERMITS.csv` (+ source zip) |
| `data/raw/npdes_outfalls_layer.csv` | Spatial layer of permitted outfalls/discharge points |

Raw data is excluded from version control (see `.gitignore`) due to size.

## Repository Structure

```
CWA/
├── _paths.R          # central path config (anchors to repo root; no absolute paths)
├── run_all.R         # one-command rebuild of every panel:  Rscript run_all.R
├── data/
│   ├── raw/          # original ECHO downloads — never modified
│   │   ├── npdes_downloads/        # 15 core ICIS-NPDES tables
│   │   ├── Attains/                # receiving-water assessment links
│   │   └── Master General Permits/
│   ├── processed/    # cleaned / analysis-ready files (built from code)
│   └── crosswalks/   # reference tables (parameter, NAICS/SIC, state codes)
├── scripts/
│   ├── build/        # numbered panel pipeline (01_… → 07_…), orchestrated by run_all.R
│   ├── summary/      # per-dataset Excel summary sheets
│   └── diagnostics/  # data-quality checks and one-off analyses
├── output/           # generated summaries (.xlsx) and flagged/extract CSVs
│   ├── tables/       # diagnostic CSV extracts
│   └── figures/
└── docs/
    ├── data_dictionary.md   # key fields and table join logic
    ├── codebook.md          # variable definitions for processed data (stub)
    └── notes.md             # running notes on quirks, decisions, findings
```

## Scripts

### `scripts/build/` — panel pipeline

Numbered build steps that turn the raw ECHO tables into the analysis panels in
`data/processed/`. Rebuild everything with **`Rscript run_all.R`** (sources each step in
order in an isolated environment; steps pass data via CSVs on disk), or run any step alone.

| Step | Output |
|---|---|
| `01_build_npdes_panel.R` | base facility-year enforcement panel |
| `02_filter_major_individual_facilities.R` | major + individual filter of the base panel |
| `03_build_facility_panel_major_individual.R` | FRS-facility panel (never-minor, entry/exit) |
| `04_build_permit_panel_major_continuous.R` | permit panel: major every year (balanced) |
| `05_build_permit_panel_major_entryexit.R` | permit panel: never-minor (entry/exit) |

### `scripts/summary/` — dataset summaries

These all produce the **same summary-sheet format**: per variable, the percent missing,
distinct-category counts, top frequent values (with code → description lookups), and
numeric/date five-number summaries. Output is a timestamped `.xlsx` in `output/`.

| Script | Input | Output |
|---|---|---|
| `summarize_npdes.R` | every CSV in `npdes_downloads/` | `npdes_summary_*.xlsx` (one sheet per table) |
| `summarize_dmrs.R` | `npdes_dmrs_fy2025.zip` (read via `unzip -p`) | `dmrs_summary_*.xlsx` |
| `summarize_eff_violations.R` | full `NPDES_EFF_VIOLATIONS.csv`, streamed from its zip (chunked, ~16 GB) | `eff_violations_summary_*.xlsx` |
| `summarize_eff_violations_state.R` | effluent violations for one state — set `STATE` at the top (e.g. `"NY"`, `"VA"`, `"PR"`) | `eff_violations_<state>_*.csv` + `_summary_*.xlsx` |
| `summarize_master_general_permits.R` | `ICIS_MASTER_GENERAL_PERMITS.csv` | `master_general_permits_summary_*.xlsx` |
| `summarize_outfalls_layer.R` | `npdes_outfalls_layer.csv` | `outfalls_layer_summary_*.xlsx` |
| `summarize_attains.R` | CSVs in `Attains/` | `attains_summary_*.xlsx` |

`summarize_npdes.R` is the template the others mirror. It normalizes whitespace-only
cells (e.g. the literal space ECHO uses for "blank" in QNCR `HLRNC`) to `NA`, so the
`% Missing` column and the frequent-values list stay consistent. Set its `ONLY_FILE`
variable to summarize a single table instead of all of them.

### `scripts/diagnostics/` — diagnostics & checks

| Script | Purpose |
|---|---|
| `eff_flagged.R` | Flags suspicious effluent-violation rows for one state → `eff_flagged_<state>_*.csv`, each with a `FLAG_REASON`. Flags: negative `DMR_VALUE_NMBR`, negative `DMR_VALUE_STANDARD_UNITS`, a year before 1984 in any of four date columns, or any value > 1,000,000 in a non-ID column. State is set at the top or passed as an argument: `Rscript eff_flagged.R va` |
| `count_informal_exact_duplicates.R` | Counts fully-identical duplicate rows in informal enforcement and writes every duplicate row, copies side by side, to `output/tables/` |
| `dup_enforcement_pairs.R` | Diagnoses why `(NPDES_ID, ENF_IDENTIFIER)` pairs repeat in formal enforcement |
| `dup_rows_by_enf_type.R` | Extracts formal-enforcement rows identical except `ENF_TYPE_CODE`/`DESC` (one action recorded once per statute) → `output/tables/` |
| `cs_rnc_missingness.R` | Tests why RNC fields are ~61% blank in compliance-schedule violations (joins permit major/minor + RNC-tracking flags) |

`scripts/diagnostics/preview_dmr2025.R` is a one-off snippet to peek at the DMR zip.

## Conventions

- **Raw data is immutable.** Derived data is rebuilt from code into `data/processed/`.
- **Outputs are timestamped** (`*_YYYY-MM-DD_HHMM.{xlsx,csv}`); each run writes a new
  file rather than overwriting, so multiple dated versions accumulate in `output/`.
- **Read CSVs as character** (`colClasses = "character"` / `fread`) before analysis so
  IDs, codes, and penalty amounts aren't silently coerced.
- **Interpreting ECHO blanks:** across ICIS files a blank almost always means
  *"not applicable / hasn't occurred / not escalated"* — not "unknown." Some files use a
  literal space rather than an empty string. Don't treat blanks as missing-at-random.
  See `docs/notes.md`.

## Housekeeping

- **Portable paths.** Scripts no longer hardcode absolute paths — each sources `_paths.R`,
  which anchors to the repo root (the folder containing `.git`) and defines `CWA_ROOT`,
  `RAW_DIR`, `DMR_DIR`, `PROC_DIR`, and `OUT_DIR`. The repo runs unchanged on any clone or
  machine; run scripts from inside the repo (e.g. `Rscript run_all.R`).

## Context

The Clean Water Act (1972) established the NPDES program, requiring point-source
dischargers to obtain permits limiting pollutant releases into U.S. waters. ECHO
publishes the underlying compliance data publicly, enabling research on regulatory
enforcement, water-quality outcomes, and environmental equity. See `docs/data_dictionary.md`
for how the tables link together.
