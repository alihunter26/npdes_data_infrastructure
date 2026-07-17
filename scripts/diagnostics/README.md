# `scripts/diagnostics/` — data-quality checks & one-offs

Standalone scripts that probe the raw ICIS-NPDES data for duplicates, missingness, and
coverage. **None of these build the panel**; they write diagnostic extracts (mostly to
`output/tables/`) that inform the modeling decisions documented in `docs/`.

## Scripts

| Script | Purpose |
|---|---|
| `eff_flagged.R` | Flags suspicious effluent-violation rows for one state → `output/eff_flagged_<state>_*.csv` with a `FLAG_REASON` (negative `DMR_VALUE_NMBR` / `_STANDARD_UNITS`, a year before 1984 in any of four date columns, or any non-ID value > 1,000,000). State via arg: `Rscript eff_flagged.R va`. |
| `count_informal_exact_duplicates.R` | Counts fully-identical duplicate rows in informal enforcement; writes every duplicate, copies side by side, to `output/tables/`. |
| `dup_enforcement_pairs.R` | Diagnoses why `(NPDES_ID, ENF_IDENTIFIER)` pairs repeat in formal enforcement. |
| `dup_rows_by_enf_type.R` | Extracts formal-enforcement rows identical except `ENF_TYPE_CODE`/`DESC` (one action recorded once per statute) → `output/tables/`. |
| `cs_rnc_missingness.R` | Tests why RNC fields are ~61% blank in compliance-schedule violations (joins permit major/minor + RNC-tracking flags). |
| `naics_california.R` | Extracts NAICS assignments for California facilities → `output/tables/npdes_naics_california_*.csv`. |
| `naics_sic_coverage_by_state_year.R` | Tabulates NAICS/SIC coverage by state and year → `output/tables/naics_sic_coverage_by_state_year_*.csv`. |
| `preview_dmr2025.R` | One-off snippet to peek inside the DMR zip. |

## Conventions

- Sources `_paths.R`; reads raw as character; deterministic.
- Read-only with respect to `data/` — outputs are timestamped CSVs in `output/` /
  `output/tables/`.

Findings from these checks are written up in `docs/data_quirks.md` and `docs/missingness.md`.
