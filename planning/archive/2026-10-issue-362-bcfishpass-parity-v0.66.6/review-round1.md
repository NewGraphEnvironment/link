# Code-check round 1 (#362), branch diff cefd4608...HEAD

## Checklist read

- `code-check.md`: `## Mechanisms`, the prose of all fourteen H3s, read in full with table rows and evidence blocks skipped.
- `code-check-r.md`: read these sections in full: "Postgres row order is never fixed…", "`sprintf("%g", x)` writes `Inf` and `NA`…", "A database driver's value is not a base R type", "`match()` treats NA as a matchable VALUE", "CSV whitespace", "`ifelse()` with an all-NA test", "`paste()` with a zero-length argument", "A value compared as `::text`…". The rest I read only as index lines (about 125 headings).
- `code-check-shell.md`, `code-check-spatial.md`: index lines only. No full section applies: the diff has no shell or spatial code.
- The repo's CLAUDE.md "Writing for the Reader" and Agent Operating Rules §3, "Documents that share an ancestor corroborate nothing".

## Verified (no finding)

These match the committed evidence and the DB, checked read-only:
- The score: 48/50, the table values, the 0.07 % accessible maximum, the five left-out pairs, the five UNEXPLAINED pairs plus one C, and class unchanged on all 50 pairs.
- The BT gate figures 0.269 / 0.325 / 0.633 km, ten other pairs, and the 0.002–0.043 range.
- The 10 added override positions with 0 lost, on blue_line_key 356570372, held by LARL.
- 51 of 86 mapping_code rows moved, by −0.06 to +0.05.
- The ADMS CH segments on 356333200: 167.5 m at 0.0483, then 88 m at 0.0441, against a CH spawning maximum of 0.0449.
- In the #277 body: 7 persisted moved breaks, all `MODELLED_CROSSINGS`, moved 9–97 m; total length unchanged.
- The stamps: link and fresh SHAs, `link_dirty` f, model leg times, primitive and bcfishobs loads at 00:46 / 00:47 UTC, the fwapg delta, and the comment-only `lnk_pipeline_pscis_build.R` change.
- TURN: falls, 69 BT records upstream, 0 TURN / UKEC rows.
- No host addresses in the changed files (the pattern was checked against a known positive first).

## Findings

- **[claim]** `research/bcfishpass_parity.md:64-65` (and the bracketed −0.1 at lines 27, 36 and 40): "which rounds to −0.1 km in four of them" is wrong about the mechanism. The four gate removals are 0.011 km (ADMS SK spawning), 0.030 km (BABL CO rearing), 0.022 km (ELKR WCT spawning) and 0.041 km (ELKR WCT rearing) (`segment_diff.csv`). Each rounds to 0.0. The −0.1 is the difference of two totals rounded separately (`pair_moves.csv`: ADMS SK 86.7 → 86.6), so the brackets overstate these moves 2–9x. Say "shows as −0.1 km at the table's rounding", or quote the `segment_diff.csv` km.

- **[claim]** `research/access_columns.md:117-125` and `research/bcfishpass_parity.md:62`: the file opens "as predicted" but keeps a prediction that says the settled segments "carry 0 km of spawning in every scored pair". Then "removes a further 0.002–0.043 km" and "and a little more" present the extra removal as beyond the prediction. It is not beyond it: these segments are already in the prediction's population on `fresh_parity246`. Example: ADMS blue_line_key 356242028 at 1,507.9 m, 11.1 m long, `accessible` t, `access_sk` / `access_co` 0, spawning t. So "0 km" was 0.0 at 0.1 km rounding, as `planning/active/findings.md:48-49` says, but the research files do not. `expected.txt`'s "spawning 0.0 on all 17 pairs" also reads −0.1 on two pairs in `pair_moves.csv`.

- **[claim]** `research/bcfishpass_parity.md:71` ("Seven modelled-crossing breaks moved this way in ADMS, BULK and ELKR") and the #277 body's "So candidate 3 … is now narrowed to the modelled-crossing positions a build persists". `resegmented.csv` has 8 lines, not 7. On the eighth, ADMS 356271598, the break at 161 m (modelled crossing 101833 at 161.5 m) exists only in `fresh_parity246`, with no counterpart in the new build. It vanished rather than moved, which is why ADMS goes from 39,424 to 39,423 segments in `moves.log`. Neither `fresh_parity246.barriers` nor `fresh_parity362.barriers` holds it. So a modelled-crossing break that neither build persists also changed between same-input builds. That contradicts narrowing #277's candidate 3 to the persisted positions, and "seven" leaves out one of the eight breaks that changed.

- **[claim]** `research/bcfishpass_parity.md:79-82` (and `planning/active/findings.md:62-63`): the mapping_code move is said to be confounded by "two changes that move mapping codes and not km (the gate, and 91a968ab…)". This is wrong in two ways.
  1. The gate does move km: the bullet just above it is the gate's BT rearing −0.3 / −0.3 / −0.6 km.
  2. It leaves out a third confound that the CSV it cites shows. `total_segs` differs between the two compares on 50 of the 86 rows, in ADMS, BABR, BULL, ELKR, HARR, KISP, KLUM, LARL, LFRA and LSKE. That is #277-type resegmentation in 10 of the 17 groups, and it moves per-segment mapping-code agreement too.

- **[claim]** `planning/active/findings.md:53`: "that line's CH rearing 4,025.5 → 4,193.0 m" does not match blue_line_key 356333200. On that line in ADMS, CH rearing is 0 m in `fresh_parity246` and 167.5 m in `fresh_parity362`. Its wscode subtree gives the same 0 → 167.5 m. Only the difference, 167.5 m, agrees. Either name the population those totals are taken over or correct them.

- **[fragile]** `data-raw/logs/parity_0.66.6/moves.R:79-99`: the segment diff joins on `(blue_line_key, downstream_route_measure)` and takes the length from the old build only. The `n` CTE selects no `length_metre`, so every `*_gained_km` is the old length too. A segment whose key survives but whose length changed is therefore counted at its old length. There are 12 such segments in the four groups, all beside the moved breaks. Two examples:
  - ADMS 356239227 at 2,380 m: 49 m → 3 m. It gives `spawning_gained_km` 0.049 on the ADMS BT / CO `other` rows.
  - ADMS 356333200 at 1,269.5 m: 167.5 m → 79.5 m. It gives ADMS CH `rearing_gained_km` 0.168.

  These match the true change only because the new piece beside each one, which is left out, carries the remainder. The `gate_settle` rows are unaffected (none of those segments changed length). But the README makes `segment_diff.csv` the authority for small moves. Fix either way: send keys whose length changed to `resegmented.csv`, or sum `n.length_metre` for gains.

planning/active/review-round1.md
