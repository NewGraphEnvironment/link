# link#264 — code-identity gaps in `fresh.log`

Shipped as **v0.50.0**. Closed the last provenance gaps before the 217-WSG run:
`fresh_sha` filled on 15 of 39 logged rows, `fresh_dirty` on **0**, and
`bcfishobs` — a model input that decides which barriers are skipped — carrying
no code pin at all.

**The premise the issue was written on was itself measured, and half of it was
wrong.** The dispatcher's NULL `fresh_sha` was not missing data; it was an
unread field. m1's installed `fresh` carried `RemoteType github`,
`RemoteRef v0.33.0` and a `RemoteSha` byte-identical to what every cypher
recorded, and `.lnk_pkg_git_sha()` simply never read it. Four documents stated
the false reason. Same lesson as #262: **measure before characterising, even
when the issue is your own.**

One `.lnk_pkg_git_state()` replaced two parallel resolvers, with a `RemoteSha`
tier between the env var and the `.git` walk; `bcfishobs_sha` and
`fresh_sha_source` joined both log tables; `fresh_sha` became a pre-flight
parity key; and `study_area_verify.sql` lost the host-aware tolerance along
with its cause.

**Two decisions departed from the issue body, and it was edited to say so.**
`bcfishobs` got a dirty *gate* rather than a `bcfishobs_dirty` column — `fwapg`
has no such column either, and one that is FALSE on every row by construction
is #257 pointing the other way. And `FRESH_GIT_DIRTY` in `cypher_prep.sh` was
demoted from the mechanism to belt-and-braces, because with the resolver built
correctly a cypher infers `FALSE` from `RemoteSha` anyway.

## Measurement

Three review rounds, **fourteen defects**, and the number worth keeping is that
rounds 2 and 3 found theirs **inside the previous round's fixes** — round 3's
findings were *all five* inside round 2's one fix.

| round | found | where |
|---|---|---|
| 1 | 5 | tests gated by the function under test; `RemoteSha` holding a version string (278 of 300 packages); tier-2 dirty attached to the wrong SHA |
| 2 | 4 | `update_hosts.sh` leaves fresh unpinned → the new assertions fail *after* spend; a missing `fresh_dirty` FAIL arm; both dirty probes failing toward skip |
| 3 | 5 | all inside round 2's `update_hosts.sh` fix: `\| tail -3` swallowing a failed install so the pin certified a build that never ran; `LINK_GIT_DIRTY=false` would have stuck `link_dirty` permanently FALSE on the dispatcher |

That last one is the one to remember: **#257 was a flag stuck always-TRUE, and
the proposed fix would have stuck it always-FALSE — the direction nobody can
notice.** Scope expansion into an install script, undertaken to close a real
gap, produced more defects than it removed and had to be narrowed rather than
extended.

Suite 1894 pass / 0 fail / 16 warnings (0.49.0 baseline 1825 / 0 / 16).

## Evidence

- `review-round1.md`, `review-round2.md`, `review-round3.md` — the full
  findings, including each round's list of *verified-clean* items, so they are
  not re-derived.
- Live verification ran against local docker `fwapg` into throwaway schemas
  (`zz_lnk_264_*`), dropped on exit — nothing durable was written, so there is
  no run log to cite. The two things it established: a log table built with the
  pre-#264 column set gains both new columns via `ADD COLUMN`, and a real write
  lands all four values on `log` **and** `log_recompute`.
- The verifier was swept across nine single-fault states on a synthetic
  two-host fixture. Healthy passes before *and* after every mutation — the
  first attempt reported a correct FAIL that had in fact errored on a column
  the fixture lacked, which is why the post-restore case now exists in
  `data-raw/study_area_verify_negative.sh`.

Closed by PR against `main`; branch `264-code-identity-gaps-in-fresh-log-fresh-sh`.
