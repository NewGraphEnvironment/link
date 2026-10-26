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


## Errors Encountered

| Error | Resolution |
|-------|------------|
