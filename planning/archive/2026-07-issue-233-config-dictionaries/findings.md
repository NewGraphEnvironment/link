# Findings — Rename dimensions_columns.csv → dictionary_dimensions.csv; add dictionary_parameters_fresh.csv (#233)

## Issue context

Two config CSVs drive the pipeline's methodology. Only one has a data dictionary, and it's named for its shape (`_columns`) rather than for what it is.

## Rename

`inst/extdata/configs/dimensions_columns.csv` → `inst/extdata/configs/dictionary_dimensions.csv`

Establishes a `dictionary_<file>` convention so the new sibling reads naturally.

A full-repo sweep found **no code reference** — no `system.file()` call, no `.Rd`, no test, no workflow. The repair surface is one line:

- `CLAUDE.md:238` (the #75 entry) — update
- `NEWS.md:409` — historical changelog, accurate at the time, leave
- `planning/archive/2026-05-issue-45-gradient-classes/findings.md:108` — archive, leave

`lnk_config()` resolves bundles via `dir.exists()` (`R/lnk_config.R:280`), so loose CSVs at the `configs/` root are inert. Adding a second one is safe.

## New file

`inst/extdata/configs/dictionary_parameters_fresh.csv` — one row per column of `parameters_fresh.csv` (19 columns).

Today those semantics are scattered: `RUNBOOK.md` §7 covers `access_gradient_max` and `observation_*` as families; roxygen on `lnk_barrier_overrides()` covers the observation block only; the 9 `cluster_*` columns are undocumented outside `R/lnk_pipeline_connect.R`.

Proposed schema — mirrors `dictionary_dimensions.csv`, with `emits` swapped for `consumed_by` (nothing is generated from this CSV) plus `owner`:

```
column,type,group,owner,consumed_by,default_when_absent,description,related
```

Groups: `key` / `access` / `gradient` / `cluster` / `observation`.

### `owner` is not a new decision

It makes declarative a partition that is already settled and already enforced.

Settled by NewGraphEnvironment/fresh#129 (shipped fresh 0.12.7). Its findings state the rule:

> The observation override from #69 put fish passage interpretation (counting, thresholds, species grouping, date filters) in fresh. That belongs in link.

`barrier_overrides` replaced `observations` on `frs_habitat()`, and the `observation_*` columns were removed from fresh's `parameters_fresh.csv`. fresh's NEWS: *"fish passage interpretation belongs in link, not the network engine."*

Enforced by `data-raw/audit_configs.R:138-186`, section *"3b. parameters_fresh column drift (fresh canonical vs link config)"*:

```r
# fresh owns the access/cluster parameter SCHEMA; link hand-authors per-bundle
# copies seeded from it plus link-only `observation_*` extensions. Values
# legitimately diverge (link tunes them) — only the COLUMN SET matters here.
```

| condition | verdict |
|---|---|
| `fresh \ link` | FLAG — link missing an engine param, may not load through `frs_habitat()` |
| `link \ fresh`, not `observation_*` | FLAG — unexpected column |
| `link \ fresh`, matches `^observation_` | expected extension, printed not flagged |
| values differ | fine by design — link tunes them |

So: **fresh owns the 14 access/cluster engine columns; link owns the 5 `observation_*` interpretation columns.** Only the column set is contractual.

The same comment records the two-way directionality: `rules.yaml` flows link → fresh (link owns the generator, `lnk_rules_build()`); `parameters_fresh` column schema flows fresh → link. Cross-referenced to #129.

### Consumers to encode

- `access_gradient_max` → `R/lnk_barriers_unify.R`, `R/lnk_pipeline_prepare.R`
- `cluster_*` (9 columns) → `R/lnk_pipeline_connect.R`
- `observation_*` (5 columns) → `R/lnk_barrier_overrides.R`
- `spawn_gradient_min` → fresh: `R/frs_habitat_classify.R:171`, `R/frs_habitat_predicates.R:87`
- `rear_gradient_min` → **no consumer in either package** — header-only in both `fresh/inst/extdata/parameters_fresh.csv` and every link bundle. It is fresh-owned, so whether it gets dropped is a fresh-side question. Record it here as unused; do not drop it as part of this issue.

## Make the dictionary load-bearing

`audit_configs.R` §3b currently hardcodes ownership as `grepl("^observation_", extra_link)`. Once the dictionary carries `owner`, §3b should read the dictionary instead of prefix-matching. That makes the dictionary checked on every audit run rather than drift-prone — the same ambition #75 has for the dimensions side.

## Stop re-deriving this

Add an ownership row to `RUNBOOK.md` §7 "Where every rule lives", pointing at NewGraphEnvironment/fresh#129 and `audit_configs.R` §3b. The fresh#69 → fresh#129 boundary has been worked out at length before and is currently only findable by archaeology through two repos' planning archives.

## Scope

- [ ] `git mv` the dimensions dictionary; repair `CLAUDE.md:238`
- [ ] Author `dictionary_parameters_fresh.csv` (19 rows), tracing each column to its consumer rather than inferring
- [ ] Rewire `audit_configs.R` §3b to read `owner` from the dictionary
- [ ] `RUNBOOK.md` §7 ownership row

## Out of scope

- Auto-generated README + `lnk_rules_build()` validation against the dictionary — stays in #75, which this unblocks by giving it two files in a consistent shape.
- Dropping or relocating `rear_gradient_min`.
- Any change to fresh's own `parameters_fresh.csv`.

## Verification

- `grep -rn "dimensions_columns" . --exclude-dir=.git` returns nothing outside `NEWS.md` and `planning/archive/`
- `Rscript data-raw/audit_configs.R` runs clean, with §3b sourcing ownership from the dictionary
- Every `consumed_by` entry in the new dictionary resolves to a real file:line
- `devtools::test()` passes (no test currently touches either file — confirms the rename is inert)


---

## Plan-mode exploration (2026-07-29)

### Reference sweep — the rename is inert

`grep -rn "dimensions_columns" . --exclude-dir=.git` returns three hits, all prose. No `system.file()` call, no `.Rd`, no test, no workflow reads the file.

| Hit | Action |
|---|---|
| `CLAUDE.md:256` (#75 entry) | repair — the only live reference |
| `NEWS.md:421` (v0.17-era changelog) | leave — historical, accurate at the time |
| `planning/archive/2026-05-issue-45-gradient-classes/findings.md:108` | leave — archive |

`lnk_config()` resolves bundles via `dir.exists()` (`R/lnk_config.R:280`), so loose CSVs at the `configs/` root are ignored. Adding a second one is safe.

### Ownership — already settled, do not re-derive

The fresh↔link `parameters_fresh` column boundary was worked out at length and is recorded in two places:

1. **The decision** — `fresh/planning/archive/2026-04-issue-129-barrier-overrides/findings.md:3`:
   > The observation override from #69 put fish passage interpretation (counting, thresholds, species grouping, date filters) in fresh. That belongs in link.

   Shipped fresh 0.12.7 — `barrier_overrides` replaced `observations`, `observation_*` columns deleted from fresh's CSV. fresh NEWS: *"fish passage interpretation belongs in link, not the network engine."* Arc is fresh#69 (added them) → fresh#129 (removed them).

2. **The enforcement** — `data-raw/audit_configs.R:140-186` §3b:
   ```r
   # fresh owns the access/cluster parameter SCHEMA; link hand-authors per-bundle
   # copies seeded from it plus link-only `observation_*` extensions. Values
   # legitimately diverge (link tunes them) — only the COLUMN SET matters here.
   ```
   | condition | verdict |
   |---|---|
   | `fresh \ link` | FLAG — link missing an engine param |
   | `link \ fresh`, not `observation_*` | FLAG — unexpected column |
   | `link \ fresh`, matches `^observation_` | expected extension |
   | values differ | fine by design |

Same comment records the two-way directionality: `rules.yaml` flows link → fresh (link owns `lnk_rules_build()`); `parameters_fresh` column schema flows fresh → link. Cross-referenced to link#129.

### Consumer traces (verified on HEAD b9f6285)

- `access_gradient_max` → `R/lnk_barriers_unify.R:139`, `R/lnk_pipeline_prepare.R:553` — **plus** fresh. Dual-consumed.
- `spawn_gradient_min` → `fresh/R/frs_habitat_classify.R:171`, `fresh/R/frs_habitat_predicates.R:87`
- `cluster_*` (9) → read in **fresh** at `fresh/R/frs_habitat.R:1164-1196`. link only passes the frame through (`R/lnk_pipeline_connect.R:107` → `.frs_run_connectivity()`). The issue body's "→ `lnk_pipeline_connect.R`" is imprecise.
- `observation_*` (5) → `R/lnk_barrier_overrides.R`
- `rear_gradient_min` → **no reader in either package.** Header-only in `fresh/inst/extdata/parameters_fresh.csv` and every link bundle. fresh-owned, so dropping it is a fresh-side call.

Cluster semantics prose source: `fresh/R/frs_cluster.R` roxygen documents `direction`, `bridge_gradient`, `bridge_distance`, `confluence_m` in full.

### Environment notes

- `data-raw/` is `.Rbuildignore`d — `audit_configs.R` is dev-only. `inst/` ships, so testthat is the durable guard for the dictionary contract; the audit is the pre-trifecta gate.
- `audit_configs.R` hardcodes `setwd("/Users/airvine/Projects/repo/link")` (line 14). Portability defect, out of scope for #233, worth its own issue.
- fresh is Suggests (>= 0.32.0). fresh repo pulled to v0.32.0 during this session; installed R package may still be 0.31.0 — reinstall before relying on cross-package tests.

### Repo state at branch time

Local `main` was 38 commits behind `origin/main`; the pull was blocked by 96 untracked `data-raw/logs/` files that upstream had since committed (65 in the first collision set, 31 more that git's truncated error had hidden). All 96 were copied to `data-raw/logs/_local_pre_pull_20260729/` (byte-identity verified, 384K) before removal, then `main` fast-forwarded to `b9f6285` / v0.44.2. Of the originals, 40 were byte-identical to upstream; the rest were divergent local run outputs from 2026-05-13/14/15 preserved in that backup.

Plan targets were checked against the 38 commits: `dimensions_columns.csv`, `data-raw/audit_configs.R`, and `RUNBOOK.md` are all untouched upstream. Adjustments carried into the plan: `CLAUDE.md` ref moved `:238` → `:256`; version bump target `0.43.1` → `0.44.3`.
