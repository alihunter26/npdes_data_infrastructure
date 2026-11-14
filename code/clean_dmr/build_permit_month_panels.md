# README — `build_permit_month_panels.R`

*Builds the baseline and the eight permit-month panels (I–VIII) described in
`CWA_Data_shared/DMR_TSS_panel_building.docx` from the cleaned TSS panel. Input:
`data/processed/clean_dmr_tss_<FY>.csv` (built by `build_dmr_clean_panel.R`). Output: nine CSVs in
`data/processed/`, each one row per permit × `YEAR` × `MONTH` over the same grid, every field text.*

```bash
Rscript code/clean_dmr/build_permit_month_panels.R > output/build_permit_month_panels_fy2009_2025.log
Rscript code/clean_dmr/build_permit_month_panels.R 2017      # any list of FYs
```

No arguments means FY2009–FY2025. A full run takes about 2.5 minutes. The log prints every count
with its denominator and ends with the doc's four summary stats for every panel. The definitions
below are also in the script's header. Numbers in this file were measured on FY2009–FY2025 on
2026-11-09, and the table on 2026-11-13.

## The baseline and the eight panels

Every file has 6,520 permits × 204 months = 1,330,080 permit-months. "Populated" = the panel has a
row for the permit-month. Shares are of 6,520 permits, 1,330,080 permit-months and 2,649,477
cleaned-panel rows.

| File (`dmr_pm…_fy2009_2025.csv`) | Doc | What it populates | Permits, ≥ 1 populated | Permits, all 204 populated | Permit-months populated | Cleaned rows used |
|---|---|---|---|---|---|---|
| `0_baseline` | — | nothing; `RAW_DATA` only | — | — | — (`RAW_DATA` TRUE 1,153,607) | — |
| `1_one_row` | I | permits with only ever one row per month; all their rows | 1,183 (18.1%) | 598 (9.2%) | 190,973 (14.4%) | 190,973 (7.2%) |
| `2_one_row_month` | II | permit-months with exactly one row | 1,953 (30.0%) | 598 (9.2%) | 255,151 (19.2%) | 255,151 (9.6%) |
| `3_one_q` | III | permits with only ever one Q row per month; their Q rows | 4,097 (62.8%) | 2,533 (38.8%) | 721,880 (54.3%) | 721,880 (27.2%) |
| `4_one_q_month` | IV | permit-months with exactly one Q row; that Q row | 4,628 (71.0%) | 2,533 (38.8%) | 782,591 (58.8%) | 782,591 (29.5%) |
| `5_one_c` | V | permits with only ever one C row per month; their C rows | 4,357 (66.8%) | 2,610 (40.0%) | 761,020 (57.2%) | 761,020 (28.7%) |
| `6_one_c_month` | VI | permit-months with exactly one C row; that C row | 5,423 (83.2%) | 2,610 (40.0%) | 862,429 (64.8%) | 862,429 (32.6%) |
| `7_max_ratio` | VII | every permit-month with data; the row with the highest value / limit | 6,520 (100.0%) | 3,997 (61.3%) | 1,153,607 (86.7%) | 1,153,607 (43.5%) |
| `8_aggregate` | VIII | every permit-month with data; one aggregated row | 6,520 (100.0%) | 3,997 (61.3%) | 1,153,607 (86.7%) | 2,649,477 (100.0%) |

In I–VII each populated permit-month holds exactly one cleaned row, so "rows used" equals
"permit-months populated". For VII, every row of the month is compared but only one is kept.

**Columns.**
- **Baseline (8):** `FY`, `FACILITY_ID`, `EXTERNAL_PERMIT_NMBR`, `STATE_CODE`, `YEAR`, `MONTH`,
  `RAW_DATA`, `FLAG_MULTI_MONTH_COVERED`.
- **Panels I–VI (30):** `FY`, the cleaned panel's 26 columns, then `N_ROWS`, `RAW_DATA` and
  `FLAG_MULTI_MONTH_COVERED`.
- **Panel VII (36):** the same 27 for the selected row, then `RATIO`, `SELECTED_BY`, `ROW_STATUS`,
  `N_ROWS`, `RAW_DATA`, `ANY_DISCHARGED`, `NODI_STRING_MONTH`, `FLAG_ZERO_LIMIT_DISCHARGE`,
  `FLAG_MULTI_MONTH_COVERED`.
- **Panel VIII (36):** `N_ROWS`, `RAW_DATA`, row counts, `NODI_STRING`, ratios, violations and
  exceedances, flags, Q totals, averages and `NMBR_OF_REPORT` summaries (list in the script, `P5_COLS`).
- **Until 2026-11-13** the files were `dmr_pm{1_one_row,2_one_q,3_one_c,4_max_ratio,5_aggregate}`,
  with 1–3 balanced over their own permits and no `RAW_DATA`. Apart from `RAW_DATA`, the new III, V,
  VII and VIII are cell-for-cell identical to the old 2, 3, 4 and 5, restricted to the old files'
  permits (checked 2026-11-13). The old 1 was overwritten by the new I under the same name.

## Choices

### What panels I–VI populate

- **Month** = `YEAR`/`MONTH` of `MONITORING_PERIOD_END_DATE`. Every row counts, NODI-only rows included.
- **I, III, V select permits; II, IV, VI select permit-months.**
  - **"Only ever" (I, III, V) is pooled over the whole window.** One month with two rows anywhere
    blanks every month of a permit in panel I; one month with two Q rows does so in panel III;
    likewise C for panel V.
  - **II, IV, VI** populate each permit-month that has exactly one row (II), one Q row (IV) or one C
    row (VI), whatever the permit's other months look like. So I sits inside II, III inside IV and V
    inside VI (asserted), and a permit populates every month of I if and only if it does so in II
    (likewise III/IV, V/VI).
- **Q** = `VALUE_TYPE_CODE` Q1/Q2 (kg/d); **C** = C1/C2/C3 (mg/L). Panels III–VI drop the other basis
  before selecting: a month with one Q row and any number of C rows is populated in IV with its Q
  row. A permit with no Q row ever populates nothing in III or IV; likewise C for V and VI.
- **These are selected samples, not universes.** Panel I leans toward states where permits report
  concentration only. 772 of its 1,183 permits (65.26%) are in the 13 states where at least half the
  permits never report a Q row (measured 2026-11-09).

### Row status (panel VII and the ratios)

Each row of the cleaned panel gets one status:
- `discharged`: a value other than 0. The 46 negative values (10 permits) are kept at face value.
- `no_discharge`: a value of 0, or a blank value with NODI C.
- `below_dl`: a blank value with NODI B.
- `no_report`: anything else.

### Panel VIII's row counts

The four counts add up to `N_ROWS`:
- `N_DISCHARGED`: a value other than 0.
- `N_NO_DISCHARGE`: a value of 0, or NODI C.
- `N_OTHER_NODI`: a blank value with any other NODI code, B included.
- `N_NO_NODI`: a blank value and no NODI code. This is the only kind of blank the data does not explain.

`N_BELOW_DL` counts the B rows (40,071), which sit inside `N_OTHER_NODI`.

### Ratios, selection, exceedances, totals

- **Ratio** = value / limit, only where the limit is above 0.
  - A blank limit gives NA.
  - A 0 limit is left out of every ratio, total and average. A discharge against one sets
    `FLAG_ZERO_LIMIT_DISCHARGE`; there are no cases.
- **Discharging-points ratio:** discharged rows only.
- **All-points ratio:** also counts no-discharge rows as 0, and B rows as 0 while the toggle
  `B_AS_ZERO` is TRUE (the default). The toggle also affects panel VII's selection and
  `TOTAL_DISCHARGED_Q`. In 12,518 permit-months the ratio rests on B rows alone, so with
  `B_AS_ZERO` FALSE it would be NA.
- **Panel VII's selection.** It keeps the row with the highest all-points ratio. If no row in the month
  has a ratio, it falls back in order to: the highest Q value, the highest C value, the first Q row,
  the first C row. Ties go to the first row in the cleaned panel's sort order. `SELECTED_BY` says which
  rule picked the row.
- **Exceedance** = value > limit > 0, with `<` values included. That gives 20,806 rows. EPA fills
  `EXCEEDENCE_PCT` on 20,869 rows: 20,756 are in both, 50 are ours only and 113 are EPA's only.
- **Violations** count codes, so `D90;E90` = 2.
- **Permit-month flags** (`FLAG_MULTI_LIMIT_SET`, `FLAG_MULTI_LIMIT_ID`): set if any row in the month
  carries the row flag.
- **Q totals** sum over the month's Q rows, across outfalls and limit sets. Where the same value is
  repeated under two limit sets, it is counted twice; there are 611 such Q cells.

### Balancing

What the script does (all panels over all permits since 2026-11-13; before that, panels I, III
and V, then numbered 1–3, were balanced over their own permits only):
- **One grid for every panel:** all 6,520 permits in the cleaned panel × every month of the
  requested FYs = 1,330,080 permit-months, whether or not the permit existed then and whether or not
  the panel's rule ever selects it. FY *y* runs from October of *y*−1 to September of *y*, so
  FY2009–FY2025 is 204 months. The nine files share the same keys and merge 1:1.
- **What an empty month holds.**
  - Filled from the permit and the month: `FY`, `FACILITY_ID`, `STATE_CODE`, `YEAR`, `MONTH`.
  - Panels I–VII: the row columns are blank and the two row flags are FALSE. In panel VII,
    `SELECTED_BY` and `ROW_STATUS` are blank too.
  - Panel VIII: the counts are 0, the strings blank, the ratios, totals and averages NA, and the
    flags FALSE.
- **`N_ROWS`, in every panel,** is the number of rows the cleaned panel has for the permit-month,
  across both bases. 0 means nothing was reported.
- **`RAW_DATA`** = `N_ROWS` > 0, so it is the same in every panel and in the baseline: TRUE on
  1,153,607 permit-months. On a blank row it separates the two reasons a month is empty: TRUE means
  the panel's rule dropped the month's rows, FALSE means there were none.
- **`FLAG_MULTI_MONTH_COVERED`** marks a month with nothing reported that lies inside the period of a
  quarterly, semiannual or annual report (`NMBR_OF_REPORT` > 1) dated to a later month. That month is
  not missing data, but its `RAW_DATA` is FALSE. There are 12,104 such months.
- **Where the empty months fall.** Of the 176,473 months with `RAW_DATA` FALSE:
  - 55,603 come before the permit's first month with rows, 91,333 after its last, and 29,537 in
    between.
  - A permit-FY with any has a median of 12, so they mostly come as whole years.
  - Months outside a permit's first-to-last span may be before it was issued or after it ended. This
    has not been checked against ICIS permit dates.

## Using the output

- **Reading.** Read with `colClasses = "character"` and cast deliberately; a blank is not 0.
- **Never pool Q and C.** Panels I and II hold both: a month's only row can be either. Panel VII's
  selected row can also be either, so its value and limit columns mix units; `RATIO` does not.
- **Panel VII's columns describe the selected row only.** Counting on them overstates months with
  nothing on any row. "No value and no NODI code" on the selected row gives 7,401 permit-months; on
  every row of the month it gives 7,370. For limits the figures are 31,251 and 30,436.
- **Panel VIII's counts are row counts,** and rows are not additive within a month: Q and C rows, limit
  sets and outfalls each add rows.
- **Check year-to-year patterns for reporting artifacts.** Missing values are elevated in
  FY2013–FY2017 in panels I, III and V (measured before the rebuild; II, IV and VI unchecked); the
  cause has not been checked.

## What the script asserts

The script stops with an error if any of these fail:
- one row per permit × month in each output;
- no permit-month split across two FY files;
- one facility and one state per permit;
- each balanced panel has permits × months rows, and its months with a row match the unbalanced
  panel's row count;
- I is inside II, III inside IV and V inside VI; II, IV and VI have one populated month per
  cleaned permit-month with exactly one row (one Q row, one C row);
- `RAW_DATA` is TRUE on every populated row, and on the same number of months in every panel;
- panel VIII's four counts add up to `N_ROWS`.

## Open items

- **NODI B.** Should B count as zero discharge? This is the `B_AS_ZERO` toggle above.
- **EPA-only exceedances.** Why does EPA fill `EXCEEDENCE_PCT` on 113 rows our rule does not count
  as exceedances?
- **Negative values.** The 46 negative values are perhaps net-of-intake (unchecked); they are kept as
  discharged.
- **Panel VII's `ROW_STATUS`** still uses the four statuses above, not panel VIII's four-way split.
- **NODI 2, N and 4** (operation shutdown, not constructed, discharge to lagoon or groundwater) may
  mean no discharge. They are counted in `N_OTHER_NODI`.
- **Empty months before a permit's first report or after its last** have not been checked against
  ICIS permit dates.
- **No codebook** for the panels yet. The pre-FY2009 years are not built.
