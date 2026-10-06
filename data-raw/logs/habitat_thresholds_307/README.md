# #307 — `default`'s MAD ranges, converted from its width minima

Local docker fwapg (:5432), 2026-10-06 PDT. fresh 0.36.2 (`e3a37f0`). Nothing was
persisted.

## Width to discharge

`data-raw/query_width_mad_equivalent.R` was run from a clean worktree at `f52c8f0`
(`stamp.txt`, `20261006_width_mad_equivalent.txt`). It takes the median `mad_m3s` on
`fresh_default` stream segments (edges 1000/1100/2000/2300, outside waterbodies) whose
modelled channel width lies within 0.1 m of each width minimum, and floors it to two
significant figures. These are the n and medians of #302's ad-hoc query, exactly
(`../habitat_thresholds_302/width_mad_equivalent.txt`).

| width | n | q25 | median | q75 | minimum |
|---|---|---|---|---|---|
| 1.5 m | 36,601 | 0.0144 | 0.0214 | 0.0276 | **0.021** |
| 2 m | 24,509 | 0.0287 | 0.04115 | 0.0521 | **0.041** |
| 4 m | 5,977 | 0.1426 | 0.2010 | 0.2448 | **0.20** |

The per-species cells are in `width_mad_conversion.csv`. KO rearing is lake-only, so
it has no cell.

## Before and after, on held segmentation

Full runs do not reproduce digest for digest (the PSCIS crossing tie), so each group was
prepared once and then re-classified.

- **Preparation.** `verify_classify.R` ran setup → connect under `default` at main
  (`5807d35`, a worktree) into the scratch schemas `zz307_natr` and `zz307_adms`.
- **Re-classification.** On those schemas, `reclassify.R` (classify + connect) and
  `mad_check.R` (classify only, overlay off) ran twice: from main, and from a frozen copy
  of the branch.
- **The `mad` runs** use `method_<wsg>_mad.csv`, which puts the group on `mad`.
- **`mad_check.R` is adapted from #286.** Rows that waterbody rules and the
  `thresholds: false` edges admit inherit no size test, so `*_out` counts them by
  design. The invariant is `*_out_nowb` / `null_nowb`, on stream segments only. Both
  are 0 in every run.

NATR is one of only two groups holding all four species (BT, GR, KO and RB). ADMS
holds BT and RB plus CH, CO and SK, which must not move.

### `cw`: unchanged

Per-species `streams_habitat` digests match, main against branch, for every species
in both groups (`*_cw_main.txt`, `*_cw_branch.txt`).

### `mad`: stream habitat off waterbodies, classify only (`*_madcheck_*.txt`)

| WSG | species | spawn km, main → branch | rear km, main → branch |
|---|---|---|---|
| NATR | BT | 0 → 1,487.1 | 0 → 2,525.2 |
| NATR | GR | 0 → 510.7 | 0 → 1,271.5 |
| NATR | KO | 0 → 815.5 | — (lake only) |
| NATR | RB | 0 → 1,406.0 | 0 → 2,272.0 |
| ADMS | BT | 0 → 219.0 | 0 → 371.5 |
| ADMS | RB | 0 → 173.3 | 0 → 264.7 |
| ADMS | CH / CO / SK | unchanged | unchanged |

KO's spawning here is overstated, because `requires_connected` is applied only at
connect. After connect it is 120.2 km (below).

### `mad`: the lake and wetland buckets shrink, as predicted

fresh gates `lake_rearing` / `wetland_rearing` on the species' rear size range once
one exists (`build_wb_pred()`). Under `mad` that is now the discharge range:

| WSG | species | lake km | wetland km |
|---|---|---|---|
| NATR | BT | 521.4 → 304.0 | 1,287.3 → 710.1 |
| NATR | GR | 408.3 → 247.3 | 0 → 0 |
| NATR | RB | 500.1 → 291.9 | 1,249.6 → 694.0 |
| ADMS | BT | 252.4 → 158.5 | 65.8 → 44.9 |
| ADMS | RB | 246.7 → 154.2 | 55.7 → 36.2 |

KO has no rear range, so its lakes do not move (345.4 km). The `rearing` flag itself is
not gated this way.

### After connect: `cw` against `mad` within `default` (branch; `*_cw_branch.txt`, `*_mad_branch.txt`)

| WSG | species | spawn km cw → mad | rear km cw → mad |
|---|---|---|---|
| NATR | BT | 1,808.0 → 1,727.2 (−4.5 %) | 3,496.3 → 3,547.0 (+1.5 %) |
| NATR | GR | 785.0 → 742.6 (−5.4 %) | 1,360.9 → 1,295.6 (−4.8 %) |
| NATR | KO | 121.2 → 120.2 (−0.8 %) | 345.4 → 345.4 |
| NATR | RB | 1,720.7 → 1,640.2 (−4.7 %) | 3,554.1 → 3,670.8 (+3.3 %) |
| ADMS | BT | 364.8 → 370.9 (+1.7 %) | 531.6 → 558.2 (+5.0 %) |
| ADMS | RB | 307.0 → 309.3 (+0.8 %) | 439.3 → 455.0 (+3.6 %) |

On main under `mad`, BT, GR and KO have 0 km after connect. RB keeps 1,163.3 km (NATR)
and 52.9 km (ADMS) of waterbody rearing.

**Discharge gaps.** On the modelled network the classify reads (`zz307_natr.streams`,
the broken working segments), NATR has no line without `mad_m3s` on edges 1000, 1100
or 1250 (9,390, 9 and 236 km). So `default`'s missing `discharge_fill` costs nothing
here:

    SELECT edge_type, sum(length_metre) / 1000 AS km,
           sum(length_metre) FILTER (WHERE mad_m3s IS NULL) / 1000 AS km_null
      FROM zz307_natr.streams
     WHERE edge_type IN (1000, 1100, 1250, 2000, 2300) GROUP BY 1;

The raw `whse_basemapping.fwa_stream_networks_sp` differs: it holds 50.4 km of NATR edge
1100, 40.9 km of it with no discharge, which the modelled network does not carry (code
review, round 4).
