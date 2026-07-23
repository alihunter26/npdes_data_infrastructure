# Codebook — facility-by-month panel

Variable definitions for the **most recent panel**:
`data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv`
(built 2026-07-22; 57 columns). This is the final-assembly output of the six-step
pipeline in `code/03_panel_building/01…06_*.R` — see
[`code/03_panel_building/README.md`](../code/03_panel_building/README.md) for the pipeline
and [`READMEs/`](../code/03_panel_building/READMEs/) for full per-script detail (this
file condenses those six READMEs into one column-by-column reference, cross-checked
against the actual CSV header and, where a discrepancy turned up, the script source).

A restricted variant, `06_facility_month_panel_major_individual_effluent_fy2025.csv`
(federal FY2025, Oct 2024–Sep 2025), has identical columns — everything below applies
to it unchanged.

**Grain:** facility × year × month. **Unit:** FRS facility (`FACILITY_UIN`, or
`NPDES_ID` when `FACILITY_UIN` is blank). **Population:** facilities linked to ≥1
individual (`NPD`) NPDES permit that was flagged **major** in at least one permit
version, at any point in its history ("ever major," not "always major"). **Window:**
Jan 2005–Dec 2025, 48 continental states + DC only (excludes AK, HI, PR, VI, GU, AS,
MP). **Rows:** 1,892,772 (7,511 facilities × 252 months) — the panel is **balanced**:
every qualifying facility has one row per month regardless of whether it was actually
open that month.

---

## Read this first: the `FACILITY_OPERATING` / NA-vs-0 convention

Column 7, `FACILITY_OPERATING`, governs how nearly every count column in this panel
encodes "nothing happened":

- **`FACILITY_OPERATING == 1`** (the month falls inside the facility's own
  earliest-open→latest-close window) **and no event matched** → the count is **`0`**
  (a true, measured zero).
- **`FACILITY_OPERATING == 0`** (outside the facility's active window) **and no event
  matched** → the count is **`NA`** (undefined — the facility wasn't there to have an
  event).
- **A real matched event always wins**, regardless of `FACILITY_OPERATING`. A month
  can show `FACILITY_OPERATING == 0` and still carry a non-NA count if an event was
  genuinely recorded then (e.g. administrative lag right at a permit boundary).
  `FACILITY_OPERATING == 0` guarantees NA only when nothing was *also* matched.

This applies to every `N_*` / `n_*` count column below (inspections, NAICS/SIC are
exempt — they're time-invariant attributes, not events). The two penalty-dollar
columns (`FED_PENALTY`, `STATE_PENALTY`) use a related but separate NA rule: NA means
"no action carried a dollar amount," not "not operating" — see their entries.

Of 1,892,772 rows, 1,639,744 are operating (`=1`) and 253,028 are not (`=0`).

---

## 1 · Spine & facility attributes (added by step 01)

| # | Column | Type | Description |
|---|---|---|---|
| 1 | `FACILITY_UIN` | text | Facility identifier (EPA FRS Universal Interchange Number). Falls back to `NPDES_ID` when blank in the raw data — no facility is silently dropped for lacking one. **Panel key**, together with `YEAR`/`MONTH`. |
| 2 | `YEAR` | integer | Calendar year, 2005–2025. |
| 3 | `MONTH` | integer | Calendar month, 1–12. |
| 4 | `NPDES_ID` | text | **Semicolon-separated list** of every individual (`NPD`) permit ever linked to this facility, `sort(unique(...))`. 427 of 7,511 facilities (5.7%) have >1; max is 7. To count distinct permits per facility, split on `"; "` — grouping directly on `FACILITY_UIN` will not do it, the collapse already happened here. |
| 5 | `MAJOR_MINOR_FLAG` | text | Semicolon list, **position-aligned with `NPDES_ID`** — one major/minor flag (`M`/`N`) per listed permit, from `ICIS_PERMITS.MAJOR_MINOR_STATUS_FLAG`. A facility qualifies for the panel if *any* entry is ever `M` at any point in that permit's version history ("ever major"); entries can legitimately mix `M` and `N` for the same facility. 875 facilities shift between major and minor at some point. |
| 6 | `PERMIT_TYPE_FLAG` | text | Constant `"NPD"` for every row — the panel is restricted to individual permits by construction (general/`GPC` permits are out of scope). |
| 7 | `FACILITY_OPERATING` | integer (0/1) | 1 iff the calendar month falls within the facility's own active window — earliest open to latest close, unioned across **all** its individual permits (not just the major one(s)), clipped to 2005–2025. See the convention section above. Facility *attribute* columns (name, address, `NPDES_ID` list, …) are **not** masked by this flag — they broadcast the same snapshot to every month regardless. |
| 8 | `FACILITY_TYPE_CODE` | text | Raw ICIS facility-type code. Observed values in this panel: `CNG`, `COR`, `CTG`, `DIS`, `FDF`, `MWD`, `MXO`, `NON`, `POF`, `STF`, `TRB`, or blank. **No code→label lookup table exists anywhere in this repo** — don't guess at meanings (e.g. `MWD` is commonly "municipal wastewater discharge" in ICIS documentation generally, but that mapping isn't verified against a source held here). If you need this decoded, pull EPA's ICIS-NPDES facility-type reference table before using it analytically. Time-invariant snapshot (see Assumption 7, next column). |
| 9 | `FACILITY_NAME` | text | Snapshot, time-invariant. When a facility has >1 linked permit, the record with a non-blank name is preferred and broadcast to all months. Real name/location changes over time are **not** tracked (ICIS carries no history for these fields). |
| 10 | `LOCATION_ADDRESS` | text | Snapshot, same caveat as `FACILITY_NAME`. |
| 11 | `CITY` | text | Snapshot. |
| 12 | `STATE_CODE` | text | 2-letter USPS state code. Restricted to the 48 continental states + DC (AK/HI/PR/VI/GU/AS/MP excluded from the whole panel). |
| 13 | `ZIP` | text | Zero-padded to 5 characters (`sprintf("%05s", ZIP)`); kept as text throughout — never coerce to numeric or the leading zeros are lost. |
| 14 | `COUNTY_CODE` | text | FIPS county code, snapshot. |
| 15 | `FAC_LAT` | numeric | Facility latitude (`ICIS_FACILITIES.GEOCODE_LATITUDE`), snapshot. |
| 16 | `FAC_LONG` | numeric | Facility longitude (`ICIS_FACILITIES.GEOCODE_LONGITUDE`), snapshot. |

## 2 · Inspections (step 02)

Inspection grain = distinct `ACTIVITY_ID` (never raw component rows — raw rows
over-count multi-component visits by ~6%). Dated by begin date, falling back to end
date. Routed to a facility via `NPDES_ID` through the step-01 crosswalk.

| # | Column | Type | Description |
|---|---|---|---|
| 17 | `N_INSPECTIONS_TOTAL` | integer / NA | All distinct inspections that facility-month, any type/conductor. |
| 18 | `N_CEI` | integer / NA | Compliance Evaluation Inspections. |
| 19 | `N_ROS` | integer / NA | Reconnaissance inspections (without sampling). |
| 20 | `N_SA1` | integer / NA | Sampling inspections. |
| 21 | `N_AU1` | integer / NA | Audit inspections. |
| 22 | `N_STATE_INSPECTIONS` | integer / NA | Inspections conducted by a state agency. |
| 23 | `N_EPA_INSPECTIONS` | integer / NA | Inspections conducted by EPA. |

**Not a partition:** one inspection can carry several monitoring types, so
`N_CEI + N_ROS + N_SA1 + N_AU1` can exceed `N_INSPECTIONS_TOTAL` (rarer types aren't
broken out). **Is a partition:** `N_STATE_INSPECTIONS + N_EPA_INSPECTIONS ==
N_INSPECTIONS_TOTAL` (conductor is exactly one per inspection; verified in the build
run log). These five columns come from one joined source row per facility-month, so
they're always all-NA or all-real together — never a mix.

## 3 · Industry codes (step 03)

Time-invariant facility attributes (the code files carry no date/version).

| # | Column | Type | Description |
|---|---|---|---|
| 24 | `NAICS_CODE` | text | Every NAICS code across all of the facility's permits, **semicolon-joined, primary code first** (`PRIMARY_INDICATOR_FLAG == "Y"` sorts first), de-duplicated, order preserved (not alphabetical). Blank `""` (not NA) if the facility's permits never appear in the NAICS file — coverage is sparse. 161 of 7,511 facilities carry >1 code. |
| 25 | `SIC_CODE` | text | Same construction for SIC. Near-complete coverage for the major population. 466 facilities carry >1 code. |

## 4 · Compliance-schedule violations (step 04)

Violation grain = distinct `NPDES_VIOLATION_ID`. Dated by when the violation
*occurred* (not when EPA detected it): `SCHEDULE_DATE` for PS/CS, `SINGLE_EVENT_VIOLATION_DATE`
(start) for SE. Routed via the step-01 crosswalk; a violation on **any** permit
resolving to the facility counts.

| # | Column | Type | Description |
|---|---|---|---|
| 26 | `N_PS_VIOLATIONS` | integer / NA | Permit-schedule violations — missed permit-schedule milestones. |
| 27 | `N_CS_VIOLATIONS` | integer / NA | Compliance-schedule violations — missed compliance-schedule milestones. |
| 28 | `N_SE_VIOLATIONS` | integer / NA | Single-event violations. |

Effluent (DMR-based) violations are **not** in this block — they live entirely in
section 6 below (step 06 owns all effluent-violation columns; they were moved out of
step 04).

## 5 · Enforcement (step 05)

Formal and informal enforcement are counted **differently, by design** — this is the
single most important thing to know about this section.

- **Formal** = distinct actions (`uniqueN(ENF_IDENTIFIER)`). Dated
  `SETTLEMENT_ENTERED_DATE` (~97% present).
- **Informal** = **per raw row** (`.N` / `sum(<flag>)`), **not** deduplicated to
  distinct `ENF_IDENTIFIER` — a deliberate PI decision, not an oversight. The informal
  source file is 42% byte-identical duplicate rows (345,822 of 821,977); under
  per-row counting an action recorded 3× identically counts as 3. This inflates
  informal totals ≈1.7× vs. distinct-action counting (93,470 informal rows vs. 56,356
  distinct actions, on this panel). Dated `ACHIEVED_DATE` (~99% present).

Both routed via `NPDES_ID` through the step-01 crosswalk; an action on any permit
resolving to the facility counts.

| # | Column | Type | Description |
|---|---|---|---|
| 33 | `N_FORMAL_ACTIONS` | integer / NA | All distinct formal enforcement actions. |
| 34 | `N_AFR` | integer / NA | Formal actions with `ACTIVITY_TYPE_CODE == "AFR"` (administrative formal). |
| 35 | `N_JDC` | integer / NA | Formal actions with `ACTIVITY_TYPE_CODE == "JDC"` (judicial). |
| 36 | `N_SCWAAPO` | integer / NA | Formal actions with `ENF_TYPE_CODE == "SCWAAPO"`. |
| 37 | `N_STAOCO` | integer / NA | Formal actions with `ENF_TYPE_CODE == "STAOCO"`. |
| 38 | `N_SCWAAO` | integer / NA | Formal actions with `ENF_TYPE_CODE == "SCWAAO"`. |
| 39 | `N_309A` | integer / NA | Formal actions with `ENF_TYPE_CODE == "309A"` (CWA §309(a) actions). |
| 40 | `N_STATE_AFR` | integer / NA | `AFR` actions led by a state agency. |
| 41 | `N_EPA_AFR` | integer / NA | `AFR` actions led by EPA. `N_STATE_AFR + N_EPA_AFR == N_AFR` (agency is one-per-action; verified in the run log). |
| 42 | `N_STATE_JDC` | integer / NA | `JDC` actions led by a state agency. |
| 43 | `N_EPA_JDC` | integer / NA | `JDC` actions led by EPA. `N_STATE_JDC + N_EPA_JDC == N_JDC`. |
| 44 | `FED_PENALTY` | numeric $ / NA | Sum of federal penalty dollars (`FED_PENALTY_ASSESSED_AMT`) across the facility-month's formal actions, penalty de-duplicated to one value per action first. **NA means "not assessed," not "$0."** Blanks vastly outnumber true zeros (~107k blank vs. 72 genuine federal $0s). NA is independent of `FACILITY_OPERATING` — it's about whether an amount was ever assessed. |
| 45 | `N_FED_PENALTY_ASSESSED` | integer | Count of distinct formal actions carrying a non-blank federal penalty amount. |
| 46 | `STATE_PENALTY` | numeric $ / NA | Same as `FED_PENALTY` for `STATE_LOCAL_PENALTY_AMT` (~64k blank vs. 768 genuine state $0s). |
| 47 | `N_STATE_PENALTY_ASSESSED` | integer | Count of distinct formal actions carrying a non-blank state penalty amount. |
| 48 | `N_INFORMAL_ACTIONS` | integer / NA | **Raw-row count** of informal enforcement records (see design note above — not distinct actions). |
| 49 | `N_LOVWL` | integer / NA | Informal rows, `ENF_TYPE_CODE == "LOVWL"` (Letter of Violation / Warning Letter). |
| 50 | `N_NOV` | integer / NA | Informal rows, `"NOV"` (Notice of Violation). |
| 51 | `N_NONC` | integer / NA | Informal rows, `"NONC"` (Notice of Noncompliance). |
| 52 | `N_AER` | integer / NA | Informal rows, `"AER"` (Agency Enforcement Review — an internal/unofficial process step; see `OFFICIAL_FLG` note below and [`docs/data_dictionary.md`](data_dictionary.md)). |
| 53 | `N_OFFICIAL_INFORMAL` | integer / NA | Informal rows with `OFFICIAL_FLG == "Y"` — genuine official actions (LOVWL/NOV/NONC-type). |
| 54 | `N_UNOFFICIAL_INFORMAL` | integer / NA | Informal rows with `OFFICIAL_FLG == "N"` — internal agency process, not an action against the discharger. `N_OFFICIAL_INFORMAL + N_UNOFFICIAL_INFORMAL == N_INFORMAL_ACTIONS`. **If you want a count of real enforcement contacts, filter to `N_OFFICIAL_INFORMAL`** — including unofficial rows inflates counts with phone calls, reviews, and internal placeholders (see `docs/data_dictionary.md`). |

**Type/activity breakouts (34–39, 49–52) are not partitions** — an action can carry
several `ENF_TYPE_CODE`s and land in more than one column; rarer codes aren't broken
out at all, so columns needn't sum to the parent total. `ENF_TYPE_CODE` variants
ending in `S` (e.g. `AERS` vs. `AER`) are the state-issued counterpart of the same
activity and are **not** folded into these columns — an open `TODO` in the source
script.

> **⚠️ Documentation discrepancy found while building this dictionary:** the
> per-script README at
> [`code/03_panel_building/READMEs/05_add_enforcement.md`](../code/03_panel_building/READMEs/05_add_enforcement.md)
> describes columns 40–41 as a single agency split of *all* formal actions
> (`N_STATE_FORMAL`, `N_EPA_FORMAL`). That doesn't match either the live CSV header or
> the current script (`05_add_enforcement.R` lines 216–219, 274, 283): the actual
> output is the finer `N_STATE_AFR` / `N_EPA_AFR` / `N_STATE_JDC` / `N_EPA_JDC`
> breakdown documented above — an agency split of `AFR` and `JDC` *separately*, with no
> single "total formal actions by agency" column at all. The README appears to predate
> a script change and is stale; I built this dictionary from the script and CSV, which
> agree with each other. Worth a one-line fix to that README.

## 6 · Effluent violations (step 06, final assembly)

**Two independent count sets, kept separate on purpose** — `n_D80/n_D90/n_E90` are
all-parameter (every parameter, feature, and monitoring location), while
`N_TSS_EFF_*` are the same violation codes restricted to one specific limit: TSS,
effluent-gross location, monthly-average statistical base. The all-parameter counts
are a superset: `n_D80 ≥ N_TSS_EFF_D80`, and likewise for D90/E90, cell-by-cell
(a handful of facility-months run 1–2 lower due to more aggressive de-dup upstream in
the condensed source — reported in the build log, not asserted away).

Violation-code meanings (from `docs/npdes_data_overview.md`):

| Code | Meaning |
|---|---|
| `D80` | Facility failed to submit required monitoring data for a parameter. |
| `D90` | Facility failed to submit monitoring data for a parameter that has a specific numeric permit limit. |
| `E90` | Facility reported a discharge measurement that **exceeded** its permit limit. |

D80/D90 (non-reporting) dominate by volume nationally; E90 (actual measured
exceedances) is the minority. Both sets are dated by the DMR monitoring-period month
and routed via the step-01 crosswalk.

| # | Column | Type | Description |
|---|---|---|---|
| 29 | `N_TSS_EFF_VIOLATIONS` | integer / NA | All TSS/effluent-gross/monthly-avg violations that month, any code, distinct `NPDES_VIOLATION_ID`. Streamed directly from the raw ~16 GB `NPDES_EFF_VIOLATIONS.csv` (Python-filtered before `fread`, to stay within an 8 GB-RAM machine's memory). |
| 30 | `N_TSS_EFF_D90` | integer / NA | TSS subset, `D90` code. |
| 31 | `N_TSS_EFF_D80` | integer / NA | TSS subset, `D80` code. |
| 32 | `N_TSS_EFF_E90` | integer / NA | TSS subset, `E90` code — genuine measured exceedances of the TSS limit. |
| 55 | `n_D80` | integer / NA | All-parameter `D80` count, from the pre-built condensed monthly panel (`effluent_violations_npdes_month_panel_2005_2025.csv`); already de-duplicated to distinct underlying violations (latest DMR resubmission version only) at source. |
| 56 | `n_D90` | integer / NA | All-parameter `D90` count. |
| 57 | `n_E90` | integer / NA | All-parameter `E90` count. |

Columns 29–32 sit right after `N_SE_VIOLATIONS` (their original position from when
this block lived in step 04); columns 55–57 sit at the very end of the panel — the
two effluent blocks are not adjacent in column order.

---

## Global conventions

- **NA vs. 0** — see the `FACILITY_OPERATING` section at the top. Applies to every
  count column; the two penalty-dollar columns follow a related but distinct rule
  (NA = "no dollar amount ever assessed").
- **Blank (`""`) vs. NA** — reserved for `NAICS_CODE`/`SIC_CODE`: a facility with no
  matching code row gets `""`, not `NA`. Don't conflate the two conventions across
  sections.
- **Semicolon-joined lists** — `NPDES_ID`, `MAJOR_MINOR_FLAG` (position-aligned with
  `NPDES_ID`), `NAICS_CODE`, `SIC_CODE`. Split on `"; "` before counting or filtering
  distinct values within a facility.
- **IDs/codes are text**, never coerced to numeric — this matters for `FACILITY_UIN`
  (silently breaks `data.table` grouping if read as `integer64` without `bit64`
  loaded) and `ZIP` (loses leading zeros).
- **Time-invariant "snapshot" columns** — `FACILITY_TYPE_CODE`, `FACILITY_NAME`,
  `LOCATION_ADDRESS`, `CITY`, `COUNTY_CODE`, `FAC_LAT`, `FAC_LONG`, `NAICS_CODE`,
  `SIC_CODE` — are one value per facility broadcast across all 252 months. ICIS
  carries no history for these fields, so real changes over time (a rename, a
  relocation, a re-classified industry code) are invisible in this panel.
- **Type/agency/official breakouts are sometimes partitions and sometimes not** —
  checked per section above; don't assume either without checking (conductor and
  agency partition; violation/enforcement *type* codes generally don't, since one
  event can carry several).
- **Routing** — every event-level source file is joined to a facility via `NPDES_ID`
  through the identical permit→facility crosswalk built in step 01 and rebuilt
  identically in each downstream step; an event on *any* individual permit ever linked
  to the facility counts toward that facility, not just the major one(s).

## See also

- [`docs/data_dictionary.md`](data_dictionary.md) — cross-table join logic for the raw
  ICIS-NPDES source tables (not the panel itself), plus the `OFFICIAL_FLG` /
  `ENF_TYPE_CODE` "-S variant" notes referenced above.
- [`docs/data_quirks.md`](data_quirks.md), [`docs/notes.md`](notes.md),
  [`docs/time_varying_vs_snapshot.md`](time_varying_vs_snapshot.md) — known data
  issues, e.g. the ~2016 eRule DMR-coverage break and non-monthly DMR periods.
- [`code/03_panel_building/READMEs/`](../code/03_panel_building/READMEs/) — full
  SSDE-style documentation per build step, including every numbered assumption this
  dictionary compresses into single lines.
