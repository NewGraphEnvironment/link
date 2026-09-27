Title: query_habitat_thresholds_obs.R: availability km differ run to run in the last bits (float sum order)

Two runs of `data-raw/query_habitat_thresholds_obs.R` on the same database, commit and bundle differ in `candidates.csv`: `avail_share_below` is `0.11325447588492017` in one run and `0.11325447588492016` in the other, and `ratio_below` differs at the same digit. Measured 2026-09-26 while verifying #290.

The cause is `sum(s.length_metre) / 1000 AS km` (the availability query, ~line 371). It is a double-precision sum, and Postgres may parallelise the aggregate, so the summation order, and therefore the last bits, vary between runs. link's bar is byte-identical reruns, and this breaks it for a research producer whose outputs are committed as evidence.

Fix: sum as `numeric` (`sum(s.length_metre::numeric) / 1000`), or round to a fixed number of decimals before writing. Then re-run twice and `cmp` the outputs. The committed CSVs will change in the last digits once, so say so in the commit.

Relates to #284, #277
