# `code/01_data_download/` — ECHO bulk-file downloader

**Purpose:** fetches every EPA ECHO / ICIS-NPDES bulk data file this repo's
pipeline depends on into `data/raw/`, replacing the previously-manual "click
through the downloads page" step. See
[`01_download_echo_bulk_files.md`](01_download_echo_bulk_files.md) for full
per-script documentation (data sources, decisions/assumptions, output columns).

## Off by default

`run_all.R` does **not** run this automatically — it's gated behind a
`DOWNLOAD_DATA <- FALSE` flag, since it can mean multi-GB downloads and
`data/raw/` is normally already populated. Set that flag to `TRUE`, or run the
script directly:

```bash
Rscript code/01_data_download/01_download_echo_bulk_files.R
```

## What it does NOT cover

- **`REF_STATISTICAL_BASE.csv`** (`data/raw/reference/`) — no bulk-zip source was
  found for this small domain/lookup table; it stays a manual placement.
- **Per-fiscal-year DMR URLs are inferred, not confirmed** — the ECHO page's DMR
  section is JS-driven, so the URL pattern is extrapolated from every other
  confirmed URL's pattern plus the local filenames already on disk. A wrong guess
  for one year fails soft (logged, loop continues) rather than aborting the run.
