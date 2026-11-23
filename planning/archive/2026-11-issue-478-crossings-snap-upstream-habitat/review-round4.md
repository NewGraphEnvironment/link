# Code-check round 4 (#478): review of round 3's fixes, and the claim enumeration

Reviewed the frozen copy at `a3e38823` (`review-r4`), round 3's fixes `a5acaa56..a3e38823`, and every quantitative claim the branch adds or changes in the files named in the brief. Probes ran only in the review copy and on read-only queries of the local fwapg. The test file run and mutation used `zz_test*` schemas, and both were dropped.

## Checklist read

- code-check.md `## Mechanisms`: the prose of all fourteen H3s (the evidence tables were skipped). The ones that decided findings here: "A guard's scope, escape hatches, and remedies", "Verification that reads its own output", "Restore the bug and prove the guard fires", "One fact derived twice", "A guard that fails toward pass" ("Provenance, and repair").
- code-check-r.md: "Postgres row order is never fixed unless the query fixes it…" (the LATERAL's `ORDER BY … DESC, linear_feature_id LIMIT 1` ends on a unique key, so it passes), and "An `information_schema` lookup by the literal table name misses what Postgres resolves" (the `species` lookup takes a schema validated as lower case, so it passes; the `to` guard is a literal-text compare, finding 2).
- code-check-spatial.md: "FWA `upstream_route_measure` misses the next segment's start" (gaps and overlaps; the LATERAL's `[ds, us)` leaves a point in a gap with no segment, but 0 of ADMS's 3,615 and BULK's 5,577 crossings sit in one), and "A relation between FWA watershed codes is not a place".

## Round 3's fixes

- **The LATERAL in `lnk_agg_pts`** (R/lnk_aggregate.R:185-197) uses the same bounds as `frs_aggregate()`'s `ref` join (fresh 0.55.1: `p.m >= ref.ds AND p.m < ref.us`). So `ref_lfid` is always one of the `ref` rows, and `ref.linear_feature_id = p.ref_lfid` keeps exactly one of them. The order ends on `linear_feature_id`, which is deterministic. A point with no segment gets `ref_lfid` NULL, so no row joins and it reads zeros, as before.
  - **Mutation:** deleting `"ref.linear_feature_id = p.ref_lfid AND"` turns the overlap test red (test 5: 1 failed, 1 passed). Unmutated, the file passes 27 of 27.
  - **The live overlap points:** 3 points in ADMS and BULK sit in an overlap (crossings 1000100373 and 1000103592, and barrier 1000103592). All three have 0 km upstream in every species, which explains why `per_crossing.csv` and `distribution.csv` did not change when `parity.R` was rerun at `4717a77d`.
- **The barrier-pair join on the resolved codes** (lines 366-383) is equivalent to the old join wherever a point sits in one segment. In an overlap it now gives one row where the old join gave two, and the old `EXCEPT` removed the duplicate anyway. I found no defect.
- **The `to` guard** (lines 122-133) refuses an unqualified `to`, a `to` equal to the crossings or barriers table, and any `to` in `schema`. Its comment says more than it checks (finding 2).
- **The `table_out` guard in `lnk_points_snap()`** sits before the `DROP` and before any query, and both names must be `<schema>.<table>`, so `search_path` cannot alias them. I found no defect.

## Findings

- **[severity: fragile] research/crossing_snap.md:46**: "two segments added on one blue line" does not match the committed evidence.
  - `compare_bcfishpass.csv` gives LILL `streams` 2 before-only and 4 after-only rows, of which only 3 are unexplained. `unexplained_bcfishpass.csv` puts those 3 on blue line 356248078: segment 59 replaced by 59 and 64, so that line gains one segment.
  - The other before-only row and two after-only rows are "explained", meaning they sit on a moved pick's line. The scratch builds confirm it: blue line 356260867's segment `0` (1,247 m) is split at 666 m. That is PSCIS 63483's new pick (`picks_moved.csv`: `blk_after` 356260867, `drm_after` 666).
  - So the two added segments are on two blue lines: one on 356248078 (the freed modelled crossing) and one on 356260867 (63483's new pick). Some habitat, access and mapping-code rows sit on the second line too: `compare_bcfishpass.csv` gives after-only 2 against unexplained 1 for each habitat table.
  - **Rule:** code-check.md, "One fact derived twice". The sentence was written from the unexplained subset, not from the whole comparison.

- **[severity: fragile] R/lnk_aggregate.R:122-133**: the comment says `to` "must name a table outside everything this reads", but the guard compares literal text, and only against `crossings`, `barriers` and `schema`. `to` is dropped (line 254) before the `CREATE … AS SELECT … FROM crossings` that reads `crossings` again. Two inputs therefore drop a table the function still needs:
  - an unqualified `crossings` or `barriers` (allowed, since `.lnk_validate_identifier()` accepts one) that resolves through `search_path` to the same table as a qualified `to`, for example `crossings = "crossings"` with `to = "public.crossings"`;
  - a `to` naming one of the `whse_basemapping` tables it reads (`fwa_stream_networks_sp`, or the lake, manmade or wetland polygons).

  Neither is a likely call, so the realistic exposure is low. But the comment states a property the guard does not enforce. Either require `crossings` and `barriers` to be `<schema>.<table>` and compare resolved names (`to_regclass()`), or narrow the comment to what is checked.
  - **Rule:** code-check.md, "A guard's scope, escape hatches, and remedies"; code-check-r.md, "An `information_schema` lookup by the literal table name misses what Postgres resolves" (the guard compares the text passed, not what Postgres resolves).

- **[severity: fragile] data-raw/logs/crossings_upstream_478/defect.R:51**: `new_sha` is `git rev-parse HEAD` at the time `defect.R` runs, while the "new" numbers it stamps are read from `working_<wsg>.crossings_upstream_habitat`, which `parity.R` wrote, possibly at another commit. The committed CSVs agree today (`defect_*.csv` `new_sha` = `stamp.csv` `link_sha` = `4717a77d`), but only because both scripts ran at one commit. It also records no dirty flag for that side. Reading `link_sha` and `link_dirty` from `stamp.csv`, the producer's own record, would make the stamp true by construction. This is the mechanism round 3 named: a value written from a picture rather than read from the artifact.
  - **Rule:** code-check.md, "A guard that fails toward pass" ("Provenance, and repair": capture the stamp from the thing that produced the output).

- **[severity: fragile] claims with no committed producer** (from the enumeration below). Each one I could check against the scratch schemas or the database holds, but nothing in `data-raw/logs/` reproduces it:
  - research/crossing_snap.md:19 and :36: "50 dams tie: 49 on one stream, one across two" and "agrees with fwapg's rule on all 49 same-stream dam ties". I recomputed 50 and 49 from `cabd.dams` (nearest two candidates at equal distance within 65 m). No committed script counts them.
  - research/crossing_snap.md:35: "each had only that one candidate within 150 m". True in `zz478_before.pscis_stream_candidates`: all 8 dropped points have one candidate each, a 999 one. `counts.csv` cannot show it.
  - research/crossing_snap.md:64: live-test counts (3 skip, 3 pass; 7 pass, 1 skip; 4 fail). I reproduced the default case (3 skip, 3 pass). The trial and `LNK_FWAPG_CURRENT` cases were not rerun.
  - NEWS.md:10: "two reruns of `query_habitat_thresholds_obs.R` are byte-identical". No digest or log is committed.
  - research/bcfishpass_parity.md:52: "built at `2b12adf0`". True in `zz478_parity.log` (all 11 groups `2b12adf0`, clean). `run.sh` prints the SHA to stdout only, and `stamp.csv` records the aggregate's SHA, not the build's.
  - **Rule:** code-check.md, "Verification that reads its own output" ("Re-derive each published number from the artifact it names").

## Enumeration

Producer paths are relative to `data-raw/logs/` unless they start with `R/`. In the verdict column, "matches" means I recomputed the number from the producer named in the third column.

| # | file | claim | producer | verdict |
|---|---|---|---|---|
| 1 | NEWS 0.89.0 | 19,905 PSCIS assessments | snap_tie_478/before,after/counts.csv `pscis_rows` | matches |
| 2 | NEWS | 2,554 CABD dams | counts.csv `dams_rows` | matches |
| 3 | NEWS | 14 picks change: 11 placeholder (8 no pick, 3 to a real stream) and 3 move 1 m | summary.csv dropped 8, stream 3, measure 3; picks_moved.csv `wscode_before` 999 ×11 | matches |
| 4 | NEWS | 17,363 unchanged | summary.csv `same_pick` | matches |
| 5 | NEWS | 17 dams move, same stream, under 1 mm | summary.csv `dams_moved`; dams_moved.csv max \|Δdrm\| 4.9e-4 m; same blue line for 17 of 17 lfid pairs (DB) | matches (the same-stream part from the DB; dams_moved.csv has no blue line column) |
| 6 | NEWS, RUNBOOK | 7,892 km instead of 7.7 | snap_tie_478/claims.txt | matches |
| 7 | NEWS | ADMS CH spawning 774.5 against 1,349.5 | crossings_upstream_478/defect_adms.csv | matches |
| 8 | NEWS | BULK 4,201 against 22,996 | defect_bulk.csv (4,201.2 / 22,996.1) | matches |
| 9 | NEWS | run 148, `v0.7.15-51-g3bd2824c` | crossings_upstream_478/stamp.csv | matches |
| 10 | NEWS | 98 to 100 % of main-stem crossings within 0.1 km, every species and metric | distribution.csv min 97.98 % (BULK BT rearing), max 100 % | matches (rounds to 98) |
| 11 | NEWS | barrier status agrees on all 9,173 | crossings_parity_232/crossings_parity_summary.csv Σ`n_both` = Σ`n_status_agree` = 9,173 | matches |
| 12 | NEWS | two threshold reruns byte-identical | none | no committed producer |
| 13 | NEWS | PSCIS picks miss nowhere; barriers 22 → 14; upper locate 581 → 21 | snap_tie_478/sweep.csv | matches |
| 14 | RUNBOOK | 11 provincial PSCIS picks sat on a placeholder | before/counts.csv `picked_on_999` | matches |
| 15 | RUNBOOK | `.lnk_pscis_pick_order` ends on the five keys listed | R/lnk_pipeline_pscis_build.R:549-561 | matches |
| 16 | crossing_snap header | link `2b12adf0`, fresh 0.55.1 | after/counts.csv `src_sha`, `fresh` | matches |
| 17 | crossing_snap | 150 m, five candidates; dams within 65 m | R/lnk_pipeline_pscis_build.R; R/lnk_wsg_downstream_check.R:75-108 | matches |
| 18 | crossing_snap | Crescent Slough at 49.105 N 123.072 W, 15.4 m from the vertex, 17 m connector, codes `100.005065` / `100`, edge 1350 | none committed; DB: 15.38 m, 17.1 m, edge 1450 and 1350, codes as stated | no committed producer (holds) |
| 19 | crossing_snap | 16 segments (7.7 km) against 17,657 segments (7,892 km) | claims.txt | matches |
| 20 | crossing_snap | 49 same-stream dam ties agree with fwapg's rule | none | no committed producer |
| 21 | crossing_snap table | candidates 37,992 → 37,972; on a placeholder 20 → 0; picks 17,377 → 17,369; picks on a placeholder 11 → 0; ties 305 / 305; picks on a tied stream 33 / 33; dams 2,554 / 2,554 | counts.csv | matches |
| 22 | crossing_snap | 8 with no pick, each had only that one candidate | counts.csv shows 8 points lose every candidate; the "one" is not in it (zz478_before confirms) | no committed producer (holds) |
| 23 | crossing_snap | KHOR 807, GRAI 1467, LILL 63483 to a real stream; NASR 20, SHUL 3703, NIMP 101956 up 1 m | picks_moved.csv | matches |
| 24 | crossing_snap | distances equal within 1.6e-10 m | summary.csv `max_abs_dist_diff_m` 1.58e-10 | matches |
| 25 | crossing_snap | 17 dams change segment, same stream, under 1 mm | dams_moved.csv; DB for the blue line | matches |
| 26 | crossing_snap | 50 dams tie: 49 on one stream, 1 across two | none committed; recomputed 50 / 49 from cabd.dams | no committed producer (holds) |
| 27 | crossing_snap | groups holding a moved pick (10 listed) | picks_moved.csv `wsg_before` | matches |
| 28 | crossing_snap | groups holding a moved dam (13 listed) | dams_moved.csv lfids → FWA `watershed_group_code` (DB) | matches |
| 29 | crossing_snap | seven groups re-modelled; main `5be4fb32`, branch `2b12adf0` | builds_bcfishpass.csv | matches |
| 30 | crossing_snap | barriers: one row moves in each of GUIC, USHU, SHUL; KETL loses one; JERV loses 3; LILL loses 1, gains 1 | compare_bcfishpass.csv | matches |
| 31 | crossing_snap | segments move only in LILL: **two segments added on one blue line** | compare_bcfishpass.csv, unexplained_bcfishpass.csv | **does not match**: one segment added on each of 356248078 and 356260867 (finding 1) |
| 32 | crossing_snap | one segment's access and mapping code above it | unexplained_bcfishpass.csv (segment 113 on 356248078) | matches |
| 33 | crossing_snap | PSCIS 63445's fifth candidate tied across two streams at 91.7 m | zz478_before/after.pscis_streams_150m (91.736 m, blue lines 355999103 and 356361451) | no committed producer (holds) |
| 34 | crossing_snap | modelled crossing 10702238 alone at 64 m on 356248078 | unexplained_bcfishpass.csv (64.14); zz478_build_after barriers `1010702238` | matches |
| 35 | crossing_snap | every other moved row is on a moved pick's or dam's line | compare_builds.R `explain()` (on a moved line, or upstream of a moved position for non-segment tables) | matches as computed |
| 36 | crossing_snap | NASR 2.2 min in the provincial run | build_minutes.csv (2.19) | matches |
| 37 | crossing_snap | stalled 30 and then 17 min | stalled_before_default_NASR.log (15:54:03 → last sample 16:24:21); stalled2 (22:04:04 → 22:20:46) | matches |
| 38 | crossing_snap sweep table | 17,369 / 0 / 0; 20,006 / 22 (6 at a top) / 14 (0); 581 / 581 / 21; 0 errors | sweep.csv | matches |
| 39 | crossing_snap | 10 of 14 misses after are in FWA's gap | claims.txt `in_gap` 10, over the same md5 sample as sweep.R. They are misses after because the reworked `fwa_locatealong` needs closed 4-decimal bounds (fwapg `a8d00b97`), and all 10 also miss before (DB) | matches |
| 40 | crossing_snap | live tests 3 skip / 3 pass; 7 pass / 1 skip; 4 fail | none; the first reproduced here | no committed producer |
| 41 | parity | run 148, 2026-11-17 | stamp.csv | matches |
| 42 | parity | built at `2b12adf0` into `zz478_parity`, 11 groups | zz478_parity.log (DB); status_parity_bcfishpass.tsv lists the groups | groups match; the SHA has no committed producer (holds) |
| 43 | parity | 9,173 on both sides, all agree on status | crossings_parity_summary.csv | matches |
| 44 | parity | all but 4 on the same stream within 1 m | Σ`n_measure_within_1m` 9,169 | matches |
| 45 | parity | 27 on one side (19 link, 8 bcfishpass) | summary Σ`n_link_only` 19, Σ`n_bcfp_only` 8 | matches |
| 46 | parity | every CABD dam matches (42) | summary CABD 7 + 35 | matches |
| 47 | parity | modelled crossings: 15 link-only, 1 bcfishpass-only, 2 on another stream, 1 at 1.6 m | summary (2 + 13; 1; 3,537 − 3,535; 1.623) | matches |
| 48 | parity | PSCIS: 7 bcfishpass-only, 4 link-only, all BULK; pairs 198104/198113, 198105/198114; 123530/123529 20 m apart; 8733, 8745, 8758 2 to 6 m from link's modelled crossing; 8744 and 58123 unmatched; 199455 3 m | crossings_parity_rows.csv (5.6, 2.9 and 2.2 m; 991 against 1,011) | matches |
| 49 | parity | 9,145 crossings both hold | per_crossing.csv distinct (wsg, id) = 9,145 (3,608 + 5,537) | matches |
| 50 | parity | 98 to 100 % within 0.1 km; ADMS rounds to 100 % | distribution.csv min 97.98; ADMS min 99.61 | matches |
| 51 | parity | ADMS no crossing over 2.1 km apart, except SK spawning (12.8) and PK spawning (8.3) | distribution.csv ADMS `max_abs_diff_km` (CO spawning_below 2.038; SK 12.790 / 12.102; PK 8.318 / 8.320) | matches |
| 52 | parity | totals within 1.5 % except SK (ADMS 302.7 / 327.1; BULK 1,102 / 1,496, 5,100 / 4,662), ADMS PK 0 / 8.4, BULK CM 0 / 1.1 | distribution.csv, spawning and rearing rows (largest other: BULK CO spawning −1.42 %) | matches, read as the total metrics (the below-barrier rows are the next bullet) |
| 53 | parity | below runs higher in BULK, BT rearing 36,331 against 34,483 | distribution.csv (36,331.29 / 34,482.97) | matches (BULK ST spawning_below is 0.15 % lower; not a finding) |
| 54 | parity | defect ADMS 774.5 / 1,349.5, 827.5 / 1,562.3; BULK 4,201 / 22,996, 4,852 / 33,498 | defect_adms.csv, defect_bulk.csv | matches |
| 55 | parity | 0.13 min ADMS, 0.3 BULK; 3,615 and 5,577 crossings | stamp.csv `aggregate_minutes`; `n_link_crossings` 9,192 = 3,615 + 5,577; the split from defect_*.csv `n_crossings` | matches |
| 56 | parity | first version 15.4 and 91.5 min | `git show 4cf02d7a:…/stamp.csv` (15.42, 91.51) | matches |
| 57 | parity | 28,920 ADMS and 44,616 BULK rows | not kept (accepted), but 3,615 × 8 and 5,577 × 8 | accepted |
| 58 | R/lnk_aggregate.R roxygen | `fwa_upstream(..., TRUE, 1)`, within 1 m; two barriers within 1 m ordered | R/lnk_aggregate.R:206-210, 378-383 | matches |
| 59 | R/lnk_points_snap.R roxygen | `num_features` default 1L, e.g. 5L; EPSG:3005 | function signature; fresh writes 3005 | matches (non-quantitative note below) |
| 60 | R/lnk_pipeline_pscis_build.R comments | tie keys and their order | `.lnk_pscis_pick_order` | matches |
| 61 | R/lnk_wsg_downstream_check.R | 65 m; tie order | R/lnk_wsg_downstream_check.R:93-104 | matches |
| 62 | CLAUDE.md | no new numbers | — | — |

## Notes, not findings

- R/lnk_points_snap.R roxygen says fresh's tie "goes to the segment with the higher `downstream_route_measure` (the one starting at that vertex)". That holds on one stream only. Across two streams the higher measure can be the other stream's top end: research/crossing_snap.md's Crescent Slough case, and LILL 63445's fifth candidate, which fresh's order moved. This is not quantitative, and the cross-stream behaviour is accepted, but the parenthetical overstates it.
- Public-repo check: the lines this branch adds outside `planning/` and `CLAUDE.md` carry no host names, addresses, tunnel ports or private repo names.
