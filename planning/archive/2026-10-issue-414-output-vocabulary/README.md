## Outcome

link names every output on four axes: how its streams were cut (`cut`), which access rules decided where gradient barriers cut them (`acc`), how gradient was measured (`grad`) and where flow came from (`flow`). The tokens live in `inst/extdata/vocabulary.csv`. `lnk_vocabulary_resolve()` derives a config's spec per axis and matches it to one live row, `lnk_pipeline_run()` refuses a config with none before its log row opens, and each build writes its tokens to `<schema>.log`. The issue's first test changed the design: `break_order` and `observation_breaks` do not fix where streams are cut, because gradient classes do too and, since #326, so do the access rules, so access became its own axis (operator, at the gate). Code review then found the real difficulty: every normalising step in a spec (a locale sort, `t` read as `TRUE`, NA read as "", upper-cased species, dropped class names, 15-digit doubles, duplicate keys hidden by row sorting) can merge two inputs the pipeline treats differently, and that fails toward pass. Rounds 1 and 2 each found such folds. Round 3 verified a 17-step enumeration of every step from what the pipeline reads to what a spec records (`review-enumeration.md`), and that ended the review. Durable write-up: `research/output_vocabulary.md`; mechanics: RUNBOOK §6b, "Output vocabulary".

## Measurement

- Live check on the local fwapg: `wsg_run_one.R ADMS default` into a scratch schema built in 1.8 min with log row `cut-full-top | acc-v1 | grad-seg | q-fwapg`. `default_extrabreaks` into the same schema exited 1 printing its cut spec, and the log still held one row.
- Full suite at `78cd47b8`: 1,201 tests, 4,711 expectations, 0 failures, 1 skip (the append-only check, which runs once main holds the table). `devtools::check()` at the release commit: 0 errors; the 3 warnings and 3 notes are all on main already.
- Guards proven by mutation: species dropped from the digest, `observation_breaks` always in the cut spec, no `t` normalisation, token order in the INSERT, the resolve moved into the log call, a locale-dependent species sort, a renamed token against the append-only check. Each turned a test red.
- Review: one plan review and three code-check rounds (3, 4 and 2 findings, all fixed or documented).

## Owed

- Before the next provincial run, the pre-run gate (#372) re-runs, because `R/` changed.
- knowledge#119 reads the table through `lnk_vocabulary_read()` / `vocabulary.csv` at a tag (its own issue).
- #415 adds `cut-access` (or whatever name it settles on) when its minimal network is built.
- A follow-up issue, drafted and not filed, for threshold variants to record their own tokens (`habitat_variants_build.R` writes no `log` row per variant, and a variant can change its flow).

Closed by: PR (this branch, v0.70.0)
