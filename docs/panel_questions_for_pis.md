# Facility-by-Month Panel (Major Individual, 2005-2025) — Questions for PIs

Open decisions and data issues to flag before/while building the facility-by-month
panel of major individual NPDES facilities, 2005-2025. Pulled from the Master
Question List, `missingness.md`, `data_quirks.md`, and digging done this round.

## Date field for operating status

Options for opening:
- ORIGINAL_ISSUE_DATE: date the permit was first issued (0.8% missing)
- ISSUE_DATE: date the specific version was issued (0.8% missing)
- EFFECTIVE_DATE: date this version became legally effective, usually = ISSUE_DATE (0.8% missing)

Options for closing:
- TERMINATION_DATE: formal termination of the permit (80.8% missing — only shows up on TRM status rows)
- EXPIRATION_DATE: stated end of the permit's term (0.8% missing, but it's populated even on permits that are still active under ADC, so can't use it alone or you close out facilities that are still discharging)
- RETIREMENT_DATE: don't use this one at all — see below, it's not a closing date

Suggestion: use EFFECTIVE_DATE for opening. For closing: TERMINATION_DATE if PERMIT_STATUS_CODE = TRM, EXPIRATION_DATE if PERMIT_STATUS_CODE = EXP (actually lapsed, not continued), otherwise assume still operating (covers ADC and EFF, which are legally still active past their expiration date).

## RETIREMENT_DATE — looks like a closing date, isn't one

Checked this because it seemed like an obvious candidate and it's not:
- RETIREMENT_DATE is set to ~1 day before the NEXT version's EFFECTIVE_DATE, basically every time. It's just marking when a version got superseded by a reissuance, not when the facility closed.
- Shows up on ADC/EFF/EXP rows too, not just closed ones. Pulled one permit's full version history (AL0029181) — 4 RETIREMENT_DATE entries across 6 versions, and it's still active today (current status ADC).
- The RET status code isn't a closure flag either. 94% of RET-status rows belong to a permit whose current/final version is something else (mostly ADC or EFF) — RET just tags an old superseded version.

Suggestion: ignore RETIREMENT_DATE and RET status for entry/exit. They track reissuance, not closure.

## Date field for PS, CS, and SE violations

Which field to sort violations by month:
- SCHEDULE_DATE: when the compliance schedule was due (0% missing)
- ACTUAL_DATE: when the milestone was actually achieved (17% missing)
- REPORT_RECEIVED_DATE: when EPA/state received the report (16.8% missing)
- RNC_DETECTION_DATE: when it was flagged as reaching RNC status (54.1% missing)
- RNC_RESOLUTION_DATE: when RNC was resolved (54.1% missing)

Missing on the RNC fields means it didn't meet the RNC threshold, not that the value is unknown.

Still an open question — haven't dug into this one enough yet to have a suggestion.

## Date field for DMR

Which field to use to decide what month a DMR record belongs to:
- MONITORING_PERIOD_END_DATE: end of the period the facility is reporting discharge for — the real-world measurement date (0% missing)
- VALUE_RECEIVED_DATE: date EPA/state actually logged the report as received — administrative processing date, not the discharge event (4.5% missing)
- RNC_DETECTION_DATE / RNC_RESOLUTION_DATE: dates tied to noncompliance escalation, not the monitoring event itself (94.3% missing — most DMR rows never escalate to RNC)
- LIMIT_BEGIN_DATE / LIMIT_END_DATE: the legal validity window of the specific numeric limit being checked against, not the report date. 0% missing, but LIMIT_END_DATE isn't a reliable cutoff — 28.2% of rows report past their limit's stated end date while still governed by that same limit (same ADC-style continuance pattern as the permit-level dates above).

Suggestion: use MONITORING_PERIOD_END_DATE. It's the actual discharge-measurement date, not when paperwork got filed (VALUE_RECEIVED_DATE) or when a limit's admin window happens to end (LIMIT_END_DATE). Reporting lag is already captured separately by DAYS_LATE and the non-receipt violation codes (D80/D90), so folding VALUE_RECEIVED_DATE into the time axis would just blur "happened in month X" with "got logged in month Y."

### The NMBR_OF_REPORT complication — assign to end month, or spread across the period?

Using MONITORING_PERIOD_END_DATE still leaves one open call. NMBR_OF_REPORT is the number of months the reported value's monitoring window actually covers — not how often the facility files paperwork overall (that's NMBR_OF_SUBMISSION, and the two only agree 65.8% of the time). A facility can file monthly for most parameters but still have one parameter on a quarterly or semi-annual monitoring schedule, and that row is only dated by its window's end.

Measured on FY2025 DMR (26.87M rows):
- NMBR_OF_REPORT = 1 (monthly) for 88% of rows; the other ~12.2% (3.29M rows) cover 2+ months (quarterly = 3, semi-annual = 6, annual = 12, plus some odd values).
- These aren't degenerate placeholder rows — 47% of multi-month rows carry an actual DMR_VALUE_NMBR (a real reported number), vs. 46.9% with a NODI code (no data). Single-month rows are actually *less* likely to have a real value (40.4%).
- Top STATISTICAL_BASE_CODE values on the multi-month rows: DD, MK, MB, MN, QA, 3C, ME, MO, IA, AF — haven't confirmed these against ECHO's published data dictionary yet, worth checking before relying on which statistical bases dominate.

Options:
- Assign to end month only: one row = one number = one time window, dated at the window's end. Doesn't invent anything — just places the summary statistic where it was actually computed.
- Spread across the window (end back through end − (NMBR_OF_REPORT − 1)): makes the panel show "activity" in every month the window touches, so a semi-annual parameter doesn't look inactive 10 months out of 12.

Suggestion: end month only, don't spread. Talked myself out of spreading it — the project's own rule for these ICIS files is that a blank/absent record almost always means "not applicable," not "unknown" (same logic as the RNC fields above). Spreading a single 6-month measurement across 5 months with no actual monitoring event manufactures presence that isn't there — those months aren't missing data, there was no monitoring event to record because the permit doesn't require one that often for that parameter. Keep NMBR_OF_REPORT as its own column in the panel so anyone using it can see that a given month's DMR row might represent a longer measurement window, instead of silently faking five extra months of activity to paper over it.

## Major/Minor status — restrict to always-major, or allow shifts?

- 875 facilities (of 84,773 individual-permit facilities held some year 2005-2025) shift between major and minor status at some point in the window.
- Of those, 855 switch once, 20 switch twice (e.g. minor → major → minor).
- Direction split: 562 minor→major, 313 major→minor — upgrades to major are about 2x more common than downgrades.

Suggestion: restrict to major the whole time. Better DMR coverage (majors ~84% vs minors ~7%, from `missingness.md`), and it keeps the major/minor status question out of the panel entirely instead of having to explain 875 edge cases.

## NAICS vs SIC — missingness and the historical switch

SIC started in 1937. NAICS officially replaced it as the federal statistical standard in 1997, but ICIS never fully cut over — SIC stayed the dominant field for decades after that.

Coverage by original issue year, individual permits:

| Original issue year | n | % with NAICS | % with SIC |
|---|---|---|---|
| <1990 | 24,590 | 21.2% | 99.2% |
| 1990–1994 | 4,591 | 17.1% | 98.1% |
| 1995–1999 | 6,729 | 18.0% | 97.6% |
| 2000–2004 | 10,130 | 24.1% | 95.8% |
| 2005–2009 | 10,853 | 24.0% | 86.9% |
| 2010–2014 | 11,422 | 23.3% | 66.3% |
| 2015–2019 | 17,178 | 14.4% | 31.7% |
| 2020+ | 12,460 | 29.2% | 39.3% |

SIC coverage falls off a cliff for 2010+ cohorts. NAICS never picks up the slack — it stays in the 15-30% range the whole time, including for the newest permits. So it's not really "SIC replaced by NAICS" in this data, it's "industry coding got worse for new permits and nothing filled the gap."

For major individual specifically (our panel population): SIC ~99% present, NAICS ~65% missing. But that's driven by the panel skewing toward older, legacy permits — recently-issued individual permits are much less likely to have SIC.

Suggestion: use SIC as the industry variable, coverage is still near-complete for majors overall. Just flag that this is weaker for anything entering after ~2010 if industry composition of recent entrants matters.

## Enforcement action double-counting (ACTIVITY_ID)

- One enforcement action can show up as multiple rows if it covers more than one permit — same ACTIVITY_ID, one row per permit it touches. Example from `data_quirks.md`: one PRASA settlement = 135 rows, same $1,024,427 fine repeated on every one.
- Checked the formal enforcement file directly: 111,816 rows but only 103,989 distinct ACTIVITY_ID — about 7% inflation if you just count rows.
- Restricting to major-individual makes FACILITY_UIN ~1:1 with NPDES_ID, which kills most of this, but not all of it — 84 facilities hold more than one individual permit, so an action touching two of that facility's permits would still double count.

Suggestion: dedupe on (FACILITY_UIN, ACTIVITY_ID) before counting actions or summing penalties. Don't just count rows.

## Facility identity: FACILITY_UIN vs NPDES_ID

- NPDES_ID = permit. FACILITY_UIN = physical site.
- Universe-wide, 10.5% of FACILITY_UIN map to more than one NPDES_ID, and some of that is generic umbrella IDs covering hundreds of unrelated permits (one ND UIN = 361 permits). Not safe to collapse to FACILITY_UIN outside a restricted population.
- Restricting to major-individual fixes this — only 84 facilities hold more than one individual permit.

Suggestion: use FACILITY_UIN as the panel unit, it's safe once restricted to major-individual. Just keep the ACTIVITY_ID dedupe above so the ~84 multi-permit facilities don't get inflated counts.

## Penalty $ as an enforcement severity measure

- Most enforcement actions are informal, and informal actions don't carry a penalty (~88-91% of all actions).
- Fed/state penalty fields are blank or zero for those, so summing $ per facility only reflects the small formal/penalized subset.
- Bulk files also don't have SEP value or compliance cost, only the case-report API does. PRASA example again: $1M penalty vs $195M actual compliance cost.

Suggestion: use action counts (or SNC/RNC flags) as the severity measure, not penalty dollars.

## Spatial / catchment coverage for coastal facilities

- ~7% (549) of major-individual permits are coastal/offshore and have no NPDES_CATCHMENTS record. They silently drop out of inner-join spatial merges — no error, no missing flag, they just vanish.

Suggestion: anti-join after any spatial merge to check who got dropped. Don't assume an inner join caught everyone.

## Aggregating outfalls up to the facility (DMR)

The DMR row is a measurement, not a facility or an outfall — FY2025 has 26.87M rows over 89,954 permits (~299 rows/permit). The grain is permit x outfall (PERM_FEATURE_NMBR) x parameter x statistical base x limit set x monitoring period. To get a facility time series you have to collapse across all of that, and the outfall dimension is the one that needs a real decision, not a default.

Key fact: this does NOT go away when we restrict to major-individual. That restriction fixes facility identity (FACILITY_UIN ~1:1 with the permit — see "Facility identity" above), but the multi-outfall structure lives *inside* a single permit. A major-individual permit averages 3.75 outfalls (FY2025 DMR: 25,157 distinct permit-outfall pairs across 6,701 reporting permits), so "aggregate outfalls to the facility" is really "aggregate ~4 outfalls within one permit," and it's central to the panel, not a fringe case.

Each specific issue, its severity, and how I'd handle it:

### 1. Outfall key only unique within a permit — LOW severity (post-restriction)

PERM_FEATURE_NMBR is sequential per permit (001, 002, ...), so two permits under the same facility can each have a "001" that are different physical outfalls. Keying outfalls on feature number alone after collapsing to facility collides them. In the full universe this matters; restricted to major-individual it barely does — only 84 facilities hold >1 individual permit (see "Facility identity"), and several of those extra permits are S-prefixed stormwater/general coverages the NPD filter already drops.

Suggestion: key outfalls on (EXTERNAL_PERMIT_NMBR, PERM_FEATURE_NMBR), never PERM_FEATURE_NMBR alone. Costs nothing and stays correct for the 84. Then either drop those 84 or handle them explicitly — they're high-outfall sites (DOT districts, chemical plants, phosphate mines, MS4s), so a "drop 84 known facilities" footnote is cleaner than silently mis-summing them.

### 2. Concentrations aren't additive across outfalls — HIGH if the outcome is discharge levels, N/A if it's compliance

You cannot sum or plain-average mg/L across outfalls 001 and 002 — it's physically meaningless. Loads (mass, lbs) *are* additive: total facility load = sum of per-outfall loads. Exceedance/compliance outcomes also aggregate cleanly (any exceedance; count of exceedances). So the whole problem only bites if the dependent variable is a concentration.

Suggestion: pick the outcome type first. For loads, sum across outfalls (needs flow per outfall + unit conversion via DMR_VALUE_STANDARD_UNITS — flow gaps will silently drop outfalls, so check coverage). For concentrations, don't aggregate — flow-weight, or take the primary process outfall (usually 001, but verify against the permit rather than assuming). For compliance, aggregate exceedances — this also lines up with the enforcement spine the panel already uses.

### 3. Changing outfall composition over time — HIGH (probably the biggest one)

The set of outfalls a facility reports isn't constant across 2005-2025: outfalls get added/retired, permits get modified, and DMR coverage ramps hard around the ~2016 NPDES eReporting rule. A facility-period total that sums "whatever outfalls reported that period" then conflates real change in discharge with change in what's being monitored — a facility that adds a stormwater outfall looks like it started discharging more, and pre-2016 years look artificially clean. This is a within-facility comparability threat, i.e. it contaminates exactly the variation a facility fixed-effects design leans on.

Suggestion: carry the count of reporting outfalls (and monitored parameter-periods) as a panel column and control for it, or build a stable-outfall-set version that only counts outfalls present across the whole active window. At minimum, flag the eReporting break so early-period "improvements" aren't read as real. Ties into the majors-have-better-coverage point in `missingness.md`.

### 4. Summing across outfall / monitoring-location types double-counts — MEDIUM-HIGH

Within one permit the features aren't all comparable effluent points. PERM_FEATURE_TYPE_CODE distinguishes external outfall (EXO), influent (INF), sum point (SUM); MONITORING_LOCATION_CODE distinguishes effluent gross (1) / net (2) from intake (0). Blindly summing all features can add intake water to discharge, or add an internal outfall AND the SUM point that already aggregates it — double counting.

Suggestion: before aggregating, filter to effluent external outfalls — PERM_FEATURE_TYPE_CODE = EXO and MONITORING_LOCATION_CODE in {1, 2}, drop intake (0). Decide SUM points deliberately: either use the SUM feature and drop its component outfalls, or use the components and drop SUM — never both.

### 5. Reporting-frequency weighting across outfalls — MEDIUM

Outfalls (and parameters within an outfall) report at different frequencies, so a raw sum over DMR rows over-weights monthly reporters vs quarterly/annual ones, and a raw mean mixes statistical bases. This is the outfall-level twin of the NMBR_OF_REPORT issue already flagged for the time axis.

Suggestion: build the intended period statistic explicitly rather than sum/mean over raw rows — annual load = sum of monthly loads; annual exceedances = count; and hold STATISTICAL_BASE_CODE fixed (don't average a monthly-avg row together with a daily-max row). Reuse the NMBR_OF_REPORT handling from the DMR date section so a single multi-month row isn't counted as if it were monthly.
