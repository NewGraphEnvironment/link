# Parent attributes on the full network (#444)

## Outcome

Each segment of the full network now reads the minimal segment it lies in. `lnk_streams_parent()` joins one group by largest measure overlap per `blue_line_key` into `<full schema>.streams_parent`, refusing unless every minimal cut has a full cut within 1.01 m, the pieces cover both networks and every full segment gets a row, and it replaces a group's rows in one transaction. `data-raw/streams_parent_build.R` judges the pair of builds once, as the pre-run gate judges a record (one modelling code, fresh and token set per schema, `cut-min` against `cut-full-*`, the same species), then builds every group; `--verify` names groups a re-model left stale. A `grad-parent` vocabulary row names the reading; no build writes it. Released as 0.79.0. The five review rounds kept finding the same mechanism, a stand-in for a property defined elsewhere with nothing comparing them (a hand path list beside what `load_all()` reads, a default `--out` beside a committed record, the pair judged beside the build joined, a name compare beside Postgres's case folding and truncation). They ended on an enumeration of the name checks, `git status` calls and name compares, with round 5 re-walking 41 refusals, 13 code reads and 8 writes.

## Measurement

- The province: 241 groups, 3.9 min summed on m4, 5,546,370 rows (equal to `fresh_default.streams`) on 4,987,761 minimal segments and 1,887,603 km. 96 full segments straddle a minimal cut by 1 cm or more, none by more than 1.000 m: the full build's 1 m skip rule. `--verify` found all 241 current.
- Acceptance 2: on BULK, SETN, MORK and COTR the table equals #415's prototype CSVs, with lengths within 5.5e-12 m. The proof's ids still name the same segments.
- The pair `193cb8aa` / `4dfbfa49` passes the guard: only `DESCRIPTION` changed on the modelling paths. Write-up: `research/minimal_network.md`, "Parent attributes".

## Evidence

`data-raw/logs/streams_parent_444/` (its README indexes it).

## Owed

- knowledge#120: switch `0310` from `PARENT_DIR` to `fresh_default.streams_parent` (or an export of it) and rerun the mechanics check on the four groups and the province (acceptance line 1 stays open on #444 until then).
- The next provincial run's pre-run gate runs again (`vocabulary.csv` moved).
- After any `default` or `default_minimal` re-model, rebuild `streams_parent` (`--verify` names the stale groups).
- Noted in review, not changed: the gate's `pretest_changed_link()` runs `git diff --name-only`, which under rename detection lists only a renamed file's new path. Editing `pretest.R` voids every gate record, so it is the gate's own limit to take up there.

Closed by: PR for branch `444-parent-attributes-on-the-full-network` (head `02bf6540` before this archive)
