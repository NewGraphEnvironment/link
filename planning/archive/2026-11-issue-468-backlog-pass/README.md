## Outcome

A backlog pass for link with `/backlog-sweep`, run under `/planning-init` because of its size: every one of
the 117 other open issues was read with its comments (three read-only readers, 39 each; their digests are in
`findings.md`), each premise was checked against `origin/main` f8a45c29, and the reference graph and the peer
issues a batch waits on (knowledge, fresh, fwapg, crate, floodplains, the infrastructure repository) were
measured. The result is `planning/backlog.md`: 20 batches grouped by the files they edit and the cost they
share, folded into 13 moves with umbrellas #469–#481 (two waiting: move 12 on knowledge#139's flow-method
decision, move 13 on fresh 0.54.0), 15 singles, 5 issues placed on the speed, provenance and minimal-run
tracks, and 21 issues closed with their reasons. Every link issue knowledge waits on is placed with the
knowledge move or track it holds up, in words: #460, #462 and #463 (move 1, knowledge#120), #400 and #434
(move 2, knowledge#178), #402 and rainbow trout's return (move 4, knowledge#132 and #148), #346 and #343
(move 12, knowledge#139 and #140). A Plan review after the go found no miscount but corrected the closure
wording (each now names the PR or issue that superseded it, and #369's and #374's evidence matches their
bodies), three move dependencies, and #269's place (moved out of the waiting move, since a host re-prep can
pull an unpinned fresh before 0.54.0 exists). Learned: done work is often never closed (#185, #196 shipped in
May), and an issue's "if we never do" line, where one exists, is the fastest closure test; 39 of the oldest
issues carried none.

## Measurement

Open issues 118 → 110 (21 closed, 13 umbrellas filed). Placement of the 118 frozen: 76 batched, 15 single,
5 on tracks, 21 closed, #468 itself. Reference-graph hubs: #402 named by 8 open issues, #377 by 7, #398 and
#369 by 5, #400 and #444 by 4. Coverage, the tick of every open move on a copy, and the public scan of the
file and all 13 umbrella bodies were each clean; `backlog_moves.sh next` prints `/planning-init #469`.

Closed by: PR (this branch, `468-backlog-pass-batch-the-open-issues-into`)
