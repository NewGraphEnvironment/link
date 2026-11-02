# minimal_breaks_415 — is the minimal network the full network with fewer cuts? (#415)

**Status: proof run 2026-11-02 on BULK, SETN, MORK and COTR at link `6bf9ca06` (0.78.0), fresh 0.52.0, every check passed. The write-up is `research/minimal_network.md`.** The groups are the top four of `pick_groups.sql` by combined rank (chinook sites plus modelled crossings), all on `cw`, built downstream-first in that order. `lifts.R` was committed before the builds. `lifts.csv` and `lifts_obs.csv` are from `lifts.R` as of `ac52e150`, which counts segment starts beside barrier positions and replaced the second control after review; `R/` is unchanged since the builds, and every run of it gave the same positions and km. Before the run, a smoke run exercised the scripts and is not evidence: ADMS on 2026-11-02 at `c86e8871` (after #432 merged), on the installed fresh 0.52.0 against the `v0.48.0` pin. `run.sh` and the recompute passed, `proof.R` passed its checks and wrote every CSV, and the scratch schemas were dropped. An earlier `proof.R` with the two schema names swapped stopped on the commit-and-token, superset and census checks, so those guards fire, and the final `proof.R` stopped on a dirtied tree. No smoke group has a dam below it, so neither `BLOCKED` branch has run on real data.

## Question

`default_minimal` cuts streams only at access-gradient positions, falls and user-definite barriers. Does dropping observation, habitat end point and crossing cuts change segmentation and nothing else a tuning reads, and where it changes more, by how much?

## Run decision (for the real run, restate before launching)

- **Software:** install the pinned fresh, or say why not. `builds.csv` records the version each build read, and `proof.R` stops when the builds differ, but it does not compare it with the pin.
- **Groups:** BULK plus two or three chinook-rearing and crossing-heavy groups, picked from `pick_groups.sql` when the proof runs, and named here with why. Check each is on `cw`, since `proof.R` reads channel width only.
- **Schemas:** `zz415_default` (`default`) and `zz415_minimal` (`default_minimal`), scratch on the local fwapg, published nowhere, dropped when the write-up lands.
- **Order:** downstream-first, passed to `run.sh` in that order. Serial, because both bundles share `working_<wsg>`. In each group `default` runs first, so `working_<wsg>` holds the minimal build the census reads.
- **One commit:** `run.sh` refuses tracked changes, and `proof.R` stops unless both builds' and recomputes' log rows name one clean `link_sha` and fresh, the ones it is run at itself, the expected cut tokens and one `acc` and `flow` token. Commit nothing and install nothing between the two scripts.
- **Recompute pass rule:** exit 0, or exit 1 with the downstream-dam post-condition (`BLOCKED (link#227)`) as the failure. That check runs after the work commits, and a scratch schema holds no groups below the ones built. `status.tsv` records `yes` or `postcondition`.

```bash
bash data-raw/logs/minimal_breaks_415/run.sh BULK <WSG> <WSG>
Rscript data-raw/logs/minimal_breaks_415/proof.R --wsgs=BULK,<WSG>,<WSG>
```

## Checks

`lifts.R` (run after `proof.R`, while `working_<wsg>` holds the minimal build) writes `lifts.csv` and `lifts_obs.csv`: how far observation lifts move the minimal cuts, from a counterfactual with no fish records in the barrier overrides. It stops unless the build's own overrides reproduce the build, and unless every segment start that moves lies within 1 m of a barrier position that moved.

| file | what it answers | stops on |
|---|---|---|
| `status.tsv` | minutes, exit, pass rule and segments per step | |
| `builds.csv` | which commit, fresh and tokens each build and recompute carries | not one clean commit and fresh, wrong tokens, an open build, a recompute missing, older than its build or failed other than on the post-condition |
| `segments.csv` | segments and km per schema; the overlap must cover both, and each segment must have a `streams_access` row | pieces not covering either side, a missing access row, a species on one network only |
| `superset.csv` | every minimal cut has a full cut within 1 m, and km of full segments straddling a minimal cut | an unmatched cut |
| `parent_<wsg>.csv.gz` (gzipped after the run, 11.8 MB raw) | the parent table's prototype: each full segment's largest-overlap minimal segment, its gradient and length, the overlap and what straddles | |
| `access_km.csv` | `access_<sp>` km by code (-9, 0, 1, 2) on each network | |
| `access_open.csv`, `access_differences.csv` | pieces where a species reads -9, 0 or open differently | any piece of 1.01 m or more |
| `crossing_fields.csv` | km on which `dam_dnstr_ind`, `remediated_dnstr_ind` and each `has_barriers_*_dnstr` differ | |
| `overlay.csv` | km of user habitat range each network applies, and under-applies | |
| `connectivity.csv` | km the rear predicate (every rear rule) gives on accessible segments and the persisted flag does not, on each network, split between lines in a lake, reservoir or wetland polygon and the rest | |
| `gradient.csv` | minimal gradient against the length-weighted full gradient over its pieces | |
| `breaks_census.csv` | what put each minimal break there | a break with no named source |
| `placement.csv` | bcfishobs records placed by knowledge's `knw_link_place()` rule on each network: start-window branch against containing segment, offset, segment length, km above and below | |

**Why 1.01 m and not containment.** Observations cut first in the full build, and a later cut within 1 m of an existing end is skipped (`frs_break_apply()`, RUNBOOK §2). So a minimal cut can be absent from the full network, and a full segment can straddle it by up to 1 m. Pieces under 1.01 m left that way read another segment's access by construction, so they count as slivers, not violations.

## What crossing-based fields mean on this network

No cut falls at a crossing, so each field reads from the segment's start:

- **`has_barriers_anthropogenic_dnstr`, `has_barriers_pscis_dnstr`, `has_barriers_dams_dnstr`, `has_barriers_remediations_dnstr`:** true only when the crossing or dam lies below the segment's start, so a segment holding a crossing reads as below it up to the next cut. These lose km against the full network, apart from pieces of about 2 m or less at a minimal cut the full build skipped, where the minimal segment starts above the full one. On this network they say "below this segment's start", not "below this point".
- **`dam_dnstr_ind`, `remediated_dnstr_ind`:** whether the *next* feature downstream of the segment's start is a dam or a remediation. A crossing that no longer counts on a segment can expose a dam or remediation below it, so these can gain km as well as lose them.
- **`has_barriers_<sp>_dnstr`:** natural barriers cut this network, so these should move little. A barrier of another group is not cut here, which `access_open.csv` would show.
- **Mapping codes** inherit the same reading. The knowledge repo reads none of them.

Whether to flag or drop these fields on the minimal network is the parent-attribute follow-up's question, answered from `crossing_fields.csv`.

`subsurfaceflow` stays off, inherited from `default`.
