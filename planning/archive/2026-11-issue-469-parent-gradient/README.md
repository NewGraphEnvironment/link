## Outcome

Backlog move 1 (#469): link can now classify each full-network segment on its minimal-network parent's gradient. `pipeline: gradient: source: parent` sets each working segment's gradient from `<schema_full>.streams_parent` between break and classify, and the new bundle `default_parent` resolves to `cut-full-top acc-v5 grad-parent q-fwapg` (#463). `grad-fwa` names the Freshwater Atlas segment's gradient (#460). #420 closes with a doc line (older builds stay filed by run id). #462's near-river transfer cost was measured, not carried. Two judgements guard the build: one before the log row opens, one before gradient is set. Code review took three rounds over the code: round 2 found a defect inside round 1's fix, and round 3 ended the loop with an enumeration of 49 checks against the mechanism, a missing, NA or stale input read as agreement. A fourth round checked the docs' claims against the code and CSVs and fixed seven, including two numbers taken from the wrong artifact and one that no script produced. The run was interrupted twice: once by the database going down, and once when m4 restarted mid-proof. The builds survived Postgres's WAL recovery, and the proof was re-run in full.

## Measurement

BULK, SETN, MORK and COTR, built under `default` (control) and `default_parent` at `6f0eea81` on m4, 8 of 8 exit 0, 3.0 to 12.9 min each:

- Segments and `streams_access` are identical between control and parent, and the parent's `gradient` equals `gradient_minimal` on every segment. The gradient changes on 3,316 to 3,777 km per group.
- Every habitat difference sits on a changed-gradient segment or in a connected cluster holding one; 0 unexplained. Over the four groups, rearing rises (CH +3.94 %, ST +3.29 %, CO +1.52 %, BT +1.07 %) and spawning moves within ±0.33 %, both ways. BULK CH rearing goes 2,101 to 2,208 km, against 2,205 in #415's minimal-network proof. So on BULK, the minimal network's rise does not need its longer segments.
- #462: 0 km of CH rearing lost in each group. Over all 1050/1150 segments, own and parent near-river distances differ on 94, by up to 542 m, and none crosses 1,000 m. Not comparable to knowledge#120's 1,042 km, which applied the pair to every line.
- Inputs (plan A1): 36 of 48 artifact rows carry an identity and all match. A first join on table name alone read every group's FWA stream network as changed, because that table is one object per group.

Write-ups: `research/minimal_network.md`, "Classifying on the parent's gradient"; `research/output_vocabulary.md`; RUNBOOK §6b.

## Evidence

`data-raw/logs/grad_parent_463/` (its README; `review-round*.md` for the four review rounds).

## Owed

- Close #460, #420 (doc line), #462 (measured cost, carry option noted), #463 by the PR.
- knowledge#120 can archive `grad-fwa` runs and read a link `grad-parent` build: say so there.
- A provincial `default_parent` build waits for an operator decision (not this move).
- knowledge's pick needs a bundle extending `default_parent` with its thresholds; tell
  knowledge#120 that, not that its pick is drawn (AC3).

Closed by: the PR from branch `469-backlog-move-1-the-parent-gradient-on-th`.
