# Code-check round 3, #261 (measurement-only branch)

## Checklist read

Read the prose of all fourteen H3s under `## Mechanisms` in `code-check.md`. Three bear on this branch. "A guard's scope, escape hatches, and remedies" covers compression: a summary sentence that gains a quantifier, superlative or comparison is unsupported until it is run against each source. "The probe is broken before the world is" says to write the numbers last, against the final tree. "A proxy is not the property" covers the confounded comparison. I recomputed everything below from the committed TSV/JSON, with no database: plan JSON parsed in Python, and `correlations.R` re-run from a scratch copy (all three outputs byte-identical to the committed ones) plus extra probes. Code facts were checked in `R/lnk_pipeline_access.R`, `R/lnk_access.R`, `data-raw/wsg_recompute_one.R` and fresh's git history.

## Mechanism

Every one of the 13 earlier defects, and the new ones below, comes from one assumption. A sentence that compresses a measurement (it rounds, counts, ranks, says "every", "only" or "did not show", or sets two numbers side by side) gets treated as a rewording of a number already checked, when it is really a new claim about a population or a set of conditions. So it gets checked against the member in view (LSKE's walks, the walks.tsv run, the files that have the column, the one script being edited) or against another surface's prose, and never against the whole set the words cover or against the committed artifact. Two consequences follow. Each surface drifts on its own, so a fix lands in one and not its siblings. And a comparison across runs or loads reads as a property of the groups.

## Enumeration

Verdicts: OK, WRONG (correct value given), UNSUPPORTED (no committed source), UNSUPPORTED-LIVE (rests on a live query that was not committed).

### data-raw/logs/recompute_cost_261/README.md

| location | claim | source checked | verdict |
|---|---|---|---|
| L3 | measured 20:32 to 23:27 UTC | walks.tsv first `measured_utc` 20:32:03Z; the last committed timestamp is walk_prefilter.tsv 22:39:33Z; rerun/predictors outputs carry no time | start OK; end UNSUPPORTED |
| L4 | PostgreSQL 17.5, `work_mem` 512 MB | none committed (consistent with plans: SETN CH sort 538,912 kB on Disk > 524,288 kB; SETN ST prefilter 447,257 kB in Memory) | UNSUPPORTED-LIVE |
| L5 | 2026-10-23 build, 241 groups | predictors.tsv 241 rows | OK |
| L6 | link `1d00c04c` / 0.68.0, fresh `e9793047` / 0.42.0 | CLAUDE.md 2026-10-23 status | OK |
| L7 | fresh 0.43.0 (`18d92ceb`) | fresh git: `18d92ce Stamp release date for v0.43.0` | OK |
| L8 | `frs_network_features()` unchanged since 0.29.0 | fresh `git log 18d92ceb -- R/frs_network_features.R`: last change f42e86a (v0.29.0) | OK |
| L8 | R 4.5.2 | none | UNSUPPORTED-LIVE |
| L13 | CHWK 15.56 min, SALR 0.72 | 20261023 log | OK |
| L14 | 9.26 and 0.51 at `-j4` on 2026-10-17 | 20261017 log | OK |
| L14 | 20× the time | 15.56 / 0.72 = 21.6× | OK (the issue's round figure; 21.6×) |
| L14 | 1.26× the segments | predictors.tsv 14,347 / 11,392 = 1.259 | OK |
| L22-23 | one walk per present species view, three sources | walks.R code; walks.tsv rows | OK |
| L23-24 | nine groups; #261's four (CHWK, SALR, LKEL, CHES) | walks.tsv; issue261 body table | OK |
| L24 | LFRA, SETN, LSKE are three of the five slowest | 1023 log top five: LFRA 22.76, FRCN 17.94, SETN 16.52, CHWK 15.56, LSKE 10.79 | OK |
| L24-25 | FRCN second slowest, not decomposed; CHWK fourth | same | OK |
| L25-26 | KOTR, SPAT near the median | median 2.655 min; KOTR 2.69 (rank 122/240), SPAT 2.63 (rank 120) | OK |
| L26-27 | tuple write counters 161,847,271 before and after | walks_run.log (both invocations) | OK |
| L30-33 | the prefilter is the blue lines plus ancestor-or-equal codes | walk_prefilter.R; plan inner Filter (criterion 1 / 2) | OK |
| L34-35 | SALR's lines in the TSV only; the log covers the other eight | walk_prefilter_run.log (no SALR) | OK |
| L36 | rerun from a worktree at `1d00c04c` | rerun.R guard (`log_recompute.link_sha` == HEAD) | OK |
| L37-39 | every written table digested and backed up | rerun.R; rerun_digest_*.tsv | OK |
| L41-43 | predictor by `fwa_downstream(…, true, 1)`; fixed 200,000-feature sample; `probe_us`, `probe_pre_us` | predictors.R | OK |
| L44 | `predictors_subset.tsv` is the nine-group check | 9 rows | OK |
| L48-49 | another session from 20:51 UTC | first `others_active` 1 at 20:51:31Z (LSKE co) | OK |
| L49 | "one backend" | walks.tsv LFRA st/anthropogenic/pscis/dams rows `others_active` = 2 (21:30:00–21:31:30Z); walk_prefilter.tsv SALR rb sent and both anthropogenic rows = 2 | WRONG (up to 2 other backends in walks.tsv and walk_prefilter.tsv) |
| L48 | "continuously" | walks.tsv 0 at 20:52:40Z (LSKE pk) and 20:59:19Z (SETN ch); walk_prefilter.tsv 0 on all 13 rows from 22:26:08Z to 22:39:33Z | WRONG |
| L49 | "Every row records `others_active`" | steps_*.tsv, rerun_walks_*.tsv and rerun_digest_*.tsv have no such column | WRONG (walks, walk_prefilter and predictors only) |
| L50 | LSKE CH-shaped walks 67.6–69.2 s alone, 68.0–70.1 s beside one | walks.tsv ch 67.577, cm 68.359, pk 69.198 (0); co 68.027, sk 70.061 (1) | OK |
| L51 | "so that load did not show" | walks.tsv `shared_read` 0 for every walk from 20:32:13 to 20:53:50 (SALR's first walk aside), then 222k–301k blocks per walk from LSKE st (20:54:46) on; SETN CH 157.3 s there (others 1, 296k reads) vs 101.0 s in walk_prefilter.tsv (others 0) | WRONG (true of LSKE's CH walks only; the rows from 20:54 on show it) |
| L51 | later scripts accept one other backend | walk_prefilter.R / predictors.R check `others() > 1` only at start; 3 walk_prefilter rows ran beside 2 | WRONG (undisclosed for walk_prefilter.R, as it is disclosed for predictors.R) |
| L51-52 | rerun.R refuses if another backend holds a lock in `fresh_default` | rerun.R `pg_locks` check (present at b2ee8609, the commit with the results) | OK |
| L52 | predictors.R checks only at its start | code | OK |
| L52-53 | the last 20 groups (UKEC to ZYMO, alphabetically last) | predictors.tsv: 20 rows with others > 1, range UKEC..ZYMO, 20 groups ≥ UKEC | OK |
| L53-54 | beside 6 or 8 other backends | 1 row at 6, 19 at 8 | OK |
| L54-55 | 2,760 of 33,517 predicted walk seconds | recomputed: 2,760 / 33,517 (241 groups) | OK |
| L55 | the correlations read the same without them | without them: walk_s_pred 0.982 / 0.970, features_inside 0.892, walks 0.858, segments 0.619, below_outlet −0.070 | OK |
| L63 | re-run total 46.3 / 617.6 s | steps_*.tsv total | OK |
| L64 | walks 28.2 / 589.4 s | `lnk_access:walks` | OK |
| L65 | setup and UPDATE 3.8 / 8.3 s | `setup_and_update` 3.832 / 8.301 | OK |
| L66 | habitat gate 2.8 / 8.0 s | 2.844 / 7.988 | OK |
| L67 | mapping code 7.2 / 7.5 s | 7.223 / 7.546 | OK |
| L68 | guard, prior copy, rest 3.7 / 4.1 s | 0.161+2.015+1.551 = 3.727; 0.522+1.453+2.131 = 4.106 | OK |
| L69 | digests unchanged, 4 / 10 tables | rerun_digest_*.tsv | OK |
| L71 | the steps sum to within 0.5 s of the wall clock | SALR 45.86 vs 46.30 (0.44); CHWK 617.29 vs 617.62 (0.33) | OK |
| L73 | the same CHWK CH walk took 80.3, 86.2 and 93.7 s | walks.tsv 80.317; rerun_walks 86.242; walk_prefilter sent 93.676 | OK |
| L78 | every walk has one plan | 78 sent plans: two signatures, differing only by the override anti-join subplan (natural views have it, sources do not) | OK |
| L79 | 7.24 M rows for CH and its six identical-before-overrides species | plan outer 7,240,975; six = CM, CO, GR, KO, PK, SK | OK |
| L79 | 3.48 M BT/DV/RB | BT 3,480,075, RB 3,475,677 (no DV walk measured) | OK |
| L80 | 5.36 M ST/WCT | ST 5,360,130, WCT 5,358,136 | OK |
| L80 | about 6 s per CH walk (outer) | outer Index Scan 5.55–8.40 s (≥ 7.2 s in SETN/LFRA, under load) | OK (approximate) |
| L81 | `BitmapOr` on `blue_line_key` and `wscode_ltree <@` | plan inner node | OK |
| L82-83 | over the same 7,240,975 features | both plans' outer rows | OK |
| L83 | inner 13.0 s SALR, 74.4 s CHWK | NL total − outer: 12.98, 74.43 | OK |
| L83 | 1.8 vs 10.3 µs, 5.7× | 1.79, 10.28; 74.43/12.98 = 5.73 | OK |
| L84 | LKEL 1.3, LSKE 8.4, SETN 19.7, LFRA 21.2 µs | 1.31, 8.42, 19.71, 21.18 | OK (SETN's and LFRA's rows ran with others_active 1 and ~300k shared reads, undisclosed) |
| L85-86 | SETN 4.83 M pairs, LFRA 1.17 M, both in 157 to 163 s | 4,829,028 / 157.26; 1,171,394 / 162.28 | OK |
| L86 | CHWK 162 k in 80 s, LKEL 98 k in 15 s | 161,974 / 80.32; 98,243 / 15.15 | OK |
| L86-87 | CHWK CH 4.1× SALR's (80.3 vs 19.6) | 4.098 | OK |
| L87-88 | eight natural views hold 4.5× the rows of SALR's two | 48,520,757 / 10,716,652 = 4.53 | OK |
| L88 | about 18×, the ratio of natural walks 545.7 vs 29.7 | 545.699 / 29.673 = 18.4 | OK |
| L91-92 | CHWK and LFRA codes `100` to `970.…` | range_hypothesis.tsv lo/hi | OK |
| L92 | range covers 7.17 M of 7.24 M | CHWK/LFRA CH in_range 7,174,041 | OK |
| L92 | SETN's covers 0.75 M | 748,128 | OK |
| L93 | SETN's walks the second dearest of the nine, after LFRA's | walks.tsv totals LFRA 1101.6, SETN 1052.1, CHWK 551.4 (SETN's rows contended); walk_prefilter.tsv sent, same four shapes, same load: LFRA 357.3, CHWK 219.0, SETN 211.6 | WRONG as stated (holds only in walks.tsv, where SETN ran under load and CHWK did not; the other committed run puts SETN third) |
| L99-107 | prefiltered table (nine rows of sent, prefiltered and ×) | walk_prefilter.tsv per-group sums, e.g. CHWK 219.013 / 8.885 = 24.65; SETN 211.582 / 178.371 = 1.19 | OK (all nine) |
| L109 | one walk per barrier-set shape plus anthropogenic | walk_prefilter.R `shapes` | OK |
| L109 | all 32 walks return the same features per segment | d_set and segments_out equal in 32 / 32 pairs | OK |
| L110 | order differs in four (CHWK CH, BT, ST; CHES CH) | d_order differs in exactly those four | OK |
| L111 | `ORDER BY` (wscode, localcode, measure) ties | plan Sort Key `a.id_segment, b.wscode_ltree DESC, b.localcode_ltree DESC, b.downstream_route_measure DESC` | OK |
| L112 | link persists only `has_barriers_<sp>_dnstr` from the natural arrays | R/lnk_pipeline_access.R:240-262 | OK |
| L113 | anthropogenic arrays, whose first element `dam_dnstr_ind` reads, match in own order in all nine | lnk_pipeline_access.R:287-291 (`anth[1]`); d_order equal in all 9 | OK |
| L114 | SETN prefiltered CH keeps 140,159 features | prefilter plan outer rows 140,159 | OK |
| L115 | 139,882 inside the group | walks.tsv features_in_wsg | OK |
| L115 | about 34 segments each; 4.83 M pairs | 4,829,028 / 140,159 = 34.5 | OK |
| L115 | the sort spills 539 MB | plan 538,912 kB on Disk; Postgres kB are 1,024 B, so 552 MB (526 MiB) | WRONG (minor unit: 538,912 kB) |
| L119-126 | correlation table, all twelve figures | correlations.tsv m1023 rows | OK |
| L119 | 240 groups | n = 240 | OK |
| L128 | slope 1.00 over the nine | lm(walk_s ~ walk_s_pred) 1.004; log-log 1.011 | OK |
| L129 | 2026-10-17: 0.981, 0.871, 0.857, 0.589, −0.100 | correlations.tsv m1017 | OK |
| L130 | seven of nine have no natural barrier and no crossing below the outlet | predictors_subset.tsv: features_below_outlet 0 in 7 (KOTR 16, SPAT 23) | OK |
| L132 | 50,352 s of summed job time | pool.tsv job_s | OK |
| L132 | span 110 min at `-j8` | loadall_260/span.tsv 110.3 | OK |
| L133 | predicted walks 33,398 s | pool.tsv | OK |
| L134 | 7,864 s calibrated | pool.tsv walk_pre_s_cal | OK |
| L134-135 | 15,177 s (the sample's estimate) | pool.tsv; it is `sum(pmin(upper, pred))`: capped at the sent walk in 5 groups (EUCL, MMUS, TAHS, UCHR, UKEC); uncapped 15,245 | OK value; the cap is undisclosed (finding) |
| L135-136 | overstates except where output-bound; SETN 560 vs 539 | upper/measured: eight groups 0.065–0.79; SETN 560.1 (shape times × walks) vs 538.9 | OK |
| L136 | saving 18,221 to 25,534 s | pool.tsv | OK |
| L136 | 36 to 51 % | 36.2 %, 50.7 % | OK |
| L136-137 | below zero for 34 groups | recomputed 34 of 240 | OK |
| L137 | floored at 5 % (46 groups) | 46 | OK; the ceiling (`pmin(..., walk_s_pred)`, 1 group: UKEC) is undisclosed |
| L138 | floor 0 to 20 % gives 7,769 to 9,128 s | 7,769 / 9,128 | OK |
| L138 | CHWK is 934 s of the pool | pool.tsv chwk_job_s | OK |
| L138-139 | ten costliest hold 17.8 % | top10_walk_share 0.178 | OK |
| L143-144 | every group pays the province-wide probe | all 78 plans drive from a province-wide Index Scan | OK |
| L145-146 | fresh issue drafted, not filed; no link code changed | branch3.diff file list (no `R/`, no DESCRIPTION) | OK |
| L150-151 | #326 roughly halves segments | CLAUDE.md #326: `default` segments drop 2.1–2.7-fold | OK (approximate) |

### research/recompute_cost.md

| location | claim | source checked | verdict |
|---|---|---|---|
| L10 | 95 % of CHWK's re-run (589 of 618 s) | 589.352 / 617.623 = 95.4 % | OK |
| L10-11 | 61 % of SALR's (28 of 46 s) | 28.237 / 46.299 = 61.0 % | OK |
| L11 | one walk per present species view plus three sources | walks.R / lnk_pipeline_access.R | OK |
| L12 | 240 groups, Spearman 0.982 vs 0.993 | correlations.tsv | OK |
| L15-16 | correlate at −0.08 | −0.083 | OK |
| L16 | seven of nine have none | predictors_subset.tsv | OK |
| L21 | 7.24 M rows for CH | plans | OK |
| L22-23 | `BitmapOr` probe, once per feature | inner loops = outer rows | OK |
| L25 | about 6 s for a CH-sized view, the same in every group | outer scan 5.55–8.40 s | UNSUPPORTED as "the same" (a 1.5× range, highest in the loaded rows) |
| L27-28 | 1.8 SALR, 10.3 CHWK, up to 21 µs in LFRA | 1.79, 10.28, 21.18 (CH plans max) | OK |
| L29-31 | highest in groups owning main-stem segments (Fraser `100`, lower Skeena `400`) and with coastal codes | of the nine, the top four are LFRA, SETN, CHWK (lo `100`), LSKE (lo `400`); across 241 (predictors.tsv probe_us) the top seven have lo `100`, but LSKE is 19th and MFRA (4.1), HARR (4.6), TABR (4.6) also hold `100` | OK for the nine |
| L31-32 | SETN's range narrow and its probe among the dearest | 0.75 M; 19.7 µs (2nd of nine); predictors 20.2 (2nd of 241) | OK |
| L33-34 | SETN 4.83 M pairs, 539 MB sort spill | 4,829,028; 538,912 kB | pairs OK; spill WRONG-minor (552 MB / 526 MiB) |
| L36 | 18× (546 vs 30 s) | 18.4 | OK |
| L36-37 | 4.1× per CH walk, probes 5.7×, 4.5× rows | as README | OK |
| L42-43 | prefilter = blue lines + ancestor-or-equal codes | walk_prefilter.R | OK |
| L43-44 | index lookups: wscode GiST, blue line btree | prefilter plans: `barriers_wscode_gist_idx`, `barriers_blk_drm_idx` | OK |
| L44-45 | nine groups, same features in all 32 walks | walk_prefilter.tsv | OK |
| L45-46 | in eight, 3.6× (SPAT) to 24.6× (CHWK) | walk_prefilter.tsv | OK |
| L46 | SETN only 1.2× | 1.19 | OK |
| L47-48 | 50,352 s pool; 18,221 to 25,534 s; 36 to 51 % | pool.tsv | OK |
| L48 | the saving is spread over every group | UKEC's calibrated estimate is capped at its sent walk (saving 0); the sample estimate gives 0 for EUCL, MMUS, TAHS, UCHR, UKEC | WRONG (minor: every group but one by the calibrated estimate, and every group but five by the sample's) |
| L48 | CHWK is 1.9 % of the pool | 934 / 50,352 = 1.85 % | OK |
| L50-51 | link keeps only whether a natural array is empty | lnk_pipeline_access.R:240-262 | OK |
| L51-52 | CH, CM, CO, GR, KO, PK, SK identical before overrides | range_hypothesis.tsv in_range equal across the seven in every group | OK |
| L54-55 | `ORDER BY` has no unique tiebreak | plan Sort Key | OK |
| L55-56 | link reads only the anthropogenic array's first element; matched in all nine | lnk_pipeline_access.R:287-291; d_order | OK (dams arrays are read as sets, so their order is unused) |

### CLAUDE.md, "Status (2026-10-27, late)", lines 14-25

| location | claim | source checked | verdict |
|---|---|---|---|
| L16 | Spearman −0.08 over 240 groups | correlations.tsv | OK |
| L16 | 7.24 M rows for CH | plans | OK |
| L16 | probes once per feature through its wscode GiST | plan: the BitmapOr probes the btree too; the GiST arm takes 0.009 ms of the 0.010 ms loop | OK |
| L16 | 10.3 vs 1.8 µs; 4.1×; 4.5×; 18× | plans / walks.tsv | OK |
| L16 | 0.982 vs 0.993 | correlations.tsv | OK |
| L16 | no link code changed | branch3.diff | OK |
| L19 | CHWK 617.6 / 589.4, SALR 46.3 / 28.2 | steps_*.tsv | OK |
| L19 | gate and mapping code under 16 s in both | CHWK 7.988 + 7.546 = 15.53; SALR 10.07 | OK |
| L19 | both re-runs digest identical | rerun_digest_*.tsv | OK |
| L20 | prefiltered walk returns the same features | walk_prefilter.tsv | OK |
| L20 | `IN (SELECT ...)` still reads the whole table | planning/active/findings.md prose only (SALR CH 6.1 s); no plan or log committed | UNSUPPORTED |
| L20 | 32 of 32; 3.6× to 24.6× in eight groups; 1.2× in SETN | walk_prefilter.tsv | OK |
| L20 | 36 to 51 %; CHWK 1.9 % | pool.tsv | OK |
| L21 | 4.83 M pairs, 539 MB sort spill, 1.2× | plans; walk_prefilter.tsv | pairs OK; spill WRONG-minor (538,912 kB) |
| L21 | link keeps only `has_barriers_<sp>_dnstr` | code | OK |
| L22 | ties; link reads only the first anthropogenic element; matched in all nine | sort key; code; d_order | OK |
| L23 | CHWK and LFRA hold `970.…` beside the Fraser main stem | range_hypothesis.tsv | OK |
| L23 | SETN's code range narrow | 0.75 M | OK |
| L23 | SETN's walks cost twice CHWK's | walks.tsv 1052.1 / 551.4 = 1.91, but SETN's rows ran with others_active 1 and ~296k shared reads per walk, CHWK's with 0 and 0; walk_prefilter.tsv sent, same load, same four shapes: SETN 211.6 vs CHWK 219.0 (0.97×) | WRONG (a cross-load comparison; the like-for-like committed run gives about 1×) |
| L24 | owed items | — | OK |

### Comment lines of the scripts

| location | claim | source checked | verdict |
|---|---|---|---|
| walks.R:5-8 | mirrors lnk_access: same indexes and ANALYZE; one call per present species and per source | R/lnk_access.R:170-180 (same four indexes, ANALYZE) | OK |
| walks.R:9-11 | SQL captured by mocking; nothing written; counters compared | code; walks_run.log | OK |
| walks.R:69-70 | the largest join node's rows × loops are the pairs | code | OK |
| walks.R:96-97 | the read-only guard was added after the run | accepted | OK |
| walk_prefilter.R:9-11 | `fwa_downstream()` admits no other feature (criterion 1 / 2) | plan inner Filter | OK |
| walk_prefilter.R:14-15 | one view per shape plus anthropogenic | code | OK |
| walk_prefilter.R:39-41 | one other backend tolerated; LSKE 67.6–69.2 / 68.0–70.1 s | numbers OK; the check runs at start only, and 3 SALR rows ran beside 2 | OK numbers; tolerance claim WRONG (see L51) |
| rerun.R:5-8 | runs what wsg_recompute_one.R runs; writes no log row | wsg_recompute_one.R:160-203 (prior copy, lnk_access, gate, mapping persist, guard) and its `.rc_*` log calls, which rerun.R lacks | OK |
| rerun.R:10-15 | guarded, digested, backed up; backups dropped only when every digest matches | code | OK |
| rerun.R:39-40 | a write needs nobody else; timing tolerates one other backend | code | OK |
| rerun.R:74-76 | lock check in place for the 2026-10-27 runs | git: `pg_locks` present at b2ee8609, the commit with steps_*.tsv | OK |
| predictors.R:5-17 | predictor definitions | code | OK |
| predictors.R:18-23 | deterministic md5-ordered 200,000 sample; no index, so the plan drives from it | sample: code OK; "plan drives from it": no probe plan committed | UNSUPPORTED (last clause) |
| predictors.R:23 | walks.R found the per-feature probe is what differs | plans | OK |
| predictors.R:24-26 | same features per segment in every group tried | walk_prefilter.tsv | OK |
| predictors.R:28-30 | the anti-join removes about 1,800 of 7.24 M rows for CH | CHWK plan Rows Removed by Filter 1,757; outer_rows_natural CHWK − LKEL vs walked rows gives 1,757 | OK |
| predictors.R:49 | one other backend tolerated | start-only check; 20 rows ran beside 6–8 (disclosed in README) | OK (disclosed) |
| predictors.R:61-62 | a code range is two index lookups | code | OK |
| correlations.R:5-7 | inputs; 2026-10-23 `-j8`, 2026-10-17 `-j4` | code | OK |
| correlations.R:28 | sources take at most 11.5 s a group | LFRA 11.49 | OK |
| correlations.R:29 | slope 1.00 over the nine | 1.004 | OK |
| correlations.R:31-32 | the sample overstates except output-bound SETN (539, measured 560) | 538.9 vs 560.1; other eight 0.065–0.79 | OK |
| correlations.R:36-37 | each shape's measured prefilter time given to every walk of that shape | code | OK |
| correlations.R:51-52 | floored at 5 %; below zero in 34 of 240; floors 0–20 % move the total by −95 to +1,264 s | 34; 7,769 − 7,864 = −95; 9,128 − 7,864 = +1,264 | OK (the ceiling on the next line is not mentioned) |
| correlations.R:78, 89-91 | misses / pool definitions | code | OK |
| range_hypothesis.sql:1-3 | SETN range 0.75 M | 748,128 | OK |
| range_hypothesis.sql:2-3 | SETN walks about twice as long as CHWK | walks.tsv 1.91× (contended SETN vs quiet CHWK); walk_prefilter sent 0.97× | WRONG (same as CLAUDE.md L23) |
| range_hypothesis.sql:3 | CHWK range 7.2 M, codes 100 to 970 | 7,174,041; lo 100, hi 970.… | OK |
| range_hypothesis.sql:3-4 | LFRA (7.2 M) only a little longer than SETN | 1101.6 vs 1052.1 s | OK |

### issue261_body.md: Verdict and Acceptance

| location | claim | source checked | verdict |
|---|---|---|---|
| Verdict b1 | −0.08 over 240; segments 0.61 | correlations.tsv | OK |
| Verdict b1 | seven of nine, CHWK and SALR among them | predictors_subset.tsv | OK |
| Verdict b2 | 617.6 / 589.4; 46.3 / 28.2; digests unchanged | steps / digest TSVs | OK |
| Verdict b3 | 7.24 M; 10.3 vs 1.8; 4.1×; 4.5×; 18× the ratio of measured natural walks | plans / walks.tsv | OK |
| Verdict b3 | 0.982, ceiling 0.993 | correlations.tsv | OK |
| Verdict b4 | 32 of 32; 3.6× to 24.6× (SETN 1.2×) | walk_prefilter.tsv | OK |
| Verdict b4 | 36 to 51 % | pool.tsv | OK |
| Verdict b4 | the pool is throughput-bound | loadall_260: span 110.3 vs summed work / 8 104.6 | OK |
| Acceptance 1-2 [x] | count correlated beside segments; refuted before optimising | correlations.tsv | OK |
| Acceptance 3 [ ] | left unchecked with a note | — | OK |

### issue377_body.md: two lines

| location | claim | source checked | verdict |
|---|---|---|---|
| #261 line | 20× | 21.6× | OK (the issue's figure) |
| #261 line | 110.3 min span, 104.6 min of work over 8 slots, longest 22.75 min | loadall_260/span.tsv, shares.txt | OK |
| #261 line | CHWK about 1.9 min of it | 15.56 / 8 = 1.95 | OK |
| #261 line | −0.08 over 240; 7.24 M; 10.3 vs 1.8; 0.982 / 0.993 | as above | OK |
| #261 line | walks are about two thirds of the pool's summed work | 33,398 / 50,352 = 66 %, but that sets single-walk seconds against job seconds run eight at once (the README's own caveat, L133, is dropped here) | UNSUPPORTED as stated |
| #261 line | 32 of 32; 3.6×–24.6× in eight groups, 1.2× SETN; 36 to 51 % | as above | OK |
| fresh line | 36 to 51 %, SETN 1.2× | as above | OK |

### pr_body.md

| location | claim | source checked | verdict |
|---|---|---|---|
| L1 | no code under `R/`, no version bump | branch3.diff files | OK |
| Verdict p1 | −0.08 over 240; seven of nine have none | as above | OK |
| Verdict p2 | 617.6 / 589.4; 46.3 / 28.2; 7.24 M; 10.3 vs 1.8; 4.1×; 4.5×; 18×; 0.982 / 0.993 | as above | OK |
| Verdict p3 | 32 of 32; 3.6×–24.6× (SETN 1.2×); 36 to 51 % | as above | OK |
| Verdict p3 | spread over every group (CHWK is 1.9 %) | see research L48 | WRONG (minor, as research L48); 1.9 % OK |
| What is here | predictors over 241 groups; row in research/README.md | predictors.tsv; branch3.diff | OK |

### draft_fresh_issue.md

| location | claim | source checked | verdict |
|---|---|---|---|
| p1 | fresh@v0.43.0; SQL unchanged since v0.29.0 | fresh git history | OK |
| p1 | 7.24 M probes per call, whatever the AOI | true of the CH view only: BT 3.48 M, ST 5.36 M, anthropogenic 0.50 M, PSCIS 10,121, dams 2,442 | WRONG (minor: probes per call = the feature table's rows; 7.24 M for the CH-sized table) |
| p1 | 1.8 SALR, 10.3 CHWK, 21 µs LFRA; main-stem groups among the dearest | plans | OK |
| p2 | most of the recompute; Spearman 0.982 | steps (95 %, 61 %); correlations.tsv | OK |
| p3 | criterion 1 / criterion 2 | plan Filter | OK |
| p3 | the feature table's own indexes (GiST on wscode, btree on blue line) | prefilter plans | OK |
| p4 | nine groups and 32 walks, the same features in every one | walk_prefilter.tsv | OK |
| p4 | 3.6× (SPAT) to 24.6× (CHWK, 219 s → 8.9 s) | 219.013 → 8.885 | OK |
| p4 | SETN 1.2×, 4.83 M pairs | as above | OK |
| p4 | 36 to 51 % | pool.tsv | OK |
| p5 | `IN (SELECT …)` reads the whole table (SALR CH 6.1 s vs 2.9 s) | 2.9 = walk_prefilter 2.89; 6.1 s and "reads the whole table" are in findings.md prose only | UNSUPPORTED (6.1 s and the full-read claim) |
| b1 | `ORDER BY` (wscode, localcode, measure, all descending) ties | plan Sort Key | OK |
| b1 | four of 32 walks changed order | d_order | OK |
| b2 | for upstream, the same cut is less selective; not measured | nothing | UNSUPPORTED (an unmeasured claim stated as fact) |

## Findings

- **[medium] data-raw/logs/recompute_cost_261/README.md:48-52.** The contention paragraph is contradicted by the rows it cites.
  - "One backend": four walks.tsv rows (LFRA st, anthropogenic, pscis, dams) and three walk_prefilter.tsv rows (SALR) record `others_active` = 2.
  - "Continuously": rows record 0 at 20:52:40Z and 20:59:19Z, and on all 13 walk_prefilter rows from 22:26:08Z.
  - "Every row records `others_active`": the rerun outputs have no such column.
  - "So that load did not show": this generalises from LSKE's CH walks, which ran before the cache moved. From LSKE st (20:54:46Z) on, every walk reads 222k–301k shared blocks, against 0 before. SETN's CH walk took 157.3 s in walks.tsv (others 1) against 101.0 s in walk_prefilter.tsv (others 0).
  - "Later scripts accept one other backend": walk_prefilter.R checks only at start, which the paragraph discloses for predictors.R only.
- **[medium] SETN against CHWK across loads.** Affects CLAUDE.md:23 ("SETN's … walks cost twice CHWK's"), README.md:93 ("SETN's walks are the second dearest of the nine, after LFRA's") and range_hypothesis.sql:2-3 ("about twice as long as CHWK"). All three rest on walks.tsv, where every SETN walk but CH ran beside another backend with ~296k shared reads, and every CHWK walk ran alone with none. The like-for-like committed run (walk_prefilter.tsv sent, same load, the same four shapes) gives SETN 211.6 s against CHWK 219.0 s (0.97×), and puts SETN third. The refutation of the code-range idea does not need "twice": SETN's range is 0.75 M against CHWK's 7.17 M, and predictors.tsv's probe (both at others 1) still has SETN at 20.2 µs against 14.1. So qualify the comparison or take it from one run. The SETN (19.7 µs) and LFRA (21.2 µs) per-feature figures (README:84, research:28) come from the same loaded rows, undisclosed.
- **[low] README.md:115, research/recompute_cost.md:34, CLAUDE.md:21: "539 MB".** The plan reports 538,912 kB, and Postgres kB are 1,024 bytes, so the spill is 552 MB (526 MiB).
- **[low] research/recompute_cost.md:48 and pr_body.md: "the saving is spread over every group".** correlations.R:53 caps the calibrated estimate at the sent walk, giving UKEC a saving of 0. The sample estimate (pool.tsv:134 via `pmin`) gives 0 for EUCL, MMUS, TAHS, UCHR and UKEC. The README discloses the 5 % floor but neither ceiling: 1 group calibrated, and 5 sampled, where 15,177 is 15,245 uncapped. UKEC is also one of the 20 contended predictor rows.
- **[low] issue377_body.md #261 line: "walks are about two thirds of the pool's summed work".** That sets single-walk seconds (33,398) against job seconds run eight at once (50,352). The README states the caveat (L133). This line drops it.
- **[low] draft_fresh_issue.md p1: "7.24 M probes per call, whatever the AOI".** Probes per call equal the walked table's rows, which is 7.24 M only for the CH-sized view: BT 3.48 M, ST 5.36 M, anthropogenic 0.50 M.
- **[low] draft_fresh_issue.md p5, CLAUDE.md:20: `IN (SELECT …)` "still reads the whole table (SALR CH 6.1 s)".** The only source is planning/active/findings.md prose. No plan or log of that attempt is committed. Commit its plan, or say it is from a discarded attempt.
- **[low] draft_fresh_issue.md b2: "the same cut by descendants is less selective".** This is stated as fact beside "not measured". Word it as an expectation.
- **[low] research/recompute_cost.md:25: "about 6 s …, the same in every group".** The outer scan runs 5.55–8.40 s across the nine. It is highest in SETN and LFRA, the loaded rows.
- **[low] predictors.R:21-22: "The sample has no index, so the plan drives from it".** No probe plan is committed, so the claim is unexecuted.
- **[low, latent bug] correlations.R:46.** `aggregate(cbind(walk_s = exec_s, pre_s) ~ wsg, w, sum)` uses the formula method's default `na.action = na.omit`. A natural walk whose shape has no prefilter row (`pre_s` NA, or a species missing from `shape`, such as CT) would be dropped from `walk_s` as well, silently shrinking the calibration's measured walk. There is no effect today: `meas$walk_s` equals walks.tsv's natural sums in all nine groups (CHWK 545.699, SETN 1042.543, …). `stopifnot(!anyNA(w$pre_s))` before the aggregate would make that hold by assertion.
- **[low, method] walks.R, walk_prefilter.R, predictors.R.** `others_active` is sampled once, after each statement finishes, so "beside one" describes the end snapshot, not the walk's duration. That is why the 20:51 onset first shows in a row that ended at 20:51:31. Say so where rows are read as contended or quiet.

No bug in the scripts changes a committed number: `correlations.R` reproduces correlations.tsv, pool.tsv and misses.tsv byte for byte, and every plan-derived figure recomputes.
