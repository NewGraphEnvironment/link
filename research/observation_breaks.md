# Where a fish observation breaks a stream

**Verified:** 2026-10-28 · **Issues:** #396 (from #326's break history; #283 the validator, #294 observation positions as threshold evidence) · **Produced by:** `data-raw/logs/observation_breaks_396/` (its README indexes it): `build_obs.R`, `cuts.sql`, `province.sql`, `code2_class.sql`, `redundancy.sql`, `run.sh`, `pre_post_diff.R`, `bias.R`, `data-raw/breaks_diff.R` · **Status:** `default` breaks at each species' top observation per line, measured on five groups; `bcfishpass` unchanged; a smaller near-exact set is the open choice

## The rule

A stream breaks at a fish observation so that `access_<sp>` can say "accessible, and the
species is observed upstream" (code 2) against "accessible, not observed upstream" (1).
Nothing else needs the break: barrier lifts count observations point against point, and
the mapping code and habitat gate read barrier flags and `access = 0` against `> 0`.

`default` breaks at each species' farthest-upstream record on each stream line
(`pipeline: observation_breaks: top_per_species`). The `bcfishpass` bundle breaks at every
record, as bcfishpass does (`all`, the value when the key is absent). Mechanics: RUNBOOK §2c.

The access walk counts a same-line record as upstream of a segment when it lies above the
segment's start or within 1 m of it. So code 2 belongs to a segment's start, and a species'
own top break never changes its own code: the segment starting at the top still reads 2. A
species turns from 2 to 1 at the first cut more than 1 m above its top, whatever made that
cut. Under `all` that is often another species' lower record. Under `top_per_species` it is
the next FWA line end, other break source or other species' top, so a kept top is where
species recorded only below it turn to 1. The issue chose the tops on the premise that a
species' top is where its own code changes; the code shows it is not (code-check round 2,
verified against fwapg's `fwa_upstream`).

## A smaller set that keeps code 2 nearly as `all` does

Keeping, per species, the lowest record of any species more than 1 m above its raw top puts
nearly every turn to 1 where `all` puts it, and it is smaller than the tops (`exact_set.sql`,
`exact_set.csv`). It is near-exact, not exact: a removed record that kept a later break from
cutting within 1 m of it releases that break (below), and an FWA end or other cut between a
top and the kept record already turns the species, so the counts are the rule's own size, not
a bound on what an exact rule needs:

| group | positions under `all` | `top_per_species` | exact set |
|---|---|---|---|
| PARS | 593 | 244 | 49 |
| LKEL | 188 | 111 | 58 |
| BULK | 1,185 | 585 | 157 |
| ELKR | 1,923 | 431 | 126 |
| UPCE | 780 | 132 | 25 |

A line holding one species needs no observation break at all under this rule. It is not
built here: `top_per_species` was decided at the gate, and the choice goes back to the
operator.

## How many cuts go (question 1)

Measured on m4's local fwapg, `default` built at main (every observation breaks) and at the
branch (`top_per_species`) into two scratch schemas (`run.sh`, `status.tsv`):

| group | observation positions, `all` → tops | segments before → after | change |
|---|---|---|---|
| PARS | 593 → 244 | 46,341 → 46,004 | −337 (−0.7 %) |
| LKEL | 188 → 111 | 3,378 → 3,312 | −66 (−2.0 %) |
| BULK | 1,185 → 585 | 43,107 → 42,555 | −552 (−1.3 %) |
| UPCE | 780 → 132 | 24,422 → 23,792 | −630 (−2.6 %) |
| ELKR | 1,923 → 431 | 40,027 → 38,601 | −1,426 (−3.6 %) |

Province-wide, `default`'s set keeps 28,876 of 63,282 positions (45.6 %), each group's tops
taken as its build takes them (`province.csv`). Nearly every removed position did cut its
own segment (86 to 97 % of them in the four groups `cuts.csv` covers), but observation
positions are few beside a group's segments, so segments fall by only 0.7 to 3.6 %; network km
are identical (`segments.csv`). The pre-build count of removed positions that save a segment
(`cuts.csv`) matched the builds exactly in those four groups (UPCE was added later).

## How much faster (question 2)

Not measurably, at this cut. Model and recompute minutes per group, BEFORE and AFTER run back
to back on one host (`minutes.csv`, from `status.tsv`):

| group | model, before → after (min) | recompute, before → after (min) |
|---|---|---|
| LKEL | 4.57 → 4.85 | 0.13 → 0.18 |
| BULK | 5.07 → 4.90 | 0.52 → 0.43 |
| UPCE | 2.92 → 2.92 | 0.15 → 0.13 |
| PARS | 4.23 → 4.07 | 0.38 → 0.38 |
| ELKR | 6.67 → 4.08 | 0.33 → 0.30 |

Every pair ran BEFORE first. ELKR's took 39 % less AFTER, far more than its 3.6 % fewer
segments explain. Run again in reverse order (`run_elkr_repeat.sh`), the pair took 3.80 min
AFTER and 3.92 min BEFORE, so the first BEFORE's 6.67 min did not reproduce; what slowed it
is not known. Elsewhere the model minutes change by −4 to +6 %, and the recomputes, which take
8 to 31 s, by at most 5 s. With segments down 0.7 to 3.6 %, the reduced breaks buy accuracy,
not speed. The BULK BEFORE build's first attempt stalled for 45 min in fresh's near-river walk and
was cancelled; its retry took 5.1 min (the shape CLAUDE.md records for OKAN), and the retry's
minutes are used.

## How much sampling bias is left (question 3)

Segment length at the sites, and how often a site starts its own segment (`bias.csv`;
FISS sites from the private knowledge repo, aggregates only; only UPCE of the built groups has
a FISS snapshot):

| sites | n | on a segment start, before → after | median segment (m), before → after |
|---|---|---|---|
| UPCE FISS, fish caught | 1,772 | 59 % → 13 % | 98 → 411 |
| UPCE FISS, no fish | 195 | 24 % → 2 % | 195 → 385 |
| bcfishobs locations, five groups | 188 to 1,923 per group | 100 % → 19 to 62 % | 61–153 → 101–483 |
| every metre of network, five groups | | | 514–671 → 516–676 |

Before, a site with fish sat on a segment half as long as a site without (98 m against
195 m), because the record cut the stream there. After, the two are alike (411 m against
385 m), and both are near the network's typical segment. What is left is the tops: 13 % of fish
sites still start a segment, against 2 % of empty ones. The gradient difference from the FWA
line's own is small either way (median 0.000 to 0.006), so the bias is in segment length, the
reach a rule's gradient is taken over, rather than in a large gradient shift.

## Who reads code 2 (question 4)

Nothing in link tells 2 from 1: every reader tests `access IN (1, 2)`, `> 0` or `= 0`.
The QGIS styles and project files in the sibling repos read bcfishpass's text
`model_access_<sp>`, not link's integer. bcfishpass's own `aw_linear_summary()` sums
`access_<sp> = 2` km as `length_naturallyaccessible_obsrvd_<sp>`; it runs on bcfishpass's
tables, and link's `bcfishpass` bundle keeps every observation break. The file-by-file list
is `readers_code2.md`.

Cutthroat aliases (`CCT`, `ACT`, `CT/RB`) pass the presence filter but never set code 2 for
CT, because the code-2 test is exact. Each alias keeps its own top under the new rule, so the
reduced breaks change nothing there; making the reader see aliases is a separate change.

## Is the remaining redundancy worth removing (question 5)

The issue asked how often a species' top is redundant because the species is also recorded
up a tributary joining above it. That premise does not hold: a species' own top never
changes its own code. The tributary count is kept for the record (`redundancy.csv`: 34, 19,
103 and 86 species-tops in PARS, LKEL, BULK and ELKR), but the real redundancy in the tops is
every top that is not the first cut more than 1 m above some other species' top. That is
what the exact set above removes: it keeps 3 to 31 % of the `all` positions, against 17 to
59 % for the tops.

## Do the outputs move only where expected (question 6)

BEFORE against AFTER on measure-overlap pieces per group and line, every species
(`pre_post_diff.csv`). A segment's codes depend only on where it starts, and both of the walk's
tests are monotone in the start, so a piece's access can only rise where its segment now
starts lower and only fall where it starts higher. That rule held on every piece in all five
groups (`n_violation` 0).

- **No change between blocked and open, no `has_barriers` change, no 2 to 1, no sliver.**
- **1 to 2: 6.1 km in 11 of the 25 group-species, every metre on a segment starting at that
  species' top.** BULK 2.72 km over seven species, ELKR 2.29 (BT), UPCE 0.87, LKEL 0.25 (CO), PARS 0.
- **Habitat moves where merged pieces take a new gradient:** at most 12.2 km of spawning or
  rearing either way per group and species (ELKR GR rearing −11.7 / +12.2 km against
  1,092 km), and the mapping codes with it (up to 35.5 km, ELKR GR).

## What a merged piece does to code 2

A segment's codes depend only on where it starts, and both of the walk's tests are monotone
in the start, so a segment that now starts lower can only open or gain "observed upstream",
and one that starts higher the reverse (RUNBOOK §2c). Fewer observation breaks mostly move
starts down: 1 to 2 above a species' top, where its segment swallows a removed break, and
blocked to open. A segment never spans a confluence, so a tributary's records count the same
for every segment of a feature in both builds. The pre-build estimate of the first
(`code2_class.csv`, not a bound) matched the builds' 1 to 2 at a top exactly, for every
species `default` computes access for, in the four groups it covers (not UPCE); it also counts
CT and DV, which have none.

Some starts move up, because three 1 m rules stack near a removed break: breaks are rounded
to the metre while the walk compares raw measures; a later break source cuts only more than
1 m from the current segment ends, observations being the first source; and the walk reads a
feature within 1 m of a segment start as upstream or downstream. So a barrier, crossing or
other break within 1 m of a removed observation cut, which did not cut, now cuts, and its
segment can turn from open to blocked (the metre-rounding defect of #349) or from 2 to 1.
Question 6 checks the direction rule on every piece.

## Owed

- Every persisted `default` group re-segments again at the next provincial run, stacked on
  #326's owed re-model. The `bcfishpass` schema does not.
- Whether `default` should keep the tops or move to the smaller near-exact set is the
  operator's call. It keeps fewer record positions than the tops; what that does at fish
  sites is unmeasured until it is built and `bias.R` re-run.
