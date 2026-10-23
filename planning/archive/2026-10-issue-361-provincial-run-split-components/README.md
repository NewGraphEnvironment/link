## Outcome

The provincial `default` run that #364 and #367 owed was built (run_uid `20261023_074321-24d85e8c`: 241 groups
into `fresh_default` at link 0.68.0 on fresh 0.42.0, m1 plus three cloud hosts, both verifiers pass at 241), and
the issue's question was answered: a drainage component can be split across hosts. The Peace's 26 groups
modelled on two hosts in the worst order, consolidated and recomputed, digest identical to the one-host build in
everything the modelling order can reach, so the buckets generator gained `--atom=group`, the resolver shim
`--exact`, and the driver `--buckets-exact` (with `bucket_mode` in `run_wsgs.tsv`). Hosts are now packed on
measured minutes at equal speeds. The verifier was fixed to pass a run that took the #348 path (a failed attempt's
open log row superseded by a finished one). bcfishpass parity at 0.68.0 is 48/50, as before. Released as 0.68.1.

What was learned, beyond the verdict: one m1 statement (fresh's near-river walk on OKAN) ran over four hours and
re-runs in 59 s on the same table, mechanism unknown, and the driver bounds no statement; cloud hosts idle for
hours waiting for the dispatcher (#369); and a quantity restated rather than derived from its artifact was the one
defect class code review kept finding (four rounds, nine numbers, among them the five TOOD digests the split
verdict first left untraced).

## Measurement

| what | number | what changed because of it |
|---|---|---|
| split test digests | 387 of 442 identical; 55 = 44 cross-host arithmetic (≤ 3.7e-9 m) + 11 test scope (NATR 2 and TOOD 2 segments whose downstream barriers sit in groups outside the 26) | group atoms allowed; "identical across hosts" is a digest after rounding |
| same-host control | MILL, LPCE rebuilt on m1 alone: identical in every model-time table but the gate-blanked habitat rows | the cross-host deltas are architecture, not order |
| packing on measured minutes | est. ~218 min per host; cloud 247 / 260 / 257 min of modelling (2026-10-17 packing: 165–272) | `--minutes-schema`, equal speeds by default |
| atoms compared (246 groups, 1,077 host-min, largest component 231) | 4 hosts 270 = 270; 5 hosts 216 < 231 | group atoms pay from five hosts |
| recompute, 240 groups, `-j8` | 110 min wall, 839 min summed, median 2.7 min | — |
| consolidate, 3 hosts | 42 min | — |
| OKAN walk statement | > 4 h in the run; 59 s after it (KTSU 65 min → 3 s) | no fresh issue; driver timeout drafted |
| cloud idle after the legs | ~17 host-hours | #369 filed, #170 closed |
| parity | 48/50; CO rearing −0.3 ADMS, −1.3 BULK (predicted), −1.4 BABL (prediction missed) | `research/bcfishpass_parity.md` |

Wrong turns kept: the fresh issue on the walk's plan shape on lake groups was drafted and withdrawn when the
statement re-ran in seconds; the split verdict first counted 6 scope digests (TOOD missed, then "six FROG rows"
from a truncated query, in fact 140 barriers across four groups); the first parity run was discarded because the
repo it modelled from was edited mid-run (`link_dirty`).

## Evidence

`data-raw/logs/provincial_361/` (README indexes it), `data-raw/logs/study_area_run/20261023_074321_*`,
`data-raw/logs/study_area_run/20261023_202311_*`, `data-raw/logs/parity_0.68.0/`,
`data-raw/logs/study_area_run/20261023_215312_*`. Records: `research/study_area_run.md`, "The province-wide
`default` run (2026-10-23)"; `research/bcfishpass_parity.md`.

## Owed

- Drop `fresh_default_20261017` once no before/after diff needs it (operator's call).
- A `job4` tofu workspace in the infra repo, if a 5-host run is wanted; group-level packing is
  worth ~30 min there and more beyond (measured: 216 against 231 min at five hosts).
- Drop the scratch schemas `fresh_361a`, `fresh_361b`, `fresh_361c` and remove the worktree
  `~/Projects/repo/link-wt361` after the merge.
- Two follow-up issues drafted for the operator's review, not filed: a per-statement timeout in the driver, and a
  scoped pre-run gate (`drafts/followup_issues_timeout_pretest.md`).

Closed by: PR (see `git log`), branch `361-provincial-run-can-a-drainage-component`
