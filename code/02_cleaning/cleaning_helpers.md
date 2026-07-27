# README — `cleaning_helpers.R`

Shared function library for the facility-by-month panel pipeline
(`code/03_panel_building/01`–`06`, plus `use_operating_proxies.R`). Not a runnable
script — it only *defines* functions; nothing here reads or writes a file on its own.
See `code/02_cleaning/module_README.md` for how this folder as a whole is organized
(this file is one of two things in it; the other, `build_effluent_violations_npdes_
month_panel.R`, is an unrelated standalone script that just happens to live in the
same folder).

## Why this file exists

Before it was written, each of the six numbered panel-building scripts carried its own
copy-pasted version of the same few pieces of logic: reading a raw file safely,
matching a permit to its physical facility, and combining several candidate date
columns into one date. That duplication is a real maintenance risk — fix a bug in one
copy, forget the other five, and the six steps quietly start disagreeing with each
other. This file collects that logic in one place, so there is exactly one version of
each rule to read, test, and fix.

**What deliberately did *not* move here:** the research decisions — e.g. *which*
columns count as a permit's opening date, or what a missing closing date means — stay
inline in the script that makes that decision (mainly `01_build_facility_month_panel_
major_individual.R`), next to the comment that justifies it. This file only holds the
generic *mechanics* (how to combine date columns), never the domain-specific *choices*
(which columns, and what a missing value means).

## How it's used

Every script in `code/03_panel_building/` sources this file via `CWA_ROOT`, right after
it sources `_paths.R`, then calls the functions below instead of redefining them
locally:

```r
source(file.path(CWA_ROOT, "code/02_cleaning/cleaning_helpers.R"))
```

This file assumes the calling script has already loaded `library(data.table)` (for
`fread`, `fifelse`, `fcoalesce`) and, for the date functions, `library(lubridate)` (for
`mdy`). It doesn't call `library()` itself — R only needs those packages loaded by the
time the functions are actually *called*, which always happens later, in the sourcing
script.

## Functions

### `rd(file, cols, raw_dir = RAW_DIR)`

Reads one column-selected slice of a raw ICIS-NPDES CSV from `data/raw/npdes_
downloads/`, with every requested column forced to `character`.

- **Why character, not auto-detected types:** many ID-like fields (`NPDES_ID`,
  `FACILITY_UIN`, ZIP codes, county codes) are digit strings with meaningful leading
  zeros (a ZIP of `"00501"`). Letting R guess the type would silently read that as the
  number `501`, corrupting the ID. Forcing character up front avoids that whole class
  of bug; specific columns get converted to real numbers later, deliberately, only
  where a numeric value is actually wanted.
- **Args:** `file` — raw CSV filename, e.g. `"ICIS_FACILITIES.csv"`. `cols` — character
  vector of columns to keep. `raw_dir` — folder to look in; defaults to `RAW_DIR`
  (already defined by every panel-building script), so most callers omit it.
- **Returns:** a `data.table` with just the requested columns, all `character`.
- **Used by:** `01`, `02`, `03`, `04`, `05`, `06`, `use_operating_proxies.R`.

### `build_facility_crosswalk(raw_dir = RAW_DIR)`

Maps every permit (`NPDES_ID`) to its physical facility (`facility_id`).

- **Why it's needed:** the panel is one row per physical *facility* per month, but most
  raw EPA data (inspections, violations, enforcement) is recorded against a *permit*.
  Every raw source needs translating from "this happened to permit X" to "this happened
  at facility Y" before it can be added to the panel — this function builds that
  translation table once, so every script uses the identical mapping.
- **The rule:** use `FACILITY_UIN` (EPA's cross-program Facility Registry Service ID,
  the more stable identifier for a physical site) when a permit has one on file;
  otherwise fall back to the permit's own `NPDES_ID` as a stand-in facility ID, rather
  than dropping the permit.
- **Why it always reads the full, unrestricted `ICIS_FACILITIES.csv`:** if a script
  built the crosswalk from an already-filtered copy (e.g. "only major individual
  permits"), any raw-data row belonging to a facility's *other* permits (a general
  stormwater permit at a site whose main permit is in-population) would have nowhere to
  route to and would be silently dropped.
- **Args:** `raw_dir` — passed to `rd()`; defaults to `RAW_DIR`.
- **Returns:** a `data.table`, one row per `NPDES_ID`, columns `(NPDES_ID,
  facility_id)`, ready to join other tables against via `on = "NPDES_ID"`.
- **Used by:** `01`, `02`, `03`, `04`, `05`, `06`, `use_operating_proxies.R`.

### `coalesce_date_priority(dt, date_cols)`

Picks **one** date to represent an event, trying each candidate column in the order
given and using the first one that's actually filled in.

- **When to use this vs. `coalesce_date_extreme()` below:** use this one when several
  columns are candidates for "the" date of a single event and you have a preference
  order among them (e.g. an inspection's `ACTUAL_BEGIN_DATE` before its
  `ACTUAL_END_DATE`). It answers "which of these interchangeable columns should win,"
  not "what's the widest possible window."
- **Args:** `dt` — a `data.table` with the raw date columns as text. `date_cols` —
  character vector of column names, **most-preferred first**.
- **Returns:** a vector of parsed `Date`s (one per row of `dt`); `NA` where every
  candidate was blank or unparseable.
- **Used by:** `02_add_inspections.R`, `use_operating_proxies.R`.

### `coalesce_date_extreme(dt, date_cols, which = c("min", "max"))`

Combines several candidate date columns into one, taking the **earliest** (`"min"`) or
**latest** (`"max"`) value across whichever candidates are actually present. A blank
candidate is simply ignored, not treated as earlier/later than everything else.

- **When to use this vs. `coalesce_date_priority()` above:** use this one when you want
  the *widest possible window*, not "the one true date" among equivalent options — e.g.
  a permit's opening date should be the *earliest* of `EFFECTIVE_DATE`, `ISSUE_DATE`,
  `ORIGINAL_ISSUE_DATE` that's actually filled in.
- **Which columns to pass, and what "no date at all" means, are research decisions**
  documented as labeled, PI-guided assumptions in `01_build_facility_month_panel_
  major_individual.R`, right next to where this function is called — this function
  only does the min/max arithmetic, not the choice of inputs.
- **Args:** `dt` — a `data.table` with the raw date columns as text. `date_cols` —
  character vector of candidate columns (order doesn't matter here, unlike
  `coalesce_date_priority()`). `which` — `"min"` or `"max"`.
- **Returns:** a vector of `Date`s (one per row); `NA` only if *every* candidate was
  blank/unparseable for that row.
- **Used by:** `01_build_facility_month_panel_major_individual.R`.

## Conventions

- Every function assumes the calling script has already run `library(data.table)`
  (and `library(lubridate)` for the date functions) — see "How it's used" above.
- No cleaning here for `dmr analysis/` or `code/dmr/`'s filter mini-pipeline — those
  are separate, standalone pipelines and out of scope for this extraction.
- No cleaning here for `build_effluent_violations_npdes_month_panel.R` either, despite
  living in the same folder — it's a standalone script, not a shared helper; see its
  own README.

## References

Called from `code/03_panel_building/01_build_facility_month_panel_major_individual.R`
through `06_add_effluent_violations.R`, and from `code/03_panel_building/
use_operating_proxies.R`. See each caller's own "LABELED ASSUMPTIONS" section for the
research decisions layered on top of these mechanics.
