## Outcome

Code 2 (`access_<sp>`: accessible, and the species is recorded upstream) now counts every
group's fish records, not only the segment's own group's. The access walk reads
`<schema>.observations_province`, which `lnk_pipeline_run()` keeps until the run ends instead of
prepare dropping it after the lifts. A new bundle key `pipeline: observation_upstream:` picks
the rule: `province` (`default`) counts any group's record, and `group_gated` (the value when
absent, so `bcfishpass`) also needs a record of any species from the segment's own group
upstream. That is bcfishpass's `spp INNER JOIN ids`, which the plan first missed: its `spp`
CTE reads every group, and the plan read that as the whole rule. The gate was reproduced and
drafted for upstream in our fork (NewGraphEnvironment/bcfishpass#16, not posted upstream). The
walk is one `frs_network_features(result = "distinct")` call, a mode added to fresh for this
(fresh#284, PR #285, released as fresh 0.48.0 and pinned here). Tokens `acc-v2` and
`acc-bcfp-2` retire at 0.73.0 for `acc-v3` and `acc-bcfp-3`. The plan's first walk shape,
one existence walk per species, was built, measured 3 to 7 times slower than today's array
walk, and replaced before review. Breaks still read the group's own records.

## Measurement

- **Walk cost** (m1, a group's segments in a temp table): array walk over the group's own
  records against a distinct walk over every group's, LFRA 64–65 → 37–39 s, SETN 47–48 →
  44–46 s, BULK 20.5 → 8 s. One existence walk per species: LFRA 205 s, SETN 320 s, BULK 55 s.
  So counting more records made the walk cheaper. LFRA's Fraser main stem has 126,371 raw
  bcfishobs records under wscode `100`, 79,300 once each is kept by its group's presence.
- **Builds before and after** (six `default` groups, three `bcfishpass`): only code 1 to 2
  moved, each piece under a record of the species from another group and none from its own.
  `default` 25.98 km over 114 pieces in 14 of 31 group-species (LNTH BT 12.25 km, 3.6 % of its
  observed km; LKEL, PARS and ELKR none); `bcfishpass` 0.05 km (UPCE BT). Smaller than the issue
  expected: groups mostly hold their own records near their boundaries. `pre_post_diff.R`
  recomputes code 2 independently of fresh with bcfishpass's join and stopped on two hand
  edits.
- **Parity:** `bcfishpass` builds equal bcfishpass's observed km (0.00) for BULK BT, CH, CO, PK,
  SK, PARS BT and now UPCE BT (−0.05 before, a record in another group). Steelhead stays apart
  (200.85 km, a reference that codes steelhead from sockeye).
- **Review:** `/code-check branch` ran four rounds. Round 1 found the pre-run gate mapping the
  walk's files to `segments` only, which gave the gate a new input, `obs_upstream` (records
  upstream of a group's outlet, LFRA first). Round 3 found a defect inside round 1's wording fix
  (the drop's `try()` also leaves the table on a lost connection). Round 4 ended the loop by
  enumeration: about 45 claims about the table's lifetime and the walk's cost, 5 false (126,000
  raw against about 79,000 kept), all corrected.

## Evidence

`data-raw/logs/obs_province_401/` (its README indexes it); review rounds `review-round*.md` here.

## Owed

- Every persisted group keeps the group-only code 2 until re-modelled: `fresh_default` and
- #403's export column (waiting on #401).

Both stand after merge: `fresh_default` and `fresh` re-model at the next provincial run (#377's
runs row), after the pre-run gate (#372) runs again, with hosts on fresh 0.48.0
(`--auto-install`). #403's export column is unblocked by this work.

Closed by: the PR for branch `401-count-every-group-s-fish-records-when-as`
