# Review — #299 phase 4-5 (docs, driver, evidence), round 1

Diff: `p45.diff` (staged). Code checked against HEAD `52c7eca` `R/lnk_habitat_validate.R`.

## Probes run (scratchpad, nothing in the repo edited)

- **cw no-change at HEAD.** Exported `4df1ffc` with `git archive` and ran `lnk_habitat_validate()`
  on `fresh_default` ADMS (CH, CO, BT, pooled) from it and from HEAD. `compare.R`'s two
  `all.equal` checks are TRUE at HEAD and 94 locations, as the log says. The extra columns
  are exactly the six in `new_obs`.
- **mad numbers at HEAD.** `zz299_mad` still exists in local fwapg (log row 2026-10-02
  08:15 UTC, config `default`). I re-ran the validator from HEAD with the method table
  swapped. Every count in `20261002_adms_compare.txt` §3 "branch" reproduces, as does
  `mad_m3s` 94/94. The README's stream km for CH (256.41 / 317.50) and CO (292.43 / 317.75)
  match `summary`. So the `R/` edits made after the runs (file mtime 01:33, README 01:27)
  did not move these numbers.
- **README tables against `compare.txt`.** Every cell matches.
- **Driver `misses` / `misses_binned`.** I extracted the block and ran it on the cw run, the
  mad run and a mixed cw+mad run. The binned totals equal the `misses.csv` non-captured,
  non-`no_segment` totals in all three (16/16, 50/50, 66/66). No downstream code in the
  script reads these frames by position.
- **Docs against the code.** These all match the code: the label semantics, the reason order
  (`width_null` before `no_mad_threshold` before the `p_nomad_g` arm), `mad_m3s` coming from
  `whse_basemapping.fwa_stream_networks_discharge` on `linear_feature_id`, the
  `.frs_habitat_models()` resolution, "a swapped `method_csv` is not detected", and the MAD
  maxima (CH 100, CO 40, ST 60, WCT 40, against the default CSV).
- **CO `width_null` → `fails_width` in the README.** The two locations have `mad_m3s`
  0.0127 and 0.0182, below CO's minima (spawn 0.164, rear 0.03). The claim is true.

## Findings

- **[severity: false-claim]** `data-raw/logs/habitat_validate_299/README.md:43`, "Scratch
  schema `zz299_mad` and the RDS files were not kept." The schema is still in local fwapg
  (`SELECT nspname FROM pg_namespace WHERE nspname LIKE 'zz299%'` → `zz299_mad`). Either
  drop it before committing, or reword the sentence. (The working schema `zz299_w_adms` is
  gone.)

- **[severity: false-claim]** `data-raw/logs/habitat_validate_299/README.md:30-38`. The
  reasons table is labelled by `stage`, but its counts are `miss_reason_spawn` /
  `miss_reason_rear` over **all** 37 BT locations, not over spawn- or rear-staged ones.
  `compare.R`'s `tab()` does not filter on `is_spawn` / `is_rear`. Only 1 BT location is
  spawn-staged and 6 are rear-staged (measured at HEAD). So "BT | spawn | 27
  `no_mad_threshold`" reads as 27 spawning observations when there is 1. That conflicts
  with the driver's own `misses.csv`, whose `stage` column *is* stage-filtered.

  The prose has the same problem: "Main tells a reader that 51 BT misses were removed by
  clustering". 51 is 24 spawn-reason plus 27 rear-reason over 37 locations, so locations
  are counted twice. `post_predicate` also covers access gating, not only clustering
  (roxygen: "removed by clustering ... or access gating"). Fix: relabel the column "reason
  column (all locations)", or tabulate by stage. Then state the figure per reason column,
  not as 51 misses.

- **[severity: false-claim]** `planning/active/draft-issue-mad-thresholds.md:35`, "`no_mad_threshold`
  counts per WSG × species are the before/after for each value added". After a value is
  added the species has a MAD range, so `.lnk_hv_mad_missing()` is FALSE, the `_nomad`
  columns are NULL, and the label cannot occur. The "after" is 0 by construction,
  whatever the value is. The count also understates the "before": `no_mad_threshold`
  covers only misses with discharge present and passing gradient. Missing-range misses
  read `width_null` (NULL discharge) or `fails_gradient_and_width` (gradient also fails);
  for BT spawn on ADMS that is 8 more beside the 27. The meaningful before/after is
  capture and cost (`share_spawning` / `share_rearing_any`, `*_km`), or the band score
  the draft already names. The same issue touches line 19-20: "so the loss can be counted"
  is only partly true, for the same reason.

- **[severity: false-claim, minor]** `planning/active/draft-issue-mad-thresholds.md:17-18`,
  "carries `spawn_mad_*` / `rear_mad_*` for CH, CM, CO, PK, SK, ST and WCT only". In all
  bundles (`default`, `default_tuned`, `bcfishpass`), CM, PK and SK carry
  `spawn_mad_*` only and their `rear_mad_*` is empty. `rear_mad_*` exists for CH, CO, ST
  and WCT. It is harmless in practice, since CM and PK have `rear: []` and SK rears in
  lakes only, but as written it misstates the CSV in a public issue.

- **[severity: fragile, minor]** `data-raw/logs/habitat_validate_299/README.md:9-10`
  gives stream km (CH 256.4 / 317.5, CO 292.4 / 317.8, "BT 0 / 0") that appear in no
  committed log. `model_mad.R` prints only `n_segments`. The values are correct (I
  reproduced them from `summary` at HEAD). BT's rollup gives `NA` (no rows), not 0. The
  rule is never a number without its producer: either print them in `model_mad.R` /
  `compare.R`, or say where they came from.

## Not findings (checked)

- `model_mad.R` / `validate_run.R` load the source tree (`devtools::load_all(repo)`) and set
  the persist schema through `cfg$pipeline$schema`, which persist reads. They use their own
  working schema and no top-level `on.exit`. The only credentials are the local-docker
  defaults. No host addresses or personal paths in any committed file.
- The `habitat_validate.R` header comment (line 42, "per bundle x species x stage") does
  not mention the new `model` dimension. It is stale-ish, but not false.
- `totals.csv` / `diff.csv` sum across WSGs whatever their model. That is unchanged by
  this diff and reasonable.
