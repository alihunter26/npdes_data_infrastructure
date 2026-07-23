# `code/diagnostics/` — data-quality checks & one-offs, grouped by topic

Standalone scripts that probe the raw ICIS-NPDES/DMR data for duplicates, missingness,
coverage, and value-quality issues, plus the generators behind `docs/institutional_briefs/`.
**None of these build the panel**; they write diagnostic extracts (mostly to
`output/tables/`) that inform the modeling decisions documented in `docs/`. Grouped into
one subfolder per topic so related scripts sit together as the list grows.

## Subfolders

| Folder | Scripts | Purpose |
|---|---|---|
| `naics_sic/` | `check_naics_sic_mapping.R`, `naics_california.R`, `naics_sic_coverage_by_state_year.R` | NAICS/SIC industry-code coverage and California-specific extracts. |
| `enforcement_duplicates/` | `count_informal_exact_duplicates.R`, `dup_enforcement_pairs.R`, `dup_rows_by_enf_type.R`, `formal_actions_same_fine_date.R` | Why enforcement-action rows repeat or look duplicated. |
| `enforcement_breakdowns/` | `enforcement_by_permit_type.R` | Formal/informal enforcement counts by permit type x major/minor status. |
| `facility_structure/` | `facility_uin_multiple_npdes.R` | Facilities (`FACILITY_UIN`) holding more than one `NPDES_ID`. |
| `missingness/` | `cs_rnc_missingness.R`, `missingness_audit_major_individual.R` (+ its own [README](missingness/missingness_audit_major_individual.md)) | Where and why fields are blank. |
| `outfalls/` | `outfall_count_breakdown.R`, `outfall_count_breakdown_dmr.R`, `feature_ids_per_permit.R` | Outfall / discharge-point (`PERM_FEATURE_ID`) counts per permit — permitted vs. actually reporting. |
| `brief_generators/` | `make_dmr_funnel_fig.R`, `make_naics_sic_coverage_brief.R` | Compute the figures/tables cited in `docs/institutional_briefs/`. (`make_permit_types_brief.R` was removed when `docs/permit_types_brief.md` became the sole canonical permit-types brief — see `docs/permit_types_brief.md`.) |
| `effluent_qc/` | `eff_flagged.R` | Flags suspicious effluent-violation rows (negative values, implausible dates/magnitudes) for one state → `output/eff_flagged_<state>_*.csv`. State via arg: `Rscript eff_flagged.R va`. |
| `scratch/` | `preview_dmr2025.R` | One-off interactive snippet to peek inside the DMR zip. Not durable — no output written. |

## Conventions

- Sources `_paths.R`; reads raw as character; deterministic.
- Read-only with respect to `data/` — outputs are timestamped CSVs in `output/` /
  `output/tables/`.
- Per-script READMEs are added as they're written (the SSDE-style template used in
  `code/03_panel_building/READMEs/`); `missingness/missingness_audit_major_individual.md`
  is the current example to follow.

Findings from these checks are written up in `docs/data_quirks.md` and `docs/missingness.md`.
