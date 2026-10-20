# accessible vs access_<sp> disagreement by mechanism (link#349)

- run: 2026-10-20 04:24 UTC, 0.2 min
- script: `data-raw/access_disagree_349.R --schema=fresh_349 --config=default --wsgs=UPCE,CARP,DUNC`
- link 0.66.5 @ ca4a58ef; fresh 0.39.0 @ e247ca1
- groups read: 3; newest log row per group by run_uid: NA (3)
- bcfishobs.observations rows: 375962

## Classes (segments; `share_of_accessible` against the species' accessible segments)

| species | direction | class | n_segments | km | n_spawning | n_rearing | share_of_accessible |
|---|---|---|---|---|---|---|---|
| bt | reverse | R_other | 7 | 1.638 | 0 | 0 | 0.00014 |
| gr | reverse | R_other | 2 | 0.572 | 0 | 0 | 0.00017 |
| ko | reverse | R_other | 1 | 0.035 | 0 | 0 | 0.00007 |
| rb | reverse | R_other | 7 | 1.638 | 0 | 0 | 0.00014 |
| wct | reverse | R_other | 2 | 1.018 | 0 | 0 | 0.00033 |

## Side effects of a settle on `access_<sp>`

| species | access0_spawning | access0_rearing | access0_spawning_overlay | access0_rearing_overlay | lake_polygons_near_blanked_spawning | lake_polygons_lose_spawning | n_minus9 | n_forward_in_absent_group |
|---|---|---|---|---|---|---|---|---|
| bt | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| ch | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| cm | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| co | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| gr | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| ko | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| pk | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| rb | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| sk | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| st | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| wct | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
