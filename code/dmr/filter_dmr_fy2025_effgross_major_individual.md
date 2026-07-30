# README — `filter_dmr_fy2025_effgross_major_individual.R`

*Step 2 (final) of the FY2025 DMR filter mini-pipeline. Input:
`data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg.csv` +
`ICIS_PERMITS.csv`. Output:
`data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg_major_individual.csv`.*

## Overview

Restricts the EXO/TSS/effluent-gross/monthly-average FY2025 DMR file (built by
`filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R`) to permits that are **major
under an individual permit** — the same population the facility panels use. The DMR
file itself carries no major/minor or permit-type field, so those come from
`ICIS_PERMITS.csv`, joined on `EXTERNAL_PERMIT_NMBR` (= `NPDES_ID`).

## Data Availability and Provenance Statements

Input is **derived data** from step 1 of this mini-pipeline, joined against a raw
EPA file. See `filter_dmr_fy2025_exo_00530_effgross_monthlyavg.md` for the effluent
data's provenance.

### Details on each data source

| File | Key fields used |
|---|---|
| `data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg.csv` | all 57 columns; filtered by joining on `EXTERNAL_PERMIT_NMBR` |
| `data/raw/npdes_downloads/ICIS_PERMITS.csv` | `EXTERNAL_PERMIT_NMBR`, `PERMIT_TYPE_CODE`, `MAJOR_MINOR_STATUS_FLAG` |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `dmr_fy2025_exo_00530_effgross_monthlyavg.csv` | input (derived) | permit × outfall × parameter × period, all permits | from step 1 |
| `ICIS_PERMITS.csv` | input (raw) | permit × version | via ECHO |
| `dmr_fy2025_exo_00530_effgross_monthlyavg_major_individual.csv` | **output** | same as input, row-filtered to major-individual | derived |

## Computational Requirements

- **R** 4.4.2. Package: `data.table`.
- **Controlled randomness:** none.
- **Memory/runtime:** both inputs are already narrowed (step 1's output is a small
  fraction of the raw 9.68 GB file); read whole with `fread`, no out-of-core engine
  needed at this stage. `TODO:` OS/timing.

## Description of program

Build the ever-major, individual (`PERMIT_TYPE_CODE == "NPD"`) permit set from
`ICIS_PERMITS.csv` (any version row flagged `MAJOR_MINOR_STATUS_FLAG == "M"` makes
the whole permit eligible). Read step 1's output, keep only rows whose
`EXTERNAL_PERMIT_NMBR` is in that eligible set, and write the result.

## Decisions and Assumptions

1. **A permit present in the DMR file but absent from `ICIS_PERMITS.csv` cannot be
   classified and is dropped** — reported in the console log (rows/permits kept vs.
   dropped), not silently discarded without a trace.
2. **A blank `MAJOR_MINOR_STATUS_FLAG`** (~3.6% of `ICIS_PERMITS` rows, per
   `docs/data_issues.md`) **is not treated as `"M"`** — a permit with only
   blank/minor flags and no `"M"` in any version is non-major and dropped.
3. **"Ever major" pools across all permit versions**, matching the looser rule used
   in `code/03_panel_building/01_build_facility_month_panel_major_individual.R` — it
   does not require the permit to have been major in FY2025 specifically. The
   script's own header notes this as a place to change if a FY2025-specific
   definition is what an analysis actually needs.

## Output columns

Same 57 columns as `dmr_fy2025_exo_00530_effgross_monthlyavg.csv` — pure row filter,
no column selection.

## Instructions to run

```bash
Rscript code/dmr/filter_dmr_fy2025_effgross_major_individual.R
```
No arguments. Requires `filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R` to have
already produced its output. Not part of `run_all.R` — run manually.

## Notes / edge cases

- Console report includes rows kept/dropped and permits kept/dropped (with percentages)
  and an explicit count of permits dropped for "general / minor / not in ICIS," so a
  large unexpected drop is visible immediately rather than needing to be inferred.
- This is the final stage of the FY2025 mini-pipeline — a separate, standalone
  pipeline from the general DMR row-filter chain (`filter_dmr_major_individual.R`
  etc.), which uses the looser "ever major" rule identically but on a
  FY-parameterized, differently-filtered population.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
