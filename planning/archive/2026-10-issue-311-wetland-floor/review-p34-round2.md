# Review p34, round 2 (df1362f + working-tree fixes, pin v0.39.0 / floor 0.38.0)

## Round-1 fixes: all five are correct

- **obs.R prefix filter.** `left(coalesce(o.source,''),17) <> 'Releases Database'` is right: the string is 17 characters, the same as the validator's `left(coalesce(source,''), length(prefix))` (R/lnk_habitat_validate.R:686).
  - I re-ran the B->C count read-only: 2,265 on rearing and 3 lost. `obs_*.csv` are byte-unchanged, which is consistent with that.
- **bcfishpass departure.** `vs_bcfp_pct_B` recomputes from `rear_km_B` and `bcfp_rear_km`.
  - B->C at full precision: NATR BT 1.11, BULK ST 1.06, PARS BT 1.01, BULK CH 0.46 points. So "at most 1.1" holds, and so do "+1.7 % to +0.6 %" and "+13.8 % to +12.8 %".
  - A->B maximum is 0.12 (PARS BT), which rounds to the quoted 0.1.
  - The regenerated `summary.csv` differs only by the added `vs_bcfp_pct_B` column.
- **CLAUDE.md #307 fact.** It is rewritten to past tense (but see finding 4 about the number it keeps).
- **"Both wetland rear rules".** The wording appears with the stream-rule caveat in CLAUDE.md, the research section, the bundle README and the dictionary.
- **"Species-locations".** Applied in CLAUDE.md, the README and the research B->C bullets.

The other numbers also recompute from `measure.csv` / `summary.csv` / `obs_*.csv`:
- the B->C table, including the 1050/1150 vs other-edge split, e.g. BULK ST 6.410 / 17.354 and NATR BT 27.277 / 6.815;
- 198.777 km and 2,078 segment-species;
- 2,265 = the sum of `n_obs_rear_from`;
- the A sub-floor figures;
- "at most 75 / 3.6 km".

The pin is safe. `.lnk_fresh_floor()` reads the DESCRIPTION floor, so a cypher still on 0.36.2 now fails the preflight's `version_ok`, and CLAUDE.md's "hard-fails otherwise" holds. fresh 0.39.0 adds nothing to classification over 0.38.0, so the floor at 0.38.0 is sound.

## Findings

- **[doc, false]** `tests/testthat/test-lnk_rules_build.R:190`: the comment still reads "so the declared floor bounds all wetland rearing".
  - This is round 1's defect class, in a file round 1's fix did not reach (committed in 0ca706b).
  - The 0ca706b commit message carries the same phrase. It is immutable, so correct it in the PR body and NEWS rather than repeating it there.

- **[doc, overclaim]** `data-raw/logs/wetland_floor_311/obs.R:5` and `README.md` ("It uses the validator's default filters") still claim more than the script applies.
  - `lnk_habitat_validate()` also drops records flagged `data_error` / `release_exclude` in `loaded$observation_exclusions` (`default` declares it). It also counts one location per species × `blue_line_key` × metre.
  - obs.R does neither: it uses DISTINCT on the raw measure.
  - Two such flagged A/B records sit in these WSGs (ADMS SK 1, BULK ST 1). I re-ran with both the exclusions and metre binning applied: 2,265 on rearing and 3 lost, unchanged. So the numbers stand.
  - The sentence is the same kind of claim as round 1's first finding: it was written from the validator's description, not its code.
  - Fix: name the two filters it applies, or apply the exclusions too.

- **[doc, overclaim]** "A → B reproduces fresh's published numbers exactly" is not true of one row of its own table.
  - The claim appears in the README Results heading, `research/habitat_thresholds.md` ("It reproduces fresh's published numbers exactly"), CLAUDE.md:22, and the #310 issue body ("matches exactly").
  - In the row "NATR BT wetland-flow rearing in wetlands < 1 ha", fresh gives ~26.4 km (307 segments, from persisted `fresh_default`; fresh `data-raw/logs/rear_wetland_floor_237/natr_bt_edge.csv`) and this build gives 26.605 km. That is 0.2 km above what fresh labels an upper bound.
  - The segmentations differ: persisted NATR BT has 10,606 rearing segments, this build 10,657 under A.
  - Five of the six rows match. Say "five checks match exactly; the sub-floor km is 26.6 against fresh's 26.4 on a different segmentation", or drop "exactly".

- **[doc, stale number]** `CLAUDE.md:73-74` reads "The buckets still ignore spawning connectivity (16,651 of 16,652 BT `lake_rearing` rows are not `rearing`)".
  - "still" now presents a count taken under fresh < 0.37 (`research/habitat_thresholds.md:1137`, `fresh_default`) as current under the v0.39.0 pin.
  - On this branch's own builds, NATR BT is 1,083 of 1,083 under B and C, and 683 of 683 under A (`zz311_snap.natr_*`).
  - The qualitative fact holds; the number is sourced from the old version. Either date it ("under fresh 0.36, in `fresh_default`") or drop the count.

- **[doc, wrong range]** `research/habitat_thresholds.md` (the operator-call bullet) says "0.13–0.62 km per species under C on BULK, NATR and PARS".
  - BULK CO is floored (0.5 ha) and has `rear_km_subfloor_C` = 0, so the range is 0–0.62.
  - Round 1's own wording ("0.13–0.618 km per floored species") had the same gap.

- **[doc, stale present tense]** `research/habitat_thresholds.md`, "What changed": "**The 1050/1150 wetland-flow rear rule has no floor of its own.**"
  - In `default` it now has one (that is #311). Use "had", or "fresh 0.38.0 left it unfloored".

- **[doc, scope]** `RUNBOOK.md:720-731` is the one doc of the five without the stream-rule caveat.
  - The heading reads "**A wetland floor bounds `rearing` as well as the bucket**". It does not say that mainlines in sub-floor wetlands still rear through the `[1000,1100,2000,2300]` stream rule (0.13–0.62 km per species under C here).
  - "Every 1050/1150 line sits in a `fwa_wetlands_poly` polygon (measured on NATR, PARS, ADMS and BULK), **so the type adds no filter beyond the floor**" generalises a four-WSG result. Province-wide, the W type drops 40 edge-1050 lines with no `waterbody_key` (6.6 km). The code comment at R/lnk_rules_build.R:354 and the research caveat both say so; the RUNBOOK, which is the mechanics document, does not.

- **[label, harmless]** Two remaining "locations" phrasings:
  - `research/habitat_thresholds.md:1182` "and no observation location". The value is 0, so it is true either way.
  - `planning/active/progress.md:13` "3 of 2,265 observation locations".
  - The df1362f commit message also says "observation locations" (immutable).

## Mechanism

Round 1's defects, and every finding above, have one source: **prose written from intent or from a description, then copied, not derived from the artifact at the moment of writing.** The fixes then repaired each quoted instance rather than grepping every file for the claim. It took four forms:

1. **A claim about code taken from that code's description.** Examples: the "Releases Database" exact match, and "same filters as the validator's defaults", which still omits exclusions and metre binning.
2. **A number taken from the neighbouring column or interval.** Examples: A->C quoted as B->C, and 16,651/16,652 carried across a version change.
3. **A scope word asserted without checking the population.** Examples:
   - "all wetland rearing" (round 1);
   - "exactly";
   - "0.13–0.62 per species", which misses BULK CO;
   - "the type adds no filter", which ignores the 40 province-wide lines;
   - "locations", where the count is species-locations.
4. **A version-dependent fact left in present tense when the pin moved.** Examples: CLAUDE.md:73, research "has no floor of its own", and RUNBOOK and CLAUDE.md before round 1.

### Where it reaches

- **Committed docs:** CLAUDE.md (lines 22, 73), RUNBOOK §7, `research/habitat_thresholds.md` #311 section, the `wetland_floor_311` README and obs.R header, the bundle README, `dictionary_dimensions.csv`.
- **Code comments and tests:** `tests/testthat/test-lnk_rules_build.R:190`.
- **Session notes:** `planning/active/progress.md`.
- **Outside the tree:**
  - commit messages 0ca706b and df1362f (immutable: correct them in the PR body and NEWS);
  - the #310 issue body ("matches exactly", "a declared floor bounds both wetland rear rules", which is fine);
  - the NEWS entry still to be written at release, which should be derived from the CSVs rather than from these docs.

## Verdict

No failure, data-loss or security issue. Every committed number recomputes. The findings are doc overclaims and stale wording; fix them before the PR.
