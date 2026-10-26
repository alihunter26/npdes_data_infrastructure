# README — `build_dmr_clean_panel.R`

*Builds a CLEANED DMR panel from the `code/dmr/` row-filter pipeline's step-3
output. Input: `code/dmr/03_dmr_fy<FY>_00530_monloc1.csv`. Output:
`data/processed/clean_dmr_<year>.csv`, where `<year>` is read off the data, not
off the `FY` toggle.*

## Overview

Takes the majors-under-individual / TSS / effluent-gross DMR file for one fiscal
year and reduces it to the variables worth keeping, adding the external-outfall
and monthly-average restrictions on top of what step 3 already applied. Every
judgment call is a named toggle in the CONFIG block, and the run log reports what
each choice cost in rows, permits and outfalls.

The script asserts step 3's restrictions rather than assuming them, so pointing
`INPUT_PATH` at an unfiltered or wrong-year file fails loudly instead of quietly
producing a different population.

## Data Availability and Provenance Statements

Input is **derived data** from step 3 of the `code/dmr/` pipeline — see
`filter_dmr_monloc1.md`, `filter_dmr_00530.md` and `filter_dmr_major_individual.md`
for the chain back to raw provenance. `FACILITY_ID` additionally reads **raw**
`ICIS_FACILITIES.csv` (ECHO NPDES bulk download).

### Details on each data source

| File | Key fields used |
|---|---|
| `code/dmr/03_dmr_fy<year>_00530_monloc1.csv` | the 20 `KEEP_COLS` + `VIOLATION_COLS` + 1 `INTERNAL_COLS` (see below) |
| `data/raw/npdes_downloads/ICIS_FACILITIES.csv` | `NPDES_ID`, `FACILITY_UIN` (via `build_facility_crosswalk()`) |
| `data/raw/reference/REF_STATISTICAL_BASE.csv` | `STATISTICAL_BASE_CODE`, `STATISTICAL_BASE_MONTHLY_AVG` (which bases count as a monthly average) |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `code/dmr/03_dmr_fy<year>_00530_monloc1.csv` | input (derived) | majors-under-individual, TSS, effluent-gross | from step 3 |
| `data/raw/npdes_downloads/ICIS_FACILITIES.csv` | input (**raw, immutable**) | one row per NPDES_ID | ECHO download |
| `data/raw/reference/REF_STATISTICAL_BASE.csv` | input (**raw**, reference) | one row per statistical base code | manual download, see `data/raw/README.md` |
| `data/processed/clean_dmr_<year>.csv` | **output** | permit × outfall × month × value type × limit set × statistical base × monitoring location × `LIMIT_ID` (unique, asserted) | derived (git-ignored) |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `lubridate`.
- **Controlled randomness:** none — no stochastic step, so no seed.
- **Memory/runtime:** reads a ~100 MB CSV fully into memory; ~1 min for FY2017.
  With `AUTO_RUN_PREREQS = TRUE` a cold start also runs pipeline steps 1–3,
  which costs ~45 min (mostly streaming the 8.24 GB zip member).

## Where `FACILITY_ID` comes from

The panel this feeds is one row per **physical facility** per month, but DMR rows
are recorded against a **permit** (`EXTERNAL_PERMIT_NMBR`). `FACILITY_ID` is the
permit → facility translation, and it is **not** an EPA column in the DMR file —
it is constructed. The chain, end to end:

1. `build_facility_crosswalk()` (in `code/02_cleaning/cleaning_helpers.R`) reads a
   fresh, **unrestricted** copy of raw `ICIS_FACILITIES.csv` — every `NPDES_ID` in
   the country, 1,212,522 rows — selecting only `NPDES_ID` and `FACILITY_UIN`.
   Unrestricted is deliberate: building the crosswalk from a population-filtered
   facilities file would leave rows belonging to a site's *other* permits with
   nowhere to route, and they would be silently dropped.
2. Both fields are `trimws()`-ed.
3. **The rule:** `FACILITY_UIN` if it is non-blank, otherwise the permit's own
   `NPDES_ID`. `FACILITY_UIN` is EPA's cross-program Facility Registry Service
   (FRS) id for the physical *site* — more stable than a permit number and shared
   across environmental programs. 2,560 of the 1,212,522 ICIS rows (0.2%) have a
   blank `FACILITY_UIN` and take the `NPDES_ID` fallback, which keeps those
   permits in the data instead of dropping them.
4. Rows with a blank `NPDES_ID` are dropped (unusable as a join key) and
   `unique()` collapses accidental repeats. Result: 1,212,522 permits mapping onto
   1,035,440 distinct facilities — 107,950 facilities carry more than one permit
   (max 362), which is the whole reason the translation is needed.
5. This script joins that table on `NPDES_ID = EXTERNAL_PERMIT_NMBR`, then
   **renames the column to upper case**: the helper returns it as `facility_id`,
   and the rename happens *here*, not in the helper, because other scripts share
   `build_facility_crosswalk()` and expect the lower-case name. Values and rule
   are untouched by the rename — it is cosmetic, so that every column in
   `clean_dmr_<year>.csv` reads in EPA's own ALL-CAPS style.

In the FY2017 output: 5,969 permits map to 5,942 facilities (27 sites hold more
than one permit), 0 rows fall back to `NPDES_ID`, and 0 rows fail to match — the run log
reports that last count as `Rows with no facility match` every run, and a non-zero
value there means permits in the DMR data are absent from `ICIS_FACILITIES.csv`.

Set `ADD_FACILITY_ID <- FALSE` to skip the join and emit permit-keyed rows only.

## Description of program

1. **STEP 0** — verifies `INPUT_PATH` exists, optionally building the missing
   pipeline stages (newest missing stage onwards, never the whole chain).
2. **STEP 1** — reads the needed columns as character and *asserts* step 3's
   upstream restrictions actually hold.
3. **STEP 2** — applies this script's own scope filters (`EXO` external outfalls,
   EPA's monthly-average statistical bases minus `EXCLUDE_STAT_BASES`,
   `VALUE_TYPES`), parses dates, derives the data's own fiscal year and clips to
   that window.
4. **STEP 3** — reporting-period handling (`RESTRICT_MONTHLY_ONLY`).
5. **STEP 4** — collapses violation fan-out to one row per `ROW_KEY` (after
   asserting nothing but `VIOLATION_COLS` differs), and sets `FLAG_MULTI_LIMIT_ID`.
6. **STEP 5** — attaches `FACILITY_ID` and `YEAR`/`MONTH`, trims to output columns.
7. **STEP 6** — verification `stopifnot()`s (including `ROW_KEY` uniqueness), then writes.
8. **STEP 7** — the run log: filter funnel, coverage, `FLAG_MULTI_LIMIT_ID`
   breakdown, value types, statistical bases, reporting periods, measurement
   completeness, data-quality counts, compliance.

## Decisions and Assumptions

The script's own header carries the authoritative, numbered list (ASSUMPTIONS
1–10) with the FY2017 counts attached to each. In brief:

1. **The input is already partly restricted** — and that is asserted, not assumed.
2. **Both `1` and `EG` are Effluent Gross**; accepting only `1` would silently
   discard 1,101 FY2017 rows and two permits entirely.
3. **"Outfall" means external outfall (`EXO`)**, and outfall identity is the
   *pair* (permit, `PERM_FEATURE_NMBR`) — 199 of 457 distinct FY2017 outfall
   numbers occur under more than one permit.
4. **Monthly average = every base EPA flags as one** (`STATISTICAL_BASE_MONTHLY_AVG
   == 'A'`, 12 codes incl. `DB` Daily Average and the 30-day codes), read from
   `REF_STATISTICAL_BASE.csv`. `MK` alone would miss 660 of 5,223 FY2017
   permits (mostly `3C` reporters). Drop codes with `EXCLUDE_STAT_BASES`.
5. **Statistical base and reporting period are independent** — the base is the
   statistic, `NMBR_OF_REPORT` is how many months the row covers. Multi-month
   rows are kept by default (FY2017: 2,406 rows, 241 permits; FY2024: 2,274
   rows, 238 permits).
6. **One row per `ROW_KEY`**: permit × outfall × period end × `VALUE_TYPE_CODE` ×
   `LIMIT_SET_ID` × `STATISTICAL_BASE_CODE` × `MONITORING_LOCATION_CODE` ×
   `LIMIT_ID`, asserted. Multiple limit sets are kept; nothing is tie-broken.
   (a) A value with several violations arrives as several rows; they are
   collapsed with `VIOLATION_COLS` joined by `;` (FY2017: 67 values, all
   `D90;E90`). (b) Two `LIMIT_ID`s in one limit set for the same statistic,
   slot, location and month are both kept and flagged `FLAG_MULTI_LIMIT_ID`
   (FY2017: 21 cells, 3 permits; 18 are possible duplicates, 3 conflict).
   `VERSION_NMBR` is not used: EPA defines it as the permit version (0 =
   current, 1 = oldest), not a resubmission counter.
7. **Values are copied verbatim** — every column read and written as character,
   so no number is reparsed or rounded. Compare `*_STANDARD_UNITS`, never the
   permit-specific `*_NMBR` fields.
8. **`EXCEEDENCE_PCT` carries a sentinel** (≥ 99999) — left as reported, counted.
9. **Nothing is corrected, only reported** — negatives, censored `<` rows and
   rows blank on both value and NODI code pass through and are counted.
10. **Prerequisites can be built automatically, stage by stage.**

## Output columns

23 columns with the default `VIOLATION_COLS`, in this order. `FACILITY_ID` is
constructed (above); `YEAR`/`MONTH` are derived from `MONITORING_PERIOD_END_DATE`;
`FLAG_MULTI_LIMIT_ID` is derived; everything else is EPA's own column, copied
verbatim as character except that collapsed rows hold `;`-joined violation fields.

| # | Column | Source |
|---|---|---|
| 1 | `FACILITY_ID` | constructed — see above (omitted if `ADD_FACILITY_ID = FALSE`) |
| 2–3 | `EXTERNAL_PERMIT_NMBR`, `PERM_FEATURE_NMBR` | EPA — **the outfall key is both together** |
| 4–5 | `YEAR`, `MONTH` | derived from `MONITORING_PERIOD_END_DATE` |
| 6 | `MONITORING_PERIOD_END_DATE` | EPA, verbatim string |
| 7–10 | `PERM_FEATURE_TYPE_CODE`, `PARAMETER_CODE`, `MONITORING_LOCATION_CODE`, `STATISTICAL_BASE_CODE` | EPA — scope; the last two are also row-key parts |
| 11–14 | `VALUE_TYPE_CODE`, `LIMIT_SET_DESIGNATOR`, `LIMIT_SET_ID`, `LIMIT_ID` | EPA — grain + limit set. Within a month designator and `LIMIT_SET_ID` identify the same limit set; a permit modification keeps the designator and issues a new ID. |
| 15–19 | `LIMIT_VALUE_STANDARD_UNITS`, `DMR_VALUE_STANDARD_UNITS`, `STANDARD_UNIT_DESC`, `DMR_VALUE_QUALIFIER_CODE`, `NODI_CODE` | EPA — measurement |
| 20 | `EXCEEDENCE_PCT` | EPA — compliance |
| 21 | `VIOLATION_CODE` (+ any other `VIOLATION_COLS`) | EPA — compliance; `D90;E90` when one value carried two violations |
| 22 | `NMBR_OF_REPORT` | EPA — reporting-period integrity |
| 23 | `FLAG_MULTI_LIMIT_ID` | derived — `TRUE` if the limit-set cell has >1 `LIMIT_ID`; summing across them may double-count |

### Columns read or derived but deliberately NOT written

| Column | Why it is not in the output |
|---|---|
| `LIMIT_VALUE_QUALIFIER_CODE` (`INTERNAL_COLS`) | read for the run log's floor-limit check only. Add to `KEEP_COLS` to retain. |
| `NPDES_VIOLATION_ID`, `RNC_DETECTION_CODE`, `RNC_DETECTION_DATE`, `RNC_RESOLUTION_CODE`, `RNC_RESOLUTION_DATE` | not carried by default (2026-10-12 decision). Add any to `VIOLATION_COLS` to carry it; it is `;`-joined in the same row order as `VIOLATION_CODE`. `NPDES_VIOLATION_ID` is the join key to `NPDES_VIOLATION_ENFORCEMENTS.csv`. |
| `VERSION_NMBR` | permit version, not a resubmission counter; within a month it is fixed by `LIMIT_SET_ID`. Removed 2026-10-12 with the step that misused it. |
| `period_end` (`INTERNAL_DERIVED`) | the parsed `Date` driving the fiscal-year clip, de-duplication, row ordering and the run log. The date is already stated twice — `MONITORING_PERIOD_END_DATE` verbatim and `YEAR`/`MONTH` for joining — and a third, re-formatted copy is how two date columns start disagreeing downstream. |
| `outfall_uid` | removed 2026-10-11. Was `paste(permit, "-", outfall)`. A composite string has to be split again before it can be joined on, and it reads as a single opaque id — exactly the error ASSUMPTION 3 warns about. Key on `EXTERNAL_PERMIT_NMBR` + `PERM_FEATURE_NMBR` instead. |

## Instructions to run

```bash
Rscript code/dmr/build_dmr_clean_panel.R
#   No arguments. Edit the CONFIG block (FY, INPUT_PATH, VALUE_TYPES, toggles)
#   and re-run. FY2017 with AUTO_RUN_PREREQS and step 3 present: ~1 min.
```

## Notes / edge cases

- **The output filename states the year of the data, not the `FY` toggle.** The
  fiscal year is read off the input's own `MONITORING_PERIOD_END_DATE`s
  (Oct–Dec roll into the next FY) and `FY` is checked against it; a mismatch stops
  with both years named, rather than clipping every row away and reporting an
  unhelpful "no rows survived".
- **`clean_dmr_<year>.csv` does not encode its toggles** (`VALUE_TYPES`,
  `EXCLUDE_STAT_BASES`, `RESTRICT_MONTHLY_ONLY`, `VIOLATION_COLS`). Two runs for
  the same year with different toggles write to the same path, and the second
  overwrites the first. The run log is the only record of which population a
  given file holds; keep the log with the file.
- **A multi-month row is dated to its period end.** With `RESTRICT_MONTHLY_ONLY =
  FALSE`, a quarterly reporter has one row per quarter; the other two months
  have no row and are not missing data.
- `validate_config()` runs immediately after the CONFIG block and rejects a
  malformed toggle by name — e.g. `VALUE_TYPES` that is not `"all"` or a vector of
  `C1/C2/C3/Q1/Q2`.
- **Read-only with respect to its input, non-destructive** (writes a new file),
  deterministic, safe to re-run.

## References

EPA ECHO ICIS-NPDES DMR Data Element Dictionary. <https://echo.epa.gov/node/206>.
Accessed `TODO`.

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>.
Accessed `TODO`.
