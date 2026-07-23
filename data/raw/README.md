# `data/raw/` — immutable source data

Original EPA ECHO / ICIS-NPDES bulk downloads. **These files are never edited in
place.** Everything downstream is rebuilt from them into `data/processed/`.

## Provenance and availability

- **Source:** EPA Enforcement and Compliance History Online (ECHO),
  <https://echo.epa.gov/tools/data-downloads>. Public domain (U.S. Government works).
- **Access:** free, no registration; download the bulk files/zips and place them here.
- **Summary of availability:** ☒ All data publicly available.
- `TODO:` record the ECHO download date / data-refresh version.

## Contents

| Path | Contents |
|---|---|
| `npdes_downloads/` | 15 core ICIS-NPDES tables: facilities, permits, violations (CS/PS/SE), formal & informal enforcement, inspections, QNCR history, violation–enforcement links, NAICS/SIC, permit components & feature coords, data groups |
| `NPDES_LIMITS.csv` | Permit-level effluent limits by parameter and limit set (~7 GB) |
| `npdes_dmrs_fy2025.zip` | Discharge Monitoring Reports, FY2025 (`NPDES_DMRS_FY2025.csv` inside) — *referenced by scripts but may be absent locally* |
| `DMR/` | Per-fiscal-year DMR zips (`npdes_dmrs_fy2009.zip` … ) |
| `npdes_eff_downloads … .zip` | Effluent violations (`NPDES_EFF_VIOLATIONS.csv`, ~16 GB uncompressed). *Note: the filename contains a non-ASCII space; scripts that stream it create an ASCII symlink first.* |
| `Attains/` | `ATTAINS_AU_CATCHMENTS`, `NPDES_CATCHMENTS`, `NPDES_ATTAINS_AU_SUMMARIES` — dischargers ↔ receiving-water assessments |
| `Master General Permits/` | `ICIS_MASTER_GENERAL_PERMITS.csv` (+ source zip) |
| `npdes_outfalls_layer.csv` | Spatial layer of permitted outfalls / discharge points |
| `reference/` | ECHO ICIS-NPDES domain/lookup tables that decode coded columns. `REF_STATISTICAL_BASE.csv` = `STATISTICAL_BASE_CODE` → description (e.g. `MK` = Monthly Average, `MN` = Monthly Maximum). Referenced by the external `../EIL Summer/build/filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R` |

## Conventions

- **Immutable.** Do not modify, re-save, or clean these files. Derived/cleaned versions
  belong in `data/processed/`.
- **Large & untracked.** Excluded from version control via `.gitignore`. This README is
  the record of *what should be here and where to get it*; to keep it tracked in a
  replication package, add a `.gitignore` negation for `data/raw/README.md`.
- Read as character to preserve leading zeros and code formatting.

See the root `README.md` data-source table and `docs/data_dictionary.md` for how the
tables join.
