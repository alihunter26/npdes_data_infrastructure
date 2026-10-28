# README — `build_dmr_clean_panel.R`

*Builds a CLEANED DMR panel straight from the **raw** per-fiscal-year DMR zips.
Input: `data/raw/DMR/npdes_dmrs_fy<FY>.zip` (and `npdes_dmrs_prefy2009.zip`).
Output: one `data/processed/clean_dmr_<year>.csv` per fiscal year built, where
`<year>` is read off the data, never off a toggle.*

## Overview

Takes the raw DMR file for one or many fiscal years and reduces it to the
variables worth keeping, applying the whole restriction itself — majors under an
individual permit, TSS, Effluent Gross, external outfalls, monthly-average
statistical bases, the continental US. `YEARS` says which years to build: one, a
vector, or `"all"`. Every judgment call is a named toggle in the CONFIG block,
and the run log reports, per year, what each choice cost in rows, permits and
outfalls.

**It used to read a pre-filtered pipeline file** (`code/dmr/03_dmr_fy<FY>_00530_monloc1.csv`)
and assert that the `code/dmr/` stages had already applied the population, TSS
and Effluent-Gross filters. That changed on 2026-10-27 because the pipeline does
not scale to every year: its per-year intermediates run **~1.55 GB** (`01_`
~1.3 GB, `02_` ~145 MB, `03_` ~100 MB), so 15 years is **~23 GB** of files that
also sync to Dropbox, against ~23 GB free. Reading raw writes ~21 MB per year
instead, and does one pass where the pipeline did three.

The restriction itself is meant to be unchanged, and **that is the check to run
before trusting any of it**: build FY2017 from raw and compare it against the
file the pipeline route produced (159,544 rows × 25 columns). It should be
identical — same rows, columns, order and values — because the filters are the
same filters. Two intermediate counts in the run log are the same check at a
finer grain: applying `dropped, not Effluent Gross` should leave **354,091**
FY2017 rows, exactly what the old `03_` file held, and `dropped, not EXO` should
then be **15,179**, exactly what the pipeline run reported.

**Where things live.** This script is in `code/clean_dmr/` and no longer depends
on `code/dmr/` at all. That pipeline still exists and is still used by eleven
other scripts (including `code/03_panel_building/07_add_dmr.R`), but it is not an
input here. Every path is anchored to the repo root by `_paths.R`, so the script
runs from any working directory.

## Data Availability and Provenance Statements

**Every input is raw.** There are no derived inputs any more.

The DMR zips are the ECHO bulk "NPDES_DMRS_FY&lt;year&gt;" downloads, fetched by
`code/01_data_download/01_download_echo_bulk_files.R`. `ICIS_PERMITS.csv` defines
the permit population, `ICIS_FACILITIES.csv` supplies `FACILITY_ID` and
`STATE_CODE`, and the two reference tables in `data/raw/reference/` supply the
monthly-average flag and EPA's NODI text.

### Details on each data source

| File | Key fields used |
|---|---|
| `data/raw/DMR/npdes_dmrs_fy<year>.zip` → `NPDES_DMRS_FY<year>.csv` | the 20 `KEEP_COLS` + `VIOLATION_COLS` + 1 `INTERNAL_COLS` — 22 of the member's 57 columns |
| `data/raw/DMR/npdes_dmrs_prefy2009.zip` → `NPDES_DMRS_PREFY2009.csv` | same columns; holds FY1986–FY2008 in one member (see ASSUMPTION 13) |
| `data/raw/npdes_downloads/ICIS_PERMITS.csv` | `EXTERNAL_PERMIT_NMBR`, `PERMIT_TYPE_CODE`, `MAJOR_MINOR_STATUS_FLAG` (via `build_major_individual_permits()`) |
| `data/raw/npdes_downloads/ICIS_FACILITIES.csv` | `NPDES_ID`, `FACILITY_UIN` (via `build_facility_crosswalk()`); `NPDES_ID`, `STATE_CODE` (the continental-US filter) |
| `data/raw/reference/REF_STATISTICAL_BASE.csv` | `STATISTICAL_BASE_CODE`, `STATISTICAL_BASE_MONTHLY_AVG` (which bases count as a monthly average) |
| `data/raw/reference/REF_NODI.csv` | `NODI_CODE`, `NODI_DESC` (EPA's text for the no-data indicator) |

The raw member's **57 columns are identical across FY2009–FY2025** and identical
to what the old `03_` file carried, which is what made the switch a clean
substitution rather than a rewrite of `KEEP_COLS`.

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `data/raw/DMR/npdes_dmrs_fy<year>.zip` | input (**raw, immutable**) | one row per DMR value, all permits | ECHO download |
| `data/raw/DMR/npdes_dmrs_prefy2009.zip` | input (**raw, immutable**) | same, FY1986–FY2008 together | ECHO download |
| `data/raw/npdes_downloads/ICIS_PERMITS.csv` | input (**raw, immutable**) | one row per permit *version* | ECHO download |
| `data/raw/npdes_downloads/ICIS_FACILITIES.csv` | input (**raw, immutable**) | one row per NPDES_ID | ECHO download |
| `data/raw/reference/REF_STATISTICAL_BASE.csv` | input (**raw**, reference) | one row per statistical base code | manual download, see `data/raw/README.md` |
| `data/raw/reference/REF_NODI.csv` | input (**raw**, reference) | one row per NODI code (33) | transcribed from EPA, see `REF_NODI_PROVENANCE.md` |
| `data/processed/clean_dmr_<year>.csv` | **output**, one per FY | permit × outfall × month × value type × limit set × statistical base × monitoring location × `LIMIT_ID` (unique, asserted), continental US only | derived (git-ignored) |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `lubridate`, `DBI`, `duckdb` (1.5.0).
- **Controlled randomness:** none — no stochastic step, so no seed.
- **Why DuckDB.** The raw members are **3.7–9.0 GB** uncompressed per year and
  **22 GB** for `prefy2009`, on an 8 GB machine, so `fread()` is not an option.
  DuckDB streams the CSV out-of-core with a `DUCKDB_MEM_LIMIT` (default 5 GB) and
  spills to scratch. It applies **only** the permit-population join and the TSS
  filter; what returns to R is small (~160k rows for a normal year), and every
  other filter runs in R exactly as it always has.
- **Scratch.** Each source is extracted from its zip to a gzip temp
  (`tar -xOf … | gzip -1`, the same approach `filter_dmr_major_individual.R`
  uses, since DuckDB cannot read a zip member directly). That temp is
  **~0.5–1.3 GB** rather than the 3.7–22 GB a plain decompression would cost, and
  it is deleted after each source unless `KEEP_GZ = TRUE`. Location:
  `$CWA_SCRATCH` if set, else the session temp dir.
- **Runtime.** Extract + gzip dominates: roughly **10–20 min per normal year**
  and **25–35 min** for the 22 GB `prefy2009` member, so an all-years run is an
  overnight job. Reference data is loaded **once** for every year, not per year —
  without that, the 190 MB `ICIS_FACILITIES.csv` would be read twice per year.
- `ICIS_FACILITIES.csv` is still read **twice per run** (once by
  `build_facility_crosswalk()` for `FACILITY_ID`, once directly for
  `STATE_CODE`). Deliberate: folding `STATE_CODE` into the shared helper would
  change a function scripts 02/04/05/06 also call, and re-implementing the
  helper's `FACILITY_UIN`-else-`NPDES_ID` rule here would put that rule in two
  places.
- **Disk written:** ~21 MB per normal fiscal year. Pre-2009 years are much
  smaller (see ASSUMPTION 13).

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

In the FY2017 output: 5,858 permits map to 5,831 facilities (27 sites hold more
than one permit), 0 rows fall back to `NPDES_ID`, and 0 rows fail to match — the run log
reports that last count as `Rows with no facility match` every run, and a non-zero
value there means permits in the DMR data are absent from `ICIS_FACILITIES.csv`.
(Before the continental-US filter of ASSUMPTION 11 these were 5,969 permits and
5,942 facilities; the 111 dropped permits are listed by state below.)

Set `ADD_FACILITY_ID <- FALSE` to skip the join and emit permit-keyed rows only.

## Why `STATE_CODE` comes from `ICIS_FACILITIES`, not from the permit number

*Decisions settled 2026-10-27. Toggle: `RESTRICT_CONTINENTAL` (default `TRUE`).
Script-side authority: ASSUMPTION 11.*

**The DMR file has no geography at all.** None of the 57 columns in
`NPDES_DMRS_FY<year>.csv` is a state, county or coordinate — they are permit,
limit and measurement fields. So "continental US" is not a filter this script can
apply to its own input; the filter variable has to be **joined in**, and where it
comes from is a decision, not a detail.

### The decision: 48 states + DC, by facility location

| Decision | What was chosen | Why |
|---|---|---|
| **Which states count** | The 48 contiguous states **plus DC** — 49 codes, listed explicitly in `F_STATES` | Matches the filter in `code/03_panel_building/01_build_facility_month_panel_major_individual.R:280` ("48 continental US states + DC"), so this file and the facility-month panel it feeds cover the *same* geography. Dropping DC here would leave DC facilities in that panel with no DMR rows — indistinguishable from genuine non-reporting. |
| **Where state comes from** | `STATE_CODE` from raw `ICIS_FACILITIES.csv`, joined on `NPDES_ID = EXTERNAL_PERMIT_NMBR` | It is the facility's physical location, and it is the same field the facility-month panel filters on. |
| **Not** the `NPDES_ID` prefix | Rejected | The first two characters are the **issuing authority**, not a location. See the measurement below. |
| **Allowlist, not denylist** | `F_STATES` lists what to keep | ICIS `STATE_CODE` also holds `XX`, `MB`, `MW`, `UM`, `GM`, `GE` and blanks. A denylist of territories silently admits every code nobody thought of. |
| **Unknown / blank / unmatched** | **Dropped, and counted by code in the run log** | Honest to the file's name, with no silent loss: every dropped code is printed with its row and permit count each run. In FY2017, 0 permits fail to match ICIS. |
| **`STATE_CODE` is written to the output** | Yes | A filter whose variable is absent from the file it produced cannot be audited. It is also the natural key for state fixed effects or clustering downstream. |

### Why the permit prefix was rejected — measured, not assumed

Using `substr(EXTERNAL_PERMIT_NMBR, 1, 2)` looks equivalent and is not. In
FY2017 scope the two rules disagree on **4 permits / 1,032 rows**, and the
disagreement is systematic rather than noise:

| `NPDES_ID` prefix | ICIS `STATE_CODE` | rows | permits | prefix rule | location rule |
|---|---|---|---|---|---|
| `NN` | AZ | 1,008 | 3 | drops | **keeps** |
| `NN` | NM | 24 | 1 | drops | **keeps** |

`NN` is **Navajo Nation** — EPA-issued tribal permits whose facilities are in
Arizona and New Mexico, inside the lower 48. A prefix rule drops every one of
them. Across all 1,212,522 ICIS permits the same mechanism misroutes `01`→NH
(268 permits), `03`→DC (54 — so "keep DC" and "use the prefix" partly cancel
each other), `GM`→TX/LA (579, Gulf of Mexico) and `NN` (98). None of those
others land in FY2017's TSS scope, but this script runs once per fiscal year.

Both rules drop the seven non-continental codes **identically**, so those four
tribal permits are the entire difference between them.

### What it costs in FY2017

2,504 rows / 111 permits, every one counted in the run log:

| `STATE_CODE` | rows | permits |
|---|---|---|
| PR | 1,038 | 49 |
| AK | 848 | 33 |
| HI | 244 | 12 |
| VI | 125 | 6 |
| AS | 108 | 5 |
| GU | 91 | 4 |
| MP | 50 | 2 |
| **total** | **2,504** | **111** |

All 49 kept codes have in-scope FY2017 rows, so nothing in `F_STATES` is dead
weight. Permits fall 5,969 → 5,858 and facilities 5,942 → 5,831.

## Where `NODI_DESC` comes from

*Decisions settled 2026-10-27. Toggle: `ADD_NODI_DESC` (default `TRUE`).
Script-side authority: ASSUMPTION 12.*

`NODI_DESC` is EPA's own text for `NODI_CODE`, joined from
`data/raw/reference/REF_NODI.csv` and written immediately to the right of the
code it explains. That file is a **pure transcription** of EPA's ICIS-NPDES DMR
Data Element Dictionary — 33 codes, verified against both the dictionary HTML
and the Region 6 PDF, with nothing authored by us. See
[`REF_NODI_PROVENANCE.md`](../../data/raw/reference/REF_NODI_PROVENANCE.md).

| Decision | What was chosen | Why |
|---|---|---|
| **Source** | `REF_NODI.csv`, verbatim | It is already in the repo, already verified, and already the reference `07_add_dmr.R` validates against. Typing descriptions into this script would create a second, drifting copy. |
| **Blank code** | Blank description, never invented text | 76.3% of written FY2017 rows report a value and carry no NODI at all. "No NODI reported" would be our words in a column that otherwise holds EPA's. |
| **Unknown code** | **Stops the run** | Same rule as `07_add_dmr.R:604-611`. Writing a blank description for a code EPA documents would read as "no NODI reported" — a silent corruption. All 21 non-blank codes in the FY2017 output are in the reference. |
| **`EPA_CODE_STATUS`** | **Not carried** | Only the description was wanted, and the status column invites a specific error: it is a *code-lifecycle* flag (can this code still be filed?) and says **nothing** about whether an outfall discharged. `2` "Operation Shutdown" is Active while the plant is by definition not running; `5` Frozen and `V` Weather are retired while it was. `REF_NODI_PROVENANCE.md` warns against exactly this reading. |
| **Interpretation** | None — readability only | No logic in this script reads `NODI_DESC`; `NODI_CODE` remains the key. The one place a NODI code is *interpreted* is `07_add_dmr.R`, which reads code `C` alone, in the script, where the decision is visible as code. |

In the FY2017 output 37,751 rows (23.7%) carry a NODI code, spanning 21 of the
33 documented codes; `C` "No Discharge" is 29,874 of them.

## Where the permit population comes from

`build_major_individual_permits()` in
[`../02_cleaning/cleaning_helpers.R`](../02_cleaning/cleaning_helpers.R) reads
raw `ICIS_PERMITS.csv` and applies two rules:

- **INDIVIDUAL** — `PERMIT_TYPE_CODE == "NPD"`.
- **EVER MAJOR** — `MAJOR_MINOR_STATUS_FLAG == "M"` in **at least one** version
  row of the permit, not "major in every version". A permit appears once per
  version in ICIS, and a facility that was ever big enough to be a major stays
  in the population.

Result: **7,804 eligible permits**.

This is the same function `code/dmr/filter_dmr_major_individual.R` calls. It
lived inline in that script until 2026-10-27; when this script started reading
raw DMR files it needed the identical set, and two copies of the project's core
population definition is exactly the kind of thing that drifts apart. Both now
call one function, verified to produce identical vectors before the switch.

**Vintage caveat.** `ICIS_PERMITS.csv` is a *current-state* extract, not a
per-fiscal-year snapshot, so the eligible set is the same whichever year's DMR
file it is applied to. Convenient, but it also means a 2026 population
definition is applied to historical rows, and permits terminated before ICIS was
populated are simply absent — which matters for pre-2009 data (ASSUMPTION 13).

## Description of program

1. **STEP 0** — resolves `YEARS` into **source zips**, grouping requested years
   by source so each zip is read once, then **pre-flights** every zip with
   `unzip -l`. A missing or truncated zip is reported in the first second and
   skipped; the rest still run.
2. **STEP 1** — loads all reference data **once for every year**: the eligible
   permit set, `REF_STATISTICAL_BASE`, `REF_NODI`, the ICIS state table and the
   facility crosswalk.
3. **STEP 2, per source** — extracts the CSV member to a gzip temp on scratch,
   then has **DuckDB** (out-of-core) return the rows matching the eligible
   permits and `PARAMETER_CODE 00530`, projecting 22 of the 57 columns. Dates are
   parsed, the fiscal year of each row derived, and the result **split by FY**.
4. **STEPS 3–7, per fiscal year** — on each FY group, in order: Effluent Gross,
   `EXO`, monthly-average statistical bases minus `EXCLUDE_STAT_BASES`,
   `VALUE_TYPES`, then the **continental-US filter** (joining `STATE_CODE` and
   counting every dropped code); reporting-period handling
   (`RESTRICT_MONTHLY_ONLY`); the violation fan-out collapse to one row per
   `ROW_KEY` and `FLAG_MULTI_LIMIT_ID`; `FACILITY_ID`, `YEAR`/`MONTH` and
   `NODI_DESC`; the trim to output columns and the `SORT_KEY` sort; the
   verification `stopifnot()`s; the write; and that year's run log.
5. **Summary** — lists every year built and every year skipped with its reason,
   and **exits non-zero** if anything was skipped.

A per-FY zip yields one FY group; `prefy2009` yields about 23. That is the whole
reason `prefy2009` needs no special-casing — it is the same four steps, just
more groups (ASSUMPTION 10, 13).

### Two ordering choices that affect the numbers

**The continental-US filter runs before the fan-out collapse**, so the drop
appears in the funnel beside the other scope restrictions and the fan-out and
`FLAG_MULTI_LIMIT_ID` counts describe the population actually written. One
visible consequence: in FY2017 the collapse falls from 67 keys to 56, because 11
of the multi-violation values were at territory facilities. That is why the
written row count is 162,037 − 2,504 **+ 11** = 159,544, not 162,037 − 2,504.

**The funnel's top line changed meaning** with the move to raw. It used to be
"rows read" from the `03_` file (354,091 for FY2017, already population + TSS +
Effluent Gross). It is now the rows DuckDB returned for the whole member
(population + TSS only), followed by how many of those belong to this fiscal
year, and then a new `dropped, not Effluent Gross` line. Applying that line to
FY2017 brings the count back to 354,091 — which doubles as a check that the raw
path reproduces the pipeline's population.

The continental-US filter runs in STEP 2, **before** the STEP 4 collapse, on
purpose: the drop then appears in the funnel beside the other scope
restrictions, and the fan-out and `FLAG_MULTI_LIMIT_ID` counts describe the
population actually written rather than one that still includes territories.
One visible consequence — in FY2017 the fan-out collapse falls from 67 keys to
56, because 11 of the multi-violation values were in dropped territories. This is
why the written row count is 162,037 − 2,504 **+ 11** = 159,544, not
162,037 − 2,504.

## Decisions and Assumptions

**This section is the authoritative text.** The script header carries the same
fourteen as one-line reminders and points here; read these before using any
results. Counts are FY2017 unless stated.

### 1. The script applies the whole restriction itself, from raw

Until 2026-10-27 this read `code/dmr/03_dmr_fy<FY>_00530_monloc1.csv` and
*asserted* that the `code/dmr/` pipeline had already applied the population, TSS
and Effluent-Gross filters. It now reads the raw zip and applies all of them
here, for the disk and pass-count reasons in the Overview.

The filters sit in two places, one pass each:

- **DuckDB** — the only part that sees the whole raw file: eligible permits +
  `PARAMETER_CODE 00530`.
- **R**, on what comes back: Effluent Gross, `EXO`, statistical base, value type,
  continental US, fiscal-year window — each counted in the funnel, in the same
  order as before.

**The population rule is shared, not copied:** `build_major_individual_permits()`
in `code/02_cleaning/cleaning_helpers.R`, the same function
`code/dmr/filter_dmr_major_individual.R` calls (7,804 permits). See "Where the
permit population comes from" above.

Equivalence to the old pipeline-sourced output is **a check to run, not an
assumption** — see the Overview for the three numbers to compare.

### 2. Both `1` and `EG` are Effluent Gross

Per EPA's [ICIS-NPDES DMR Data Element Dictionary](https://echo.epa.gov/node/206)
the monitoring location code has three Effluent Gross variants: `1`, `EG`, and
`Y` (Effluent Gross — Supplementary). This script keeps `1` and `EG`. Accepting
only `1` would silently discard the 1,101 FY2017 `EG` rows and delete two permits
entirely. `Y` is excluded and verified harmless for this scope — its one in-scope
FY2017 row duplicates a primary measurement.

### 3. "Outfall" means external outfall (`EXO`)

Monitoring location 1 still admits internal outfalls (`INO`) and other feature
types; counting those would double-count the same water on its way out.

**Outfall identity is the pair (permit, `PERM_FEATURE_NMBR`), never the number
alone** — 199 of 457 distinct FY2017 outfall numbers occur under more than one
permit, so outfall `001` is a different physical outfall at different permits.
The output carries that pair as its two own columns (`EXTERNAL_PERMIT_NMBR`,
`PERM_FEATURE_NMBR`); **key on both**. No pasted-together `outfall_uid` column is
written — a composite string has to be split again to be joined on, and it reads
as a single opaque id, which is exactly the mistake this assumption warns about.

### 4. Monthly average = every statistical base EPA flags as one

The codes with `STATISTICAL_BASE_MONTHLY_AVG == 'A'` in
`data/raw/reference/REF_STATISTICAL_BASE.csv` — 12 codes, read from the file, not
typed into the script. That includes `DB` (Daily Average) and the 30-day codes
(`3C` etc.), not just `MK`.

`STATISTICAL_BASE_CODE` is carried and is part of the row key, so any narrower
definition is a filter on the output. In FY2017, **660 of 5,223 permits** with a
monthly-average-flagged base other than `DB` report no `MK` row at all (mostly
`3C`), so `MK` alone is not a neutral choice. To drop a code, list it in
`EXCLUDE_STAT_BASES`.

### 5. Statistical base and reporting period are independent

`MK` says the *statistic* is a monthly average; `NMBR_OF_REPORT` says how many
*months* the row covers. EPA: "The number of months in the monitoring period
covered by the DMR (e.g., monthly = 1, quarterly = 3, semi-annually = 6)."

A quarterly row with `MK` is a monthly average computed over 3 months, dated to
the window's end. Such rows are **kept by default**
(`RESTRICT_MONTHLY_ONLY = FALSE`): a quarterly reporter has one row per quarter,
and the two months without a row are not missing data. FY2017: 2,400 rows across
239 permits (FY2024: 2,274 rows, 238 permits).

`NMBR_OF_SUBMISSION` is deliberately **not** carried: it is the *filing* cadence,
not the measurement window, and filtering on it would discard 4,019 genuine
monthly observations that happen to be filed in quarterly batches.

### 6. One row per `ROW_KEY`

`EXTERNAL_PERMIT_NMBR` × `PERM_FEATURE_NMBR` × `MONITORING_PERIOD_END_DATE` ×
`VALUE_TYPE_CODE` × `LIMIT_SET_ID` × `STATISTICAL_BASE_CODE` ×
`MONITORING_LOCATION_CODE` × `LIMIT_ID` — asserted unique before writing, per
fiscal year.

Every part is needed in FY2017: a limit set can report one statistic in two
concentration slots (C2 with C1 or C3), under both `1` and `EG`, or under two
`LIMIT_ID`s. **Multiple limit sets are kept**, never collapsed or tie-broken.
`LIMIT_SET_DESIGNATOR` is carried beside `LIMIT_SET_ID`: within one month they
identify the same limit set, but a permit modification or reissuance keeps the
designator and issues a new `LIMIT_SET_ID` — 775 of 7,264 FY2017
permit-outfall-designators switch ID mid-year, every switch coinciding with a
`VERSION_NMBR` change.

Two things are not unique at the source and are handled explicitly:

**(a) Violation fan-out.** EPA writes one row per violation, so a value carrying
two violations appears twice, identical except for the violation fields. Those
rows are collapsed to one, with `VIOLATION_COLS` joined by `;` in a common row
order; the script asserts every other column agrees first, so the collapse cannot
lose a value. FY2017: **56 keys**, all `D90` + `E90` — 56 and not 67 because the
continental-US filter runs first and 11 of these values were at territory
facilities.

**(b) Two `LIMIT_ID`s in one limit set** for the same statistic, slot, location
and month. FY2017: 21 cells in 3 permits; 18 carry the same value and limit under
both IDs (a possible duplicate), 3 conflict. Both rows are **kept** and marked
`FLAG_MULTI_LIMIT_ID = TRUE`. Summing across `LIMIT_ID` within a flagged cell may
double-count.

`VERSION_NMBR` is not used. EPA: "The current permit is VERSION_NMBR = 0. The
oldest permit version is VERSION_NMBR = 1" — it is the permit version, not a DMR
resubmission counter, and "highest" is not "latest".

### 7. Values are copied verbatim

Every column is read **and** written as character — DuckDB reads the raw CSV with
`all_varchar=true` — so no number is reparsed, rounded or reformatted. Numeric
casting is left to whoever uses the file.

The only written columns not read from the input are `FACILITY_ID`,
`YEAR`/`MONTH`, `STATE_CODE`, `NODI_DESC` and `FLAG_MULTI_LIMIT_ID` — all derived
or joined, none a restatement of a reported number.

Always compare the `*_STANDARD_UNITS` fields, never the permit-specific `*_NMBR`
fields: permits write TSS limits in g/d, kg/d, lb/d, lb/kgal, lb/qtr, mg/L and
ug/L, and only the standard-units columns are comparable across outfalls.
`STANDARD_UNIT_DESC` is carried so every row states its own unit (kg/d for the
mass value types, mg/L for concentration).

### 8. `EXCEEDENCE_PCT` carries a sentinel

5 FY2017 written rows hold 99999 or more, which is a placeholder rather than a
real percentage. They are left exactly as reported and counted in the run log —
**filter them before averaging**.

### 9. Nothing is corrected, only reported

Negative TSS values, censored (`<`) rows whose number is a detection limit rather
than a measurement, and rows blank on both value and NODI code all pass through
unchanged. The run log counts each. What to do about them is a research decision.

### 10. One pass per source zip, and years are batched by source

A "source" is one zip. Processing it is always the same four steps — extract the
CSV member to a gzip temp on scratch, filter it in DuckDB out-of-core, split what
comes back by fiscal year, then run the per-year cleaning on each group. A per-FY
zip yields **one** group; `prefy2009` yields many (assumption 13), so it is not a
special case, just more groups.

Requested years are **grouped by source so each zip is read once** — asking for
`2005:2008` must not stream the 22 GB `prefy2009` member four times. The gzip
temp (~0.5–1.3 GB, versus 3.7–22 GB uncompressed) is deleted after each source
unless `KEEP_GZ`. DuckDB cannot read a zip member directly, which is why the
extract step exists; it is the same `tar | gzip -1` approach
`code/dmr/filter_dmr_major_individual.R` uses.

**Nothing is ever deleted or overwritten in `data/raw/`.** The script reads the
zips and writes only `data/processed/clean_dmr_<FY>.csv`.

### 11. Continental US = the 48 states + DC, by facility location

`RESTRICT_CONTINENTAL` keeps only rows whose facility sits in one of the 49 codes
in `F_STATES`; Alaska, Hawaii and the territories are dropped. The DMR file
carries no geography, so `STATE_CODE` is joined from raw `ICIS_FACILITIES.csv`
and written to the output. **Not** the `NPDES_ID` prefix, which is the issuing
authority rather than a location — in FY2017 that would drop 4 Navajo Nation
permits (1,032 rows) sited in AZ/NM. `F_STATES` is an allowlist; anything outside
it, including a blank state or an unmatched permit, is dropped and counted by code
(FY2017: 2,504 rows, 111 permits).

Full treatment, with the measured disagreement and the per-state costs:
["Why `STATE_CODE` comes from `ICIS_FACILITIES`"](#why-state_code-comes-from-icis_facilities-not-from-the-permit-number) above.

### 12. `NODI_DESC` is EPA's own text, carried for readability only

Joined from `REF_NODI.csv`, blank where the code is blank; an undocumented code
stops that year rather than being written with a blank description. `NODI_CODE`
stays the key and the only field any logic reads. `EPA_CODE_STATUS` is
deliberately not carried — it is a code-lifecycle flag and says nothing about
whether an outfall discharged.

Full treatment: ["Where `NODI_DESC` comes from"](#where-nodi_desc-comes-from) above.

### 13. Pre-2009 coverage is thin, and the population rule is anachronistic

`npdes_dmrs_prefy2009.zip` is not one fiscal year: it holds **FY1986–FY2008** in a
single 22 GB member, so one source produces many output files.

Two things make early years not comparable to later ones:

- **The population and geography come from today's ICIS.** `ICIS_PERMITS.csv` is
  a current-state extract, so a 2026 population definition is applied to 1986
  rows, and permits terminated before ICIS was populated are absent entirely. The
  same holds for `STATE_CODE` and `FACILITY_ID` (assumption 11).
- **The raw row counts are reporting-regime artifacts, not discharge activity.** A
  300k-row sample of the member holds ~140 rows for FY1986 and ~132 for FY1987,
  rising to ~24k for FY2008 — and that is *before* the population, TSS and
  Effluent-Gross filters, which empty some years completely.

A fiscal year that filters to zero rows is **reported as a skip, not an error**,
and no file is written for it. Do not compare across the FY2009 boundary, or
between early years, without accounting for all of this.

### 14. A fiscal year must come from exactly one source zip

Sampling found no FY2009 rows in `prefy2009` and no pre-2009 rows in `fy2009`,
but only ~1% of the 22 GB member was read, so the script checks rather than
trusts: if two sources would write the same `clean_dmr_<FY>.csv` in one run it
**stops** and names both.

Separately, a per-FY zip is held to its own year — rows in
`npdes_dmrs_fy2017.zip` dated outside FY2017 are counted as out-of-window and
dropped, exactly as before, rather than silently creating a second year's file
out of a handful of stray rows. Only `prefy2009` is allowed to emit many years.

## Which years get built

`YEARS` takes a single fiscal year, a vector, a range, or `"all"`:

```r
YEARS <- 2017L            # the default -- one year
YEARS <- c(2017L, 2019L)
YEARS <- 2009:2012
YEARS <- "all"            # every zip in data/raw/DMR/
```

**It defaults to one year, not `"all"`**, so running the script unintentionally
costs a minute rather than a night. `"all"` discovers the zips on disk rather
than using a hardcoded list, so a newly downloaded FY2026 file is picked up
without editing anything — and it currently means **up to 40 fiscal years**
(FY1986–FY2008 out of `prefy2009`, plus FY2009–FY2025).

### What happens when a year can't be built

Nothing stops the run. Each source and each fiscal year is isolated, the reason
is recorded, and the closing summary names every skip — then the script **exits
non-zero** so a wrapper or cron job notices:

```
=== all-years summary: 16 source(s), 36 fiscal year(s) built, 5 skipped ===
-- SKIPPED --
     FY   source      reason
   1986   prefy2009   0 rows after the scope filters
   2018   fy2018      source zip unreadable (truncated download: no end-of-central-directory record)
   2020   fy2020      source zip unreadable (truncated download: no end-of-central-directory record)
```

**Two zips are currently unusable.** `npdes_dmrs_fy2018.zip` (13 MB) and
`npdes_dmrs_fy2020.zip` (304 MB) are truncated downloads with no
end-of-central-directory record — neighbouring years are ~550 MB. The download
script explains how they got there: its DMR URLs are an *inferred* pattern and it
"log[s] a failure and let[s] the script continue" rather than hard-failing. So
`"all"` currently means **15 usable per-FY years**, not 17, until those two are
re-fetched with `code/01_data_download/01_download_echo_bulk_files.R`.

## Output columns

25 columns with the default `VIOLATION_COLS`, in this order. `FACILITY_ID` and
`STATE_CODE` are constructed (above); `YEAR`/`MONTH` are derived from
`MONITORING_PERIOD_END_DATE`; `NODI_DESC` is EPA reference text joined on
`NODI_CODE`; `FLAG_MULTI_LIMIT_ID` is derived; everything else is EPA's own
column, copied verbatim as character except that collapsed rows hold
`;`-joined violation fields.

**Row order is part of what the file promises** and is asserted before writing
(`SORT_KEY`): `FACILITY_ID`, `YEAR`, `MONTH`, then period-end date, then the rest
of the row key (permit, outfall, value type, statistical base, monitoring
location, limit-set designator, `LIMIT_SET_ID`, `LIMIT_ID`). Facility first
because the file is read and merged facility-by-facility; the period-end date
breaks ties inside a `YEAR` × `MONTH`, since one month can hold more than one
period-end day; the remaining key parts make the order **total**, so the same
input always writes the same rows in the same sequence. With
`ADD_FACILITY_ID = FALSE` the first key is `EXTERNAL_PERMIT_NMBR` instead.

| # | Column | Source |
|---|---|---|
| 1 | `FACILITY_ID` | constructed — see above (omitted if `ADD_FACILITY_ID = FALSE`) |
| 2–3 | `EXTERNAL_PERMIT_NMBR`, `PERM_FEATURE_NMBR` | EPA — **the outfall key is both together** |
| 4 | `STATE_CODE` | constructed — joined from raw `ICIS_FACILITIES.csv`; the filter variable, written so the filter can be audited (omitted if `RESTRICT_CONTINENTAL = FALSE`) |
| 5–6 | `YEAR`, `MONTH` | derived from `MONITORING_PERIOD_END_DATE` |
| 7 | `MONITORING_PERIOD_END_DATE` | EPA, verbatim string |
| 8–11 | `PERM_FEATURE_TYPE_CODE`, `PARAMETER_CODE`, `MONITORING_LOCATION_CODE`, `STATISTICAL_BASE_CODE` | EPA — scope; the last two are also row-key parts |
| 12–15 | `VALUE_TYPE_CODE`, `LIMIT_SET_DESIGNATOR`, `LIMIT_SET_ID`, `LIMIT_ID` | EPA — grain + limit set. Within a month designator and `LIMIT_SET_ID` identify the same limit set; a permit modification keeps the designator and issues a new ID. |
| 16–20 | `LIMIT_VALUE_STANDARD_UNITS`, `DMR_VALUE_STANDARD_UNITS`, `STANDARD_UNIT_DESC`, `DMR_VALUE_QUALIFIER_CODE`, `NODI_CODE` | EPA — measurement |
| 21 | `NODI_DESC` | EPA reference text, joined on `NODI_CODE` from `REF_NODI.csv`; blank where the code is blank (omitted if `ADD_NODI_DESC = FALSE`) |
| 22 | `EXCEEDENCE_PCT` | EPA — compliance |
| 23 | `VIOLATION_CODE` (+ any other `VIOLATION_COLS`) | EPA — compliance; `D90;E90` when one value carried two violations |
| 24 | `NMBR_OF_REPORT` | EPA — reporting-period integrity |
| 25 | `FLAG_MULTI_LIMIT_ID` | derived — `TRUE` if the limit-set cell has >1 `LIMIT_ID`; summing across them may double-count |

### Columns read or derived but deliberately NOT written

| Column | Why it is not in the output |
|---|---|
| `LIMIT_VALUE_QUALIFIER_CODE` (`INTERNAL_COLS`) | read for the run log's floor-limit check only. Add to `KEEP_COLS` to retain. |
| `EPA_CODE_STATUS` (from `REF_NODI.csv`) | a code-lifecycle flag, not a fact about the outfall — it says nothing about whether anything discharged, and its `Active`/`Inactive` vocabulary collides with words that mean something else here. See `REF_NODI_PROVENANCE.md`. |
| `FACILITY_UIN`, and every other `ICIS_FACILITIES` field | only `NPDES_ID`, `FACILITY_UIN` (inside the crosswalk helper) and `STATE_CODE` are read. Facility name, address and coordinates belong to the facility-month panel, not to a DMR-grain file that would repeat them on every row. |
| `NPDES_VIOLATION_ID`, `RNC_DETECTION_CODE`, `RNC_DETECTION_DATE`, `RNC_RESOLUTION_CODE`, `RNC_RESOLUTION_DATE` | not carried by default (2026-10-12 decision). Add any to `VIOLATION_COLS` to carry it; it is `;`-joined in the same row order as `VIOLATION_CODE`. `NPDES_VIOLATION_ID` is the join key to `NPDES_VIOLATION_ENFORCEMENTS.csv`. |
| `VERSION_NMBR` | permit version, not a resubmission counter; within a month it is fixed by `LIMIT_SET_ID`. Removed 2026-10-12 with the step that misused it. |
| `period_end` (`INTERNAL_DERIVED`) | the parsed `Date` driving the fiscal-year clip, de-duplication, row ordering and the run log. The date is already stated twice — `MONITORING_PERIOD_END_DATE` verbatim and `YEAR`/`MONTH` for joining — and a third, re-formatted copy is how two date columns start disagreeing downstream. |
| `outfall_uid` | removed 2026-10-11. Was `paste(permit, "-", outfall)`. A composite string has to be split again before it can be joined on, and it reads as a single opaque id — exactly the error ASSUMPTION 3 warns about. Key on `EXTERNAL_PERMIT_NMBR` + `PERM_FEATURE_NMBR` instead. |

## Instructions to run

```bash
# The YEARS toggle in the CONFIG block (default 2017L):
Rscript code/clean_dmr/build_dmr_clean_panel.R
```

`YEARS` can also be given on the command line, which overrides the toggle — so a
batch needs no file edit:

```bash
Rscript code/clean_dmr/build_dmr_clean_panel.R 2017
```

```bash
Rscript code/clean_dmr/build_dmr_clean_panel.R 2016 2017 2019
```

```bash
Rscript code/clean_dmr/build_dmr_clean_panel.R all
```

Runs from any working directory — paths anchor to the repo root via `_paths.R`.
Expect ~10–20 min per normal year and ~25–35 min for `prefy2009`, so `all` is an
overnight job; run it in the background and keep the log.

## Notes / edge cases

- **Each output filename states the year of the data, not a toggle.** The fiscal
  year is derived from each row's own `MONITORING_PERIOD_END_DATE` (Oct–Dec roll
  into the next FY) and is what names the file, so a file cannot misreport its
  contents. The script asserts this before writing: every row in
  `clean_dmr_<FY>.csv` has `fy_of(period_end) == <FY>`.
- **A truncated zip is caught in the first second, not hours in.** Pre-flight
  runs `unzip -l` on every needed zip before any work starts. `tar` will happily
  begin streaming a truncated archive — FY2018's local header still claims an
  8.59 GB member — which is why the check uses `unzip` rather than `tar`.
- **The scratch gzip temp is ~0.5–1.3 GB per source** and is deleted after that
  source unless `KEEP_GZ = TRUE`. `REUSE_GZ = TRUE` (the default) reuses an
  existing temp instead of re-extracting, which makes a re-run of the same year
  much faster if you kept it. Scratch goes to `$CWA_SCRATCH` if set, else the
  session temp dir — on this machine that shares the same physical disk as the
  output, which had ~23 GB free.
- **`clean_dmr_<year>.csv` does not encode its toggles** (`VALUE_TYPES`,
  `EXCLUDE_STAT_BASES`, `RESTRICT_MONTHLY_ONLY`, `VIOLATION_COLS`,
  `RESTRICT_CONTINENTAL`, `ADD_NODI_DESC`). Two runs for the same year with
  different toggles write to the same path, and the second overwrites the first.
  The run log is the only record of which population a given file holds; keep the
  log with the file. `RESTRICT_CONTINENTAL` and `ADD_NODI_DESC` at least leave a
  visible trace — `STATE_CODE` and `NODI_DESC` are present only when they were on.
- **The output's geography is an ICIS snapshot, not a time-varying variable.**
  `STATE_CODE` is read from whatever `ICIS_FACILITIES.csv` vintage is on disk and
  is attached to every row of a permit regardless of month. Re-downloading ICIS
  can move a facility between states and so change panel membership, and a
  facility that relocated mid-period carries only its latest state. The filter
  is therefore reproducible from a *given* raw snapshot, not across snapshots.
- **A permit absent from `ICIS_FACILITIES.csv` is dropped by the state filter**,
  not kept with a missing state. FY2017 has none, and the run log prints the
  count as `<no ICIS match>` whenever it is non-zero. With
  `ADD_FACILITY_ID = TRUE` the same permits would also show up in
  `Rows with no facility match`.
- **A multi-month row is dated to its period end.** With `RESTRICT_MONTHLY_ONLY =
  FALSE`, a quarterly reporter has one row per quarter; the other two months
  have no row and are not missing data.
- `validate_config()` runs immediately after the CONFIG block and rejects a
  malformed toggle by name — a `YEARS` outside FY1986–FY2025 or with a repeat, a
  `VALUE_TYPES` that is not `"all"` or a vector of `C1/C2/C3/Q1/Q2`, an
  `F_STATES` entry that is not an upper-case two-character code, a non-logical
  toggle.
- **Read-only with respect to `data/raw/`, non-destructive** (writes new files in
  `data/processed/`), deterministic, safe to re-run.
- **Re-running overwrites only the years you asked for.** Years not in `YEARS`
  keep whatever `clean_dmr_<FY>.csv` is already on disk, which is convenient for
  rebuilding one year — and a trap if toggles changed in between, since the
  untouched files were built under the old ones (see the toggle note above).

## History

- **2026-10-27** — switched from the `code/dmr/` pipeline's `03_` file to the raw
  DMR zips, added the `YEARS` toggle and all-years mode, moved the population
  rule into `build_major_individual_permits()`, and retired `INPUT_PATH`,
  `AUTO_RUN_PREREQS` and the old STEP 0. Earlier the same day: the
  continental-US filter and `STATE_CODE` column (ASSUMPTION 11), the `NODI_DESC`
  column (ASSUMPTION 12), the facility → year → month sort order, and the move
  of this script from `code/dmr/` to `code/clean_dmr/`.
- **2026-10-12** — dropped `VERSION_NMBR` and the extra violation fields from the
  output; kept every limit set rather than tie-breaking.
- **2026-10-11** — removed the pasted-together `outfall_uid` column.

## References

EPA ECHO ICIS-NPDES DMR Data Element Dictionary. <https://echo.epa.gov/node/206>.
Accessed `TODO`.

EPA ECHO / ICIS-NPDES data downloads. <https://echo.epa.gov/tools/data-downloads>.
Accessed `TODO`.
