# Code review, round 3: link#374 (early recompute), `git diff b24778b9...HEAD`

## Checklist read

- **code-check.md** (index read in full). Prose of the `## Mechanisms` H3s, table rows skipped. Read in full: "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Zero-length, empty, and unset are three different things", "One fact derived twice". Opening paragraphs only: "Verification that reads its own output", "A guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that share a harness", "Restore the bug and prove the guard fires", "A shared working tree…", "A wrapper's exit is not the work". Not read: "The probe is broken…", "Written data outlives the fix", "Serialization loses meaning silently", and the ~30 stand-alone, security and spreadsheet rules (index lines only).
- **code-check-shell.md** (index read in full). Full sections: "`wait` with no argument…", "Parallel writers sharing one output file…", "A second `trap … EXIT` replaces the first", "Put cleanup on the EXIT trap, not RETURN", "`for x in $(cmd | grep … || true)`…", "awk `==` compares version strings as numbers". The other ~65 headings: index line only.
- **code-check-r.md** (index read in full). Full sections: "`read.delim()` quotes by default", "as.POSIXct on a Date…", "`$` on a list partial-matches", "`ifelse()` with an all-NA test…", "Postgres row order…", "`on.exit()` at a script's top level never fires", "A `data-raw/` script must load the source tree". The other ~110 headings: index line only.
- **code-check-spatial.md**: index headings only (93). Only the FWA rules touch `recompute_deps.R`, and their index lines were enough.

## Mechanism

Every earlier finding has the same shape. A check infers a fact about the world (a group landed, a recompute started, a gate ran, two schemas were compared) from a record, and that record has a second writer, a second clock, or a second reason to be empty. When the record is absent or reads as a default, the check takes the safe-looking answer: NA becomes "never landed", no row becomes "nothing ran", an empty map becomes "nothing blocks", and an unlisted file means nothing was checked. The fixes so far have closed the instances they were shown. They have not walked every branch where a missing or unparseable value turns into a verdict.

Where the mechanism reaches, with a verdict for each:

- `recompute_landed`: **holds**. An unreadable header, another run_uid, a database that does not answer, or a missing table (strict `.hosts_query`) returns 1. A missing state file is a known "nothing landed", because `in_flight` is written before the first copy. An `ok` row whose post-copy rewrite failed stays `in_flight`, which is fail-closed.
- `recompute_ready`: **holds**. One quirk, harmless: it reads "skip" per group with any-row semantics, while `recompute_landed` (and the audit) read it per row. They diverge only when one host's row says `yes` and another's says `no`, and SKIP is deterministic (no modelled species), so nothing is read either way.
- Audit, dispatcher arm: **same clock** (both `now()` on the dispatcher database), and overlap groups are skipped. **Does not hold** in the no-start branch (finding 1).
- Audit, remote arm: **same clock** (driver). Truncation to whole seconds errs safe, because launch `now` is taken after the poll read `ok`. **Does not hold** where the landing time cannot be parsed (finding 2).
- Audit, never-landed branch: by design for a group that truly never landed. It also captures "landed, unparseable time" (finding 2).
- Audit, no-start / fallback branch: `start_unrecorded` → exit 2 holds for a missing or failed launch record or `fallback.txt`. `no_recompute_row` → pass **does not hold** (finding 1). `after_final` assumes a fallback group's earliest start was the fallback's own. That fails only if a scheduler launch went unrecorded (the window between `recompute_one &` and the `>> launched.tsv` append, which under `set +e` fails silently) and the scheduler then died. Very narrow, not reported separately.
- Finish, launched count (`n_early`): display only, guarded. **Holds.**
- Finish, the `unread` remedy: **does not hold** (finding 3, the other caller of the audit).
- `recompute_deps.R` empty map: refused in R (no line or owner pairs) and again in the driver (header plus more than one line). **Holds.**
- View key, unreadable catalog: zero rows or NA def → the view is replaced and no key is written. **Holds**, and the failure direction is a lock, never a stale view.
- `ab_compare.R`: guarded on `streams_access` rows existing in `a`. A table absent from `a` is silently not compared, a residual too minor to report. **Holds** for its use.
- `digest_test.R`: guarded on rows in `all`. Its negative control does not reach the exit status (finding 4).

## Findings

1. **[fragile] `data-raw/recompute_audit.R:106,112`: a missing `log_recompute` row is read as "the gate never committed", and the dispatcher arm passes.**
   - For a dispatcher dependency, `start` comes only from `log_recompute.date_start`. When the group has no row, the verdict is `no_recompute_row` and the audit exits 0, even when `launched.tsv` shows the scheduler started it and its `.rc` says 0.
   - A row is absent for a second reason besides "the job died before its insert". `wsg_recompute_one.R:109` skips the insert whenever `LNK_LOG=0`, and it still runs `lnk_habitat_gate` (line 184).
   - `recompute_sweep.sh` and `recompute_parity.sh` export `LNK_LOG=0`. The driver neither clears nor refuses it, and the scheduler's jobs inherit the driver's environment. So an operator shell left with `LNK_LOG=0` turns every dispatcher-dependency pair into a pass, which is exactly the readiness bug the audit exists to catch.
   - Fix: treat "no recompute row but `.rc` = 0 (or a launch recorded)" as cannot-audit (exit 2), or refuse/unset `LNK_LOG` for the scheduler's jobs.

2. **[fragile] `data-raw/recompute_audit.R:90-94,110`: a remote dependency that landed but whose `state_utc` cannot be parsed is classed `dep_never_landed`, and the pair is skipped.**
   - `land_remote` returns NA both for "no `ok` row" and for "an `ok` row whose time is blank or unparseable".
   - `HOST_CONS_UTC[$ws]=$(.legs_now) || HOST_CONS_UTC[$ws]=""` (`study_area_legs.sh:117`) writes a blank time on an `ok` row. The scheduler acts on that row (it reads only `state == ok`), so the pair it acted on is the one the audit drops.
   - Unlikely (`date -u` failing), but it is the mechanism exactly. An `ok` row with no parseable time should be `start_unrecorded`-style "cannot audit", not "never landed".

3. **[bug, low] `data-raw/study_area_finish.sh:893` (the `RC_AUDIT=unread` remedy): the printed re-audit command omits `[out.tsv]` and `fallback.txt`.**
   - After a run whose scheduler died and whose fallback pool ran, every remote-dependency pair of a fallback group re-reads as `start_unrecorded`. The remedy therefore exits 2 again however healthy the run was.
   - The driver's own call (line ~666) passes both. This is the two-callers shape: the r2 fix added the 8th argument to one caller only.
   - Fix: print `… $RC_DIR/launched.tsv $LOG_DIR/${TS}_recompute_audit.tsv $RC_DIR/fallback.txt`.

4. **[fragile] `data-raw/logs/recompute_early_374/digest_test.R:113-118`: the negative control does not gate the exit.**
   - The header says `closure` must not match `all`, "otherwise the test cannot tell the rules apart". Yet `closure_differs` is only printed, and the script exits 0 on `line_ok` alone.
   - A group whose line and closure sets give identical results, the case where the test discriminates nothing, therefore passes as evidence for the line rule.
   - The committed NATR and TOOD runs did print `closure differs: TRUE`, so the recorded evidence stands. The script as a reusable check does not.
   - Fix: exit non-zero (or a distinct status) when `!closure_differs`.

No other bug or security issue found in the scheduler (launch/stop/orphan/final paths, `$!` capture, explicit `wait`s), `recompute_landed`/`recompute_ready`, the fallback pid wait, `.lnk_view_replace`, the driver's prep ordering or `recompute_deps.R`.

/Users/airvine/Projects/repo/link/planning/active/review-round3.md
