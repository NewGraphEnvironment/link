# Findings — tunnel-free `lnk_compare_mapping_code` + orchestrator (#175)

## Issue context

#175 (updated 2026-05-24): promote `with_mapping_code` flag → stand-alone `lnk_compare_mapping_code()` export, sibling to `lnk_compare_rollup`. Post-#200 refinement: make the reference the **local snapshot** `fresh.streams_vw_bcfp`, not the `:63333` tunnel. Also (folded in): the provincial orchestrator's tunnel-free + M1-dispatch + post-consolidate cross-WSG recompute. Supersedes #167 (tunnel-drops → autossh; tunnel-free obviates it).

## Mechanism (mapped this session)

- **Existing compare** (`R/lnk_compare_wsg.R`): `.lnk_compare_wsg_mapping_code_diff(conn, conn_ref, …)` diffs link's `<persist>.streams_mapping_code` vs `bcfishpass.streams_mapping_code` over the **tunnel** (`conn_ref`, `:63333`), joined on `segmented_stream_id`. Returns per-species `wsg, species, total_segs, match_pct, n_diffs`. `lnk_compare_rollup` is the km-rollup sibling (also tunnel, queries `bcfishpass.habitat_linear_<sp>`).
- **Tunnel-free swap**: the snapshot (`snapshot_bcfp.sh --with-bcfp-views`) already loads bcfp's published streams output into local `fresh.streams_vw_bcfp` (province-wide, has `mapping_code_<sp>` + `blue_line_key` + `downstream_route_measure`). So the compare = local join, same DB, no `conn_ref`.
- **Join key**: link's `<persist>.streams_mapping_code.id_segment` is a local surrogate (≠ bcfp `segmented_stream_id`). Join via `<persist>.streams` to get `blue_line_key` + `downstream_route_measure`, then match `fresh.streams_vw_bcfp` on `(blue_line_key, round(downstream_route_measure,1))`. This is the validated query: PARS BT 98.95%, LFRA BT 97.77% / CO 97.90%.
- **Reference build verified**: `s3://fresh-bc/bcfishpass/log.json` → `v0.7.15-14-ge12c1a5` (2026-05-20 rebuild); our snapshot matches. Next rebuild Tue 2026-05-27.

## Orchestrator gaps (predates #200 + tunnel-free)

- `wsgs_run_pipeline.sh` pre-flight hard-requires `:63333` + `PG_PASS_SHARE` (lines ~179-181). M4-centric: hardcoded `ssh m1` (229/280/284), "snapshot on M4+M1", LPT host model `m4/m1/cy`.
- `wsg_compare.R` → `lnk_compare_rollup(reference="bcfishpass")` connects `conn_ref` to the tunnel (lines ~44-46). Each host runs compare per-WSG → each needs the tunnel.
- **Cross-WSG `;DAM` gap**: `wsgs_run_host.R` computes mapping_code per-WSG against only the host's local bucket barriers, **before** consolidate → cross-WSG dams in other buckets invisible. No post-consolidate recompute. Fix = Step 9b recompute on the merged schema (the two-pass), then one tunnel-free compare. Simplification: cyphers run+persist only (no compare, no tunnel); dispatcher recomputes + compares once.
- `cypher_prep.sh` installs link from `main` by default → cyphers get v0.40.4 automatically now that #200 is merged. ✓ (no branch-push needed).

## Study areas (the validation scope)

From the `fish_passage_*_reporting` repos' `wsg_code`/`wsg` params:
- **Peace** (`fish_passage_peace_2025_reporting` index.Rmd): CARP, CRKD, FINA, FINL, FIRE, FOXR, INGR, LOMI, MESI, NATR, OSPK, PARA, PARS, PCEA, TOOD, UOMI (16)
- **Fraser** (`fish_passage_fraser_2025_reporting` index.Rmd): LCHL, NECR, FRAN, MORK, UFRA, WILL, TABR, LSAL (8)
- **Skeena** (`fish_passage_skeena_2024_reporting` `0160-load-bcfishpass-data.R`): BULK, MORR, ZYMO, KISP, KLUM (5)
- 29 focal → **52 with downstream-closure** (LFRA, MFRA, UPCE, LPCE, LBTN, LSKE, USKE, MSKE, …). Closure + DS-first order derivable from `public.wsg_outlet` (per-WSG outlet `wscode_ltree`, materialized this session) via `@>` ancestry. Major drainages by root wscode: Fraser `100` (68), Peace `200` (65), Columbia `300`/ELKR (17), Skeena `400` (12).

## Cypher capability (proven 2026-05-24)

M1 fired up 3 cyphers in parallel (`cypher_up.sh --workspace job1/2/3`, ~3 min each from warm snapshot `228350154`), verified ready, burned clean (`cypher_down.sh`, 0 tofu resources). DO auth + Tailscale confirmed. `wsgs_run_pipeline.sh` is the all-in-one (spin→prep→dispatch→consolidate→compare→burn via `trap EXIT`).

## Phase 1 done + id_segment bug (2026-05-24)

`lnk_compare_mapping_code()` built tunnel-free (reads local `fresh.streams_vw_bcfp`); `.lnk_compare_wsg_mapping_code_diff` delegates; shared merge in `.lnk_mc_diff`. **Live PARS BT 98.95% tunnel-free** (reproduced the hand-validation). WSG-active species resolution added (PARS → BT only; CO empty in upper Peace, correctly excluded — avoids spurious 0%).

**id_segment is NOT globally unique** (per-WSG row index): `fresh.streams` = 1,542,427 rows but only **80,555 distinct id_segment** (~19× repeat across WSGs; unique only on the persist PK `(id_segment, watershed_group_code)`). Any persist join on `id_segment` ALONE is a ~19-22× cartesian. Found two: `lnk_compare_mapping_code` (fixed in build) and **`lnk_compare_rollup`** (3 joins — was inflating km ~22×: PARS BT spawning_km 36,820 → 1,681; **tactically fixed to full-PK joins this phase**). Safe: `lnk_compare_wsg`/`lnk_pipeline_persist` (working schema = single WSG).

**bcfp `segmented_stream_id` (verified):** globally unique (4.23M distinct); position-derived from `blue_line_key` + `downstream_route_measure` (data dictionary confirms); text; integer part = blk, fraction = `round(measure,3)`-derived; segmentation-dependent. Root fix = make link `id_segment` likewise position-derived → filed **#203** (also enables direct `id_segment == segmented_stream_id` joins).

## Open / watch

- Reference freshness: re-snapshot if the run slips past Tue 2026-05-27 (next bcfp rebuild). Orchestrator Step 1+2 re-snapshots each host automatically.
- Residual ~1-2% mapping_code mismatch is token1 habitat-presence (dimensions/rules), not the dam-access fix — don't chase under #175.
- Base public inputs (pscis/cabd/obs) pulled live each snapshot → slight drift vs bcfp's frozen build inputs; small (98.95% confirms).
