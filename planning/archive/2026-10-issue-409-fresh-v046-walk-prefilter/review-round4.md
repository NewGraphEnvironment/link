# Code-check round 4 (termination) — #409 (fresh v0.46.0 pin, prefilter_409 record)

## Checklist read

- Indexes read: `index_code-check.md`, `index_code-check-r.md`, `index_code-check-shell.md`, `index_code-check-spatial.md`.
- code-check.md: prose of every H3 under `## Mechanisms` (guard that fails toward pass, fixture that cannot reach the failure, proxy is not the property, verification that reads its own output, guard's scope, fix in one of two callers, restore the bug, shared working tree, wrapper's exit, zero/empty/unset, probe broken before the world, written data outlives the fix, serialization, one fact derived twice).
- code-check-r.md sections for patterns the diff uses: on.exit at top level; data-raw must load the source tree; `sort()`/`order()` collate by locale; `read.delim()` quotes by default; Rscript reads a script as it runs; Postgres row order; `function(...)` mocks hide arguments; `stats::aggregate()` silent behaviours; `system2(stdout = TRUE)`; `local_mocked_bindings`; `is.na` on NULL.
- code-check-shell.md sections: `if ! cmd; then rc=$?`; `grep -c`; heredoc delimiter; process substitution / `mapfile` (bash ≥ 4); `set -u` empty arrays; psql `:'var'`; `pgrep -f` waiter; `&` binding; wrapper exit.
- code-check-spatial.md: index only (the diff's only spatial call is `md5(ST_AsEWKB(...))` in compare.R, inherited from #367).

## Method

Every claim below was re-derived from the outputs, not the prose: `recompute/steps_*`, `walks_*`, `digest_*`, `status.txt`, `input_counters.tsv`, `summary_*.csv`, `rerun_SETN_a2_refused1.log`; `model/*`; `ties_*.txt`; `reach.md`, `pick_only.md`; fresh v0.46.0's `R/frs_network_features.R`, `NEWS.md` and `data-raw/logs/network_features_272/{README.md,walks.tsv}`; `recompute_cost_261/README.md`; `provincial_361/buckets_default.md`; read-only queries on m4's local fwapg; `git reflog` in `~/Projects/repo/fresh`; `ps` for the running driver. Nothing was queried on the dispatcher, because the waiting driver counts any lock in `fresh_default` as company.

## Enumeration

Verdicts: S = SUPPORTED, W = WIDER, U = UNSUPPORTED, X = WRONG. `rc/` = `data-raw/logs/prefilter_409/recompute/`, `md/` = `.../model/`, `PR/` = `data-raw/logs/prefilter_409/`.

| # | where | claim | producer | verdict |
|---|---|---|---|---|
| 1 | CLAUDE.md:14, NEWS.md:3, RUNBOOK.md:1553-1554 | walks read only features on the group's lines or downstream (ancestor-or-equal) codes | fresh `.frs_walk_prefilter` (blue-line arm, `subpath` ancestor arm) | S |
| 2 | CLAUDE.md:16 | pins fresh v0.46.0, floor and `Remotes:` | DESCRIPTION | S |
| 3 | CLAUDE.md:16, NEWS.md:3 | v0.46.0 carries fresh#272 (scoped walk) and fresh#242 (group-matched passes) | fresh NEWS 0.45.0 / 0.46.0 | S |
| 4 | CLAUDE.md:16, NEWS.md:3 | no link code changed, because link passes `aoi` on every downstream walk | `git diff 64f8de0a -- R/ inst/` empty; `frs_network_features` called only at R/lnk_pipeline_access.R:156,184 (downstream, `aoi`) and :208 (upstream) | S |
| 5 | CLAUDE.md:16, NEWS.md:6, PR/README tables, research table | CHWK 686→75, LSKE 580→178, LKEL 111→46, SALR 42→23, SETN 1,481→891 | rc/summary_steps.csv `total` | S |
| 6 | CLAUDE.md:16, NEWS.md:6, PR/README:74 | 77 % less over the four; 23.6 → 5.4 min | 1,418.9 → 322.3 s | S |
| 7 | PR/README:74 | over all five 48.3 → 20.2 min (58 %) | 2,899.9 → 1,213.2 s | S |
| 8 | PR/README:95-100, research:74-81 | ratios 1.8/2.4/3.3/9.2/1.7, walks 28→10 … 1,332→774, ratios 2.9/3.6/4.4/14.7/1.7, all-five 2,900/1,213/2.4×, 2,624/970/2.7× | summary_steps.csv | S |
| 9 | CLAUDE.md:16, NEWS.md:5 | recompute outputs digest-identical in all five groups | rc/digest_*: 152 of 152 `same`; one digest per wsg×table across all runs | S |
| 10 | PR/README:71-72 | 18 runs; 4 to 10 tables per group | digest_*: SALR 4, LKEL 9, LSKE/CHWK/SETN 10; 4+4+4+4+2 runs | S |
| 11 | NEWS.md:5, PR/README:72-73, research:86-87 | every walk returned the same features per segment, 48 of 48 | summary_walks.csv `same_features` all TRUE, 48 rows | S |
| 12 | PR/README:73-75 | `streams` / `barriers` write counters did not move | input_counters.tsv: 12 identical rows bracketing every finished run | S |
| 13 | CLAUDE.md:16, NEWS.md:5, PR/README:88-89, research:87-90 | model time: five table kinds identical for ADMS, NATR, ELKR; 25 of 25 non-empty, 20 empty | md/model_digests.csv; md/model_provenance.csv (0.44.0/0.46.0, one link SHA, clean) | S |
| 14 | PR/README:46-48, research:89-90 | `barrier_overrides` and `streams_near_river` not compared; `frs_near_river.R` unchanged between pins | compare.R `tables_of`; round 3's `git diff v0.44.0 v0.46.0` | S |
| 15 | PR/README:42-43 | ADMS SK and NATR KO reach fresh#242's connected-waterbody pass | md digests (ADMS sk, NATR ko non-empty); fresh 0.46.0 NEWS ("SK and KO reach this path") | S |
| 16 | CLAUDE.md:18 | Owed: SETN pair; re-prep with `--auto-install`; pin voids the 2026-10-29 gate record; provincial minutes | status.txt; #372 record mechanics | S |
| 17 | CLAUDE.md:18 | dispatcher busy with another session "for hours" | status.txt (72 min waited before SETN a2 refusal) + PWF | S (operator estimate) |
| 18 | CLAUDE.md:21, PR/README:116-117, research:103-104 | under 0.46.0 walks are 41 % (SALR) to 87 % (SETN) | per run 40.7 % (SALR a2) to 86.8 % (SETN a1) | S |
| 19 | CLAUDE.md:21, PR/README:117, research:104 | "against 66 to 96 % under 0.44.0" — CLAUDE.md says "of the five groups' runs" | fastest runs give 65.8 / 95.9; per run under 0.44.0 it is 58.9 % (SALR b1) to 96.9 % (CHWK b1) | W (F3) |
| 20 | CLAUDE.md:21, PR/README:108, research:95 | natural walks, summed per group, gain 4.7× to 17× (SETN 1.8×) | summary_walks.csv: SALR 5.22, LKEL 4.70, LSKE 4.90, CHWK 17.33, SETN 1.77 | S |
| 21 | PR/README:108-109 | per walk 1.45× to 18.5× | SETN rb 1.45, CHWK co 18.45 | S |
| 22 | CLAUDE.md:21, PR/README:118-120, research:95-96 | #261's prefiltered walks 6.3× (SALR) to 24.6× (CHWK) server-side | recompute_cost_261/README:111-119 (`EXPLAIN ANALYZE` plans) | S (note: #261's per-group figure includes the anthropogenic walk, these do not; including it here lowers the 0.46.0 gain, so "below" holds either way) |
| 23 | research:95-96, PR/README:120 | SETN output-bound, as #261 found (1.2× there) | #261 README:119-123 (4.83 M pairs, sort spill); same features both versions | S (inherited) |
| 24 | CLAUDE.md:22, NEWS.md:6, PR/README:109-111, research:97-98, RUNBOOK.md:597-599 | every PSCIS and dam walk slower: 1.0-1.3 s SALR/LKEL/CHWK, 2.0-2.4 LSKE, 3.5-4.2 SETN ("about 1 … up to about 4") | summary_walks.csv: 1.03-1.33, 2.04-2.38, 3.47-4.19 | S |
| 25 | PR/README:109-110, research:98-99 | anthropogenic walk slower in four groups of five (CHWK 4.4 → 1.8) | summary_walks.csv | S |
| 26 | CLAUDE.md:22, PR/README:111-112, research:98, RUNBOOK.md:599-600 | a group makes 5 to 11 walk calls (SALR 5, the others 10 or 11) | walks_* rows per run: 5 / 10 / 11 / 11 / 11 | S |
| 27 | CLAUDE.md:22, NEWS.md:6, PR/README:112, research:99-100, RUNBOOK.md:600 | what costs the rise is not measured | — | S |
| 28 | CLAUDE.md:22, PR/README:112-114, research:100-101 | fresh's temp-table timing 0.07-0.15 s (SALR, LKEL, CHWK), 0.7 s LSKE | fresh network_features_272/walks.tsv `ddl_seconds` 0.072-0.146, 0.665-0.723 | S (numbers) |
| 29 | CLAUDE.md:22, PR/README:113 ("m4"), research:100 | that timing was taken **on m4** | m4's `fresh_default.streams` holds 859,522 rows, no SALR/CHWK, last written 2026-10-27; fresh's walks returned CHWK CH 11,301 and SALR CH 1,343 segments, the dispatcher recompute's own counts; fresh's README names an 11.3 M-row province-wide `streams`; the #272 commits reached m4's fresh clone by `pull` | X (F1) |
| 30 | CLAUDE.md:22, NEWS.md:6, PR/README:114-115, research:101-102 | walking each barrier set once (#394) makes fewer calls | #394 title | S |
| 31 | CLAUDE.md:23, PR/README:76-77, research:91-92 | order changed in 9 per-species natural walks (CHWK's 8, SALR CH), same within each version | walks_*: `digest_order` unique per wsg×table×side in all 48; differs across sides in exactly those 9 | S |
| 32 | CLAUDE.md:23, PR/README:77-78, research:92 | link reduces natural arrays to membership | R/lnk_pipeline_access.R:243-252 | S |
| 33 | CLAUDE.md:23 | fresh 0.45.0 breaks ties on the feature id | fresh R/frs_network_features.R:305-310 (`b.<id>` last) | S |
| 34 | CLAUDE.md:23, PR/README:78-81 | natural views hold co-located copies; 189 / 188 on m4's 30-group copy, which holds neither CHWK nor SALR; the dispatcher's copy not counted | ties_natural.txt; read-only m4 query: 1,119,730 rows, 30 groups, no CHWK/SALR | S (accepted as labelled) |
| 35 | CLAUDE.md:23, NEWS.md:5, PR/README:82-83, research:92-94 | no anthropogenic tie among the dispatcher's 502,233 rows (241 groups), so `dam_dnstr_ind` cannot move there | ties_anthropogenic.txt; tie key = fresh's three `ORDER BY` keys; R/lnk_pipeline_access.R:282-291 reads `anth[1]` | S (241 from the file header) |
| 36 | research:59-61, PR/README:84-87 | `remediated_dnstr_ind` computed at model time only; 356,568 rows in 134 working schemas (of 138), unrecorded dates, no tie; dispatcher modelled 74 groups on 2026-10-23 | R/lnk_access.R:192-207 (`crossings_table = NULL`, merge leaves it); ties_remediations.txt; provincial_361/buckets_default.md:98 | S ("with rows" means a non-empty remediation set, not crossings rows) |
| 37 | research:57-58 | until 0.45.0 the `ORDER BY` had no unique tiebreak | fresh NEWS 0.45.0 | S |
| 38 | CLAUDE.md:24 | pak put 26 resolved dependencies into the scratch library | PWF findings | S (PWF only) |
| 39 | CLAUDE.md:25 | rerun.R refuses on any other lock or > 1 other active client | rerun.R:124-136 | S |
| 40 | CLAUDE.md:25 | rerun.R "checks for company only at its start … and does not look again" | rerun.R:255-258 samples `busy_end` (which is how the next clause knows SETN had company) | W (F5) |
| 41 | CLAUDE.md:25 | SETN's 0.46.0 run had another client by its end | steps_SETN_a1.tsv `others_end` 1 | S |
| 42 | CLAUDE.md:25, PR/README:55-56 | autovacuum's lock, set off by the runs' own rewrites, refused one run | status.txt (LSKE a2 exit 1, 3 s); holder read live (PWF) | S (inference) |
| 43 | CLAUDE.md:25, PR/README:57-59 | a session running walks back to back left a gap the driver started into → QUIET_S | status.txt (SETN a2 refused 3 s after 4,320 s of waiting); refused1.log (16 locks) | S |
| 44 | CLAUDE.md:26, #411 | lnk_access builds a scoped table: CREATE, four indexes, ANALYZE | R/lnk_access.R:171-184 | S |
| 45 | CLAUDE.md:26, #411 | its step, holding the merge UPDATE, is 2.7 to 7.7 s under 0.46.0 | summary_steps `setup_and_update` s_a: 2.73-7.73 | S |
| 46 | CLAUDE.md:26 | "now redundant beside fresh's" | fresh `.frs_walk_scope` copies from whatever table it is given; cost of skipping it owed in #411 | S (design statement; #411 holds the check) |
| 47 | #411 | recompute makes no upstream walk | R/lnk_access.R:193,206 (`observations = NULL`) | S |
| 48 | #411 | fresh scopes with `WHERE watershed_group_code = aoi` on whatever table it is given | fresh `.frs_walk_scope` :347 | S |
| 49 | #411 | before 0.45.0 a view or the province-wide table led the planner to drive from the barrier side (#205) | R/lnk_access.R:160-170 comment; fresh 0.45.0 NEWS | S |
| 50 | #411 | overlaps #410, which edits the same function | #410 body (lnk_access()'s `barrier_sources`) | S (plan) |
| 51 | CLAUDE.md:37, pretest_inputs.csv `why` (28 rows), PR/README:131-132 | fresh reach the same 18 files at v0.44.0 and v0.46.0; 28 unreached | PR/reach.md: identical lists at both tags (18 + 28) | S |
| 52 | PR/reach.md:3 | run from link `8ddbffeb` with the pin bumped | 8ddbffeb is the PWF baseline (pin bump uncommitted then, committed b0dd63eb) | S |
| 53 | PR/README:133-134, NEWS.md:8 | pick-only over fresh v0.42.0..v0.46.0 exits 0, 31 changed files each mapped | pick_only.md (31 rows, all mapped); session pick.log | S |
| 54 | NEWS.md:7 | a host below 0.46.0 fails `lnk_preflight_fresh()`; a walk needs a session that can create temp tables | R/lnk_preflight_fresh.R floor check; fresh 0.45.0 NEWS | S |
| 55 | NEWS.md:8 | tests: every downstream walk passes `aoi`; floor = `Remotes:` tag | the two tests (round 3 ran them: 0 failed, 0 skipped) | S |
| 56 | RUNBOOK.md:592-596 | copies segments into an indexed, analyzed temp table; admits blue-line or ancestor-or-equal features; plan no longer depends on the segments table link hands it | fresh :258-271, :344-371 | S |
| 57 | RUNBOOK.md:596-598 | read-only transaction / hot standby / transaction pooler | fresh 0.45.0 NEWS | S |
| 58 | RUNBOOK.md:601-602 | without `aoi`, the old province-wide walk, same answers | fresh `aoi = NULL` path | S |
| 59 | RUNBOOK.md:1551-1552 | "Most of the recompute's cost is its downstream walks (#261; 41 to 87 % of five groups' runs under v0.46.0)" | SALR 41 %, LKEL 50-53 % | W (F2) |
| 60 | RUNBOOK.md:1553-1555 | the gate's scratch barriers hold only its picks, so it cannot exercise them | RUNBOOK §8d | S |
| 61 | research:3-7 | header: produced on the 2026-10-23 build; #409's model builds and one tie count on m4 | PR/README | S |
| 62 | research:65-72 | four runs for SALR, LKEL, LSKE, CHWK; twice so far for SETN; on the dispatcher, serially from m4 | status.txt | S |
| 63 | PR/README:3 | measured 2026-10-29 00:58 to 05:12 UTC; recompute runs 01:27 to 03:23 | md/stamp.txt 00:58:47; status.txt; ties_natural committed 05:12 | S |
| 64 | PR/README:10-14 | PostgreSQL 17.5, work_mem 512 MB; 2026-10-23 build; five groups at `1d00c04c`; R 4.5.2 on m4 | #261 README (same DB); rerun.R's HEAD check; `R --version` | S |
| 65 | PR/README:15 | model builds on m4's local fwapg from `64f8de0a` | md/model_provenance.csv `link_sha`; compare.R on localhost | S |
| 66 | PR/README:16-22 | arms differ only in fresh; SHAs; shared deps; line 1 of each log | walks_* `fresh_sha`; rlib_fresh046 / rlib_fresh044 hold `fresh/` only | S |
| 67 | PR/README:23-25 | recompute code is the new pin's (5-file diff empty); `1d00c04c`'s floor 0.42.0 admits both | `git diff 1d00c04c HEAD -- …` empty; `git show 1d00c04c:DESCRIPTION` | S |
| 68 | PR/README:29-35, rerun.R:4-9 | rerun.R unchanged from #261's except the listed changes | `diff recompute_cost_261/rerun.R prefilter_409/rerun.R` | S |
| 69 | PR/README:55-62 | two refusals and one hand stop; SETN a2 after 72 min; relaunch with LIB044 so the shared library could move | status.txt; input_counters.tsv (two launches without a stop row); shared library now 0.46.0, LIB044 0.44.0 `22034c1a` | S |
| 70 | PR/README:62-65 | LSKE a2's refusal log overwritten; SETN's kept as refused1; "the driver now keeps an earlier attempt's log" | the driver now running the pending SETN pair is `scratchpad/rerun_all_frozen.sh` (pid 11752, started 04:44 UTC), which has no log keeping and no RESUME check | W (F6) |
| 71 | PR/README:102-103, research:83-84 | SETN one run per version; another client by the end of a1, so 891 s may be high | status.txt; steps_SETN_a1 | S |
| 72 | PR/README:105 | walks are the whole gain | saved: walks 613.3/63.9/400.5/17.9 of total 611.3/64.9/401.7/18.7; SETN 558.8 of 590.1 with mapping code named as one pair | S |
| 73 | PR/README:105-106 | gate, mapping code, setup vary as much within a version as between; LKEL mapping code 4.4 to 7.3 under 0.46.0 | steps_LKEL_a1/a2 7.338 / 4.362 | S |
| 74 | PR/README:107 | "first runs read colder" | b1 is each complete group's slowest run, but no buffer read was measured, and per step it is not so (CHWK mapping code a2 11.3 > a1 7.4; LSKE b2 27.2 > b1 26.2) | W (F4) |
| 75 | PR/README:124-127, research:105-107 | provincial share and model-time minutes not measured | design | S |
| 76 | test-lnk_pipeline_access.R comment | without `aoi` each walk drives from every feature in the province | #261; fresh `aoi = NULL` path | S |
| 77 | test-lnk_preflight_fresh.R comment | a floor below the pin lets an older fresh pass; older fresh gives the same answers more slowly | preflight floor check; rc digests | S |

**Counts:** 77 claims; SUPPORTED 71, WIDER 5 (#19, #40, #59, #70, #74), UNSUPPORTED 0, WRONG 1 (#29).

## Findings

- **[bug] CLAUDE.md:22, data-raw/logs/prefilter_409/README.md:113, research/recompute_cost.md:100 — fresh's temp-table timing was not taken on m4.** All three say it was ("0.07 to 0.7 s on m4", "(m4, fresh `data-raw/logs/network_features_272/`)"). The record says otherwise:
  - m4's local `fresh_default.streams` holds 859,522 rows (`pg_stat_user_tables`), has no SALR or CHWK segment, and was last written and analyzed 2026-10-27 07:42 UTC; `fresh_default.log` there holds four groups (PCEA, FINA, PARS, LKEL).
  - fresh's README for that log names `segments = fresh_default.streams (province-wide, 11.3 M rows)`, and its `new` walks return CHWK CH 11,301 and SALR CH 1,343 segments, the same counts the dispatcher recompute's walks return (`walks_CHWK_a1.tsv`, `walks_SALR_a1.tsv`).
  - The #272 commits (`b8f702c`, `18d36bc`, `df7ae64`) are not in m4's fresh reflog; they arrived by `pull --ff-only` (8a5ca76).
  So the timing ran on a database holding the province-wide 2026-10-23 build, most likely the dispatcher's own. The label came from round 2's review ("That is on m4's local database, not the dispatcher, so it does not settle the question") and was copied into the prose without a check. The direction matters less than the label: if it was the dispatcher, the comparison with the rise is same-database and stronger, not weaker. Fix: drop "on m4"; say "fresh's own timing of its temp-table build, on a database holding the province-wide build (fresh's README)", and confirm the host from fresh's session record if it should be named.

- **[fragile] RUNBOOK.md:1551-1552 — "Most of the recompute's cost is its downstream walks (#261; 41 to 87 % of five groups' runs under fresh v0.46.0, #409)".** This is round 3's fix to its F8, and the quantifier contradicts its own parenthesis: in SALR the walks are 41 % (9.6 of 23.2 s) and in LKEL 50 to 53 %, so "most" fails in one group of five and is marginal in another. Fix as round 3 proposed: "was its downstream walks (#261); under fresh v0.46.0 they are 41 to 87 % of five groups' runs (#409)".

- **[fragile] CLAUDE.md:21 — "41 % (SALR) to 87 % (SETN) of the five groups' runs, against 66 to 96 % under 0.44.0".** The 0.46.0 range holds per run (40.7 to 86.8 %). The 0.44.0 range is the fastest runs only (and `summary.R`'s per-step minima: CHWK's walks and total minima come from different runs); over the five groups' runs it is 58.9 % (SALR b1) to 96.9 % (CHWK b1). README:116-117 and research:103-104 sit under "each arm's fastest run" and read correctly; CLAUDE.md's "of the five groups' runs" does not. Say "of each version's fastest run".

- **[fragile] data-raw/logs/prefilter_409/README.md:107 — "first runs read colder".** A cause (cache state) no output measures; no buffer counts were taken. What the outputs show is narrower: b1 is the slowest run of every complete group (SALR 49.4 / 41.9 s, LKEL 125.4 / 111.4, LSKE 601.8 / 579.6, CHWK 1,010 / 686), while for the step the sentence is about it does not hold (CHWK mapping code a2 11.3 s against a1 7.4; LSKE b2 27.2 against b1 26.2). Say "b1 was each complete group's slowest run", or cut the clause.

- **[fragile] CLAUDE.md:25 — "`rerun.R` checks for company only at its start … and does not look again (SETN's 0.46.0 run had another client by its end)".** rerun.R does look again: it samples other active clients after the steps (`busy_end`, rerun.R:255-258) and stamps them, which is how the parenthesis is known. What it does not do is refuse, or check locks, again. "does not refuse again (it samples clients at the end only to stamp them)".

- **[fragile] data-raw/logs/prefilter_409/README.md:64-65 — "the driver now keeps an earlier attempt's log".** True of the committed `rerun_all.sh`, not of the driver that will produce SETN's pending pair: `ps` shows pid 11752 running `scratchpad/rerun_all_frozen.sh`, copied 04:44 UTC from the pre-df73195f script, with no log keeping and no unmatched-RESUME check (`diff` against the committed script: those two blocks only). Round 3 raised this (its F14); the duplicate was untracked, but the README still attributes the behaviour to "the driver". No data is at risk (refused1 is separate, and the frozen driver overwrites only the untracked duplicate). When the pair lands, name the frozen copy and its difference from the committed script.

## Code

No defects found in the diff's code:
- `rerun.R`: radix sort is locale-free; the walk wrapper handles a 0-row walk; no top-level `on.exit`; backups and the restore statement survive a moved digest; the backup-exists refusal protects a prior failure's only copy.
- `rerun_all.sh`: the quiet loop fails closed (a psql failure prints nothing, which is not `"0"`, and resets quiet); `[ -e "$log" ] && mv` is safe without `set -e`; the success test needs both the marker and exit 0; the unmatched-RESUME check precedes `ALLDONE`.
- `summary.R`: asserts one fresh version per side and the expected versions; `read.delim` on unquoted TSV with no quote characters.
- `compare.R`: refuses unless six provenance rows with the expected versions, one link SHA and `link_dirty` all FALSE (an NA fails `stopifnot`); empty-on-both is NA, one-sided empty is FALSE; digest orders are unique keys within a group.
- `ties_remediations.sh`: an empty schema list fails; `mapfile` needs bash ≥ 4 (the `env bash` on m4 is Homebrew's; the 3.2 `/bin/bash` would fail loudly, not silently).
- `model_run.sh`: records each build's exit; compare.R's provenance check is the gate.
- Tests: the `aoi` test fails if any downstream call drops `aoi` (NA ≠ "ADMS") or a source walk is lost (length 4); the floor test fails on a floor below the tag, and skips only when `Remotes:` is absent.

## Note outside the diff

#410's body still says "every group runs three extra province-wide walks". Since this pin those walks are scoped, and the PSCIS and dam walks are the ones that got slower per call (1.0 to 4.2 s each); #410's measure-first step should start from #409's per-walk numbers.

## Termination

One WRONG (a host label inherited from round 2's reviewer, not from any output) and five WIDER, four of them single clauses. One of the five (RUNBOOK "Most …") sits inside round 3's fix, so the mechanism round 3 named is still live in the fixes; the rest are clauses earlier rounds did not reach. Every number in the branch re-derives from its producer. Fix the six and the record is closed on this enumeration; a fifth round would need to re-check only the six edited sentences.
