# minimal_breaks_415 — is the minimal network the full network with fewer cuts? (#415)

**Status: scripts ready, real proof not run.** This directory holds the scripts for the proof builds. The real run waits for #432 to merge, since pausing KO and RB moves which species cut streams, and folds in #433's keep-or-drop measurement. Its evidence and the write-up land on a second branch. A smoke run exercised the scripts and is not evidence: ADMS on 2026-11-02 at `e287abcb`, on the installed fresh 0.52.0 against the `v0.48.0` pin. `run.sh` and the recompute passed, `proof.R` passed its checks and wrote every CSV, and the scratch schemas were dropped. The same `proof.R` with the two schema names swapped stopped on the commit-and-token, superset and census checks, so those guards fire.

## Question

`default_minimal` cuts streams only at access-gradient positions, falls and user-definite barriers. Does dropping observation, habitat end point and crossing cuts change segmentation and nothing else a tuning reads, and where it changes more, by how much?

## Run decision (for the real run, restate before launching)

- **Software:** `proof.R` reads the fresh version from `builds.csv`; install the pinned one or say why not.
- **Groups:** BULK plus two or three chinook-rearing and crossing-heavy groups, picked from `pick_groups.sql` when the proof runs, and named here with why. Check each is on `cw`, since `proof.R` reads channel width only.
- **Schemas:** `zz415_default` (`default`) and `zz415_minimal` (`default_minimal`), scratch on the local fwapg, published nowhere, dropped when the write-up lands.
- **Order:** downstream-first, passed to `run.sh` in that order. Serial, because both bundles share `working_<wsg>`. In each group `default` runs first, so `working_<wsg>` holds the minimal build the census reads.
- **One commit:** `run.sh` refuses tracked changes, and `proof.R` stops unless both builds' log rows name one clean `link_sha`, the expected cut tokens and one `acc` and `flow` token. Edit nothing in the checkout while it runs.
- **Recompute pass rule:** exit 0, or exit 1 with the downstream-dam post-condition (`BLOCKED (link#227)`) as the failure. That check runs after the work commits, and a scratch schema holds no groups below the ones built. `status.tsv` records `yes` or `postcondition`.

```bash
bash data-raw/logs/minimal_breaks_415/run.sh BULK <WSG> <WSG>
Rscript data-raw/logs/minimal_breaks_415/proof.R --wsgs=BULK,<WSG>,<WSG>
```

## Checks

| file | what it answers | stops on |
|---|---|---|
| `status.tsv` | minutes, exit, pass rule and segments per step | |
| `builds.csv` | which commit and tokens each build carries | not one clean commit, wrong tokens |
| `segments.csv` | segments and km per schema; the overlap must cover both | pieces not covering either side |
| `superset.csv` | every minimal cut has a full cut within 1 m, and km of full segments straddling a minimal cut | an unmatched cut |
| `parent_<wsg>.csv` | the parent table's prototype: each full segment's largest-overlap minimal segment, its gradient and length, the overlap and what straddles | |
| `access_km.csv` | `access_<sp>` km by code (-9, 0, 1, 2) on each network | |
| `access_open.csv`, `access_differences.csv` | pieces where a species reads -9, 0 or open differently | any piece of 1.01 m or more |
| `crossing_fields.csv` | km on which `dam_dnstr_ind`, `remediated_dnstr_ind` and each `has_barriers_*_dnstr` differ | |
| `overlay.csv` | km of user habitat range each network applies, and under-applies | |
| `connectivity.csv` | km the stream rear predicate gives on accessible segments and the persisted flag does not, on each network | |
| `gradient.csv` | minimal gradient against the length-weighted full gradient over its pieces | |
| `breaks_census.csv` | what put each minimal break there | a break with no named source |
| `placement.csv` | bcfishobs records placed by knowledge's `knw_link_place()` rule on each network: start-window branch against containing segment, offset, segment length, km above and below | |

**Why 1.01 m and not containment.** Observations cut first in the full build, and a later cut within 1 m of an existing end is skipped (`frs_break_apply()`, RUNBOOK §2). So a minimal cut can be absent from the full network, and a full segment can straddle it by up to 1 m. Pieces under 1.01 m left that way read another segment's access by construction, so they count as slivers, not violations.

## What crossing-based fields mean on this network

No cut falls at a crossing, so each field reads from the segment's start:

- **`has_barriers_anthropogenic_dnstr`, `has_barriers_pscis_dnstr`, `has_barriers_dams_dnstr`, `has_barriers_remediations_dnstr`:** true only when the crossing or dam lies below the segment's start, so a segment holding a crossing reads as below it up to the next cut. These can only lose km against the full network. On this network they say "below this segment's start", not "below this point".
- **`dam_dnstr_ind`, `remediated_dnstr_ind`:** whether the *next* feature downstream of the segment's start is a dam or a remediation. A crossing that no longer counts on a segment can expose a dam or remediation below it, so these can gain km as well as lose them.
- **`has_barriers_<sp>_dnstr`:** natural barriers cut this network, so these should move little. A barrier of another group is not cut here, which `access_open.csv` would show.
- **Mapping codes** inherit the same reading. The knowledge repo reads none of them.

Whether to flag or drop these fields on the minimal network is the parent-attribute follow-up's question, answered from `crossing_fields.csv`.

`subsurfaceflow` stays off, inherited from `default`.
