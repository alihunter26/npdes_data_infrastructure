# `data/` — project data

All data for the NPDES / Clean Water Act compliance project, split by provenance and
mutability. Follows the [SSDE](https://social-science-data-editors.github.io/guidance/)
data-availability conventions.

## Subfolders

| Folder | Contents | Mutability | Tracked? |
|---|---|---|---|
| `raw/` | Original EPA ECHO / ICIS-NPDES bulk downloads (permits, facilities, violations, enforcement, inspections, limits, DMRs, effluent violations, ATTAINS, outfalls) | **Immutable** — never edited in place | No (gitignored; too large) |
| `processed/` | Cleaned / analysis-ready panels and derived extracts, **rebuilt from code** | Regenerable | No (gitignored; large) |
| `crosswalks/` | Small reference/linking tables (e.g. `NPDES_ID ↔ EXTERNAL_PERMIT_NMBR`) | Regenerable | No (gitignored) |

## Provenance and availability

- **Source:** EPA Enforcement and Compliance History Online (ECHO),
  <https://echo.epa.gov/tools/data-downloads>. U.S. Government works, public domain.
- **Summary of availability:** ☒ All data publicly available.
- `TODO:` record the exact ECHO download date / data-refresh version for the copy used.

## Conventions (hard rules)

- **Raw is immutable.** Never modify anything in `raw/`. All derived data is written to
  `processed/` (or `crosswalks/`) **by code**, so any file here can be reproduced by
  re-running the scripts.
- **No hand-edited data.** Fix the script, not the CSV.
- **IDs and codes are text.** Read with `colClasses = "character"` so leading zeros in
  ZIP, `NPDES_ID`, and numeric-looking codes survive.
- **Blanks are usually structural** ("not applicable / hasn't occurred"), not
  missing-at-random — see `docs/notes.md` and `docs/missingness.md`.

Paths are resolved via `_paths.R` at the repo root (`RAW_DIR`, `PROC_DIR`, …). See the
root `README.md` for the full data-source table.
