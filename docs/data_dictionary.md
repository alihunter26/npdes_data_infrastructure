# Data Dictionary

Notes on key variables, table relationships, and join logic across the ICIS-NPDES datasets.

## Key Linking Fields

| Field | Description | Tables |
|---|---|---|
| `EXTERNAL_PERMIT_NMBR` | NPDES permit ID — master key across all ICIS tables | Facilities, Permits, Limits, DMR, Violations |
| `VERSION_NMBR` | Permit version; `0` = current | Permits, Limits, DMR |
| `PERM_FEATURE_NMBR` | Specific outfall/discharge point within a permit | Limits, DMR, Discharge Points |
| `NPDES_ID` | Alternate permit identifier used in some tables | Catchments, ATTAINS summaries |
| `REGISTRY_ID` | EPA facility registry ID | Facilities, Inspections, Informal Enforcement |
| `NHDPLUSID` | NHDPlus catchment ID — links facilities to hydrologic network | Catchments, ATTAINS |
| `ASSESSMENTUNITIDENTIFIER` | ATTAINS water body ID | ATTAINS catchments, ATTAINS summaries |
| `NPDES_VIOLATION_ID` | Identifies one violation record | CS/PS/SE/EFF Violations, Violation-Enforcement bridge |
| `ENF_IDENTIFIER` | Identifies one enforcement action | Formal/Informal Enforcement, Violation-Enforcement bridge |

## Table Relationships

```
ICIS_FACILITIES
    └── ICIS_PERMITS (via EXTERNAL_PERMIT_NMBR)
            ├── NPDES_LIMITS (via EXTERNAL_PERMIT_NMBR + VERSION_NMBR + PERM_FEATURE_NMBR)
            ├── DMR (via EXTERNAL_PERMIT_NMBR + VERSION_NMBR + PERM_FEATURE_NMBR)
            └── CS/PS/SE/EFF Violations (via NPDES_ID)
                    └── NPDES_VIOLATION_ENFORCEMENTS (bridge: NPDES_VIOLATION_ID ↔ ENF_IDENTIFIER)
                            └── NPDES_FORMAL/INFORMAL_ENFORCEMENT_ACTIONS (via ENF_IDENTIFIER)
NPDES_CATCHMENTS (via NPDES_ID)
    └── ATTAINS_AU_CATCHMENTS (via NHDPLUSID)
    └── NPDES_ATTAINS_AU_SUMMARIES (via NPDES_ID + ASSESSMENTUNITIDENTIFIER)
```

Enforcement is **not** a child of effluent violations specifically — it links to
violations of *any* type (CS/PS/SE/EFF) through the `NPDES_VIOLATION_ENFORCEMENTS`
bridge table, not directly via `NPDES_ID`.

## Field notes

### `OFFICIAL_FLG` — `NPDES_INFORMAL_ENFORCEMENT_ACTIONS`

Marks whether an informal-enforcement record is an **official enforcement action** (`Y`) or an
**unofficial internal/procedural step** (`N`). Measured split: `Y` ≈ 84% (691,679), `N` ≈ 16%
(130,298).

- **`Y` (official)** — a formal written action notifying the facility of noncompliance:
  Letter of Violation / Warning Letter (`LOVWL`), Notice of Violation (`NOV`), Notice of
  Noncompliance (`NONC`).
- **`N` (unofficial)** — internal agency process, communications, or dispositions that ICIS logs
  but are not actions taken against the discharger: Agency Enforcement Review (`AER`), "Under
  Review" (`UNDREV`), Enforcement Meeting (`ENFMTG`), Phone Call/Email (`PHEMAIL`), Information
  Request Letter (`IRL`), "No Further Action" (`NFA`), etc.

**Use:** when counting informal enforcement actions, restrict to `OFFICIAL_FLG == "Y"` — including
`N` rows inflates counts with phone calls, reviews, and placeholders that aren't enforcement.
(Separately, `ENF_TYPE_CODE` values that differ only by a trailing `S` — e.g. `AER`/`AERS`,
`PHEMAIL`/`PHEMLS` — are the state-issued vs EPA-issued variants of the same activity, a distinct
axis from `OFFICIAL_FLG`.)

