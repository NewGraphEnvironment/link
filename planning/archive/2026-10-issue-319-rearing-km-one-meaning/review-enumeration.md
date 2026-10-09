# code-check enumeration after round 3 (#319)

Mechanism (round 3): prose restating a closed set ("every", "only", "since", "everywhere",
"sums to") built from what was in view during the change, not enumerated from the code.

Candidate set: every added line of the branch diff (planning/, logs .txt, binary rds and man/
excluded) matching `every|everywhere|only|all|none|no|never|always|since|exactly|identical|
unchanged|both|each|0 km|not move|do not|does not` — 58 lines. Each checked against the code
or a measurement:

| claim | result |
|---|---|
| validator / habitat_validation.md: `rearing` flag is "every line the rear rules admit" | too wide (connectivity passes drop admitted lines: `post_predicate`) — fixed |
| RUNBOOK / research / logs README / test: "every WSG rollup" | too wide (`data-raw/compare_adms.R`, `exp_gradient_extra_breaks.R` sum the flag with their own SQL) — narrowed to link's rollups, exceptions named |
| logs README: "every `score305_` schema" | none exist (#305 = `score300_*_fill`) — fixed |
| logs README: "reared on lake lines only from #310", "L rule always admitted" | `default` only — qualified |
| RUNBOOK / test: "the two (always) sum to the flag total" | NA case — qualified |
| lnk_rollup_wsg roxygen: default rearing_km, connection 0, NA clause, example | matches code |
| parity before/after, access + spawning identical, LKEL ST/CO/CH unmoved, PCEA 8.2 km | matches logs |
| PARS spawning 0.02 km drift | matches rds |
| #284 36/36 identical; KO numbers 259.06 / 254.67 / −4.39; only #300/#305 carry KO | re-measured |
| #283 BT 76,872.28 / 2,503.43 / 74,368.85 vs 75,280.2; CH 0 both sides | re-measured |
| MORR stats / ANALYZE | observed |
| vignette "on both sides" | matches parity scripts |
| fixture comments ("BT absent, so no observation scores here", "AAAA has none") | round 2 checked |

No candidate is left above its source of truth.
