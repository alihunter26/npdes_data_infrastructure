# Time-Varying vs. Snapshot Files in the NPDES / ICIS Data

Purpose. For a **facility-by-month panel of major-individual NPDES facilities, ~2005–2025**
(unit = `FACILITY_UIN`, time = calendar month), classify every raw ECHO file by whether it
carries a usable time dimension, and flag what that implies for panel construction.

Three temporal types:

- **Event / period-dated** — each row is stamped with a date (or monitoring period) and can be
  binned into a month. These populate the *time-varying* cells of the panel.
- **Spell / interval** — rows describe states that hold over a date range (permit versions,
  limit sets). Time-varying only after you *expand* the intervals into month rows.
- **Snapshot** — as-of-download; no usable within-file time dimension. These enter the panel
  only as **time-invariant covariates**, or not at all.

Grain matters as much as time: almost every time-varying table keys on `NPDES_ID` (a *permit*),
not `FACILITY_UIN` (a *site*). See §3.

Column headers below were read directly from the raw files; counts marked *(measured)* were
computed this session over `data/raw/` (see `data_quirks.md`, `missingness.md`).

---

## 1. Classification table

| File | Type | Row grain | Date/period field(s) | Can place in a month? |
|---|---|---|---|---|
| `NPDES_INSPECTIONS` | Event | one inspection | `ACTUAL_BEGIN_DATE`, `ACTUAL_END_DATE` | Yes |
| `NPDES_FORMAL_ENFORCEMENT_ACTIONS` | Event | one action×permit | `SETTLEMENT_ENTERED_DATE` | Yes (dedupe `ACTIVITY_ID`) |
| `NPDES_INFORMAL_ENFORCEMENT_ACTIONS` | Event | one action×permit | `ACHIEVED_DATE` | Yes (dedupe `ACTIVITY_ID`) |
| `NPDES_SE_VIOLATIONS` | Event | one single-event viol. | `SINGLE_EVENT_VIOLATION_DATE`, `_END_DATE`, RNC dates | Yes |
| `NPDES_CS_VIOLATIONS` | Event | one comp-schedule viol. | `SCHEDULE_DATE` / `ACTUAL_DATE` / `REPORT_RECEIVED_DATE` / RNC dates | Yes — **but which date?** (§4) |
| `NPDES_PS_VIOLATIONS` | Event | one permit-schedule viol. | `SCHEDULE_DATE` / `ACTUAL_DATE` / `REPORT_RECEIVED_DATE` / RNC dates | Yes — **but which date?** (§4) |
| `NPDES_QNCR_HISTORY` | Period | permit × quarter | `YEARQTR` | **Quarter only** — not monthly (§4) |
| `NPDES_DMRS_FY2009…FY2025` | Period | permit×outfall×param×period | `MONITORING_PERIOD_END_DATE`, `VALUE_RECEIVED_DATE` | Yes, but period ≠ always monthly (§5) |
| `NPDES_EFF_VIOLATIONS` | Period | one param violation | monitoring-period end, RNC dates | Yes — but **lossy/selected** (§5) |
| `ICIS_PERMITS` | **Spell** | permit **× version** | `EFFECTIVE_DATE`→`EXPIRATION_/TERMINATION_DATE` (+ `ISSUE`, `ORIGINAL_ISSUE`, `RETIREMENT`) | Only after expanding versions (§2) |
| `NPDES_LIMITS` | **Spell** | permit×version×feature×param×limit | `LIMIT_BEGIN_DATE`→`LIMIT_END_DATE` + `JAN…DEC` seasonal flags | Only after expanding intervals (§5) |
| `NPDES_DATA_GROUPS` | Snapshot* | permit×version×data group | `CREATED_DATE`, `UPDATED_DATE` (admin only) | No — classification, not events |
| `ICIS_FACILITIES` | Snapshot | one facility interest | none | No — current registry/location |
| `NPDES_PERM_COMPONENTS` | Snapshot | permit × component type | none | No |
| `NPDES_PERM_FEATURE_COORDS` | Snapshot | outfall | none | No — current coordinates |
| `NPDES_NAICS` | Snapshot | permit × NAICS | none | No — treat industry as fixed |
| `NPDES_SICS` | Snapshot | permit × SIC | none | No — treat industry as fixed |
| `NPDES_VIOLATION_ENFORCEMENTS` | Link | violation↔action | none (inherits) | No — bridge table only |
| `npdes_outfalls_layer` | Snapshot | outfall | none (embeds "current" status) | No — as-of-download |
| `ICIS_MASTER_GENERAL_PERMITS` | Spell | general permit×version | permit dates | Out of panel (general, not individual) |
| `Attains/NPDES_CATCHMENTS` | Snapshot | permit×catchment | none | No — static spatial crosswalk |
| `Attains/ATTAINS_AU_CATCHMENTS` | Snapshot | assessment unit | `REPORTINGCYCLE` (latest only) | No — latest cycle only *(measured)* |
| `Attains/NPDES_ATTAINS_AU_SUMMARIES` | Snapshot | permit×assessment unit | `REPORTINGCYCLE` (latest only) | No — no impairment history *(measured)* |

\* `NPDES_DATA_GROUPS` carries `CREATED_/UPDATED_DATE`, but these are record-maintenance
timestamps, not a compliance timeline; treat it as a snapshot classification.

**Bottom line for the panel.** Only the enforcement, inspection, violation, DMR, and effluent
files supply genuine month-level *events*. `ICIS_PERMITS` and `NPDES_LIMITS` supply the
*backbone* (who exists / what's regulated in month *t*) but must be expanded from spells.
Everything else — facility identity/location, industry, spatial/hydrography, and water-quality
impairment — is a **snapshot** that can only enter as a time-invariant covariate.

---

## 2. `ICIS_PERMITS` is a version *spell* file — the panel backbone (correction to earlier notes)

`ICIS_PERMITS` has **one row per (permit, version)**: 1,694,646 rows across 1,194,023 permits;
**24% of permits have >1 version** *(measured)*. Each version carries its own date range, so the
file is not a flat snapshot — it is a set of spells you expand into months.

I checked whether facility attributes actually change across a permit's versions *(measured)*:

- `MAJOR_MINOR_STATUS_FLAG` differs across version rows for **908 permits** → major/minor **is
  weakly time-varying**. This corrects `missingness.md`, which calls the flag "a snapshot." It is
  a snapshot *within a version* but changes at reissuance; the 908 is consistent with the ~875
  status-shifting facilities in `panel_questions_for_pis.md` (permit vs. facility grain).
- `TOTAL_DESIGN_FLOW_NMBR` differs across versions for **10,964 permits** → design flow is
  version-varying too; don't treat it as a fixed facility constant.
- `PERMIT_TYPE_CODE` differs for only **7 permits** → individual/general status is effectively
  fixed; safe to treat as time-invariant.

**Implication.** Build operating status and version-level covariates by expanding
`EFFECTIVE_DATE → (EXPIRATION_/TERMINATION_DATE)` into month rows. Open on `EFFECTIVE_DATE`;
close on `TERMINATION_DATE` if `PERMIT_STATUS_CODE = TRM`, on `EXPIRATION_DATE` if `= EXP`,
otherwise treat as still operating (ADC/EFF are legally active past expiration). **Do not** use
`RETIREMENT_DATE` or `RET` status as closure — they mark version supersession, not shutdown
(see `panel_questions_for_pis.md`). `VERSION_NMBR = 0` is the current version.

---

## 3. Grain mismatch: the panel is by *facility*, the data is by *permit*

- Panel unit = `FACILITY_UIN` (site). Time-varying tables key on `NPDES_ID` / `EXTERNAL_PERMIT_NMBR`
  (permit). You need the permit→facility crosswalk in `ICIS_FACILITIES` to roll up.
- Universe-wide, **10.5% of `FACILITY_UIN` map to >1 `NPDES_ID`** *(measured)*, some via generic
  umbrella IDs (one ND UIN = 361 permits) — **unsafe to collapse to facility outside a restricted
  population.** Restricting to major-individual fixes this: only **84 facilities hold >1 individual
  permit** *(measured)*.
- Enforcement double-counts: one `ACTIVITY_ID` is stored as **one row per permit it touches**
  (PRASA = 135 rows of the same $1,024,427). The formal file has 111,816 rows / 103,989 distinct
  `ACTIVITY_ID` (~7% inflation) *(measured)*. **Dedupe on `(FACILITY_UIN, ACTIVITY_ID)` before
  counting or summing.**

---

## 4. Frequency mismatch and the violation date-field problem

- **QNCR is quarterly** (`YEARQTR`), not monthly. It cannot be placed in a month without
  arbitrarily allocating the quarter's counts across its three months — which invents
  within-quarter timing that isn't in the data. Either keep the panel quarterly for QNCR-derived
  variables, or assign each quarter's flags to a designated month and document it.
- **Which date puts a violation in a month?** CS/PS violations expose `SCHEDULE_DATE` (0% missing),
  `ACTUAL_DATE` (~17% missing), `REPORT_RECEIVED_DATE` (~17%), and RNC detection/resolution dates
  (~54% missing). These mean different things — *scheduled* vs. *achieved* vs. *reported* vs.
  *escalated to RNC* — and choosing changes which month a violation lands in and how many are
  usable. Still an **open decision** (`panel_questions_for_pis.md`); pick per economic
  interpretation (occurrence vs. detection) and hold it fixed.
- RNC-date blanks are **structural**: missing = "never reached the RNC threshold," not unknown.
  Do not impute.

---

## 5. The measurement files are lossy, selected, and mixed-frequency

- **`NPDES_EFF_VIOLATIONS`** contains **only violating rows** — no compliant reports. An
  absent facility-month means "no recorded violation," **not** "no discharge." You can build
  violation *counts*, but not rates or averages (no denominator). Also ~46.4M rows are dominated
  by non-reporting codes D80/D90 (missing data), not measured exceedances (E90) — separate them.
- **DMR coverage is non-stationary.** Majors ~84% vs. minors ~7% in FY2025 *(measured)*, and the
  **2016 eRule pulls minors into e-reporting**, creating an artificial coverage jump. Restricting
  to majors mitigates this; if you use DMR/effluent variables, flag/control the ~2016 break.
- **DMR periods aren't all monthly.** `MONITORING_PERIOD_END_DATE` follows each parameter's
  monitoring frequency (monthly, quarterly, semiannual, annual). Aggregating to month requires
  handling parameters that report less often than monthly.
- **DMR history starts ~FY2009** (files present: FY2009–FY2025); monitoring data before ~2007 is
  absent (`npdes_data_overview.md`). A 2005–2025 monthly panel has **no DMR/effluent signal for
  2005–2008** — left-censored for those variables even though QNCR/enforcement reach further back.
- **`NPDES_LIMITS` is interval + seasonal.** Each limit holds over `LIMIT_BEGIN_DATE →
  LIMIT_END_DATE` and has monthly applicability flags (`JAN…DEC`, `ALL_MONTHS_LIMIT`). To know a
  facility's binding limit in month *t* you must expand intervals **and** read the seasonal
  columns, aligning on `EXTERNAL_PERMIT_NMBR + VERSION_NMBR + PERM_FEATURE_NMBR`.

---

## 6. Snapshots imposed on a monthly panel = anachronism / measurement error

Facility location, `NAICS`/`SIC` industry, outfall coordinates, catchment/hydrography, and ATTAINS
impairment are **as-of-download**. Backfilling the current value onto every historical month
assumes it never changed. Specific hazards:

- **Industry.** `NAICS` ~65% missing in major-individual; `SIC` ~99% present *(measured)* → use
  `SIC`, treat as time-invariant. ~49k facilities have >1 SIC (multi-activity) — collapse on the
  primary code. Coding is worse for post-2010 entrants, so recent-entrant industry composition is
  weakest.
- **Water quality (ATTAINS).** Only the latest reporting cycle survives (0 of 813k unit-pairs have
  >1) *(measured)* → a single impairment snapshot; **you cannot study water-quality change** over
  the window, only use it as a fixed covariate.
- **Silent coastal dropout.** `NPDES_CATCHMENTS` covers inland surface waters only; **~7% (549) of
  major-individual permits** (coastal/offshore) have no record and vanish from inner-join spatial
  merges with no error *(measured)*. **Anti-join** after any spatial merge to catch them.
- **`npdes_outfalls_layer`** embeds "current" SNC/violation/inspection status with no dates — do
  not read its status fields as time-varying; it is a snapshot layer.

---

## 7. Other panel hazards (not temporal, but they bite here)

- **Penalty `$` is not a usable continuous severity.** ~88–91% of actions are informal with no
  penalty; fed/state penalty fields are blank/zero for those, and bulk files omit SEP value and
  compliance cost (PRASA: $1M penalty vs. $195M compliance cost). Use **action counts / SNC-RNC
  flags**, not dollars.
- **Conditionally-defined fields.** `EXCEEDENCE_PCT`, `RNC_*`, `NODI_CODE`, `DAYS_LATE` are
  populated only for their specific violation subtype. Condition on `VIOLATION_TYPE_CODE` before
  any mean/sum, or structural zeros/NAs corrupt the aggregate.
- **Unclassifiable rows.** ~3.6% of permit rows have a blank `MAJOR_MINOR_STATUS_FLAG` *(measured)*;
  they drop from a major-restricted sample. Document the drop.
- **Parsing.** ICIS CSVs contain embedded commas, embedded newlines inside quoted fields, and NUL
  bytes (`ICIS_PERMITS`). Use a real CSV parser with `colClasses="character"` (`fread` / `read.csv`
  `skipNul=TRUE`); never `cut`/`awk -F,` or line-splitting, or columns silently shift and fake rows
  appear.

---

## 8. Assembly recipe implied by the above

1. Build the **spine** from `ICIS_PERMITS`: expand version spells → facility-month operating
   status; carry version-varying `MAJOR_MINOR_STATUS_FLAG` and `TOTAL_DESIGN_FLOW_NMBR`.
2. Roll permit → `FACILITY_UIN` via `ICIS_FACILITIES`; restrict to **major-individual** to make
   the roll-up safe.
3. Attach **event** tables (inspections, formal/informal enforcement, SE/CS/PS violations) by
   binning the chosen date into month; **dedupe `ACTIVITY_ID`**.
4. Attach **quarterly** QNCR at quarter grain (or a documented month assignment).
5. Optionally attach **DMR/effluent** for majors, flagging the 2016 eRule break and the
   pre-2009 gap; effluent gives counts only.
6. Merge **snapshots** (SIC, geocode, catchment, ATTAINS) as **time-invariant** covariates;
   anti-join to catch silent coastal dropout.
7. Do **not** use penalty dollars as a continuous outcome.

---
*Sources: raw headers in `data/raw/`; `data_quirks.md`, `missingness.md`,
`panel_questions_for_pis.md`, `npdes_data_overview.md`, `permit_types_brief.md`. Measured counts
recomputed this session over `ICIS_PERMITS.csv` and are reproducible with `data.table::fread`.*
