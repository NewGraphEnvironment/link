# 2026-09 — issue #250: parallelise the post-consolidate recompute

**Outcome: shipped as v0.47.3 + v0.48.0.** The recompute runs N-wide behind
`--recompute-jobs=` (default 4), output is proven byte-identical to serial, and
recompute failures now fail the run — which they previously could not.

## Two things the issue did not know

**Its safety argument had a hole.** #250 argued each WSG's recompute writes only
its own rows, so order is irrelevant. True of everything except `lnk_access()`,
which unconditionally rebuilt ~38 **schema-scoped** barrier views per call. Two
distinct failures: `DROP VIEW` + a separate `CREATE` autocommit, leaving an
interval in which the view does not exist; and `CREATE OR REPLACE VIEW` takes an
`AccessExclusiveLock` whose *queued* request blocks every subsequent
`AccessShareLock`, so one job's DDL stalls every sibling's read until
`lock_timeout`. Fixed by hoisting the build out of the loop (load-bearing) and
removing the redundant DROP (defence in depth).

**Recompute failures could not fail the run.** `|| echo` inside the loop,
`RUN_INCOMPLETE` assigned before it, success line unconditional. A run in which
all 50 recomputes failed exited 0 and wrote a compare CSV. This was the more
consequential half — an incomplete recompute is *silently wrong* output, not
missing output.

## The measurement, which is not what the issue projected

**1.43× on 4 WSGs, 1.51× on 8, at `-j4` — not ~3.4×.** The pool reached 93% and
79% of the theoretical ceiling for those sets; the ceiling is low because a pool
cannot beat its slowest single job, and CHWK alone was 74% and 52% of the work.

**Two confident diagnoses were wrong first**, both from theorising about the
aggregate instead of reading the per-job distribution: a Postgres worker-pool
theory (refuted — disabling intra-query parallelism made scaling *worse*) and a
Docker I/O theory (refuted — 269 `pg_stat_activity` samples, 100%
`CPU(running)`). Full record: `research/recompute_parallel_2026_09_01.md`.

**Recompute cost does not track segment count.** SALR is 20% *larger* than CHWK
and finishes 20× faster — the cost is the downstream barrier walk. So bucketing
balanced on segments will not balance recompute time, and whether the 34-WSG
field set contains a dominant item is unknown and decides the real speedup.

## Four review rounds, 13 findings — the interesting part

Rounds 2, 3 and 4 **each found a defect inside the previous round's fix.** The
recurring class, named in round 3: *a value validated with one numeric grammar
and consumed with another.*

| round | input | failure |
|---|---|---|
| 1 | width `0` | `seq 0 -1` empty → `break` unreachable → hang |
| 2 | width `abc` | `[ abc -lt 1 ]` exits 2, guard falls through → hang |
| 3 | width `08` | `$((08-1))` "value too great for base" → hang |
| 3 | width `010` | **silently** an 8-slot pool; banner says 10 |
| 4 | width `1e20` | `10#` wraps to 7766279631452241919 → hang |

Closed by normalising **once** rather than adding a fifth predicate — shape check,
base-10 normalisation, then a 1..64 bound, in the pool where all three callers
meet it. The candidate set for a string consumed as a count is
shape / sign / value / base / magnitude; all five are enumerated in
`pool_probe.sh`.

**The probe was twice unable to fail**, which is worse than absent: the bad-width
cases had no deadline (a hanging guard was never reported), and the leading-zero
case asserted a *job count* — a proxy for width that cannot tell 8 slots from 10,
and which passed against the octal defect. It now derives peak concurrency
exactly from an ordered start/end event stream.

## Also found by review

- The shape-change regex matched **2 of Postgres' 4** refusals — `cannot drop
  columns from view` has no trailing noun, and collation was missed entirely.
- `lnk_fanout_judge`: a duplicate in `expected` returned "ok, 1/2 succeeded";
  `allow_empty` excused a job that reported and *failed*.
- The INCOMPLETE message named two files that the view-build failure path never
  creates.
- `recompute_parity.sh`'s coverage guard used `N_WSG` where the digest emits 2
  rows per WSG, surviving at half strength.

## Left open

- **Per-job `pkgload::load_all()`** — at `-j4` the database is active only ~28%
  of the time; the rest is R-side. Removing it changes the `LNK_LOAD` contract
  shared with `wsg_run_one.R` / `host_vintage.R` / `host_stamp.R`.
- **Why CHWK is 20× SALR at 80% of its size.** The makespan floor *is* the
  slowest WSG, so this is worth more than pool width — and it would speed up the
  serial path too. Likely a fresh-side question about `frs_network_features`
  over a barrier-dense drainage.
- **#257** — `link_dirty` is `t` on every dispatcher row and is false. Untouched
  here; the `.d/` subdirectory is gitignored so this work does not widen it.
