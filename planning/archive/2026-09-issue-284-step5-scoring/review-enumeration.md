# Code-check termination: enumeration after round 5 (2026-09-29)

Rounds 3, 4 and 5 each found a defect inside the previous round's fix. The shared mechanism, named in round 3, is a partial producer read by a whole-population reader. So the loop ends on this enumeration, not on a quiet round.

The table takes every artifact the build writes against every reader, as listed in `review-round5.md`. Each FAIL from round 5 is re-checked against the fixed code with a probe.

| artifact → reader | round 5 | now | evidence |
|---|---|---|---|
| base schema → build resume | FAIL: reused the pre-flight's dirty rows, and the digest came from another `--out` | HOLDS | Resume requires a clean log row at this HEAD, and for focal WSGs the working schema plus a digest row in this `--out`. Probe: the three dirty pre-flight rows give `ok = f`, and a missing row gives FALSE, so the WSG re-runs. |
| base schema → digest licence | FAIL: an empty lookup was reported as a re-classify defect | HOLDS | `length(want) != 1` now stops with "run --step=base with this --out first". |
| base schema → stamp run_uid | FAIL: NULL | accepted | The launch exports `LNK_RUN_UID`. |
| variant schema → score (threshold per WSG) | FAIL: built.csv was per variant | HOLDS | built.csv is keyed on variant × WSG. The score requires every scored WSG, one sha, and the right schema. Probe: after a BULL-only build, a 12-WSG score stops with "default was not built for: ELKR, …". |
| bundles → score | FAIL per WSG | HOLDS | Bundles are written in `run_variant()`. The per-WSG sha is checked against the bundle, and the bundle against the current default (one cell). |
| built.csv → score | FAIL | HOLDS | As above. |
| stamps and score outputs → reader | FAIL: the build the score verified was not recorded | HOLDS | `stamp_score.txt` carries a `built <variant>:` line per variant (sha, link, dirty, WSG count, time range). |
| habitat_validate.R stamp → reader | low: dirty taken at the end | HOLDS | Dirty and HEAD are now both taken at launch. |
| working schemas, closure.txt, base_recompute.csv | HOLDS / no reader | HOLDS | The 23-WSG post-condition is read from the DB (Phase 4), not from closure.txt. |
| ladder shape → both scripts | round 4 FAIL, fixed | HOLDS | Probe: a trimmed ladder stops with "step_from names no listed variant", where it used to hang. |

Seven review agents were spent on this task: 1 plan review and 5 code-check rounds, plus this enumeration done in-session. That is past the ~5 bound. The extra rounds found a variants step that could never pass, a walk that named the wrong value, and a resume that would have stopped the full run after 75 minutes.
