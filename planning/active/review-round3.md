# Code-check round 3 — #403 branch (39e9c2c5...f9473c8c)

## Checklist read

- `index.md`: read in full (it mirrors the CLAUDE.md index).
- `code-check.md` (37 H3s): the prose of all 14 H3s under `## Mechanisms`, `|` rows skipped. The 23 headings under "Rules that stand alone", Security and Spreadsheets not read.
- `code-check-r.md` (115 H3s): read in full "Postgres row order is never fixed unless the query fixes it…", "An `information_schema` lookup by the literal table name misses what Postgres resolves", "A `data-raw/` script must load the source tree, not the installed package", "`system2(stdout = TRUE)` warns on a non-zero exit…", "Rscript reads a script as it runs…". 110 not read.
- `code-check-shell.md` (70 H3s): "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0" read; 69 not read.
- `code-check-spatial.md` (93 H3s): "FWA `upstream_route_measure` misses the next segment's start" read (parity_pieces.sql builds m1 as `downstream_route_measure + length_metre`, the form it prescribes; the 1 cm sliver drop covers the rest); 92 not read.

## What was checked (and held)

- Default SQL, its NULL / 0 behaviour and the 0.01 rounding bound; `rollup.csv` recomputed (32 rows gap 0, 18 rows gap 0.01, no NA, 10 columns).
- The validator's `summary` merges the whole rollup frame (`.lnk_hv_summary()` `merge(out, cost, …)`), so "carries all three" holds; no consumer of the default frame selects columns by pattern.
- `fresh.streams_vw_bcfp` is the bcfishpass snapshot, not a link view. Local copy: BULK `access_st = 2` km = `access_sk = 2` km = 312.53, 0 segments with ST 2 and SK not 2, matching the research's steelhead paragraph. The `'SK'` test in `access_st` is present at `a7373af` (the recorded reference) as well as `620dbe43`, and gone at `3bd2824c`.
- bcfishpass `access_<sp>` 2/1 is per species (not the salmon group) at the reference, so the access-code parity is like for like.
- Piece totals against the gaps, the 1.3 km accessible residual, "never the reverse": the totals reconcile exactly (PARS 29.70 = 29.70), so no 2-vs-0 piece the SQL's `IN (1, 2)` filter cannot see carries code 2.
- A side probe on local `fresh_default` (BT): 0 code-1 segments with a same-group BT record on the same line more than 1 m above their start (positive control: 89,672 code-2 segments match), so the recompute's "keep a prior 2, else 1" is not undercounting code 2 there. 613 code-1 segments do sit below code-2 segments on the same line (557 in MSTR), all on lines whose `localcode_ltree` jumps to a side code and back; that is the walk's ltree upstream test, not this branch.

## Findings

- **[severity: fragile]** research/known_suspected_km.md:109-113 ("What bcfishpass tabulates") — The second split is described as "habitat code 2 against 1. Code 2 is set where the model says habitat and the user habitat classification confirms it". bcfishpass's `aw_linear_summary()` at `620dbe43` (`db/schema.sql:5359` and siblings) sums `length_spawningrearing_obsrvd_<sp>` over `greatest(spawning_<sp>, rearing_<sp>) >= 2`, i.e. codes 2 **and 3**, and `load_habitat_linear.sql`'s header defines 3 as "observed spawn/rear (not modelled)": user-classified habitat the model does not classify. So `obsrvd` is all user-confirmed habitat, modelled or not, against model-only (`= 1`); the "code 2 against 1" reading leaves out the code-3 reaches, which is exactly the part a link-side match (the "Not done" bullet below it) would have to include. Also CM and PK use spawning only (`spawning_cm >= 2`), so "spawning and rearing combined" holds for the other species. One-line fix: "habitat codes 2 and 3 (user habitat classification confirms it, whether or not the model does) against 1 (model only)".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (a claim about an external system, settled by reading that system's own code)

- **[severity: fragile]** data-raw/logs/known_suspected_403/README.md:32 — "`rollup.csv` | 50 rows: schema, group, species, the eight default columns, `share_observed`". `lnk_rollup_wsg()`'s default has six metric columns; the file has 10 columns (`schema`, `wsg`, `species`, six metrics, `share_observed`). "Eight" counts `wsg` and `species` a second time. Say "the six default metrics".
  - **Rule:** none

No defects found in the R code, the default SQL, the tests, `rollup.R`'s species selection and assertions, or `parity_pieces.sql`'s join shape.
