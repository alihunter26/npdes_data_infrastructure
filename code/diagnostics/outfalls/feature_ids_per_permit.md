# README — `feature_ids_per_permit.R`

*A standalone, **exploratory** diagnostic (not a panel-building step). Input: the
filtered FY2025 DMR file from `code/dmr/`. Output: console only.*

## Diagnostic Context

**1. What issue is this script designed to give us information about?**
Same underlying question as `outfalls/outfall_count_breakdown.R` (outfalls per
permit), but scoped to what facilities actually *report* discharging (via FY2025 DMR,
restricted to TSS/00530 monthly-average EXO outfalls) rather than what they're
*permitted* to have.

**2. What do we learn from the information created by this script?**
**Console-only, no saved output file, and not referenced in `docs/data_issues.md` or
`docs/missingness.md`** — I have no captured numbers from an actual run; only the
script's logic and comments, not a persisted result.

*How fully have we dug in?* ~10%, similarly to `missingness/cs_rnc_missingness.R` — the
tool exists and runs, but its output was never saved or written up, unlike its sibling
script `outfall_count_breakdown.R` in the same folder.

**3. What are the implications of what we learned for our issue?**
Undetermined without a saved run. Its real value would be comparing *permitted*
outfall counts (`outfall_count_breakdown.R`'s answer) against *actually-reporting*
outfall counts for the same population — if the two diverge substantially, that
signals under-reporting (permitted but non-reporting outfalls). That comparison is a
real open analytical question the repo cannot currently answer, because this script's
output was never captured.

## Overview

Counts how many distinct `PERM_FEATURE_ID` values each `EXTERNAL_PERMIT_NMBR` has in
the input file, and reports the distribution (how many permits have 1 feature, how
many have 2, etc.).

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. &boxtimes; All data publicly available.

### Details on each data source

- `data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg.csv` (derived) — the
  filtered FY2025 DMR file produced by the `code/dmr/` mini-pipeline (see its README),
  restricted to EXO outfalls reporting TSS (parameter `00530`) monthly-average values.
  Read via `fread(select = c("EXTERNAL_PERMIT_NMBR", "PERM_FEATURE_ID"), colClasses =
  "character")` — only the two ID columns.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `dmr_fy2025_exo_00530_effgross_monthlyavg.csv` | input (derived) | one row per DMR measurement (EXO outfall &times; TSS &times; monthly period) | derived, via `code/dmr/` |

**Output: console only — no file written.**

## Computational Requirements

- **R** 4.4.2. Package: `data.table`.
- **Controlled randomness:** none.
- **Memory/runtime:** only two columns read from an already-filtered (smaller) DMR
  extract; fast. `TODO:` OS/timing.

## Description of program

Read only `EXTERNAL_PERMIT_NMBR` and `PERM_FEATURE_ID` from the input file; count
distinct `PERM_FEATURE_ID` per permit; tabulate the distribution of that count across
permits (with percentage of all permits); print summary statistics (min/median/mean/max
features per permit) and the full breakdown table.

## Decisions and Assumptions

No numbered assumption block in the source. The one configurable parameter, `IN_PATH`,
is a named constant at the top of the script: "Point `IN_PATH` at another DMR-format
CSV to change the scope" (the header comment notes the full FY2025 CSV would need the
out-of-core/DuckDB approach used in `outfalls/outfall_count_breakdown.R`, not `fread`,
since it's too large to load whole).

## Output: console only

Prints: input path; distinct permit count and distinct feature-ID count; min/median/
mean/max features-per-permit; a full breakdown table of `n_features` &rarr;
`n_permits`, `pct_permits` (1 dp).

## Instructions to run

```bash
Rscript "code/diagnostics/outfalls/feature_ids_per_permit.R"
```
Requires `data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg.csv` to already
exist — produced by `code/dmr/filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R` (see
`code/dmr/README.md`). Run that first if the file is missing.

## Notes / edge cases

- Because the default input is already filtered to TSS/00530 monthly-average EXO
  outfalls, feature counts here describe *reporting* outfalls in that scope, not
  necessarily every outfall a permit holds — compare against
  `outfalls/outfall_count_breakdown.R` (same parent folder), which counts *permitted*
  EXO outfalls from `NPDES_LIMITS.csv` regardless of whether they reported.
- Changing `IN_PATH` to the unfiltered full FY2025 DMR CSV will not work with
  `fread` at that file's size — see the DuckDB approach in
  `outfalls/outfall_count_breakdown.R` for the pattern to use instead.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
