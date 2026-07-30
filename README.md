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
├── run_all.R         # one command: raw download (if missing) → panel → website data
├── data/
│   ├── raw/          # original ECHO downloads — never modified
│   │   ├── npdes_downloads/        # 15 core ICIS-NPDES tables
│   │   ├── DMR/                    # per-fiscal-year DMR zips
│   │   ├── Attains/                # receiving-water assessment links
│   │   ├── Master General Permits/
│   │   └── reference/              # ECHO domain/lookup tables (code -> description)
│   ├── processed/    # cleaned / analysis-ready files (built from code)
│   └── crosswalks/   # NPDES_ID <-> EXTERNAL_PERMIT_NMBR crosswalk (built from code)
├── code/
│   ├── 00_setup/            # package/directory checks (run_all.R's first step)
│   ├── 01_data_download/    # scripted ECHO bulk-file downloader
│   ├── 02_cleaning/         # shared cleaning helpers used by 03_panel_building/; see its module_README.md
│   ├── 03_panel_building/   # facility-by-month panel pipeline (01–06); see its READMEs/
│   ├── summary/             # per-dataset Excel summary sheets + built-panel QA/composition checks
│   ├── diagnostics/         # data-quality checks, grouped by topic; see its README.md
│   └── dmr/                 # DMR-specific summaries/diagnostics + two filter pipelines (incl.
│                             #   git-ignored row-filter intermediates, code/dmr/*.csv; see below)
├── output/           # generated summaries (.xlsx) and flagged/extract CSVs
│   ├── tables/       # diagnostic CSV extracts
│   └── figures/
├── website/          # static site (HTML/JS/CSS) + its data build
│   ├── *.html        # pages: summaries, dataset, panel, temporal-coverage, briefs, …
│   ├── assets/       # style.css, table.js, datasets.js, year-coverage.js
│   ├── data/         # *.json the pages fetch (generated — see "Building the website")
│   └── scripts/      # build_website_data.R + the xlsx→JSON converters
└── docs/
    ├── data_dictionary.md      # key fields and table join logic
    ├── codebook.md             # variable definitions for the current facility-by-month panel
    ├── notes.md                # running notes on quirks, decisions, findings
    └── institutional_briefs/   # brief write-ups (.tex/.pdf) and their source figures/tables
```

## Scripts

### `code/dmr/` — FY2025 DMR filter mini-pipeline

A small two-step DMR-filtering mini-pipeline, run manually (not part of `run_all.R`).
Previously lived in its own root-level `build/` folder (a sibling to `code/`); folded
into `code/dmr/` 2026-07-27 alongside this repo's other DMR-specific scripts (see
`code/dmr/README.md`):

| Step | Script | Output |
|---|---|---|
| 1 | `filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R` (moved in from the external EIL Summer folder 2026-07-27) | `data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg.csv` — FY2025 DMR rows filtered to TSS / effluent-gross / monthly-average |
| 2 | `filter_dmr_fy2025_effgross_major_individual.R` | `data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg_major_individual.csv` — step 1's output restricted to major, individually-permitted facilities |

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

Two more scripts in `code/summary/` read a *built* panel rather than a raw source file
(see [`code/summary/README.md`](code/summary/README.md) for full detail):

- **`summarize_panel.R`** — face-validity/QA check for a built facility-month panel in
  `data/processed/` (`Rscript code/summary/summarize_panel.R [panel_filename]`).
  Its consistency-check section verifies component sums against totals, e.g.
  `N_AFR == N_STATE_AFR + N_EPA_AFR`, `N_JDC == N_STATE_JDC + N_EPA_JDC`, and
  `N_INFORMAL_ACTIONS == N_OFFICIAL_INFORMAL + N_UNOFFICIAL_INFORMAL` — the same
  identities `05_add_enforcement.R`'s own run log verifies (there is no single
  state/EPA split of *all* formal actions; agency is broken out separately within
  `AFR` and within `JDC` — see `code/03_panel_building/READMEs/05_add_enforcement.md`).
- **`summarize_violation_types.R`** — violation-type composition of a built panel
  (permit-schedule vs. compliance-schedule vs. single-event vs. effluent).

### `code/diagnostics/` — diagnostics & checks

Grouped into one subfolder per topic (NAICS/SIC coverage, enforcement duplicates,
missingness, outfalls, brief generation, effluent QC). See
[`code/diagnostics/README.md`](code/diagnostics/README.md) for the full, current list —
not duplicated here so this table can't drift out of sync as scripts are added.

## Building the website

The static site under `website/` shows its tables from `website/data/*.json`, which
are **generated**, not hand-written. `run_all.R` rebuilds them as its final stage
(`BUILD_WEBSITE <- TRUE`); to (re)build them on their own:

```bash
Rscript website/scripts/build_website_data.R
```

That orchestrator runs the per-dataset summaries (`code/summary/summarize.R`), the
year-coverage cross-tab, and the panel QA summary, then converts each to JSON
(`website/scripts/{xlsx_to_json,year_coverage_to_json,panel_to_json}.R`). Each step
runs in its own R process (memory isolation for the multi-GB `limits` summary) and
is fail-soft — a step that errors is logged and the rest continue, refreshing the
JSON that did build. It is **slow** (`limits` loads a multi-GB file; the two
eff_violations states each stream a ~2.9 GB zip).

**Serve over HTTP — not `file://`.** The pages load their JSON with `fetch()`, which
browsers block on the `file://` protocol, so opening a page by double-clicking it
shows empty tables. Serve the folder instead:

```bash
cd website && python3 -m http.server 8000    # then open http://localhost:8000
```

The built facility-by-month panel has its own QA page (`panel.html`, linked as the
first card on Data Summaries); the raw source datasets are the other cards. See
[`website/README.md`](website/README.md).

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
