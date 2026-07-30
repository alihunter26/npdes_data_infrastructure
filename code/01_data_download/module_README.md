# `code/01_data_download/` — ECHO bulk-file downloader

** verified by Ali 7/27 **

**Purpose:** fetches every EPA ECHO / ICIS-NPDES bulk data file this repo's
pipeline depends on into `data/raw/`, replacing the previously-manual "click
through the downloads page" step. See
[`01_download_echo_bulk_files.md`](01_download_echo_bulk_files.md) for full
per-script documentation (data sources, decisions/assumptions, output columns).

## When `run_all.R` runs this

`run_all.R` runs this on demand via its `DOWNLOAD_DATA` flag, which defaults to
`"auto"`: it fetches the bulk files **only when `data/raw/` looks unpopulated**
(a fresh clone downloads on its own; an already-populated setup skips the
multi-GB transfer). Set `DOWNLOAD_DATA <- TRUE` to always run it, or `FALSE` to
never. The download is idempotent — it logs `SKIPPED-EXISTS` and fetches only
missing files — so re-running is safe. You can also run the script directly:

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
