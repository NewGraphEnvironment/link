# Findings — lnk_compare_wsg + provincial parity annotated CSV (#162)

## Issue context

## Problem

Today we have three disjoint sources of "why does this WSG-species-metric diverge from bcfp":

1. `research/provincial_parity_2026_05_01.md` (Class A/B/C/D taxonomy, narrative)
2. `research/bcfp_compare_mapping_code.md` (Phase A per-segment, 4-WSG sample)
3. ~12 PR bodies + issue threads + commit messages (closing each class)

Every time a divergence surfaces during a provincial run, we manually re-derive whether it's already known. The next-WSG investigation often duplicates the BBAR/THOM trace from #158 just to find the same answer.

There is no single artifact a future-us (or anyone) can look at and say: "this BBAR CH +12% rearing — what class is it, what's known, where's the next step." We rediscover.

## Goal

One CSV per provincial run: every (wsg, species, metric) row annotated against a canonical taxonomy. Zero rows ≥2% divergence end up "unexplained" — either they map to a known class with a citation, or they're flagged "needs investigation" with a clear hand-off.

## Output shape

`data-raw/logs/provincial_parity/<TS>_annotated.csv`:

```
wsg, species, metric, unit,
  link_value, bcfp_value, diff_pct,           # rollup lens
  mc_match_pct, mc_n_diffs, mc_top_pattern,   # mapping_code lens (NULL if not run)
  class,                                       # A | B | C | D | MEASUREMENT_ASYMMETRY |
                                               # TOKEN2_RESIDUAL | INTENTIONAL | UNEXPLAINED
  mechanism_ref,                               # link#158, fresh#158, research/<doc>.md, ...
  status,                                      # CLOSED | INTENTIONAL | OPEN | NEEDS_INVESTIGATION
  notes
```

## Single source of truth

`research/bcfp_divergence_taxonomy.yml` — a keyed lookup of every known divergence pattern. Each PR / issue that surfaces a new pattern updates THIS file. The annotation script joins provincial-run output to it.

Example entries:

```yaml
SETN:
  species: all-anadromous
  metric: rearing_stream
  pattern: link > bcfp by 50-200%
  class: A
  mechanism: bcfp barriers_subsurfaceflow stale
  refs: [research/provincial_parity_2026_05_01.md#class-a]
  status: INTENTIONAL  # link correct; awaiting upstream refresh

HORS:
  species: BT
  metric: rearing_stream
  pattern: link < bcfp by 5-9%
  class: B
  mechanism: fresh#158 stream_order_parent rear bypass not implemented
  refs: [fresh#158, research/dimensions_audit.md]
  status: INTENTIONAL  # methodology choice

"*":
  species: "*"
  metric: lake_rearing | wetland_rearing
  pattern: link == 0, bcfp > 0 (diff_pct == -100)
  class: MEASUREMENT_ASYMMETRY
  mechanism: link credits centerline km vs bcfp polygon ha
  refs: [research/default_vs_bcfishpass.md]
  status: INTENTIONAL
```

## Scope — what gets built

1. **`R/lnk_compare_wsg.R` — NEW exported function.** Signature: `lnk_compare_wsg(conn, aoi, cfg, loaded, reference = "bcfishpass", with_mapping_code = FALSE)`. Per-WSG convenience wrapper around the `lnk_pipeline_*` phases + reference queries. Returns a list with `rollup` (linear sums per species) AND optionally `mapping_code` (per-species segment match stats). The `reference` arg leaves room for future non-bcfp comparisons (default-bundle parity, regression detection, federal sources). Initial implementation handles `reference = "bcfishpass"` only.

2. **`data-raw/compare_bcfishpass_wsg.R` — refactor.** Becomes a thin per-WSG orchestrator that calls `lnk_compare_wsg(reference = "bcfishpass")` and persists the RDS. New optional arg `--with-mapping-code`.

3. **`data-raw/compare_bcfp_mapping_code.R` — DELETE.** Its logic moves into `lnk_compare_wsg()` (gated by `with_mapping_code = TRUE`).

4. **`research/bcfp_divergence_taxonomy.yml` — NEW.** Initial population captures every Class A/B/C/D row from `research/provincial_parity_2026_05_01.md` plus MEASUREMENT_ASYMMETRY + TOKEN2_RESIDUAL patterns from `research/provincial_parity_2026_05_11.md`.

5. **`data-raw/annotate_provincial_parity.R` — NEW.** Reads `data-raw/logs/provincial_parity/<TS>*.rds` + the taxonomy, emits the annotated CSV.

6. **`data-raw/trifecta_provincial.sh` — extended.** New `--with-mapping-code` flag (default off for fast runs). Pre-flight check that all 5 hosts (3 cyphers + M4 + M1) are ready. Support `--workspace job1,job2,job3` style for the 3-cypher fan-out.

## Cleanups bundled

- `data-raw/balance_provincial_buckets.R` — dedup bug (yesterday I worked around by writing inline LPT; should land in the canonical script)
- `data-raw/consolidate_schema.R` — `ok=FALSE` false-positive on cypher restores; also need bucket-aware destination cleanup so `streams_habitat_<sp>` pg_restore doesn't dup-key collide. See 2026-05-12 addendum in `research/provincial_parity_2026_05_11.md`.
- Stale `_per_wsg_times.csv` discovery pattern — currently picks up old logs from 2026-05-08 unless you manually rename. Move to an archive convention so only the latest run feeds the LPT.

## Out of scope (separate issues if they come up)

- fresh-side changes (fresh#158 stream-order bypass, fresh#190/191 SK new-geographies) — bake them into the taxonomy with `status: INTENTIONAL_FRESH_DEFERRED` for now.
- Cypher infra (rtj#129 closed; if a different infra issue surfaces, file separately in rtj).
- Default bundle parity — same machinery should work but defer to a follow-up after bcfishpass bundle reaches "zero unexplained".

## Acceptance

- [ ] Provincial run with `--with-mapping-code` finishes in ≤90 min on 5 hosts (3 cyphers + M4 + M1)
- [ ] Annotated CSV contains all 217 WSGs × 8 species × N metrics
- [ ] **Zero rows with `abs(diff_pct) >= 2` AND `class == UNEXPLAINED`** (every ≥2% divergence has either a class label or a "needs_investigation" hand-off)
- [ ] `research/bcfp_divergence_taxonomy.yml` is the only place we record new patterns going forward
- [ ] Runbook (`research/provincial_run_runbook.md`) updated: the CSV is the primary deliverable; existing rollup/mapping_code compare outputs become diagnostic detail

## Phase 7 live run — operational lessons (2026-05-12 → 13)

The first end-to-end live provincial run with the full link#162 machinery surfaced four real bugs + two visibility gaps. Captured here verbatim so future-us doesn't relearn them. All six are fixed on this branch as `Phase 7 hardening`.

### 1. M4's installed library lagged the dispatched R session

What happened: pushed the Phase 7 bcfp-not-modeled fix at T+64:11 and `pak::local_install`'d on M1 + cyphers in Step 11. Step 14 (M4 install) didn't fire until T+80:54 — AFTER the resume dispatched at T+65:45. M4's R session loaded `library(link)` at dispatch with the pre-fix code. Result: 10 bcfp-not-modeled WSGs in M4's bucket errored even though every other host had the fix on disk.

Lesson: **install before dispatch, on every host without exception**. The orchestrator already does a preflight-version check against on-disk `packageVersion("link")` but doesn't check whether the dispatched R session will load that version. Real fix: never reinstall on a host whose R session is already mid-run — install once, before ANY dispatch on that host.

### 2. Cypher snapshot's `fresh.streams` carried stale GENERATED DDL — fixed

What happened: `cypher-20260512-warm` snapshot was baked at a point where `fresh.streams` had previously been touched by `fresh::frs_col_generate()`, leaving `gradient` as `GENERATED ALWAYS AS (...) STORED`. `lnk_persist_init` uses `CREATE TABLE IF NOT EXISTS` (no-op when table exists, no DDL drift detection), so the stale DDL survived. `lnk_pipeline_persist`'s `INSERT INTO fresh.streams (..., gradient, ...)` then failed with `cannot insert a non-DEFAULT value into column gradient`. **All 93 cypher WSGs errored** at the persist step.

Runbook documented this with a manual `DROP TABLE IF EXISTS fresh.streams CASCADE` step — operator-must-remember, not codified.

Fix shipped this commit: `lnk_persist_init` now detects unexpected GENERATED columns at init time. Errors loud with a clear message + offers `force_recreate = TRUE` to DROP+recreate. Tests cover detection, force-recreate, and idempotent no-op paths. The manual runbook step is now a function arg.

### 3. Cypher-side R output was invisible — fixed

What happened: orchestrator's per-host log files (`data-raw/logs/<TS>_trifecta_provincial_cypher_*.txt`) captured only `cypher_run.sh`'s wrapper output — tunnel setup messages, the SSH command echo, exit codes. The actual cypher-side R output (where errors fire) lived at `rtj/scripts/cypher/logs/<TS>_cypher-run_*.txt` in a different repo. Per-host log + RDS counts ("31/31 on each cypher!") suggested everything was fine. The 93 error stubs were invisible until I went looking after the fact.

Fix shipped this commit: `trifecta_provincial.sh` now scp-pulls each cypher's R log back to `data-raw/logs/<TS>_trifecta_provincial_cypher_<ws>_R.txt` at run completion. Cross-repo log boundary closed.

### 4. "217/217 pulled" headline was true but misleading — fixed

What happened: error stubs ARE RDS files. The orchestrator counted total pulled files, not successful-rollup files. `local RDS file count: 217 / 217` was both true and a lie — 103 of those 217 were error stubs. Annotated CSV had only 114 WSGs' data; the headline didn't say so.

Fix shipped this commit: orchestrator now inspects each RDS and prints `local RDS: 217/217 pulled — 114 OK, 103 errors`. When errors present, it lists the cypher-side R log paths so the operator goes to the right place first.

### 5. Per-WSG soft-fail wastes compute when WSG #1 fails for systemic reasons — fixed

What happened: each cypher's R session encountered the gradient DDL error on its FIRST WSG, then `tryCatch`-saved an error stub and CONTINUED to the next. Same error 31 times per cypher × 3 cyphers = 93 confirmed-failures × ~80 sec each = ~120 min of wasted compute.

Fix shipped this commit: `--fail-fast` flag on `run_provincial_parity.R`. When set, the first per-WSG error aborts the loop. Smoke passes it automatically. Full provincial defaults to soft-fail (some WSGs legitimately error for non-systemic reasons).

### 6. Smoke needs explicit pass/fail assertion, not just "ran without crashing" — fixed

What happened: the smoke ran 5 small WSGs at Phase 7 start. All 5 hosts exited 0, "smoke passed." But the smoke didn't INSPECT what was in those RDS files. If any cypher's smoke WSG had been an error stub (it wasn't — luck of the WSG choices), we would have caught the DDL issue 80 minutes earlier.

Fix shipped this commit: `trifecta_smoke.sh` now snapshots the RDS dir pre-dispatch, finds new files post-dispatch, and explicitly inspects each. Any error stub → smoke exits non-zero with clear message identifying the failing WSG + pointing at the cypher R log. "Smoke passed" now means "every smoke WSG produced a valid tibble," not "scripts exited 0."

### Cost summary

- ~120 min wasted compute on confirmed-failure WSGs (lesson #5)
- ~10 hours of cyphers running unattended overnight because the burn-down script silently failed on an unrelated grep bug (separate Phase 6 cleanup issue — `phase7_post_run.sh` needs the same trap/test treatment)
- DO spend: ~$1.80
- Engineering time investigating after the fact: ~2 hours

Future-us cost: 0 (these are now fail-fast or fail-loud, with tests).

