# accessible vs access_<sp> disagreement by mechanism (link#349)

- run: 2026-10-20 03:57 UTC, 4.0 min
- script: `data-raw/access_disagree_349.R --schema=fresh_default --config=default`
- link 0.66.5 @ 809bf084 (dirty); fresh 0.39.0 @ e247ca1
- groups read: 241; newest log row per group by run_uid: 20261017_004619-3f4c713b (241)
- bcfishobs.observations rows: 375962

## Classes (segments; `share_of_accessible` against the species' accessible segments)

| species | direction | class | n_segments | km | n_spawning | n_rearing | share_of_accessible |
|---|---|---|---|---|---|---|---|
| bt | forward | A_other |     85 | 16.347 |     0 |      0 | 0.00003 |
| bt | forward | A_prime_ltree |   7636 | 1,636.295 |    31 |     84 | 0.00280 |
| bt | forward | A_rounding |   6999 | 1,506.029 |    18 |     56 | 0.00256 |
| bt | forward | B_cross_group |  33739 | 6,473.634 |  4582 |   8602 | 0.01236 |
| bt | forward | residual |    269 | 58.641 |    66 |    125 | 0.00010 |
| bt | reverse | R_other |    866 | 202.851 |     0 |      0 | 0.00032 |
| bt | reverse | R_override_scope |    169 | 19.358 |     0 |      0 | 0.00006 |
| ch | forward | A_other |     70 | 13.260 |     1 |      0 | 0.00008 |
| ch | forward | A_prime_ltree |   7339 | 1,331.092 |    24 |    158 | 0.00843 |
| ch | forward | A_rounding |   6695 | 1,232.280 |    17 |     95 | 0.00769 |
| ch | forward | residual |    138 | 29.896 |    64 |     77 | 0.00016 |
| ch | reverse | R_other |    710 | 174.189 |     3 |      0 | 0.00082 |
| cm | forward | A_other |     47 | 6.040 |     0 |      0 | 0.00014 |
| cm | forward | A_prime_ltree |   3923 | 723.965 |    71 |      0 | 0.01173 |
| cm | forward | A_rounding |   3504 | 644.827 |    52 |      0 | 0.01048 |
| cm | forward | residual |    324 | 109.985 |    52 |      0 | 0.00097 |
| cm | reverse | R_other |    477 | 114.626 |     0 |      0 | 0.00143 |
| co | forward | A_other |     69 | 12.346 |     0 |      0 | 0.00011 |
| co | forward | A_prime_ltree |   6475 | 1,152.734 |    91 |    159 | 0.01031 |
| co | forward | A_rounding |   5804 | 1,044.190 |    64 |     96 | 0.00924 |
| co | forward | residual |    369 | 120.461 |    61 |    276 | 0.00059 |
| co | reverse | R_other |    676 | 167.045 |     3 |      0 | 0.00108 |
| gr | forward | A_other |     54 | 10.652 |     0 |      0 | 0.00006 |
| gr | forward | A_prime_ltree |   5423 | 944.441 |     3 |     19 | 0.00611 |
| gr | forward | A_rounding |   4999 | 901.341 |     3 |     20 | 0.00564 |
| gr | forward | B_cross_group |  20319 | 5,283.659 |  4964 |   7046 | 0.02290 |
| gr | forward | residual |    201 | 55.220 |    61 |     85 | 0.00023 |
| gr | reverse | R_near_1m |      1 | 0.137 |     0 |      0 | 0.00000 |
| gr | reverse | R_other |    452 | 86.852 |     0 |      0 | 0.00051 |
| gr | reverse | R_override_scope |    299 | 60.468 |     0 |      0 | 0.00034 |
| ko | forward | A_other |      2 | 0.883 |     0 |      0 | 0.00003 |
| ko | forward | A_prime_ltree |    270 | 46.999 |     2 |      0 | 0.00433 |
| ko | forward | A_rounding |    213 | 29.779 |     0 |      0 | 0.00341 |
| ko | forward | B_cross_group |  55498 | 15,314.841 |   429 |    983 | 0.88921 |
| ko | forward | residual |      6 | 0.917 |     1 |      0 | 0.00010 |
| pk | forward | A_other |     42 | 5.325 |     0 |      0 | 0.00011 |
| pk | forward | A_prime_ltree |   3798 | 631.763 |    65 |      0 | 0.00980 |
| pk | forward | A_rounding |   3407 | 573.083 |    41 |      0 | 0.00879 |
| pk | forward | residual |    325 | 110.249 |    47 |      0 | 0.00084 |
| pk | reverse | R_other |    360 | 94.329 |     0 |      0 | 0.00093 |
| rb | forward | A_other |     98 | 19.862 |     0 |      0 | 0.00003 |
| rb | forward | A_prime_ltree |   8608 | 1,948.063 |    40 |    126 | 0.00304 |
| rb | forward | A_rounding |   7840 | 1,793.364 |    23 |     58 | 0.00277 |
| rb | forward | B_cross_group | 457912 | 97,549.501 | 65363 | 145045 | 0.16168 |
| rb | forward | residual |   6817 | 1,267.613 |  1557 |   2216 | 0.00241 |
| rb | reverse | R_other |    759 | 175.191 |     0 |      0 | 0.00027 |
| sk | forward | A_other |     48 | 9.536 |     0 |      0 | 0.00009 |
| sk | forward | A_prime_ltree |   5648 | 1,037.087 |    22 |      0 | 0.01012 |
| sk | forward | A_rounding |   5236 | 953.316 |    16 |      0 | 0.00938 |
| sk | forward | residual |    366 | 119.185 |    21 |    193 | 0.00066 |
| sk | reverse | R_other |    496 | 131.335 |     4 |      0 | 0.00089 |
| st | forward | A_other |     50 | 8.171 |     0 |      0 | 0.00007 |
| st | forward | A_prime_ltree |   4775 | 926.058 |    16 |     94 | 0.00654 |
| st | forward | A_rounding |   4330 | 849.283 |     4 |     56 | 0.00593 |
| st | forward | residual |    456 | 127.269 |    57 |    284 | 0.00062 |
| st | reverse | R_other |    515 | 124.273 |     0 |      0 | 0.00071 |
| wct | forward | A_other |     12 | 4.031 |     0 |      0 | 0.00007 |
| wct | forward | A_prime_ltree |   1161 | 244.460 |    12 |     22 | 0.00684 |
| wct | forward | A_rounding |   1094 | 216.156 |     4 |     14 | 0.00645 |
| wct | forward | residual |     17 | 1.574 |     1 |      8 | 0.00010 |
| wct | reverse | R_other |    161 | 34.538 |     0 |      0 | 0.00095 |
| wct | reverse | R_override_scope |      2 | 0.458 |     0 |      0 | 0.00001 |

## Side effects of a settle on `access_<sp>`

| species | access0_spawning | access0_rearing | access0_spawning_overlay | access0_rearing_overlay | lake_polygons_near_blanked_spawning | lake_polygons_lose_spawning | n_minus9 | n_forward_in_absent_group |
|---|---|---|---|---|---|---|---|---|
| bt |  4697 |   8867 |   0 | 0 |   98 | 0 | 0 | 0 |
| ch |   284 |    335 | 189 | 5 |   30 | 0 | 0 | 0 |
| cm |   455 |      0 | 300 | 0 |    0 | 0 | 0 | 0 |
| co |   976 |    536 | 788 | 5 | 3470 | 0 | 0 | 0 |
| gr |  5031 |   7170 |   0 | 0 |   11 | 0 | 0 | 0 |
| ko |   432 |    983 |   0 | 0 |    3 | 0 | 0 | 0 |
| pk |   395 |      0 | 263 | 0 |    0 | 0 | 0 | 0 |
| rb | 66983 | 147445 |   0 | 0 |  175 | 0 | 0 | 0 |
| sk |   197 |    193 | 153 | 0 |   42 | 0 | 0 | 0 |
| st |   181 |    434 | 110 | 0 |   20 | 0 | 0 | 0 |
| wct |    17 |     44 |   0 | 0 |   53 | 0 | 0 | 0 |
