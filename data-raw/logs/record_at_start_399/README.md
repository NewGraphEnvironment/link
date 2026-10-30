# A record at a segment's start, before and after (#399)

The access walk's observation call went from `include_equivalents = TRUE` to `FALSE`
(bcfishpass's reading), so the same-line measure test counts a record as upstream of a segment only at
`m >= start + 1`. These builds measure what moved, under both configs. Write-ups:
`research/known_suspected_km.md` ("After #399") and `research/observation_breaks.md`.

## Run decision (written before the builds, 2026-10-30)

- **Host:** m1's local docker fwapg, idle apart from this work. Scratch schemas only:
  `zz399_default_{pre,post}`, `zz399_bcfishpass_{pre,post}`, `zz399_obs`. Never `fresh`
  or `fresh_default`.
- **Code:** PRE at `804276e6` (origin/main at the branch point, link 0.71.1), POST at
  `9a84317d` (the change), each from its own git worktree under `load_all`. fresh 0.47.0
  installed (`RemoteSha 2c35e3eb`).
- **Groups:** `default` LKEL, BULK, UPCE, PARS, ELKR (#396's five; UPCE before PARS,
  which drains through it); `bcfishpass` BULK and PARS (#403's parity pair). The species
  are whatever each config models in each group.
- **Flags:** `wsg_run_one.R` with `LNK_LOAD=loadall`, `LNK_GUARD_DOWNSTREAM=warn`
  (the scratch schemas hold no downstream groups), the habitat gate at model time (one
  group per build). BEFORE and AFTER of each group back to back.
- **No recompute:** `lnk_access()` passes no observations and keeps a prior 2, so it
  cannot see this change.
- **Pass rule:** `pre_post_diff.R` with `n_violation = 0` on every row.

## How it was run

```bash
git worktree add <pre> 804276e6 && git worktree add <post> 9a84317d
nohup bash data-raw/logs/record_at_start_399/run.sh <pre> <post> > data-raw/logs/record_at_start_399/driver.log 2>&1 &
Rscript data-raw/logs/record_at_start_399/build_obs.R
Rscript data-raw/logs/record_at_start_399/pre_post_diff.R
```

`run.sh` set `PGPASSWORD` for its gate after a first look: psql on m1 does not read the
docker password from anywhere else, and a gate whose probe always fails reads every minute
as busy.

## What happened

All 14 builds closed on their first try between 19:00 and 20:00 UTC (`status.tsv`, with
the 1-minute load at each step's start and end). The gate passed while the branch's own
test suite was finishing, so LKEL's two builds overlapped it; minutes are not measured
here. Each build's newest `log` row is closed, clean and stamped with its worktree's SHA,
fresh 0.47.0 and the expected access token (`stamp.txt`). `default`'s config hash differs
between PRE and POST (`edb0a5f9`, `b70d0eea`) because the branch edits a comment in
`default`'s `config.yaml`; `bcfishpass`'s does not move.

`build_obs.R`'s sets equal, row for row, the `working_<wsg>.observations` each group's last
build read (`default` for LKEL, UPCE and ELKR; `bcfishpass` for BULK and PARS).

**Only the expected output moved** (`pre_post_diff.csv`, 32 group-species rows,
`n_violation` 0 on each): segment counts and every segment start are identical, and the
only change is `access_<sp>` 2 to 1 on a piece with a same-line record of the species
within 1 m of its start. No piece went 1 to 2, to or from 0, and no `has_barriers`,
mapping code or habitat flag moved.

| config | group-species | km 2 to 1 | per group-species | share of observed km |
|---|---|---|---|---|
| `default` | 25 | 346.6 | 0.02 to 73.5 | 0 to 5.4 %, median 1.8 % |
| `bcfishpass` | 7 | 93.6 | 1.9 to 29.7 | 0.6 to 4.2 %, median 1.9 % |

The guard was proved to fire: with the AFTER schema edited by hand on LKEL (one BT
segment 1 to 2, one CO mapping code, and separately one CO segment 2 to 1 with no CO
record at its start), the script stopped with `n_violation` 1 on each edited row. With the
edits reverted it wrote a `pre_post_diff.csv` identical to the first run's.

**The `bcfishpass` builds now match bcfishpass's observed km** (`parity_bcfp.csv`): after
#399 link minus bcfishpass is 0.00 km for BULK BT, CH, CO, PK and SK and PARS BT, from
1.91 to 29.70 km before (#403's gaps, reproduced to the hundredth). Steelhead stays apart
(200.85 km, 187.11 of it on pieces with no steelhead record at the start) because this
reference codes steelhead from sockeye records. No disagreeing piece needed a record from
another group (`upstream_group` FALSE on every row of `parity_pieces.csv`). Accessible km
do not move (BULK BT −0.10, PARS BT −1.30, as in #403).

## Files

| file | what it is |
|---|---|
| `run.sh` | Quiet-database gate, then the 14 builds |
| `status.tsv`, `driver.log`, `<step>_<WSG>.log` | Each build's times, exit, load and log |
| `build_obs.R` | Rebuilds each config's observation set per group into `zz399_obs` |
| `pre_post_diff.R`, `pre_post_diff.csv` | The pass rule, per config, group and species |
| `rollup.R` | `lnk_rollup_wsg()` on all four schemas, segment counts, the parity reading |
| `rollup.csv`, `segments.csv` | Observed and unobserved km per build; segment counts |
| `parity_pieces.sql`, `parity_pieces.csv`, `parity_bcfp.csv` | link's `bcfishpass` builds against the reference view, by code and by mechanism |
| `stamp.txt` | Commits, fresh, reference version, the builds' log rows |
