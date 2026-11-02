# #415: a minimal network for tuning, first PR (bundle, token, proof scripts)

## Outcome

`default_minimal` (`extends: default`, schema `fresh_default_minimal`) cuts streams only at gradient barriers where a modelled species' access changes, falls and user-definite barriers, and resolves to `cut-min` with `default`'s other three tokens. `.lnk_config_merge()` now refuses a child's `break_order: ~`, the only R change. `data-raw/logs/minimal_breaks_415/` holds `run.sh` and `proof.R`, which compare the two networks on measure-overlap pieces and stop on a defect. Nothing has been modelled for evidence. Three premises turned out wrong along the way. The overlay under-applies on this network rather than over-extending. A full segment can straddle a minimal cut by up to 1 m, so containment is not the test. And the network is not independent of the fish records, because gradient positions are reduced after observation lifts: code-check round 1 found this, and the docs and the issue now say so. PR 437 (#432) merged during the run, so the planned `0.76.0` became `0.77.0` and the token test compares with `default` rather than naming an `acc` token. Code check: three rounds, ended by round 3's enumeration of 90 prose claims and every stop in both scripts (`review-round3.md`); round 2 found defects inside round 1's fixes, including a gate route that could not run.

## Measurement

ADMS smoke runs only, which test the scripts and are not evidence. At `c86e8871`: 15,716 full and 11,920 minimal segments on 5,475.8 km; 8,434 minimal cuts all matched exactly on the full network; no access difference on any piece; 6 falls, 6,788 FWA base segments and 1,640 gradient positions name every minimal break. An earlier smoke, before pausing KO and RB: `dam_dnstr_ind` true on 15.996 km only on the minimal network and 0.654 km only on the full one, which moved the docs from "shifts up to the next cut" to "moves either way"; CO overlay under-application 7.19 km of 122.1 km against 0.05 km on the full network; 488 of 615 bcfishobs records fall in `knw_link_place()`'s start window on the full network and 31 on the minimal one, so it runs on its fallback there. `proof.R` with the schema names swapped stopped on three guards, and on a dirtied tree on one.

## Evidence

No run logs committed: the smoke output is not evidence. The scripts are `data-raw/logs/minimal_breaks_415/`; the real run commits its CSVs beside them.

## Owed

- Second branch (#432 merged 2026-11-02, during this run): the proof builds, `research/minimal_network.md` (or a section of `bcfp_segmentation_parity.md`), read beside #433's measurement in `research/species_paused.md`, and the parent-attribute issue drafted from the proof (how far lifts move the cuts, measured with the records left out: round 1 of the code check found gradient positions are reduced after observation lifts, so the network is not independent of the records; the `streams_parent` table, its `grad` token, and whether the Atlas-line reading gets one), with knowledge#120's mechanics check named as its acceptance.
- Pre-run gate (#372) on `fresh_default_minimal` before the minimal provincial run.

Closed by: PR on branch `415-a-minimal-network-for-tuning-with-parent` (first of two; #415 stays open).
