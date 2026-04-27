# Findings — vignette-ship

## Why "extremely tight"

User feedback: pkgdown site is public; a long vignette risks looking
half-baked. The vignette's purpose is to teach a user to RUN link's
bcfishpass config, not to teach them every methodological choice
(research doc owns that).

Audit of the dev/.draft, what to keep / cut:

| section | line count (roughly) | keep | rationale |
|---|---|---|---|
| Title + frontmatter | 20 | yes | minimum |
| Top-of-vignette scope paragraphs | 15 | yes | shipped in v0.11.2; framing is right |
| Prereqs | 25 | trim | tunnel-as-required reads wrong; reorder so fwapg is required, tunnel only for the comparison map |
| How config works (intro) | 12 | yes | one paragraph |
| DAG ASCII art | 28 | **cut** | research doc has it; visual in knitted output is awkward |
| Where breaks go | 60 | **cut** | research doc territory |
| Where classification comes from | 30 | **cut** | research doc territory |
| Known-habitat overlay | 18 | **cut** | research doc territory |
| Stream-order bypass — not applied | 8 | **cut** | research doc + filing as follow-up |
| Running the pipeline | 30 | yes | the actual point of the vignette |
| The rollup | 30 | yes — rewrite for new numbers | core empirical content |
| Comparison map | 50 | yes | nice visualization |
| Reproducibility | 8 | **cut** | generic, not load-bearing |
| Further reading | 10 | trim | pkgdown nav covers this |

Net: keep 5 sections + 2 chunks. ~150 lines including code.

## Compare query parity update

The stash carried `data-raw/compare_bcfishpass_wsg.R`'s retarget from
`bcfishpass.habitat_linear_<sp>` to `bcfishpass.streams_habitat_linear.<spawning|rearing>_<sp> > 0`.
Confirms apples-to-apples post-overlay comparison. SK BABL diff_pct
flips from +43.8% to ~-36% (link 85.2 vs published 132 — the residual
is the range-containment relaxation gap, fresh follow-up).

## Stamp output now includes shape_drift

After link 0.13.0, `lnk_stamp()`'s markdown output has a 3-col table
(file, byte drift, shape drift). The vignette's pipeline stamp output
will surface that. No vignette content adjustment needed — same
markdown.

## Vignette data regen

`Rscript data-raw/vignette_reproducing_bcfishpass.R` reads
`tar_read(rollup, store = "data-raw/_targets")` and writes
`inst/extdata/vignette-data/rollup.rds` plus the two `sub_ch*.rds` map
artifacts. After this PR's tar_make rerun, regen pulls the post-
fresh-0.22.0 + post-retarget numbers.

## Local render approach

```r
rmarkdown::render("vignettes/habitat-bcfishpass.Rmd",
  output_format = "bookdown::html_vignette2",
  output_dir = tempdir())
```

Should knit clean — chunks are mostly read-only RDS reads + mapgl
widget. No DB needed at render time. CI-safe.

## SK BABL prose update

Old prose (in dev/.draft): "Observed differences come from the stream-
order bypass omission..." — tied to the old comparison. Needs
rewrite. The new comparison produces:

- Link side: rule predicates + known-habitat overlay
- Bcfishpass side: streams_habitat_linear (model + known)

Difference sources:
- Stream-order bypass: BT rearing -3% to -5% (still applies, still
  documented)
- Range-containment artifact in overlay: SK BABL ~-36% (under-counts
  known habitat)
- Segmentation rounding near rule thresholds: small per-WSG variation

Single tight paragraph covering all three.

## CI cost

The vignette renders without DB. The bundled `*.rds` files are committed
(small, ~70 KB total). Pkgdown CI will rebuild the site on the merge
commit; it pulls from `gh-pages`. No new CI dependencies.

## Stream-order-parent issue (filed as follow-up)

bcfishpass applies a rearing-side bypass on `channel_width_min` for
BT/CH/CO/ST/WCT when stream_order = 1 AND parent_order >= 5. Link's
bcfishpass bundle doesn't (despite `lnk_rules_build()` having emission
machinery for `channel_width_min_bypass: {stream_order: 1, stream_order_parent_min: 5}`).

Mention in vignette: NO. Research doc covers it. File as a separate
issue to track tackling.

Effort estimate (per user's question):
- If fresh's classify already evaluates `channel_width_min_bypass`:
  ~1-2 hours. Flip dimensions.csv, regenerate rules.yaml, rerun.
- If fresh needs predicate evaluator: ~half day. Fresh PR + link config.
- I haven't verified fresh's side; worth a 5-min check before sizing.
