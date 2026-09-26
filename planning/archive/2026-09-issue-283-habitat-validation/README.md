## Outcome

Built `lnk_habitat_validate()` and `data-raw/habitat_validate.R`, which score a persisted
run against fish observations rather than against bcfishpass. Per WSG × species × stage
they report capture, cost in km, miss reasons and FISS absences. The miss reasons come
from the bundle's own predicates, re-evaluated with the gradient and the width relaxed.

The design moved three times on measurement:
- The issue's "use per-WSG schemas, fresh#218 duplicates" turned out to be a bare
  `id_segment` join artifact.
- `schema` became required because `default` declares the schema the bcfishpass
  bundle writes.
- Capture outside `user_habitat_classification` reaches was added once the baseline
  showed CH spawn-staged capture is almost all overlay.

The method, the baseline and the #284 step-5 command are in
[`research/habitat_validation.md`](../../../research/habitat_validation.md).

## Measurement

`default:fresh_default` vs `bcfishpass:fresh`, 51 shared WSGs, buffer 0:
- **BT, rear-staged (n 1,047):** any-rearing capture 66.5 % on 75,280 km (default) vs
  63.6 % on 76,872 km (bcfishpass).
- **CH, any stage (n 1,734):** stream-rearing capture 87.7 % vs 86.6 %, for 28 % more
  rearing km.
- **CH, spawn-staged:** 237 of 245 locations sit in UHC spawning reaches. That is why
  `default` reads 98.4 % and bcfishpass 84.5 %. Outside those reaches n is 8.
- **Buffer 100 m:** +0.4–2.8 points on spawning, 0–1.6 on rearing.
- **Reconciliation:** `fresh_default` alone retains 5,104 BT+DV and 1,745 CH locations,
  exactly #284's counts.

**The wrong turns, kept:**
- The first absence rule counted FISS sites that caught fish but listed no species. They
  were 63 % of BT absences in a 5-WSG probe.
- The first UHC flag ignored the indicator, so 98.7 % of flagged records were in
  spawning-only reaches.
- The first spawn gradient floor was derived twice, from two sources that happen to
  agree today.
- `toupper(NULL)` is `character(0)`, so the first full run scored zero WSGs.
- The first predicate call passed `model =`, which the pinned `fresh@v0.33.0` lacks.
  Only the full suite's drift guard led to it.

Review: a plan review plus five code-check rounds (`review-*.md`). Round 2 found a
defect inside a round-1 fix. Round 3 named three mechanisms and enumerated 59 rows, and
round 4 re-walked them.

## Evidence

`data-raw/logs/habitat_validate_283/*` (link @ `0c19e0a`; `stamp.txt` records the run-log
coverage of each schema).

Closed by: PR for #283 (branch `283-validate-modelled-habitat-against-fish`)
