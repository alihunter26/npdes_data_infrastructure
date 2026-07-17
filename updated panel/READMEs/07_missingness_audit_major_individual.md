# README — `07_missingness_audit_major_individual.R`

*Step 7: a standalone **diagnostic** (not a panel-building step). Input: the final panel
(06) + raw ICIS-NPDES files. Output: per-variable missingness tables.*

## Overview

For every core ICIS-NPDES bulk file used in steps 01–06, computes the percent missing of
each column **restricted to the major-individual population** defined by the final panel,
then flags variables that are ≥25% missing ("chronic") and attaches qualitative
annotations. This documents data quality; it does not modify the panel.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. ☒ All data publicly available.

### Details on each data source

- **Population source:** `data/processed/06_..._effluent_2005_2025.csv` — unique
  `FACILITY_UIN` and the split (semicolon) `NPDES_ID` list define the qualifying
  `NPDES_ID` set (`QUAL_IDS`).
- **13 raw ICIS-NPDES files** in `data/raw/npdes_downloads/` (all read as text /
  NA-tolerant): `ICIS_FACILITIES.csv`, `ICIS_PERMITS.csv` (restricted via
  `EXTERNAL_PERMIT_NMBR`), `NPDES_INSPECTIONS.csv`,
  `NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv`, `NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv`,
  `NPDES_NAICS.csv`, `NPDES_SICS.csv`, `NPDES_CS_VIOLATIONS.csv`,
  `NPDES_PS_VIOLATIONS.csv`, `NPDES_SE_VIOLATIONS.csv`, `NPDES_QNCR_HISTORY.csv`,
  `NPDES_VIOLATION_ENFORCEMENTS.csv` (restricted via `NPDES_VIOLATION_ID`),
  `NPDES_EFF_VIOLATIONS.csv` (~16 GB, streamed in chunks).
- **Deliberately excluded:** `NPDES_LIMITS.csv` (7 GB, out of scope), ATTAINS, the DMR
  fiscal-year files, and the outfalls layer.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| final panel (06) | input | facility × month | derived |
| 13 raw ICIS-NPDES files | input (raw) | various | via ECHO |
| `output/missingness_audit_major_individual_<timestamp>.csv` | **output** | file × variable | derived |
| `output/chronic_missingness_major_individual_<timestamp>.csv` | **output** | flagged variable | derived |

Output filenames carry a `format(Sys.time(), "%Y-%m-%d_%H%M")` timestamp.

## Computational Requirements

- **R** 4.4.2. Package: `data.table`. **External tool:** `unzip` (streams the effluent file).
- **Controlled randomness:** none.
- **Memory/runtime:** small/medium files read whole; the ~16 GB effluent file is streamed
  in 2 M-row chunks, keeping only per-column running totals — important on the 8 GB-RAM
  machine. `TODO:` OS/timing.

## Description of program

Build `QUAL_IDS` from the final panel; for each raw file, restrict to the qualifying
population and compute per-column percent missing; stream the effluent file in chunks
accumulating only column totals; write the full table and the ≥25%-missing subset (joined
to manual annotations).

## Decisions and Assumptions

1. **`NPDES_VIOLATION_ENFORCEMENTS.csv` has no `NPDES_ID`.** It links
   `NPDES_VIOLATION_ID` to `ENF_IDENTIFIER`, so the qualifying `NPDES_VIOLATION_ID` set is
   collected from the CS/PS/SE/EFF violation files (which do have `NPDES_ID`), then used to
   restrict this file.
2. **The effluent file is streamed in chunks** (`chunk_size = 2,000,000`; ~46.4 M rows).
   Only per-column running totals (non-missing count, row count) are kept across chunks.
3. **Small/medium files (<600 MB) are read whole**, restricted, and tabulated directly.
4. **Qualitative annotations are analyst judgment.** The `what_is_affected` /
   `why_problem` / `severity` columns come from a manual `ANNOTATIONS` lookup, keyed to
   the exact flagged variables — not derived. If a re-run after a data refresh surfaces a
   newly chronic variable not in the lookup, it appears with **blank** annotation columns
   (not silently hidden).

**Population:** `QUAL_IDS` = unique, sorted qualifying `NPDES_ID`s from the final panel.

**"Missing" definition:** blank string, literal `"NA"`, or true NA
(`na.strings = c("", "NA")`); `pct_missing = round(100 * n_missing / n, 2)`.

**"Chronic" definition:** `pct_missing ≥ CHRONIC_THRESHOLD` (**25**).

**Restriction by file:** most files via `%chin% QUAL_IDS` on `NPDES_ID`; `ICIS_PERMITS`
via `EXTERNAL_PERMIT_NMBR`; `NPDES_VIOLATION_ENFORCEMENTS` via `NPDES_VIOLATION_ID`; the
effluent file restricted per chunk.

**Hardcoded parameters:** `CHRONIC_THRESHOLD = 25`; `chunk_size = 2,000,000`.

## Output columns

- **Full table:** one row per (file, variable) with `n_rows`, `pct_missing`.
- **Chronic table:** the ≥25%-missing rows plus `what_is_affected`, `why_problem`,
  `severity` (blank when not yet annotated).

## Instructions to run

```bash
Rscript "updated panel/07_missingness_audit_major_individual.R"
```
Run **after** step 06 (needs the final panel to define the population). Requires `unzip`
and the effluent zip in `data/raw/`.

## Notes / edge cases

- `qual_violation_ids` is built incrementally as the CS/PS/SE/EFF files are read.
- A newly chronic variable absent from `ANNOTATIONS` surfaces with blank annotations,
  so data refreshes cannot silently hide new problems.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
