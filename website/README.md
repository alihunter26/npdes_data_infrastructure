# `website/` — static Clean Water Act Data Explorer

A plain HTML/CSS/JS site (no build tooling, no framework) that presents the
project's data as browsable tables. Pages load their data at runtime from
`website/data/*.json`; those JSON files are **generated** from the summary
workbooks, not edited by hand.

## Layout

| Path | What |
|---|---|
| `*.html` | Pages. `index`, `summaries` (dataset cards), `dataset.html?key=…` (one raw dataset), `panel.html` (built facility-month panel QA), `temporal-coverage`, `briefs` + `brief-*`, `data-documentation`, `about`. |
| `assets/` | `style.css`; `table.js` (`renderDataTable`); `datasets.js` (the raw-dataset card registry); `year-coverage.js` (the temporal cross-tab renderer). |
| `data/` | Generated JSON the pages `fetch()`: `<key>.json` per raw dataset, `year_coverage.json`, `panel.json`. |
| `scripts/` | The data build (below). |

## Building the data

One command rebuilds every JSON:

```bash
Rscript website/scripts/build_website_data.R
```

It runs the summaries and then the converters:

```
code/summary/summarize.R <dataset>   (npdes all, dmrs, attains, limits,
                                       master_general_permits, outfalls_layer,
                                       eff_violations_state VA, …NY)   ─┐
code/summary/summarize_year_coverage.R                                 ─┤→ output/*.xlsx
code/summary/summarize_panel.R                                         ─┘
                                                                         │
website/scripts/xlsx_to_json.R        → website/data/<key>.json          │
website/scripts/year_coverage_to_json.R → website/data/year_coverage.json│
website/scripts/panel_to_json.R       → website/data/panel.json         ─┘
```

- Each step runs in its **own R process**: memory isolation (the `limits` summary
  loads a ~7 GB file) and fail-soft (a failed step is logged; the rest continue).
- `xlsx_to_json.R` **skips** any dataset whose workbook is missing, leaving that
  dataset's existing JSON untouched — so a partial build still refreshes the rest.
- It is **slow**: `limits` reads a multi-GB CSV; the two eff_violations states each
  stream a ~2.9 GB zip. Comment out `run_step()` lines in `build_website_data.R` to
  refresh only some pages.

`run_all.R` runs this as its final stage (`BUILD_WEBSITE <- TRUE`), so a full
`Rscript run_all.R` rebuilds the panel and the site together.

## Viewing

Serve over HTTP — the pages `fetch()` their JSON, which browsers block under the
`file://` protocol (open a page directly and its tables are empty):

```bash
cd website && python3 -m http.server 8000    # then open http://localhost:8000
```

## Adding a dataset page

1. Add the dataset to `code/summary/summarize.R`'s `DATASETS` registry (raw source)
   and a `run_step()` line in `build_website_data.R`.
2. Add its `<prefix>_summary_` pattern to `xlsx_to_json.R`'s `DATASET_FILES` and its
   date columns to `DATE_COLS`.
3. Add a card entry to `assets/datasets.js` (raw datasets render through
   `dataset.html`). The built panel is the exception — its QA layout differs, so it
   has its own `panel.html` + `panel_to_json.R` rather than a `datasets.js` entry.
