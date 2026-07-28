# Codebook — facility-by-month panel

Variable definitions for the **most recent panel**:
`data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv`
(built 2026-07-28; 59 columns). This is the final-assembly output of the six-step
pipeline in `code/03_panel_building/01…06_*.R` — see
[`code/03_panel_building/README.md`](../code/03_panel_building/README.md) for the pipeline
and [`READMEs/`](../code/03_panel_building/READMEs/) for full per-script detail (this
file condenses those six READMEs into one column-by-column reference, cross-checked
against the actual CSV header and, where a discrepancy turned up, the script source).

**2026-07-23: a standalone correction step 07 was retired and folded into step 01.**
`FACILITY_OPERATING` used to be corrected by a post-processing script that ran after
step 06 (because it needed every event type already assembled). It turned out to only
need to know *whether and when* a facility had any real event, not the full detailed
counts, so that check now runs **inside step 01** instead — `FACILITY_OPERATING` is
correct from the moment it's first created, and steps 02–06 needed no code changes.
The panel's columns, values, and row count are **unchanged** by this move — verified
by a full column-by-column diff against the retired step-07 output (zero differences).
See "The window correction" below and step 01's README for the full story.

**2026-07-28: panel membership now depends on proxy evidence too, not permit dates**
**alone, and a new column (9) reports the proxy-only window.** Previously, a facility
whose permit-paperwork window didn't overlap 2005–2025 was dropped entirely before
the proxy scan ever ran — proxy evidence only widened an already-admitted facility's
window, never granted admission on its own. Now a facility is kept if EITHER its
permit window overlaps 2005–2025 OR it has independent proxy evidence (inspection,
violation, enforcement, effluent) anywhere in that range. Verified: of 7,531
candidate facilities, 16 are admitted **solely** via proxy evidence (no permit-window
overlap at all) and 1 is dropped (neither) — final population 7,530, panel rows
1,897,560 (+4,032 = 16 × 252 months vs. the pre-7/28 baseline). The new column,
`FACILITY_OPERATING_PROXY_WINDOW`, reports the proxy-only-derived window independent
of permit dates — for a proxy-only-admitted facility it's the *only* column showing
why that facility is in the panel at all, since `FACILITY_OPERATING_PERMIT_WINDOW`
correctly reads 0 for every one of its months. See "Panel membership" below and step
01's README, Assumption 1B.

**FY2025 row-filter script removed (2026-07-23).** `restrict_06_to_fy2025.R` (which
produced a federal-FY2025, Oct 2024–Sep 2025 extract) has been deleted. Its two prior
outputs remain on disk as **static, non-regenerable** files — there is no longer a
script that rebuilds either, so don't treat them as a source of truth:
`07_facility_month_panel_major_individual_operating_corrected_fy2025.csv` and the
still-older `06_facility_month_panel_major_individual_effluent_fy2025.csv`. For a
fresh FY2025 (or any other window) extract, filter the current 06 panel directly.

**Grain:** facility × year × month. **Unit:** FRS facility (`FACILITY_UIN`, or
`NPDES_ID` when `FACILITY_UIN` is blank). **Population:** facilities linked to ≥1
individual (`NPD`) NPDES permit that was flagged **major** in at least one permit
version, at any point in its history ("ever major," not "always major"), AND (since
2026-07-28) either a permit-paperwork window overlapping 2005–2025 **or** independent
proxy evidence anywhere in that range — permit dates alone no longer gate membership
(see "Panel membership" below). **Window:** Jan 2005–Dec 2025, 48 continental states +
DC only (excludes AK, HI, PR, VI, GU, AS, MP). **Rows:** 1,897,560 (7,530 facilities ×
252 months) — the panel is **balanced**: every qualifying facility has one row per
month regardless of whether it was actually open that month.

---

## Read this first: `FACILITY_OPERATING` and the NA-vs-0 convention

Column 7, `FACILITY_OPERATING`, governs how nearly every count column in this panel
encodes "nothing happened":

- **`FACILITY_OPERATING == 1`** (the month falls inside the facility's active window)
  **and no event matched** → the count is **`0`** (a true, measured zero).
- **`FACILITY_OPERATING == 0`** (outside the facility's active window) **and no event
  matched** → the count is **`NA`** (undefined — the facility wasn't there to have an
  event).
- **A real matched event always wins**, regardless of `FACILITY_OPERATING`. A month
  can show `FACILITY_OPERATING == 0` and still carry a non-NA count if an event was
  genuinely recorded then — but this can now only happen for a facility with **zero**
  recorded events anywhere in its whole panel life (see below); for every facility
  with at least one real event, the window has already been extended to cover it, so
  `FACILITY_OPERATING == 0` reliably means NA.

This applies to every `N_*` / `n_*` count column below (inspections, NAICS/SIC are
exempt — they're time-invariant attributes, not events). The two penalty-dollar
columns (`FED_PENALTY`, `STATE_PENALTY`) use a related but separate NA rule: NA means
"no action carried a dollar amount," not "not operating" — see their entries.

Of 1,897,560 rows, **1,754,214 are operating (`=1`) and 143,346 are not (`=0`)**.

### The window correction (why `FACILITY_OPERATING` isn't just permit dates)

`FACILITY_OPERATING` was originally computed purely from `ICIS_PERMITS` date fields —
no independent knowledge of whether a facility was actually active. Measured directly:
**12.66% of `FACILITY_OPERATING == 0` rows (32,033 of 253,028) still carried a real
recorded event** — proof the facility was genuinely active — and 75.9% of those were
more than 12 months outside the computed window (median 31, max 250 months). 2,381 of
7,511 facilities (32%) were affected.

**Root cause:** permits with `PERMIT_STATUS_CODE == "ADC"` (Administrative
Continuance — legally still active past the nominal `EXPIRATION_DATE` while a renewal
is pending) had that `EXPIRATION_DATE` read as a real closing date anyway. 86.7% of the
8,007 permits linked to this panel's facilities carry `ADC` status at some point (see
`docs/data_issues.md`, the `PERMIT_STATUS_CODE`/`EXPIRATION_DATE` row).

**The fix (now applied inside step 01):** extend each facility's window (both
directions) to `min/max(permit-only window, first/last month with a real recorded
event)`, checking event *existence* only across inspections, PS/CS/SE violations,
formal/informal enforcement, and effluent violations (the last via the pre-built
condensed panel — no need to stream the raw 16 GB effluent file for this). This can
only grow a window, never shrink one. The result: `FACILITY_OPERATING` in this panel
is the **corrected** flag; the original permit-window-only flag is preserved as a
separate column, **`FACILITY_OPERATING_PERMIT_WINDOW`** (column 8) — see its entry
below. Full detail, every labeled assumption, and the worked example (facility
`110006619212`) are in
[`code/03_panel_building/READMEs/01_build_facility_month_panel_major_individual.md`](../code/03_panel_building/READMEs/01_build_facility_month_panel_major_individual.md)
(Assumption 10; see also `code/03_panel_building/use_operating_proxies.R`) and `docs/notes.md`.

**One residual limitation to know:** a facility whose panel life shows **zero**
recorded events anywhere (no inspections, violations, enforcement, or effluent
violations, ever) cannot be corrected this way — there's no event to extend the window
against, so its `FACILITY_OPERATING` still rests entirely on the original permit-date
window and carries the same undiagnosed risk described above. The fix resolves every
facility where the risk is *provable* from the panel's own data; it cannot fix a
facility where the permit dates are wrong **and** the facility was never independently
observed doing anything. (Such a facility's `FACILITY_OPERATING_PROXY_WINDOW`, column
9, is `NA` throughout — the honest signal that no independent evidence exists either
way.)

### Panel membership: permit-window overlap OR proxy evidence (2026-07-28)

Before this date, a facility's admission to the panel depended **only** on its
permit-paperwork window overlapping 2005–2025 (Assumptions 2–4 in step 01's README);
proxy evidence only ever widened an *already-admitted* facility's operating window,
never granted admission on its own. Now a facility is admitted if **either**:

- its permit-paperwork window genuinely overlaps 2005–2025 (tested on the raw,
  unclipped dates, not the panel-clipped ones — clipping would otherwise make every
  facility "overlap" by construction), **or**
- it has independent proxy evidence (inspection, PS/CS/SE violation, formal/informal
  enforcement action, or effluent violation) anywhere in 2005–2025, even if its
  permit window never reaches that range.

**Verified:** of 7,531 "ever major, ever individual" candidates, 7,514 have permit-
window overlap, **16 are admitted solely via proxy evidence**, and 1 is dropped
(neither) — final population 7,530. For a proxy-only-admitted facility,
`FACILITY_OPERATING_PERMIT_WINDOW` (column 8) correctly reads **0 for every month**
(the permit info exists, it just says "not active this period" — a genuine reported
zero, not a missing value), and `FACILITY_OPERATING` (column 7) collapses to exactly
`FACILITY_OPERATING_PROXY_WINDOW` (column 9) — spot-checked on facility
`110000311485` (0/252 months permit-window-active; 243/252 proxy-window-active;
`FACILITY_OPERATING` matches the proxy column exactly everywhere).

Full detail: step 01's README, Assumption 1B, and
`code/03_panel_building/use_operating_proxies.R`'s own header.

---

## 1 · Spine & facility attributes (step 01)

| # | Column | Type | Description |
|---|---|---|---|
| 1 | `FACILITY_UIN` | text | Facility identifier (EPA FRS Universal Interchange Number). Falls back to `NPDES_ID` when blank in the raw data — no facility is silently dropped for lacking one. **Panel key**, together with `YEAR`/`MONTH`. |
| 2 | `YEAR` | integer | Calendar year, 2005–2025. |
| 3 | `MONTH` | integer | Calendar month, 1–12. |
| 4 | `NPDES_ID` | text | **Semicolon-separated list** of every individual (`NPD`) permit ever linked to this facility, `sort(unique(...))`. 427 of 7,511 facilities (5.7%) have >1; max is 7. To count distinct permits per facility, split on `"; "` — grouping directly on `FACILITY_UIN` will not do it, the collapse already happened here. |
| 5 | `MAJOR_MINOR_FLAG` | text | Semicolon list, **position-aligned with `NPDES_ID`** — one major/minor flag (`M`/`N`) per listed permit, from `ICIS_PERMITS.MAJOR_MINOR_STATUS_FLAG`. A facility qualifies for the panel if *any* entry is ever `M` at any point in that permit's version history ("ever major"); entries can legitimately mix `M` and `N` for the same facility. 875 facilities shift between major and minor at some point. |
| 6 | `PERMIT_TYPE_FLAG` | text | Constant `"NPD"` for every row — the panel is restricted to individual permits by construction (general/`GPC` permits are out of scope). |
| 7 | `FACILITY_OPERATING` | integer (0/1) | **The union — use this.** See "Read this first" above. 1 iff the calendar month falls within the facility's window after extending it to also cover any month with independent proxy evidence. For a facility admitted solely via proxy evidence (no permit-window overlap; see "Panel membership" above), this column is identical to `FACILITY_OPERATING_PROXY_WINDOW` (column 9). Facility *attribute* columns (name, address, `NPDES_ID` list, …) are **not** masked by this flag — they broadcast the same snapshot to every month regardless. |
| 8 | `FACILITY_OPERATING_PERMIT_WINDOW` | integer (0/1) | The *original* permit-dates-only definition: 1 iff the month falls within the facility's earliest-open/latest-close window computed purely from permit dates (unioned across all its individual permits, clipped to 2005–2025) — before the correction. **Explicitly 0 (not NA) for every month of a facility admitted solely via proxy evidence** — the permit info exists, it just doesn't reach this panel's range. Preserved for traceability; use `FACILITY_OPERATING` (column 7) for analysis, not this one. |
| 9 | `FACILITY_OPERATING_PROXY_WINDOW` | integer (0/1) / NA | **New 2026-07-28.** 1 iff the month falls within the facility's proxy-evidence-only window (earliest to latest month with an inspection, PS/CS/SE violation, formal/informal enforcement action, or effluent violation), with **no permit-date influence at all**. `NA` (not 0) for a facility with zero qualifying proxy events anywhere in 2005–2025 — there's no earliest/latest of an empty set, so "not operating per proxies" and "no proxy evidence exists at all" stay distinguishable. For a proxy-only-admitted facility this is the *only* column showing why it's in the panel; for every other facility it's a third, independent lens on operating status. Identity: `FACILITY_OPERATING >= FACILITY_OPERATING_PROXY_WINDOW` holds for every row (ignoring NA). |
| 10 | `FACILITY_TYPE_CODE` | text | Raw ICIS facility-type code. Observed values in this panel: `CNG`, `COR`, `CTG`, `DIS`, `FDF`, `MWD`, `MXO`, `NON`, `POF`, `STF`, `TRB`, or blank. **No code→label lookup table exists anywhere in this repo** — don't guess at meanings (e.g. `MWD` is commonly "municipal wastewater discharge" in ICIS documentation generally, but that mapping isn't verified against a source held here). If you need this decoded, pull EPA's ICIS-NPDES facility-type reference table before using it analytically. Time-invariant snapshot. |
| 11 | `FACILITY_NAME` | text | Snapshot, time-invariant. When a facility has >1 linked permit, the record with a non-blank name is preferred and broadcast to all months. Real name/location changes over time are **not** tracked (ICIS carries no history for these fields). |
| 12 | `LOCATION_ADDRESS` | text | Snapshot, same caveat as `FACILITY_NAME`. |
| 13 | `CITY` | text | Snapshot. |
| 14 | `STATE_CODE` | text | 2-letter USPS state code. Restricted to the 48 continental states + DC (AK/HI/PR/VI/GU/AS/MP excluded from the whole panel). |
| 15 | `ZIP` | text | Zero-padded to 5 characters (`sprintf("%05s", ZIP)`); kept as text throughout — never coerce to numeric or the leading zeros are lost. |
| 16 | `COUNTY_CODE` | text | FIPS county code, snapshot. |
| 17 | `FAC_LAT` | numeric | Facility latitude (`ICIS_FACILITIES.GEOCODE_LATITUDE`), snapshot. |
| 18 | `FAC_LONG` | numeric | Facility longitude (`ICIS_FACILITIES.GEOCODE_LONGITUDE`), snapshot. |

## 2 · Inspections (step 02)

Inspection grain = distinct `ACTIVITY_ID` (never raw component rows — raw rows
over-count multi-component visits by ~6%). Dated by begin date, falling back to end
date. Routed to a facility via `NPDES_ID` through the step-01 crosswalk.

| # | Column | Type | Description |
|---|---|---|---|
| 19 | `N_INSPECTIONS_TOTAL` | integer / NA | All distinct inspections that facility-month, any type/conductor. |
| 20 | `N_CEI` | integer / NA | Compliance Evaluation Inspections. |
| 21 | `N_ROS` | integer / NA | Reconnaissance inspections (without sampling). |
| 22 | `N_SA1` | integer / NA | Sampling inspections. |
| 23 | `N_AU1` | integer / NA | Audit inspections. |
| 24 | `N_STATE_INSPECTIONS` | integer / NA | Inspections conducted by a state agency. |
| 25 | `N_EPA_INSPECTIONS` | integer / NA | Inspections conducted by EPA. |

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
| 26 | `NAICS_CODE` | text | Every NAICS code across all of the facility's permits, **semicolon-joined, primary code first** (`PRIMARY_INDICATOR_FLAG == "Y"` sorts first), de-duplicated, order preserved (not alphabetical). Blank `""` (not NA) if the facility's permits never appear in the NAICS file — coverage is sparse. 161 of 7,511 facilities carry >1 code. |
| 27 | `SIC_CODE` | text | Same construction for SIC. Near-complete coverage for the major population. 466 facilities carry >1 code. |

## 4 · Compliance-schedule violations (step 04)

Violation grain = distinct `NPDES_VIOLATION_ID`. Dated by when the violation
*occurred* (not when EPA detected it): `SCHEDULE_DATE` for PS/CS, `SINGLE_EVENT_VIOLATION_DATE`
(start) for SE. Routed via the step-01 crosswalk; a violation on **any** permit
resolving to the facility counts.

| # | Column | Type | Description |
|---|---|---|---|
| 28 | `N_PS_VIOLATIONS` | integer / NA | Permit-schedule violations — missed permit-schedule milestones. |
| 29 | `N_CS_VIOLATIONS` | integer / NA | Compliance-schedule violations — missed compliance-schedule milestones. |
| 30 | `N_SE_VIOLATIONS` | integer / NA | Single-event violations. |

Effluent (DMR-based) violations are **not** in this block — they live entirely in
section 6 below (step 06 owns all effluent-violation columns; they were moved out of
step 04).

## 5 · Enforcement (step 05)

**Updated 2026-07-28:** formal and informal are now counted the **SAME way — per raw
row** (`.N` / `sum(<condition>)`, never `uniqueN(ENF_IDENTIFIER)`). Previously formal
counted distinct actions while informal counted raw rows — the two were deliberately
on different grains; per request, formal switched to informal's per-row style. This is
the single most important thing to know about this section.

- **Formal** = **per raw row**. Dated `SETTLEMENT_ENTERED_DATE` (~97% present).
  Consequence: the formal file has multiple rows per action (one per permit and/or
  per `ENF_TYPE_CODE`) — 111,816 rows vs. 103,989 distinct `ENF_IDENTIFIER`s, with
  **0 exact-duplicate rows** — so `N_FORMAL_ACTIONS` now over-counts relative to
  distinct actions for any action spanning >1 permit or >1 type (entirely
  multi-permit/multi-type fan-out, not literal duplication).
- **Informal** = **per raw row** (`.N` / `sum(<flag>)`), **not** deduplicated to
  distinct `ENF_IDENTIFIER` — a deliberate PI decision, not an oversight. The informal
  source file is 42% byte-identical duplicate rows (345,822 of 821,977); under
  per-row counting an action recorded 3× identically counts as 3. This inflates
  informal totals ≈1.7× vs. distinct-action counting (93,470 informal rows vs. 56,356
  distinct actions, on an earlier panel build). Dated `ACHIEVED_DATE` (~99% present).
- **Penalty dollars are the one exception, still distinct-action grain:**
  `FED_PENALTY`/`STATE_PENALTY`/`N_FED_PENALTY_ASSESSED`/`N_STATE_PENALTY_ASSESSED`
  still de-duplicate to one row per action before summing (summing a shared penalty
  across an action's raw rows would multiply it) — so these four are on a
  **different grain** than `N_FORMAL_ACTIONS` and shouldn't be compared 1:1 against it.

Both routed via `NPDES_ID` through the step-01 crosswalk; an action on any permit
resolving to the facility counts.

| # | Column | Type | Description |
|---|---|---|---|
| 35 | `N_FORMAL_ACTIONS` | integer / NA | **Raw-row count** of formal enforcement records (see design note above — not distinct actions; a multi-permit/multi-type action's rows each count separately). |
| 36 | `N_AFR` | integer / NA | Formal actions with `ACTIVITY_TYPE_CODE == "AFR"` (administrative formal). |
| 37 | `N_JDC` | integer / NA | Formal actions with `ACTIVITY_TYPE_CODE == "JDC"` (judicial). |
| 38 | `N_SCWAAPO` | integer / NA | Formal actions with `ENF_TYPE_CODE == "SCWAAPO"`. |
| 39 | `N_STAOCO` | integer / NA | Formal actions with `ENF_TYPE_CODE == "STAOCO"`. |
| 40 | `N_SCWAAO` | integer / NA | Formal actions with `ENF_TYPE_CODE == "SCWAAO"`. |
| 41 | `N_309A` | integer / NA | Formal actions with `ENF_TYPE_CODE == "309A"` (CWA §309(a) actions). |
| 42 | `N_STATE_AFR` | integer / NA | `AFR` actions led by a state agency. |
| 43 | `N_EPA_AFR` | integer / NA | `AFR` actions led by EPA. `N_STATE_AFR + N_EPA_AFR == N_AFR` (agency is one-per-action; verified in the run log). |
| 44 | `N_STATE_JDC` | integer / NA | `JDC` actions led by a state agency. |
| 45 | `N_EPA_JDC` | integer / NA | `JDC` actions led by EPA. `N_STATE_JDC + N_EPA_JDC == N_JDC`. |
| 46 | `FED_PENALTY` | numeric $ / NA | Sum of federal penalty dollars (`FED_PENALTY_ASSESSED_AMT`) across the facility-month's formal actions, penalty de-duplicated to one value per action first. **NA means "not assessed," not "$0."** Blanks vastly outnumber true zeros (~107k blank vs. 72 genuine federal $0s). NA is independent of `FACILITY_OPERATING` — it's about whether an amount was ever assessed; unaffected by the window correction. |
| 47 | `N_FED_PENALTY_ASSESSED` | integer | Count of distinct formal actions carrying a non-blank federal penalty amount — a different grain than `N_FORMAL_ACTIONS` (row 35, per-row); not directly comparable. |
| 48 | `STATE_PENALTY` | numeric $ / NA | Same as `FED_PENALTY` for `STATE_LOCAL_PENALTY_AMT` (~64k blank vs. 768 genuine state $0s). |
| 49 | `N_STATE_PENALTY_ASSESSED` | integer | Count of distinct formal actions carrying a non-blank state penalty amount — same different-grain note as row 47. |
| 50 | `N_INFORMAL_ACTIONS` | integer / NA | **Raw-row count** of informal enforcement records (see design note above — not distinct actions). |
| 51 | `N_LOVWL` | integer / NA | Informal rows, `ENF_TYPE_CODE == "LOVWL"` (Letter of Violation / Warning Letter). |
| 52 | `N_NOV` | integer / NA | Informal rows, `"NOV"` (Notice of Violation). |
| 53 | `N_NONC` | integer / NA | Informal rows, `"NONC"` (Notice of Noncompliance). |
| 54 | `N_AER` | integer / NA | Informal rows, `"AER"` (Agency Enforcement Review — an internal/unofficial process step; see `OFFICIAL_FLG` note below and [`docs/data_dictionary.md`](data_dictionary.md)). |
| 55 | `N_OFFICIAL_INFORMAL` | integer / NA | Informal rows with `OFFICIAL_FLG == "Y"` — genuine official actions (LOVWL/NOV/NONC-type). |
| 56 | `N_UNOFFICIAL_INFORMAL` | integer / NA | Informal rows with `OFFICIAL_FLG == "N"` — internal agency process, not an action against the discharger. `N_OFFICIAL_INFORMAL + N_UNOFFICIAL_INFORMAL == N_INFORMAL_ACTIONS`. **If you want a count of real enforcement contacts, filter to `N_OFFICIAL_INFORMAL`** — including unofficial rows inflates counts with phone calls, reviews, and internal placeholders (see `docs/data_dictionary.md`). |

**Type/activity breakouts (36–41, 51–54) are not partitions** — an action can carry
several `ENF_TYPE_CODE`s and land in more than one column; rarer codes aren't broken
out at all, so columns needn't sum to the parent total. `ENF_TYPE_CODE` variants
ending in `S` (e.g. `AERS` vs. `AER`) are the state-issued counterpart of the same
activity and are **not** folded into these columns — an open `TODO` in the source
script.

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
| 31 | `N_TSS_EFF_VIOLATIONS` | integer / NA | All TSS/effluent-gross/monthly-avg violations that month, any code, distinct `NPDES_VIOLATION_ID`. Streamed directly from the raw ~16 GB `NPDES_EFF_VIOLATIONS.csv` (Python-filtered before `fread`, to stay within an 8 GB-RAM machine's memory). |
| 32 | `N_TSS_EFF_D90` | integer / NA | TSS subset, `D90` code. |
| 33 | `N_TSS_EFF_D80` | integer / NA | TSS subset, `D80` code. |
| 34 | `N_TSS_EFF_E90` | integer / NA | TSS subset, `E90` code — genuine measured exceedances of the TSS limit. |
| 57 | `n_D80` | integer / NA | All-parameter `D80` count, from the pre-built condensed monthly panel (`effluent_violations_npdes_month_panel_2005_2025.csv`); already de-duplicated to distinct underlying violations (latest DMR resubmission version only) at source. This is the same file step 01 reads for its proxy-evidence scan (Assumption 10; see `code/03_panel_building/use_operating_proxies.R`). |
| 58 | `n_D90` | integer / NA | All-parameter `D90` count. |
| 59 | `n_E90` | integer / NA | All-parameter `E90` count. |

Columns 31–34 sit right after `N_SE_VIOLATIONS` (their original position from when
this block lived in step 04); columns 57–59 sit at the very end of the panel — the
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
  to the facility counts toward that facility, not just the major one(s). Step 01
  itself builds this crosswalk **twice** — once restricted (for the spine), once
  unrestricted (for the proxy-evidence scan) — see its README, Assumption 10.
- **Three operating flags, one intended for use** — `FACILITY_OPERATING` (the union,
  column 7) is what analysis should use; `FACILITY_OPERATING_PERMIT_WINDOW` (column 8)
  is the original permit-date-only version, kept for traceability/audit only;
  `FACILITY_OPERATING_PROXY_WINDOW` (column 9, new 2026-07-28) is the proxy-evidence-
  only version — useful for understanding *why* a facility is in the panel, or for
  isolating proxy-driven activity from permit-derived activity, but not a substitute
  for `FACILITY_OPERATING` in general analysis.

## See also

- [`docs/data_dictionary.md`](data_dictionary.md) — cross-table join logic for the raw
  ICIS-NPDES source tables (not the panel itself), plus the `OFFICIAL_FLG` /
  `ENF_TYPE_CODE` "-S variant" notes referenced above.
- [`docs/data_issues.md`](data_issues.md), [`docs/notes.md`](notes.md),
  [`docs/time_varying_vs_snapshot.md`](time_varying_vs_snapshot.md) — known data
  issues, e.g. the ~2016 eRule DMR-coverage break, non-monthly DMR periods, and the
  `PERMIT_STATUS_CODE`/`ADC` quirk behind the window correction.
- [`code/03_panel_building/READMEs/`](../code/03_panel_building/READMEs/) — full
  SSDE-style documentation per build step, including every numbered assumption this
  dictionary compresses into single lines.
