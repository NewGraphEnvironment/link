# Code-check round 3 (#362), branch diff cefd4608...HEAD

## Checklist read

- `code-check.md`: `## Mechanisms`, the prose of all fourteen H3s, read in full (`|` table rows and
  evidence blocks skipped). "Rules that stand alone", Security, Spreadsheets: headings only.
- `code-check-r.md`: read in full: "Postgres row order is never fixed…", "A database driver's value
  is not a base R type", "`paste()` with a zero-length argument…", "`sprintf("%g", x)` writes `Inf`
  and `NA`…", "An `information_schema` lookup…". The rest (about 125 headings) by heading only.
- `code-check-shell.md`, `code-check-spatial.md`: index only. The diff has no shell or spatial code.

## The mechanism behind rounds 1-3

**A claim's population was taken from the instrument in hand, not from the set the sentence
names.** The instruments were the four scored groups that `moves.R` queries, totals rounded to
0.1 km, the `streams` row count, the compare's `total_segs`, and the list of commits between the
builds. Each answers a narrower question than the sentence built on it, and no claim was checked
by listing the set it names. Rounds 1-2 found instances of this: a rounding artefact read as a
move, "0 km" read as exceeded, an unscoped "8 lines", "the gate is km-neutral", a line total
summed over four lines. This round finds three more:

- "the other seven" comes from assuming that the compare's 10 groups contain the 3 groups
  `moves.R` measured.
- 91a968ab is named as a cause because it is in the commit list. Nobody checked whether its branch
  fires on this data.
- #277 gives the reach of the bug by row count, a proxy that misses three groups.

I measured the whole set directly (all 17 groups, read-only): **349 segments on 75 lines in 12 of
the 17 groups exist in one build only.** The groups are ADMS 19 / 4 lines, BABR 4 / 1, BULK 10 / 2,
BULL 63 / 13, ELKR 10 / 2, HARR 62 / 14, KISP 13 / 3, KLUM 4 / 1, KOTL 41 / 8, LARL 35 / 8,
LFRA 49 / 11 and LSKE 39 / 8. The four scored groups hold 39 / 8 of these.

## Findings

- **[claim]** `research/bcfishpass_parity.md:91-93` ("in 10 of the 17 groups; the tie above in the
  three scored groups that have one, the other seven not examined"). Of the 10 groups where
  `total_segs` differs (`mapping_code_moves.csv`: ADMS, BABR, BULL, ELKR, HARR, KISP, KLUM, LARL,
  LFRA, LSKE), only **two** are scored groups, ADMS and ELKR. BULK resegments on 2 lines and its
  `total_segs` is unchanged (42,940 both builds). So 8 of the 10 were not examined, not 7. The
  compare's count also misses KOTL, which resegments on 8 lines. Correct wording: "in 10 of the 17
  groups (ADMS and ELKR among the scored; the other eight not examined)", or cite the direct count
  above (12 groups).

- **[claim]** `research/bcfishpass_parity.md:89-90` ("Three things move it at once: the gate,
  91a968ab's `has_barriers_<sp>_dnstr` for a present species with no barrier…, and breaks").
  `planning/active/findings.md:72` and `moves.R:153-154` say the same ("confounded by 91a968ab").
  91a968ab changes only the branch where `nrow(dnstr_per_sp[[sp]]) == 0`
  (`R/lnk_pipeline_access.R:244`). That branch gives every segment of the group NA, so
  `mapping_code_<sp>` is `""` on every segment. Two checks show it does not fire on any of the 86
  compared rows:
  - each of the 86 (group, species) rows has barrier rows in `fresh_parity362.barriers_<sp>_access`;
  - none of the 86 has an all-empty `mapping_code_<sp>` in `fresh_parity246.streams_mapping_code`.
    The groups that are all-empty there (CM, PK, WCT, …) are exactly the absent species the compare
    leaves out.

  Two causes are measured. The gate moves token 1 (`SPAWN` / `REAR` emit without an access test,
  `R/lnk_pipeline_mapping_code.R:263-268`). Breaks move it as above. 91a968ab is a candidate taken
  from the commit list, never measured, and the data rules it out. Drop it, or say it cannot apply
  here.

- **[claim]** #277 body, "Measured 2026-10-20" ("The `streams` row counts also differ in BULL, KISP,
  KOTL, LARL, LFRA and LSKE, which were not examined"). `findings.md:68-69` says the same. The
  sentence is true as written. But this is the reproducibility issue, so the extent is what a reader
  wants from it, and the row count hides three groups that resegment at an unchanged count: BABR (1
  line), HARR (14 lines, the largest after BULL) and KLUM (1). By direct measure, 9 unexamined groups
  hold 310 segments on 67 lines. Give the direct count, or say that the row count is a lower bound.

- **[claim]** `data-raw/logs/parity_0.66.6/README.md:31`: `resegmented.csv` is "breaks at modelled
  crossings that moved (#277)". This is the mechanism round 2 rejected. No modelled crossing moved:
  `fresh.modelled_stream_crossings` has the same positions for both builds. On 7 lines the build
  kept the other crossing of a tied pair, and on the eighth (356271598) a break disappeared.
  `moves.R:15` ("a moved break") and `:46` ("a break that moved") are comments with the same
  wording. Suggested: "segments where the two builds broke a line differently (the PSCIS pick tie,
  #277)".

- **[fragile]** `data-raw/logs/parity_0.66.6/moves.R:157` vs `:168`. `segment_diff.csv` is written
  last, after the mapping-code compare reads `Sys.getenv("LNK_COMPARE_NEW")`. If that variable is
  unset, `read.csv("data-raw/logs/study_area_run/")` errors. By then `pair_moves.csv`,
  `resegmented*.csv` and `override_diff.csv` have already been rewritten, so the old
  `segment_diff.csv` and `mapping_code_moves.csv` are left beside the new files. The script fails
  loud, but the directory then holds outputs from two runs. Check `nzchar(Sys.getenv(...))` at the
  top, or write `segment_diff.csv` before the compare.

`moves.R` has no other defects: round 2's empty `IN ()` guard is in place, `%d` gets an int4
`blue_line_key`, the merges are checked by `nrow`, and the segment joins are unique per schema. It
is otherwise clean.

## Enumeration

Every quantified, numeric or causal claim in the named texts. ✓ means measured or traced to a
committed file this round, read-only.

### research/bcfishpass_parity.md

| Claim | Source | Verdict |
|---|---|---|
| Run `20261020_171738-477072be`, link 0.66.6 (`6e5cc837`) | `fresh_parity362.log` | ✓ (6e5cc837 is v0.66.6+7 commits; no `R/` change after the tag) |
| 48 of 50 pairs within tolerance | `parity_crosssection.log` | ✓ |
| tolerances: accessible 1 %, spawning / rearing 5 % | `parity_crosssection.log` summary | ✓ |
| two pairs over: BULK SK +10.99 % / +7.39 % | same | ✓ |
| parked under #130 (title), from fresh#190 | `gh issue view 130` | ✓ |
| accessible within 0.07 % on all 17 pairs | log: max 0.07 %, 17/17 | ✓ |
| table: all 50 cells (link / bcfp, diff %, brackets) | `pair_moves.csv`, checked by script | ✓ 50/50 |
| a bracket can read 0.1 for a 0.01 km move | ADMS SK −0.1 from 0.011 km | ✓ |
| rearing leaves lake connection lines out on both sides | `parity_crosssection.R` (#319) | ✓ |
| Pink has no freshwater rearing | PK in `species_spawn_only`, no rearing row | ✓ |
| five pairs left out: CM, PK in ADMS and BABL; CM in BULK | log "link-absent" list | ✓ |
| closure is 17 groups, verified | `verify.log` PASS, `expected_n=17` | ✓ |
| reference loaded 2026-10-17 00:55 UTC, `v0.7.15-50-g620dbe4`, run 143, completed 2026-10-14 | `bcfp_baselines.csv` (17:55 PDT; `bcfp_date_completed` 2026-10-14T03:00:03Z); `turn_bt.txt` run 143 | ✓ (`turn_bt.txt` shows tunnel `date_completed` 2026-10-13 19:35:21, no zone; the two sources differ, the cited one agrees) |
| 2026-10-17: 48/50, link `a17e9177`, same reference, same primitive load | `provincial_246/parity_crosssection.log`, `fresh_parity246.log` | ✓ |
| Accessible: no change on any pair | `pair_moves.csv` | ✓ |
| province-wide counting can only add lifts | `.lnk_pipeline_prep_obs_province`: the observation set is a superset | ✓ |
| 10 override positions added, none removed | `override_diff.csv`, `moves.log` | ✓ |
| BT and WCT at five positions on 356570372 (Columbia), held by LARL | `override_diff.csv` | ✓ |
| none reaches a scored pair | accessible unchanged | ✓ |
| BT rearing −0.269 / −0.325 / −0.633 km | `segment_diff.csv` | ✓ |
| matches the 0.3 / 0.3 / 0.6 predicted | `access_columns.md` | ✓ |
| 0.002–0.043 km of spawning or rearing from ten other pairs | `segment_diff.csv` (10 metric pairs) | ✓ |
| "0 km of spawning" was these, read at 0.1 km | recomputed on `fresh_parity246`: every value under 0.05 km | ✓ |
| each is a segment whose access did not change and is 0 | `cause = gate_settle` | ✓ (1–3 segments per pair) |
| on shared segments these are the only changes | `segment_diff.csv`: only `gate_settle` rows | ✓ (scope: the scored group × species) |
| ADMS CH +0.088 km spawning, +0.167 km rearing | `resegmented_habitat.csv` | ✓ |
| not #349 | crossing code changed only in a comment (a17e9177..6e5cc837); one input load | ✓ |
| 8 lines in ADMS, BULK, ELKR; 39 segments | `resegmented.csv` | ✓ (scoped to the four scored groups) |
| on each of the 8, a PSCIS crossing with two modelled crossings on one `linear_feature_id`, matched to different ones | `fresh.crossings_vw_bcfp`, `modelled_stream_crossings`, both `barriers` tables; 356271598 via 197392 / 101833 / 100891 (100891 removed by a `NONE` fix) | ✓ |
| the last tiebreak, `linear_feature_id`, cannot separate the two | `R/lnk_pipeline_pscis_build.R:113-205,264-279`: one candidate row per modelled crossing within 100 m, same lfid and distance | ✓ |
| 356333200: break at 1,349 m (100122), not 1,446 m (101854) | `barriers`, `resegmented.csv` | ✓ |
| 88 m piece at 0.0441, under CH's spawning max; old 167.5 m piece at 0.0483 | `streams`; CH `spawn_gradient_max` 0.0449 | ✓ |
| that piece spawns; 1,269–1,437 m (167.5 m) now rears; no CH rearing on that line before | `streams_habitat_ch`, both builds | ✓ |
| CH gains exactly that; BT spawning, CO spawning and CO rearing lose 0.006 km each | `resegmented_habitat.csv` | ✓ |
| annotation classes unchanged on all 50 | `pair_moves.csv` | ✓ |
| mapping_code moved on 51 of 86 rows, −0.06 to +0.05 | `mapping_code_moves.csv` | ✓ |
| three things move it: the gate, 91a968ab, breaks | | ✗ 91a968ab's branch fires on none of the 86 rows (finding 2) |
| segment count differs on 50 of 86 rows, in 10 of 17 groups | `mapping_code_moves.csv` | ✓ |
| the tie in "the three scored groups that have one, the other seven not examined" | same | ✗ two scored groups among the 10, eight others (finding 1) |
| five UNEXPLAINED, one class C (BULK SK spawning) | `parity_annotated.csv` | ✓ |
| annotation tolerance 2 % | `lnk_parity_annotate(tolerance = 2)` | ✓ |
| the same five as on 2026-10-17 | `pair_moves.csv` | ✓ |
| lift counting changes access only behind another group's barrier; none of the four has one | 0 barriers held by another group on any line of the four (queried) | ✓ |
| TURN BT: 69 BT records upstream, none in UKEC; UKEC barrier is a falls | `groups_blocked.csv` | ✓ |
| bcfishpass models neither TURN nor UKEC; none in the local reference | `turn_bt.txt` | ✓ |
| TURN BT is the only row for a species the config models; list built under `default` | `turn_bt.txt` (bt 1, gr 7, ko 9, rb 61) | ✓ |
| history rows: dates, link versions, 11 groups, 50 study-area groups | headers of each file | ✓ |

### CLAUDE.md line 26 bullet

| Claim | Source | Verdict |
|---|---|---|
| 48/50, as on 2026-10-17 | logs | ✓ |
| accessible km did not move | `pair_moves.csv` | ✓ |
| gate −0.3 / −0.3 / −0.6 BT rearing, as predicted | `segment_diff.csv` | ✓ |
| ADMS CH +0.17 rearing (+0.09 spawning) is #277, not #349 | `resegmented_habitat.csv` | ✓ |
| PSCIS matched to different modelled crossings on one lfid, the pick tie; on 8 lines of the scored groups | DB queries | ✓ |
| TURN BT cannot be scored | `turn_bt.txt` | ✓ |
| the sizing and recompute sentences | carried over unchanged from the earlier bullet | not re-checked (not new in this diff) |

### research/access_columns.md, "Measured 2026-10-20"

| Claim | Source | Verdict |
|---|---|---|
| stay at 48/50; accessible does not move | logs | ✓ |
| BT rearing falls 0.269 / 0.325 / 0.633 | `segment_diff.csv` | ✓ |
| "0 km" is 0 at 0.1 km; 0.002–0.043 km from ten other pairs | `segment_diff.csv`; recomputed on `fresh_parity246` | ✓ |
| TURN cannot be scored | `turn_bt.txt` | ✓ |

### research/study_area_run.md (added sentence)

| Claim | Source | Verdict |
|---|---|---|
| re-scored at v0.66.6 on 2026-10-20 (#362), record in `bcfishpass_parity.md` | | ✓ |

### research/README.md (added rows)

| Claim | Source | Verdict |
|---|---|---|
| `bcfishpass_parity.md`: the current record, revised in place | the file itself | ✓ |
| the dated parity files are its history | its History table | ✓ |

### data-raw/logs/parity_0.66.6/README.md

| Claim | Source | Verdict |
|---|---|---|
| run_uid, label, dispatcher only | `fresh_parity362.log` (one host, m1) | ✓ |
| model leg 17:17:47 → 18:10:08 UTC | `log.date_start` / `date_end` (18:10:07.59) | ✓ |
| recompute `-j8`; exit 0 at 18:15 UTC | `run.exit` = 0, mtime 18:14:34 UTC | ✓ (rounded) |
| link 0.66.6, `6e5cc837`, `link_dirty` f on all 17 | log | ✓ |
| fresh 0.39.0 `e247ca19`, same as baseline | log | ✓ |
| fwapg `6d48dabf` vs `f9718cb7`: a WatershedAtMeasure migration and pcic, which link does not call | fwapg `git log`; no link `R/` call | ✓ |
| bcfishobs `08630cf4` same; primitives loaded 00:46 UTC | log; `provenance.source_artifact.loaded_at` | ✓ |
| `verify.log` PASS | file | ✓ |
| score 48/50 PASS | file | ✓ |
| `resegmented.csv` = "breaks at modelled crossings that moved" | | ✗ none moved; one tied pair resolved differently (finding 4) |
| other file descriptions | the files | ✓ |

### #277 body, "Measured 2026-10-20"

| Claim | Source | Verdict |
|---|---|---|
| built 2026-10-17 / 2026-10-20 on m1, links `a17e9177` / `6e5cc837`, one primitive load (00:46 UTC) | logs | ✓ |
| crossings and break-source observations left alone; pscis_build changed only a comment | `git diff a17e9177 6e5cc837` (prepare keeps `<schema>.observations` AOI-scoped) | ✓ |
| 39 segments on 8 lines in ADMS, BULK, ELKR; each group's total length unchanged | `resegmented.csv`; length difference 0.0000 m in all 17 | ✓ |
| row counts also differ in BULL, KISP, KOTL, LARL, LFRA, LSKE | `streams` counts | ✓ as written; the proxy misses BABR, HARR, KLUM (finding 3) |
| each of the 8: two modelled crossings on one lfid, matched differently; pick ends on `linear_feature_id ASC` | DB, code | ✓ |
| seven are `MODELLED_CROSSINGS` barriers, 9 to 97 m apart | `barriers` (8.7–97.2 m) | ✓ |
| 356333200: 101854 at 1,446 m old, 100122 at 1,349 m new, both on 700276704 | `barriers` | ✓ |
| 356271598: 101833 breaks only the old build and is a barrier in neither | `resegmented.csv`, `barriers` | ✓ |
| 88 m at 0.0441 passes CH spawning, old 167.5 m (0.0483) did not; +0.088 / +0.167 km | `streams`, `resegmented_habitat.csv` | ✓ |
| candidate 3 has a measured instance | the above | ✓ |
