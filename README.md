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
│   ├── build panel/  # facility-by-month panel pipeline (01–07); see its READMEs/
│   ├── summary/      # per-dataset Excel summary sheets
│   └── diagnostics/  # data-quality checks and one-off analyses
│   # NOTE: the former scripts/build/ pipeline was moved OUT of this repo to the
│   # EIL Summer working folder (../EIL Summer/build). See the note below.
├── output/           # generated summaries (.xlsx) and flagged/extract CSVs
│   ├── tables/       # diagnostic CSV extracts
│   └── figures/
└── docs/
    ├── data_dictionary.md   # key fields and table join logic
    ├── codebook.md          # variable definitions for processed data (stub)
    └── notes.md             # running notes on quirks, decisions, findings
```

## Scripts

### `build/` — panel pipeline (moved out of this repo)

> **Relocated:** the former `scripts/build/` folder now lives in the **EIL Summer**
> working folder (`../EIL Summer/build`), outside this repository. It holds the
> facility-**year** / permit builders (`01–05`) plus `build_effluent_violations_npdes_month_panel.R`
> and `filter_dmr_...R` — the latter two still produce inputs consumed by the
> `scripts/build panel/` pipeline (their output CSVs live in `data/processed/`), so keep that
> folder available when you need to rebuild those inputs.

The (relocated) numbered build steps turn the raw ECHO tables into the analysis panels
in `data/processed/`:

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

**`summarize.R` is the single entry point** — one script that builds any of these
summaries from a dataset registry, so the shared styles / helpers / worksheet writer
live in one place instead of being copy-pasted across scripts:

```
Rscript scripts/summary/summarize.R <dataset> [arg]
#   <dataset>: npdes | dmrs | attains | eff_violations | eff_violations_state
#              limits | master_general_permits | outfalls_layer   (or "all")
#   [arg]:     state code for eff_violations_state (default NY);
#              a single filename for npdes (default: NPDES_QNCR_HISTORY.csv),
#              or "all" to summarize every CSV in npdes_downloads/ in one workbook
```

Each dataset is a config entry in the `DATASETS` list (id/date columns, descriptions,
distinct-count label, reader). To add or adjust a summary, edit that entry — not a
whole script. Output verified byte-identical to the old per-dataset scripts, with one
intentional layout change: every sheet now uses the fuller 8-column categorical /
9-column numeric tables (a trailing, always-blank **Missing Explanation** column that
some sheets already had) and a single "Notes" footer. No summary statistic changes
value. The old per-dataset scripts below are kept as a reference and still run.

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
