# Findings — Decouple bcfp compare from link pipeline run (#168)

## Issue context

### Principle

**Modelling stands on its own.** The link pipeline produces the BC freshwater network model — PG `fresh.*` tables. That's the deliverable. It must be runnable end-to-end without any comparison framework attached.

**Comparison is separate.** Parity vs bcfishpass (or any future reference: federal data, regression-against-previous-run, etc.) is a diagnostic overlay on top of the canonical model. It reads from PG, produces side artifacts (RDS, annotated CSV), and never gates whether the model itself ran.

Today these are coupled — modelling and comparison live inside one function (`compare_bcfishpass_wsg.R`) called from one loop (`run_provincial_parity.R`). The loop's resume-check uses RDS existence (the comparison artifact), not PG state (the model). Result: a stale comparison RDS silently skips re-running the model, even when PG never received the model output.

### Concrete reproduction (2026-05-14)

While running a 16-WSG `--no-cyphers` integration test on the #172 branch, the dispatch reported `16 OK, 0 errors` but only **12** of 16 WSGs actually populated `fresh_default.streams`. Four WSGs (`FINA`, `CRKD` on M4; `INGR`, `MESI` on M1) had stale RDS files from earlier failed attempts. The cache-skip in `run_provincial_parity.R:200-205` saw the RDS and skipped them:

```r
for (w in wsgs) {
  out_rds <- file.path(out_dir, paste0(w, ".rds"))
  if (file.exists(out_rds)) {
    cat(format(Sys.time(), "%H:%M:%S"), "  ", w, " (cached, skip)\n", sep = "")
    next   # ← skips PIPELINE *and* compare; PG may be empty
  }
  ...
  out <- compare_bcfishpass_wsg(wsg = w, config = cfg, ...)  # ← pipeline + compare bundled
  saveRDS(out, out_rds)
}
```

Reference run: `data-raw/logs/202605141122_trifecta_provincial_orchestrator.txt`.

### Proposed: decoupled architecture

#### Two independent functions

| Function | Role | Input | Output |
|---|---|---|---|
| `lnk_pipeline_run(conn, wsg, cfg, ...)` | Model — runs the `lnk_pipeline_*` chain end-to-end | local fwapg conn | PG: `fresh.streams`, `fresh.streams_habitat_<sp>`, `fresh.barriers` for this WSG |
| `lnk_compare_rollup(conn, conn_ref, wsg, cfg, reference, ...)` | Comparison — reads PG, queries reference, returns diff | local + reference conns | R tibble (caller persists as RDS or CSV) |

`lnk_compare_rollup()` is reference-agnostic via the `reference` arg — `"bcfishpass"` today, future references plug in without naming changes.

Today's `lnk_compare_wsg()` becomes a thin convenience wrapper that calls both (for backwards-compat with operators who want the bundled behavior). New code uses the two split functions.

#### `data-raw/` companions, renamed for honesty

| Old name (lies about scope) | New name | Role |
|---|---|---|
| `data-raw/compare_bcfishpass_wsg.R` | `data-raw/wsg_pipeline_run.R` + `data-raw/wsg_compare.R` | Split into the two concerns. `wsg_compare.R` is reference-agnostic, not bcfp-specific. |

The other 8 script renames (`trifecta_provincial.sh` → `wsgs_dispatch.sh` etc.) stay in #172, which builds the autonomy CLI surface on top of this decoupled foundation.

#### Resume-check uses PG, not the filesystem

PG is the canonical state. RDS is a diagnostic side-artifact. Operator can drop PG rows to force re-model, or delete RDS to force re-compare — independently.

#### `--force` flag

Operator-friendly opt-out of all caching for a re-dispatch.

## Exploration notes (2026-05-14, this session)

### Seam location inside `lnk_compare_wsg()`

`R/lnk_compare_wsg.R:109-264` — the function body splits cleanly at line 210 (`lnk_pipeline_persist`). Everything 168-210 is **modelling** (pipeline phases + persist_init + persist). Everything 227-256 is **compare** (rollup queries + assemble + optional mapping_code). The mapping_code branch (199-206, 247-256) optionally calls `lnk_barriers_unify` before persist (link#152) and `.lnk_compare_wsg_mapping_code` after rollup.

### Naming chosen

`lnk_compare_one` (issue body) → `lnk_compare_rollup` (user redirect). Noun = the artifact produced (the long-format rollup tibble). Matches `lnk_compare_wsg` family shape (`lnk_compare_<noun>`).

### Family-shape follow-ups (out-of-scope for #168)

User surfaced naming-as-families during plan review:
- `lnk_compare_mapping_code` as its own export (promotes the `with_mapping_code=TRUE` branch to a stand-alone family member). Requires refactoring `.lnk_compare_wsg_mapping_code` to read persisted state.
- `lnk_compare_wsg` → `lnk_compare_run` rename (symmetric with `lnk_pipeline_run` as family umbrella).
- `lnk_persist_init` + `lnk_pipeline_persist` re-family.

All file-separately after #168 lands.

### Persist-table source of truth

`R/utils.R:153-173` `.lnk_table_names(cfg)` returns `streams = "<persist_schema>.streams"` + `habitat_for(sp)` closure. Used by both `lnk_persist_init` and `lnk_pipeline_persist`. Reused for `.lnk_wsg_persisted()`.

### `lnk_pipeline_run()` always-on barriers

Today `lnk_barriers_unify` only runs when `with_mapping_code=TRUE`. Promoting to always-on in `lnk_pipeline_run()` means `<persist_schema>.barriers` is canonical for any future mapping_code reader. Per-WSG cost is small (single unify + copy).

### Callers of old function (4)

```
data-raw/_targets.R              # lines 49, 69, 78
data-raw/regress_dams_isolation.R
data-raw/rule_flexibility_demo.R
data-raw/run_provincial_parity.R
```

`run_provincial_parity.R` is the loop with the resume bug. The other three are batch wrappers that should call both new functions sequentially.

### Test infrastructure

`tests/testthat/test-lnk_compare_wsg.R` has 5 test_that blocks covering arg validation + phase-order composition via `mockery::stub`. The new tests for `lnk_pipeline_run` + `lnk_compare_rollup` mirror this pattern. Bit-identical-rollup test against live DB needs the existing `skip_if_not_local()` or equivalent pattern — check what helpers exist when starting Phase 2.
