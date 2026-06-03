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

## Table Relationships

```
ICIS_FACILITIES
    └── ICIS_PERMITS (via EXTERNAL_PERMIT_NMBR)
            └── NPDES_LIMITS (via EXTERNAL_PERMIT_NMBR + VERSION_NMBR + PERM_FEATURE_NMBR)
            └── DMR (via EXTERNAL_PERMIT_NMBR + VERSION_NMBR + PERM_FEATURE_NMBR)
                    └── NPDES_EFF_VIOLATIONS (via NPDES_VIOLATION_ID)
                            └── NPDES_FORMAL_ENFORCEMENT_ACTIONS (via NPDES_ID)
NPDES_CATCHMENTS (via NPDES_ID)
    └── ATTAINS_AU_CATCHMENTS (via NHDPLUSID)
    └── NPDES_ATTAINS_AU_SUMMARIES (via NPDES_ID + ASSESSMENTUNITIDENTIFIER)
```

## Notes

