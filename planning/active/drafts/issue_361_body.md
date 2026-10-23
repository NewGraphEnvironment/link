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

- [x] Build at link v0.68.0 or later. Done: run `20261023_074321-24d85e8c` at link `1d00c04c` (0.68.0), fresh `e9793047` (0.42.0). `data-raw/cypher_prep.sh` installs link and fresh from the DESCRIPTION pin on each spin; do not use `scripts/update_hosts.sh`, which installs fresh from main (#269).
- [x] Re-prep every cypher for the fresh v0.42.0 pin (done by `cypher_prep.sh` on spin; the host-parity gate passed on all four hosts before any write) (`data-raw/cypher_prep.sh`). `lnk_preflight_fresh()` hard-fails on a host whose fresh lacks `frs_habitat_predicates(near_river_table)` or `.frs_near_river_specs`; confirm it passes on each host before dispatch.
- [x] Decided at the plan gate (operator, 2026-10-22/23): `fresh_default` renamed `fresh_default_20261017` and kept; `--refresh-primitives` (cypher_prep loads current primitives, so keeping the old load would have split the hosts' inputs). Was: keep today's `fresh_default` under a new name (`fresh_default_20261017`) for the parity re-score's segment diff, or build over it; refresh the primitives (`--refresh-primitives`) or keep the 2026-10-17 load.
- [x] (A full run; KETL, LARL and SKGT persisted at 0.68.0 in the run.) Under `default`, a group upstream of a US dam placeholder (the BC Columbia above the border, the Kettle, the Skagit) fails the downstream guard until KETL, LARL and SKGT are persisted at 0.68.0. A full run orders them correctly; a partial re-model of today's schema fails `wsg_recompute_one.R`'s error-mode check for those groups.
- [x] Re-model every group into `fresh_default` at link >= 0.68.0. Done (241 groups; both verifiers pass at 241; `habitat_validate.R` accepts the schema under `default` again). Until then `lnk_habitat_validate()` refuses the schema under `default`: it has no `streams_near_river` table and no `log.near_river` column.
- [x] The split test ran against this run's own Peace build (Phase 3; `data-raw/logs/provincial_361/split_verdict.md`). The split test in the Proposal can run on this same run, so it costs no extra build.
- [ ] After it, re-score bcfishpass parity (`research/bcfishpass_parity.md`). The #367 pick moves picks toward bcfishpass's (656 of 17,377 PSCIS change modelled crossing against 0.67.0), so parity can move too. CO moves with its 1050/1150 gradient test (ADMS 352.55 -> 352.33 km, BULK 2,215.57 -> 2,214.12; `data-raw/logs/wetland_door_364/`).

## Not in scope

The recompute itself. Measured 2026-10-20: 8 workers are 1.43x 4 on 53 groups (about 154 to 108 min at 241), and the database VM (6 CPUs) looks like the limit past 4 (`data-raw/logs/recompute_width_20261020/`).

Relates to #246, #274, #364.




## Result (2026-10-23)

**A component can be split across hosts.** The Peace's 26 groups modelled on two hosts in the worst order (each host's list upstream-first, half of every group's downstream groups on the other host), consolidated and recomputed, digest identical to the run's own one-host build in everything the modelling order can reach: of 442 per-group per-table digests, 387 are identical and the 55 that differ are cross-host arithmetic (the reference Peace was built on an amd64 cloud host, the split on arm64 m1: `length_metre`, geometry and 62 snapped barrier positions differ by at most 3.7e-9 m; ids and row sets the same) or the test's 26-group scope (two NATR segments on a Fraser-coded line whose downstream barriers are TAKL's, outside the scratch schema). MILL and LPCE rebuilt on m1 alone are byte-identical to the split build in every model-time table. Evidence: `data-raw/logs/provincial_361/split_verdict.md`; record: `research/study_area_run.md`.

So `study_area_buckets.R --atom=group` packs single modelable groups (each host's list in the global downstream-first order; the report prints the makespan under both atoms), `study_area_wsgs.R --exact` resolves a list as given, and `study_area_run.sh --buckets-exact` takes those lists, makes an overlap fatal and records `bucket_mode` in `run_wsgs.tsv`. On this run's minutes four hosts tie at 270 min under either atom and five hosts give 216 against 231, so group atoms pay from five hosts on (a `job4` workspace is the infra-repo work it would need).

The run itself: run_uid `20261023_074321-24d85e8c`, 241 groups, link `1d00c04c` / fresh `e9793047`, both verifiers pass at `expected_n=241`. One m1 group (OKAN) sat over four hours in one statement that re-runs in 59 s on the same table (mechanism not identified; `findings.md` in the PWF archive); it was cancelled under an operator-approved statement timeout, re-modelled under the run_uid and finished with `--recompute-only --wsgs=OKAN`. The cloud hosts idled about 17 host-hours waiting for the dispatcher: #369. Two follow-ups are drafted for review: a per-statement timeout in the driver, and a scoped pre-run gate.
