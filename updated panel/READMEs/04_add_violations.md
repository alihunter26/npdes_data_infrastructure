# README — `04_add_violations.R`

*Step 4 of the facility-by-month panel build. Input: step-03 panel + raw violation
files. Output: the panel with four kinds of violation counts.*

## Overview

Attaches per-facility-month counts of four violation types: **permit-schedule (PS)**,
**compliance-schedule (CS)**, **single-event (SE)**, and **TSS effluent** violations.
The large effluent file is streamed straight from its zip and pre-filtered so only the
TSS / effluent-gross / monthly-average subset reaches R.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. ☒ All data publicly available.

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `data/processed/03_..._naics_sic_2005_2025.csv` | `.csv` | step-03 panel |
| `data/raw/npdes_downloads/NPDES_PS_VIOLATIONS.csv` | `.csv` | `NPDES_ID`, `NPDES_VIOLATION_ID`, `SCHEDULE_DATE` |
| `data/raw/npdes_downloads/NPDES_CS_VIOLATIONS.csv` | `.csv` | `NPDES_ID`, `NPDES_VIOLATION_ID`, `SCHEDULE_DATE` |
| `data/raw/npdes_downloads/NPDES_SE_VIOLATIONS.csv` | `.csv` | `NPDES_ID`, `NPDES_VIOLATION_ID`, `SINGLE_EVENT_VIOLATION_DATE`, `SINGLE_EVENT_END_DATE` |
| `NPDES_EFF_VIOLATIONS.csv` (inside its zip in `data/raw/`) | `.csv` in `.zip`, ~16 GB unzipped | `NPDES_ID`, `NPDES_VIOLATION_ID`, `VIOLATION_CODE`, `PARAMETER_CODE`, `MONITORING_LOCATION_CODE`, `STATISTICAL_BASE_MONTHLY_AVG`, `MONITORING_PERIOD_END_DATE` |
| `ICIS_FACILITIES.csv` | `.csv` | crosswalk (`NPDES_ID`, `FACILITY_UIN`) |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| step-03 panel | input | facility × month | derived |
| PS/CS/SE/EFF violation files | input (raw) | violation | via ECHO |
| `data/processed/04_..._violations_2005_2025.csv` | **output** | facility × year × month | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `lubridate`.
- **External tools:** `python3` on `PATH` (streams/filters the effluent file) and
  `unzip` (the effluent CSV is read via `unzip -p`, never extracted to disk).
- **Controlled randomness:** none.
- **Memory/runtime:** the effluent file is ~16 GB uncompressed but is pre-filtered in a
  streaming pipe, so peak memory stays low — important on the 8 GB-RAM build machine.
  PS/CS/SE are small. `TODO:` OS/timing.

## Description of program

For each of PS/CS/SE: read, date the rows, filter to the window, crosswalk to
facilities, and count distinct violation IDs per facility-month. For effluent: stream
`NPDES_EFF_VIOLATIONS.csv` out of its zip through a Python filter that keeps only the
TSS subset and emits four columns; count those per facility-month by violation code.
Full-outer-merge the four count tables onto the panel and fill absent cells with 0.

## Decisions and Assumptions

1. **Violation grain = `NPDES_VIOLATION_ID`.** Count **distinct** IDs, never raw rows
   (SE has rare repeated IDs).
2. **Date = when the violation occurred** (PI guidance):
   - PS & CS: `SCHEDULE_DATE` (the missed-milestone due date; 100% present). Deliberately
     **not** `RNC_DETECTION_DATE` (EPA detection timing, ~54–61% blank).
   - SE: `SINGLE_EVENT_VIOLATION_DATE` (start; 100% present). `SINGLE_EVENT_END_DATE` is
     ignored; the violation is placed in the month it began (mirrors step 02's begin-date rule).
3. **Routed by `NPDES_ID` via the step-01 crosswalk** (`FACILITY_UIN` else `NPDES_ID`).
   A violation on **any** permit resolving to the facility is counted (PI guidance:
   "all permits at facility").
4. **The panel defines the observation set** — left-join; facility-months with no
   violation of a kind get **0**, not NA.
5. **Effluent violations filtered to a single specific limit** (PI guidance). Keep a row
   only if **all** of:
   - `PARAMETER_CODE == "00530"` (EPA's standard TSS code; synonym codes excluded),
   - `MONITORING_LOCATION_CODE == "1"` (Effluent Gross; `"EG"`/`"E1"` excluded),
   - `STATISTICAL_BASE_MONTHLY_AVG == "A"` (EPA's monthly-average-equivalent flag).

   Kept violations are dated by `MONITORING_PERIOD_END_DATE`. `N_TSS_EFF_D90 / _D80 /
   _E90` break the total out by `VIOLATION_CODE` (D90 = value overdue [limited];
   D80 = value overdue; E90 = numeric limit exceedance). `N_TSS_EFF_VIOLATIONS` is the
   total over all codes in the subset (≥ the sum of the three breakouts if any other
   code appears).
6. **The effluent file is streamed once and pre-filtered in Python.** `unzip -p
   <zip> NPDES_EFF_VIOLATIONS.csv | python3 <filter> 00530 1 A` → R's `fread` reads only
   the small filtered subset (4 columns). The Python filter uses `csv.reader` (correct
   quoting) and locates columns by header name (survives future reordering). The
   effluent zip's filename contains a **non-ASCII space** that `fread(cmd=)` cannot
   encode, so the script first creates an ASCII-named temporary **symlink** to the zip.

**Filters / drops:** window 2005–2025; rows with unparseable dates dropped (PS/CS 100%
parseable, SE ~100%); effluent rows failing the TSS filter are dropped in Python before
R sees them; inner-join to the crosswalk drops unroutable `NPDES_ID`s. Tables merged via
`Reduce(..., all = TRUE)` (full outer) so a facility-month with any one kind is kept;
NA → `0L`.

**Hardcoded parameters:** `YEAR_MIN = 2005`, `YEAR_MAX = 2025`; `TSS_PARAM_CODE =
"00530"`, `GROSS_LOC_CODE = "1"`, `MONTHLY_AVG = "A"`.

## Output columns (7)

`N_PS_VIOLATIONS`, `N_CS_VIOLATIONS`, `N_SE_VIOLATIONS`, `N_TSS_EFF_VIOLATIONS`,
`N_TSS_EFF_D90`, `N_TSS_EFF_D80`, `N_TSS_EFF_E90` (integer counts).

## Instructions to run

```bash
Rscript "updated panel/04_add_violations.R"
```
Run **after** step 03. Requires `python3` and `unzip` on `PATH`, and the effluent zip
present in `data/raw/`.

## Notes / edge cases

- Placement uses violation timing, not EPA detection timing (assumption 2).
- The TSS columns here are the **TSS-only** subset; step 06 adds the **all-parameter**
  D80/D90/E90 counts (a superset) as separate columns — both are kept on purpose.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
