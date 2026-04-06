# Findings & Decisions

## Requirements
- Connectivity-system agnostic — BC/PSCIS defaults but not hardcoded
- Function families with autocomplete-friendly naming: `lnk_override_*`, `lnk_match_*`, `lnk_score_*`, `lnk_break_*`, `lnk_habitat_*`
- Configurable column names and thresholds via params with sane defaults
- Override CSVs with provenance tracking
- Bridge to fresh via `break_sources` interface
- Examples on every exported function — show integration, results, usefulness
- SRED tracking: commits close issues, PR references sred-2025-2026#24

## Research Findings

### fresh API surface (from exploration)
- 35 exported `frs_*` functions
- `frs_habitat()` is the main orchestrator — takes `break_sources` as list of specs
- `break_sources` spec: `list(table, where, label, label_col, label_map)`
- `frs_params()` loads thresholds from CSV or DB — returns named list by species code
- `frs_classify()` has three modes: ranges, breaks, overrides (table-based joins)
- Override mechanism: joins on `blue_line_key + downstream_route_measure` — exact match
- No CSV override loader in fresh — that's link's job
- Generated columns auto-recompute gradient/measures after geometry splits

### SRED issue #24
- Technological uncertainty: species-specific swimming performance → crossing-specific passability scores
- MOTI integration gap: chris_culvert_id not linked in provincial systems
- Moving beyond binary BARRIER/PASSABLE to severity-based metrics
- Adult spawner vs juvenile thresholds — current provincial criteria are juvenile-only

### Open issues
- #1 — Package scope (architecture, function surface, dependencies)
- #2 — Literature RAG store (ragnar search, separate workstream)

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| Column params with defaults | `col_drop = "outlet_drop"` — BC users get zero-config, others swap names |
| `lnk_thresholds()` returns named list | Same pattern as `frs_params()` — ecosystem consistency |
| Override load validates structure | Catch bad CSVs early, not at scoring time |
| Provenance cols optional | `reviewer`, `review_date`, `source` — tracked when present, not required |
| `lnk_break_source()` returns list not table | Direct input to `frs_habitat(break_sources = list(...))` |
| `lnk_match_sources()` is generic | Any table with ID + network position participates — not PSCIS-specific |
| Severity levels: high/moderate/low | Biological impact framing, not infrastructure condition |

## Resources
- fresh package: `~/Projects/repo/fresh/`
- fresh break_sources interface: `R/frs_habitat.R` lines 62–341
- fresh params pattern: `R/frs_params.R` lines 51–89
- SRED issue: NewGraphEnvironment/sred-2025-2026#24
- R package conventions: `soul/conventions/r-packages.md`
