# `code/00_setup/` — package & directory setup

**Purpose:** the module's master script, run first by `run_all.R`. Checks every R
package the pipeline uses is installed (installs any missing ones from CRAN) and
creates the directories every downstream script expects to write into
(`data/raw/`, `data/processed/`, `data/crosswalks/`, `output/`, `output/tables/`,
`output/figures/`).

**Not a data step.** It never touches the contents of `data/raw/`, downloads
anything, or runs any part of the panel build.

## Inputs / Outputs

- **Inputs:** none.
- **Outputs:** none directly — side effects are installed packages and created
  (empty, if not already present) directories.

## Instructions to run

```bash
Rscript code/00_setup/00_setup.R
```

Or simply run `Rscript run_all.R` from the repo root — it sources this first.

## Notes

- Package list is the union of every `library(...)` call found across `code/`,
  `build/`, and `dmr analysis/` (verified via repo-wide grep, not guessed).
- Directories are created with `dir.create(..., showWarnings = FALSE)`, so
  re-running this script is always safe — it never overwrites or clears an
  existing directory.
