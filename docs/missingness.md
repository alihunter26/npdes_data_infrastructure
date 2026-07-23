# Chronically Missing Variables in the NPDES / ICIS Data

Purpose. A reference for which variables are systematically missing, how badly,
which facilities are affected, and why it matters for analysis. Missingness here is
almost never random (MNAR) — it tracks permit type, size, vintage, and geography — so
complete-case analysis induces selection bias, not just lost power.

Number provenance. Figures marked *(measured)* were computed this session from the
raw files in `data/raw/` (via the checks in `scripts/check_naics_sic_mapping.R`,
`code/summary/summarize_dmr_coverage_major_minor.R`, and ad-hoc passes over
`ICIS_PERMITS`, `ICIS_FACILITIES`, `NPDES_EFF_VIOLATIONS`); they are reproducible but
were run interactively. Figures marked *(derived)* follow logically from the data model.
Figures marked *(qualitative)* are dataset knowledge not exactly quantified here.

---

## Summary table

| Variable | File | Missingness | Most affected | Why it's a problem |
|---|---|---|---|---|
| `NAICS_CODE` | `NPDES_NAICS` | ~75% missing across all permits; ~65% in major-individual (~35% present) *(measured)* | All permit types; flat across vintages | No NAICS industry controls across the sample; can't crosswalk to SIC; can't be modeled as a vintage effect |
| `SIC_CODE` | `NPDES_SICS` | ~1.5% missing for major-individual; ~41% missing across all permits *(measured)* | General / minor / recently issued permits | Fine for majors; collapses on any extension to minors/general/recent cohorts → biased to older, larger facilities |
| `MAJOR_MINOR_STATUS_FLAG` | `ICIS_PERMITS` | ~3.6% blank (60,436 / 1,694,646 rows) *(measured)* | Scattered | Those facilities can't be classified and silently drop from major/minor-restricted samples; also a snapshot (not time-varying) |
| Lifecycle dates (`TERMINATION_DATE`, `EFFECTIVE_DATE`, `ORIGINAL_ISSUE_DATE`) | `ICIS_PERMITS` | Frequently missing *(qualitative)* | Active permits (termination); older records | Drives entry/exit reconstruction; a missing date defaults to "ongoing," mis-dating entry/exit and inflating the balanced portion |
| `GEOCODE_LATITUDE` / `LONGITUDE` | `ICIS_FACILITIES` | 0.5% invalid for major-individual; higher for general/offshore; plus placeholder/centroid fills *(measured)* | General, offshore, corporately-addressed permits | Spatial joins silently fail or misassign; placeholder coords create phantom clustering |
| `COUNTY_CODE`, address fields | `ICIS_FACILITIES` | Often blank / `(UNKNOWN)` *(qualitative)* | General/minor, generic-UIN facilities | County-level merges (demographics, EJ, jurisdiction) drop or mismatch |
| `FED_PENALTY_ASSESSED_AMT`, `STATE_LOCAL_PENALTY_AMT` | `NPDES_FORMAL/INFORMAL_ENFORCEMENT_ACTIONS` | Absent/zero for the ~88–91% of actions that are informal, plus many formal *(derived)* | Informal actions (the vast majority) | Penalty-based severity is defined only on a small, selected subset — not usable as a general enforcement outcome |
| SEP value, compliance-action cost, cost recovery | (bulk files) | Entirely absent from bulk; only in the case-report API *(measured)* | All | Bulk penalty totals badly understate true case magnitude (e.g., PRASA: $1M penalty vs $195M compliance cost) |
| `DMR_VALUE_NMBR` (non-receipt blanks) | `NPDES_DMRS` | Majors ~84% covered vs minors ~7% (FY2025) *(measured)* | Minor facilities, pre-2016 | Can't measure discharge/violations for most minors; gap shrinks after the 2016 eRule → spurious non-stationary "trend" |
| `ADJUSTED_DMR_VALUE_NMBR` | `NPDES_EFF_VIOLATIONS` | ~100% missing (6 of 46,361,587 rows) *(measured)* | All | None — ignore; effluent trading is negligible |
| `EXCEEDENCE_PCT`, `RNC_*`, `NODI_CODE`, `DAYS_LATE` | `NPDES_EFF_VIOLATIONS` | Populated only for their specific violation subtype *(derived)* | All rows of other types | Conditionally defined, not truly missing; aggregating over all rows mixes structural NAs/zeros and misleads unless you condition on `VIOLATION_TYPE_CODE` |
| ATTAINS assessment / impairment | `NPDES_ATTAINS_AU_SUMMARIES`, `NPDES_CATCHMENTS` | Catchment record absent for ~7% (549) of major-individual permits *(measured)* | Coastal / marine / offshore | Inner-join spatial merges silently drop these facilities with no error, shrinking the sample non-randomly |
| ATTAINS assessment history | `NPDES_ATTAINS_AU_SUMMARIES` | Only the latest cycle per unit — no history *(measured)* | All | A recent snapshot; can't study water-quality *change* over the panel window |

---

## The non-random pattern (why it's the real problem)

The missingness is concentrated in the same places:

- Industry codes, coordinates, and DMRs go missing for general / minor / recent / offshore facilities.
- Penalties are missing for the many non-penalized (informal) actions.
- Water quality is missing for coastal / offshore sites.

So dropping incomplete rows quietly selects toward large, onshore, older, individually-permitted,
formally-enforced majors. Complete-case analysis is therefore not neutral — it changes the
population you are describing.

## Implication for the major-individual panel

Restricting to major-individual permits makes most of these near-complete: ~99% have SIC, ~99%
have a valid geocode, ~99% have a major/minor flag, only ~1% have no industry code. The variables
that still bite even in this panel:

1. `NAICS_CODE` (~65% missing) → use SIC as the industry variable.
2. Penalty fields (informal actions) → don't use penalty `$` as a general enforcement outcome; use action counts / SNC flags.
3. Catchment dropout (~7% coastal/offshore) → anti-join after any spatial merge to catch silently dropped facilities.
4. DMR / eRule non-stationarity → if you add violation/DMR data, control for or flag the ~2016 reporting break.

---
*Regenerate the measured figures from the scripts named above.*
