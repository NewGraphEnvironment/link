# Study-area run (tunnel-free, M1-dispatch)

Lean alternative to the 5-host `provincial_run_runbook.md` for running
**study-area** mapping_code parity.

> **Corrected 2026-08-31.** This document used to say "the 3 FWCP study areas".
> Only **Peace** is FWCP; **Fraser and Skeena are HCTF** (provincial). And a
> project's **field scope** (the WSGs in its GIS/Mergin AOI,
> `rtj/scripts/gis/projects/<name>/project.yml`) is not its **model scope** (the
> WSGs its report analyses, `wsg_code` in the reporting repo) — Peace is 8 field
> vs 16 model. Conflating the two cost an hour. Full table in
> `research/study_areas.md`. Reuses the
proven per-WSG build + cypher lifecycle but is **tunnel-free** (compare =
local bcfp snapshot, no `:63333`) and **M1-as-dispatcher** (no M4). Built for
link#175. Companion: `provincial_run_runbook.md` (shared mechanics),
`RUNBOOK.md` (the access/mapping_code machinery), `data-raw/README.md`.

## One command

```bash
cd ~/Projects/repo/link
# largest area on the dispatcher (fast/free M1); smaller areas on the cyphers
bash data-raw/study_area_run.sh \
  --cy-workspaces=job1,job2 \
  --focal=<Fraser focal csv>  \   # -> dispatcher (M1)
  --focal=<Peace focal csv>   \   # -> cy1 (job1)
  --focal=<Skeena focal csv>      # -> cy2 (job2)
```

Focal lists + study-area definitions: [`research/study_areas.md`](study_areas.md).
`--focal` count MUST equal `1 + N(--cy-workspaces)`; first = dispatcher, rest =
cyphers in order. Dispatcher-only (no cyphers): omit `--cy-workspaces`, pass one
`--focal`. Pre-req: dispatcher has `fresh.streams_vw_bcfp`
(`snapshot_bcfp.sh --with-bcfp-views`); branch pushed to origin (cyphers pull it).

## What it does

1. **Pre-flight** (tunnel-free): local fwapg up, `fresh.streams_vw_bcfp` present,
   doctl/tofu (only if cyphers).
2. **Drainage-closed DS-first buckets** (`study_area_wsgs.R`): each focal set →
   its closure (every WSG it drains through, via `lnk_wsg_resolve()`,
   `f.outlet <@ w.outlet`) ordered downstream-first (`nlevel(outlet) ASC`),
   then **filtered to bundle-species presence** (link#157).
3. **Spin + prep** cyphers (`cypher_up.sh`, `cypher_prep.sh` with
   `CYPHER_PREP_BRANCH=<dispatcher branch>`).
4. **Run** each host's bucket DS-first (`wsg_run_one.R` =
   `lnk_pipeline_run(mapping_code=TRUE)`), dispatcher local + cyphers via ssh,
   per-WSG **soft-fail**.
5. **Consolidate** cyphers → dispatcher (`schema_consolidate.R`, shape-tolerant).
6. **Burn** cyphers (then a trap-EXIT safety net).
7. **Post-consolidate recompute ALL run WSGs** on the dispatcher via
   `wsg_recompute_one.R` → [lnk_access()] `merge=TRUE` (cheap access-only,
   reuses persisted streams/habitat/barriers; ~10s/WSG) + `lnk_mapping_code`.
   Because it is cheap, every run WSG is re-settled — bucketing is a speed
   knob, not a correctness lever (link#205).
8. **Compare** all run WSGs tunnel-free (`study_area_compare.R`) → CSV.

## Post-consolidate recompute — the correctness guarantee

Each WSG's accessibility (hence its `mapping_code` token1 ACCESS/SPAWN/REAR and
token2 DAM/…) depends on whether a blocking barrier exists **downstream** —
possibly in a *different* WSG (the provincial-accumulation property,
`RUNBOOK.md` §5). When WSGs are distributed across machines, each machine holds
only its own bucket's barriers while it runs, so a WSG's access is computed
against an **incomplete** barrier set → wrong tokens.

**Drainage-closed + DS-first bucketing is NOT sufficient on its own.** It
*reduces* divergence (downstream often persists first within a bucket) but does
not eliminate it: downstream barriers can be cross-bucket, or arrive late in
DS-first order. Caught 2026-05-25 — FINA 75.5% / PARA 68.6% per-host → both
**99%+** after re-modelling on the full consolidated barrier set.

So the methodology is **distribute (any bucketing) → consolidate → recompute →
compare**, and the *recompute* is what makes it correct **regardless of machine
count or WSG assignment**. The recompute is **`lnk_access(merge=TRUE)` +
`lnk_mapping_code`** (link#205): cheap access-only, reusing the persisted
streams / habitat / barriers / barrier_overrides — no full pipeline, ~10s/WSG
(FINA: 11.86s wall vs ~90s full pipeline, identical bcfp parity). Two
non-obvious things had to be true for it to be cheap:
1. AOI-scope the segments as a **real table** (with indexes + `ANALYZE`),
   not a view — otherwise the planner picks the ~800k-row barriers as the
   outer driver and the join cost explodes by ~1000×.
2. Persist `streams` / `barriers` need **ltree GIST/btree indexes**
   (`lnk_persist_init` builds them; matches `fresh`'s working-table pattern).
3. `lnk_mapping_code` must filter access by `watershed_group_code` when the
   table has that column (persist) — the original `id_segment IN (…)` query is
   cartesian against persist because `id_segment` is per-WSG, not globally
   unique (link#203).

## Gotchas that cost real time (2026-05-25)

- **A per-WSG FATAL burns the cyphers with un-consolidated data.** A
  species-less closure WSG (LEUT) errored `No species resolved for AOI` →
  `|| exit 1` → driver FATAL → trap `cypher_down` → an entire run's Peace+Skeena
  data gone. **Fixes:** species-presence filter the closure (link#157) AND
  per-WSG soft-fail (never abort a host before consolidate). The cyphers were
  NOT externally destroyed — the driver's own trap burned them.
- **Cyphers checkout `main` by default.** The driver scripts + branch link only
  exist on the feature branch → cyphers must run `CYPHER_PREP_BRANCH=<branch>`,
  and the branch must be **pushed** first (`cypher_prep` does `git fetch origin
  && git reset --hard origin/$BRANCH`).
- **Fresh-droplet sshd race.** `cypher_up` returns when the IP is assigned,
  before sshd is up → scp `Connection closed`. Poll ssh before scp.
- **Wide-table shape drift across hosts.** `streams_access` /
  `streams_mapping_code` carry one column per species; a host seeding persist
  from `parameters_fresh` (11 sp) vs `cfg$species` (8 sp) breaks the positional
  COPY-consolidate. `cypher_prep` now uses `cfg$species`; `schema_consolidate`
  COPYs shared columns by name (link#204).
- **Cypher cost is ~$0.06/hr each.** "Minimize idle" means don't leave them up
  for HOURS (the 2026-05-12 10-hr incident), not shave minutes. Don't
  over-engineer early-burn for cents.

## Scripts

| Script | Role |
|---|---|
| `data-raw/study_area_run.sh` | driver: pre-flight → spin → prep → run DS-first → consolidate → burn → compare |
| `data-raw/study_area_wsgs.R` | focal → drainage-closed, DS-first, species-filtered WSG list |
| `data-raw/wsg_run_one.R` | one WSG: `lnk_pipeline_run(mapping_code=TRUE)`, local, host-agnostic |
| `data-raw/wsg_recompute_one.R` | one WSG cheap post-consolidate recompute (`lnk_access(merge=TRUE)` + `lnk_mapping_code`) — link#205. Sets `statement_timeout`/`lock_timeout` so a runaway/locked query fails fast |
| `data-raw/study_area_compare.R` | tunnel-free `lnk_compare_mapping_code` loop → CSV |

## Cypher operational gotchas

The tunnel-free M1-dispatch runner tripped over things the older `wsgs_run_host.R`
+ `research/provincial_run_runbook.md` already solved. The worst (2026-05-25): a
species-less closure WSG (LEUT) errored "No species resolved for AOI" → `|| exit 1`
→ driver FATAL → the trap's `cypher_down` **burned the cyphers with their
un-consolidated data** — a whole run's Peace + Skeena gone, self-inflicted (the
driver's own trap, not external destruction).

- **Always species-filter the WSG set** to bundle-species presence (link#157,
  `wsgs_run_host.R:88` pattern) — closure pulls in unmodelable WSGs.
- **Per-WSG soft-fail; never abort a host before consolidate** — one bad WSG must
  become a compare gap, not total data loss.
- **Cyphers checkout `main` by default** → pass `CYPHER_PREP_BRANCH=<branch>` AND
  push the branch first (`cypher_prep` does `git reset --hard origin/$BRANCH`).
- **Wait for sshd before scp** to a fresh droplet (`cypher_up` returns pre-sshd).
- **Cyphers cost ~$0.06/hr each** — "minimize idle" means don't leave them up for
  hours, not shave minutes; don't over-engineer early-burn.
- **Read the records first** (`RUNBOOK.md`, `research/provincial_run_runbook.md`,
  `data-raw/wsgs_run_host.R`) before re-deriving orchestration.

### Correctness knob: post-consolidate recompute

Per-segment access (hence mapping_code) depends on **downstream** barriers, possibly
in another WSG (provincial accumulation, RUNBOOK §5). Distributed hosts each see only
their own bucket's barriers mid-run → incomplete → wrong tokens. **Drainage-closed +
DS-first per-host is NOT sufficient** (it only reduces divergence): 2026-05-25 had
FINA 75.5% / PARA 68.6% per-host → 99%+ only after re-modelling on the consolidated
barrier set. So recompute the diverged WSGs on the dispatcher post-consolidate.
Bucketing is a speed knob, not a correctness lever. Authoritative result: median
**99.66%**; genuine divergences SETN salmon ~94%, UNRS BT 61.8%. The full-pipeline
recompute is ~2× on diverged WSGs; a cheap access-only recompute (#205) makes
recompute-all bulletproof + ~1×.

---

## Pre-flight gates (v0.47.x, link#246)

`study_area_run.sh` no longer trusts its inputs. Two blocks, answering two
different questions — a cypher's software is *predictable* from the dispatcher
before the cypher exists, so validate that pre-spin and confirm it post-prep.
**Predict before spend; verify before write.**

`preflight_local()` (pre-spin, free): dispatcher `fresh` completeness, branch
pushed *and* worktree clean, `FWAPG_GIT_SHA` resolvable and exported, primitive
vintage, and **both** DigitalOcean credentials forced through a real API call.

`preflight_hosts()` (post-prep, pre-write): cross-host parity keyed on
`repo_sha`, and cypher primitive vintage. A failure exits 1, which trips the
EXIT trap and burns — bounding loss at prep rather than a whole run.

Post-conditions: every host must account for its whole bucket before
consolidate, and every run WSG must have rows in the persist afterwards.

### Flags added

| flag | |
|---|---|
| `--preflight-only` | run local gates and exit, zero spend. **Reports what it did NOT check** |
| `--refresh-primitives` | `snapshot_bcfp.sh --with-bcfp-views --force` first. Default off |
| `--vintage-max-days=N` | staleness window, default 7 |
| `--prep-ssh-wait=N` | wait for `cypher@`, default 600s — see below |
| `--auto-install` | on parity mismatch, re-run the cyphers' install stage, re-check once |
| `--preflight-note="why"` | downgrades **only** vintage and parity, and only with a written reason. There is deliberately no global bypass |

### Operational facts worth knowing before a run

- **`cypher_up` reports ready ~227s before `cypher@` works** on a snapshot spin.
  Fixed upstream (NewGraphEnvironment/rtj#250 — it now polls `cloud-init status`
  rather than a marker baked into the image), but `--prep-ssh-wait` exists
  because a caller should not depend on that being right.
- **The run dirties its own repo** — it writes logs into the tracked
  `data-raw/logs/study_area_run/`, and `snapshot_bcfp.sh` stamps
  `bcfp_baselines.csv` on each cypher. So the dirty check runs pre-spin only.
- **A wipe is NOT required for a provenanced rebuild.** `lnk_pipeline_persist`
  replaces per WSG (`DELETE ... WHERE watershed_group_code = <aoi>` then INSERT),
  so re-running a WSG overwrites it. Verified 2026-08-31: the 93 WSGs then in
  `fresh` were a strict subset of the 119-WSG run, zero orphans.
- Hosts are **not** interchangeable: dispatcher 0.0391 vs cypher 0.0872 min per
  1000 persisted segments — **2.23x**. `study_area_buckets.R` packs by finish
  time; see `--host-speeds=`.

Measured timings and the four defects that produced these numbers:
`research/run_record_2026_08_31_cypher_pilots.md`.

## Operational facts from the first real multi-host run (2026-08-31, 34 WSGs)

Migrated from machine-local memory 2026-09-01 (soul#47). The 2026-05-25 gotchas
above still stand; these are additional and were learned on the field-scope run
(`20260831_232553`, 3 hosts, 158 min, ~$0.83).

- **Launch a long run DETACHED — `nohup … & disown`.** A run started inside a
  tool-managed background process is killed when the harness reclaims it.
  Measured: killed at 33 min, mid-modelling. The EXIT trap fired correctly and
  burned both droplets, so the loss was ~$0.30 rather than an overnight bill —
  but the run was gone.
- **Never touch the repo while a run is in flight.** The dispatcher runs via
  `pkgload::load_all()`, and the recompute re-reads git state for `lnk_stamp()`.
  An edit mid-run risks reading a tree that never existed, and stamps
  `link_dirty` onto part of one run.
- **`fresh_sha` is non-NULL on every host from link#264 onward.** It was NULL on
  the dispatcher for 24 of the first 39 logged rows, and the stated reason —
  "m1 installs `fresh` locally, `RemoteType: local`, no `RemoteSha`" — was
  measured **false** on 2026-09-01: m1's install carried `RemoteType github`,
  `RemoteRef v0.33.0` and a `RemoteSha` byte-identical to the cyphers'. The
  resolver simply never read the field. It does now, so a verification
  asserting it non-NULL everywhere is correct rather than a false failure, and
  `study_area_verify.sql` asserts exactly that. **Runs logged before v0.50.0
  still carry the NULLs** and are not retroactively fixable.
- **`link_dirty` is currently always TRUE on the dispatcher, and it is FALSE** —
  the run's own logs land in the tracked `data-raw/logs/`. #257.
- **Measured timing, 34 WSGs / 3 hosts, SECOND run 2026-09-01 (`20260901_234743`):
  133 min** — spin + prep + parity ~11, then modelling / consolidate / recompute +
  compare. 25 min faster than the 2026-08-31 run below on the same scope and host
  count; the recompute was parallel this time (link#250), which is most of it. Same
  buckets, 19 Fraser / 9 Peace / 6 Skeena, reproducible from the focal sets in
  `research/study_area_scope_and_funders.md`. **First run with complete code
  provenance:** `fresh_sha`, `fresh_dirty`, `fresh_sha_source` and `bcfishobs_sha`
  non-NULL on all 34 rows across 3 hosts, one distinct input-SHA set, `link_dirty`
  0 everywhere, `study_area_verify.sql` exit 0 with `expected_n=34`. Logs committed
  under `data-raw/logs/study_area_run/20260901_234743*`.
- **Measured timing, 34 WSGs / 3 hosts:** 158 min total — spin + prep + parity
  ~10, modelling ~83, consolidate + burn + coverage ~11, recompute + compare
  ~55. **Correction 2026-09-02: the recompute runs over the RUN's WSGs, not the
  schema.** This said "all WSGs in the schema (95 at the time), not the run's
  34, which is why it dominates". `ALL_WSGS` is the union of the host buckets
  (`study_area_run.sh:1306`), and the 2026-09-01 run logged
  `recompute (lnk_access, 34 WSGs, -j4)` against a 95-WSG schema. So it **does**
  scale with scope — 217 WSGs is ~6.4x, not a constant — and the inference that
  parallelising beat adding machines rested on a false premise. Narrowing the
  set to `run ∪ upstream(run)` is #274, unmeasured. #250 parallelised it; see
  `research/recompute_parallel_2026_09_01.md` for what that did and did not buy.
- **Verify a completed run against the DB, never the exit code.** Filter
  `fresh.log` on `date_end`, **not** `date_start` — a killed run leaves rows
  with `date_start` set and `date_end` NULL, which a naive count reports as
  done. `data-raw/study_area_verify.sql` is the reusable checker. Note it cannot
  yet group a run as a unit: `run_id` is per WSG, so reconstruction is by time
  window until #262 lands.
- **Cyphers cost $0.25/hr each** (`s-8vcpu-32gb-amd`, from
  `doctl compute size list`, 2026-08-31). An earlier note said $0.06, which was
  wrong. "Minimize idle" therefore means do not leave them up for hours — it is
  not a reason to shave minutes or to over-engineer an early burn.
- **Referencing a repo in a markdown FILE never notifies anyone.** Only
  issue/PR bodies, comments and commit messages create cross-references. So
  scrubbing an `owner/repo#N` form from docs is safe; writing that form in the
  commit message that does the scrub is what would notify.
