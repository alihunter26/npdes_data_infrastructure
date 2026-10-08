# README — `07_add_dmr.R`

** built and self-verified 2026-10-07; not yet reviewed by Ali **

*Step 7 of the facility-by-month panel build, and the first step that reads the DMR
files themselves. Input: step-06 panel + the FY2017 filtered DMR file. Output: the panel
plus 20 discharge/compliance variables and 6 bookkeeping columns, populated for FY2017
(Oct 2016 – Sep 2017) and `NA` everywhere else.*

## Overview

Through step 06 the panel knows only whether a facility was **cited** — `n_D80`,
`n_D90`, `n_E90`, `N_TSS_EFF_*`. It carries no measure of **how much was discharged**,
**how much was permitted**, or **how close to its limit** a facility ran. Those
quantities exist only in the per-fiscal-year DMR files, which the pipeline never opened.

This step reduces one fiscal year of DMR data to one row per **outfall × basis × month**
and aggregates it to facility-months. "Basis" is the mass/concentration distinction:

- **mass** = `VALUE_TYPE_CODE == 'Q1'` (quantity average, kg/d)
- **concentration** = `VALUE_TYPE_CODE == 'C2'` (concentration average, mg/L)

FY2017 only for now. Column names carry no year, so adding another fiscal year later means
filling more months, not renaming anything.

## Data Availability and Provenance Statements

Derived from EPA ECHO / ICIS-NPDES public data (public domain). DMR zips downloaded
2026-07-27 (see `data/raw/DMR/`). `REF_NODI.csv` transcribed from
[EPA's published DMR NODI code list](https://www.epa.gov/system/files/documents/2022-10/EPA%20DMR%20NODI%20CODES.pdf)
(Region 6 ECAD, 2022-10). ☒ All data publicly available.

### Details on each data source

| File | Format | Key fields used |
|---|---|---|
| `code/dmr/03_dmr_fy2017_00530_monloc1.csv` | `.csv` | `EXTERNAL_PERMIT_NMBR`, `PERM_FEATURE_NMBR`, `PERM_FEATURE_TYPE_CODE`, `LIMIT_SET_ID`, `VERSION_NMBR`, `MONITORING_PERIOD_END_DATE`, `STATISTICAL_BASE_CODE`, `VALUE_TYPE_CODE`, `NMBR_OF_REPORT`, `DMR_VALUE_STANDARD_UNITS`, `DMR_VALUE_QUALIFIER_CODE`, `LIMIT_VALUE_STANDARD_UNITS`, `LIMIT_VALUE_QUALIFIER_CODE`, `NODI_CODE`, `VIOLATION_CODE` |
| `data/processed/06_..._effluent_2005_2025.csv` | `.csv` | step-06 panel (the spine) |
| `data/raw/reference/REF_NODI.csv` | `.csv` | `NODI_CODE` → `NODI_ACTIVITY_CLASS` |
| `ICIS_FACILITIES.csv` | `.csv` | crosswalk via `build_facility_crosswalk()` |

## Dataset list

| File | Role | Grain | Provided |
|---|---|---|---|
| `code/dmr/03_dmr_fy2017_00530_monloc1.csv` | input (derived, pre-built) | DMR row | derived |
| step-06 panel | input | facility × year × month | derived |
| `data/raw/reference/REF_NODI.csv` | input (reference) | NODI code | **hand-curated** |
| `data/processed/dmr_fy2017_tss_effgross_mk_outfall_basis.csv` | output (intermediate) | permit × outfall × month × basis | derived |
| `data/processed/07_..._dmr_tss_2005_2025.csv` | **output (panel)** | facility × year × month | derived |
| `output/tables/dmr_fy2017_dropped_multiset_permits_<stamp>.csv` | output (diagnostic) | permit | derived |
| `output/tables/dmr_fy2017_exceed_disagreements_<stamp>.csv` | output (diagnostic) | DMR row | derived |

## Computational Requirements

- **R** 4.4.2. Packages: `data.table`, `lubridate`.
- **External tools:** none. Unlike the `code/dmr/` prerequisite steps, this script needs
  no DuckDB, `unzip` or `gzip` — its input is ~100 MB and `fread`s safely on an 8 GB machine.
- **Controlled randomness:** none; fully deterministic.
- **Memory/runtime:** seconds to low minutes.
- **Prerequisite** (manual, ~45 min, run once per FY):
  ```bash
  Rscript code/dmr/filter_dmr_major_individual.R 2017
  Rscript code/dmr/filter_dmr_00530.R 2017
  Rscript code/dmr/filter_dmr_monloc1.R 2017
  ```
  Step 4 of that pipeline (`filter_dmr_c1q1.R`) is deliberately **not** used — it selects
  `C1`/`Q1`, and the basis pair here is `C2`/`Q1` (see Assumption 2).

## Description of program

Self-test the variable definitions against the hand-worked specification (Assumption 12),
then: read the filtered DMR file; restrict to external outfalls, monthly-average
statistical base, and the `Q1`/`C2` basis pair; date rows by monitoring-period-end month
and clip to the FY window; de-duplicate (latest version, then exact duplicates); drop
permits whose outfalls carry multiple limit sets; derive `has_limit` / `exceeds` /
`censored` and join NODI activity classes; route permits to facilities with the shared
crosswalk; compute the 20 variables in two stages (outfall level, then facility-month);
left-join onto the panel spine; apply the coverage and fill rules; write.

## Decisions and Assumptions

Numbered to match the `LABELED ASSUMPTIONS` block in the script itself.

**There is no coverage-flag column.** A facility-month is covered **iff**
`N_OUTFALL_BASIS_TOTAL` is non-`NA` — verified bit-for-bit identical to the flag that
used to exist, since every covered facility-month has `N_OUTFALL_BASIS_TOTAL >= 1` and
every uncovered one is `NA` in all 28 variables. Filter covered rows with
`!is.na(N_OUTFALL_BASIS_TOTAL)`.

1. **One fiscal year; absence is `NA`, not `0`.** Every variable is `NA` outside
   FY2017 *and* inside it where no DMR report exists. This is **deliberately unlike
   step 06**, where a missing violation record genuinely means zero violations. A
   facility that filed nothing did not measurably discharge zero.
2. **Grain = outfall × basis × month, so the statistical base must be fixed.** A
   monthly-average row and a daily-maximum row for the same outfall-month are different
   statistics and cannot share a cell, so `STATISTICAL_BASE_CODE == 'MK'`. `VALUE_TYPE_CODE`
   encodes concentration-vs-quantity and a slot number, **not** a statistic — established
   empirically in `code/dmr/value_type_vs_statistical_base.R`. Restricting to the `Q1`/`C2`
   average pair guarantees at most one row per outfall-basis-month before Assumption 4.
2b. **Both `1` and `EG` are "Effluent Gross", and a third code `Y` is excluded.** Per
   EPA's [ICIS-NPDES DMR Data Element Dictionary](https://echo.epa.gov/node/206),
   `MONITORING_LOCATION_CODE` has three Effluent Gross variants: `1` Effluent Gross,
   `EG` Effluent Gross, `Y` Effluent Gross (Supplementary). The dictionary also explains
   why one outfall can carry two: *"One parameter may have several monitoring location
   requirements pertaining to the same permitted feature."*
   - `1` and `EG` are both **kept** (`F_MONLOC <- c("1", "EG")`), matching the upstream
     filter. FY2017: 352,990 rows coded `1`, 1,101 coded `EG`; in this step's final grain,
     105,613 and 72. They never collide — zero (permit, outfall, month, basis) keys carry
     both — so keeping both cannot double-count. Filtering `== "1"` would silently delete
     `MT0022641` entirely (it uses only `EG`) and an outfall of `MD0002399`.
   - `Y` is **excluded** by the upstream filter, and verified harmless: of 1,433 FY2017 TSS
     `Y` rows across 112 permits, exactly **one** is in scope (`KS0042722`), and that
     outfall-month-basis is already present under code `1` — i.e. it duplicates a primary
     measurement, which is what "Supplementary" means. For other parameters or statistical
     bases the `Y` volume is large enough to need rechecking.
   - A guard written as `== "1"` instead of `%in%` fired on this step's first run, which is
     how the second code was found. `MONITORING_LOCATION_CODE` is carried into the grain
     intermediate so the choice stays auditable.
3. **"Outfall" means external outfall** (`PERM_FEATURE_TYPE_CODE == 'EXO'`). Monitoring
   location 1 still admits internal outfalls (`INO`) and other feature types; counting
   those would double-count the same water on its way out. Outfall **identity** is
   `(permit, PERM_FEATURE_NMBR)` — the outfall number is only unique within a permit.
4. **Permits with multi-limit-set outfalls are dropped whole.** A residual duplicate on
   (permit, outfall, month, basis) after version de-dup means two or more `LIMIT_SET_ID`s
   govern the same cell. No settled collapse rule exists (the open `needs_rule` question
   in `data/processed/fy2017_tss_*_multiset_*.csv`), and every sum, count and ratio
   depends on the choice — so per decision 2026-10-07 the whole **permit** is dropped
   rather than collapsed under a guess. A facility holding a dropped permit gets `NA`
   for the whole facility-month (flagged `DMR_TSS_DROPPED_MULTISET`), never a partial
   total — a facility can hold several permits, and silently summing the survivors
   would understate its discharge without saying so. Every dropped permit is logged to
   `output/tables/`, so the decision is reversible.

   **Measured cost on FY2017, at three different grains — they are not interchangeable:**

   | Grain | Dropped | Share |
   |---|---|---|
   | outfall-basis-month DMR rows | 10,857 of 116,610 | 9.31% |
   | permits | 148 of 4,309 | 3.43% |
   | **facility-months (the panel's own grain)** | **1,740 of 49,134 potentially coverable** | **3.54%** |
   | **facilities** | **145 of 4,195** | **3.46%** |

   **The panel-level cost is ~3.5%, not 9.31%.** The DMR-row share is inflated because the row
   count balloons *below* the panel's grain and is collapsed away by aggregation: `LA0043982`
   has ONE outfall governed by 16 limit sets, which is many DMR rows but still only 12
   facility-months. Use 9.31% to describe how much raw measurement data was discarded, and
   3.54% to describe how much of the analysis sample is lost.

   **What the dropped permits have in common is complexity, not size.** The median dropped
   permit has 1 outfall — the same as the median kept permit — and 95 of the 148 are
   single-outfall. The distinguishing feature is many limit sets on few outfalls (mean 73.4
   DMR rows per dropped permit vs 25.4 per kept one), with a few genuine giants pulling the
   mean (`MT0023965`: 144 outfalls, 467 limit sets). So the exclusion is of
   *conditionally-permitted* facilities, not of large ones.

   **`DMR_TSS_DROPPED_MULTISET` is therefore not missing-at-random**, and the bias is toward
   simply-permitted facilities: a plant with 16 conditional TSS limits is plausibly a different
   kind of regulated entity than one with a single flat limit. Results on the covered sample
   are results about simply-permitted facilities unless that flag is tested against.
5. **Standard units only**, never the raw `*_NMBR` columns (permit-specific units, not
   comparable across outfalls). **Units caveat:** `Q1` is **kg/d** — a daily-average
   *rate*, not a monthly mass. Summing a rate across outfalls is legitimate (rates are
   additive), but `MASS_DISCHARGED_TOTAL` is in kg/d and must not be read as kilograms.
   No multiplication by days-in-month happens anywhere.
6. **Exceedance is `reported > limit`.** Safe for TSS because its numeric limits are
   near-uniformly `<=` ceilings (`docs/data_issues.md`); the script **asserts** this and
   stops on any floor (`>=`) qualifier rather than mis-signing it. Two exceedance counts
   are kept separate on purpose: `N_*_EXCEED_CALC` (ours) and `N_*_EXCEED_EPA`
   (`VIOLATION_CODE == 'E90'`). Disagreements are written to `output/tables/` and
   reported, **not reconciled**.
7. **Censored values are taken at face value.** A `<` row reports the *detection limit*,
   not the discharge, so `MASS_DISCHARGED_*` is an **upper bound** for those outfalls.
   We use the reported number as-is (EPA's own `E90` convention) and expose
   `N_OUTFALLS_CENSORED_MASS` / `_CONC` so the sensitivity is boundable.
8. **NODI classes live in a reference table, not in code.** `N_OUTFALLS_ACTIVE` needs to
   know which "no data" reasons still imply a live outfall, so
   `data/raw/reference/REF_NODI.csv` carries all 33 EPA codes with a curated
   `NODI_ACTIVITY_CLASS` (`active` / `no_discharge` / `inactive` / `no_data_admin` /
   `unclear`). Six codes are genuine judgment calls — `4` (discharge to
   lagoon/groundwater), `7` (no influent), `I` (land applied), `J` (recycled closed
   system), `K` (natural disaster), `W` (dry well): discharging-but-elsewhere versus
   not-operating. They are left `unclear` and counted in
   `N_OUTFALLS_NODI_UNCLASSIFIED` rather than forced into or out of the active count.
   Change a classification by editing one cell of that CSV. The script **stops** if the
   data contains a code the reference lacks. Note `B` (Below Detection Limit) is classed
   **active**, not no-discharge: the outfall is discharging, below the measurable floor.
9. **Multi-month reports are dated to their period-end month, not spread backwards**
   (`docs/panel_questions_for_pis.md`). `N_OUTFALL_BASIS_MULTIMONTH` makes their presence
   visible per facility-month rather than hidden.
10. **Empty-denominator averages are `NA`, not `0`.** The paired count column carries the
    information, keeping "no exceedances occurred" distinct from "exceedances averaged
    zero" — which matters for any regression on the average. `MASS_EXCEED_TOTAL` is the
    exception: it is a sum, so an empty set legitimately gives `0`.
11. **Routed by `NPDES_ID` via the same crosswalk as steps 02/04/05/06**
    (`build_facility_crosswalk()`: `FACILITY_UIN` when present, else the `NPDES_ID`),
    then aggregated across all of the facility's permits. Facility-months present
    in the DMR data but **absent from the panel spine** drop in the join — the panel's
    membership is narrower than "ever-major individual permit" (step 01 also requires a
    permit window overlapping 2005–2025 or independent proxy evidence). FY2017: **1,073
    facility-months across 95 facilities, 1,984 outfall-basis rows.** Same behaviour as
    step 06, but counted in the run log rather than assumed away.
12. **The specification is executable.** The requested variable list came with a
    hand-worked example, so that example runs as a `stopifnot()` fixture through the same
    `summarise_dmr_outfall_basis()` function the real data uses, before any file is read.
    If a definition drifts, the script fails instead of producing quiet nonsense.

13. **Negative reported values are surfaced, not corrected.** FY2017 contains **8 rows
    across 2 facilities** (`WY0000418`, `OH0001872`) reporting a negative TSS mass or
    concentration — physically impossible. They are counted in
    `N_OUTFALL_BASIS_NEGATIVE`, written in full to `output/tables/`, and otherwise left
    exactly as reported: dropping or zeroing them would hide a real data-quality problem
    (the class `code/dmr/eff_flagged.R` exists to catch), and what to do about them is a
    research decision, not this script's. They drag `MASS_RATIO_POOLED` /
    `CONC_RATIO_AVG` below zero in 8 facility-months; excluding them leaves the mass
    ratio in `[0, 22.155]` and the concentration ratio in `[0, 17.667]`.

## Output columns (29)

### The 20 requested variables (23 columns)

| # | Column | Definition |
|---|---|---|
| — | `N_OUTFALLS_TOTAL` | distinct outfalls reporting at all. **Not** `max(#3,#4)` and **not** `#3+#4` — 33,789 of 69,737 FY2017 outfall-months report only one basis, so the per-basis counts bound the outfall count from neither side. Supplied because #21 and #22 are counts of distinct outfalls and are uninterpretable without their denominator. |
| 3 | `N_OUTFALLS_MASS` | distinct outfalls with a `Q1` row |
| 4 | `N_OUTFALLS_CONC` | distinct outfalls with a `C2` row |
| 5 | `N_OUTFALLS_NOLIMIT_ALL` | outfalls where **every** basis reported has no numeric limit |
| 6 | `N_OUTFALLS_NOLIMIT_ANY` | outfalls with **≥1** reported basis lacking a numeric limit |
| 6b | `N_OUTFALL_BASIS_NOLIMIT` | outfall-basis cells with no numeric limit |
| 6b | `N_OUTFALL_BASIS_TOTAL` | outfall-basis cells in total (the denominator) |
| 7 | `MASS_DISCHARGED_TOTAL` | Σ discharge over **all** `Q1` rows, kg/d |
| 8 | `MASS_DISCHARGED_LIMITED` | Σ discharge over `Q1` rows carrying a limit, kg/d |
| 9 | `MASS_PERMITTED_TOTAL` | Σ limit over `Q1` rows carrying a limit, kg/d |
| 10 | `MASS_RATIO_POOLED` | `MASS_DISCHARGED_LIMITED / MASS_PERMITTED_TOTAL` — a **ratio of sums** |
| 10b | `MASS_RATIO_AVG` | mean of per-row discharge/limit over limited `Q1` rows — an **average of ratios** |
| 11 | `N_MASS_EXCEED_CALC` | `Q1` rows where discharge > limit (our test) |
| 12 | `MASS_EXCEED_TOTAL` | Σ(discharge − limit) over exceeding `Q1` rows; `0` when none |
| 13 | `MASS_EXCEED_AVG_PROP` | mean of (discharge − limit)/limit over exceeding `Q1` rows |
| 14 | `N_MASS_EXCEED_EPA` | `Q1` rows with `VIOLATION_CODE == 'E90'` |
| 15 | `CONC_RATIO_AVG` | mean of per-row discharge/limit over limited `C2` rows |
| 16 | `CONC_EXCEED_AVG_PROP` | mean of (discharge − limit)/limit over exceeding `C2` rows |
| 17 | `N_CONC_EXCEED_CALC` | `C2` rows where discharge > limit (our test) |
| 18 | `N_CONC_EXCEED_EPA` | `C2` rows with `VIOLATION_CODE == 'E90'` |
| 19 | `N_OUTFALLS_CENSORED_MASS` | distinct outfalls with a censored (`<`) `Q1` row |
| 20 | `N_OUTFALLS_CENSORED_CONC` | distinct outfalls with a censored (`<`) `C2` row |
| 21 | `N_OUTFALLS_NO_DISCHARGE` | outfalls where **every** basis is a confirmed zero (reported `0`, or NODI `C`) |
| 22 | `N_OUTFALLS_ACTIVE` | outfalls with discharge > 0 on any basis, **plus** no-discharge outfalls whose NODI class is `active` |

> **Why #10 and #15 are asymmetric, on purpose.** Mass is additive across outfalls;
> concentration is not (`docs/panel_questions_for_pis.md`, "Concentrations aren't additive
> across outfalls"). So the mass ratio pools numerator and denominator, while the
> concentration ratio averages per-outfall ratios. `MASS_RATIO_AVG` is supplied as the
> explicit mass-side counterpart so that #10's original "avg ratio" label is never
> ambiguous about which was computed.

### Bookkeeping columns (6)

| Column | Definition |
|---|---|
| `DMR_TSS_DROPPED_MULTISET` | `1` if ≥1 of the facility's in-scope permits was dropped under Assumption 4 |
| `N_OUTFALLS_NODI_UNCLASSIFIED` | outfalls that cannot be classified active/inactive because their only signal is one of the six `unclear` NODI codes |
| `N_OUTFALL_BASIS_MULTIMONTH` | cells whose `NMBR_OF_REPORT > 1` (Assumption 9) |
| `N_OUTFALL_BASIS_UNEXPLAINED_BLANK` | cells with neither a value nor a NODI code — genuinely unexplained (599 in FY2017) |
| `N_OUTFALL_BASIS_NEGATIVE` | cells reporting a **negative** TSS mass or concentration — physically impossible, kept as reported (Assumption 13). Condition on `== 0` to exclude. |

## Instructions to run

```bash
# prerequisite, once per fiscal year (~45 min)
Rscript code/dmr/filter_dmr_major_individual.R 2017
Rscript code/dmr/filter_dmr_00530.R 2017
Rscript code/dmr/filter_dmr_monloc1.R 2017

# this step (seconds to low minutes)
Rscript code/03_panel_building/07_add_dmr.R
```

Not wired into `run_all.R`: it depends on those manually-run filter steps and on a single
fiscal year, so including it would make the full rebuild silently depend on a 45-minute
DMR stream for one year of coverage.

## Notes / edge cases

- **The coverage fraction is small by construction.** The panel spans 2005–2025; FY2017
  is 12 months of it, and within those months only facilities with a major individual
  permit that actually reported TSS at an external outfall on a monthly-average basis are
  covered. Treat `!is.na(N_OUTFALL_BASIS_TOTAL)` as the analysis sample, not the panel.
- **`DMR_TSS_DROPPED_MULTISET` is not missing-at-random.** It flags larger, multi-outfall,
  multi-limit-set facilities. Any analysis restricted to covered rows is conditioning on
  a non-random subset; see Assumption 4.
- **`MASS_*` are kg/d rates, not kilograms** (Assumption 5). Converting to a true monthly
  mass needs a days-in-month multiplication that this script deliberately does not do.
- **Discharge sums are upper bounds where censoring occurs** (Assumption 7).
## Measured run (2026-10-07)

| Stage | Rows / count |
|---|---|
| filtered DMR file read | 354,091 |
| − not `EXO` | −15,179 → 338,912 |
| − `STATISTICAL_BASE_CODE != MK` | −212,222 → 126,690 |
| − `VALUE_TYPE_CODE` not `Q1`/`C2` | −10,080 → **116,610 in scope** |
| unparseable dates / outside FY2017 | 0 / 0 |
| − superseded versions | 0 (the filtered file already carries one version per key) |
| − exact duplicate rows | −68 |
| multi-limit-set keys | 3,004 of 111,066 (**2.70%**) |
| **permits dropped whole** (Assumption 4) | **148 of 4,309 (3.43%)** |
| **rows lost to that drop** | **10,857 (9.31% of in-scope rows)** |
| facilities flagged → `NA` | 148 |
| clean outfall-basis-month rows | **105,685** (6,501 outfalls, 4,146 facilities) |
| facility-months in DMR but off the panel spine | 1,073 (95 facilities, 1,984 rows) |
| **covered facility-months** | **47,394** (4,050 facilities × 12 months) = 2.50% of the 1,897,560-row panel |
| panel columns | 59 → 88 (29 new) |

Measured results on the covered rows:

- `MASS_DISCHARGED_TOTAL` summed: 9,831,349 kg/d against `MASS_PERMITTED_TOTAL` 52,706,201 kg/d
- median `MASS_RATIO_POOLED` 0.094, median `CONC_RATIO_AVG` 0.200 — the typical covered
  facility-month discharges well under its limit
- mass exceedances 272 (ours) vs 269 (EPA `E90`); concentration 451 vs 438
- **24 row-level exceedance disagreements of 105,685** (0.02%), written to
  `output/tables/dmr_fy2017_exceed_disagreements_*.csv` — reported, not reconciled
- 270 covered facility-months carry ≥1 mass exceedance, 438 ≥1 concentration exceedance
- 14,335 of 103,689 outfall-basis cells have no numeric limit
- limit qualifiers on numeric limits: 91,274 `<=`, 2 `<` — no floors, so the
  Assumption-6 ceiling assertion holds for FY2017
- censored outfall-months: 2,135 mass / 3,262 concentration (Assumption 7)
- 599 unexplained blank cells; 1,796 multi-month cells; 8 negative values

### Independent verification performed

- The hand-worked specification runs as a 25-value `stopifnot()` fixture on every run — passes.
- All 59 pre-existing panel columns are **byte-identical** to step 06's output.
- Panel row count unchanged (1,897,560); facility-month keys unique.
- No variable is populated where an uncovered facility-month; flagged facilities are never covered.
- Coverage is confined to exactly the 12 FY2017 months.
- **Row accounting balances exactly**: 103,689 covered + 12 in flagged facilities +
  1,984 off-spine = 105,685 grain rows.
- Monotonic invariants hold: `NOLIMIT_ALL ≤ NOLIMIT_ANY`, `DISCHARGED_LIMITED ≤
  DISCHARGED_TOTAL`, `BASIS_NOLIMIT ≤ BASIS_TOTAL`, `MASS`/`CONC`/`ACTIVE +
  NO_DISCHARGE` ≤ `TOTAL`, `CENSORED_* ≤` its basis count.
- `MASS_RATIO_POOLED` is `NA` exactly when `MASS_PERMITTED_TOTAL == 0`;
  `*_EXCEED_AVG_PROP` is `NA` exactly when the exceedance count is 0.
- **One facility-month was independently re-derived by hand** from the grain
  intermediate across 16 variables — every value matches.
- Every negative-driven ratio carries `N_OUTFALL_BASIS_NEGATIVE > 0`.

Further notes in `docs/running_notes_on_open_questions.md` under the dated entry.

## References

- `docs/panel_questions_for_pis.md` — DMR date field, `NMBR_OF_REPORT`, outfall aggregation
- `docs/data_issues.md` — `LIMIT_VALUE_QUALIFIER_CODE` uniformity for TSS
- `code/dmr/value_type_vs_statistical_base.R` — why `VALUE_TYPE_CODE` is a basis, not a statistic
- `code/dmr/README.md` — the row-filter pipeline that produces this step's input
- [EPA DMR NODI codes](https://www.epa.gov/system/files/documents/2022-10/EPA%20DMR%20NODI%20CODES.pdf)
