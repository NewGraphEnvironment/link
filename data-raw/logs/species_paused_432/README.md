# Pausing KO and RB in `default`: what it does to segmentation (#432, #433)

Two builds of six groups under `default`, the same inputs and fresh (0.52.0,
`245c8d8d`), one behaviour apart, on m4's local fwapg, 2026-11-02:

- **before**, schema `zz432_pre`, run_uid `432_pre`: link `07203cde` (KO and RB modelled)
- **after**, schema `zz432_post`, run_uid `432_post`: link `a6942b5d` (KO and RB paused)

Each arm ran `wsg_run_one.R` then `wsg_recompute_one.R` per group from its own
worktree (`arm.sh`; `arm_pre.txt`, `arm_post.txt` hold the minutes), with
`LNK_GUARD_DOWNSTREAM=warn` because each schema holds only these six groups.
KOTL's recompute fails its downstream-state post-condition in both arms (a dam
below it is in a group not built here); its model-time outputs are compared.

Groups: KOTL (KO present), SALR and KETL (RB present, BT absent), NBNK (RB only
through the CT/DV/RB presence group), MURT (only RB, a paused species) and BULK
(control: BT present, so RB's 25 % class stays).

`compare.R` writes:

- `summary.csv`: segments, break positions only one side has, barrier and override rows that differ, KO/RB habitat rows left after
- `km.csv`: accessible, spawning and rearing km per species each side, and the km whose flag differs on a measure-overlap join
- `obs.csv`: fish records of modelled species (and DV) on a segment that changed, and the gradient shift there

## Result

| group | segments before | after | breaks gone | breaks new |
|---|---:|---:|---:|---:|
| BULK | 42,556 | 42,458 | 98 | 0 |
| KETL | 44,057 | 41,394 | 2,672 | 9 |
| KOTL | 39,411 | 38,287 | 1,127 | 3 |
| MURT | 15,219 | 14,403 | 816 | 0 |
| NBNK | 3,939 | 3,914 | 25 | 0 |
| SALR | 10,676 | 10,615 | 61 | 0 |

- Barrier and override rows are identical in all six groups; no KO or RB habitat row is left after.
- Accessible km is unchanged for every modelled species in every group.
- Habitat moved in two groups: KOTL BT rearing 20.9 km flips (2,161.3 to 2,166.7 km net), spawning 2.6 km; KOTL WCT rearing 9.8 km (2,191.3 to 2,186.5), spawning 3.4 km; KETL WCT rearing 0.4 km.
- Fish records on a segment that changed: KOTL 33 of 1,473 (median gradient shift 0.012, largest 0.083), KETL 4 of 47 (0.030); none in BULK, NBNK or SALR. MURT has no record of a modelled species.

## The clearing and the verifier

- Re-modelling SALR with the after code into the before schema (run_uid `432_clear`) took its `streams_habitat_rb` rows from 10,676 to 0, its CH rows to its new 10,615 segments, and its near-river rows from 954 to 947.
- `stale_check.sql` is `study_area_verify.sql`'s new assertion alone (the full verifier stops first at KOTL's missing recompute): it passes on both arms, fails on three RB rows planted for SALR in the after schema, and passes again once they are removed.

The two scratch schemas stay on m4 (`zz432_pre`, `zz432_post`) until the next provincial run, so `compare.R` can be re-run; `zz432_dev` (the first MURT build) was dropped.
- MURT alone (run_uid `432_murt`, at the review-fixed HEAD) models, recomputes and passes the full `study_area_verify.sql` with `expected_n=1` (`verify_murt.txt`): a group whose log lists no species passes every per-group check.
