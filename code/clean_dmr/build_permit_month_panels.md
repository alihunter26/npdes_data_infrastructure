# README — `build_permit_month_panels.R`

*Builds the five permit-month panels described in `CWA_Data_shared/Cleaned_Intermediate_DMR_TSS.docx`
from the cleaned TSS panel. Input: `data/processed/clean_dmr_<FY>.csv` (built by
`build_dmr_clean_panel.R`). Output: five CSVs in `data/processed/`, one row per permit × `YEAR` ×
`MONTH`, every field text.*

```bash
Rscript code/clean_dmr/build_permit_month_panels.R > output/build_permit_month_panels_fy2009_2025.log
Rscript code/clean_dmr/build_permit_month_panels.R 2017      # any list of FYs
```

No arguments means FY2009–FY2025. A full run takes 1.5–3 minutes. The log prints every count with
its denominator. The definitions below are also in the script's header. Numbers in this file were
measured on FY2009–FY2025 on 2026-11-09.

## The five panels

| File (`dmr_pm…_fy2009_2025.csv`) | What it keeps | Permits | Permit-months | With a row |
|---|---|---|---|---|
| `1_one_row` | permits with exactly one row in every month; all their rows | 1,183 | 241,332 | 190,973 |
| `2_one_q` | permits with at most one Q row in every month; Q rows only | 4,097 | 835,788 | 721,880 |
| `3_one_c` | permits with at most one C row in every month; C rows only | 4,357 | 888,828 | 761,020 |
| `4_max_ratio` | every permit; the one row with the highest value / limit | 6,520 | 1,330,080 | 1,153,607 |
| `5_aggregate` | every permit; one aggregated row (counts, ratios, flags, Q totals) | 6,520 | 1,330,080 | 1,153,607 |

**Columns.**
- **Panels 1–3 (29):** `FY`, the cleaned panel's 26 columns, then `N_ROWS` and `FLAG_MULTI_MONTH_COVERED`.
- **Panel 4 (35):** the same 27 for the selected row, then `RATIO`, `SELECTED_BY`, `ROW_STATUS`, `N_ROWS`,
  `ANY_DISCHARGED`, `NODI_STRING_MONTH`, `FLAG_ZERO_LIMIT_DISCHARGE`, `FLAG_MULTI_MONTH_COVERED`.
- **Panel 5 (35):** row counts, `NODI_STRING`, ratios, violations and exceedances, flags, Q totals,
  averages and `NMBR_OF_REPORT` summaries (list in the script, `P5_COLS`).

## Choices

### Who is in panels 1–3

- **Month** = `YEAR`/`MONTH` of `MONITORING_PERIOD_END_DATE`. Every row counts, NODI-only rows included.
- **"Only ever" is pooled over the whole window.** One month with two rows anywhere excludes a permit
  from panel 1; one month with two Q rows excludes it from panel 2; likewise C for panel 3.
- **Q** = `VALUE_TYPE_CODE` Q1/Q2 (kg/d); **C** = C1/C2/C3 (mg/L). A permit needs at least one Q row to
  be in panel 2, and one C row to be in panel 3.
- **These are selected samples, not universes.** Panel 1 leans toward states where permits report
  concentration only. 772 of its 1,183 permits (65.26%) are in the 13 states where at least half the
  permits never report a Q row.

### Row status (panel 4 and the ratios)

Each row of the cleaned panel gets one status:
- `discharged`: a value other than 0. The 46 negative values (10 permits) are kept at face value.
- `no_discharge`: a value of 0, or a blank value with NODI C.
- `below_dl`: a blank value with NODI B.
- `no_report`: anything else.

### Panel 5's row counts

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
  `B_AS_ZERO` is TRUE (the default). The toggle also affects panel 4's selection and
  `TOTAL_DISCHARGED_Q`. In 12,518 permit-months the ratio rests on B rows alone, so with
  `B_AS_ZERO` FALSE it would be NA.
- **Panel 4's selection.** It keeps the row with the highest all-points ratio. If no row in the month
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

What the script does:
- **Every panel gets every month of the requested FYs**, whether or not the permit existed then.
  FY *y* runs from October of *y*−1 to September of *y*, so FY2009–FY2025 is 204 months.
- **Which permits.** Panels 4 and 5 are balanced over all 6,520 permits in the cleaned panel. Panels
  1–3 are balanced over **their own permits only**.
- **What an empty month holds.**
  - Filled from the permit and the month: `FY`, `FACILITY_ID`, `STATE_CODE`, `YEAR`, `MONTH`.
  - Panels 1–4: the row columns are blank and the two row flags are FALSE. In panel 4,
    `SELECTED_BY` and `ROW_STATUS` are blank too.
  - Panel 5: the counts are 0, the strings blank, the ratios, totals and averages NA, and the flags
    FALSE.
- **`N_ROWS`, in every panel,** is the number of rows the cleaned panel has for the permit-month,
  across both bases.
  - 0 means nothing was reported.
  - In panels 2 and 3, `N_ROWS` > 0 on a blank row means the permit reported only the other basis
    that month: 22,960 C-only months in panel 2 and 11,342 Q-only months in panel 3.
- **`FLAG_MULTI_MONTH_COVERED`** marks a month with nothing reported that lies inside the period of a
  quarterly, semiannual or annual report (`NMBR_OF_REPORT` > 1) dated to a later month. That month is
  not missing data. There are 12,104 such months in panels 4–5.
- **Where the empty months fall.** Of the 176,473 empty months in panels 4–5:
  - 55,603 come before the permit's first month with rows, 91,333 after its last, and 29,537 in
    between.
  - A permit-FY with any has a median of 12, so they mostly come as whole years.
  - Months outside a permit's first-to-last span may be before it was issued or after it ended. This
    has not been checked against ICIS permit dates.

**The alternative, probably the better choice, for panels 1–3.** Balance panels 1–3 over all 6,520
permits as well, giving a blank row and a flag such as `IN_PANEL` = FALSE to every permit that never
qualifies. Why:
- **One grid for all five panels.** They would share 6,520 × 204 = 1,330,080 permit-months with the
  same keys, so they line up row for row and merge 1:1.
- **The selection becomes visible.** Membership in a panel would be a column rather than an implicit
  sample restriction. Who gets in, and who does not, could then be compared directly, for example
  panel 1's tilt toward concentration-only states.
- **One denominator.** Shares in different panels would use the same base.

The cost:
- **Bigger files, mostly blank.** Each of the three files grows to 1,330,080 rows. For panel 1 that
  adds 1,088,748 rows for permits never in it.
- **Filtering.** Users must filter on the flag to get a panel's own permits.

This has not been done. The change would be in `balance13()`: build the grid from `pa` (all permits)
instead of the panel's permits, and add the flag.

## Using the output

- **Reading.** Read with `colClasses = "character"` and cast deliberately; a blank is not 0.
- **Never pool Q and C.** Panel 1 holds both: a permit's only row can be either. Panel 4's selected
  row can also be either, so its value and limit columns mix units; `RATIO` does not.
- **Panel 4's columns describe the selected row only.** Counting on them overstates months with
  nothing on any row. "No value and no NODI code" on the selected row gives 7,401 permit-months; on
  every row of the month it gives 7,370. For limits the figures are 31,251 and 30,436.
- **Panel 5's counts are row counts,** and rows are not additive within a month: Q and C rows, limit
  sets and outfalls each add rows.
- **Check year-to-year patterns for reporting artifacts.** Missing values are elevated in
  FY2013–FY2017 in panels 1–3; the cause has not been checked.

## What the script asserts

The script stops with an error if any of these fail:
- one row per permit × month in each output;
- no permit-month split across two FY files;
- one facility and one state per permit;
- each balanced panel has permits × months rows, and its months with a row match the unbalanced
  panel's row count;
- panel 5's four counts add up to `N_ROWS`.

## Open items

- **NODI B.** Should B count as zero discharge? This is the `B_AS_ZERO` toggle above.
- **EPA-only exceedances.** Why does EPA fill `EXCEEDENCE_PCT` on 113 rows our rule does not count
  as exceedances?
- **Negative values.** The 46 negative values are perhaps net-of-intake (unchecked); they are kept as
  discharged.
- **Panel 4's `ROW_STATUS`** still uses the four statuses above, not panel 5's four-way split.
- **NODI 2, N and 4** (operation shutdown, not constructed, discharge to lagoon or groundwater) may
  mean no discharge. They are counted in `N_OTHER_NODI`.
- **Empty months before a permit's first report or after its last** have not been checked against
  ICIS permit dates.
- **Panels 1–3 balancing:** the alternative above.
- **No codebook** for the panels yet. The pre-FY2009 years are not built.
