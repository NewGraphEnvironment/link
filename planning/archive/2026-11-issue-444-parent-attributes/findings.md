# Findings — Parent attributes on the full network: each segment reads its minimal parent's gradient (#444)

## Issue context

**If we do it:** a habitat rule tuned on the minimal network (`default_minimal`, `cut-min`) applies unchanged on the full network, because each full segment reads the gradient of the minimal segment it was cut from. **If we never do:** knowledge's tuning on minimal segments (`NewGraphEnvironment/knowledge#120`) has no way to deploy on the network link ships, and the transfer cost cannot be measured.

## What the proof showed

#415's proof built BULK, SETN, MORK and COTR under `default` and `default_minimal` from one commit (`research/minimal_network.md`, evidence `data-raw/logs/minimal_breaks_415/`). Every check passed:

- **Every minimal cut has a full cut within 1 m**, so each full segment lies in one minimal segment, straddling a minimal cut by at most about 1 m. The largest-overlap join is well defined: `parent_<wsg>.csv.gz` is its prototype, one row per full segment.
- **The minimal gradient is the length-weighted gradient of the full pieces it holds** (median difference 0, at least 99.99 % of km within 0.01). So a parent's gradient is a real quantity at the full segment, not an artefact of the join.
- **Accessible km do not move.** Code 2, the user habitat overlay and the crossing-based fields do. On the minimal network the crossing fields read below a segment's start, not below a point, and should not be carried to the parent table.
- **Rearing rises on the minimal network** (BULK chinook 2,101 to 2,205 km, COTR 1,322 to 1,419), because the connectivity pass drops less on longer segments. A threshold tuned there is tuned on the parent's gradient, not on the full network's rearing. That is why the full network needs to read the parent's gradient, and not just its own.
- **Fish records still reach the minimal cuts through observation lifts.** Only bull trout's observation lifts moved positions in the four groups. With every record left out, 0 to 1.2 % of km changed segment, and 0 to 0.9 % of modelled-species records sat on a changed segment, with a median gradient shift of 0.007 to 0.073. So a leave-one-out tuning (`NewGraphEnvironment/knowledge#131`) can still move a cut below a held-out bull trout record.

## The full build now exists (2026-11-03)

#454 rebuilt `fresh_default` on m4 under `default` (run `20261103_163715-269b585a`, 241 groups, 5,546,370 segments, `cut-full-top acc-v5 grad-seg q-fwapg`), beside `fresh_default_minimal` (run `20261102_203300-60ab009d`, 241 groups, 4.99 M segments, `cut-min acc-v5 grad-seg q-fwapg`) in the same database, on the same fresh (`245c8d8d`, 0.52.0) and primitives load. **The two `link_sha`s differ:** the minimal build is at `193cb8aa` (0.78.1), the full one at `4dfbfa49` (0.78.2), and between them only `DESCRIPTION` changed (`git diff 193cb8aa 4dfbfa49 -- R inst DESCRIPTION data-raw/wsg_run_one.R data-raw/wsg_recompute_one.R`). A raw-sha guard would refuse this pair over a version bump, so the guard compares the modelling code instead (operator, 2026-11-03; second box below), and this pair passes it.

## Proposed

The design is the one #415 set at the gate (operator, 2026-11-01):

- [ ] `<full schema>.streams_parent` (`id_segment, watershed_group_code, id_segment_minimal, gradient_minimal, length_minimal`, plus the minimal build's `config_hash` and run), built by a post-hoc join by largest measure overlap per `blue_line_key`, with slivers under 1 cm dropped. Its own table, because `streams` has no `ADD COLUMN` path and the export's column list is a fixed contract.
- [ ] The minimal build it reads is named, and the join refuses it unless it and the full build share one modelling code and one species set (operator, 2026-11-03): no change on the modelling path between their two `link_sha`s, judged as the pre-run gate judges a record (`data-raw/pretest_check.R`: the diff between the shas against `data-raw/pretest_inputs.csv`, where a version bump or docs commit keeps it and an unmapped changed file refuses); the same fresh sha; the same `acc` token; and neither build dirty. Raw `link_sha` equality is not required, because the superset depends on the code the builds ran, not on the commit's other files.
- [ ] Reading the parent's gradient on the full network is a `grad` token of its own, because knowledge archives a setup by link's four tokens and two readings on one build would collide.
- [x] Which other attributes a rule reads come along: none besides gradient, for now. Channel width is per FWA line. **Discharge is per FWA segment:** fwapg's fork gives each FWA segment one PCIC routed value, wet adds its water balance and a `pick` of the default source, and link joins it on `linear_feature_id`. Neither network crosses an FWA segment boundary (in `fresh_default_minimal`, 4,987,761 segments on 4,486,608 FWA segments, extra cuts inside 358,457 of them), so a full segment and its minimal parent read the same value and the table needs no discharge column. Physically flow grows along a segment; whether one value per FWA segment is accurate enough for tuning is a research question for knowledge (operator, 2026-11-03), not this issue's.

## Acceptance

- [ ] `NewGraphEnvironment/knowledge#120`'s mechanics check passes on link's test groups: every visit lands on a segment on both networks, segment ids join, and the parent-gradient setup reads its parent's value.
  Checked on the prototype on 2026-11-02 (knowledge's `research/minimal_network_tuning.md`). All 2,082 visits in the four groups land on both networks at one stream and measure. Every full segment a visit sits on joins `parent_<wsg>.csv.gz`, and its parent is the minimal segment the visit sits on, with that segment's gradient. No visit sits on a full segment that straddles a minimal cut. This line stays open until `streams_parent` replaces the prototype and the check is rerun on it.
- [ ] On the four proof groups, the table's parent for each full segment equals `parent_<wsg>.csv.gz`.

Relates to #415, #441, #414.







## Plan-mode exploration (2026-11-03, on m4)

- Both provincial builds are in m4's local fwapg: `fresh_default` 241 groups at link `4dfbfa49` (run `20261103_163715-269b585a`), `fresh_default_minimal` 241 at `193cb8aa` (run `20261102_203300-60ab009d`); both fresh `245c8d8d`, `acc-v5 grad-seg q-fwapg`, `link_dirty` FALSE, one `config_hash` each. `log.species` equal per group (BULK: `{BT,CH,CM,CO,PK,SK,ST}` on both).
- `git diff 193cb8aa 4dfbfa49` and `git diff 6bf9ca06 193cb8aa` on the modelling paths touch only `DESCRIPTION`, mapped `none` (`pretest_inputs.csv:149`). BULK holds 42,458 full segments in `fresh_default`, as in the #415 proof.
- The proof groups were built on mixed hosts (full: BULK, COTR on cypher-job1; MORK, SETN on m1. minimal: BULK cypher-job1, COTR m1, MORK cypher-job2, SETN m4), so the prototype check compares by position with tolerances, not by bytes.
- `zz415_default` / `zz415_minimal` no longer exist; the prototype is the committed `parent_<wsg>.csv.gz` (header `id_segment,wsg,id_segment_minimal,gradient_minimal,length_minimal,overlap_m,straddle_m`; BULK 42,458 rows).
- knowledge's `knw_parent_join()` (`knowledge/R/parent_join.R`) needs `overlap_m` and `straddle_m` and checks `overlap_m + straddle_m` against the visit's segment length; `0310` reads `PARENT_DIR`; `0320` scores `GRADIENT=parent_gradient` into `grad_parent/`.
- Consolidate's table filter (`schema_consolidate.R:255-258`), `_HOSTS_PERSIST_CORE`, the verifier and the export all name their tables; a table `lnk_persist_init()` created would fail `test-schema_consolidate.R:375-395`.
- `.lnk_vocabulary_specs()` hardcodes `grad = "gradient=segment"`; the matcher keys on axis + spec, so a second live grad row with another spec resolves nothing differently.
- Stale first-party installs: fresh 0.52.0 (pin `v0.52.0`; not upgraded), link 0.78.1 local (work runs by `load_all`).

## Errors Encountered

| Error | Resolution |
|-------|------------|
