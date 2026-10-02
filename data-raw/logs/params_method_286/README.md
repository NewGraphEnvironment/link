# #286 live verification — per-WSG cw/mad method table

Local docker fwapg (:5432), 2026-10-02 UTC. Config `default`. Scratch working schemas
`zz286_adms` and `zz286_bulk` only; nothing persisted to `fresh` / `fresh_default`.
Branch code ran from a frozen copy of the working tree, main from a worktree at
`f462113`. fresh 0.36.2 (`e3a37f0`), plus fresh 0.33.0 (`7f12d99`) in a separate library
for the A0 runs (`LNK_LIBPRE`).

- `verify_classify.R` runs setup → connect on one WSG and digests `streams_habitat` per
  species (copied from `../habitat_thresholds_282/`).
- `reclassify.R` re-runs classify + connect on a prepared schema, so segmentation is held
  fixed. It optionally takes `method_csv`.
- `mad_check.R` runs classify only, with the overlay off and no connect, under a given
  method table, then checks fresh's mad invariants. The `*_nowb` columns are segments
  outside any waterbody (`waterbody_key IS NULL`).

## No-change proof (per-species `streams_habitat` digests, after connect)

| WSG | runs compared | result |
|---|---|---|
| ADMS | full branch run; B branch; A main + fresh 0.36.2; A0 main + fresh 0.33.0; A_nocol main with `mad_m3s` dropped; B2 branch after re-joining it | **all identical**, 5 species |
| BULK | full branch run; B branch; A main + fresh 0.36.2; A0 main + fresh 0.33.0 | **all identical**, 7 species |

So the fresh 0.33.0 → 0.36.2 bump, the extra `mad_m3s` column and the all-`cw` method
table each move nothing. `mad_m3s` survives breaking: 39,414 of ADMS's 39,423 working
segments carry it.

## `mad` takes effect (classify only, overlay off)

ADMS has discharge for 10,449 of 11,520 FWA segments. Stream (non-waterbody) km,
cw → mad:

| species | spawn cw → mad | rear cw → mad |
|---|---|---|
| BT | 214.5 → 0 | 346.2 → 0 |
| RB | 172.7 → 0 | 251.9 → 0 |
| CH | 128.3 → 106.4 | 169.8 → 132.4 |
| CO | 162.1 → 140.1 | 169.8 → 172.3 |
| SK | 90.5 → 81.8 | 0 → 0 |

- **Invariants hold.** No stream spawning or rearing segment of CH/CO/SK has `mad_m3s`
  outside `[*_mad_min, *_mad_max]` or NULL.
- **BT and RB keep 63.5 and 52.9 km of rearing**, all of it inside waterbodies: the
  wetland-polygon rules and the 1050/1150 `thresholds: false` edges. fresh's lake and
  wetland rules inherit no thresholds under either model (`.frs_rule_to_sql`), so this
  is intended.
- **222 CH and 128 CO rearing segments sit below the MAD minimum.** They come from those
  same non-inheriting waterbody rules, not from a broken invariant.

BULK has **no discharge at all**. Under `mad`, every species has 0 km of stream spawning
and rearing, and nothing errors. The rearing that remains is waterbody rules only (CH
391.3 km, BT 458.8 km). This is why coverage has to be checked before a group is moved
to `mad`.
