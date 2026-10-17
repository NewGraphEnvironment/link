# Code-check round 4 (#246): enumeration

Reviewer: subagent, 2026-10-16. Diffs: `cc_round4.diff` (branch), `cc_round4_fixes.diff` (round-3 fix).
Read in full: `data-raw/parity_crosssection.R`, `data-raw/logs/provincial_246/verify_extra.sql`,
plus the changed hunks of `study_area_run.sh`, `cypher_prep.sh` and `study_area_buckets.R`, and
`R/lnk_pipeline_species.R`, `R/lnk_rollup_wsg.R`, `R/lnk_parity_annotate.R`, `R/lnk_log.R`
(`.lnk_input_primitives`, `.lnk_log_inputs`), `R/lnk_persist_init.R`, `data-raw/study_area_wsgs.R`,
`data-raw/wsg_run_one.R` (schema override), and `data-raw/study_area_verify.sql` (the companion's
assertions).

## Verdict: Clean

No defect found. Every skip, exclusion, aggregate and threshold below either fails loud on the
input that would defeat it, or is a documented design choice.

## Probes run (all read-only)

- `parity_crosssection.R FINA ZZZZ`: `FAIL: fresh has no rows for: ZZZZ`, exit 1 (no_link fires).
- `parity_crosssection.R BULK`: PASS, exit 0. BULK SK is +11.0 / +7.4 % with non-zero link
  values, so the parked case goes through `hab_parked`, not `missing`. BULK CM is excused as absent,
  correctly: CM is not present in BULK.
- Default sweep (FINA PARS PCEA LKEL): 25/25, PASS. The only excusal is LKEL SK (not present).
- Mutation (a copy in `cc4_work/`) drops BT rows from `lk`. On BULK it gives
  `FAIL: bcfishpass models the species ... BULK BT accessible/spawning/rearing`, exit 1. On FINA
  (BT only) it gives `FAIL: no parity rows at all`, exit 1. So the round-3 guard fires.
- `lnk_pipeline_species()` against the newest `fresh.log.species` per group: **39/39 groups agree.**
- The `bcfishpass` and `default` presence CSVs are identical for all 8 species the script compares,
  over the same 246 groups.
- `verify_extra.sql`, adapted copy. The artifact columns are NULLed (local `log_input` predates
  #265) and the thresholds table check is dropped (absent in `fresh`). Run under
  `default_transaction_read_only=on` on run `20260901_234743-6628379d`:
  - it raised (exit 3) with "67 groups in streams whose newest log row is not this run" (correct:
    a 34-group run in a 95-group schema);
  - and with "2 loader tables read at different versions" (correct: all NULL).
  - Row-count checks 5b and 5c passed. That run's snapshot tables agree across 3 hosts, and
    cypher-job2 has one NULL among 6 rows for bcfishobs, which is the case 5c is meant to tolerate.
  - The unmodified file against `fresh` raised on the missing
    `log_parameters_habitat_thresholds` (exit 3): it fails loud.
- `study_area_wsgs.R PARS default` with `LNK_LOAD=loadall`: stdout is exactly one comma line (`od -c`),
  so the `$(...)` bucket capture is clean.
- `bash -n` is clean on `study_area_run.sh` and `cypher_prep.sh`.

## Round-3 fix: does `lnk_pipeline_species(cfg, loaded, w)` give the built set?

- The build picks species the same way. `lnk_pipeline_run()` takes `active_species <-
  lnk_pipeline_species(cfg, loaded, aoi)` and stops when it is empty, and `wsg_run_one.R` skips a
  group whose set is empty.
- The function returns uppercase codes (`BT CH ...`). The script applies `tolower()`, and the
  `species` vector is lowercase, so the `%in%` matches.
- A group absent from presence returns `character(0)`, which would excuse every link-zero. But
  `lnk_pipeline_run` refuses to build such a group, so the link side has no rows for it and
  `no_link` fires first. Presence has all 246 groups.
- The residual risk is drift, not a defect. The set is derived from HEAD's bundle, not from the
  build's recorded `<schema>.log.species`. They diverge only if the presence CSV or `cfg$species`
  changed after the build. Presence is hand-authored (`source: link (hand-authored)`, last changed
  in #106), and the 39/39 agreement above is measured.
- `LNK_CONFIG` different from the build config: harmless today for the 8 compared species, because
  presence is identical across the two bundles. `default`'s KO / RB / GR are not in `species`, so
  they are not compared at all. That is fine: the bcfp view carries no reference for them.

## Enumeration

### data-raw/parity_crosssection.R

| location | what it skips / aggregates | input that would make it pass wrongly | verdict |
|---|---|---|---|
| L51-52 `cfg_name` default | unset `LNK_CONFIG` → bcfishpass | a schema built under another config | handled: presence is identical across bundles for the 8 species, so `modelled` is the same |
| L55-56 `schema` default | empty → `fresh` | — | handled (`nzchar`) |
| L58 `wsgs` default | no args → 4 groups | — | design |
| L94-97 `num()` NA/empty→0 | NULL sum (FILTER matched nothing); `bc[[col]]` NULL | link access NULL from missing `streams_access` rows → 0 | handled: a modelled species at 0 goes to `missing` (fail); a non-modelled one has no `lk_row`. The bcfp side is `coalesce`d, and an aggregate with no GROUP BY always returns one row |
| L107-110 `!nrow(lk)` → `no_link`, `next` | group absent from the link schema | — | handled: counted in `n_fail` (probe: ZZZZ, exit 1) |
| bcfp group absent from `streams_vw_bcfp` | `bc` all zero | link also all < 1 km | handled: link ≥ 1 gives pct = Inf, `ok` FALSE (fail); link and bcfp both < 1 is the threshold below |
| L117 rearing `next` for cm / pk | no freshwater rearing | — | design |
| L120 `max(lkv,bcv) < present_min` `next` | pairs under 1 km on both sides | a real 0.9 km vs 0 departure | design threshold |
| L121-127 `absent` / `missing` split | link < 1 km, bcfp ≥ 1 km | not modelled per HEAD presence while the build modelled it (drift) | handled (mutation fires; 39/39 agree; drift residual noted above) |
| L129 pct with bcv < present_min | bcv = 0 → Inf | — | handled: `abs(Inf) <= tol` is FALSE; NaN is unreachable, because lkv = bcv = 0 was skipped at L120 |
| L130 `tol_acc` 1 % / `tol_hab` 5 % | thresholds | — | design |
| L131 `hab_parked` BULK:SK | habitat rows excused | — | accepted. Accessible is not parked, and a link-zero parked species still goes to `missing` (BULK SK is non-zero today, measured) |
| L138-140 `no_link` print | — | — | report only; the count is in `n_fail` |
| L141-144 `!length(rows)` → `quit(1)` | nothing compared | — | handled (mutation on FINA, exit 1) |
| L149-158 annotate | informational | — | not a gate. A vocabulary miss makes rows read UNEXPLAINED (the loud direction); a missing taxonomy path errors (exit 1) |
| L162-175 summary `max(abs())` | empty metric → -Inf plus a warning | — | cosmetic |
| L187 `if ("FINA" %in% wsgs)` | structural block skipped when FINA is not requested | a sweep without FINA prints no structural line | pre-existing design: the canonical segment is in FINA. When FINA is requested and absent, `seg` is empty, the check fails, and `no_link` also fires |
| L190-207 structural checks | `span == 0`, `seg` all 0, `maxupm` coalesce 0 | an empty blk passes `span` and `maxupm` | handled: `seg` must be non-empty and all 0 (`isTRUE(all(NA==0))` is FALSE) |
| L215-216 `acc_fail` / `hab_fail` | not-ok rows, minus parked habitat | — | handled |
| L219-226 `n_fail` / `quit` | sums acc, hab, struct, no_link, missing | — | handled; every failure list is in the sum (the `absent` exclusion is deliberate) |
| global `missing <- character(0)` | shadows `base::missing` | — | harmless: R skips non-function bindings in a call position, and package functions resolve through the namespace |

### data-raw/logs/provincial_246/verify_extra.sql

| check | aggregate / assertion | input that would make it pass wrongly | verdict |
|---|---|---|---|
| params | `:'schema'` etc. via `set_config` | an unset `-v` | handled: a psql syntax error under ON_ERROR_STOP (exit 3); `''::int` errors |
| 1a `count(DISTINCT wgc) <> en` | counts *attempted* groups | a group that started and failed (log opens before persist) | handled by the companion: `study_area_verify.sql` raises on `date_end IS NULL` and on zero `streams` rows |
| 1b NULL hash or `config_drift IS DISTINCT FROM false` | — | — | handled (NULL counts as a failure) |
| 1c `count(DISTINCT config_hash) <> 1` | all NULL → 0 → fail | — | handled |
| `h := min(config_hash)` | NULL when all NULL | — | handled: check 4 then finds 0 rows and fails, and 1b fails |
| 2 newest row per `streams` group from this run | `max(date_start)` | a tie in `date_start` with another run | negligible; a group with no log rows (max NULL) fails, correctly |
| 3 run_id has any non-NULL `row_count` | `.lnk_log_inputs()` soft-fails with a warning | — | handled: a run_id with no `log_input` fails here |
| 4 thresholds / params / dimensions by hash | `count = 0` | rows from an earlier run with the same hash | design (keyed per hash, write-once); a missing table errors (probe) |
| 5a version agreement | `count(DISTINCT coalesce) <> 1 OR count(v) <> count(*)` | a host with no row for the table | handled by 5c (host × table cross join). Names match `.lnk_input_primitives()` exactly (`bcfishobs.observations`, `fresh.modelled_stream_crossings`), so the IN-list cannot read nothing |
| 5b `count(DISTINCT row_count) > 1`, non-FWA | NULLs skipped | a host all NULL | handled by 5c. pscis / cabd (api) are included, and the 2026-09-01 run agreed across 3 hosts (measured) |
| 5c (host, table) with `count(row_count) = 0` | LEFT JOIN of hosts × tables seen in run | `log.host` NULL | fails loud (no match gives 0); `host` is never NULL in `fresh.log` (65/65) |
| final `array_length(fails,1) > 0` | NULL on an empty array → pass | — | correct |
| `%%` in `format()` | gives a literal `%` for LIKE | — | correct (probe ran) |
| report SELECT | `:"schema"` outside dollar quotes | — | correct (interpolated by psql) |

### Changed hunks: study_area_run.sh, cypher_prep.sh, study_area_buckets.R

| location | guard / resolved value | input that would make it pass wrongly | verdict |
|---|---|---|---|
| run.sh bash ≥ 4 check | `BASH_VERSINFO[0] -lt 4` | zsh / sh | handled: bash 3.2 is caught; zsh has `BASH_VERSINFO` unset, so `set -u` aborts |
| run.sh `*[!A-Za-z0-9_]*` on `CONFIG` / `SCHEMA_OVERRIDE` | an empty value passes the class | `--config=` | handled downstream: the schema guard or the discharge resolution FATALs. `--schema=` is empty-checked at parse. The resolved `SCHEMA` without an override comes from a shipped YAML (trusted) |
| run.sh `study_area_wsgs.R … "$CONFIG"` with loadall | `$(...)` under `set -e` | R noise on stdout | handled: stdout is one line (probe); R failure aborts |
| run.sh `CYPHER_PREP_CONFIG/SCHEMA` in the ssh string | single-quoted | — | handled by the charset guard; `SCHEMA` is never empty (FATAL earlier) |
| run.sh ssh keepalives | ServerAlive 60 × 10 | — | a dropped link exits 255, which the existing bucket check catches |
| cypher_prep `Sys.getenv("CYPHER_PREP_CONFIG","bcfishpass")` | set-but-empty → "" | — | `lnk_config("")` errors (loud). The driver always passes a value |
| cypher_prep `nzchar(CYPHER_PREP_SCHEMA)` | override of `cfg$pipeline$schema` | — | handled; `lnk_persist_init` reads `cfg$pipeline$schema` via `.lnk_table_names()`, the same override `wsg_run_one.R` applies. Species is `cfg$species` (11 for default) and matches the dispatcher's `fresh_default` (11 access columns, measured) |
| cypher_prep R block in `'...'` | no apostrophe in the added lines | — | `bash -n` clean |
| buckets.R `setequal(focal, outlets)` / `n_all` / `flat` / `config` | doc text only | — | all defined earlier (L44, L102, L173) |
| buckets.R `--schema=<persist schema>` | deliberately non-runnable | — | accepted |

## Findings

None.
