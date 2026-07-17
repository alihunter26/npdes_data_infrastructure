# `data/crosswalks/` — reference & linking tables

Small, regenerable reference tables used to join permit-keyed and facility-keyed data
across the ICIS-NPDES files.

## Contents

| File pattern | Purpose |
|---|---|
| `xwalk_npdesid_externalpermit_<timestamp>.csv` | Crosswalk between `NPDES_ID` and `EXTERNAL_PERMIT_NMBR` (the two permit identifiers ECHO uses across different tables). Needed because some files key on one and some on the other. |

Files are **timestamped** (`*_YYYY-MM-DD_HHMM.csv`); each build writes a new dated
version rather than overwriting, so multiple vintages accumulate — use the latest.

## Conventions

- **Derived, not source.** Built from `data/raw/` (ICIS permits/facilities), so they can
  be regenerated; do not hand-edit.
- **Untracked.** `data/crosswalks/*.csv` is gitignored.
- Keys stored as text to preserve formatting.

For how the ICIS identifiers relate, see `docs/data_dictionary.md`.
