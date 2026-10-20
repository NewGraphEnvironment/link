# accessible vs access_<sp> disagreement by mechanism (link#349)

- run: 2026-10-20 04:20 UTC, 2.6 min
- script: `data-raw/access_disagree_349.R --schema=fresh_349 --config=default --wsgs=UPCE,CARP,DUNC`
- link 0.66.5 @ ca4a58ef; fresh 0.39.0 @ e247ca1
- groups read: 3; newest log row per group by run_uid: NA (3)
- bcfishobs.observations rows: 375962

## Classes (segments; `share_of_accessible` against the species' accessible segments)

| species | direction | class | n_segments | km | n_spawning | n_rearing | share_of_accessible |
|---|---|---|---|---|---|---|---|
| bt | forward | A_other |   3 | 0.168 | 0 | 0 | 0.00006 |
| bt | forward | A_prime_ltree | 163 | 46.064 | 1 | 1 | 0.00332 |
| bt | forward | A_rounding | 186 | 52.855 | 0 | 0 | 0.00378 |
| bt | forward | residual |   1 | 0.136 | 0 | 1 | 0.00002 |
| bt | reverse | R_other |   7 | 1.638 | 0 | 0 | 0.00014 |
| gr | forward | A_other |   1 | 0.059 | 0 | 0 | 0.00008 |
| gr | forward | A_prime_ltree |  79 | 10.971 | 0 | 0 | 0.00654 |
| gr | forward | A_rounding |  91 | 11.847 | 0 | 0 | 0.00753 |
| gr | forward | residual |   1 | 0.507 | 1 | 1 | 0.00008 |
| gr | reverse | R_other |   2 | 0.572 | 0 | 0 | 0.00017 |
| ko | forward | A_prime_ltree |  34 | 5.972 | 0 | 0 | 0.00242 |
| ko | forward | A_rounding |  17 | 2.946 | 0 | 0 | 0.00121 |
| ko | reverse | R_other |   1 | 0.035 | 0 | 0 | 0.00007 |
| rb | forward | A_other |   3 | 0.168 | 0 | 0 | 0.00006 |
| rb | forward | A_prime_ltree | 164 | 46.165 | 1 | 1 | 0.00324 |
| rb | forward | A_rounding | 187 | 52.937 | 0 | 0 | 0.00369 |
| rb | forward | residual |   1 | 0.136 | 0 | 1 | 0.00002 |
| rb | reverse | R_other |   7 | 1.638 | 0 | 0 | 0.00014 |
| wct | forward | A_other |   2 | 0.109 | 0 | 0 | 0.00032 |
| wct | forward | A_prime_ltree | 105 | 35.274 | 2 | 2 | 0.01659 |
| wct | forward | A_rounding | 128 | 44.662 | 0 | 0 | 0.02022 |
| wct | forward | residual |   1 | 0.136 | 0 | 1 | 0.00016 |
| wct | reverse | R_other |   2 | 1.018 | 0 | 0 | 0.00032 |

## Side effects of a settle on `access_<sp>`

| species | access0_spawning | access0_rearing | access0_spawning_overlay | access0_rearing_overlay | lake_polygons_near_blanked_spawning | lake_polygons_lose_spawning | n_minus9 | n_forward_in_absent_group |
|---|---|---|---|---|---|---|---|---|
| bt | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 |
| ch | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| cm | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| co | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| gr | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| ko | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| pk | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| rb | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 |
| sk | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| st | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| wct | 2 | 3 | 0 | 0 | 1 | 0 | 0 | 0 |
