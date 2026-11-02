# Code-check of PR 3, round 3 (enumeration)

## Checklist read

`code-check.md`, the prose of every H3 under `## Mechanisms` (table rows skipped): a guard that fails toward pass;
a fixture that cannot reach the failure mode; a proxy is not the property; verification that reads its own output;
a guard's scope, escape hatches, and remedies; a fix lands in one of two callers that share a harness; restore the bug
and prove the guard fires; a shared working tree; a wrapper's exit is not the work; zero-length, empty and unset; the
probe is broken before the world is; written data outlives the fix; serialization loses meaning silently; one fact
derived twice. Index read for the -r, -shell and -spatial files.

Sources used: `git` (log, diff, blame, cat-file), the CSVs and logs in `data-raw/logs/test_builds_440/`,
`data-raw/logs/parity_0.78.0/`, `data-raw/logs/study_area_run/20261102_083253_*`, `data-raw/logs/bcfp_baselines.csv`,
issue #446, `gh pr view 443`, fresh's `v0.52.0` tag, and read-only queries on m4's fwapg (`zz440_default`,
`zz432_post`, `whse_basemapping.fwa_stream_networks_sp`). The parity table, brackets, counts and "moved away" set were
recomputed from `pair_moves.csv` by script (every one of the 51 cells matches).

## Enumeration

### data-raw/logs/test_builds_440/README.md

| line | claim | verdict | source |
|---|---|---|---|
| 3 | 2026-11-02, m4, link 0.78.0, fresh 0.52.0 | pass | `zz440_default.log`: link_version 0.78.0, fresh 0.52.0 (`245c8d8d` = fresh `v0.52.0`) |
| 3 | link 0.78.0 is "the code PR #443 pins" | pass | PR #443 head `34c4c598`; `git diff 34c4c598 4069fdfc` touches no `R/`, `inst/`, `DESCRIPTION` or `data-raw/*.R` |
| 3 | KETL built at `4069fdfc` | pass | `zz440_default.log` |
| 3 | KOTL, BULK, MURT and all four recomputes logged `7c36b882` | pass | `log`, `log_recompute` |
| 3 | because `expected.txt` was committed while run.sh modelled; run.sh checks the tree only at start | pass | commit 09:24:51Z; KETL log row opened 09:24:19, KOTL 09:26:43; `run.sh` line 11 |
| 3 | `R/` identical between the two | pass | `git diff --stat 4069fdfc 7c36b882`: only `expected.txt` |
| 3 | every row is clean | pass | `link_dirty`, `fresh_dirty` f on all 4 `log` rows; `link_dirty` f on all 4 `log_recompute` rows |
| 3-4 | four groups built under `default` into `zz440_default` and recomputed | pass | `status.tsv`, `log.config_name` |
| 4 | MURT is the group where only paused species are present | pass | presence table: MURT has only `rb` |
| 5-7 | KOTL recompute exit 1 on the downstream-dam post-condition, dam in a group not held; as in 415's pass rule | pass (accepted) | `recompute_KOTL.log` (Grand Coulee, LARL); `minimal_breaks_415/run.sh` lines 13-16 |
| 11 | compare.R "copied from ../species_paused_432/, output path changed" | **fail** | argument handling also changed (finding 7) |
| 11 | identical | pass | `summary.csv`, `km.csv`, `obs.csv` all zero |
| 11 | BULK, KETL, KOTL in `zz432_post` are link `a6942b5d` at fresh 0.52.0 | pass | `zz432_post.log` |
| 11 | MURT's newest row is a later rebuild, `2774f5b2`, fresh 0.48.0 | pass | `zz432_post.log` |
| 11-13 | segments, breaks, barrier and override rows, km per species, segment under each record the same in all four | pass | compare outputs (MURT has no modelled species or records, so its km and record checks are vacuous) |
| 13 | "The code since those builds moves nothing in `default`'s output on these groups" | **fail (wider than the cited check; true on my check)** | finding 5 |
| 15 | m1 `fresh_default`, run `20261023_074321-24d85e8c`, link 0.68.0, fresh 0.42.0 | pass | `provenance_m1_fresh_default.csv` (file carries terminal escape bytes, finding 6) |
| 17 | summary.R run on each host against its own schema | pass (no other record) | summary CSVs' `schema` column |
| 22-25 | the eight segment and barrier counts | pass | summary CSVs |
| 27 | segments fall 2.1- to 2.9-fold | pass | 2.06, 2.47, 2.87, 2.61 |
| 27-29 | breaks removed by #326, #396, #432 | accepted (attribution, "not decomposed") | #402 added only BULK CM in these groups (adds, not removes) |
| 29 | #433 measured 0.2 to 6.0 % | pass | `research/species_paused.md` line 21 |
| 30-31 | KO and RB have no habitat or access; MURT built with no habitat | pass | summary; `access_ko`, `access_rb` NULL on every row |
| 32 | BULK gains chum, 5,164 km accessible, 1,862 spawning, from #402 | pass | summary; presence notes |
| 33 | barrier rows rise 15 to 40 | pass | +15, +25, +40, +23 |
| 33-34 | "that is the scale" #326's unify fix restored (4 to 31 lost) | accepted (attribution) | KOTL's +40 is above the 4-31 range; net also mixes #432 and BULK CM; not reported |
| 35-36 | accessible 0.0 to 0.3 %, spawning and rearing under 1 %, every species modelled in both; the two examples | pass | recomputed: accessible 0.002-0.27 %, max habitat 0.97 % (KOTL WCT spawning) |

### data-raw/logs/parity_0.78.0/README.md

| line | claim | verdict | source |
|---|---|---|---|
| 3-4 | 17-group closure, `bcfishpass`, `fresh_parity441` on m1, against `fresh_parity361` | pass | `run.log` |
| 11 | run_uid, label, dispatcher only, worktree at `34c4c598` | pass | `run.log`; `run_verify.log` link_sha |
| 12 | 08:32 to 09:22, `-j8`, critical path 50.0 min, driver files | pass | `run.log` summary; files exist |
| 13 | link 0.78.0, `34c4c598` = PR #443's head | pass | `gh pr view 443` |
| 14 | fresh 0.52.0 `245c8d8d`; install route | pass (accepted) | `run_verify.log`; fresh tag |
| 15 | primitives = the 2026-10-23 load; `--preflight-note` recorded it | pass | `run.log` OVERRIDE line; load stamps 10 d |
| 16 | reference view loaded 2026-10-23 at `-50-g620dbe4`, newest m1 snapshot row | pass | `bcfp_baselines.csv` (`snapshot-20261023`, `--with-bcfp-views`) |
| 16 | driver pin and every `fresh_parity441.log` row read `-51-g3bd2824`; cause per #446 | pass | `run.log`, `run_verify.log` section 2; #446 |
| 16 | expected.txt repeated that pin | pass | `expected.txt` last lines |
| 17 | `--pretest-note`, reason | pass | `run.log` |
| 21 | 48/50 PASS; `run_verify.log` PASS | pass | logs |
| 21-22 | reference moved on 0 of 50; no override added or lost | pass | `moves.log`, `pair_moves.csv` |
| 23-24 | expected.txt committed 09:24:51Z, then the score ran | pass | commit time; `parity_crosssection.log` mtime 09:25:14Z on m4 |
| 24-25 | three of four bounds wrong (accessible, spawning, BULK CO rearing) | pass | `pair_moves.csv` |
| 34 | moves.R adapted from 0.68.0's; temp table; 17,527 lines; old/new labels | pass | `git diff --no-index`; `moves.log` |
| 34 | "because #326 re-breaks 17,527 lines" | accepted as attribution here, but contradicts `moves.R` line 17 (finding 2) | |
| 36 | `segment_diff.csv`: "segments both builds share whose habitat changed" | **fail** | finding 8 |
| 37 | override_diff: none | pass | `moves.log` |

### Script headers

| file:line | claim | verdict |
|---|---|---|
| run.sh 2-5 | scratch `zz440_default` on m4, built then recomputed, beside `zz432_post`; MURT | pass |
| compare.R 2 | "copied ..., output path changed" | **fail** (finding 7) |
| compare.R 3 | README names each commit | pass |
| compare.R 4-13 | original header, kept as such | pass |
| summary.R 2-5 | per group and species: segments, km, barrier rows, accessible (1 or 2), spawning, rearing | pass (code) |
| moves.R 1-3 | 0.68.0 build vs 0.78.0 build, adapted, reports reference change | pass |
| moves.R 5-12 | the five outputs and the raw-flag note | pass |
| moves.R 15-16 | match on key, same length within 1 mm | pass (code) |
| moves.R 16-17 | one-build-only segments: "the two builds break the line in different places, #277" | **fail** (finding 2) |

### research/bcfishpass_parity.md (top through "What moved at v0.78.0", "What is not yet explained", "Re-scoring", "History")

| line | claim | verdict | source |
|---|---|---|---|
| 3-5 | verified date, producers, run, link, fresh | pass | |
| 13-16 | 48/50; tolerances; the two BULK SK pairs and values; accessible within 0.11 % on 17 | pass | `parity_crosssection.log` |
| 18-19 | bracket definition (change since 0.68.0, 0.1 km or more); lake connection out both sides | pass | `moves.R` rounding; `parity_crosssection.R` |
| 23-39 | all 51 cells | pass | script check against `pair_moves.csv`: no mismatch |
| 41-42 | five pairs left out | pass | log |
| 44-48 | closure 17, m1, worktree, verify PASS, primitives, reference 0 of 50 | pass | |
| 52 | 0.68.0 run uid, schema, 48/50 | pass | `parity_0.68.0/README.md` |
| 53 | primitives same load (load stamps) | pass (ages only; no stamp value committed) | `run.log` 10 d |
| 54 | reference = m1 view load of 2026-10-23, `-50-g620dbe4`, "the newest snapshot row in `bcfp_baselines.csv`" | **fail (fragile)** | finding 3 |
| 54-55 | 0 of 50; no override added or lost; FWA and discharge not compared | pass | |
| 56 | about 40 of 50 moved by 0.1 km or more | pass | exactly 40 |
| 58 | rearing rose in BULK and BABL for BT, CH, CO, ST by 4.6 to 23.3 km | pass | |
| 58-59 | BULK CH, CO, ST crossed the reference; all but BULK CO ended nearer | pass | |
| 59-60 | most of the gain on shared segments, "BULK BT +22.1 km of +21.4" | **fail (fragile)** | finding 4 |
| 60-62 | can come from a rule or clusters; consistent with #326's order-1 exception, BT CH CO ST WCT in this bundle; not isolated | pass | `dimensions.csv` |
| 63 | spawning fell toward the reference: ADMS BT -4.5, ELKR BT -8.2, ELKR WCT -9.1 | pass | |
| 64 | 0 km on shared segments, so every spawning move is on re-broken lines | pass | `segment_diff.csv`: spawning lost and gained 0 everywhere |
| 64-65 | ELKR WCT rearing -15.5, toward | pass | |
| 66 | accessible fell up to 2.1 km a pair; within 0.11 % | pass | all 17 negative |
| 67-68 | eight pairs moved away; BULK CO rearing 3.3 to 8.5; seven by 0.2 to 2.1; ELKR WCT accessible 1.8 to 3.9 | pass | recomputed |
| 70-71 | bracket rounding; ADMS BT accessible 0.064 km on shared segments | pass | `segment_diff.csv` |
| 71-72 | 95,106 of 129,329 shared | pass | `moves.log` |
| 72-74 | expected.txt three of four bounds wrong; leaned on #326 elsewhere; only pass count held | pass | |
| 76 | `default` builds "match their last builds exactly" | pass on my check (finding 5 is about the cited evidence) | |
| 76 | moves line up with #326, #396, #432, #402 | accepted (attribution) | |
| 136-138 | two UNEXPLAINED, one class C at 2 % tolerance | pass | `parity_annotated.csv` (2 % is `lnk_parity_annotate()`'s default, not the taxonomy's; value correct) |
| 141-142 | +7.39, +2.72 | pass | |
| 144 | BABL ST, BABL CH, ELKR WCT rearing UNEXPLAINED at 0.68.0, within 2 % now | pass | `pair_moves.csv` class columns |
| 144-145 | segmentation the first suspect for ELKR WCT spawning, not measured | pass (stated as suspect) | |
| 159-167 | the re-score commands | **fail** | finding 1 |
| 169-171 | keep the reference fixed (no `--refresh-primitives`); previous schema kept | the first half collides with the vintage gate (finding 1); the second not checkable from m4 | |
| 177-187 | History rows for 0.78.0, 0.68.0, 0.66.6, 2026-10-17 | pass | each README / `run_verify.log` / `DESCRIPTION` at the sha |

## Findings

- **[severity: bug]** research/bcfishpass_parity.md:159-171 — the "Re-scoring" recipe refuses when run as written.
  This re-score needed both `--pretest-note` and `--preflight-note` (`run.log`: "WARN: pre-run gate not cleared
  (... fresh_parity441.log_pretest does not exist) — proceeding on --pretest-note"; "primitive vintage (window 7 d) -
  FAILED ... proceeding on --preflight-note"). `study_area_run.sh` sets `fail=1` for each when no note is given
  (lines 1197-1208 and 1264-1275). The recipe passes neither. Its own advice, "do not pass `--refresh-primitives`",
  makes the vintage refusal certain once the held load is more than 7 days old, and a new scratch schema never has a
  gate record. The recipe predates #372's gate; this PR edited the paragraph under it and left the command.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (run the remedy yourself)

- **[severity: fragile]** data-raw/logs/parity_0.78.0/moves.R:16-17 — the header blames one-build-only segments on
  "#277", the PSCIS pick tie that 0.68.0 fixed (#367), and that is not what separates these two builds. Line 103 of the
  same file and the README's Files row (line 34) blame #326. The line was inherited from the 0.66.6 script, and the
  0.78.0 adaptation corrected the comment it added but not this one. The mapping-code comment further down
  ("Moved by the gate and by lines the two builds break differently", near line 185) is inherited too. The gate has
  not changed since 0.66.6, so it moves nothing between 0.68.0 and 0.78.0.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (an inherited restatement that must track)

- **[severity: fragile]** research/bcfishpass_parity.md:54 — "the newest snapshot row in `bcfp_baselines.csv`" names
  no host. The parity README (line 16) was corrected to "the newest m1 snapshot row", and this copy was not. The
  working tree already holds an uncommitted m4 row, `2026-11-02 03:01,m4,snapshot-20261102,...,v0.7.15-51-g3bd2824,
  ...--with-bcfp-views`, from the refresh now running (`git blame` shows "Not Committed Yet"). Once that row is
  committed, the sentence points at `-51-g3bd2824`, the version #446 says the view was not loaded at.
  - **Rule:** code-check.md "One fact derived twice"

- **[severity: fragile]** research/bcfishpass_parity.md:59-60 — "BULK BT +22.1 km of +21.4" sets two different
  populations side by side. The +22.1 is `segment_diff.csv`'s raw `rearing` flag, which includes lake connection
  lines (`moves.R` line 8). The +21.4 is the scored pair, which leaves them out (this file, line 19). Read as written,
  the shared segments carry 103 % of the gain, and nothing on the page says why. The comparison holds for "most of
  the gain" only on the raw flag. The resegmented lines add +8.6 km raw (`resegmented_habitat.csv`, 1953.3 → 1962.0),
  and those lines include some shared segments, so the raw total cannot be split from these files.
  - **Rule:** code-check.md "One fact derived twice" (one column name carrying different populations)

- **[severity: fragile]** data-raw/logs/test_builds_440/README.md:13 (and research/bcfishpass_parity.md:76,
  "match their last builds exactly") — "The code since those builds moves nothing in `default`'s output" claims more
  than `compare.R` checks. `compare.R` compares segments, break positions, barrier and override rows, access codes
  1 or 2 together, spawning and rearing, and the segment under each record. It does not compare the code 1 versus 2
  split, mapping codes, downstream-barrier flags or the lake and wetland buckets. The claim does hold: on m4, an
  `EXCEPT` in both directions between `zz432_post` and `zz440_default` for the four groups returns 0 rows for
  `streams`, `streams_access`, `streams_mapping_code` and all 11 `streams_habitat_*` tables. The record should carry
  that check (the scratch schemas are not durable) or narrow the sentence to what `compare.R` covers.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** data-raw/logs/test_builds_440/provenance_m1_fresh_default.csv:1 — the file starts with the
  bytes `ESC ( B ESC [ m` (a terminal reset, likely from the remote shell's output), so the first column reads as
  `"\033(B\033[mwatershed_group_code"`. A reader that selects the column by name gets nothing, and the file the README
  cites for m1's provenance is not clean CSV.
  - **Rule:** none

- **[severity: fragile]** data-raw/logs/test_builds_440/compare.R:2 and README.md:11 — "copied from
  species_paused_432/compare.R, output path changed" undersells the diff: the argument handling changed as well (the
  `zz432_pre` / `zz432_post` defaults were removed, both arguments are now required, and the usage line changed). That
  is round 1's fix, so the provenance line no longer describes the copy.
  - **Rule:** none

- **[severity: fragile]** data-raw/logs/parity_0.78.0/README.md:36 — the Files row describes `segment_diff.csv` as
  shared segments "whose habitat changed". The file also holds access-only rows (`cause = access_changed`, for
  example ADMS BT, 15 segments, 0.064 km accessible, no habitat change), as `moves.R`'s own header says ("access,
  spawning or rearing differ").
  - **Rule:** none
