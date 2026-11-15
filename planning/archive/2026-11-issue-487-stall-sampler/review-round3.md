# Code-check round 3: link#487 stall sampler (branch head 5bf1b5e7)

## Checklist read

- **code-check.md:** I read the prose of all 14 H3s under `## Mechanisms` and skipped the table rows. I read none of the `## Rules that stand alone` or `## Security` / `## Spreadsheets and PDFs` sections (none name a tool or shape this diff uses), so 0 of about 20.
- **code-check-shell.md:** I read 3 sections in full:
  - "Parallel writers sharing one output file interleave mid-record"
  - "macOS `/usr/bin/awk` aborts when a regex meets a byte slice…"
  - "macOS `sed` dies on an invalid byte…"

  The other headings I read only in the index. That covered `if ! cmd`, `wait`, `pgrep -f`, the `trap` EXIT handler, `mktemp`, `grep -c`, `a && b || c`, a failed `cd` and Tailscale ssh exit 0. None of those shapes is new in this diff. 3 sections read in full, about 70 not.
- **code-check-r.md:** I read 5 sections in full:
  - "`system2(stdout = TRUE)` warns on a non-zero exit…"
  - "`tempfile()` lives in the session tempdir…"
  - "A `data-raw/` script must load the source tree…"
  - "`tryCatch()` nests its handlers…"
  - "`on.exit()` at a script's top level never fires"

  The other headings I read only in the index. 5 sections read in full, about 150 not.
- **code-check-spatial.md:** I read the index only. No spatial code is in the diff, so 0 sections read.

## Findings

- **[severity: fragile]** `data-raw/wsg_run_one.R:106`: a run outside the driver gets a 10-minute threshold whatever bound it runs under, so its sampler can never record.
  - **What happens:** when `LNK_STALL_AFTER_MIN` is unset, `wsg_run_one.R` uses 10 minutes. It ignores the bound it has just read at lines 96 to 98 (`bound_ms`). Round 1 added a rule that the default gives way to a short bound (bound minus 1 minute, or 0.5 under a 1-minute bound), but that rule lives only in `study_area_run.sh` (lines 407 to 414).
  - **Who misses it:** `wsg_run_one.R` has two other callers, and neither sets the variable.
    - **The pre-run gate** (`data-raw/pretest_run.sh:252-256`) bounds each pick at `statement_min`. `data-raw/logs/pretest_372/gate_final/picks.tsv` gives TAKL a 10-minute bound and SAJR 5 minutes; those are the two picks killed at their bounds on 2026-10-28. Under the default 10 the sampler never records either of them. The wall-clock kill (9.45 and 5 minutes) also comes before 10 minutes.
    - **The printed re-model commands** (`data-raw/study_area_finish.sh:877-880` and `:1008-1011`) carry `PGOPTIONS=…${RUN_BOUND}` but not the threshold. Under a run bound of 10 minutes or less, re-modelling the stalled group records nothing.
  - **What the user sees:** in both cases `wsg_run_one.R` starts a sampler that cannot record and prints no `stall sampler off` line. The RUNBOOK line "Unset, it gives way to a shorter bound" holds only for the driver.
  - **Fix:** the rule belongs to the shared entry point. When `LNK_STALL_AFTER_MIN` is unset, `wsg_run_one.R` should derive the threshold from `bound_ms`.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness"

- **[severity: fragile]** `data-raw/wsg_run_one.R:131-137` together with `data-raw/study_area_finish.sh:1008-1011` (and `:877-880`): a hand re-model names a stall file that will not hold its own samples.
  - **The assumption:** a set `LNK_RUN_UID` is taken to mean the group's output lands in a `<ts>_run_*.log` that `run_stalls` will split. So the TIMEOUT path prints `stall samples: <ts>_stall_<WSG>.tsv`.
  - **Why it fails:** the printed re-model command for a stalled or missing group sets `LNK_RUN_UID=$RUN_UID` and redirects nothing. That re-model's `[wsg_stall]` lines go to the operator's terminal, and `run_stalls` (`find … "${ts}_run_*.log"`) never reads them.
  - **Result:** the named file holds only the original run's rows, or does not exist if the original never passed N. This is the path a stalled group takes, and its samples are the ones that matter. The marker proves a row was written, not that the row will reach the named file.
  - **Fix options:** either the printed command appends to the run's log (`>> $LOG_DIR/${ts}_run_local.log 2>&1`), or the name is gated on a driver-only variable instead of `LNK_RUN_UID`.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** `R/lnk_stall.R:157` (`every_s <- min(every_s, max(after_s, 1))`) together with `data-raw/study_area_run.sh:410-414`: the default threshold under a short bound gives a sampling window no longer than the check cadence, so a cancelled stall can leave no rows.
  - **The window:** the driver's fallback threshold (bound minus 1 minute, or 0.5 under a 1-minute bound) gives a window between threshold and cancel of 60 seconds (30 seconds under a 1-minute bound). The sampler's cadence is 60 seconds (30 seconds).
  - **Why one check is not guaranteed:** checks are scheduled every C seconds, but each runs at the first 2-second poll after its scheduled time. A scheduled check in the last couple of seconds before the cancel can run after the statement is gone. The check before it can also land at or just below the threshold. I estimate this leaves no rows about 1% of the time at C = 60 and about 2 to 3% at C = 30, from that jitter.
  - **Who it reaches:** every `--statement-timeout` from 1 to 10 without an explicit `--stall-sample-after`.
  - **The docstring:** it claims "a stall between `after_s` and a bound twice as long is still caught". That fails for the same reason: with C equal to `after_s`, the window is exactly one cadence long.
  - **The cause:** the driver chooses the threshold knowing the bound; the sampler chooses the cadence without knowing it.
  - **Fix:** make the window longer than C plus `poll_s`. Either the fallback becomes bound/2, or the sampler's cadence becomes (bound − after)/2. The sampler can read the watched backend's `statement_timeout` from `pg_settings` only for its own session, so the bound would have to be passed in.
  - **Rule:** none

- **[severity: fragile]** `data-raw/study_area_run.sh:638`: the banner reports a sampling cadence the driver never checked and that the remote legs do not use.
  - **What it prints:** `every ${LNK_STALL_EVERY_S:-60} s (…both legs…)`, taken from the driver's environment.
  - **What actually happens:**
    - The driver never validates the value; only `wsg_run_one.R` does (1 to 3600 seconds).
    - `LNK_STALL_EVERY_S` is not exported over ssh (it is not in `REMOTE_LEG_VARS` and not in `remote_leg_cmd`), so remote legs run at 60 seconds.
  - **Result:** with `LNK_STALL_EVERY_S=15` (the RUNBOOK's exercise setting) the banner shows 15 seconds for a run whose cloud and worker legs sample every 60. With an out-of-range value (0, or `abc`), the banner announces sampling while every local group prints `stall sampler off` into a host log nobody reads.
  - **Rule:** code-check.md "One fact derived twice"

## Mechanism and enumeration

**The shared assumption:** each stage reaches its conclusion from what it can see locally, and that conclusion is taken to stand for a property decided somewhere else. Both candidates in the brief are the same mechanism seen from two sides:

1. A value that stands in for the property: a default for an explicit choice, a bound for "rows were written", a uid for "output reaches a split log", the banner's environment for what the legs run.
2. The same fact (threshold, cadence, `<ts>`, tag and columns, locale) is derived separately in several pieces, and only some of them know the input that decides it. The bound is known to the driver and to `wsg_run_one.R`, but not to the sampler. The fact that output reaches a `_run_` log is known only to the driver.

Every place in the diff it reaches:

| Place | Fact or stand-in | Holds? |
|---|---|---|
| driver `:407-414` | explicit or default threshold against the bound (R1) | holds after R1 |
| `wsg_run_one.R:106` | default 10 with no bound known | **does not hold** for the gate and the printed re-models (finding 1) |
| `remote_leg_cmd` `${STALL_AFTER_MIN:-10}` | second copy of the default | holds: the driver always sets the value before the leg; the default is reached only by tests |
| `.lnk_stall_watch(after_s = 600, every_s = 60)` | third and fourth copies of the defaults | holds: only tests reach them |
| `wsg_run_one.R:150` marker | "a row was written" (R2) | holds: the sampler creates it after `cat` and `flush` |
| `wsg_run_one.R:133` `nzchar(LNK_RUN_UID)` | "output reaches a `<ts>_run_*.log`" | **does not hold** for the printed re-model (finding 2) |
| `wsg_run_one.R:120-125` `started` (`system2(wait = FALSE)` returned) | "sampler running" | holds: it does not name the file alone; the marker gates it, so a sampler that dies at `library(link)` (an older install on a cloud host) names nothing |
| summary `stall samples:` from `STALL_WSGS` | "file written" | holds: set only after a successful `mv`; a header implies rows, because the sampler emits its header only with its first row |
| INCOMPLETE `samples:` (`-f` test) | "file written" | holds: tests the file itself |
| cadence `min(every, max(after, 1))` against the driver's fallback threshold | coverage of the window between threshold and cancel | **does not hold** at window ≤ cadence + poll (finding 3) |
| banner `${LNK_STALL_EVERY_S:-60}` | cadence the run uses | **does not hold** for remote legs or invalid values (finding 4) |
| validation ranges | driver 1–1440 whole minutes (or 0.5); `wsg_run_one.R` (0, 1440] and every 1–3600; sampler: numeric only; `.lnk_stall_snapshot`: finite and ≥ 0 | holds: every value the driver can send passes `wsg_run_one.R` (0.5 > 0; bound − 1 ≤ 1439) |
| `<ts>`: R `sub("-.*$", "", uid)` against shell `${RUN_UID%-*}` (three times in the finish lib) | the same timestamp | holds: `--run-uid` is validated `^[0-9]{8}_[0-9]{6}-[0-9a-f]{8}$` and a minted uid is `${TS}-hex8`, one hyphen; they differ only for a hand uid with two hyphens, whose output `run_stalls` never reads anyway |
| tag and column contract | `.lnk_stall_lines` writes `[wsg_stall] ` + WSG + tab; `run_stalls` requires `[A-Z]{4}` then a tab; the header literal `sampled_utc` equals `.lnk_stall_cols[1]` | holds: WSG is `toupper(args[1])` and driver codes are 4 letters; the uid-less line `the [wsg_stall] XXXX lines…` is rejected (a space, not a tab); the duplicated header literal holds today |
| sanitising `[wsg_` and `__LNK_` in fields | log readers: `host_log_reported` `\[wsg_run_one\] [A-Z]{4} done/SKIP`, `run_timeouts` `TIMEOUT after` and `statement_timeout=`, `remote_leg_status` `__LNK_LEG_END__` | holds for `[wsg_stall]` rows. The `[wsg_stall_error]` line is not sanitised, but its text is an R or DB condition message carrying no host-log marker, and `run_stalls`'s tag (`] ` + 4 letters + tab) does not match it |
| locale in `run_stalls` | `awk`, `cut`, `sort` under `LC_ALL=C`; `find \| sort` sorts ASCII names; `cat`, `mv` and `mktemp` are locale-free | holds. The INCOMPLETE loop replaced `sed 's/^/…/'` with `read` and `echo`, so no regex scans the line. The awk `substr(…) !~` sits under `LC_ALL=C`, so no wide-character conversion |
| `host_log_reported` `grep -oE` (no `LC_ALL=C`, pre-existing) | now also reads sampler text | holds: query text comes from Postgres (valid UTF-8; `left()` and R `substr()` cut by character; `pg_stat_activity` clips with `pg_mbcliplen`) |
| interleaving of parent and sampler on one fd (shell rule "Parallel writers…") | records torn mid-line | holds in practice: the sampler writes only while the parent is blocked in the stalled statement, so the parent is silent. A torn line needs the statement to end within the write; `run_stalls` matches the tag mid-line |
| sampler holding the leg's stdout (ssh channel, gate pick log) | the leg ends when the group ends | holds: parent checked every 2 s, DB calls bounded; the gate's `pg_terminate_backend` by `application_name` also reaches the sampler (inherited `PGAPPNAME`) |
| ending the watch on the first error (`.lnk_stall_watch`) | a judgement, not a stand-in | noted, not flagged: one transient failure (connection drop, a 10 s statement bound under extreme load) ends sampling for the rest of that group, which is when a stall is likeliest; `pg_stat_activity` reads are cheap, so this was not judged likely |

Clean otherwise:
- **The SQL holds:** the `make_interval` parameter is typed, the `to_char` escapes come out right, and `'\s+'` survives `standard_conforming_strings`.
- **R `cat(…, sep = "\n")` writes a trailing newline when `sep` holds one.** I measured it: `cat(c("a","b"), sep = "\n"); cat(c("c","d"), sep = "\n")` gives `a\nb\nc\nd\n`, so consecutive batches never join on one line.
- **The `system2` arguments are safe:** `shQuote` is applied to both paths, and the numbers are formatted below `1e5`.

/Users/airvine/Projects/repo/link/planning/active/review-round3.md
