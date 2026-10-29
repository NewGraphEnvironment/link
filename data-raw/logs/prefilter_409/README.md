# prefilter_409: the recompute under fresh v0.46.0's walk prefilter

Evidence for link#409 (tracked on #377), measured 2026-10-29 00:58 to 06:53 UTC (the recompute runs 01:27 to 03:23, and SETN's second pair 06:10 to 06:53). It
measures fresh#272 (fresh v0.45.0, scoped downstream walks) and fresh#242 (v0.46.0,
group-matched connectivity passes) against fresh v0.44.0. The verdict is in
[`research/recompute_cost.md`](../../../research/recompute_cost.md), "Measured since fresh#272".

## Environment

- **Recompute (Phase 2):** the dispatcher's `fresh_default` (PostgreSQL 17.5, `work_mem` 512 MB),
  still the 2026-10-23 provincial build (run_uid `20261023_074321-24d85e8c`, link `1d00c04c`,
  fresh 0.42.0 `e9793047`). All five groups' newest `log` and `log_recompute` rows are at
  `1d00c04c`. R 4.5.2 ran on m4 from a worktree at `1d00c04c`, so array transfer and parsing on
  m4 are inside the walk times. Serial, one group at a time.
- **Model builds (Phase 3):** m4's local fwapg, from a worktree at `64f8de0a` (main at the start).
- **The two arms differ only in fresh:** v0.44.0 (`RemoteSha 22034c1a`) from the shared
  library, v0.46.0 (`8a5ca763`, equal to `git rev-parse v0.46.0^{commit}`) from a scratch
  library holding fresh alone, put first by `R_LIBS`. RPostgres 1.4.10, DBI 1.3.0, sf 1.1.2 and
  withr 3.0.3 come from the shared library in both (pak had put copies of 25 dependencies into
  the scratch library; they were removed). Each run prints the fresh it loaded and its path
  (`recompute/rerun_<WSG>_<label>.log`, line 1); each model build's own `log` row names it
  (`model/model_provenance.csv`).
- **The recompute code is the new pin's:** `git diff 1d00c04c HEAD -- R/lnk_access.R
  R/lnk_pipeline_access.R R/lnk_habitat_gate.R R/lnk_mapping_code.R R/lnk_wsg_downstream_check.R`
  is empty at this branch, and `1d00c04c`'s floor (`fresh >= 0.42.0`) admits both arms.

## Method

- `rerun.R`: #261's `data-raw/logs/recompute_cost_261/rerun.R`, unchanged except: outputs carry a
  run label and the fresh loaded; other active clients and m4's 1-minute load are stamped; each
  walk's arrays are digested in the order returned and with each array sorted (radix); the
  backup schema is `zz409_backup`. It runs the group's whole recompute (prior copy,
  `lnk_access(merge = TRUE)`, habitat gate, mapping code, downstream guard), digests every table
  it writes before and after, and stops with the restore statement if one moves. Its lock check
  refuses beside any other lock in `fresh_default`.
- `rerun_all.sh`: each of SALR, LKEL, LSKE, CHWK and SETN to run four times, b1 a1 a2 b2 (b = 0.44.0,
  a = 0.46.0), so cache warmth favours neither arm. Before each run it waits for the database to
  be quiet (no other active client and no other lock in `fresh_default`), since a refused run
  stops it; it records the input tables' write counters (`recompute/input_counters.tsv`).
- `summary.R`: each arm's fastest run per group and step (`recompute/summary_steps.csv`), and per
  walk (`recompute/summary_walks.csv`).
- `model_run.sh` and `compare.R` (Phase 3): ADMS (its SK reaches fresh#242's
  connected-waterbody pass), NATR (its KO does) and ELKR built with `wsg_run_one.R` into `fresh_409b` (0.44.0)
  and `fresh_409a` (0.46.0), then `streams`, `barriers`, `streams_access`,
  `streams_mapping_code` and every `streams_habitat_<sp>` digested per group (every column,
  geometry as EWKB; #367's `compare.R`). `barrier_overrides` (link's) and `streams_near_river`
  (from `frs_near_river.R`, unchanged between the pins; `frs_habitat_classify.R`'s only code
  change is a progress count) were not. The schemas were dropped afterwards.
- `ties_anthropogenic.sql`, `ties_remediations.sh`: whether fresh 0.45's new tiebreak (each
  array's `ORDER BY` now ends on the feature id) can move the two values link reads from an
  array's first element, `dam_dnstr_ind` and `remediated_dnstr_ind`. Read-only, on the
  dispatcher, before any write.
- `reach.md`, `pick_only.md`: the pre-run gate at the new pin (below).

**Two refusals and one hand stop, none an output change.** LSKE a2 first refused on autovacuum's lock on
`streams_access` (set off by the runs' own rewrites); the driver then also waited out locks, and
resumed there (`RESUME=`). SETN a2 refused once, after 72 minutes of waiting, when another session's walks (on #394, in
`zz394_*` tables of `fresh_default`) took locks seconds after the driver saw quiet; the driver
then required five minutes of continuous quiet (`QUIET_S`). With the dispatcher expected
busy for hours more, the waiting driver was stopped by hand (no run in flight) and relaunched
with its own v0.44.0 library (`LIB044`, built the same way), so the shared library could move to
v0.46.0. `recompute/status.txt` has every attempt. LSKE a2's refusal log was overwritten by its
  resumed run (the lock holder was read live from `pg_locks`: `autovacuum: VACUUM
  fresh_default.streams_access`); SETN a2's is kept as `rerun_SETN_a2_refused1.log`. The committed
  `rerun_all.sh` now keeps an earlier attempt's log and exits 2 on a `RESUME` that matches no
  run; the copy that ran SETN's second pair (06:10 to 06:53 UTC, no other client during either run) was frozen before both changes.

## Measurement

### Outputs

- **Recompute:** every one of the 20 runs left every table it writes digest-identical (4 to 10
  tables per group), under both versions. Each walk returns the same features per segment in
  every run of both versions (48 of 48 walks). Summed over the four complete groups the
  recompute went from 23.6 to 5.4 min (77 % less); over all five, 47.4 to 18.8 (60 %). The `fresh_default.streams` and `.barriers`
  write counters did not move.
- **Element order** differs between versions in 9 walks (CHWK's eight per-species natural walks,
  SALR's CH), and is the same within each version. link keeps only membership from those arrays
  (`has_barriers_<sp>_dnstr`). Natural views can hold co-located features, since a barrier on a
  line several groups share is persisted once per group: m4's 30-group `barriers_ch_access`
  holds 189 such positions, 188 across groups (`ties_natural.*`). That copy holds neither CHWK
  nor SALR, and the dispatcher's copy, on which the walks ran, was not counted.
- **The tiebreak cannot move `dam_dnstr_ind` on the 2026-10-23 build:** no two features share a
  position among the dispatcher's 502,233 anthropogenic rows (241 groups).
  `remediated_dnstr_ind` is computed at model time only (`lnk_access()` passes no crossings table,
  so the recompute keeps it); the 356,568 rows of the remediation sets in the 134 working schemas
  the dispatcher had kept with rows (of 138) hold no shared position either. Those schemas come
  from builds of unrecorded date: the dispatcher modelled 74 groups in the 2026-10-23 run.
- **Model builds:** 25 of 25 non-empty group-tables identical (20 empty on both sides), barriers
  included (`model/model_digests.csv`).

### Time (each arm's fastest run)

| group | total, 0.44.0 (s) | total, 0.46.0 (s) | | walks, 0.44.0 (s) | walks, 0.46.0 (s) | |
|---|---|---|---|---|---|---|
| SALR | 42 | 23 | 1.8× | 28 | 10 | 2.9× |
| LKEL | 111 | 46 | 2.4× | 88 | 25 | 3.6× |
| LSKE | 580 | 178 | 3.3× | 518 | 117 | 4.4× |
| CHWK | 686 | 75 | 9.2× | 658 | 45 | 14.7× |
| SETN | 1,424 | 804 | 1.8× | 1,274 | 666 | 1.9× |
| all five | 2,843 | 1,126 | 2.5× | 2,566 | 863 | 3.0× |


- Walks are the whole gain. Gate, mapping code and setup vary as much between runs of one
  version as between versions (LKEL's mapping code 4.4 to 7.3 s under 0.46.0 alone); SETN's mapping code is 47 to 62 s under 0.46.0 and 76 to 80 under 0.44.0.
- **The natural walks, summed per group, gain 4.7× to 17×** (SETN 2.2×; per walk 1.6× to 18.5×,
  `recompute/summary_walks.csv`). **Every PSCIS and dam walk got slower, and the anthropogenic walk
  in four groups of five** (CHWK's went 4.4 → 1.8 s): the PSCIS and dam walks by 1.0 to 1.3 s in
  SALR, LKEL and CHWK, 2.0 to 2.4 in LSKE and 3.5 to 3.9 in SETN. A group makes 5 to 11 walk calls
  (SALR 5, the others 10 or 11). What costs it is not measured here: fresh's own timing of its
  temp-table build is 0.07 to 0.15 s in SALR, LKEL and CHWK and 0.7 s in LSKE, on a
  province-wide `fresh_default` with no other client active (fresh
  `data-raw/logs/network_features_272/`), less than the rise. Walking each barrier set once
  (#394, lever 2) makes fewer calls.
- **Walks are no longer nearly all of a recompute:** under 0.46.0 they are 41 % (SALR) to 83 %
  (SETN) of these runs, against 66 to 96 % under 0.44.0.
- **Against #261's estimate:** its prefiltered walks ran 6.3× (SALR) to 24.6× (CHWK) faster on the
  server; as the recompute runs them, from R, the natural walks summed per group gain 4.7×
  to 17×. SETN is output-bound, as #261 found (1.2× there).

## Not measured

- The pool at `-j8` on the dispatcher, where the database contends (#374); the provincial share
  comes from the next run's `log_recompute` (owed on #377).
- Model-time minutes: Phase 3's scratch schemas hold three groups' barriers, so its walks are not
  the province-wide case.

## The pre-run gate at the new pin

`reach.md`: fresh's files reached from link's modelling path are the same 18 at v0.44.0 and
v0.46.0, so the 28 `none` rows in `data-raw/pretest_inputs.csv` hold. `pick_only.md`:
`pretest_run.sh --pick-only --since=1d00c04c` exits 0 over fresh v0.42.0..v0.46.0 (31 changed
files, every one mapped). The pin voids the gate's record; the full gate is owed before the next
provincial run.
