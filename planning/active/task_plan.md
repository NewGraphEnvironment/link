# Task: Provenanced rerun of all WSGs — pre-flight gates (#246), Phases 1–2

`fresh` holds 93 WSGs / 2,865,775 rows accumulated 2026-05 → 2026-08 across
several link and fresh versions, with **no `log` / `log_input` tables at all**.
Not one row is traceable to a run, a config hash, or a date. Before that can be
rebuilt cleanly, three defects have to close — a run started today would
**silently skip 80 of 119 WSGs and exit 0**.

This branch is **Phases 1–2 of the issue plus the bucketing derivation**. The
destructive multi-host wipe, the paid 4-host run and the provenance audit are a
separate session driven by the merged, hardened script.

## Phase 1 — make fresh a real dependency

- [x] `DESCRIPTION`: move `fresh (>= 0.33.0)` Suggests → Imports (keep the
      `Remotes: NewGraphEnvironment/fresh@v0.33.0` pin)
- [x] `R/lnk_preflight_fresh.R` — exported `lnk_preflight_fresh()`, internal
      `.lnk_fresh_required()` (curated symbol list) and `.lnk_fresh_floor()`
      (parses the floor out of link's own DESCRIPTION, single-sourced)
- [x] `tests/testthat/test-lnk_preflight_fresh.R` — both known answers
- [x] `cypher_prep.sh`: `CYPHER_PREP_FRESH_REF` override + export assertion
      replacing the assert-nothing echo at line 66, using the file's own
      tempfile + `if !` idiom (never `$( )`, which discards exit status)
- [x] `cypher_prep.sh`: `CYPHER_PREP_STAGE=install|all` so `--auto-install`
      costs ~3 min not ~20
- [x] `cypher_prep.sh`: write `~/.Renviron` with the cypher's **own** observed
      `LINK_GIT_SHA` / `LINK_GIT_DIRTY` / `FRESH_GIT_SHA`
- [x] `cypher_prep.sh`: header rewrite (the baked-fresh assumption is what
      broke) + fix stale `dispatch_provincial.sh` ref at line 41
- [x] **Sentinel fix** — `study_area_run.sh:203` and `wsgs_run_pipeline.sh:267`
      grep `=== READY`, not `snapshot_bcfp.sh: complete`

## Phase 2 — pre-flight gates in `study_area_run.sh`

### 2a `preflight_local()` — pre-spin, zero cost
- [x] Gate 5: persist-schema guard (arg-time + resolved-collision second layer)
- [x] Gate 4: branch pushed (fetch first) + worktree clean
- [x] Gate 6: resolve and export `FWAPG_GIT_SHA`; fail when unresolvable
- [x] Gate 2: credential probe — doctl leg, tfvars `do_token` leg via direct
      DO API call, s3 backend leg labelled honestly
- [x] `R/lnk_preflight_vintage.R` + `data-raw/host_vintage.R` + tests
- [x] Gate 3a: dispatcher primitive vintage, `--vintage-max-days=N` (default 7)

### 2b `preflight_hosts()` — post-prep, pre-write
- [x] `R/lnk_preflight_stamp.R` + `R/lnk_preflight_parity.R` +
      `data-raw/host_stamp.R` + tests
- [x] Gate 1: cross-host parity keyed on `repo_sha` (**not** `link_sha` — that
      is NA on every pak-installed cypher by construction)
- [x] Gate 3b: cypher primitive vintage
- [x] `--auto-install` remediation (re-run install stage, re-check once)
- [x] Export `FWAPG_GIT_SHA` on the run ssh leg (line 226)

### 2c post-condition + ergonomics
- [x] Gate 7: per-host completeness count before consolidate
- [x] Coverage assertion after burn, before recompute
- [x] `--preflight-only`
- [x] `--refresh-primitives` (must land with gate 3a — m1 is 3 months stale)

## Phase 3 — bucketing derivation

- [x] `data-raw/study_area_buckets.R` — union-find over `frs_wsg_drainage()`
      closures, LPT-pack components into N hosts, emit `--focal=` strings
- [x] Rewrite `research/study_areas.md` from the script's own output
- [x] Verify against the issue's asserted 22 components / 119 modelable

## Phase 4 — testing, docs, release

- [x] Both-known-answers run for every gate, recorded
- [x] `devtools::test()`, `devtools::document()`, `lintr::lint_package()`
- [x] RUNBOOK section; `NEWS.md`; version bump as the final commit
- [x] Edit issue #246 body (three corrections — see findings.md)
- [x] File follow-up #247 (`fresh.snapshot_stamp`). The `fresh::` call-site
      lint was not deferred after all — it shipped as `.lnk_fresh_callsites()`
      plus its drift test. doctl/tofu account-UUID match drafted, not filed.

## Validation

- [x] Tests pass (FAIL 0 | PASS 1603; R CMD check 0 errors)
- [x] `/code-check` — 5 rounds over the branch diff (not per commit; see progress.md). Round 5 clean.
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
