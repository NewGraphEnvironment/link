# Code-check round 2: #284 research scripts, config, verdict doc

Reviewer: subagent, 2026-09-26. Everything was read-only: docker fwapg (a count query only),
the staged outputs in `data-raw/logs/habitat_thresholds_284/`, fresh's source, and a copy of
the Zotero DB in the scratchpad. The only repo file written is this one. `git status` shows no
unstaged changes, and every output's mtime is later than both scripts' last edit, so the
committed CSVs come from the committed code.

## Mechanism behind round 1

**One fact derived twice.** Each round-1 defect was a definition written out by hand at each
place that consumed it, when it should have been defined once:

- the "use" population was filtered for `accessible` separately in quantiles, selection and
  the floor rule;
- `rules.yaml` was re-coded as `status_one()`;
- `pred_set` was written once in R and again in SQL;
- width was binned in SQL on one side and in R on the other;
- the dedup key and the group key differed.

The same shape also reaches the **prose**. The research doc restates numbers and populations
from the CSVs, and some of them date from the pre-fix run. It also reaches the **second
script**: the stamp fix went into one of the two producers. Findings 1-7 below are all
instances of it.

## Findings

- **[bug, undeclared departure that flips two verdicts]** `research/habitat_thresholds.md:32-33`, `:58-61`; `data-raw/logs/habitat_thresholds_284/README.md` (last bullet)
  The doc says the rule "was fixed before any distribution was looked at, and applied
  mechanically", and it lists exactly **one** correction, the inverted ratio clause. The
  pre-registered rule (`task_plan.md:28-36`) defines Use without an accessibility condition,
  and the gradient P95 is not a use-vs-availability statistic. Restricting the P95/P5 to
  accessible segments was decided after round 1 had already shown the result, and it flipped
  CH `spawn_gradient_max` and CH `rear_gradient_max` from "change" to "keep".
  `findings.md:108-112` records this ("withdraws the CH `rear_gradient_max` 0.0649
  candidate"). The restriction is defensible, but it is a second post-hoc departure and it
  decided two published rows. List it under the departures, with the before and after values
  (CH spawn P95 0.052 → 0.044, CH rear 0.063 → 0.060, BT rear 0.131 → 0.125).

- **[bug, stale number]** `research/habitat_thresholds.md:209`
  Scoring question 1 asks "whether CH rearing at 0.0649 earns its length". 0.0649 is the
  candidate from before the fix, withdrawn in `findings.md:111`. Nothing in the committed
  outputs produces it: `candidates.csv` has `rule_value` 0.0549, "keep". Either drop it, or
  name it as an untested alternative and say where it came from.

- **[bug, number does not match selection.csv]** `research/habitat_thresholds.md:98-99`
  The doc says of CH rearing: "ratio 0.3–0.5 from 5 to 10 %". The `CH_rear` gradient ratios
  from 5 % to 10 % are 0.34, 0.51, 0.35, **0.10** (7–8 %), **0.20** (8–9 %) and 0.50. Two of
  the six bins are well below the stated range, and the prose uses that range to argue use
  "persists to ~10 %".

- **[bug, wrong model mechanism in prose]** `research/habitat_thresholds.md:155-157` (also `task_plan.md:13`)
  The doc says: "the extra steep rearing survives only when spawning lies above it through
  ≤ 5 % reaches." fresh's `.frs_cluster_both()` (`fresh/R/frs_cluster.R`, Phase 2 and
  Phase 3) validates a rearing cluster in two ways:
  - *upstream* spawning is a boolean check with no gradient constraint (rearing below
    spawning);
  - *downstream* spawning must lie within 10 km with no segment ≥ `bridge_gradient` on the
    downstream trace (rearing above spawning).

  So steep rearing survives whenever spawning lies above it, whatever the gradient in
  between. It also survives with spawning below it through < 5 % reaches. The doc attaches
  the 5 % constraint to the wrong direction and omits the second path. Scoring question 2
  (`:210`) is framed on this sentence.

- **[fragile, population stated differently from the one computed]** `research/habitat_thresholds.md:39-41`, `:51`, `:84-86`
  - `:39-41` says "every statistic below uses the ones on accessible segments". Some
    statistics below do not:
    - The bridge share (1.2 %, `:153`) divides by all 2,560 BT locations, including 14
      inaccessible ones, and so does `candidates.csv`'s bridge row (`n` = 2560 against
      2,443 for the other BT rows).
    - The UHC count of 636 (`:186`) uses all 1,745 CH locations.

    Neither changes a verdict: 31/2546 is still 1.2 %.
  - `:51` says "P5 of non-river-polygon width". `:85` says "The 67 that do not [sit on river
    polygons]". The code uses `pred_set == "stream"` only: stream edges outside every
    waterbody, with non-NULL width. There are 86 accessible CH spawning observations off
    river polygons: 68 stream, 15 lake and 3 wetland. One of the 68 has NULL width.

- **[fragile, number]** `research/habitat_thresholds.md:94-95`, `:166`
  - `:94-95` says modelled width "carries roughly ±40–50 % error". `fiss_width_error.csv`
    MODELLED has p10–p90 0.69–1.56, which is −31 % / +56 % on n = 18.
  - `:166` says "averages 0.97 × measured". 0.97 is the **median** ratio, not a mean.

- **[fragile, provenance; round-1 fix #5 landed in one of two producers]** `data-raw/query_habitat_thresholds_fiss.R:176-186`
  `fiss_stamp.txt` records the knowledge SHA but none of the following:
  - a knowledge dirty flag;
  - link's SHA or dirty state (the script was uncommitted when it ran);
  - the vintage of the schema it snaps to. That is `fresh`, not `fresh_default`, and its
    `log` is never read.

  The FISS width-error and presence numbers quoted in the doc therefore carry a weaker stamp
  than the obs numbers. A smaller gap in the obs stamp: `data-raw/query_habitat_thresholds_obs.R:484`
  checks dirt only for `R/` and the script. It does not check
  `inst/extdata/configs/default/`, which supplies the thresholds, presence, exclusions and
  UHC it reads.

- **[fragile, citation fidelity]** `research/habitat_thresholds.md:139-140`, `:147`
  The doc cites Dunham & Rieman (1999) as a primary source ("find juveniles 'very
  unlikely'…"). `literature.md:123` and `:151` say it was **not read**: the finding comes
  through Dunham & Chandler (2001, pp. 3, 26). Under the repo's reference convention it
  should read "Dunham & Rieman 1999, as cited in Dunham & Chandler 2001". At `:139` it is
  also listed as one of the "sources for 2 m" in the **spawning**-width paragraph, but it is
  about juvenile occurrence.

- **[PWF integrity, same shape as round-1 #8]** `planning/active/task_plan.md`
  Four ticked boxes claim things the code or doc does not do:
  - Phase 1 (`:52-53`): "DV … used where `wsg_species_presence` marks bt **and not dv**".
    The code (`query_habitat_thresholds_obs.R:84`) uses "bt" only, which is the documented
    replacement. The box still describes the rule that was dropped.
  - Phase 2: "size modelled-vs-measured width **and gradient** error". Only the width error
    is computed.
  - Phase 4: "Update `test-lnk_config.R` (**it now owns `parameters_fresh`**)".
    `default_tuned` does not own a copy, per the next box.
  - Phase 5: "one row per threshold (current / use-vs-availability / FISS / literature /
    candidate / confidence / status)". The verdict table has five columns, with no FISS,
    literature or status column per row.

- **[fragile, overclaim]** `inst/extdata/configs/default_tuned/README.md` Status paragraph (and `config.yaml` description)
  The README says "Every other CH and BT threshold was examined and kept". #284 examined the
  gradient max, the width min, `spawn_gradient_min` and the bridge. It did not examine
  `*_channel_width_max`, the MAD columns, `rear_lake_ha_min` or the edge types, although
  they sit in the same CSV. The claim should say "every other CH and BT gradient and
  channel-width minimum".

## Round-1 fixes verified

1. Quantiles are now accessible-only. Recomputed from `obs_segments.csv`:
   - CH_spawn P95 0.044275 (n 226), P5 width 6.637 (n 67);
   - CH_rear P95 0.05956 (n 497), P5 width 1.714 (n 215);
   - BT_any P95 0.12533 (n 2443), P5 width 1.912 (n 1469);
   - BT_spawn_dv P95 0.196425 (n 76), P5 width 1.16 (n 53);
   - BT_any_dv P95 0.134825 (n 4764).

   All match `quantiles.csv` and `candidates.csv`. `snap49` and the keep/change arms
   reproduce every row.
2. `width_null_river_poly` is correct against `.frs_rule_to_sql` (an explicit rule
   `channel_width` → `BETWEEN`, NULL fails). The bridge is now 31/2560 = 0.0121, matching
   `bridge_bt.csv`. The 55 NULL-width river-poly rows split 21 CH, 30 BT and 4 DV (47
   distinct locations); UPCE 11, LPCE 10 and TABR 10 make up the 31, as the doc says.
3. Availability groups on the raw `gradient` and `channel_width`, and both sides bin through
   the same `cut()`.
4. `BT_any_dv` has 5,104 distinct locations after `distinct(loc)` (5,382 − 278).
   `distinct()` keeps the BT row, deterministically, because the post-`slice` order is by
   `obs_species`.
5. The obs stamp now reads fresh's run log and flags dirt. See the FISS gap above.
6. `ORDER BY o.observation_key` plus `arrange()` before `slice(1)` makes the dedup
   deterministic.
7. The `independent` column is correct. The FIELD_MEASURMENT median |diff| of 0.003 m
   supports the "same sites" explanation.

## Checked and fine

- **Config and tests.**
  - The `default_tuned` checksum `sha256:f6959055…075` matches
    `digest::digest(file=, algo="sha256")`.
  - `lnk_config_verify(lnk_config("default_tuned"))` shows no missing file and no byte or
    shape drift. `audit_configs.R` §1 shows 0 drift, and §2 shows `default_tuned`
    structure identical.
  - `diff default default_tuned` gives exactly one cell.
  - `NOT_CRAN=true devtools::test(filter="lnk_config")` gives FAIL 0 / PASS 171.
  - The new cell-pinning test fails toward failure when nothing differs (it errors on a NULL
    `diffs`).
- **Links.** `../../../../research/habitat_thresholds.md` resolves from
  `inst/extdata/configs/default_tuned/`. Every link in `research/README.md` resolves, and
  every file in `research/` is indexed.
- **Doc numbers that match the CSVs.**
  - Ledger 1,745 / 2,560.
  - Accessible n 226 / 497 / 2,443.
  - CH spawning ratios: < 1 at 2–3 %, 0.38 / 0.49 / 0.46 at 3–5 %, and 0 observations in
    (0.05, 0.055] over 2,139.6 km.
  - 14 observations at 3–4.5 %.
  - Floor bin ratio 2.78, holding 41 %.
  - No CH spawning observations at 4–6 m over 3,367.8 km.
  - BT selection ~0.6 from 5 to 12 %, 0.37 and 0.19 above that; DV rearing 1.37 / 0.70.
  - BT width selection ≥ 1 from 3 m.
  - DV floor 2.2.
  - BT NULL-width ratio 0.084.
  - 98 % / 99 % accessible, UHC 636, DV in 140 of 158 BT WSGs, 45 `n_cand` ties.
  - Window P95s 0.044 vs 0.042 and 0.125 vs 0.141.
  - Every FISS aggregate quoted: n 15 / 16, P95 0.106, P5 1.9, medians 5.5 m / 2.5 % vs
    1.46 m / 8 %, 18 / 81 sites.
- **`status_one()` against the real `rules.yaml`.**
  - The CH and BT **rear** rule 1 has no `in_waterbody`, so edge-1000/1100 obs inside
    wetlands are threshold-tested there but labelled `waterbody_rule` here. All 9 such BT
    obs have `rearing = TRUE`, so the bridge cell is unaffected.
  - The lake-segment edges (1200/1300/1450) are not in the rule-1 list.
  - No observation segment has a negative or NULL gradient, so the `BETWEEN 0 AND max`
    lower bound never bites.
- **Joins.** `fwa_waterbodies.waterbody_key` is unique (538,743 / 538,743), so neither
  waterbody join fans out.
- **FISS.** Only 4 FISS sites list DV or char and not BT, none of them with measured width,
  so labelling DV captures as BT-absent does not move `fiss_presence.csv`.
- **Literature.** The doc's "Woll Table 17 rates 3–7 % as low suitability" is correct
  against the source text (scale 0–4, with class 1 = gradient 3–7 %). The Isaak, Cooney &
  Holzer, Busch, Beamer, Agrawal, Rebellato, Hagen and McPhail statements match
  `literature.md`.
- **Public-repo hygiene.** The diff has no absolute home paths, host addresses or FISS
  site rows.
