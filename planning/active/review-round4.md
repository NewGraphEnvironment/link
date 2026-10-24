# Code-check round 4 — #375 (`<TS>_phases.tsv`), diff e496d853...HEAD

## Checklist read

- code-check-r.md (177,187 bytes, over 40,000): read the index; no full sections.
  The diff's only R is two testthat files that call bash via `system2()` and read a TSV.
  The rules they touch (`system2` status, `read.delim` quoting, testthat failure snapshots,
  `expect_match` on a collapsed string) are covered by their index lines. ~150 headings not read.
- code-check-shell.md (124,118 bytes): read in full the sections "Parallel writers sharing one
  output file", "`&` binds to the whole `&&` list", "`wait` with no argument", "`if ! cmd; then
  rc=$?`", "A second `trap … EXIT` replaces the first", "Put cleanup on the EXIT trap, not
  RETURN", "A failed `cd`", "`grep -c` prints the count AND exits 1", "A `pgrep -f` waiter".
  About 80 headings not read.
- code-check-spatial.md (155,517 bytes): index only. Nothing in the diff is spatial. 0 sections read.
- code-check.md (330,698 bytes): read the prose of all 14 H3s under `## Mechanisms`, without
  the `|` table rows or the evidence blocks. Index only for the stand-alone rules.

## Round-3 fix itself (`>> <leg log> 2>&1` on the three wrappers)

- **Open order.** The outer `>>` (O_APPEND|O_CREAT) is opened in the forked wrapper before its
  body runs. The inner `>` (O_TRUNC) opens next, and it truncates before anything has been
  written: the wrapper writes nothing before its inner command. Any later wrapper output
  lands at EOF. I ran a stub harness built from the driver's own block (awk-extracted from
  `RUN_N=` to `CY_PID[$WS]=$!`): both leg logs came out intact, every `[wsg_run_one] X done`
  line included, the mid-line one too.
- **Stdout no longer held.** With legs of 12 s and 6 s, `driver | cat` returned once the
  parent exited (6 s, which was the stub `host_baseline`), while both legs ran on and later
  wrote their rows.
- **What the wrappers can now add to a leg log:** the `WARN: could not write the … row`
  line (stderr, only when a row write fails), and bash's own job message when the foreground
  ssh, or the inner subshell, dies of a signal. Measured: `Terminated: 15  <unexpanded
  command text>`. Neither can match `host_log_reported`'s `\[wsg_run_one\] [A-Z]{4}
  (done|SKIP)`, nor `run_timeouts`' `\[wsg_run_one\] [A-Z]{4} statement_timeout=` and TIMEOUT
  patterns. The ssh command text has `wsg_run_one.R \$w` and `statement_timeout=${…}min`
  after `-c`, never `[wsg_run_one] XXXX `. So no count, SKIP or done reading can change.
- **Status passthrough.** Stub ssh exit 255 gives host_wait rc non-zero, so CY_RUN_RC[job1]
  is non-zero and the row says failed. Exit 0 gives CY_RUN_RC=0 and the row says ok.
  `phase_end` touches no `mrc`/`prc`, and every command in it is guarded, so under the
  inherited `set -e` it cannot change the re-raised status. A set -u expansion error there,
  which cannot happen with the current keys, would exit non-zero, which is the direction
  that holds the host.

## Remaining context properties of "wrap a block in a new compound"

| property | old shape | new shape | anything depend on it? |
|---|---|---|---|
| stdin | async, so /dev/null | outer async gets /dev/null; inner and ssh inherit it | measured: inner `cat` read nothing from a piped stdin. ssh/Rscript read /dev/null as before |
| SIGINT/SIGQUIT | ignored (async, no job control) | ignored in the outer, inherited by the inner subshell and the exec'd child | measured: `kill -INT -<pgid>` killed the driver; `sleep` survived in the old shape, the nested shape and the direct-foreground (ssh-like) shape |
| SIGTERM/SIGHUP | default / nohup-inherited | same | no |
| traps | EXIT not run in subshells | same | measured on bash 5.3: a wrapper that calls `exit` or is killed by TERM does not run `on_exit`; only the driver does. No burn from a wrapper |
| process group | driver's (no job control) | same | no |
| `$!` | the inner subshell / ssh | the wrapper | only `wait $LOCAL_PID` and `host_wait` (→ `wait`) use it. Nothing kills, `ps`es or `kill -0`s these PIDs |
| `$$` / `BASHPID` | — | — | not used in any wrapped block |
| umask | inherited | inherited | not used |
| cwd | driver's | driver's | local leg cds with `|| exit 1`; `LOG_DIR` is absolute (`$REPO_ROOT/data-raw/logs/…`); the ssh leg's cwd is irrelevant |
| env | fork copy | fork copy, plus non-exported `mrc`/`prc` visible to the inner | unused by inner bodies |
| errexit | on | off left of `||` | fixed for the local cd (round 1); prep accepted; the ssh leg has no inner body |
| nounset/pipefail | on | on (only errexit is suspended in `||` context) | no |
| other fds | 0–2 only (no `exec N>` in the driver) | same | no |
| argv / identity | the local inner already carried the driver's argv; ssh did not | the wrappers carry it | `pkill -f study_area_run` now also kills the ssh leg's wrapper (RUNBOOK documents it). No script pgreps `study_area_run` |

The phases tests (15 blocks, 58 expectations) pass from a temp copy. I did not run the
finish tests: they need the database the acceptance run is using.

## Clean

One non-blocking note, not a defect. The prep wrapper's comment at
`data-raw/study_area_run.sh:1353-1354` still says "quiet: its stdout is the driver's". Since
round 3 the wrapper's stdout is the prep log. `quiet` is still correct, because the row
would otherwise print into the log, so behaviour is unaffected.
