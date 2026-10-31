# Every group's fish records for code 2, before and after (#401)

The access walk's observation call now reads `<schema>.observations_province` (every group's
records, each kept by its own group's presence, minus exclusions) instead of
`<schema>.observations` (the group's own), so a segment reads 2 where a record of the species
lies upstream in any group. `default` sets `pipeline: observation_upstream: province`. The
`bcfishpass` bundle leaves it at `group_gated`, which also needs a record of any species from
the segment's own group upstream: bcfishpass's `spp INNER JOIN ids`
(`smnorris/bcfishpass@620dbe4`, `load_streams_upstr_observations.sql`). The walk is one
`frs_network_features(result = "distinct")` call (fresh 0.48.0, fresh#284), plus an existence
walk over the group's own records under the gate. Write-ups: RUNBOOK §2c, "Which records
count"; `research/known_suspected_km.md` ("After #401"); `research/observation_breaks.md`.

## Run decision (written before the builds, 2026-10-30)

- **Host:** m1's local docker fwapg. Scratch schemas only: `zz401_default_{pre,post}`,
  `zz401_bcfishpass_{pre,post}`, `zz401_obs`. Never `fresh` or `fresh_default`.
- **Code:** PRE at `47bb3dfa` (origin/main at the branch point, link 0.72.0), POST at
  `ff6e7ea2` (the change), each from its own git worktree under `load_all`. PRE reads the
  shared library's fresh 0.47.0. POST reads a scratch library holding only fresh at
  `1b2d4bc` (fresh PR #285's head before its archive commit), whose `R/` is the released
  v0.48.0's (`stamp.txt`).
- **Groups:** `default` LKEL, BULK, UPCE, PARS, ELKR (#396's five) and LNTH, a main stem
  below five other groups' records (BRID, CLWR, MAHD, MURT, UNTH); `bcfishpass` BULK, PARS
  and UPCE. UPCE runs before PARS, which drains through it.
- **Flags:** `wsg_run_one.R` with `LNK_LOAD=loadall`, `LNK_GUARD_DOWNSTREAM=warn`, the
  habitat gate at model time. BEFORE and AFTER of each group back to back, after five
  minutes with no other client on the database.
- **No recompute:** `lnk_access()` passes no observations and keeps a prior 2.
- **Pass rule:** `pre_post_diff.R` with `n_violation = 0` on every row.

## What the walk costs

Measured before the builds on persisted `fresh_default` segments, each group's segments in a
temp table, m1 (`walk_*.csv`). Another session's R scripts loaded the machine during
`walk_time.R` (1-minute load 4 to 28), which gave the existence column; the first and last
columns are `walk_fresh_distinct.R`'s, two runs each, at a load of about 2.5.

| group | today: array walk, own records | one existence walk per species, every group's | distinct walk, every group's (fresh's own call) |
|---|---|---|---|
| LFRA | 64 to 65 s | 205 s | 37 to 39 s |
| SETN | 47 to 48 s | 320 s | 44 to 46 s |
| BULK | 20.5 s | 55 s | 8 s |

Per-species existence walks were built first and dropped for this; the distinct mode was
added to fresh instead (fresh#284). LFRA holds 287 Fraser main-stem segments with 126,371
bcfishobs records under wscode `100`.

## How it was run

```bash
git worktree add <pre> 47bb3dfa && git worktree add <post> ff6e7ea2
bash data-raw/logs/obs_province_401/run.sh <pre> <post> <fresh lib> > data-raw/logs/obs_province_401/driver.log 2>&1
Rscript data-raw/logs/obs_province_401/build_obs.R
Rscript data-raw/logs/obs_province_401/pre_post_diff.R
Rscript data-raw/logs/obs_province_401/rollup.R
```

## What happened

All 18 builds closed on their first try between 23:17 and 00:17 UTC (`status.tsv`, load
1.4 to 2.9). Each build's newest `log` row is closed, clean and stamped with its worktree's
SHA and the expected access token: `acc-v2` / `acc-bcfp-2` before, `acc-v3` / `acc-bcfp-3`
after (`stamp.txt`). Build minutes are one run each and not a measurement (ELKR AFTER took
6.65 min against 3.48 BEFORE, UPCE 1.77 against 2.85). `bcfishobs.observations` did not
change during the window (`bcfishobs.txt`).

`build_obs.R` rebuilt each group's own records and each config's province table with the
pipeline's own helper; each group's slice of the province table equals its own table row for
row (0 rows either way in all nine), which is what makes "a 1 to 2 needs a record from
another group" hold.

**Only the expected output moved** (`pre_post_diff.csv`, 39 group-species rows, `n_violation`
0 on each). `pre_post_diff.R` recomputes code 2 for every segment independently of fresh,
with bcfishpass's join (`FWA_Upstream(…, false, 1)`), and checks both builds against their
rule on every accessible piece: BEFORE 2 iff a record of the species from the group,
`default` AFTER 2 iff one from any group, `bcfishpass` AFTER 2 iff one from any group and a
record of any species from the group. Segment counts and starts are identical, the only
change is 1 to 2, every such piece has a record of the species from another group upstream
and none of its own group's, and no `has_barriers`, mapping code or habitat flag moved.

| config | group-species | moved | km 1 to 2 | pieces |
|---|---|---|---|---|
| `default` | 31 | 14 | 25.98 | 114 |
| `bcfishpass` | 8 | 1 | 0.05 | 2 |

LNTH moved most: BT 12.25 km (51 pieces, 3.6 % of its observed km), CH 1.21, CO and RB 1.35.
UPCE took 3.1 km for BT, GR and RB, BULK 0.06 km on one piece for each of seven species.
LKEL, PARS and ELKR did not move. Under `bcfishpass` the gate holds most of it back: only
UPCE BT moved (0.05 km).

The guard was proved to fire: one `default` LKEL BT segment edited 1 to 2 in the AFTER
schema stopped the script with `n_rule_post` 1 and `n_1_to_2_unexplained` 1, and one
`bcfishpass` PARS BT mapping code edited stopped it with `n_mapping_code_change` 1. With each
edit reverted, it wrote a `pre_post_diff.csv` byte-identical to the first run's.

**The `bcfishpass` builds still equal bcfishpass's observed km** (`parity_bcfp.csv`): 0.00 km
for BULK BT, CH, CO, PK and SK, PARS BT and now UPCE BT, which was −0.05 km before: two
pieces where bcfishpass read 2 from a record in another group upstream (`parity_pieces.csv`,
`upstream_group` TRUE), gone after. Steelhead stays apart (200.85 km, as in #399), from a
reference that codes steelhead from sockeye records. Accessible km do not move (BULK BT
−0.10, PARS BT −1.30, UPCE BT −0.36).

## Files

| file | what it is |
|---|---|
| `walk_time.R`, `walk_time.csv`, `walk_time.log` | Array walk against per-species existence walks, eight groups |
| `walk_distinct.R`, `walk_distinct.csv` | Hand-written `SELECT DISTINCT` walk over every group's records |
| `walk_fresh_distinct.R`, `walk_fresh_distinct.csv` | fresh's own `result = "distinct"` call |
| `run.sh` | Quiet-database gate, then the 18 builds |
| `status.tsv`, `driver.log`, `<step>_<WSG>.log` | Each build's times, exit, load and log |
| `bcfishobs.txt` | `bcfishobs.observations` count and digest before and after |
| `build_obs.R`, `build_obs.log` | Rebuilds each record set into `zz401_obs` |
| `pre_post_diff.R`, `pre_post_diff.csv`, `pre_post_diff.log` | The pass rule, per config, group and species |
| `rollup.R`, `rollup.log` | `lnk_rollup_wsg()` on all four schemas, segment counts, the parity reading |
| `rollup.csv`, `segments.csv` | Observed and unobserved km per build; segment counts |
| `parity_pieces.sql`, `parity_pieces.csv`, `parity_bcfp.csv` | link's `bcfishpass` builds against the reference view, by code and by mechanism |
| `stamp.txt` | Commits, fresh, reference version, the builds' log rows |
