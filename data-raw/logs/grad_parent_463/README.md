# Classifying on the minimal parent's gradient: the proof build (#463, #462)

**Question.** Does a build that classifies each full-network segment on its minimal-network
parent's gradient (`pipeline: gradient: source: parent`, bundle `default_parent`, token
`grad-parent`) change only what that gradient decides? And what does the near-river
distance cost when it stays the segment's own rather than the parent's (#462)?

**Answer.** Yes. On BULK, SETN, MORK and COTR the parent build holds `default`'s segments
exactly, reads the parent's gradient on every segment, and leaves access unchanged in every
column. Every habitat difference sits either on a segment whose gradient changed or in a
cluster that holds one. Rearing rises (CH +3.9 %, ST +3.3 %, CO +1.5 %, BT +1.1 % over the four
groups) and spawning barely moves (at most ±0.33 %). The near-river transfer cost is 0 km in
all four groups.

## Run decisions

- **Groups:** BULK, SETN, MORK, COTR, the minimal network's proof groups (#415), on m4's local
  fwapg. Not the province (operator, 2026-11-09).
- **Builds:** for each group, `default` into the scratch control schema `zz469_control`, then
  `default_parent` into `fresh_default_parent`. Both ran serially from one commit
  (`6f0eea81`, 0.81.0, clean tree) with `LNK_LOAD=loadall`, `LNK_GUARD_DOWNSTREAM=warn` and a
  30 min statement bound, after five quiet database minutes (`run.sh`).
- **Parent table:** `fresh_default.streams_parent` (#444), checked current for the four groups
  before building (`verify_before/verify.tsv`: `streams_parent_build.R --verify`, every
  segment has one row naming the newest `default` and `default_minimal` builds).
- **Inputs:** the four groups' `fresh_default` builds read the same primitive loads as m4
  holds now (`artifact_ids.csv`). The 36 of 48 rows that carry a version identity all match.
  The other 12 rows (`cabd.dams`, `whse_fish.pscis_assessment_svw` and
  `fwa_stream_networks_order_parent` in each group) carry none on either side, so they are not
  compared. The comparison was recorded after the builds, from tables the builds do not write.

## Results

All eight builds exited 0, between 05:12 and 06:02 UTC on 2026-11-13, taking 3.0 to 12.9 min each
(`status.tsv`, `<step>_<WSG>.log`). No group was refused on mapping. `proof.R` passed every
check (`verdict.csv`). It ran at 06:41 UTC, after a machine restart and Postgres's crash
recovery; it re-read the builds from the database.

| check | file | result |
|---|---|---|
| builds are this commit's, clean, with the expected tokens and notes | `builds.csv` | 8 of 8 |
| segments identical across control, parent and `fresh_default` | `segments.csv` | BULK 42,458; SETN 80,538; MORK 51,930; COTR 28,473 |
| parent `gradient` equals `streams_parent.gradient_minimal`; control equals `fresh_default` | `gradient.csv` | every segment |
| `streams_access` identical, every column | `access.csv` | 0 differences |
| habitat differences classed; none unexplained | `habitat.csv`, `habitat_classes.csv` | 0 unexplained |

Gradient changes on 3,316 to 3,777 km per group (BULK 3,777 of 14,642 km, COTR 3,501 of 8,268).

Habitat summed over the four groups, for the species and flags that moved:

| species | flag | control km | parent km | change |
|---|---|---:|---:|---:|
| CH | rearing | 6,902.8 | 7,175.0 | +3.94 % |
| ST | rearing | 3,935.5 | 4,065.0 | +3.29 % |
| CO | rearing | 5,139.0 | 5,216.9 | +1.52 % |
| BT | rearing | 10,287.2 | 10,396.7 | +1.07 % |
| CM | spawning | 2,531.2 | 2,539.6 | +0.33 % |
| PK | spawning | 3,622.3 | 3,629.5 | +0.20 % |
| CO | spawning | 3,528.7 | 3,533.1 | +0.13 % |
| CH | spawning | 4,089.5 | 4,090.2 | +0.02 % |
| BT | spawning | 6,327.5 | 6,324.1 | −0.05 % |
| ST | spawning | 1,932.9 | 1,930.3 | −0.14 % |
| SK | spawning | 306.6 | 305.8 | −0.28 % |
| BT, CO | wetland rearing | | | −0.36 km each (SETN) |

Spawning moves both ways in roughly equal amounts (BT gains 74.1 km and loses 77.5).
Rearing mostly gains (CH +317.3, −45.0 km). That is the direction the minimal network
moved in (#415, BULK CH 2,101 to 2,205 km). Here, on the full network's segments, BULK CH goes
from 2,101 to 2,208 km. Accessible km, lake rearing and SK rearing do not move.

**#462, the near-river transfer cost.** CH's near-river pair applies only to 1050/1150
lines under `default`. On those lines, accessible CH segments failing the rear width whose parent
is within 1,000 m of a 15 m river while the segment itself is not: 0 in each group
(`near_river_462.csv`). The segment's own distance and its parent's differ on 94 segments, by up
to 541.6 m, but none crosses the 1,000 m line (`near_river_462_distances.csv`). The number is not
comparable to knowledge#120's 1,042 km, which applied the pair to every line.

## Review

`/code-check branch` ran three rounds before the builds:

| round | findings | fixed | inside the previous fix |
|---|---|---|---|
| 1 | 3 | 3 | — |
| 2 | 2 | 2 | yes |
| 3 | 2 | 2 | yes |

Round 2 found a defect inside round 1's fix. So round 3 enumerated all 49 checks in the
branch's R code and in `proof.R` against the mechanism named: a missing, NA or stale input
read as agreement. The two `proof.R` checks it found are fixed (`6f0eea81`), and the R code was
clean in that enumeration (`review-round1.md` to `review-round3.md`).

## Errors on the way

- Two launches before this one were stopped and relaunched at a new commit. They leave open
  rows in `zz469_control.log`; `proof.R` reads the newest closed row.
- The first proof run was killed part way through by a machine restart (Docker Desktop did not
  come back, and Postgres replayed about 7.9 GB of WAL on restart). The builds' rows were intact
  afterwards, and the proof was re-run in full.
