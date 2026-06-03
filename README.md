# NPDES

Research project exploring facility-level compliance and water quality outcomes using NPDES data from EPA's Enforcement and Compliance History Online (ECHO) system.

## Data Sources

All data is sourced from [EPA ECHO Data Downloads](https://echo.epa.gov/tools/data-downloads#downloads). Key datasets include:

- **ICIS-NPDES** — facility, permit, and compliance records
- **NPDES Limits** — permit-level effluent standards by parameter
- **Discharge Monitoring Reports (DMR)** — self-reported discharge measurements by facility and monitoring period
- **NPDES Discharge Points** — spatial locations of permitted outfalls
- **NPDES Catchment & ATTAINS** — links dischargers to receiving water body assessments

## Repository Structure

```
NPDES/
├── data/
│   ├── raw/          # original downloaded files — never modified
│   ├── processed/    # cleaned and analysis-ready files
│   └── crosswalks/   # reference tables (parameter codes, NAICS/SIC, state codes, etc.)
├── scripts/          # numbered R scripts for downloading, cleaning, and analysis
├── output/
│   ├── tables/       # summary tables and regression output
│   └── figures/      # plots and maps
└── docs/
    ├── data_dictionary.md   # variable definitions and table join logic
    ├── codebook.md          # variable definitions for processed datasets
    └── notes.md             # running notes on data quirks and decisions
```

## Data Notes

Raw data files are excluded from version control (see `.gitignore`) due to file size. Download scripts in `scripts/` reproduce the raw data from ECHO.

## Context

The Clean Water Act (1972) established the NPDES program, requiring point-source dischargers to obtain permits limiting pollutant releases into U.S. waters. ECHO publishes the underlying compliance data publicly, enabling research on regulatory enforcement, water quality outcomes, and environmental equity.
