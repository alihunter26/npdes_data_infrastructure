# `code/diagnostics/` — data-quality checks & one-offs, grouped by topic

Standalone scripts that probe the raw ICIS-NPDES data for duplicates, missingness,
coverage, and value-quality issues, plus the generators behind `docs/institutional_briefs/`.
**None of these build the panel**; they write diagnostic extracts (mostly to
`output/tables/`) that inform the modeling decisions documented in `docs/`. Grouped into
one subfolder per topic so related scripts sit together as the list grows. DMR-specific
diagnostics (effluent QC, DMR funnel figure, DMR-based outfall counts) live in
`code/dmr/` instead — see its README.

## Subfolders

| Folder | Scripts | Purpose |
|---|---|---|
| `naics_sic/` | [`check_naics_sic_mapping.R`](naics_sic/check_naics_sic_mapping.md), [`naics_california.R`](naics_sic/naics_california.md), [`naics_sic_coverage_by_state_year.R`](naics_sic/naics_sic_coverage_by_state_year.md) | NAICS/SIC industry-code coverage and California-specific extracts. |
| `enforcement_duplicates/` | [`count_informal_exact_duplicates.R`](enforcement_duplicates/count_informal_exact_duplicates.md), [`dup_enforcement_pairs.R`](enforcement_duplicates/dup_enforcement_pairs.md), [`dup_rows_by_enf_type.R`](enforcement_duplicates/dup_rows_by_enf_type.md), [`formal_actions_same_fine_date.R`](enforcement_duplicates/formal_actions_same_fine_date.md) | Why enforcement-action rows repeat or look duplicated. |
| `enforcement_breakdowns/` | [`enforcement_by_permit_type.R`](enforcement_breakdowns/enforcement_by_permit_type.md) | Formal/informal enforcement counts by permit type x major/minor status. |
| `facility_structure/` | [`facility_uin_multiple_npdes.R`](facility_structure/facility_uin_multiple_npdes.md) | Facilities (`FACILITY_UIN`) holding more than one `NPDES_ID`. |
| `missingness/` | [`cs_rnc_missingness.R`](missingness/cs_rnc_missingness.md), `missingness_audit_major_individual.R` (+ its own [README](missingness/missingness_audit_major_individual.md)) | Where and why fields are blank. |
| `outfalls/` | [`outfall_count_breakdown.R`](outfalls/outfall_count_breakdown.md), [`feature_ids_per_permit.R`](outfalls/feature_ids_per_permit.md) | Outfall / discharge-point (`PERM_FEATURE_ID`) counts per permit — permitted vs. actually reporting. (`outfall_count_breakdown_dmr.R` moved to `code/dmr/` 2026-07-27 — see its README.) |
| `brief_generators/` | [`make_naics_sic_coverage_brief.R`](brief_generators/make_naics_sic_coverage_brief.md) | Compute the figures/tables cited in `docs/institutional_briefs/`. (`make_permit_types_brief.R` was removed when `docs/permit_types_brief.md` became the sole canonical permit-types brief — see `docs/permit_types_brief.md`. `make_dmr_funnel_fig.R` moved to `code/dmr/` 2026-07-27.) |

## Conventions

- Sources `_paths.R`; reads raw as character; deterministic.
- Read-only with respect to `data/raw/` — most outputs are timestamped CSVs in
  `output/tables/`, but not all: `check_naics_sic_mapping.R`,
  `formal_actions_same_fine_date.R`, and `enforcement_by_permit_type.R` write
  untimestamped CSVs to `output/` root (a re-run overwrites the prior copy), and
  `facility_uin_multiple_npdes.R` writes to `data/processed/` instead of `output/` at
  all. See each script's own README for the specifics.
- Every script now has a per-script README in the SSDE-style template (see
  `missingness/missingness_audit_major_individual.md` for the original exemplar);
  linked from the table above.

Findings from these checks are written up in `docs/data_issues.md` and `docs/missingness.md`.
