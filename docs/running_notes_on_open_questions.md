# Running Notes on Open Questions

Running notes on data quirks, analytical decisions, and findings.

## Data Quality Issues

### Effluent violations file (2026-07-14)
- **Zip filename has a non-ASCII byte.** `npdes_eff_downloads … .zip` contains a
  non-breaking narrow space (U+202F, bytes `e2 80 af`) between the time and "PM".
  System `unzip` fails to open it; `tar`/`bsdtar` (libarchive) works. Passing the
  path through R's `system()` fails to translate to the session locale, so the
  build script keeps the name out of the shell string (cd into `data/raw` + an
  ASCII glob). Never hardcode this filename — match by pattern.
- **The CSV is a zip64 archive, ~16 GB uncompressed** (16,284,937,729 bytes exactly, per
  `unzip -l`). Too large for whole-file
  `fread` on this 8 GB machine; read out-of-core with DuckDB (see below).
- **A head sample of this file is NOT representative.** The first ~3 M rows are all
  D80/D90 (sorted, no E90). The resubmission de-dup rate looked like ~0.3% there
  but is **4.31% on the full file** — always verify counts on the full data.

### Negative TSS values in the FY2017 DMR (2026-10-07)
Found while building step 07. **8 rows across 2 facilities report a NEGATIVE TSS mass or
concentration** in the FY2017 majors/individual/TSS/effluent-gross/monthly-average slice:
- `WY0000418`, feature `SUM`, 2017-09: mass −2,661.30 kg/d against a 730 limit
- `OH0001872`, outfall `099`: seven consecutive months (Nov 2016 – Aug 2017) of negative
  concentrations, −0.75 to −4.20 mg/L, against a 5 mg/L limit. The persistence over seven
  months suggests a systematic sign or data-entry problem at that outfall, not a one-off.

Physically impossible, and they drag `MASS_RATIO_POOLED` / `CONC_RATIO_AVG` below zero in
8 facility-months. **Not corrected or dropped** — counted in `N_OUTFALL_BASIS_NEGATIVE`
and written to `output/tables/dmr_fy2017_negative_values_*.csv`. Excluding them leaves the
mass ratio in `[0, 22.155]` and the concentration ratio in `[0, 17.667]`. Same class of
problem `code/dmr/eff_flagged.R` exists to catch; **open question for the PIs**: drop,
treat as zero, or treat as missing?

### `MONITORING_LOCATION_CODE` has THREE "Effluent Gross" codes (2026-10-07, sourced 2026-10-08)
**Authoritative source: EPA's [ICIS-NPDES DMR Data Element Dictionary](https://echo.epa.gov/node/206)**
(the code list is inline on that page; verified against the raw HTML, not a paraphrase).
`MONITORING_LOCATION_CODE` is defined there as *"The code that the monitoring location at
which the monitoring requirement (and effluent limit if limited) applies. One parameter may
have several monitoring location requirements pertaining to the same permitted feature."*
Three of its values mean Effluent Gross:

| Code | Description | Treatment |
|---|---|---|
| `1` | Effluent Gross | **kept** |
| `EG` | Effluent Gross | **kept** |
| `Y` | Effluent Gross (Supplementary) | **excluded** |

- `code/dmr/filter_dmr_monloc1.R` keeps `1` and `EG` (its inline comment asserting this is
  now confirmed against the dictionary above). FY2017 TSS: 352,990 rows `1`, 1,101 `EG`.
- **`1` and `EG` never collide**: zero (permit, outfall, month, basis) keys carry both, so
  keeping both cannot double-count. The dictionary's "several monitoring location
  requirements" sentence explains the coexistence — e.g. `TN0062499` outfall 001 codes its
  mass slot `1` and its concentration slot `EG` within one limit set.
- **Filtering `== "1"` silently deletes facilities.** `MT0022641` uses only `EG` (12 months
  × both bases of real values against real limits) and would vanish entirely, looking
  identical to a non-reporter; `MD0002399` would lose outfall 104. Clustered by state
  (MD/MT/TN), so the loss is not spread thin. A too-narrow filter on this field raises no
  error — a guard written `== "1"` in `07_add_dmr.R` is the only reason this surfaced.
- **`Y` is excluded and that is verified harmless** for this scope: of 1,433 FY2017 TSS `Y`
  rows across 112 permits, exactly **one** is in scope (`KS0042722`), and its
  outfall-month-basis is already present under `1` — a duplicate of a primary measurement,
  as "Supplementary" implies. The other 1,432 are out of scope for unrelated reasons
  (1,080 are statistical base `AB` not `MK`, 108 are internal outfalls, etc.). **For a
  different parameter or statistical base the `Y` volume is big enough to recheck.**
- `MONITORING_LOCATION_CODE` is carried into
  `data/processed/dmr_fy2017_tss_effgross_mk_outfall_basis.csv` so this choice is auditable
  and a sensitivity test is one line.


## Analytical Decisions

### Effluent-violations NPDES_ID × month panel (2026-07-14; rebuilt in-repo 2026-07-27)
Produces `data/processed/effluent_violations_npdes_month_panel_2005_2025.csv`.
**Update 2026-07-27:** this file's producing script now lives in this repo --
`code/02_cleaning/build_effluent_violations_npdes_month_panel.R` (moved again,
same day, from `code/03_panel_building/` to `code/02_cleaning/`, per request --
path-only, no logic change) -- and `run_all.R` builds it automatically if it's
missing (it's a prerequisite for steps 01 and 06, not an optional step). The
rebuild also folds in the TSS
gross-effluent-subset counts (`N_TSS_EFF_VIOLATIONS`/`_D90`/`_D80`/`_E90`) that
`06_add_effluent_violations.R` used to compute separately via a second,
python3-driven stream of the raw file -- both count sets are now produced in
one pass. Columns: `NPDES_ID, month, n_D80, n_D90, n_E90, N_TSS_EFF_VIOLATIONS,
N_TSS_EFF_D90, N_TSS_EFF_D80, N_TSS_EFF_E90`. The original all-parameter
construction logic below is unchanged.
- **Month** = calendar month of `MONITORING_PERIOD_END_DATE` (the DMR reporting
  period), not detection or receipt date.
- **Codes** live in `VIOLATION_CODE` (D80, D90, E90); one distinct-count column each.
- **Scope** = observed ID-months only. No zero-filled grid: a missing
  `NPDES_ID × month` means no D80/D90/E90 that month, not a measured zero.
- **Counting** = distinct underlying violation, latest `VERSION_NMBR` only, to drop
  DMR resubmissions. Implemented as `COUNT(DISTINCT vkey)` where `vkey` =
  NPDES_ID + perm feature + limit-set + monitoring location + parameter +
  statistical base + monitoring-period date; this is provably identical to a
  row_number() latest-version dedup for counts, and avoids a DuckDB internal
  planner bug in `row_number() OVER (PARTITION BY …)`.
- **Caveat (not corrected):** counts are over rows already filtered to the three
  codes, so a period corrected to compliant in a later version is not netted out.
- **Engine:** DuckDB out-of-core (5 GB mem cap + disk spill); the zip member is
  streamed to a ~3.9 GB gzip temp once, then parsed. ~15 min end to end.

### FY2025 DMR TSS/effluent-gross/monthly-avg filter moved into repo (2026-07-27)
Script: `code/dmr/filter_dmr_fy2025_exo_00530_effgross_monthlyavg.R` (moved from the
external EIL Summer working folder, same precedent as the effluent panel above; an
untouched copy remains there). Produces
`data/processed/dmr_fy2025_exo_00530_effgross_monthlyavg.csv` — the input
`code/dmr/filter_dmr_fy2025_effgross_major_individual.R` restricts to major/individual
permits. Not part of `code/03_panel_building/` or `run_all.R`; a manually-run
mini-pipeline (see `code/README.md`).
**Update 2026-07-27 (later same day):** both scripts moved again, from a root-level
`build/` folder (now removed) into `code/dmr/`, alongside this repo's other
DMR-specific summary/diagnostic scripts — path-only, no logic change.
- **No path changes needed.** The script already used this repo's exact `_paths.R`
  constants (`DMR_DIR`, `PROC_DIR`) and portable header, unlike the effluent panel
  script, which needed real adaptation.
- **Verified by running it end to end from its new location:** 754,033 rows, 34,797
  distinct permits, 57/57 columns, zero filter-violation rows, internal assertions
  (`n_param`/`n_feat`/`n_stat` each `== 1`) passed. ~24.5 min wall time (~9.68 GB raw
  file streamed once).

### `FACILITY_OPERATING` correction — step 07 (2026-07-23)
Script: `code/03_panel_building/07_extend_facility_operating.R` →
`data/processed/07_facility_month_panel_major_individual_operating_corrected_2005_2025.csv`
(new final panel; superseded `06_..._effluent_2005_2025.csv`, which remains on disk
unchanged).
- **Trigger:** a direct question about whether `FACILITY_OPERATING == 0` (hence `NA`
  count columns) could be mislabeling facilities that were genuinely operating but just
  quiet that month.
- **Measured on the 06 panel:** 12.66% of `FACILITY_OPERATING == 0` rows (32,033 of
  253,028) carried a real recorded event anyway. 75.9% of those are >12 months outside
  the computed window (median 31, max 250 months) — not boundary noise. 2,381 of 7,511
  facilities (32%) affected: 2,132 close-side, 413 open-side.
- **Root cause:** permits with `PERMIT_STATUS_CODE == "ADC"` (Administrative
  Continuance) have `EXPIRATION_DATE` read as a real closing date by script 01 even
  though `ADC` means the permit is still legally active pending renewal. Confirmed on
  facility `110006619212` / permit `NH0100455`. 86.7% of the 8,007 permits linked to
  this panel's facilities carry `ADC` status at some point. This was already flagged as
  a general risk in `docs/data_issues.md` (the `PERMIT_STATUS_CODE`/`EXPIRATION_DATE`
  row) before it was confirmed to actually be realized in the built panel.
- **Fix:** extend each facility's window (both directions, per PI decision) to
  `min/max(computed window, first/last month with a real recorded event)`; fill
  previously-NA count columns with `0` in the newly-covered months. Never shrinks a
  window. `FACILITY_OPERATING` in the new file carries the corrected value; the
  original is preserved as `FACILITY_OPERATING_PERMIT_WINDOW`.
- **Verified:** full column diff against the 06 panel shows zero illegal changes —
  every altered cell is exactly a blank/NA → 0 fill, every other column byte-identical.
  109,823 rows flip `FACILITY_OPERATING` 0→1; 3,772,636 NA→0 fills. Self-check (no
  `FACILITY_OPERATING==0` row may carry a real event after correction) passes and is a
  mathematical guarantee of the construction, not just an empirical result.
- **Not yet regenerated:** `06_facility_month_panel_major_individual_effluent_fy2025.csv`
  (the FY2025 row-filter) still reflects the pre-correction 06 panel.

### `FACILITY_OPERATING` correction relocated into step 01 (2026-07-23)
Per request, step 07 above was retired and its logic folded directly into
`code/03_panel_building/01_build_facility_month_panel_major_individual.R`
(Assumptions 10–13 there). The findings and numbers in the entry above are unchanged
and still accurate — only *where* the correction runs changed, not what it does or
what it produces.
- **Why this was possible:** the correction only ever needed event *existence*
  (whether/when a facility had any real event), not the full detailed counts steps
  02/04/05/06 compute — so it doesn't actually need to wait until step 06 finishes.
  Verified empirically first: zero facility-months have a positive TSS-subset
  violation while the condensed all-parameter effluent panel shows nothing, so step 01
  can use just the condensed panel and skip streaming the raw 16 GB effluent file
  entirely (no `python3`/`unzip` needed in step 01).
- **Bug caught and fixed during the move:** an early version of the relocated logic
  derived its event-routing crosswalk from `01`'s own individual/major-restricted
  facility table, rather than a full, unrestricted `ICIS_FACILITIES` read (as
  02/04/05/06 each independently do) — this silently dropped events recorded under a
  qualifying facility's *other* (general/minor) permits, undercounting the correction
  (2,305 facilities extended instead of 2,381). Fixed by reading `ICIS_FACILITIES` a
  second, unrestricted time inside step 01.
- **Verified:** the new panel — `06_facility_month_panel_major_individual_effluent_2005_2025.csv`,
  rebuilt via a full 01→06 run — is **byte-for-byte identical** (full column diff,
  zero differences) to the retired step-07 output. Final counts unchanged: 2,381
  facilities extended, 1,749,567 operating / 143,205 not.
- `07_extend_facility_operating.R` and its README were deleted; the file
  `07_facility_month_panel_major_individual_operating_corrected_2005_2025.csv` remains
  on disk as an orphaned, superseded artifact (see `data/processed/README.md`).

**Update 2026-07-27: the correction's scanning/extension logic factored out into
`use_operating_proxies.R`.** What used to be step 01's Assumptions 10–13 (STEP 6B/6C,
written inline) is now one function, `use_operating_proxies()`, in its own file
(`code/03_panel_building/use_operating_proxies.R`), with an on/off switch per proxy
source (all seven default `TRUE`, reproducing this same correction exactly — verified
via an isolated side-by-side run of the old inline code and the new function on
identical input, `identical()` for every facility). Step 01's own header is now just
Assumptions 1–9 (unchanged) plus a single Assumption 10 pointing here; all the
measured evidence, root cause, and worked example above now live in
`use_operating_proxies.R`'s header instead of being duplicated in both places.
Purely a refactor — reasons: (1) letting a different mix of evidence be tried without
editing script 01 itself, (2) not duplicating a large block of explanation across two
files that were drifting out of sync with each other's edits.

**Update 2026-07-28: `USE_PROXIES` config flag added, then panel membership itself**
**changed from permit-dates-only to permit-window-overlap OR proxy evidence.** Two
separate changes, same day:
- A single `USE_PROXIES` flag (default `TRUE`) now feeds all seven `use_operating_
  proxies()` switches at once — `FALSE` skips the proxy scan entirely (permit-
  paperwork dates only, ~45% faster since no proxy source is read).
- Per request: previously, a facility whose permit-paperwork window didn't overlap
  2005–2025 was dropped from the panel entirely, before `use_operating_proxies()`
  ever ran — proxy evidence only widened an *already-admitted* facility's window,
  never granted admission on its own. Now a facility is admitted if EITHER its
  permit window overlaps 2005–2025 OR it has independent proxy evidence anywhere in
  that range (step 01's new Assumption 1B). Required restructuring the eligibility
  test to run on the raw, unclipped permit dates (not the panel-clipped ones, which
  would otherwise always "overlap" once clipped to the boundary) and moving the
  proxy scan earlier, against the full candidate population rather than an
  already-filtered one.
- A new third column, `FACILITY_OPERATING_PROXY_WINDOW`, exposes the proxy-only
  bounds `use_operating_proxies()` was already computing internally (previously
  discarded before returning, used only as a step toward the union). For a
  proxy-only-admitted facility, `FACILITY_OPERATING_PERMIT_WINDOW` correctly reads
  0 for every month (a genuine zero, not NA), and `FACILITY_OPERATING` collapses to
  exactly `FACILITY_OPERATING_PROXY_WINDOW`.
- **Verified** (full 01→06 rebuild): of 7,531 "ever major, ever individual"
  candidates, 7,514 have permit-window overlap, 16 are admitted solely via proxy
  evidence, 1 is dropped (neither) — final population 7,530 (was 7,514), panel rows
  1,897,560 (was 1,893,528; +4,032 = 16 × 252 months). Spot-checked facility
  `110000311485`: `FACILITY_OPERATING_PERMIT_WINDOW` 0/252 months,
  `FACILITY_OPERATING_PROXY_WINDOW` well-defined (243/252 operating), `FACILITY_
  OPERATING` matches it exactly everywhere. Re-running with `USE_PROXIES <- FALSE`
  correctly collapses membership back to permit-window-overlap only (7,514
  facilities, 0 admitted via proxy-only) — confirmed, then restored to `TRUE` and
  re-run so the on-disk panel reflects normal default behavior.
- Final panel is now 59 columns (was 58); `FACILITY_OPERATING_PROXY_WINDOW` is
  physical column 9, confirmed via `head -1`. `docs/codebook.md` renumbered
  columns 9–58 → 10–59 accordingly (these are literal physical CSV positions, not
  just documentation ordinals, so the renumbering reflects the real file, not a
  stylistic choice).

### FY2017 DMR discharge & compliance variables — step 07 (2026-10-07)
Script: `code/03_panel_building/07_add_dmr.R` →
`data/processed/07_facility_month_panel_major_individual_dmr_tss_2005_2025.csv`
(59 → 89 columns; step 06's panel untouched). Intermediate at the auditable grain:
`data/processed/dmr_fy2017_tss_effgross_mk_outfall_basis.csv`.

**Trigger:** through step 06 the panel knew only whether a facility was *cited*. It had no
measure of how much was discharged, how much was permitted, or how close to its limit a
facility ran — all of which live only in the DMR files, which the pipeline never opened.

**Four decisions settled (these were open going in):**
1. **Statistical base = `MK` only** (literal Monthly Average). The grain is outfall ×
   basis × month, and a monthly-average row cannot share a cell with a daily-maximum row.
2. **Basis = `VALUE_TYPE_CODE`, restricted to the average pair `Q1` (mass, kg/d) and
   `C2` (concentration, mg/L).** Within `MK`, `C1`/`C3`/`Q2` also occur; including them
   would put two "concentration" rows in one cell. Builds on
   `code/dmr/value_type_vs_statistical_base.R`'s finding that `VALUE_TYPE_CODE` is a
   basis, not a statistic.
3. **Multi-limit-set outfalls → drop the whole PERMIT.** This closes the `needs_rule`
   column in `data/processed/fy2017_tss_*_multiset_*.csv` *by avoidance, not by solving
   it*. 3,004 of 111,066 outfall-basis-month keys (2.70%) are contested.

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

   145 facilities are flagged and forced to `NA` (never a partial total). Every dropped
   permit is logged, so the decision is reversible if a collapse rule is later agreed.
4. **Empty-denominator averages = `NA`, not 0**, with the paired count column carrying
   the information. `MASS_EXCEED_TOTAL` excepted (a sum legitimately gives 0).

**No coverage-flag column** (removed 2026-10-08 per request): a facility-month is covered
**iff** `N_OUTFALL_BASIS_TOTAL` is non-`NA`, which was verified bit-for-bit identical to the
flag it replaced — covered rows always carry `N_OUTFALL_BASIS_TOTAL >= 1` and uncovered rows
are `NA` in all 28 variables, so the flag was exactly redundant. The three distinct reasons a
row is uncovered remain recoverable: outside FY2017 (1,807,200 rows), inside FY2017 with no
DMR report (41,226), and inside FY2017 but dropped by the multi-limit-set rule (1,740,
flagged `DMR_TSS_DROPPED_MULTISET`). Panel is 59 → **88** columns, 29 new.

**Coverage:** 47,394 facility-months (4,050 facilities × 12 months) = **2.50%** of the
1,897,560-row panel. FY2017 is 12 months of a 21-year panel, so
`!is.na(N_OUTFALL_BASIS_TOTAL)` is the analysis sample, not the panel. `NA` here means "no DMR
report", **not** zero discharge — the opposite of step 06's fill rule.

**Headline numbers:** 9,831,349 kg/d discharged against 52,706,201 kg/d permitted;
median `MASS_RATIO_POOLED` 0.094 and median `CONC_RATIO_AVG` 0.200, so the typical covered
facility-month runs well under its limit, with a long right tail (max 22.2× and 17.7×).

**Our exceedance test vs EPA's `E90`:** 272 vs 269 (mass), 451 vs 438 (concentration);
**24 row-level disagreements of 105,685 (0.02%)**, written to
`output/tables/dmr_fy2017_exceed_disagreements_*.csv`. Both counts are kept as separate
columns — reported, not reconciled.

**NODI handling, revised 2026-10-08 — the one judgment call, and its removal.** #21/#22
ask whether an outfall discharged; ~21% of in-scope cells carry a NODI code instead of a
number. The first implementation added a hand-built `NODI_ACTIVITY_CLASS` to
`data/raw/reference/REF_NODI.csv` classifying all 33 codes by whether they implied a live
outfall. **EPA publishes no such mapping** — it was our judgment stored where it read as
source data, and it decided 2,431 outfall-months (4.6%) of `N_OUTFALLS_ACTIVE` on no
documented basis. It also collided with EPA's **own** `Status` column for these codes,
which means *may this code still be filed* — unrelated to discharge, and contradictory in
five cases (`2` Operation Shutdown is EPA-Active while the plant is shut; `5`/`S`/`V`
weather codes are EPA-Inactive while the plant runs).

Retired in favour of reading **exactly one code**: `C`, whose EPA description is verbatim
"No Discharge". Transcription, not interpretation. Every other no-data code leaves the
outfall-month in the new `N_OUTFALLS_UNDETERMINED`.

| Column | Hand-classified | Code `C` only |
|---|---|---|
| `N_OUTFALLS_NO_DISCHARGE` | 15,151 | **15,151** (unchanged — `C` always did the work) |
| `N_OUTFALLS_ACTIVE` | 52,410 | **49,999** |
| residual | 57 | **3,369** |

All 26 other columns byte-identical. Gained a property the old scheme lacked: the three
**partition** `N_OUTFALLS_TOTAL` exactly, asserted each run. Also rejected a stricter
numbers-only rule, which destroys 96.1% of #21 (only 597 outfall-months report a literal
`0`) and strands 26.1% of outfall-months, 14,700 of them carrying a code EPA describes as
"No Discharge".

`REF_NODI.csv` is now a pure EPA transcription — code, description, `EPA_CODE_STATUS` —
sourced from the [ICIS-NPDES DMR Data Element Dictionary](https://echo.epa.gov/node/206)
and cross-checked against the Region 6 PDF; all 33 codes agree exactly. Nothing in it feeds
the logic; it only validates that no unknown code appears. `EPA_CODE_STATUS` is reference
only — 13 codes are retired and 141 FY2017 rows (0.7%) use them, so a code's frequency
changing between fiscal years can be a reporting-convention change, not a behavioural one.

**Column added beyond the requested list:** `N_OUTFALLS_TOTAL`. Discovered during
verification that **33,789 of 69,737 outfall-months report only ONE basis**, so neither
`max(N_OUTFALLS_MASS, N_OUTFALLS_CONC)` nor their sum gives the distinct-outfall count —
and the no-discharge/active counts are uninterpretable without that denominator.
`MASS_RATIO_AVG` was also added: the requested #10 is labelled "avg ratio" but its worked
example is a ratio of sums, while #15's is an average of ratios, so both are supplied.

**Verified:** the hand-worked specification runs as a 25-value `stopifnot()` fixture on
every run; all 59 pre-existing panel columns byte-identical to step 06; panel row count
unchanged and keys unique; nothing populated outside coverage; coverage confined to the 12
FY2017 months; row accounting balances exactly (103,689 covered + 12 flagged + 1,984
off-spine = 105,685 grain rows); all monotonic invariants hold; and **one facility-month
independently re-derived by hand across 16 variables, every value matching**.

**Known limitations, not bugs:** `MASS_*` are kg/d **rates**, not monthly kilograms (no
days-in-month multiplication anywhere); censored (`<`) rows report the detection limit, so
discharge sums are **upper bounds** for 2,135 mass / 3,262 concentration outfall-months;
`DMR_TSS_DROPPED_MULTISET` is **not missing-at-random**; 1,073 facility-months (95
facilities, 1,984 rows) appear in the DMR but not on the panel spine and drop in the join,
because panel membership is narrower than "ever-major individual permit".

## Findings

### Effluent D80/D90/E90 counts, 2005–2025 (2026-07-14)
From the panel above: 2,694,316 ID-months across 121,708 distinct NPDES_IDs, all
252 months present. Raw target rows in window 43,317,821 → 41,451,812 after
latest-version de-dup (**1,866,009 resubmissions removed, 4.31%**). Totals:
D80 = 21,073,782 · D90 = 17,814,134 · E90 = 2,563,896 (sum = 41,451,812, matches
the de-duplicated count).

