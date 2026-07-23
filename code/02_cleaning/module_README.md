# `code/02_cleaning/` — reserved

**No dedicated cleaning module exists yet.** Cleaning logic (blank-handling,
`colClasses = "character"` to preserve leading zeros, whitespace normalization,
permit→facility crosswalk construction) currently lives **inline** inside each
step of `code/03_panel_building/`, and inside the sibling `dmr analysis/` and
`build/` pipelines — it was never extracted into a standalone, reusable module.

This folder is a placeholder for that extraction, matching the lab's numbered
`code/` module convention (`00_setup` → `01_data_download` → `02_cleaning` →
`03_panel_building`). It's deliberately empty of code rather than populated with
fabricated `cleaning_functions.R` / `cleaning_parameters.R` files that don't
correspond to anything real.

## If/when this gets built

Worth extracting here if cleaning logic starts being duplicated across
`code/03_panel_building/`, `dmr analysis/`, and `build/` — e.g. the repeated
`trimws()` + `colClasses = "character"` reads, or the permit→facility crosswalk
that's currently "rebuilt identically in steps 02/04/05/06" per
`code/03_panel_building/README.md`'s own conventions section. Until then, look in
those three locations for the actual cleaning code.
