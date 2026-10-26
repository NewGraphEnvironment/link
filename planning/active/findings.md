# Findings — study_area_run.sh: recompute each group as soon as its downstream groups are consolidated (#374)

## Issue context

## Problem

The post-consolidate recompute starts only after every host's leg has finished and every host is consolidated. On `20261023_074321-24d85e8c` it took 110 min at `-j8` over 240 groups, after a 42 min consolidate. The cloud legs had finished about four hours before the dispatcher's. So the recompute's whole cost lands on the critical path, even though most groups had their inputs on the dispatcher hours earlier.

## Proposal

Recompute a group as soon as everything its access reads is on the dispatcher, not when the whole run is.

What a group's recompute reads, from `data-raw/wsg_recompute_one.R` and `barriers_views_build.R`:
- its own persisted rows;
- the schema-wide barrier views, which are views over the persisted `barriers` and `barrier_overrides`. Access is resolved past downstream barriers, so the rows that matter are those of the groups on its flow path to the outlet. That is its downstream closure (`lnk_wsg_resolve()`).

So a group is ready once it and every group downstream of it are consolidated (the dispatcher's own groups count once their build closes). The driver would start a recompute job for each group as it becomes ready, in place of one pool after the last consolidate. Paired with #369, which consolidates each cloud host when its own leg finishes, most of the recompute would then overlap with the slowest leg.

## To verify before building

- **Does the recompute read anything from upstream groups?** Lifts are counted from every group's observations (#349), but at model time, into the barrier-holding group's own `barrier_overrides`. If nothing at recompute time reads upstream groups, the downstream closure is the whole dependency set. Settle this from the code and with a test: recompute one group with only its closure present, against the same group recomputed after the full run. The two digests must match.
- **Does the dispatcher's database have room?** The dispatcher models its own leg on the same database the recompute uses, and past `-j8` the database VM, not R, looked like the limit (`data-raw/logs/recompute_width_20261020/`). Measure the dispatcher leg's per-group minutes with and without concurrent recompute jobs.
- **Consolidate and recompute on the same tables at once:** consolidate deletes and copies one source's groups, and a recompute rewrites one group's `streams_access` / `streams_mapping_code`. Check that the two never touch the same group, and what locks each takes.

## Acceptance

- On a run, the recompute's last job ends within (longest single recompute job) of the last consolidate, not 110 min after it.
- Per-group digests of `streams_access`, `streams_mapping_code` and the gated habitat flags match a run whose recompute started after the full consolidate.
- `study_area_verify.sql` passes.

## Related

#369 (consolidate on finish), #371, #348 (a missing group costs only itself), #349 (province-wide lift counting).


## Phase 1 — what a recompute reads and writes, and the locks (2026-10-26)

`wsg_recompute_one.R`, per group G, all in the persist schema `<s>`:

| step | reads | writes | lock on shared relations |
|---|---|---|---|
| prior snapshot | `streams_access` (G rows) | new `zz_lnk_access_prior_<g>` | AccessShare |
| `lnk_access(merge = TRUE)` | `streams` (G rows → `zz_lnk_streams_<g>`), views `barriers_<sp>_access`, `barriers_{anthropogenic,pscis,dams}_unified` over **every** group's `barriers` and `barrier_overrides`, walked downstream by position (`fwa_downstream`, equivalents within 1 m) | `UPDATE streams_access WHERE wsg = G` | AccessShare on views/tables; RowExclusive on `streams_access` |
| `lnk_habitat_gate` | `streams_access`, `streams`, prior | `UPDATE streams_habitat_<sp> WHERE wsg = G` (one-way) | RowExclusive |
| `.lnk_mapping_code_persist` | `streams_access`, **view `streams_habitat_long_vw`**, `streams` | DELETE + INSERT `streams_mapping_code` WHERE wsg = G, one transaction | AccessShare on the view; RowExclusive |
| `lnk_wsg_downstream_check` | `cabd.dams`, persisted `barriers` of downstream groups | — | AccessShare |
| log | — | `log_recompute` row | RowExclusive |

Session: `statement_timeout 10 min`, `lock_timeout 60 s`. Nothing reads another group's access, habitat or mapping code, so recomputes are order-independent among themselves (#250's parity runs).

Beside it on the dispatcher:
- **Model persist** (`lnk_pipeline_run`): `lnk_persist_init()` per group: `CREATE TABLE IF NOT EXISTS` (no table lock once present), catalog-checked indexes and columns (#369), and **`CREATE OR REPLACE VIEW streams_habitat_long_vw` unconditionally** (`R/lnk_persist_init.R:539-544`): an AccessExclusiveLock on a view every recompute reads, once per dispatcher group. With jobs reading it, each dispatcher group's init queues behind them and every new reader queues behind the init (#250's convoy). Must be fixed before early recompute (review B2). Then `lnk_pipeline_persist`: DELETE + INSERT WHERE wsg per table (row locks only). The model's own barrier views are in its working schema (`R/lnk_pipeline_run.R:258`), never the persist schema's.
- **Consolidate** (`schema_consolidate.R`): step 3.5 one autocommitted DELETE per persist table for the bucket, step 4 one COPY per table (RowExclusive), log tables by a one-transaction staged replace. No DDL, TRUNCATE or ANALYZE on the dispatcher. Not one transaction across tables, so a group mid-copy is visible half-there: readiness must never count a group whose host is `in_flight`.

## Phase 1 — which groups a recompute reads (2026-10-26)

`data-raw/recompute_deps.R`, three rules over FWA (`deps.tsv` in `data-raw/logs/recompute_early_374/`):

| rule | pairs | groups with any | median per group |
|---|---|---|---|
| closure (`frs_wsg_drainage`, #374's proposal) | 965 | 184 | 4 |
| owner (groups with a segment on the path) | 1,243 | 198 | 5 |
| line (groups touching any line on the path) | 2,211 | 208 | 9 |

- **The closure is not the dependency set.** The owner rule contains it in every group and adds groups in 150 of 241. A watershed group is not one drainage: coastal groups hold many rivers, and inland groups hold tributaries that enter another group's main stem, so a group's own segments drain through groups its outlet never reaches. It reproduces #361's finding unprompted: TOOD's extra dependencies include FROG, LKEC, UKEC and ULRD; NATR's include the Fraser groups through its two Fraser-coded segments.
- **The owner rule is not complete by construction (review B1).** Gradient barriers are found along the whole of every line a group touches and persisted under its own code. In `fresh_default`: 1,224 barrier positions are held by more than one group, all gradient, up to 13 holders (every Fraser main-stem group). Copies agree at all but 1 position, and no override copy differs; 1,864 rows are held by a group that does not own the segment, of which an owner holds an identical copy for all but 2; 285 rows sit on no persisted segment. So the owner rule is right for this build's data save a handful of rows, and controls are AOI-filtered, so the next build could differ.
- **The line rule is complete by construction**, and the scheduler uses it: every barrier row is on a line its holder touches (gradient: the whole line; every other source: the holder's own segments), and an override sits at its holder's own barrier positions.
- **FWA's unassigned codes (`999…`, 208,189 construction segments) are left out on both sides.** Unfiltered, they made every group depend on 245 others. No persisted segment carries one, and `999` is never an ancestor of a real code.
- FWA leaves 158,188 segments without a local code; the line rule needs none, so they stay in it (leaving them out dropped 52 pairs).

## Phase 1 — simulation (2026-10-26)

`data-raw/recompute_schedule_sim.R` replays `20261023_074321-24d85e8c` (240 pool groups, `-j8`, longest first, job = `log_recompute` minutes + 9.7 s gap). Cloud groups land at their host's consolidate end, consolidated as each leg ends (#369) for the copy minutes the run logged (12.7 / 14.0 / 12.9). Minutes from the first model start:

| scenario | rule | recompute end | tail after the last landing | saving | job-min run before the dispatcher leg ends |
|---|---|---|---|---|---|
| recorded | end (today) | 670.8 | 110.4 | — | 0 |
| recorded | line | 581.4 | 21.0 | 89.4 | 775.6 |
| recorded | owner | 563.6 | 3.3 | 107.2 | 865.0 |
| recorded | closure | 563.2 | 2.8 | 107.6 | 870.2 |
| no stalls | end (today) | 375.1 | 110.7 | — | 0 |
| no stalls | line | 336.9 | 72.6 | 38.1 | 213.1 |
| no stalls | owner | 326.1 | 61.7 | 49.0 | 299.3 |
| no stalls | closure | 323.1 | 58.8 | 51.9 | 323.2 |

- The honest case is "no stalls": legs end close together (dispatcher 253, last consolidate 264), so most groups read something from the last host to land, and the pool is throughput-bound after it (837 job-minutes at `-j8`). Early recompute still takes 38 min off the critical path.
- Under "recorded" the dispatcher leg ran 5 h past the cloud legs (KTSU's stall, OKAN's), and nearly the whole pool fits inside it.
- The owner rule would buy 11 more minutes than the line rule in the balanced case: the price of the control asymmetry (review S1).
- Not modelled: contention. The headroom benchmark measures it.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| Line rule made every group depend on 245 others | FWA's all-`999` unassigned code is an ancestor of itself across groups; leave `999…` codes out |
| Line rule by `blue_line_key` had 52 fewer pairs than by code | Its segment table dropped NULL local codes, which only the owner rule needs |
| Simulated baseline pool started 44 min after the leg | `^\[[0-9:]+\]` matched R's `[1]` print prefix in the consolidate log; anchor on `hh:mm:ss` |
| Residual ownership probe ran 17 min | Unindexed self-join; cancelled before the headroom benchmark, to re-run indexed |
