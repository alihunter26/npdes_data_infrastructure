# `code/03_panel_building/` — facility-by-month panel pipeline

The seven numbered scripts that build the **facility-by-month panel** of major,
individually-permitted NPDES facilities, 2005–2025, from the raw ECHO/ICIS-NPDES data
in `data/raw/`. Each step reads the prior step's CSV from `data/processed/` and writes
the next.

> This is distinct from `code/dmr/`'s FY2025 DMR filter mini-pipeline (formerly a
> root-level `build/` sibling folder; see `code/README.md`).

## Steps

| Step | Script | Adds |
|---|---|---|
| 01 | `01_build_facility_month_panel_major_individual.R` | base facility × month spine + facility attributes + all three operating flags. Panel **membership** (since 2026-07-28) requires EITHER a permit-paperwork window (`ICIS_PERMITS.csv`) overlapping 2005–2025 OR independent proxy evidence anywhere in that range — permit dates alone no longer gate inclusion. The proxy scan — inspections, PS/CS/SE violations, formal/informal enforcement, effluent — is done by calling `use_operating_proxies()` (see Helper scripts below), which also produces `FACILITY_OPERATING`'s window-extension correction. |
| 02 | `02_add_inspections.R` | inspection counts by type & conductor |
| 03 | `03_add_naics_sic.R` | NAICS / SIC industry codes |
| 04 | `04_add_violations.R` | PS/CS/SE violation counts |
| 05 | `05_add_enforcement.R` | formal/informal enforcement counts + penalty $ |
| 06 | `06_add_effluent_violations.R` | all effluent-violation counts: TSS subset + all-parameter D80/D90/E90 |
| 07 | `07_add_dmr.R` | **FY2017 DMR discharge & compliance variables** (final panel): 30 columns covering outfall counts by mass/concentration basis, mass discharged vs. permitted, exceedance counts and magnitudes (ours and EPA's), censoring, and outfall activity. First step that reads the DMR files themselves. Requires the `code/dmr/` row-filter pipeline steps 1–3 for FY2017 first; **not** in `run_all.R`. See [`READMEs/07_add_dmr.md`](READMEs/07_add_dmr.md). |

> **2026-10-07: the `07_` name is now step `07_add_dmr.R`.** Two earlier, unrelated
> things carried that number: a retired `FACILITY_OPERATING` correction (folded into step
> 01, see below) and, before that, the missingness audit (now a diagnostic). The static
> files `data/processed/07_facility_month_panel_major_individual_operating_corrected_*.csv`
> on disk are leftovers of the FIRST of those and are **not** this step's output — the new
> step writes `07_facility_month_panel_major_individual_dmr_tss_2005_2025.csv`. Don't
> confuse them.

> The missingness audit that used to occupy the "step 07" name is now a diagnostic:
> [`../diagnostics/missingness/missingness_audit_major_individual.R`](../diagnostics/missingness/missingness_audit_major_individual.R).

> **2026-07-23: retired a separate step 07.** `FACILITY_OPERATING` used to be corrected
> by a standalone post-processing script (step 07, run after step 06). That correction
> now runs **inside step 01** — it only ever needed to know whether/when a facility had
> *any* real event (not the full detailed counts), so it doesn't need to wait for
> steps 02–06 to run first. See [`READMEs/01_build_facility_month_panel_major_individual.md`](READMEs/01_build_facility_month_panel_major_individual.md),
> Assumption 10.

> **2026-07-28: panel membership now depends on proxy evidence too, not permit dates**
> **alone.** Previously, a facility whose permit-paperwork window didn't overlap
> 2005–2025 was dropped before the proxy scan ever ran. Now it's kept if EITHER its
> permit window overlaps OR it has independent proxy evidence anywhere in 2005–2025 —
> verified: 16 of 7,531 candidate facilities are admitted solely via proxy evidence.
> See [`READMEs/01_build_facility_month_panel_major_individual.md`](READMEs/01_build_facility_month_panel_major_individual.md),
> Assumption 1B.

**Per-script documentation** — inputs, outputs, and every decision/assumption — lives in
[`READMEs/`](READMEs/README.md) (SSDE-style, one file per script).

## Prerequisite (not one of the six numbered steps)

- `build_effluent_violations_npdes_month_panel.R` — lives in
  [`code/02_cleaning/`](../02_cleaning/), not here (moved 2026-07-27; see that
  folder's `module_README.md`). Must run **before step 01**, not just before step 06:
  both steps read its output,
  `data/processed/effluent_violations_npdes_month_panel_2005_2025.csv`. Streams the raw
  effluent file (via DuckDB) into a condensed permit×month summary of both all-parameter
  and TSS-subset violation counts. See
  [`../02_cleaning/build_effluent_violations_npdes_month_panel.md`](../02_cleaning/build_effluent_violations_npdes_month_panel.md).

## Helper scripts (not part of the numbered chain)

- `summarize_violation_types.R` — tabulates violation-type frequencies → `output/tables/`.
- `use_operating_proxies.R` — defines `use_operating_proxies()`, the event-based
  proxy-evidence logic behind step 01's Assumptions 1B, 10, and 11, factored out
  into its own function with an on/off switch per proxy source (inspections,
  PS/CS/SE violations, formal/informal enforcement, effluent — all default `TRUE`,
  reproducing the original correction exactly). **This is the only place the seven
  event/proxy sources get used** — step 01 itself builds the baseline window from
  permit paperwork dates alone (`ICIS_PERMITS.csv`) and never reads any of these seven
  directly; it just calls this function to scan for proxy evidence. As of
  2026-07-28, its return value feeds THREE things in step 01, not just one: the
  proxy-only bounds (`FACILITY_OPERATING_PROXY_WINDOW`, Assumption 11), the union
  bounds (`FACILITY_OPERATING`, Assumption 10), and — since a facility with proxy
  evidence but no permit-window overlap is now admitted to the panel at all —
  panel **membership** itself (Assumption 1B). Step 01 ties all seven switches to
  a single `USE_PROXIES` config flag (default `TRUE`; set `FALSE` for permit-
  paperwork dates only, no proxy evidence scanned or used at all, which also
  collapses membership back to permit-window-overlap only) — see that flag's own
  `use_*` arguments if you want to enable/disable individual sources instead.
  Sourced and called by step 01; see
  [`READMEs/01_build_facility_month_panel_major_individual.md`](READMEs/01_build_facility_month_panel_major_individual.md).

> **Removed 2026-07-23:** `restrict_06_to_fy2025.R` (the federal-FY2025 row filter) was
> deleted. Its outputs (`data/processed/07_..._operating_corrected_fy2025.csv` and the
> earlier `data/processed/06_..._effluent_fy2025.csv`) remain on disk as static files —
> **no longer regenerable by any script.** Neither should be treated as a source of
> truth; filter the current 06 panel directly for a fresh FY2025 (or other) extract.

## Run order

```bash
Rscript "code/03_panel_building/01_build_facility_month_panel_major_individual.R"
Rscript "code/03_panel_building/02_add_inspections.R"
# … 03, 04, 05, 06 in order (06 = last step in run_all.R)

# Step 07 is run manually, after its own DMR prerequisite (see note below):
Rscript "code/dmr/filter_dmr_major_individual.R" 2017
Rscript "code/dmr/filter_dmr_00530.R" 2017
Rscript "code/dmr/filter_dmr_monloc1.R" 2017
Rscript "code/03_panel_building/07_add_dmr.R"
Rscript "code/diagnostics/missingness/missingness_audit_major_individual.R"   # diagnostic, after 06
```

Or simply `Rscript run_all.R` from the repo root, which builds the condensed effluent
panel first (if it's not already on disk) and then runs all six steps in order.

Neither step 01 nor step 06 needs `python3` or `unzip` — both read only the pre-built
condensed effluent panel at
`data/processed/effluent_violations_npdes_month_panel_2005_2025.csv`. That file's own
build script (`code/02_cleaning/build_effluent_violations_npdes_month_panel.R`, see
above) is what needs `unzip` and `gzip` on `PATH`, plus the DuckDB R package, since
it's the one that actually streams the raw ~16 GB effluent file.

> Step 01's `OUT_PATH` already writes the `01_`-prefixed name step 02 expects — a
> previously-documented mismatch here has been verified resolved in code. See
> [`READMEs/`](READMEs/README.md).

## Conventions

- Unit = FRS facility (`FACILITY_UIN`, or `NPDES_ID` when blank); grain = facility × year
  × month; window 2005–2025.
- Sources `_paths.R`; reads as character; deterministic (no seeds); permit→facility
  crosswalk rebuilt identically in steps 02/04/05/06 (and twice, for two different
  purposes, within step 01 itself — see its README).
