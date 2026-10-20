# Code-check round 2 (#362), branch diff cefd4608...HEAD (reviewing 2ff9d7ad's fixes too)

## Checklist read

- `code-check.md`: `## Mechanisms`, the prose of all fourteen H3s, read in full (table rows and evidence blocks skipped). Rules that stand alone, Security, Spreadsheets: headings only.
- `code-check-r.md`: read in full: "A database driver's value is not a base R type", "A value compared as `::text`…", "`paste()` with a zero-length argument…", "`match()` treats NA as a matchable VALUE", "Postgres row order is never fixed…", "`sprintf("%g", x)` writes `Inf` and `NA`…", "A range total taken as the difference of two large running totals…", "`ifelse()` with an all-NA test…". The rest (about 120 headings) by heading only.
- `code-check-shell.md`, `code-check-spatial.md`: not read beyond the index. The diff has no shell or spatial code.
- `index.md`: I did not read it in full. I took the headings from the full files with grep.

## Verified (no finding)

All checked read-only against the committed CSVs and the local DB:
- Accessible km per pair, unrounded: identical to 0.0001 km in both builds for every scored pair.
- `segment_diff.csv`: only `gate_settle` rows. Ten non-BT pairs at 0.002–0.043 km; BT 0.269 / 0.325 / 0.633.
- `resegmented_habitat.csv` deltas: CH ADMS +0.088 / +0.167. BT spawning, CO spawning and CO rearing −0.006 each, all from 356333200's 9 m piece at 1,437 m (lost) and 356239227's +3 m. Nothing else moves.
- The 356333200 segment story (167.5 m at 0.0483, then 79.5 m at 0.0530 and 88 m at 0.0441; CH none → 88 m spawning and 167.5 m rearing).
- The 7 moved positions: 8.7–97.2 m. The vanished break at 101833 (161.5 m) is a barrier in neither build.
- 10 override positions added and 0 lost, on the Columbia River (`gnis_name`), held by LARL.
- mapping_code: 51 / 86 rows; −0.06 to +0.05; `total_segs` differs on 50 rows in 10 groups.
- Stamps: link `a17e9177` / `6e5cc837`, fresh `e247ca19` on both, fwapg `f9718cb7` → `6d48dabf`, bcfishobs `08630cf4`, `link_dirty` f, `run.exit` at 18:14:34 UTC, schema sizes 3.9 GB.
- `config_hash` differs between the builds (`c48ed740…` / `ab240417…`). The only bundle change is the trailing newline on `cabd_blkey_xref.csv` (#347), so "same inputs" holds in content.
- `R/lnk_pipeline_pscis_build.R` changed only a comment between the builds.

## Findings

- **[claim]** `research/bcfishpass_parity.md:69-78`, the #277 body ("Measured 2026-10-20": "Every moved break … moves by 9 to 97 m along its line"; "So candidate 3 … is now narrowed to which modelled crossings break a line"), `CLAUDE.md:26` ("a modelled-crossing break that moved") and `planning/active/findings.md:51-60`. On all eight lines, the evidence shows something these texts do not say. A break did not move. A PSCIS crossing sits between **two different modelled crossings on one `linear_feature_id`**, and the two builds keep a different one of the pair (`fresh.modelled_stream_crossings`, `fresh.crossings_vw_bcfp`):

  | line | PSCIS | old build | new build | shared `linear_feature_id` |
  |---|---|---|---|---|
  | 356239227 | 366 | 101843 (2368.7) | 101419 (2383.0) | 700276917 |
  | 356308590 | 197401 | 24728121 (446.6) | 102755 (394.0) | 700258335 |
  | 356333200 | 367 | 101854 (1446.3) | 100122 (1349.1) | 700276704 |
  | 356485958 | 197560 | 24734797 (445.6) | 4600181 (463.9) | 706829022 |
  | 356540859 | 197541 | 4604198 (275.2) | 4606094 (237.7) | 706837142 |
  | 360467487 | 203852 | 24742362 (672.1) | 1803307 (663.4) | 17027400 |
  | 360758470 | 203864 | 1805558 (54.0) | 1800034 (114.7) | 17093686 |
  | 356271598 | 197392 | 101833 breaks (161.5) | no break | 700266052 (with 100891) |

  This is the PSCIS→modelled pick tie in `R/lnk_pipeline_pscis_build.R:264-279`: `linear_feature_id ASC` cannot separate two candidates on one feature. `CLAUDE.md`'s 2026-09-25 status already names it ("two identical ADMS runs gave 39,423 vs 39,422 segments"), and so does `code-check-r.md`, "Postgres row order is never fixed". The eighth line is not a separate oddity. It is the same tie, between two non-barrier crossings. So the evidence identifies candidate 3's exact site rather than narrowing it to "which modelled crossings break a line".

  It also changes how the ADMS CH move reads. bcfishpass pairs PSCIS 367 with 101854 and keeps 100122 at 1,349 m as a modelled crossing. That is what the new build does, so on that line the new build moved *toward* bcfishpass.

  Why it matters: #277 is the reproducibility bar, and its body and the parity record give a weaker, partly wrong mechanism ("a break that moved 9–97 m") when the committed segments plus two read-only queries name the line of code.

- **[claim]** `research/bcfishpass_parity.md:69-70` ("Two builds over the same inputs break 8 lines in ADMS, BULK and ELKR at different places") and `planning/active/findings.md:57`. `moves.R` measured only the four scored groups (`wsgs <- unique(new$wsg)`), but the sentence has no scope. Over the 17-group closure, `streams` row counts differ in seven groups: ADMS −1, BULL −1, KISP +1, KOTL −1, LARL +3, LFRA +1, LSKE +1. So resegmentation reaches at least six groups the record does not mention, and the 8-line set is not the whole. The #277 body gets this right ("Of the four scored groups"). The mapping_code paragraph (`:86-90`) then attributes the `total_segs` differences in 10 of 17 groups to "the moved breaks above". Those are the 3 groups measured, and for the other groups the attribution is unmeasured. Scope the sentence to the four scored groups.

- **[fragile]** `data-raw/logs/parity_0.66.6/moves.R:70-82`. When the two builds share every segment, `reseg` has 0 rows. `sprintf("('%s', %d)", character(0), integer(0))` is then `character(0)`, `paste(collapse = ", ")` is `""`, and the query becomes `WHERE (…) IN ()`, a Postgres syntax error that aborts the script before `segment_diff.csv` and `mapping_code_moves.csv` are written. A reproducible pair of builds is exactly the outcome #277 is working toward, and `research/bcfishpass_parity.md:131` tells the next re-score to use `moves.R`. Guard it: `if (nrow(reseg_lines)) … else reseg_hab <- <empty frame>`.

planning/active/review-round2.md
