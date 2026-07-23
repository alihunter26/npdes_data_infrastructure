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
├── run_all.R         # one-command rebuild of the panel:  Rscript run_all.R
├── data/
│   ├── raw/          # original ECHO downloads — never modified
│   │   ├── npdes_downloads/        # 15 core ICIS-NPDES tables
│   │   ├── Attains/                # receiving-water assessment links
│   │   └── Master General Permits/
│   ├── processed/    # cleaned / analysis-ready files (built from code)
│   └── crosswalks/   # reference tables (parameter, NAICS/SIC, state codes)
├── code/
│   ├── 00_setup/            # package/directory checks (run_all.R's first step)
│   ├── 01_data_download/    # scripted ECHO bulk-file downloader
│   ├── 02_cleaning/         # reserved — no dedicated module yet; see its module_README.md
│   ├── 03_panel_building/   # facility-by-month panel pipeline (01–07); see its READMEs/
│   ├── summary/             # per-dataset Excel summary sheets
│   └── diagnostics/         # data-quality checks, grouped by topic; see its README.md
├── build/            # sibling pipeline: facility-year / permit-panel builder (see below)
├── dmr analysis/     # sibling pipeline: DMR row-filtering, feeds 03_panel_building/06
├── output/           # generated summaries (.xlsx) and flagged/extract CSVs
│   ├── tables/       # diagnostic CSV extracts
│   └── figures/
└── docs/
    ├── data_dictionary.md   # key fields and table join logic
    ├── codebook.md          # variable definitions for the current facility-by-month panel (step 07)
    └── notes.md             # running notes on quirks, decisions, findings
```

## Scripts

### `build/` and the external EIL Summer builders — two separate things, easy to conflate

This repo has its **own** root-level `build/` folder (a sibling to `code/`, not nested
inside it — see decision in `code/README.md`), currently holding one script,
`filter_dmr_fy2025_effgross_major_individual.R`.

That is **distinct** from the original facility-**year** / permit-panel builders, which
genuinely still live outside this repo, in the **EIL Summer** working folder
(`../EIL Summer/build/`):

| Step | Output |
|---|---|
| `01_build_npdes_panel.R` | base facility-year enforcement panel |
| `02_filter_major_individual_facilities.R` | major + individual filter of the base panel |
| `03_build_facility_panel_major_individual.R` | FRS-facility panel (never-minor, entry/exit) |
| `04_build_permit_panel_major_continuous.R` | permit panel: major every year (balanced) |
| `05_build_permit_panel_major_entryexit.R` | permit panel: never-minor (entry/exit) |
| `build_effluent_violations_npdes_month_panel.R` | condensed effluent panel feeding `code/03_panel_building/06_add_effluent_violations.R` |
| `filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R` | DMR rows (TSS / effluent-gross / monthly-avg) |

Those two external scripts' output CSVs live in `data/processed/` and are still needed
to rebuild those specific inputs — keep that external folder available. This repo's own
`build/` is a newer, separate addition; the two are not the same folder and were never
merged.

### `code/summary/` — dataset summaries

These all produce the **same summary-sheet format**: per variable, the percent missing,
distinct-category counts, top frequent values (with code → description lookups), and
numeric/date five-number summaries. Output is a timestamped `.xlsx` in `output/`.

**`summarize.R` is the single entry point** — one script that builds any of these
summaries from a dataset registry, so the shared styles / helpers / worksheet writer
live in one place instead of being copy-pasted across scripts:

```
Rscript code/summary/summarize.R <dataset> [arg]
#   <dataset>: npdes | dmrs | attains | eff_violations | eff_violations_state
#              limits | master_general_permits | outfalls_layer   (or "all")
#   [arg]:     state code for eff_violations_state (default NY);
#              a single filename for npdes (default: NPDES_QNCR_HISTORY.csv),
#              or "all" to summarize every CSV in npdes_downloads/ in one workbook
```

Each dataset is a config entry in the `DATASETS` list (id/date columns, descriptions,
distinct-count label, reader). To add or adjust a summary, edit that entry — not a
whole script. Every sheet uses an 8-column categorical / 9-column numeric layout (a
trailing, always-blank **Missing Explanation** column) and a single "Notes" footer.

Datasets covered: `npdes` (every CSV in `npdes_downloads/`, one sheet per table),
`dmrs`, `attains`, `eff_violations` / `eff_violations_state`, `limits`,
`master_general_permits`, `outfalls_layer`.

### `code/diagnostics/` — diagnostics & checks

Grouped into one subfolder per topic (NAICS/SIC coverage, enforcement duplicates,
missingness, outfalls, brief generation, effluent QC). See
[`code/diagnostics/README.md`](code/diagnostics/README.md) for the full, current list —
not duplicated here so this table can't drift out of sync as scripts are added.

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
