# Code-check round 2: #401 branch (47bb3dfa...93c68a52)

## Checklist read

- **code-check.md:** the prose of all 14 H3s under `## Mechanisms` (table rows skipped; read from the extracted `mech.txt`). Not read: 24 (Rules that stand alone 15, Security 6, Spreadsheets and PDFs 3; none names a tool or shape this diff uses).
- **code-check-r.md:** read in full: "Postgres row order is never fixed unless the query fixes it, so a pick, a float sum and a presence check can each depend on it"; "A `function(...)` mock hides arguments the real callee no longer accepts"; "`load_all()` refuses an installed dependency below the `Imports:` floor, so measure old-against-new from a frozen worktree"; "`on.exit()` at a script's top level never fires". Not read: 111.
- **code-check-shell.md:** read in full: "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0". Not read: 69.
- **code-check-spatial.md:** read in full: "FWA `upstream_route_measure` misses the next segment's start"; "FWA main flow is not edge type 1000 alone"; "A Freshwater Atlas main stem's downstream end lies on the receiving river's centreline, not at the confluence". Not read: 90.

## Clean

No issues found.

## What I checked (no finding)

**The round-1 fix, `data-raw/pretest/obs_upstream.sql`, as the gate consumes it.**

- Ran it read-only on the local fwapg (no other active client): 36 s, 246 groups, one row each (PORI 0), so `pretest_pick()` gets a value for every group and no group drops out for a missing outlet. Top values: LFRA 126,143; HARR 102,474; FRCN 87,488; LARL 58,912; SETN 43,683. At `--per-input=2` the gate picks LFRA and HARR.
- HARR second is right for the walk, not an outlet artifact: HARR holds 120 order-10 segments (61 km) of the Fraser main stem (`wscode_ltree = '100'`), so the max-order rule puts its outlet on the Fraser at 84,054 m and its segments do sit below ~100k records.
- `fwa_upstream` resolves to the 10-argument overload, which passes `downstream_route_measure_a` as `upstream_route_measure_a`, so the same-line test is `b.drm >= a.drm + 1`: the walk's own test (fresh calls the same overload). The 11-argument body's first clause is `wscode_ltree_b <@ wscode_ltree_a`, so the SQL's `b.wscode <@ o.wscode_ltree` prefilter restates a necessary condition and drops nothing. `bcfishobs.observations` has 0 NULL `wscode` rows and only its primary key index, as the comment says.
- `DISTINCT ON … ORDER BY …, linear_feature_id` ends on a unique key, so the outlet pick reproduces. `count(b.*)` over the `LEFT JOIN` gives 0 for an unmatched outlet.
- `pretest_pick.R` reads `data-raw/pretest/<input>.sql` by name, runs it with no statement bound, and keeps groups with history; `pretest_match()` returns one hit per matching row, so the two rows each for `lnk_pipeline_access.R` and `frs_network_features.R` give both inputs. `PRETEST_RULES` globs `data-raw/pretest*` and `data-raw/pretest/**`, so the new query voids older records as intended.

**The rest of the branch.**

- `lnk_pipeline_access()`: distinct-mode return shape (`feature_ids`, NULL array parsed to `character(0)`, segments with no record absent), the named-list lookup and its empty cases (0 walk rows, 0 segments), the gate's existence walk, `observed & has_observation_key_upstr` under the gate. Matches bcfishpass's `spp INNER JOIN ids` read from the local checkout's `load_streams_upstr_observations.sql` (`spp` unfiltered by group, `ids` with `a.watershed_group_code = b.watershed_group_code`, both `FWA_Upstream(…, False, 1)`). `has_observation_key_upstr` is not persisted (`lnk_persist_init.R:89`).
- `lnk_pipeline_run()`: the drop's `on.exit(add = TRUE)` runs after the log-fail handler and after `log_finish`; with `cleanup_working = TRUE` the schema is gone first and the `IF EXISTS` drop is inside `try()`. `observations_province` is built unconditionally in prepare (empty-table path included), so the access walk always finds it. Other `lnk_pipeline_access()` callers (`lnk_access()`, both modes) pass `observations = NULL`; nothing else in `R/` or `data-raw/` reads the province table.
- Config key validated at load and through `extends:` (test covers a bad value under `extends: default`); the `acc` payload hashes the resolved value, so absent and `group_gated` hash alike; `vocabulary.csv` retires `acc-v2` / `acc-bcfp-2` at 0.73.0 and `.lnk_vocabulary_match()` keys "live" on `is.na(retired)`.
- `pre_post_diff.R`: rule columns (`want_a`, `want_b` with the gate only for `bcfishpass`), joins on `(id_segment, watershed_group_code)`, measure-overlap pieces; `run.sh`'s quiet probe fails toward busy (`|| n=1`), and its subshell `cd` is guarded.

## Notes (not findings)

- **The outlet's tie-break compares measures across blue lines.** In 18 groups several max-order lines of equal `nlevel` all start at measure 0 (coastal groups with several rivers, and side channels: ATLL, BABL, CLAY, CLRH, COMX, FINA, GOLD, GRAI, KHTZ, LRDO, MBNK, MORI, NASC, NECL, PORI, SEYM, SHUL, TSIT), so `linear_feature_id` decides, and the pick differs from fresh's `inst/extdata/wsg_outlet.csv` (whose tie is plan order). Neither is a network rule: SQL's pick is downstream of fresh's in BABL, SHUL and ATLL and upstream in FINA and CLRH. The value moves about 10 % (FINA 3,163 here against 3,443 at fresh's outlet; CLRH 5,504 against 6,083), far below the picks (LFRA, HARR), so no pick changes. A `localcode_ltree` tie-break would order points along the network; both this file and fresh share the measure rule (#238).
- **The input counts raw `bcfishobs.observations`** (every species, no presence filter, no exclusions), not `observations_province`, which the walk reads. As a ranking input that is a close proxy; RUNBOOK's "what the access walk reads" describes the scope, not the exact table.
- **Direct callers of `lnk_pipeline_prepare()` now keep the province table.** Only `lnk_pipeline_run()` drops it. The callers outside it are one-off scripts (`data-raw/exp_gradient_extra_breaks.R` and four `data-raw/logs/*/` scripts), each leaving ~200 MB in its working schema if re-run. No data effect.
