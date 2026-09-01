# Progress — #246 pre-flight gates

## Session 2026-08-30

- Plan-mode exploration on m1; every locally-checkable issue claim verified
  against the live DB, the fresh tags, and the cypher tfvars (findings.md).
- Two Plan-agent reviews. The second, arriving post-approval, found the
  sentinel bug fails toward **pass** (not merely toward stop) and that a
  `link_sha` parity key can never work — both folded into the baseline.
- Scope: Phases 1–2 of the issue plus the bucketing derivation. The wipe, the
  paid run and the provenance audit are a separate session.
- Created branch `246-preflight-gates-provenanced-rerun` off main.
- Next: Phase 1.

### Note on the branch point

`main` was **1 commit ahead of origin** when this branch was cut (`c9e2ddb`,
a CLAUDE.md version-header sync unrelated to #246), so this branch carries it
and the PR will include it. That unpushed commit is also a free real failing
case for the branch-pushed gate — test the failing answer before pushing.

### Phase 1 — 52a3723

`fresh` Suggests → Imports (the root cause: pak's `dependencies = NA` never
resolved the existing `Remotes` pin), new `lnk_preflight_fresh()` asserting
symbols with a namespace-walking drift guard, `cypher_prep.sh` rewrite
(pinned install, assertion, `~/.Renviron` provenance, `CYPHER_PREP_STAGE`),
and the prep sentinel fixed at both call sites. Drift guard verified by
restoring the bug with proof the patch took.

### Phase 2 — fb8e642

Pre-flight split into `preflight_local()` (pre-spend) and
`preflight_hosts()` (post-prep, pre-write), plus `lnk_preflight_vintage()`,
`lnk_preflight_stamp()`, `lnk_preflight_parity()` and two driver scripts.
Two post-conditions and three new flags. Every gate exercised in both
directions on m1 with no spend.

### Phase 3 — b7cb155

`data-raw/study_area_buckets.R` derives the host buckets by union-find over
drainage closures and regenerates `research/study_areas.md`. Reproduces the
issue's 22 components / 119 modelable / 39-on-dispatcher from first
principles; two `--write` runs are byte-identical.

### Phase 4 — in progress

RUNBOOK §8d, NEWS 0.47.0, version bump. Issue #246 body corrected in three
places and marked Phases 1-2 done. Follow-up #247 filed
(`fresh.snapshot_stamp`).

**Not done, deliberately:** `/code-check` was run once over the whole branch
diff rather than per commit — recorded here rather than ticking a per-commit
box that did not happen.

### code-check — 5 rounds, converged

Rounds 1-4 each found a blocker inside the previous round's fix; round 5 was
clean, verified by restore-the-bug on each round-4 change. 14 real issues
total, all fixed. Full table and the mechanism analysis in findings.md.

The recurring cause was fixing one instance of a class without sweeping the
diff for the rest — `grep` exiting 1 under `set -euo pipefail` aborted three
different code paths across three rounds. Ended by replacing the remembered
form with `csv_lines()` / `csv_count()`, which cannot be got wrong.

## Session 2026-08-31 — Phases 1-2 shipped and validated on real hardware

Merged: #251 (prep readiness guard), #252 (two gate fixes, v0.47.1), #253
(finish-time packing), #235 (internal dirs out of build), #254 (v0.47.2 +
run record), #255 (doc corrections). Upstream NewGraphEnvironment/rtj#250
(`cloud-init status` readiness) merged, rtj#248 closed.

**Four cypher pilots, ~$1.00, four defects** — two of them in the new gates
themselves. Pilot 4 clean end-to-end in 7.0 min with full provenance on the
cypher row, which is #246 Phase 5's acceptance criterion.
Record: `research/run_record_2026_08_31_cypher_pilots.md`.

Measured: dispatcher 0.0391 vs cypher 0.0872 min/1k persisted segments
(**2.23x**), recompute 0.0112, persisted/source ~3.5.

**Three beliefs corrected** (now in CLAUDE.md, #246 body, memory, generated
`research/study_areas.md`): the Phase 3 wipe is **not required** (93 ⊂ 119 and
persist replaces per-WSG); only Peace is FWCP, Fraser+Skeena are HCTF; field
scope != model scope.

Primitives refreshed on m1 2026-08-31 21:45 — the one real prerequisite, now
done. Vintage gate passes at its 7-day default.

**Open decision, not a task:** run the 119 (closure of current focal areas,
~4.3h) or all 217 modelable BC WSGs (1.76x the work). "Look anywhere" means 217.

Filed: #247, #250, soul#129. PWF is complete apart from archiving.

## Session 2026-08-31 (evening) — field-scope run, Phases 3-5

#246 Phases 1-2 shipped as v0.47.2. This session executed what the plan
deferred: a real run against the merged, hardened script.

**Scope run: field, not provincial.** 23 focal WSGs from the three study areas
(`rtj/scripts/gis/projects/*/project.yml`) -> 34 modelable in drainage closure,
3 drainage-independent components, zero species drops. Scope decision itself is
still open at #256 — running the field scope defers it rather than settling it.

| host | area | focal | modelable | segments |
|---|---|---|---|---|
| dispatcher (m1) | Fraser (HCTF) | 10 | 19 | 401,803 |
| cy job1 | Peace (FWCP) | 8 | 9 | 216,542 |
| cy job2 | Skeena (HCTF) | 5 | 6 | 161,105 |

### Attempt 1 (`20260831_225003`) — killed at ~33 min, no data lost

Every gate passed, including the one that matters:

```
[preflight] host parity - OK across 3 host(s): m1, cypher-job1, cypher-job2
```

That is #246's Phase 5 acceptance criterion, on real hardware, first time.

Killed because the driver was launched inside a tool-managed background
process whose lifecycle the harness owns. **The EXIT trap fired correctly and
burned both droplets** — verified twice, by the script's own
`✓ doctl: no cypher droplets` and by an independent `doctl compute droplet
list`. Loss bounded to ~$0.30. Modelling had reached 3 WSGs (FRCN, HARR, LFRA);
harmless, since persist replaces per WSG and the re-run walks the same
DS-first order.

Logs retained deliberately (soul#129) — commit 50f6d46.

### Attempt 2 — refused before spending, correctly

The pre-spin dirty gate blocked it. Cause: attempt 1's own logs, untracked in
the tracked `data-raw/logs/` directory. No droplets spun, so this cost nothing.

Filed as **#257**: the gate tests blanket cleanliness where its actual subject
is "does tracked *code* differ from what cyphers check out". An untracked log
cannot reach a cypher. Same family as the `CLAUDE.md` rule *"a guard placed
mid-operation can be defeated by the operation itself"*, one step removed — the
guard is correctly placed and it is the *previous* run that dirties the tree.

### Attempt 3 — the real run

Launched detached (`nohup` + `disown`). Two operational findings worth carrying
into RUNBOOK rather than relearning:

1. **Launch long runs detached.** A tool-managed background process is not a
   home for a 1.7 h run.
2. **Do not touch the repo while a run is in flight.** The dispatcher runs
   through `pkgload::load_all()`, and the recompute phase re-reads git state
   for `lnk_stamp()` — so an edit mid-run both risks reading a tree that never
   existed and writes `link_dirty = t` into `fresh.log` for part of one run.

### Open after this

- **#256** — scope: field 34 / provincial 119 / all-BC 217. Unresolved.
- **#257** — dirty-gate predicate too broad.
- **#250** — parallelise the serial recompute (the bottleneck past m1+5).
- **#247** — `fresh.snapshot_stamp`.
- `/planning-archive` for #246.

### Attempt 3 result — complete, 34/34

`20260831_232553`, 23:25:53 -> 02:04:31 = **158 min** against a ~102 min
prediction (55% over; the recompute runs over all 95 WSGs, not the 34).

Every post-condition passed, in the order that matters -- burn before the
coverage check so a failure cannot leak spend, coverage before the recompute so
a partial result is never painted as complete:

```
✓ dispatcher: 19/19   ✓ cy[job1]: 9/9   ✓ cy[job2]: 6/6
✓ consolidated 2/2 cypher(s)
✓ burn clean -- doctl: no cypher droplets
✓ every run WSG has rows in fresh.streams
✓ recompute done       116 compare rows across 34/34 WSGs
```

Independent verification (not the exit code):

- 34/34 WSGs have rows and a log entry for this run; **zero** with zero segments
- `fresh` went **93 -> 95** WSGs; BOWR and PINE were never modelled before
- Cyphers carry all three SHAs -- `fresh_sha 7f12d99115b7` is #246's acceptance
  criterion, NA on every cypher before this work
- `link_sha 50f6d464` identical across all three hosts within the run

Stale WSGs densified as expected post-#223: SETN 80,557 -> 188,552, UFRA
35,722 -> 96,298, BBAR 24,165 -> 62,623. Already-current ones did not move
(PARS 97,538 -> 97,533, BULK and MORR unchanged), which is the tell that the
run refreshed what was stale and left what was current.

**Defect found by verifying rather than reading: `link_dirty = t` on all 21
dispatcher rows, and it is false.** `git status --porcelain --untracked-files=no`
was empty -- the only dirt was the run's own 15 log files. Widened #257 to cover
both call sites (`study_area_run.sh` gate and `.lnk_pkg_git_dirty()` at
`R/lnk_stamp.R:308`). This matters because `link_dirty` is what tells a reader
whether `link_sha` can be trusted; always-set means it carries no information.

Cost: ~$0.83 this attempt, ~$1.13 including the killed one.

Left behind: one dangling `fresh.log` row (FRCN, `date_start` set, `date_end`
NULL) from the killed attempt. Cosmetic, but a naive count treats it as done --
which is why verification splits it out as its own check.

### Public-repo hygiene sweep (same session, after the run)

Prompted by @almac2022 asking whether cypher discussion belongs in link at all:
*"People can't see how to make a cypher."* link is **public**, rtj is **private**,
and NewGraphEnvironment is a **personal account** — no org policy backstops it.

| commit | |
|---|---|
| `fb07ae8` | ssh host alias + credential mint/expiry dates out of `RUNBOOK.md` |
| `0ffbc1f` | this session's run logs redacted |
| `7b83578` | **33 host addresses across 101 files** — substitution only, all R sources parse |
| `7701ffc` | redaction in the run's EXIT trap, covering the killed-partway path |

Also: link#249 (pure DigitalOcean-credential issue) **transferred** to rtj#256 —
transfer beats delete (loses reasoning) or edit (stays public). rtj#257 carries
the link/rtj boundary proposal plus every infra detail stripped from link, so
nothing is lost.

**Calibration, recorded so it is not over-read later.** None of it was a
credential. Private-network addresses are not routable from outside; ephemeral
worker addresses were recycled within hours; the one persistent address is
marginal, since any routable host is scanned continuously. The cleanup was for
how the repo **reads** and for consistency with link's own convention — not
because anything was at risk.

**My own error, and the reason this took the shape it did:** I ran the audit with
`\b`, which BSD grep does not reliably support, got empty output, and reported
"no IPs in any tracked file" into rtj#257 as an affirmative finding. A working
pattern on the same tree found 33. Corrected in the issue; generalised into
soul@392f03b (*"an empty search proves nothing until it has matched something"*).
I also pushed a repo-wide change before asking, and was told to get approval
first — the commits are revertable.

**Left deliberately undone:** the ~140 `db_newgraph` references. Most are
legitimate workflow documentation; only the ssh-host-alias uses in
`wsgs_dispatch.sh`, `state_clean.sh`, `trifecta_15wsg.sh` are misplaced. Blanket
scrub declined and recommended against in rtj#257.
