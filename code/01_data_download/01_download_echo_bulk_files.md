# README — `01_download_echo_bulk_files.R`

*Step 1: downloads the EPA ECHO / ICIS-NPDES bulk data files into `data/raw/`,
replacing the previously-manual "click through the downloads page" step. Input:
none (fetches over HTTP). Output: files under `data/raw/`, plus a manifest at
`data/raw/_download_log.csv`.*

## Overview

Downloads every ECHO bulk-data source this repo's pipeline depends on: the 15-table
ICIS-NPDES bundle, effluent violations, permit limits, the outfalls spatial layer,
Master General Permits, the ATTAINS/catchment integration file, and one zip per
fiscal year of Discharge Monitoring Reports (FY2009–FY2025, plus a pre-FY2009
combined file). One config-table-driven loop handles all of them, mirroring the
registry pattern already used in `code/summary/summarize.R`.

## Data Availability and Provenance Statements

- **Source:** EPA Enforcement and Compliance History Online (ECHO) bulk downloads,
  <https://echo.epa.gov/tools/data-downloads>. U.S. Government works, public domain.
- **Summary of availability:** ☒ All data are publicly available, no registration
  required.
- **Access modality:** direct HTTPS downloads of static zip files for six of the
  seven non-DMR sources (see below); the per-fiscal-year DMR files are served from
  a JS-driven dropdown on the ECHO site rather than static links.

### Details on each data source

| Source | URL confirmed? | Extracted to |
|---|---|---|
| `npdes_downloads.zip` (15 core ICIS-NPDES tables) | Yes (fetched live page directly) | `data/raw/npdes_downloads/` |
| `npdes_eff_downloads.zip` | Yes | not extracted — read via `unzip -p` |
| `npdes_limits.zip` | Yes | `data/raw/` (→ `NPDES_LIMITS.csv`) |
| `npdes_outfalls_layer.zip` | Yes | `data/raw/` (→ `npdes_outfalls_layer.csv`) |
| `npdes_master_general_permits.zip` | Yes | `data/raw/Master General Permits/` |
| `npdes_attains_downloads.zip` | Yes | `data/raw/Attains/` |
| `npdes_dmrs_fy{2009..2025}.zip`, `npdes_dmrs_prefy2009.zip` | **No — inferred** (see Decisions and Assumptions) | not extracted |

`REF_STATISTICAL_BASE.csv` (`data/raw/reference/`) is **not** covered by this script
— see Decisions and Assumptions #3.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| Everything under `data/raw/` listed above | output | one row per source | this script |
| `data/raw/_download_log.csv` | output | one row per download attempt | this script |

## Computational Requirements

- **R**: base R only (`utils::download.file`, `utils::unzip`, `readBin`) — no new
  package dependency (`httr`/`curl`/`rvest` are not used anywhere in this repo).
- **External tools:** none required; `download.file(method = "libcurl")` is used,
  which ships with R.
- **Controlled randomness:** none.
- **Memory/runtime:** `TODO:` record actual runtime for a full run (dominated by the
  ~2.5 GB effluent file and 17 DMR-year zips, several hundred MB each).
- **Network:** requires outbound HTTPS access to `echo.epa.gov`.

## Description of program

1. Defines a `SOURCES` list: six confirmed non-DMR sources, then one entry per DMR
   fiscal year 2009–2025 plus a pre-FY2009 combined file (23 entries total).
2. For each source, if the destination already exists and `REFRESH` is `FALSE`
   (the default), skips it and logs `SKIPPED-EXISTS`.
3. Otherwise downloads the zip, validates it (file-size floor + zip magic-byte
   check on the first 4 bytes), and either extracts it (if `extract_to` is set) or
   leaves it zipped (effluent + all DMR files, since downstream scripts stream
   specific members via `unzip -p` rather than needing a full extraction).
4. Logs every attempt (timestamp, name, url, path, status, bytes) to
   `data/raw/_download_log.csv`, appending rather than overwriting.
5. Confirmed sources raise a hard error on failure. DMR sources (inferred URL) log
   `FAILED-inferred-url` and let the loop continue.
6. Sleeps 2 seconds between the 17 DMR-year requests (etiquette — one host, many
   requests in a row).
7. Prints a final summary and a reminder that `REF_STATISTICAL_BASE.csv` needs
   manual placement.

## Decisions and Assumptions

1. **Confirmed vs. inferred URLs.** Six of the seven non-DMR-per-year URLs were
   verified by fetching the live ECHO data-downloads page directly and reading its
   rendered link table. The per-fiscal-year DMR URL pattern
   (`.../npdes_dmrs_fy{year}.zip`) could **not** be confirmed the same way — that
   section of the page is a JS dropdown with no static `href` to read. The pattern
   used is inferred from (a) every other confirmed URL following
   `https://echo.epa.gov/files/echodownloads/<exact-local-filename>`, and (b) the
   local files already present in `data/raw/DMR/` being named exactly
   `npdes_dmrs_fy2009.zip` … `npdes_dmrs_fy2025.zip`. Because of this, DMR sources
   are marked `mandatory = FALSE`: a failure is logged and the run continues,
   rather than aborting on an unconfirmed guess.
2. **Raw-immutability default.** `REFRESH <- FALSE` at the top of the script means
   an existing file at a destination is never overwritten by default, consistent
   with `data/raw/README.md`'s "raw is immutable" convention. Set `REFRESH <- TRUE`
   to force a full re-download.
3. **`REF_STATISTICAL_BASE.csv` is out of scope.** No bulk-zip source for this
   small domain/lookup table (`data/raw/reference/`) was found on the ECHO
   downloads page or its linked summary pages. It remains a manual placement,
   flagged in the script's final message rather than silently skipped without
   explanation.
4. **Zips are kept after extraction**, not deleted — several downstream scripts
   (`code/03_panel_building/06_add_effluent_violations.R`,
   `code/diagnostics/missingness/missingness_audit_major_individual.R`, and others)
   read specific member CSVs directly out of a zip via `unzip -p` rather than
   requiring a full extraction.
5. **Validation is a size floor + zip magic bytes**, not a checksum against a
   known-good hash — ECHO does not publish per-file checksums, so there is nothing
   to compare against. A failed/redirected download from ECHO typically returns a
   small HTML error page rather than a zip, which the magic-byte check catches.

## Output columns — `data/raw/_download_log.csv` (6)

| Column | Description |
|---|---|
| `timestamp` | When this attempt ran (`YYYY-MM-DD HH:MM:SS`). |
| `name` | Source identifier (e.g. `npdes_downloads`, `npdes_dmrs_fy2025`). |
| `url` | Exact URL attempted. |
| `dest_path` | Where the zip was (or would have been) written. |
| `status` | `OK`, `SKIPPED-EXISTS`, `FAILED`, or `FAILED-inferred-url`. |
| `bytes` | File size in bytes (`NA` if the download failed before any bytes landed). |

## Instructions to run

```bash
Rscript "code/01_data_download/01_download_echo_bulk_files.R"
```

Or set `DOWNLOAD_DATA <- TRUE` in `run_all.R` to run this automatically before the
panel build. Safe to re-run: existing files are skipped unless `REFRESH <- TRUE`.

## Notes / edge cases

- A fresh download produces a clean `npdes_eff_downloads.zip` — if the old,
  non-ASCII-named `npdes_eff_downloads 12.30.45 PM.zip` is still present alongside
  it, delete the old one so `list.files(pattern = "eff.*zip")[1]` in
  `06_add_effluent_violations.R` can't nondeterministically pick between two
  matches.
- If an inferred DMR-year URL turns out wrong, the log will show
  `FAILED-inferred-url` for that specific year only — the rest of the run is
  unaffected.
- This script does not delete or modify anything already in `data/raw/`; it only
  adds what's missing (or, with `REFRESH <- TRUE`, replaces it).

## References

EPA ECHO bulk data downloads: <https://echo.epa.gov/tools/data-downloads>.
Accessed `TODO:` (record the date this script was first run against the live site).
