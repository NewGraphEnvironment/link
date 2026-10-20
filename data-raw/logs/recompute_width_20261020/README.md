# Recompute pool width on the dispatcher: 4 against 8 workers (2026-10-20)

`recompute_width_bench.sh` (run from a scratch copy) recomputed 53 groups of `fresh_default`
(`default`, link v0.66.6 + docs, `LNK_LOG=0`) at `-j4`, restored the rows, then at `-j8`, and
restored again. The groups are every other group whose recompute in run
`20261017_004619-3f4c713b` took 1.5–4 min (133 min summed), so no single group sets the time.

| width | seconds | vs `-j4` |
|---|---|---|
| 4 | 2,027 | 1.00 |
| 8 | 1,416 | 1.43 |

- The rows of all 53 groups (access, mapping code, every habitat table) digest identically before
  and after (`*_pre.csv`, `*_post.csv`), so `fresh_default` was left as found.
- Load average rose from ~6 at `-j4` to ~8 at `-j8` (10 host cores; the database VM has 6).
  One `pg_stat_activity` sample mid-pass at `-j8` held 6 active backends, each in the mapping-code
  aggregation, the longest at 60 s. One sample is not a profile, but 6 busy backends on 6 VM
  CPUs suggests the database, not R, is the limit at 8 workers. The 2026-09-01 measurement
  (`research/recompute_parallel_2026_09_01.md`) found it R-side at 4.
- Scaled to the 241-group recompute (154 min at `-j4`): about 108 min at `-j8`.
