# README — `enforcement_by_permit_type.R`

*A standalone **diagnostic** (not a panel-building step). Input: raw permits and
enforcement files. Output: one CSV (not timestamped).*

## Diagnostic Context

**1. What issue is this script designed to give us information about?**
Does enforcement intensity (formal vs. informal) differ systematically by permit type
(Individual vs. General) and facility size (Major vs. Minor) — i.e., are majors and
individually-permitted facilities actually enforced more formally/severely, as might be
assumed?

**2. What do we learn from the information created by this script?**
Informal actions dominate everywhere, including for Major/Individual facilities:
Individual-Major has 210,134 total actions, 85.3% of them informal. Individual-Minor
(393,452 actions, 89.2% informal) and General-Minor (261,247 actions, 91.1% informal)
are the two largest buckets by volume (`output/enforcement_by_permit_type.csv`).

*How fully have we dug in?* ~50%. This answers the raw-count cross-tab cleanly at full
scale, but it's explicitly a snapshot (permit type/status collapsed to one first-seen
value per `NPDES_ID` across all versions — see Assumption 1) with no year filter, so it
can't speak to whether this pattern has changed over time.

**3. What are the implications of what we learned for our issue?**
Reinforces `docs/data_issues.md`'s guidance that severity can't be inferred from
formal-vs-informal counts alone, since informal dominates even for the "most major"
facilities — "formal action" isn't a good proxy for "big violation." Any severity
ranking needs a better outcome variable (e.g. SNC flags, or deduplicated penalty $ per
`formal_actions_same_fine_date.R`) than raw formal/informal counts.

## Overview

Cross-tabulates formal vs. informal enforcement-action counts by permit type
(Individual/General/Other/Unmatched) &times; facility major/minor status.

## Data Availability and Provenance Statements

EPA ECHO / ICIS-NPDES public bulk data (<https://echo.epa.gov/tools/data-downloads>),
public domain. `TODO:` download date. &boxtimes; All data publicly available.

### Details on each data source

| File | Key fields used |
|---|---|
| `data/raw/npdes_downloads/ICIS_PERMITS.csv` | `EXTERNAL_PERMIT_NMBR`, `PERMIT_TYPE_CODE`, `MAJOR_MINOR_STATUS_FLAG` |
| `data/raw/npdes_downloads/NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv` | `NPDES_ID` only |
| `data/raw/npdes_downloads/NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv` | `NPDES_ID` only |

All read via `fread(select = ..., colClasses = "character")`, wrapped as tibbles.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `ICIS_PERMITS.csv`, `NPDES_FORMAL_ENFORCEMENT_ACTIONS.csv`, `NPDES_INFORMAL_ENFORCEMENT_ACTIONS.csv` | input (raw) | various | via ECHO |
| `output/enforcement_by_permit_type.csv` | **output** | one row per (permit_type, facility_status) | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `dplyr`, `tidyr`.
- **Controlled randomness:** none.
- **Memory/runtime:** selective-column reads; fast. `TODO:` OS/timing.

## Description of program

Reduce `ICIS_PERMITS.csv` to one row per `NPDES_ID` (first value kept across
versions); read formal and informal enforcement `NPDES_ID`s, tag each with `kind`
("Formal"/"Informal"), and stack them; left-join permit attributes on; classify
`permit_type` (Individual/General/Unmatched/Other) and `facility_status`
(Major/Minor/Unknown); cross-tabulate counts, pivot formal/informal into columns, and
compute `Total`/`pct_informal`; print and write.

## Decisions and Assumptions

1. **Permit attributes are a snapshot:** one `PERMIT_TYPE_CODE`/
   `MAJOR_MINOR_STATUS_FLAG` value per `NPDES_ID`, collapsed across all permit
   versions by keeping the first value (`distinct(NPDES_ID, .keep_all = TRUE)`) — not
   restricted to the current version the way `naics_california.R` is.
2. **Counts are action records (rows), not distinct facilities.** A facility with 5
   informal actions contributes 5 to the informal count.
3. **Actions whose `NPDES_ID` is not in `ICIS_PERMITS.csv` are reported as
   "Unmatched," not dropped** — the breakdown accounts for every action row.
4. **No year filter:** every action in both enforcement files is counted regardless of
   date.

## Output columns

One row per (`permit_type`, `facility_status`): `permit_type`, `facility_status`,
`Formal`, `Informal`, `Total`, `pct_informal` (1 dp), ordered by descending `Total`.

## Instructions to run

```bash
Rscript "code/diagnostics/enforcement_breakdowns/enforcement_by_permit_type.R"
```
No dependency on other scripts; reads raw data directly.

## Notes / edge cases

- Console output also prints a second rollup — totals by `permit_type` alone (pooling
  major/minor) — that is not written to the CSV.
- **Output is a cross-cutting exception to this repo's convention:** written to
  `output/` root (not `output/tables/`) and **not timestamped** — a re-run silently
  overwrites the previous copy.

## References

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>. Accessed `TODO`.
