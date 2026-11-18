# Backlog move 4: default's presence table as bcfishpass's copy plus an overlay (#472)

## Outcome

One release, 0.86.0, covering #431, #436 and #292, with #402's decisions written as overlay rows. `default`'s presence table is now bcfishpass's file byte for byte (3bd2824), synced weekly. Its 122 departures (110 added, 10 removed, UTRE CH and LARL GR kept absent) and the four `ko` cells are rows of `wsg_species_presence_overlay.csv`, each reason carrying the decision, the review's rule and the story's opening. `observation_exclusions_link.csv` excludes three records bcfishpass does not list, read as text with the copy through one row helper. `presence_groups.csv` holds `lnk_presence()`'s groups. No output token moved, so the `acc` row the issues expected was not needed. #497 (rainbow trout's return) was filed on the operator's word, and #402's body now lists what is left.

What was learned: the plan review and code-check round 1 found the same mechanism three ways. Readers written when the copy was the only file each relied on something true only of it: read.csv typing over a large file, a `$` lookup with no longer sibling key, "data_error rows" meaning bcfishpass's list. Round 3 found the last instance, in a sibling script, and the loop ended on an enumeration of all 15 exclusion readers by role. Two process slips are in `findings.md`: a mutation check restored with `git checkout`, which discarded an uncommitted edit, and two commits made before reading a failing dictionary test.

## Measurement

- The loaded `default` and `default_tuned` presence species cells digest identical before and after (`2d9f3856…`, computed at the merge-base). All five live bundles resolve to the same tokens (`acc-v6`, `acc-bcfp-5`).
- ADMS, BULK and GUIC built at `main` and at the branch (m1, scratch schemas): 53 of 54 table and group pairs identical. GUIC's `access_ch` goes 2 → 1 on 227 segments (52.3 km), where its excluded CH record stood. This turned "the conversion changes nothing" into a measurement.
- Presence check: 233 flags, down from 351. The 111 adds and 9 of the 10 removes drop out, and MESI SK with them. VICT DV, FINA ST, MFRA BT and UFRT ST read differently since #470.
- A wrong turn kept for the record: the first `main` try stalled 34 min in ADMS's near-river walk (no statement bound). It was recorded as #487's first real stall: CPU-bound, no waits, begun while another session read the database. The bounded re-run took 2.5 min.

## Evidence

`data-raw/logs/presence_overlay_431/` (its README); `data-raw/logs/stall_sample_487/20261118_*`; reviews in this directory (`review-plan.md`, `review-round*.md`).

## Owed

- The pre-run gate runs again before the next provincial run (`R/` and `inst/extdata/` changed)
- GUIC, and the groups whose code 2 or lifts read its records, re-model at the next provincial run (its CH exclusion; MESI SK and KOTL ST are absent cells, so their exclusions move no model output; no token moves)
- `config_hash` moved for `default`, `default_tuned`, `default_minimal`, `default_parent` and `bcfishpass`: earlier builds read as another bundle in `recompute_readers_check.R` and the export until re-modelled (already owed: the current builds are `acc-v5`)
- The upstream offer of the three exclusions, if you give the word

Closed by: PR (to be opened from branch `472-backlog-move-4-default-s-presence-table`)
