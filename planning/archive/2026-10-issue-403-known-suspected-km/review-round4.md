# Code-check round 4 — #403 branch (39e9c2c5...2f8fa10b)

## Checklist read

- `index.md`: read in full.
- `code-check.md`: the prose of all 14 H3s under `## Mechanisms` (`|` rows skipped), "A guard's scope, escape hatches, and remedies" in full, including its closing paragraphs on enumerating claims and on compression adding a quantifier. "Rules that stand alone", Security and Spreadsheets not read.
- `code-check-r.md`: "Postgres row order is never fixed unless the query fixes it…", "An `information_schema` lookup by the literal table name misses what Postgres resolves", "A `data-raw/` script must load the source tree, not the installed package", "Rscript reads a script as it runs…". Others not read.
- `code-check-shell.md`: "psql does not interpolate `:'var'` inside a dollar-quoted string…" (from the index line; `parity_pieces.sql` uses `:'wsg'` / `:sp` outside any dollar quote). Others not read.
- `code-check-spatial.md`: "FWA `upstream_route_measure` misses the next segment's start" (from the index line; `parity_pieces.sql` builds m1 from `downstream_route_measure + length_metre`). Others not read.

## Enumeration of claims

Sources: the diff, the files at `2f8fa10b`, the committed CSVs and `stamp.txt` in `data-raw/logs/known_suspected_403/`, local `fwapg` (read-only), the bcfishpass clone at `620dbe43`, `gh api` read-only on smnorris/bcfishpass. m4 was not queried (out of scope for this review), so claims only m4 can settle are marked so.

| # | Place | Claim | Source checked | Verdict |
|---|---|---|---|---|
| 1 | roxygen `lnk_rollup_wsg` | an unbuilt access gives `accessible_km` `NA` (filtered sum over no rows) | default SQL: LEFT join, `FILTER (WHERE access IN (1, 2))` over no rows is NULL | holds |
| 2 | roxygen | observed = `access = 2`, unobserved = `access = 1` | default metric strings L151-154 | holds |
| 3 | roxygen, RUNBOOK, research | both sum over the same rows as `accessible_km` | same `FILTER (WHERE access IN (1, 2))` on all three | holds |
| 4 | roxygen, RUNBOOK, research | all three NA together where access is not built | same filter set; CASE parts NULL only when the set is empty | holds |
| 5 | roxygen | a part is 0 where accessible rows exist but none carry its code | `CASE … ELSE 0` inside a non-empty filter | holds |
| 6 | roxygen, RUNBOOK, research, log README | pair equals `accessible_km` to 0.01 km | three columns rounded to 2 dp, results multiples of 0.01, max error <= 0.01; `rollup.csv` recomputed: max gap 0.010, no NA | holds |
| 7 | roxygen, RUNBOOK | bcfishpass reports the same split as `length_naturallyaccessible_obsrvd_<sp>` / `_model_<sp>` | `db/schema.sql:5283-5288` (`access_bt = 2` / `= 1`) | holds |
| 8 | roxygen `@param metrics` | default emits six names in that order | `formals()` L149-160; test pins names | holds |
| 9 | roxygen example | spawning / rearing by access code through `metrics =` | aliases `spawning`, `rearing`, `connection`, `access` exist in the per-species SELECT | holds |
| 10 | roxygen `lnk_habitat_validate` | summary carries the split | `R/lnk_habitat_validate.R:350-352` calls the rollup with defaults; `.lnk_hv_summary()` `merge(out, cost, …)` at :1384 keeps every column | holds |
| 11 | README example | PARS BT 6882.15 / 842.81 / 6039.34 / 1682.72 / 2624.20 / 40.16; GR 4441.86 / 596.01 / 3845.86 / 983.83 / 1398.15 / 30.09 | `rollup.csv` `zz396_default_post` PARS rows; progress.md records the README code run into `zz403_readme` at `c8f78f17` equal to them (schema since dropped, so not re-checkable) | holds (as recorded) |
| 12 | README example | 6-metric frame wraps into two printed blocks at width 80 | header line 76 chars, adding `spawning_km` exceeds 80 | holds |
| 13 | RUNBOOK §2c hunk | until #403 nothing in link told 2 from 1 | `readers_code2.md` exists; grep of `R/` for `access… = 2` outside the rollup: none | holds |
| 14 | RUNBOOK §2c hunk | `aw_linear_summary()` tells 2 from 1 on bcfishpass's tables | schema.sql:5283+ | holds |
| 15 | RUNBOOK §8 bullet | validator's `summary` carries all three | as #10 | holds |
| 16 | RUNBOOK §8 bullet | "What code 2 means… is §2c" | RUNBOOK L182 §2c "Observation breaks" describes the walk's 1 m rule and the top break | holds |
| 17 | research L7-10 | rule definitions | as #2-#3 | holds |
| 18 | research L16-18 | same-line record counts when above start or within 1 m (§2c) | RUNBOOK §2c text | holds |
| 19 | research table (25 rows) | accessible, observed km | `rollup.csv` post rows, every value compared | holds |
| 20 | research table | observed share | recomputed observed / accessible for all 25, rounded to 0.1 % | holds |
| 21 | research table | change from #396 | post minus pre observed for all 25 (e.g. ELKR BT 835.08 - 832.79 = 2.29) | holds |
| 22 | research L22-23 | pre build = every observation as a break | `zz396_default_pre` built at `43e34096`, before `71ccc2ce` added `top_per_species`; 43e34096..71ccc2ce touches only `lnk_config.R`, `lnk_pipeline_break.R` and the two config.yaml | holds |
| 23 | research L53-54 | 0.3 % (ELKR GR) to 42 % (LKEL CO); "most" has no record | min 0.35 %, max 41.67 %; all < 50 % | holds |
| 24 | research L54 | accessible km did not move with #396 | pre = post accessible on all 25 pairs | holds |
| 25 | research L55 | observed km only rose, by at most 2.29 km | no negative change; max 2.29 | holds |
| 26 | research L60-61, `parity_bcfp.csv` | accessible km agree within 1.3 km | diffs -0.1, 0 x5, -1.3 | holds |
| 27 | research parity table | six rows of link / bcfp observed and differences | `parity_bcfp.csv` | holds |
| 28 | research L72-73 | every disagreeing piece is link 2 / bcfp 1, never the reverse | `parity_pieces.csv`: only `link_only` rows; the SQL sees only both-in-(1,2) pieces, but piece totals equal the gaps (PARS 29.70 = 29.70), so no code-2 km sits outside it | holds |
| 29 | research L73-74 | every piece on a segment starting within 1 m of a record | all rows `at_start = t` | holds |
| 30 | research L76 | each species' piece total equals its gap, to rounding | 14.46/14.46, 5.46/5.46, 27.77/27.77, 4.15/4.14, 1.91/1.91, 29.70/29.70 | holds |
| 31 | research L76-78 | #399's 1 m rule puts the boundary on the record, as bcfishpass does | CLAUDE.md #396 facts (`include_equivalents = FALSE` counts at `m >= start + 1`) | holds |
| 32 | research L80-82 | bcfishpass BULK ST observed = SK observed = 312.53, link 523.55 | `parity_bcfp.csv` | holds |
| 33 | research L82-84 | `access_st` tests `'SK'` at `620dbe43` | `model/01_access/sql/load_streams_access.sql:120-121` | holds |
| 34 | research L84-85 | fixed 2026-10-23 at `3bd2824c`, their issue 938 | `gh api`: commit 2026-10-23T20:48Z "access_st observed code checks for ST, not SK (#939)"; #938 is the issue ("`access_st` observed code tests for SK instead of ST"), #939 the PR "Fixes #938" | holds |
| 35 | research L85 | the view on m4 predates the fix | inferred from ST = SK observed km on the view; not queried | holds (inference stated on evidence) |
| 36 | research L90-92 | #399 "removes the km above each species' top record on a line … the 1.9 to 29.7 km per pair measured above" | §2c's tributary rule, the pieces SQL | **fails**: see finding 1 |
| 37 | research L93-95 | #401: today code 2 reads only the group's own records | CLAUDE.md #396 facts (`R/lnk_pipeline_prepare.R:346` filter) | holds |
| 38 | research L97 | none of the five groups models CT under `default` | `rollup.csv` species: no CT | holds |
| 39 | research L104-105 | `aw_linear_summary()` reports two splits per assessment watershed | schema.sql:5272 return list (plus `length_total` and salmon aggregates of the same two) | holds |
| 40 | research L109-112 | `spawningrearing_obsrvd` = codes 2 and 3; 2 model and classification, 3 classification only | schema.sql:5359 (`>= 2`); `load_habitat_linear.sql:1-6`, CASE arms | holds (round 3 fix verified) |
| 41 | research L113-114 | combined, except CM and PK spawning only | schema.sql:5375, 5391 (`spawning_cm >= 2`, `spawning_pk >= 2`); SK, ST, WCT, CH, CO, BT use `greatest()` | holds |
| 42 | research L117-118 | `_access_a` no dam or PSCIS barrier downstream, `_access_b` no anthropogenic | schema.sql:5284-5285 | holds |
| 43 | research L122-123 | export carries habitat flags, not access codes | `R/lnk_scenario_export.R:190-215`: flags + `has_barriers_<sp>_dnstr`, no `access_<sp>` | holds |
| 44 | research L126-127 | link matches the classification at gate time, persists no flag | `R/lnk_habitat_gate.R:17-22, 91` | holds |
| 45 | research L128-129 | bcfishpass has no habitat split by access code | grep of bcfishpass SQL: only `aw_linear_summary`'s access split and a mapping label at schema.sql:11440 | holds |
| 46 | log README L182-184 | ran at `735349e0`, the commit adding the metrics; stamp holds SHA and 15:05 UTC | `git log`; `stamp.txt` | holds |
| 47 | log README build table | schemas, configs, SHAs, versions, hash prefixes, built times | `stamp.txt` (pre 06:56-08:58, post 07:01-08:54, fresh 08:29 / 08:32) | holds |
| 48 | log README L187 | all closed, `link_dirty` FALSE, fresh 0.43.0 | `stamp.txt` | holds |
| 49 | log README L196-197 | the `bcfishpass` builds record `v0.7.14-113-ga7373af` (ledger) | `data-raw/logs/bcfp_baselines.csv`: m4's newest rows record a7373af; the log rows themselves are on m4, not queried | consistent; not verified on m4 |
| 50 | log README files table | `rollup.csv` 50 rows, six metrics, `share_observed`; `parity_bcfp.csv` BULK six species, PARS BT; `parity_pieces.csv` seven pairs less ST | the files (51 lines incl. header, 10 columns; 7 rows; 6 rows) | holds (round 3 fix verified) |
| 51 | log README L204 | `rollup.R` selects species with an access column, a habitat table, not -9 everywhere | `rollup.R:329-347` | holds |
| 52 | log README L220-221 | identity on all 50 rows, max gap 0.010, no empty accessible set | `rollup.csv` recomputed | holds |
| 53 | `rollup.R` comments | worktree + load_all; writes three files beside the script; view sums every segment, rollup inner-joins habitat with a row per segment | code; local `fresh` BULK/PARS: streams 87,639 / 97,534 = habitat BT rows; BULK CO equal | holds (locally) |
| 54 | `parity_pieces.sql` header | measure overlaps per blue_line_key, pieces < 1 cm dropped, `at_start` within 1 m (bcfishobs, any group) | SQL L262-292 | holds |
| 55 | test comments | split NULL exactly where `accessible_km` is; live check uses the rollup's join shape | default SQL; the direct query uses an inner join to access where the rollup left-joins, equivalent under `access_bt = 2` | holds |

## Findings

- **[severity: fragile]** research/known_suspected_km.md:90-92 — "**#399** removes the km above each species' top record on a line: under `bcfishpass` the 1.9 to 29.7 km per pair measured above." The quantifier is wider than what was measured. Under the walk (RUNBOOK §2c), a tributary's records count for every segment of the feature below its mouth, so a segment starting at a species' top record on one `blue_line_key` stays code 2 after #399 wherever a tributary entering that line above it holds a record of the species. #399 moves only the segment above a record that has no other record of the species anywhere upstream, and only that segment (to the next break), not "the km above" the record. That is exactly the set `parity_pieces.sql` measured (segments bcfishpass codes 1, i.e. nothing upstream), which is why the 1.9 to 29.7 km figures are right; the sentence's description of them is not, and a reader applying it to `default` would over-estimate what #399 moves (the next sentence repeats "the segment above a top record"). Suggested wording: "removes code 2 from the segment above each record with no other record of the species upstream of it: under `bcfishpass` the 1.9 to 29.7 km per pair measured above."
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (compression gaining a quantifier the source does not carry)

No defects in the R code, the default SQL, the tests, `rollup.R`, `parity_pieces.sql`, or the round 3 fixes (claims 40, 41, 50 hold).
