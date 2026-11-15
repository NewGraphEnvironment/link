# The pre-run gate finds its history with no flags (link#450)

Two `pretest_run.sh --pick-only` runs on m1, 2026-11-12, on branch
`474-backlog-move-6-what-a-run-stamps-and-che` (uncommitted Phase 4 tree; pick only,
nothing modelled or recorded). Each directory holds the pick's `pretest.md`,
`picks.tsv`, `range.txt` and `history.txt`.

| directory | command | held to |
|---|---|---|
| `default_minimal_ancestor/` | `--config=default_minimal --schema=fresh_default_minimal_x` (a schema with no log) | `ancestor`: `default`'s 241 builds in `fresh_default`, found through `extends:` |
| `default_every_input/` | `--config=default --schema=fresh_nohistory_x` (no log; `default` extends nothing) | `every_input`: all seven query inputs, minutes from `data-raw/logs/build_minutes.csv` scaled to m1 |

The every-input pick takes SETN, BULK, QUES, LFRA, TOAD, HARR, UPCE, OKAN, TAKL,
HORS and SAJR: the same 11 groups #454's gate picked on 2026-11-03 from a log
hand-seeded with 242 rows copied from m1 (`data-raw/logs/pretest/20261103_153249_default/picks.tsv`).

The first ancestor pick chose `fresh_smoke369b` (2 groups) over `fresh_default`
(241): the per-schema group count is a bigint, which RPostgres returns as
`integer64`, and ordering on its negation without bit64 attached ordered on the
raw bits. Fixed by casting the count in SQL and coercing in R
(`pretest_ancestor_pick()`); the unit test pins plain-number ordering.
