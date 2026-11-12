# Plan review — #465 (Plan agent, spawned 2026-11-12T06:12Z, delivered ~06:22Z)

Findings as delivered, condensed; verdicts in the last column of each item.

## Blockers
1. **Fingerprint guard compares the export host's database with builds from other hosts.** `.lnk_log_inputs()` copies identity from the build host's ledger only (`R/lnk_log.R:863-867`); CABD and PSCIS are `api` kind with no version handle, `row_count` is a `reltuples` estimate, `loaded_at` is per host. — **Verified** 2026-11-12 on m1's `fresh_default`: latest builds on 5 hosts (m1 55, m4 52, cypher-job1..3 45/45/44); `cabd.dams` and PSCIS have 0 version ids across 241 builds and 5 distinct loads; observations and modelled crossings carry 1 version id and 1 ETag across all 241. Gate decision 2 goes back to the operator.
2. **CABD and PSCIS group slices cannot be selected outside a run.** Raw `cabd.dams` has no group (snap + bundle edits decide it, `R/lnk_pipeline_prepare.R:948-1031`); PSCIS picks province-wide, and its 100 m join to modelled crossings has no group filter (`R/lnk_pipeline_pscis_build.R:104-110, 200-207`). Suggests province-wide snapshots keyed by content. — **Verified by reading**; part of the same operator question (CABD 2,593 rows / 1.9 MB, PSCIS 19,905 / 18 MB, observations 375,962 / 227 MB).

## Gaps
1. Groups the export includes are not all the walk read (failed latest builds pre-persisted barriers; paused-only groups have no segment parts). Iterate `r_cf` groups for barrier parts (done); the lister classifies each dependency as exported / skipped (refuse) / not held. — **Adopted** (Phase 5).
2. Manifest code to change: `_previous`, `_write`, `_regressions`, PUBLISH `verify_tree`, puts, stale deletion, read-back. Dependency map must not go in `files` (write-once refuses a changed md5). Old manifests lack the arrays (treat as empty); an older link building into the root drops them (document a minimum link version, keep `manifest_version` 1). — **Adopted** (Phases 2, 3, 6).
3. A written-once snapshot can contradict a later guard result: reference the existing key and skip the guard. — **Adopted** if snapshots stay.
4. Loaded rows look like built rows: add `<schema>.log_downstream_load`; report `config_hash` and link version against the local bundle; reuse `.lnk_part_fetch()`; one transaction; schema from `cfg$pipeline$schema`. — **Adopted** (Phase 5).
5. Export fixture has no barrier tables. — **Adopted**: the export refuses a schema without them (every persist schema has them); fixture extended.
6. Encoding: arrays as Postgres text (done), ltree as text (done); geometry as hex EWKB to keep the SRID. — **Kept as hex WKB**: the SRID is in the persist type and the loader sets it from there; recorded in the manifest's dataset spec.
7. `observations_province` (every group's records, upstream ones too) reaches the walk outside the barrier parts; newer local records can lift a dependency's barrier the provincial run did not. — **Adopted as a report and a documented limit**: observations are a machine primitive (versioned object), not a persisted output.
8. Parity needs the dependency groups' FWA (gradient search covers whole lines; snaps cross boundaries). — **Adopted**: the lister names the FWA objects; RUNBOOK states the limit.

## Acceptance
1. Same-database end to end cannot fail for one-group-machine reasons. — Operator question (partial-database arm or round trip only).
2. Compare against `fresh_default` can fail for wrong reasons (merged recompute codes, cypher loads, code drift). Add a control arm (dependency rows copied by SQL) and require the export-loaded arm equal to it exactly; pick a target built on m1 (this host). — **Adopted.**
3. Negative arm needs `LNK_GUARD_DOWNSTREAM=ignore`; positive arm passes the guard in `error`; add a barriers-without-overrides arm; prefer a target whose line set is larger than its closure. — **Adopted.**
4. One SQL check that the line rule is a superset: rows whose `blue_line_key` FWA does not touch under the row's own group. Expect 0. — **Adopted** (Phase 3).
5. The scratch run overwrites `working_<wsg>`; drop `fresh_465` and it afterwards. — **Adopted.**

## Ordering / scope
- Phase 5 and the end to end after Phases 2-3; Phase 4 last. — **Adopted.**
- Prove `recompute_deps.R` identical for `all` too (owner rule's refusal path). — **Adopted.**
- Printed commands include seeding the root from the bucket; PUBLISH skips keys whose ETag already equals the md5. — **Adopted** (Phase 6).
- Dependency-map fingerprint: record the export database's FWA table identity, not a per-build `log_input` row. — **Adopted.**
