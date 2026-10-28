# Plan review — #261 (Plan agent, spawned 2026-10-27 20:21 UTC)

Findings as returned, condensed; dispositions in findings.md, "Plan review, folded in".

- **B1** re-run must not run `wsg_recompute_one.R` with its defaults (config `bcfishpass`, schema from YAML, views rebuilt without `LNK_VIEWS_PREBUILT=1`).
- **B2** EXPLAIN ANALYZE excludes the client half of a walk (array transfer, `sf::st_read`, `.frs_parse_pg_array`), so "harness times agree with the re-run's walk step" cannot hold as written. Time the real `frs_network_features()` from R too.
- **G1** instrument the re-run without editing a copy (auto_explain via PGOPTIONS, a `pg_stat_activity` sampler).
- **G2** measure "other" step by step, not as a remainder: prior table, scoped streams copy, R assembly, the UPDATE, the guard.
- **G3** rows out are not work done: the probe follows candidates (same blue line or ancestor stream); record loops and rows removed by filter; the `_access` views' `NOT EXISTS` on `barrier_overrides` cannot use a measure index.
- **G4** the digest must cover `streams_habitat_<sp>`; `data-raw/recompute_checksum.sql` exists.
- **G5** nothing undoes a one-way gate after the fact: back up first (precedent `recompute_width_bench.sh`, `recompute_parity.sh`).
- **G6** tuple counters are lazy and miss DDL; set `default_transaction_read_only` after the TEMP build; never use counters for the re-run.
- **G7** a re-run settles 0 gate segments where the run settled 488 (CHWK), so it understates the gate.
- **G8** pool lock waits cannot be recovered after the fact.
- **A1** 10-17 and 10-23 are not replicates: 10-17 ran at `a17e9177` with no habitat gate, on a build since renamed `fresh_default_20261017`. Make 10-23 primary.
- **A2** longest-first ordering co-schedules heavy jobs, so heavy jobs are more contended; Spearman tolerates it, a log-log slope does not.
- **A3** a TEMP table cannot scan in parallel and uses local buffers; confirm the plan matches production before extending past CHWK and SALR; run cold then warm.
- **A4** count with the walk's own predicate (`include_equivalents = TRUE`, tolerance 1, per walked view), not the guard's.
- **A5** pre-register: SALR's path below its outlet contains CHWK's lower-Fraser path, so the bare outlet count predicts SALR >= CHWK.
- **A6** idempotence holds in the data (no serial or timestamp columns; recompute-path code unchanged from `1d00c04c` to HEAD apart from a print line and a comment).
- **A7** one outlet per group is an assumption: coastal groups and groups the Fraser runs through.
- **S1** an exact pair count over 241 groups costs about a provincial walk; decompose it as segments x below-outlet plus inside-group pairs.
- **S2** a follow-up carries only measured attribution, not optimisation scoping.
- **O1** re-run before extending the harness; never run harness and re-run together.
- **O2** run the cheap outlet predictor first.
- **AC3** the fresh issue cannot be raised in-branch without approval: PR says "Relates to #261".
