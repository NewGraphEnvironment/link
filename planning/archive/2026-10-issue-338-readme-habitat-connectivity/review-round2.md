# Code-check round 2 (#338): branch diff vs main

Reviewer: subagent, 2026-10-14. Round-1 fixes 1-6 checked; each holds:
- discharge fill is scoped to `mad` groups (`default_tuned/config.yaml`);
- the connected-spawning bucket rule matches `default/dimensions.csv`: 10 km for BT, CH, CO, ST, WCT, RB, CT, DV, and GR (lakes only); NA for SK and KO;
- `snapshot_bcfp.sh` loads PSCIS, CABD dams, bchamp modelled crossings and bchamp observations, and fwapg's `load.sh` loads channel width and discharge;
- the ORCID now matches every sibling package and passes the ISO 7064 check (the old one failed it);
- `CITATION.cff` regenerates byte-identical with cffr 1.4.2 and the workflow's exact command;
- `data-raw/readme_figure.R` reproduces `man/figures/readme-pars.png` byte-identical (both run in a temp copy).

Four claims are wrong.

## Findings

- **[claim]** DESCRIPTION:13-15, README.md:5, CITATION.cff abstract, man/link-package.Rd: "then resolves access past road crossings, dams, falls and steep gradients, using fish observations and habitat confirmations as evidence of passage." Access is gated by natural barriers only (gradient at the species threshold, falls, user-definite, and subsurface flow when opted in). Road crossings and dams never gate access; they are recorded only as the barrier type below a reach.
  - Code evidence:
    - `R/lnk_pipeline_run.R:252-264`: "Dams/PSCIS/modelled are NOT in the access set — they annotate access via token2 … never block it. So a dam-downstream segment that is otherwise accessible stays accessible and emits `;DAM`."
    - `R/lnk_barriers_views.R:23-33` says the same.
  - Observations and habitat confirmations lift only natural barriers: the anti-join against `barrier_overrides` runs on the natural set.
  - The README's own figure contradicts the sentence: most reaches are "Accessible, dam below".
  - Why it matters: this is the package's one-paragraph definition, copied into DESCRIPTION, the CITATION abstract and the Rd. It tells a reader that link models passability at crossings and dams, and it does not.
  - Suggested shape: "resolves access past falls and steep gradients, using fish observations and habitat confirmations as evidence of passage, and records the road crossings and dams below each reach."
  - Related (README.md:23): "access reads the barriers already persisted for the groups below, and `lnk_wsg_downstream_check()` checks that the dams below a group are already persisted". Each clause is true on its own, but together they read as if dams are access barriers. The dams matter for the `DAM` token in `mapping_code`, not for access.

- **[claim]** README.md:48 ("For each crossing, `lnk_aggregate()` sums the habitat upstream of it"), together with README.md:5 ("how much spawning and rearing habitat sits above each one, and what a fix would open up").
  - `R/lnk_aggregate.R:150-163` joins habitat to a crossing only on the same `blue_line_key` with `measure >= crossing measure`. It does no network traversal (no `fwa_upstream`), so:
    - every tributary above the crossing is left out;
    - habitat beyond the next barrier upstream on that line is counted.
  - It is also not per species, and it cannot read what the pipeline persists:
    - it needs one table carrying `blue_line_key`, `downstream_route_measure`, `length_metre` and boolean `spawning` / `rearing`;
    - `<schema>.streams_habitat_<sp>` and `streams_habitat_long_vw` carry only `id_segment`, `watershed_group_code`, `spawning` and `rearing` (`R/lnk_persist_init.R:465-477`), while length and position live on `streams`.
  - Nothing in `R/`, `data-raw/` or `vignettes/` calls it.
  - Why it matters: "habitat above each crossing / what a fix would open up" is the restoration-program pitch of the new README. As written, a user would get the habitat on the crossing's own stream line only and read it as the upstream gain.
  - Either scope the sentence (habitat on the same stream above the crossing) or drop the `lnk_aggregate()` and "what a fix would open up" wording until a network-aware per-crossing rollup exists.

- **[claim]** data-raw/readme_figure.R:67 (the legend label "Not classified for grayling"), shown in man/figures/readme-pars.png. The grey reaches are not unclassified; they are inaccessible to grayling.
  - The script greys every segment whose `mapping_code_gr` is empty.
  - In `R/lnk_pipeline_mapping_code.R`, an empty code means the species has a blocking barrier downstream (token 1 and token 2 are suppressed when it is not accessible). The other possibility is that `has_barriers_<sp>_dnstr` is NA.
  - Measured on the local `fresh_default`: all 78,305 PARS segments with `mapping_code_gr = ''` have `has_barriers_gr_dnstr = TRUE`, none NA.
  - The cached gpkg keeps those segments only because they carry a bull-trout code (`data-raw/wsg_vignette_data.R:169-171`). The grey network is therefore mostly reaches above grayling's 15 % gradient barriers that bull trout (25 %) can pass, about 2,400 km.
  - Why it matters: the headline figure of an access-focused README labels "blocked for grayling" as "not classified".
  - Fix: relabel, e.g. "Above a grayling barrier (inaccessible)". The caption could say so too.
  - Minor, same script: the single PARS segment coded `REAR` (rearing, inaccessible) draws in `#999999` with no legend entry. It is 0.0 km, so the effect is negligible.

- **[claim, minor]** README.md:11, caption "Orange and red reaches sit above a road crossing modelled or assessed as a barrier". DESCRIPTION / README.md:5 say "road crossings" in the same sense.
  - Anthropogenic barriers include railway crossings. In PARS, 195 of the 3,346 modelled-crossing barriers in `fresh_default.barriers` match a `fresh.modelled_stream_crossings` row with `railway_track_id IS NOT NULL`, matched on `blue_line_key` and a measure within 1 m (the remaining 3,151 are roads).
  - Fix: "road or rail crossing", or just "crossing".
