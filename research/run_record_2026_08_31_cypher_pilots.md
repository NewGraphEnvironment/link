# Does the v0.47.0 orchestration work on a real cypher? — 2026-08-31

First run record under the shape proposed in
[soul#129](https://github.com/NewGraphEnvironment/soul/issues/129).
Logs: `data-raw/logs/study_area_run/20260831_*`.

## Question

link v0.47.0 (#246) added pre-flight gates, a fresh-install path for cyphers,
and post-conditions around consolidate. **None of it had ever run against a
real droplet.** The provincial run it was built for is ~4 h and several hundred
WSG-hours; committing to that on unexercised code was the risk we were trying
to retire.

Two unknowns, and we could not answer either by reading:

1. Does the orchestration survive first contact with a cypher?
2. How long does a run actually take post-#223? Every timing on record
   predated the 2–3.5× segmentation change, so the estimate spanned 5–9 h with
   nothing to narrow it.

## Method

Four droplet spins, ~$1.00 total. Two tiny drainage-closed components
(`COWN`, `TSIT`) into a scratch schema `fresh_smoke`, so `fresh` was never
touched. Plus one read-only diagnostic spin that ran nothing but probes.

## Measurement

| spin | result | log |
|---|---|---|
| 1 | prep died. Whole diagnostic: `scp: Connection closed` | `20260831_164236_*` |
| diagnostic | `cypher_up` reports ready at **t+156 s**; `cypher@` first works at **t+383 s**. Marker mtime **2026-05-12** while `cloud-init status: running`, VM up 14 s | — |
| 3 | prep **succeeded** (fresh installed from GitHub on a droplet, first time). Two gates then fired wrongly | `20260831_174503_*` |
| 4 | **clean end-to-end, 7.0 min** | `20260831_190558_*` |

Per-segment modelling rate, measured on identical work:

| host | min / 1000 persisted segments |
|---|---|
| dispatcher (m1) | **0.0391** |
| cypher | **0.0872** — 2.23× slower |

Recompute: 0.0112 min/1k segments. Persisted/source segment ratio ≈ 3.5
(median of six WSGs).

Provenance, `fresh_smoke.log`, cypher row — the #246 Phase 5 acceptance test:

```
TSIT | cypher-job1 | link_sha 0fa2c27d486f | fresh_sha 7f12d99115b7 | fwapg_sha e6e1eb0f4718
```

All four columns non-null on a worker. They were all NULL before this work.

## Conclusion

Four defects found, all fixed:

| defect | where |
|---|---|
| readiness loop exhausted then ran `scp` anyway — no failure branch | link#251 |
| `cypher_up`'s marker is baked into the snapshot, so it never waited | rtj#248 → rtj#250 |
| parity gate's dirty check fires on every run (the run dirties its own repo) | link#252 |
| vintage gate conflated "table absent" with "statistics not yet collected" | link#252 |

The 2.23× ratio then rewrote the packer (link#253): balancing raw segments
balanced *work* and unbalanced *time*, leaving the dispatcher idle 96 minutes
on a provincial run. Packing by finish time cut the provincial modelling phase
**191 → 150 min** and moved the end-to-end estimate **5.0 h → 4.3 h**.

Field-scope run (34 WSGs) is now **~1.7 h**, not the 2.6 h projected from May
data and not the 9 h feared at the outset.

## Dead ends — kept, because they are the evidence

**The root cause was diagnosed correctly, retracted on a bad inference, then
confirmed by measurement.** The retraction is the instructive part:
`cypher_snapshot.sh:169` scrubs the marker and that line predates the image by
eleven days, so I concluded the scrub had *run*. It had not. Presence taken as
provenance — one level above the bug itself, which was the same error. One
`ls -l --time-style=full-iso` settled it, and should be the first command
against this class of question.

**Two of the four defects were in gates written to catch exactly that class**,
and both passed tests that could not fail: the dirty fixture set
`dirty = "FALSE"`, and the vintage fixtures never modelled a freshly-restored
database. The rule "a fixture set that cannot reach the failure mode is not
validation" had been written into this branch's own `findings.md` two days
earlier.

**A cheap probe reported success against a garbage input.** `tofu output -raw`
exits 0 with a "No outputs found" warning while a droplet is still creating, so
a non-empty check passed on multi-line prose and the probe ssh'd to nonsense
for a minute.

## What it cost

~$1.00 and about an hour. Each spin found something that would otherwise have
surfaced partway through a 4-hour run — and the first two would have surfaced
as `scp: Connection closed` with no further detail.
