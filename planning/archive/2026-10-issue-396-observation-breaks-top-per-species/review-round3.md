# Code-check round 3 (#396): observation breaks

Read only. Nothing was run and no database was touched.

## Checklist read

- **code-check.md**: the prose of every H3 under `## Mechanisms`, all 14 (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers; Restore the bug and prove the guard fires; A shared working tree; A wrapper's exit is not the work; Zero-length, empty, and unset; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice). Table rows skipped. Not read: the 23 H3s under "Rules that stand alone", Security, and Spreadsheets/PDFs, which cover tools this diff does not use.
- **code-check-r.md**: 9 of 111 read in full (Postgres row order; `sprintf("%g")` into SQL; `information_schema` lookup by literal name; Rscript reads a script as it runs; `function(...)` mock hides arguments; testthat counts an uncaught error under `error`; `$` partial match; `nzchar(NA)`; Under `R CMD check` tests run against the installed package). 102 not read: their index lines name tools or shapes this diff does not use.
- **code-check-shell.md**: 4 of 67 read in full (`local` reading its own assignment; a failed `cd`; psql `:'var'` in dollar quotes and `\quit N`; macOS awk with multibyte text). 63 not read.
- **code-check-spatial.md**: 2 of 93 read in full (FWA `upstream_route_measure` misses the next start; FWA main flow is not edge type 1000). 91 not read.

## Mechanism

Every round so far has found a case of one assumption: **removing an observation break only deletes a boundary, and the boundary sits at the record's position.** The code stacks three tolerances, and the assumption ignores the interaction between them:

1. **Metre rounding.** A break, and so a segment start, sits at `round(raw)`. The walk compares the **raw** record or barrier measure with that start.
2. **Cut order.** `frs_break_apply()` cuts only more than 1 m from the current ends, one source after another. So a later source within 1 m of an observation cut is suppressed while the observation stands, and **released** once it goes. Removing an observation can therefore *move* a boundary by 1 m, or *create* one 2 m from a kept cut.
3. **The walk's 1 m equivalence.** A feature within 1 m of a segment's start, on either side, counts as upstream (observations) or downstream (barriers).

Round 1 #1 and round 2 #4 found this assumption at work on the barrier / `access = 0` side, and round 2 #5 found it on the observation's own top. **No round has yet applied it to the code-2 / code-1 boundary.** There, a released later-source break (a crossing, a habitat endpoint, or a gradient break for a species it does not block) gives 2 to 1 changes: 1 m slivers, and whole segments. The RUNBOOK, `code2_class.sql`, `exact_set.sql` and `pre_post_diff.R`'s stated expectation all say these cannot happen.

Worked case (case **b**), checked against the 1 m rules above. The line is one FWA segment, [0, 1000].
- X's top is at raw 500.2, so T = 500.
- Y has a non-top record at raw 501.1 (R = 501), and its top at 800.3.
- A crossing sits at raw 502.3, rounded to 502.

| | cuts | X on [502, 800) |
|---|---|---|
| `all` | 500, 501 and 800; the crossing at 502 is 1 m from 501, so it does not cut | segment [501, 800): \|501 − 500.2\| = 0.8 ≤ 1, so 2 |
| `top_per_species` | 500 and 800, then the crossing at 502 (2 m from 500) | segment [502, 800): 502 − 500.2 = 1.8 > 1, so 1 |

So 298 m go from 2 to 1.

Case **a**, the sliver form: R lies more than 1 m above X's flip, with a later source at g = R − 1. Under `all`, X flips at R. Under `top_per_species`, X flips at R − 1, and [R − 1, R) goes from 2 to 1.

## Enumeration

| place | depends on | verdict |
|---|---|---|
| `R/lnk_pipeline_break.R:169-185` builder SQL | rounding (`round(max)` = `max(round)`) | right |
| `R/lnk_pipeline_break.R:161-162` subset claim | rounding is monotone | right |
| `R/lnk_pipeline_break.R:28` table row, `:154-159` mode doc ("turns … at the first cut more than 1 m above its top") | raw top against rounded start | right as stated. It does not say that the first cut can be a later source a removed record had suppressed (case b) |
| `R/lnk_pipeline_break.R:18-24` `break_order` doc (round 2 #6) | which sources gate access | right |
| `inst/extdata/configs/bcfishpass/config.yaml:96` "Remove an entry to skip both segmentation and access-gating" | same claim as round 2 #6 | **wrong**: pre-existing, and outside the hunk, but in a file this diff edits. It is the sentence round 2 corrected in roxygen |
| `inst/extdata/configs/default/config.yaml:116-128` comment | first cut more than 1 m above the top | right, and loosely worded ("mostly shortens") |
| `R/lnk_config.R:388-403`, `.lnk_observation_breaks_check()` | a closed set | right |
| `R/lnk_habitat_validate.R:43-51` attach rule | the validator's `< 1`, against the walk's `<= 1` | rule right. "most points sit inside a segment" under `top_per_species` is not measured; `bias.R`'s `share_on_segment_start` measures it. LKEL keeps 59 % of positions |
| `R/lnk_habitat_validate.R:54-65` buffer | `s2.drm >= seg_drm AND < m + buf` | right |
| RUNBOOK:200-203 "own top break never changes its own code" | raw top against rounded start, ±0.5 | right |
| RUNBOOK:203-206 "first cut more than 1 m above its top … under `top_per_species` the next of FWA ends, other break sources and other species' tops" | cut order | partly. The other sources that count include ones a removed record had suppressed (released), which can lie *below* where `all` put the flip (case b) |
| RUNBOOK:211-215 "Where a removed record lay more than 1 m above X's top" | raw against rounded | imprecise: the test is the record's rounded position R > raw_t + 1, not its raw measure |
| RUNBOOK:215 "That is 1 to 2, never 2 to 1" | release | **wrong** (cases a and b) |
| RUNBOOK:216-219 exact set "keeps code 2 exactly" | release, and FWA ends | **wrong** (see finding 3) |
| RUNBOOK:221-228 1 m boundary paragraph | release | right for blocked/open, `has_barriers` and the token. It leaves out 2 against 1, which the same release moves |
| RUNBOOK:230-237 whole-segment paragraph | rounding plus release | right |
| RUNBOOK:239-240 omitting `observations` | — | right |
| RUNBOOK:242-245 validator | — | right |
| `cuts.sql:9-13` header ("a position cuts here when … more than 1 m from … every other break source") | cut order | **mislabelled**: observations are the first source, so an observation within 1 m of a later source still cuts and the later source is the one suppressed. The count is right as "adds a segment net of later sources", but `positions_cutting`, `tops_cutting` and `tops_on_other_cut` (lines 57-59) are named for something else |
| `cuts.sql:49,61` `removed_saving_a_segment` | release | right, apart from a released source that is itself suppressed by a kept top or FWA end (rare, a small undercount) |
| `cuts.sql` FWA ends from `upstream_route_measure` | sub-mm FWA gap | immaterial at 1 m |
| `province.sql` | per-group tops (round 1 #2) | right |
| `code2_class.sql:22,46,51` `tops_sp` rounded, `c.m > t.m + 1`, `r.m > n.m + 1` | raw top, which `exact_set.sql` was fixed to use | **wrong** (finding 2) |
| `code2_class.sql:1-4` "The one access change … Only 1 -> 2" | release | **wrong** (cases a and b; finding 1) |
| `code2_class.sql:36-44` `cut` list | release and suppression | ±1 m on `next_m`: it lists later sources that are suppressed and leaves out ones that are released |
| `code2_class.sql:63-71` `fwa_upstream` on other lines with a rounded `o.m` | measure is irrelevant across lines | right |
| `exact_set.sql:27` `p.m > t.raw_t + 1` | raw against rounded | right (round 2 fix) |
| `exact_set.sql:1-9` "keeps every flip where `all` puts it" | release, FWA ends | **wrong** (finding 3) |
| `redundancy.sql` | flagged moot | right as labelled |
| `pre_post_diff.R:11` "no 2 -> 1 (slivers included)" | release | **wrong** (finding 1) |
| `pre_post_diff.R:95` `b_at_top`, `abs(round(top) - b.dm) <= 1` | raw against rounded | fragile: an AFTER segment starting at an FWA end in (T + 1, raw_t + 1] reads 2 and is counted as `1_to_2_elsewhere` |
| `pre_post_diff.R:96-101` `near_barrier` | which barriers gate | fragile (finding 4) |
| `pre_post_diff.R:103` sliver `< 1.01` | slivers are exactly 1 m, plus up to 3.93 mm of FWA overshoot | right |
| `pre_post_diff.R:118` `km_acc_2_to_1`, no sliver or release split | release | its expectation is wrong (finding 1). The column itself is a correct detector |
| `pre_post_diff.R:139-145` coverage tolerance | — | right |
| `bias.R:106-112` attach | the validator's `< 1` | right (it matches the validator) |
| `bias.R:113-118` FWA gradient lookup | FWA mm gaps | a NULL drops a site silently; immaterial |
| `build_obs.R` | the pipeline's own prep helper | right |
| `run.sh` | — | no rounding dependence; fine |
| `tests/testthat/test-lnk_pipeline_break.R` live test (100.4 → 100, 520.6 → 521, 300.2 → 300) | rounding | right |
| `tests/testthat/test-lnk_pipeline_break.R` mocks and load check | — | right |
| `tests/testthat/test-lnk_habitat_validate.R` new test | attach inside a segment | right |

## Findings

- **[bug] RUNBOOK.md:215; `data-raw/logs/observation_breaks_396/pre_post_diff.R:11`; `code2_class.sql:1-4`.** All three say `top_per_species` gives "1 to 2, never 2 to 1", with "no 2 -> 1 (slivers included)" and "Only 1 -> 2". A released later-source break gives 2 to 1 in two shapes:
  - **(a) a 1 m sliver.** g = R − 1, with R a removed record more than 1 m above X's flip.
  - **(b) a whole segment.** A removed non-top record at R = T + 1, with X's raw top ≥ T, and a later-source break at T + 2. The worked case above loses 298 m.

  This is round 1 #1 and round 2 #4 one axis over: code 2 against 1 instead of blocked against open. `km_acc_2_to_1` (line 118) has no sliver or release split, so either shape reads as a failed expectation once the diff runs. Fix: state both shapes in the RUNBOOK and the script header. Split `km_acc_2_to_1` the way `near_barrier` splits the 0/open changes: flag a piece when the AFTER segment start is a non-observation break within 1 m of a removed observation position, or 2 m above a kept top with a removed position between.

- **[bug] `code2_class.sql:22,46,51`.** The flip tests use the **rounded** top (`max(round(m))`), while the walk compares the **raw** record with the start. `exact_set.sql` was corrected to `raw_t` in round 2, and this file was not.
  - It misses a removed R = T + 1 when raw_t < T. Both T and T + 1 cut under `all` (same call), and T + 1 > raw_t + 1, so the BEFORE piece read 1. AFTER, [T, next) reads 2, so this is a real and possibly long 1 to 2 change that `code2_class.csv` leaves out.
  - Its `next_m` window (`c.m > t.m + 1`) is off for FWA ends in (raw_t + 1, T + 1] or (T + 1, raw_t + 1], which gives both false and missed flips.

  This is the predicted side that `pre_post_diff`'s `km_acc_1_to_2_at_top` is compared against, so the two will disagree for a reason the record does not name. Fix: carry `max(raw_m)` and test `r.m > raw_t + 1` and `c.m > raw_t + 1`.

- **[fragile, a measurement] `exact_set.sql:1-9,24-29`; RUNBOOK:216-219.** The claim is that keeping, per species, the lowest observation position above raw_t + 1 "keeps every flip where `all` puts it". That is false three ways:
  1. **Release.** In case (b), dropping R = T + 1 (in no species' exact entry) releases the later source at T + 2, and X flips there instead of at `all`'s next cut.
  2. **An exact position that does not cut.** If the exact position lies within 1 m of an FWA end at or below raw_t + 1, it does not cut, and the flip moves to the next observation position, which is not in the set.
  3. **Not minimal.** Where an FWA end or a non-observation cut lies in (raw_t + 1, p*], X already flips there under both builds, so p* is not needed. `positions_exact` (49, 58, 157, 126, 25) is therefore an upper bound on the set the comment describes, not "the break set that keeps code 2 exactly".

  The research doc reports this number to the operator as the alternative, so say "upper bound, up to released breaks" or compute it against the line's FWA ends and the `:wk` sources the way `cuts.sql` does.

- **[fragile, a measurement] `pre_post_diff.R:96-101` `near_barrier`.** The check reads every row of `<post>.barriers` whose `blocks_species` holds the species. That includes PSCIS, CABD and modelled crossings, which block all species in that table, and natural barriers lifted by an override. Access is gated only by `barriers_<sp>_access`: GRADIENT, FALLS, SUBSURFACE_FLOW and USER_DEFINITE, minus overrides (`R/lnk_barriers_views.R:196-213`). Crossings are themselves a break source, so many changed pieces start within 3 m of one. The "`*_elsewhere` must be 0" control is then weaker than the mechanism it tests, because it can absorb an unexplained 0/open or `has_barriers` change next to any crossing. Fix: filter `x.barrier_source IN ('GRADIENT','FALLS','SUBSURFACE_FLOW','USER_DEFINITE')`, or read `barriers_<sp>_access`.

- **[fragile] `cuts.sql:9-13,57-59`.** The header derives "a position cuts" from "observations are the first break source", but that premise implies the opposite. An observation within 1 m of a later source still cuts; the later source is the one suppressed. The counts are right as "adds a segment beyond the other sources", but the column names (`positions_cutting`, `tops_cutting`, `tops_on_other_cut`) and the header sentence describe frs_break_apply behaviour the code contradicts. A reader quoting `positions_cutting` as "observation positions that cut" undercounts.

- **[fragile, doc] `inst/extdata/configs/bcfishpass/config.yaml:96`.** "Remove an entry to skip both segmentation and access-gating from that source" is the claim round 2 #6 corrected in the roxygen. It is pre-existing, but it sits in a file this diff edits, and it now contradicts `R/lnk_pipeline_break.R:18-24`.
