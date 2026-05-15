# Findings — Provincial run autonomy + script renames (#172)

## Issue context

### Problem

After PR #171 (v0.36.1) the operational scripts work but are scattered, inconsistently named, and require operator handholding mid-run. Goal: single command — approved once — that runs end-to-end and lands clean output. M4+M1 baseline first; cyphers opt-in after baseline lands repeatably.

Names lie about scope — these scripts run **any list of WSGs**, not just "provincial".

### Goals

1. **Single-command autonomous run.** `bash data-raw/<umbrella>.sh ...` runs everything (state-clean → snapshot → dispatch → pull → consolidate → burn cyphers if any) without further prompts.
2. **Any WSG list.** `--wsgs=A,B,C` accepted at the umbrella level, auto-split via LPT across configured hosts.
3. **Any config bundle.** `--config=default` or `bcfishpass`, `--schema=<name>`.
4. **Any host subset.** `--no-cyphers` (M4+M1 only) for the validated baseline; `--cy-workspaces=...` for full distributed.
5. **Rename for honesty.** No more "provincial" / "trifecta" / "bcfishpass" in script names that work for any list/host count/reference.

### 16-WSG test set

`CARP, CRKD, FINA, FINL, FIRE, FOXR, INGR, LOMI, MESI, NATR, OSPK, PARA, PARS, PCEA, TOOD, UOMI`

## Naming decision (yesterday's session, confirmed locked-in today)

Resolved before this session started; pulled forward into this plan:

- **Umbrella**: `province_run.sh` → `wsgs_run_pipeline.sh` (typed by user as `wsgs_run_pipeline.R` — confirmed `.R` was a typo for `.sh`, the user is the operator entry point and that's a shell script).
- **Per-host loop**: `run_provincial_parity.R` → `wsgs_run_host.R` (plural `wsgs_` signals collection; suffix `host` signals scope = one host's bucket).
- **Other wrappers**: user picked "Mixed nouns (more descriptive)" — `state_clean.sh`, `progress_check.sh`, `runs_archive.sh`, `buckets_balance.R`, `schema_consolidate.R`.

The singular/plural distinction `wsg_*` (one WSG operations, from #168) vs `wsgs_*` (collection-level operations) reads naturally now that #168 has shipped `wsg_pipeline_run.R` + `wsg_compare.R`.

## Architecture shift vs yesterday's first attempt at #172

The scab fixes from yesterday's first attempt (smoke auto-skip when `--wsgs`, archive `--config`, phantom-cy from `paste0("cy", integer(0))` returning `"cy"` due to R constant recycling) are mostly **no longer load-bearing** because #168's PG-state resume gate makes the loop idempotent:

- A stale RDS no longer silently skips a missing pipeline run.
- Operators can re-dispatch with `--force` to bypass all caching.
- Compare-only re-runs (`pipeline_done && !rollup_ok`) cost ~3s vs ~80s for full pipeline+compare.

What remains genuinely needed:

- `--wsgs=A,B,C` filter in `trifecta_provincial.sh` SPLIT_R block.
- `--no-cyphers` mode (force `N_CY=0`, skip cypher subprocess + wrap + pullback paths).
- `--force` passthrough to the per-host Rscript.
- Phantom-cy bug fix (still real — `paste0("cy", integer(0))` returns `"cy"` length-1; need explicit `if (n_cy == 0L) character(0)` branch).
- `province_run.sh` arg parser surface and config-aware ANN_CSV path.

## Cross-repo coordination (rtj)

`rtj/scripts/cypher/cypher_run.sh:8` references `~/Projects/repo/link/data-raw/run_provincial_parity.R`. After the rename, this reference becomes stale.

User confirmed: direct commit + push to rtj is fine ("no one but us using this stuff"). Order: link's rename PR merges first, then a one-line update on rtj/main. This way `cypher_run.sh` never references a missing file on link/main.

Coordinate via Phase 6 of this plan (not via comms thread — direct commit was approved).

## Reference counts at start of session

```
trifecta_provincial:     15 files reference it
run_provincial_parity:   12
consolidate_schema:       9
archive_provincial_runs:  7
balance_provincial_buckets: 6
```

Most are inside data-raw/ scripts that source each other, plus README/runbook docs and CLAUDE.md. Phase 4 walks each rename + reference update in one commit per file (or one bulk commit — TBD during execution).
