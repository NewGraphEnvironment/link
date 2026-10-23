# Findings — Provincial run: can a drainage component be split across hosts now that the recompute settles access? (#361)

## Issue context

**If we do it:** a provincial `default` run's modelling stops being bounded by its largest drainage component (the Fraser, 205 of 873 host-minutes), so more cloud hosts shorten it, toward the slowest single group (16.5 min). **If we never do:** modelling cannot finish in under ~205 min however many hosts are added, and a fifth cloud host buys nothing.

## Problem

`study_area_buckets.R` packs whole drainage components onto hosts (union-find over per-group `frs_wsg_drainage()` closures), and each host models its component downstream-first. On run `20261017_004619-3f4c713b` (241 groups, `fresh_default`):

| | host-minutes |
|---|---|
| modelling, all groups | 873 |
| Fraser component (68 groups) | 205 |
| next largest (Peace, 26 groups) | 107 |
| slowest single group (SETN) | 16.5 |

So the dispatcher's Fraser bucket sets the floor, and four cloud hosts already fill the other 668 min under it (`research/study_area_run.md`, "Hosts against wall clock").

The rule was written for two reasons (`study_area_buckets.R` header):
1. Cross-group `;DAM` and access need downstream groups' barriers persisted first.
2. Overlapping closures would model a group on two hosts, and consolidate would keep whichever finished last.

## Why it may no longer hold

- **Reason 1.** At model time, a group reads other groups' results only through `<persist_schema>.barriers` (the barrier views behind `lnk_pipeline_access()` and the mapping code; `R/lnk_pipeline_run.R`, steps 0 to 2). The post-consolidate recompute rebuilds `streams_access`, `streams_mapping_code` and, since #349, the habitat flags from every group's persisted barriers. That has been the correctness guarantee since #175 ("bucketing is a speed knob"), and `study_area_run.sh` already models with `LNK_GUARD_DOWNSTREAM=warn` and `LNK_HABITAT_GATE=0`.
- **Reason 1, the barriers themselves.** A group's persisted barriers come from its own inputs: natural barriers, overrides counted over `observations_province`, and CABD dams. As far as read, none of these is another group's output.
- **Reason 2.** Overlapping closures only matter when hosts model closures. A province-wide run assigns each group to exactly one host.

None of this is tested. In particular, `lnk_access(merge = TRUE)` reads its own prior output (`access_<sp> = 2` is kept), so model-time access built from a partial barrier set could survive the recompute.

## Proposal

1. **Test.** Model one component two ways into two scratch schemas, then recompute both and compare digests (`recompute_checksum.sql`, habitat tables included):
   - whole and downstream-first;
   - split across two hosts in a deliberately bad order, upstream groups first.

   The Peace component (26 groups, 107 min) is big enough and holds the shared Peace barrier rows that #349 depended on.
2. **If they are identical,** let `study_area_buckets.R` pack single groups (LPT on measured per-group time from `log`) for a province-wide run, keeping the component rule for focal sub-province runs, where closures decide which groups are modelled at all.
3. **If not,** name the input that differs, which says what the component rule protects.

## Before the run (link v0.68.0 on fresh v0.42.0; owed by #364 and #367)

The next provincial `default` run is also the re-model #364 left owed, and the first run at v0.68.0 (#367: a reproducible PSCIS pick, and the US dam placeholders as barriers under `default`). Do these in order:

- [ ] Build at link v0.68.0 or later. `data-raw/cypher_prep.sh` installs link and fresh from the DESCRIPTION pin on each spin; do not use `scripts/update_hosts.sh`, which installs fresh from main (#269).
- [ ] Re-prep every cypher for the fresh v0.42.0 pin (`data-raw/cypher_prep.sh`). `lnk_preflight_fresh()` hard-fails on a host whose fresh lacks `frs_habitat_predicates(near_river_table)` or `.frs_near_river_specs`; confirm it passes on each host before dispatch.
- [ ] Decide at the plan gate, recommendations first: keep today's `fresh_default` under a new name (`fresh_default_20261017`) for the parity re-score's segment diff, or build over it; refresh the primitives (`--refresh-primitives`) or keep the 2026-10-17 load.
- [ ] Under `default`, a group upstream of a US dam placeholder (the BC Columbia above the border, the Kettle, the Skagit) fails the downstream guard until KETL, LARL and SKGT are persisted at 0.68.0. A full run orders them correctly; a partial re-model of today's schema fails `wsg_recompute_one.R`'s error-mode check for those groups.
- [ ] Re-model every group into `fresh_default` at link >= 0.68.0. Until then `lnk_habitat_validate()` refuses the schema under `default`: it has no `streams_near_river` table and no `log.near_river` column.
- [ ] The split test in the Proposal can run on this same run, so it costs no extra build.
- [ ] After it, re-score bcfishpass parity (`research/bcfishpass_parity.md`). The #367 pick moves picks toward bcfishpass's (656 of 17,377 PSCIS change modelled crossing against 0.67.0), so parity can move too. CO moves with its 1050/1150 gradient test (ADMS 352.55 -> 352.33 km, BULK 2,215.57 -> 2,214.12; `data-raw/logs/wetland_door_364/`).

## Not in scope

The recompute itself. Measured 2026-10-20: 8 workers are 1.43x 4 on 53 groups (about 154 to 108 min at 241), and the database VM (6 CPUs) looks like the limit past 4 (`data-raw/logs/recompute_width_20261020/`).

Relates to #246, #274, #364.





## Errors Encountered

| Error | Resolution |
|-------|------------|

## The run (2026-10-23, run_uid `20261023_074321-24d85e8c`)

| stage | UTC | minutes |
|---|---|---|
| snapshot, spin, prep, host parity | 07:43–08:02 | 19 |
| modelling, cloud (job1 / job2 / job3) | 08:02–12:12 / 12:27 / 12:22 | 249 / 264 / 259 wall; 247 / 260 / 257 modelling |
| modelling, m1 (73 of 74) | 08:02–17:23 | 560 wall; 306 modelling; OKAN stall 09:19–13:30 |
| consolidate (167 groups) | 17:24–18:06 | 42 |
| burn, coverage | 18:06 | <1 |
| recompute, 240 groups, `-j8` | 18:06–19:57 | 110 (longest LFRA 22.7, FRCN 17.9, SETN 16.5) |
| compare | 19:57–20:02 | 5 |
| OKAN re-model, then `--recompute-only --wsgs=OKAN` | 20:15–20:22, 20:23–20:25 | 7.6, 3 |

Phase 1's packing estimated about 218 min per host; the cloud hosts ran 13–19 % over it and m1, net of KTSU's
excess and the stall, about 10 % over. Cloud idle after each leg: 5.1 / 4.8 / 5.0 h (→ #369). Provenance: 241
`log` rows and 241 `log_recompute` rows at link `1d00c04c`, `link_dirty` f, fresh `e9793047`, one config_hash;
OKAN also keeps its failed row (date_end NULL, "run failed or interrupted").

### The KTSU / OKAN stall

- KTSU 08:07–09:13 UTC (65.4 min; 1.3 on 2026-10-17). OKAN 09:19 UTC → cancelled 13:30 inside
  `CREATE TEMP TABLE pg_temp.frs_near_river_walk AS …` (fresh 0.42.0 `.frs_near_river_walk_sql()`, cw 15 m /
  1000 m), three parallel workers attached at the cancel.
- Re-run after the run on the working tables the run left (`walk_<wsg>_explain_analyze.out`, scratch): HOLB 2.7 s
  (229,774 origin × main-stem pairs), KTSU 3.0 s (220,649), OKAN 58.9 s (3,228,956 pairs; 6,597 origins kept).
  The plan shape equals the EXPLAIN taken during the run: the planner estimates 44 rows; a nested loop over
  main-stem rows with a BitmapAnd of the geom GiST and the wscode GiST / blk indexes (`FWA_Downstream` is
  `LANGUAGE sql IMMUTABLE`, so it inlines and the ltree index is used); the per-row EXISTS on `blk_drm`; the
  polygon subplan 2,181 loops. The indexes exist at walk time (`.frs_index_working()` runs before
  `frs_near_river()` in `frs_habitat_classify()`).
- Pair counts do not order the cost: LFRA (about 105 M bbox pairs) ran 6.6 min; KTSU (7 M) 65 min.
- Context: both ran in the first 5.5 h after `--refresh-primitives` reloaded the primitives (07:43–08:02), while
  another session's jobs read `fresh_default_20261017`; the 54 m1 groups after 13:30 ran at the 2026-10-17 pace
  with that session still running. PG log 09:00–13:40: autovacuum "skipping vacuum of streams — lock not available"
  at 10:26 and 10:52, nothing else. Mechanism not identified; not reproducible in isolation. No fresh issue filed.
- OKAN's re-model under the same code took 7.6 min (2.8 on 2026-10-17), with the walk inside it.

### The verifier and a failed-then-finished group

`.lnk_log_run_fail()` leaves `date_end` NULL on purpose (three states: finished; failed with notes; killed with
nothing). `study_area_verify.sql` raised on any open row of the run_uid, so a run that took the #348 path (fail,
re-model by hand under the run_uid, `--recompute-only`) could never pass. 2026-10-17 did not meet it because KITR
and UPET failed before their log rows opened. Patched 2026-10-23: open rows a later finished row supersedes are
a NOTICE; the rest still raise; negative cases 6f and 6g prove both.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `bash 3.2.57 is too old` from `launch.sh` under nohup | `exec "$BASH" …` re-execs the driver under the launching bash (`1d00c04c`) |
| OKAN: one statement ran > 4 h; the driver bounds no statement | role `statement_timeout = '30min'` + `pg_cancel_backend` (operator-approved), reset after the run; driver-side bound drafted as a follow-up |
| `pgrep -f 'wsg_run_one.R OKAN'` found no process | Rscript's argv is `--file=… --args OKAN`; match `wsg_run_one[.]R --args OKAN` |
| `study_area_verify.sql`: "1 modelling row(s) started and never finished" with every group finished | the failed attempt's open row; verifier now distinguishes superseded from unfinished |

## The split test (Phase 3): nothing the order of modelling can reach differs

Harness `data-raw/logs/provincial_361/split_test.sh` + `split_compare.R`, run 20:33–21:32 UTC 2026-10-23 from a
worktree at `1d00c04c` (`split_stamp.txt`). Peace's 26 groups, DS-first order from `study_area_wsgs.R`, odd
positions reversed onto `fresh_361a`, even reversed onto `fresh_361b`; the guard warned at open on 18 of 26
(`split_guard_warnings.tsv`: PCEA's and UPCE's dams unmodelled downstream); B consolidated into A; barrier views
built once; all 26 recomputed with the guard in error mode (0 failures) and the habitat gate. Reference:
`fresh_default`'s Peace groups, built on one cloud host DS-first and recomputed over all 241 groups.

Digests (`split_test.csv`, `split_test_summary.txt`): 442 (26 groups × 17 tables), 387 identical, 55 differing;
the control (`fresh_default_20261017`, another link version) differs, as it must. Every one of the 55 is explained
(`split_verdict.md`):

| class | where | size |
|---|---|---|
| cross-host arithmetic | `streams.length_metre` on 104,047 of 1,476,338 segments; 1,265 geometries; `barriers.downstream_route_measure` + `geom` on 62 of 1,000,112 rows (ids identical) | ≤ 2.0e-10 m length, ≤ 2.3e-10 m Hausdorff, ≤ 3.7e-9 m position |
| the test's scope | NATR `streams_access`, 4 `streams_habitat_<sp>`, `streams_mapping_code`: 2 segments (0.1 km) of a Fraser-coded (100.*) line inside NATR, whose downstream barriers (TAKL falls and gradient) are outside the 26-group scratch schema; in `fresh_default` the recompute saw TAKL | 2 of 47,302 segments |
| the order | nothing | — |

The reference Peace was built on `cypher-job1` (amd64); the split on m1 (arm64). MILL and LPCE rebuilt on m1
alone into `fresh_361c` (`hostcheck_build_*.log`) are identical to the split build in `streams`, `barriers`,
`barrier_overrides`, `streams_near_river` and every `streams_habitat_<sp>` except the rows the recompute's
habitat gate blanked in `fresh_361a` (5 / 69 / 100 / 69 rows, every one with `access_<sp> = 0` there).

So the component rule protects nothing the recompute does not settle, and Phase 4a follows. Two facts fall out:
a build is byte-identical on one host and differs at 1e-10 m across architectures, so "identical" across hosts
is a digest after rounding, not of bytes; and a scratch-schema recompute of a subset of groups can differ from
the full one wherever a group holds lines coded to another basin (NATR: 2 segments on a 100.* line).

## Phase 4a: group atoms, and what they buy

`study_area_buckets.R --atom=group` on the 246 focal groups at this run's minutes (`--minutes-schema=fresh_default`,
newest finished row per group, so KTSU's 65 min is in; 1,077 host-minutes; largest component 231): four hosts
270 min under either atom; five hosts 216 under group atoms against 231 under components
(`data-raw/logs/provincial_361/buckets_group{4,5}.md`). The gain is bounded by the largest component only once
hosts outnumber the big components, as the plan said; at four hosts the even split (269) already exceeds the
Fraser. `study_area_wsgs.R --exact` keeps input order and still drops species-less groups (BASH); the driver's
`--buckets-exact` prints `buckets: exact` in the banner, records `bucket_mode` in `run_wsgs.tsv` (reader accepts
both headers; 296 tests pass), refuses an overlap, and is refused by `--recompute-only`.

| Error | Resolution |
|-------|------------|
| Parity run `20261023_203809`: 16 of 17 log rows `link_dirty` t | I edited the main repo (research, driver scripts) while the run modelled from it; the split test ran from a worktree and I treated the parity run as isolated too. Schema dropped; re-run from the worktree at `1d00c04c` (`run_dirty_tree.log` kept) |
| `DROP SCHEMA fresh_parity361 CASCADE` dropped `working_<wsg>.barriers_*_unified` views | the parity run's working schemas reuse `working_<wsg>` names and their barrier views point at the persist schema; views only, the working tables stay |
