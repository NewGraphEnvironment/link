# Code-check round 3 — #409 (fresh v0.46.0 pin, prefilter_409 record)

## Checklist read

- Indexes read: `index_code-check.md`, `index_code-check-r.md`, `index_code-check-shell.md`, `index_code-check-spatial.md`.
- code-check.md, prose of every H3 under `## Mechanisms` read (tables skipped), with "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "A guard's scope, escape hatches, and remedies", "One fact derived twice", "Verification that reads its own output" and "Serialization loses meaning silently" read in full.
- code-check-r.md sections for patterns the diff uses: "on.exit() at a script's top level never fires", "A data-raw/ script must load the source tree", "testthat counts an uncaught error under error", "`sort()` and `order()` collate by LC_COLLATE", "`read.delim()` quotes by default", "Rscript reads a script as it runs", "Postgres row order is never fixed unless the query fixes it", "A `function(...)` mock hides arguments", "`stats::aggregate()` has three separate silent behaviours", "`system2(stdout = TRUE)` warns on a non-zero exit".
- code-check-shell.md sections: "`if ! cmd; then rc=$?`", "A `pgrep -f` waiter", "psql does not interpolate `:'var'`", "`grep -c` prints the count AND exits 1", "`for x in $(cmd | grep … || true)`", "A heredoc whose body contains its own delimiter", "Empty arrays under `set -u`", "process substitution" (via `mapfile < <(...)` in ties_remediations.sh).
- code-check-spatial.md: index only; nothing spatial in the diff beyond `md5(ST_AsEWKB(...))` in compare.R (inherited from #367).

## Mechanism

Every prior finding, and every one below, is a sentence whose **conclusion** was written from the shape of the measurement rather than re-derived from the files the measurement wrote: the numbers in a sentence get fixed when a review points at them, but the clause that interprets them ("which is why …", "describe the 2026-10-23 build", "where the walk returns little", "each run four times") was composed from the design of the experiment and is never checked against the outputs. Round 1 fixed numbers and kept the cause; round 2 fixed the cause in one sentence and the same conclusion survives in the next; here the *interpretive* clauses and the *population* a count is said to describe are what is wider than the record.

The candidate set this implies: every interpretive clause and every named population (which build, which groups, which runs, which walks) in the changed prose, each checked against the output file that would have to back it. That is the table below.

## Enumeration (table)

Verdicts: S = SUPPORTED (re-derived), W = WIDER, U = UNSUPPORTED, X = WRONG. Producers: `rc/` = `data-raw/logs/prefilter_409/recompute/`, `md/` = `.../model/`.

| # | where | claim | producer | verdict |
|---|---|---|---|---|
| 1 | CLAUDE.md:14 (title), NEWS.md:3, RUNBOOK.md:1551-1552 | walks "scoped to / admit only the features that can reach the group" | fresh v0.46.0 `.frs_walk_prefilter` | W (prefilter is a necessary-condition superset; see F9) |
| 2 | CLAUDE.md:16 | pins fresh v0.46.0, floor and Remotes | DESCRIPTION | S |
| 3 | CLAUDE.md:16, NEWS.md:3 | carries fresh#272 scoped walk and fresh#242 group-matched passes | fresh NEWS 0.45.0/0.46.0 | S |
| 4 | CLAUDE.md:16, NEWS.md:3 | no link code changed; link passes `aoi` on every downstream walk | `git diff` (no R/), grep: `frs_network_features` is called only in R/lnk_pipeline_access.R (3 sites, all pass `aoi`) | S |
| 5 | CLAUDE.md:16, NEWS.md:6, README tables, research table | CHWK 686→75, LSKE 580→178, LKEL 111→46, SALR 42→23, SETN 1,481→891 | rc/summary_steps.csv `total` | S |
| 6 | CLAUDE.md:16, NEWS.md:6, README:74 | 77 % less over the four; 23.6→5.4 min | summed `total`: 1418.9→322.3 s | S |
| 7 | README:74 | over all five 48.3→20.2 min (58 %) | 2899.9→1213.2 s | S |
| 8 | README/research tables | walk ratios 2.9/3.6/4.4/14.7/1.7; totals 1.8/2.4/3.3/9.2/1.7; all five 2,900/1,213/2.4×, 2,624/970/2.7× | summary_steps.csv | S |
| 9 | CLAUDE.md:16 | SETN "(output-bound)" | #261 record (recompute_cost_261/README:119, 1.2×) | S (inherited) |
| 10 | CLAUDE.md:16, NEWS.md:5, README:71, research:82 | recompute outputs digest-identical, every run | rc/digest_*.tsv: 152 of 152 `same`, one before/after digest per wsg×table across all runs | S |
| 11 | README:71 | 18 runs, 4 to 10 tables per group | digest_* (SALR 4, LKEL 9, others 10; 4+4+4+4+2 runs) | S |
| 12 | NEWS.md:5, README:72, research:82 | every walk returned the same features per segment (48 of 48) | rc/summary_walks.csv `same_features` all TRUE, 48 rows | S |
| 13 | CLAUDE.md:16, NEWS.md:5, README:86, research:84-86 | model time: every table compared identical; 25 of 25 non-empty, 20 empty | md/model_digests.csv | S |
| 14 | NEWS.md:5, README:46-48, research:85-87 | not compared: barrier_overrides (link's) and streams_near_river (fresh code unchanged) | lnk_persist_init.R table list; `git diff v0.44.0 v0.46.0 -- R/frs_near_river.R` empty; frs_habitat_classify.R diff is progress count + docs | S |
| 15 | README:42-43 | ADMS SK and NATR KO reach fresh#242's connected-waterbody pass | md/model_digests.csv (ADMS sk, NATR ko non-empty); fresh 0.46.0 NEWS | S |
| 16 | README:48 | scratch schemas dropped | read-only query on m4: no `fresh_409a/b` | S |
| 17 | CLAUDE.md:17-18 (Owed) | the pin voids the 2026-10-29 gate record | #372 mechanics (fresh pin compared) | S |
| 18 | CLAUDE.md:18 | dispatcher busy "for hours" | rc/status.txt (72 min to SETN a2 refusal) + progress.md:16 (operator's ~3 h) | S (operator estimate) |
| 19 | CLAUDE.md:21, NEWS.md:6, README:108-109, research:95, RUNBOOK:598-599 | PSCIS and dam walks rose 1.0-1.3 s (SALR/LKEL/CHWK), 2.0-2.4 (LSKE), 3.5-4.2 (SETN) | summary_walks.csv: 1.03-1.33, 2.04-2.38, 3.47-4.19 | S |
| 20 | same lines | rise happens "where the walk returns little" | walks_*: SETN dams 118,755 segs / 169,971 features rose 3.5 s; anthropogenic walks (SETN 507,630 features) rose too | W (F5) |
| 21 | CLAUDE.md:21, README:110, research:96 | a group makes 5 to 11 calls (SALR 5, others 10 or 11) | walks_* rows per run: 5/10/11/11/11 | S |
| 22 | CLAUDE.md:21, README:106, research:96 | every PSCIS and dam walk slower; anthropogenic slower in 4 of 5 (CHWK 4.4→1.8) | summary_walks.csv ratios | S |
| 23 | CLAUDE.md:21, NEWS.md:6 | "small groups gain least" / "which is why small groups gain least" | summary_steps.csv | X (F1) |
| 24 | CLAUDE.md:21, README:106/113, research:92-93 | natural walks gain 4.7× to 17× (SETN 1.8×) | summary_walks.csv summed per group: 4.70/4.90/5.22/17.33, SETN 1.77; per walk 3.85-18.45 | W (F3) |
| 25 | CLAUDE.md:21, README:112, research:93 | #261's 6.3× to 24.6× server-side | recompute_cost_261/README:111-119 (SALR 6.3, CHWK 24.6 over these four) | S |
| 26 | CLAUDE.md:21, README:110, research:97 | fresh's temp-table build 0.07-0.15 s (SALR/LKEL/CHWK), 0.7 s LSKE, m4 | fresh v0.46.0 data-raw/logs/network_features_272/walks.tsv `ddl_seconds` 0.072-0.146, 0.665-0.723 | S |
| 27 | CLAUDE.md:21, README:110, research:97 | ancestor-code array built per call is a candidate | fresh `.frs_walk_prefilter` (ARRAY(SELECT DISTINCT subpath…) per call) | S (as candidate) |
| 28 | CLAUDE.md:22, README:76-77 | element order changed only in per-species natural walks (9: CHWK's 8, SALR CH); same within each version | walks_*: digest_order unique per wsg×table×side in all 48; differs across sides in exactly those 9 | S |
| 29 | CLAUDE.md:22, README:78-81, research:77-79 | the order change is co-located copies persisted once per group; 189 / 188 on m4's 30 groups | ties_natural.txt; m4's copy holds neither CHWK nor SALR (checked) | W (F6; count itself accepted as labelled) |
| 30 | CLAUDE.md:22, README:81, research:78 | link reduces natural arrays to membership | R/lnk_pipeline_access.R:247-252 (`%in%` on segment ids) | S |
| 31 | CLAUDE.md:22, NEWS.md:5, README:82-84, research:79-80 | no tie among dispatcher's 502,233 anthropogenic rows (241 groups), so dam_dnstr_ind cannot move | ties_anthropogenic.txt; ORDER BY keys in fresh = (wscode, localcode, drm) = the tie key | S |
| 32 | CLAUDE.md:22, research:80-81 | remediation check covers 134 groups whose working schemas the dispatcher kept with rows (of 138) | ties_remediations.txt | S |
| 33 | README:84-85 | "Both counts describe the 2026-10-23 build" | dispatcher modelled 74 groups on 2026-10-23 (provincial_361/buckets_default.md); wsg_run_one keeps working schemas | X (F2) |
| 34 | research:56-59 | neither set has a co-located pair "on the 2026-10-23 build" | as #33 | W (F2) |
| 35 | NEWS.md:5 | tiebreak did not move remediated_dnstr_ind "in the 134 groups whose remediation sets could be checked" (in a sentence about the 2026-10-23 build) | as #33 | W (F2) |
| 36 | CLAUDE.md:23 | pak put 26 dependencies into the scratch library | planning/active/findings.md:14 (observation at the time; library since cleaned) | S (recorded in PWF only) |
| 37 | README:18-20 | RPostgres 1.4.10, DBI 1.3.0, sf 1.1.2, withr 3.0.3 from the shared library in both | current `find.package()` on m4: all four in the shared user library at those versions; scratch libs hold only `fresh/` | S |
| 38 | CLAUDE.md:24 | rerun.R refuses on any other lock or >1 other client, and does not look again | rerun.R:114-127 | S |
| 39 | CLAUDE.md:24 | SETN's 0.46.0 run had another client by its end | steps_SETN_a1.tsv others_end = 1 | S |
| 40 | CLAUDE.md:24, README:55-56 | autovacuum set off by the runs' own rewrites | live `pg_locks` read (README:63-64); rerun UPDATEs streams_access | S (inference) |
| 41 | CLAUDE.md:24 | autovacuum "leaves quiet gaps of seconds" | none: LSKE a2 refused under a driver that did not check locks (status.txt "waited 0 s") | U (F15) |
| 42 | CLAUDE.md:25, issue #411 | lnk_access builds a scoped table: CREATE, four indexes, ANALYZE | R/lnk_access.R:172-185 | S |
| 43 | CLAUDE.md:25, issue #411 | setup + merge UPDATE 2.7 to 9.5 s per group | summary_steps `setup_and_update`: 2.73 (SALR a) … 9.48 (SETN b); 0.46.0 arm 2.73-7.73 | W (F7: max is the 0.44.0 arm) |
| 44 | issue #411 | removing the table saves "about 4 to 8 s per group" | none; the measured step includes the merge UPDATE removal keeps | U (F7) |
| 45 | issue #411 | recompute makes no upstream walk | R/lnk_access.R:194,207 (`observations = NULL`) | S |
| 46 | issue #411 | persist streams has a `watershed_group_code` index | R/lnk_persist_init.R:479 | S |
| 47 | CLAUDE.md:36 | link reaches 40 R/ and 18 fresh files, same at v0.42.0/v0.44.0/v0.46.0 | reach.md (18 at v0.44.0 and v0.46.0, identical lists); #372 for v0.42.0 and the 40 | S |
| 48 | pretest_inputs.csv `why` (28 rows), README:125-127 | 28 fresh files not reached at v0.44.0 and v0.46.0 | reach.md NOT REACHED lists: same 28 files, both tags | S |
| 49 | README:127-129, NEWS.md:8 | pick-only over fresh v0.42.0..v0.46.0: 31 changed files, every one mapped | pick_only.md (31 rows, each with inputs) | S |
| 50 | NEWS.md:7 | a host below 0.46.0 fails lnk_preflight_fresh() | R/lnk_preflight_fresh.R:58,84 (`compareVersion(version, min_version)`, floor from DESCRIPTION) | S |
| 51 | NEWS.md:7, RUNBOOK:596-598 | needs a session that can create temp tables; read-only / hot standby / pooler | fresh 0.45.0 NEWS | S |
| 52 | NEWS.md:8 | tests: every downstream walk passes aoi; floor = Remotes tag | tests run in a throwaway worktree: 0 failed, 0 skipped | S |
| 53 | RUNBOOK:591-596 | copies segments into an indexed analyzed temp table; admits features on group blue lines or ancestor-or-equal wscode | fresh `.frs_walk_scope` / `.frs_walk_prefilter` | S |
| 54 | RUNBOOK:600-602 | every downstream walk link makes passes aoi; without it the old province-wide walk with same answers | grep (only lnk_pipeline_access); fresh: `aoi = NULL` → unprefiltered | S |
| 55 | RUNBOOK:1551 | "The recompute's cost is its downstream walks" (present tense) | summary_steps: walks are 41 % (SALR) to 87 % (SETN) of the 0.46.0 total | W (F8) |
| 56 | research:3-6 | produced on the 2026-10-23 default build | prefilter_409 model builds and ties_natural ran on m4's local fwapg | W (F12) |
| 57 | research:66-67 | five groups' whole recompute "each run four times" | status.txt: SETN ran b1, a1 only | X (F4) |
| 58 | research:65 | prefilter "admits only the features fwa_downstream() can return" | fresh `.frs_walk_prefilter` | W (F9) |
| 59 | README:3 | measured 2026-10-29 00:58 to 03:23 UTC | md/stamp.txt 00:58:47; status.txt SETN a1 03:23:49; but ties_natural.txt added in df73195f (05:12 UTC), SETN a2 attempt 04:36 | W (F11) |
| 60 | README:10 | PostgreSQL 17.5, work_mem 512 MB | recompute_cost_261/README:4 (same database, 2026-10-27) | S (inherited) |
| 61 | README:12-13 | "Every group's newest log and log_recompute row is at 1d00c04c" | progress.md:10 says "all five groups"; rerun.R checks log_recompute per run | W (F10) |
| 62 | README:16-17 | v0.44.0 RemoteSha 22034c1a; v0.46.0 8a5ca763 = `git rev-parse v0.46.0^{commit}` | walks_* fresh_sha; `git -C fresh rev-parse` | S |
| 63 | README:23-26 | recompute code is the new pin's (5-file diff empty) | `git diff 1d00c04c HEAD` on those 5 empty; other changed callees on the path (lnk_config.R: an added config check; utils.R: an added helper) do not change the recompute | S |
| 64 | README:29-33 | rerun.R unchanged from #261's except label/fresh, others/load, array digests, backup schema | `diff recompute_cost_261/rerun.R prefilter_409/rerun.R` | S |
| 65 | rerun.R:4-7 (header) | "Changes from the original: …" | same diff: omits array digests and load stamp | W (F13) |
| 66 | README:36 | each group four times b1 a1 a2 b2 | design; SETN pending (stated at README:3) | S |
| 67 | README:55-60 | two refusals and one hand stop; SETN a2 after 72 min | status.txt (LSKE a2 exit 1, SETN a2 exit 1 waited 4320 s); input_counters.tsv (two launches with no stop row) | S |
| 68 | README:57-58 | SETN a2's lock holder was another session's #394 walks in zz394_* | progress.md:16 only; refusal log names no holder | S (PWF record) |
| 69 | README:62-65 | LSKE a2 refusal log overwritten; SETN's kept as refused1; driver now keeps earlier logs | tree: refused1 present; rerun_SETN_a2.log is a duplicate of it; the *running* driver is a frozen pre-df73195f copy without log keeping | W (F14) |
| 70 | README:74-75 | streams / barriers write counters did not move | input_counters.tsv: identical in all 12 rows across both windows covering every run | S |
| 71 | README:103-105 | walks are the whole gain; gate/mapping/setup vary as much within a version (LKEL mapping 4.4-7.3 under 0.46.0); first runs colder; SETN mapping 76 vs 47 one pair | steps_*: LKEL a 4.362/7.338, b1 11.98; SALR b1 7.74; SETN 75.96/47.38 | S |
| 72 | README:100-101, research footnote | SETN one run per version; another client by end of a1 | status.txt; steps_SETN_a1 others_end 1 | S |
| 73 | research:99-101, README "Not measured" | provincial share not measured; serial vs `-j8` | design | S |
| 74 | test-lnk_pipeline_access.R comment | without aoi each walk drives from every feature in the province | #261 record; fresh `aoi = NULL` path | S |
| 75 | test-lnk_preflight_fresh.R comment | a floor below the pin lets an older fresh pass; older fresh same answers, slower | preflight floor check; rc digests | S |

## Findings

- **[bug] NEWS.md:6 and CLAUDE.md:21 — "which is why small groups gain least" / "So … small groups gain least" is a stated cause the record contradicts.** (a) The group that gains least is SETN, the largest: total 1.66× against SALR's 1.80× (`summary_steps.csv`). (b) The ranking is not by size: LSKE (65,897 segments on the CH walk) gains 3.3× and CHWK (11,301) 9.2×; CHWK's gain is #261's per-feature probe cost, not size. (c) In SALR, the smallest, the per-call rise on the PSCIS, dam and anthropogenic walks totals 2.85 s of a 23.2 s run under 0.46.0 (12 %), while the steps fresh does not touch (gate, mapping code, setup, prior copy, guard, pipeline_access_other) are 13.6 s (59 %). So what keeps a small group's ratio low is the unchanged non-walk steps, which README:103 already says ("Walks are the whole gain"). Round 1 corrected the numbers in this sentence and round 2 the cause of the per-call cost; this clause is the same conclusion one step further on. Fix: drop the clause, or say small groups gain least because their non-walk steps do not change, and SETN least of all because its walks are output-bound.

- **[bug] data-raw/logs/prefilter_409/README.md:84-85 — "Both counts describe the 2026-10-23 build" is wrong for the remediation count.** `ties_remediations.sh` reads every `working_<wsg>.crossings` the dispatcher holds (138; 134 with rows). The dispatcher modelled 74 groups in the 2026-10-23 run (`data-raw/logs/provincial_361/buckets_default.md`, "dispatcher (m1) (74)"); the other groups' working schemas were on the cloud hosts, which were burned. `wsg_run_one.R:137` keeps working schemas (`cleanup_working = FALSE`), so at least 60 of the 134 are left from other builds, and nothing in the script checks a schema's vintage. The same scope is claimed at research/recompute_cost.md:58-59 ("neither set has a co-located pair on the 2026-10-23 build") and implied at NEWS.md:5 (the remediation clause sits in a sentence about the 2026-10-23 build). Also worth saying where it is stated: the recompute does not recompute `remediated_dnstr_ind` at all (`R/lnk_access.R` passes `crossings_table = NULL`, and the merge preserves the column, lines 30-31, 237-238), so the remediation tie question bears on the next model-time build, not on the recompute measured here. Fix: "in the 134 working schemas the dispatcher holds (mixed builds; at most 74 from 2026-10-23)".

- **[fragile] CLAUDE.md:21, README.md:106 and 113, research/recompute_cost.md:92-93 — "the natural walks gain 4.7× to 17×".** That range is of per-group sums of the natural walks' per-walk minima (LKEL 4.70, LSKE 4.90, SALR 5.22, CHWK 17.33; SETN 1.77), which no script prints; read per walk, as the sentence reads, the range is 3.85× (LKEL BT) to 18.45× (CHWK CO) (`summary_walks.csv`), so "every natural walk gained at least 4.7×" is false. Say "summed per group", or give the per-walk range.

- **[fragile] research/recompute_cost.md:66-67 — "Five groups' whole recompute, each run four times alternating".** SETN ran twice (b1, a1; `recompute/status.txt`). Its own footnote says so, so the sentence and the footnote disagree. "four times (SETN twice so far)".

- **[fragile] CLAUDE.md:21, NEWS.md:6, README.md:107-108, research/recompute_cost.md:94-95, RUNBOOK.md:598 — "where the walk returns little".** The walks the sentence then quantifies include SETN's dam walk, which returns 118,755 segments and 169,971 features and rose 3.5 s, and the anthropogenic walks (SETN 507,630 features) also rose in four groups of five. The measured set is "the PSCIS, dam and anthropogenic walks", whatever they return; the qualifier is a mechanism nobody measured (the cause is stated as unmeasured two sentences later). RUNBOOK's "a call that returns little costs … up to about 4 s in SETN" has the same problem.

- **[fragile] CLAUDE.md:22, README.md:78-81, research/recompute_cost.md:77-79 — the cause of CHWK's and SALR's order change.** The order changed only in CHWK and SALR walks run on the dispatcher; the explanation (co-located copies persisted once per group) rests on m4's 30-group copy, which holds neither CHWK nor SALR (read-only check on m4: `count(DISTINCT watershed_group_code) = 30`, `bool_or(… = 'CHWK')` and `'SALR'` both false). The count is accepted as labelled; the sentence should say the explanation is inferred from a copy that holds neither group (one of m4's 189 tie positions is within one group, so within-group ties are a second candidate).

- **[fragile] issue #411 — "about 4 to 8 s per group" has no producer, and the 9.5 s quoted beside it (also CLAUDE.md:25) is the 0.44.0 arm.** The measured step `lnk_access:setup_and_update` is 2.73-7.73 s under 0.46.0 (9.48 is SETN's 0.44.0 run), and it includes the merge `UPDATE`, the view-existence checks and the scratch column query, which removing the table does not remove; the table's own share is not measured. #411's opening line then promises "about 4 to 8 s per group" from dropping the table alone. Restate as "at most the 2.7 to 7.7 s step, which also holds the merge UPDATE; the table's own share is to be measured".

- **[fragile] RUNBOOK.md:1551 — "The recompute's cost is its downstream walks (#261)" in the present tense.** Under 0.46.0 the walks are 41 % (SALR 9.6 of 23.2 s), 53 % (LKEL), 60 % (CHWK), 66 % (LSKE) and 87 % (SETN) of the recompute (`summary_steps.csv`). "Was its downstream walks (#261); since v0.45.0 they are 41 to 87 % of it".

- **[fragile] research/recompute_cost.md:65 ("admits only the features `fwa_downstream()` can return"), RUNBOOK.md:1552 and CLAUDE.md:14 title and NEWS.md:3 ("admit only the features that can reach the group").** fresh's `.frs_walk_prefilter` admits every feature on any of the group's blue lines or on any ancestor-or-equal wscode: a necessary-condition superset (a feature on a group line above every group segment, or on an ancestor line above the confluence, passes the prefilter and is then dropped by `fwa_downstream()`). fresh's own NEWS words it correctly ("admits only the features that meet either criterion"), as do NEWS.md:3's second sentence and RUNBOOK.md:591-594. Outputs are unaffected; the wording matters to anyone sizing a walk by its admitted set (#394).

- **[fragile] README.md:12-13 — "Every group's newest `log` and `log_recompute` row is at `1d00c04c`."** The only producer is planning/active/progress.md:10, which says "all five groups"; `rerun.R` enforces `log_recompute` only, for the group it runs. Say "each of the five groups'".

- **[fragile] README.md:3 — "measured 2026-10-29 00:58 to 03:23 UTC".** `ties_natural.*` entered the record in df73195f (05:12 UTC) and the SETN a2 attempt ran at 04:36 UTC; neither is inside the window.

- **[fragile] research/recompute_cost.md:3-6 header — "Produced by … `data-raw/logs/prefilter_409/` …, on the 2026-10-23 `default` build".** Phase 3 (the model-time comparison) and `ties_natural` ran on m4's local fwapg, not on that build.

- **[fragile] data-raw/logs/prefilter_409/rerun.R:4-7 — the header's "Changes from the original" list** omits the per-walk array digests and the load stamp, both of which README:29-33 lists and the diff against `recompute_cost_261/rerun.R` shows.

- **[fragile] recompute/rerun_SETN_a2.log (committed) and the running driver.** `rerun_SETN_a2.log` is a byte-identical duplicate of `rerun_SETN_a2_refused1.log` (same size and mtime). The driver now waiting for SETN is a frozen copy taken at 04:44 UTC (`scratchpad/rerun_all_frozen.sh`), before df73195f, and has no log keeping: it will overwrite the duplicate, which is harmless, but it is not the committed `rerun_all.sh` that the README says produced the record (the difference is log handling only; say so when the pair lands). If instead the committed `rerun_all.sh` is relaunched with `RESUME=SETN:a2` while the duplicate exists, it renames it to `_refused2.log`: two files for one refusal, the "SETN refused twice" reading round 1 removed. Delete the duplicate (or name it in the README).

- **[fragile] CLAUDE.md:24 — "Autovacuum … and a session running walks back to back both leave quiet gaps of seconds".** No record shows autovacuum leaving gaps: LSKE a2 was refused under a driver that did not yet check locks (`status.txt`: "waited 0 s"), and the holder was read live once. Only the #394 session's gap (SETN a2, refused 3 s after the driver saw quiet) is evidenced. Drop "Autovacuum … and" from the gap clause, or say the five minutes was sized on the SETN case.

- **[fragile] data-raw/logs/prefilter_409/rerun_all.sh:331-338 — a `RESUME` value that matches no `<WSG>:<label>`** (a typo, or a group not in `"$@"`) skips every run and still writes `counters after` and `ALLDONE`: the driver reports completion having run nothing. One check after the loops (`[ -z "$RESUME" ] || { echo "RESUME $RESUME not found"; exit 2; }`) closes it. Low: a one-off driver, but its ALLDONE line is what a waiter keys on.

Code otherwise checked and clean: `rerun.R` (radix sort is locale-independent; the walk wrapper handles a 0-row walk; backups and the restore statement survive a moved digest; no top-level `on.exit`), `summary.R` (version-per-side assertion; `read.delim` on unquoted TSV with no quote characters), `compare.R` (provenance refuses on NA `link_dirty`; empty tables set to NA, not "identical"; digest orders unique per group), `ties_remediations.sh` (empty schema list fails closed; its WHERE matches `lnk_barriers_emit()`'s `barriers_remediations`), `model_run.sh`, and both tests (pass in a throwaway worktree, 0 failed, 0 skipped; the `aoi` test would fail on a walk without `aoi`).
