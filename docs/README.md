# `docs/` — project documentation & notes

Prose reference material: data dictionaries, codebooks, and running notes on data
quirks, definitions, and modeling decisions. These are the human-readable companion to
the code in `code/` and `code/03_panel_building/`.

## Contents

| File | Purpose |
|---|---|
| `data_dictionary.md` | Key fields across the ICIS-NPDES tables and how they join. |
| `codebook.md` | Variable definitions for the processed panels (stub — expand as panels grow). |
| `npdes_data_overview.md` | High-level tour of the NPDES/ECHO data and what each file covers. |
| `permit_types_brief.md` | Permit-type codes (individual `NPD`, general, master general, …) and what they mean. |
| `time_varying_vs_snapshot.md` | Which fields are time-varying vs. one-snapshot-per-facility (drives the panel's broadcast-vs-monthly logic). |
| `data_quirks.md` | Catalogue of gotchas (duplicate rows, non-ASCII filenames, blank-vs-zero, etc.). |
| `missingness.md` | Where and why fields are missing; how blanks are interpreted. |
| `notes.md` | Running log of decisions, findings, and open questions. |
| `panel_questions_for_pis.md` | Design questions raised with the PIs and the guidance received. |

## Conventions

- **Markdown, not code.** Nothing here is executed; these files record intent,
  definitions, and decisions so the project can be picked back up cold.
- Modeling decisions documented here are the authority behind the "LABELED ASSUMPTION"
  blocks in the panel-build scripts — keep them in sync.
- Export to PDF from VS Code (*Markdown PDF: Export*) when a shareable copy is needed.
