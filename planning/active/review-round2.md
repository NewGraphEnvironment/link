# Code-check round 2 — #376 persistent workers (branch diff 7e855364...HEAD)

## Checklist read

- **code-check.md** (37 H3s): read the full prose of all 14 under `## Mechanisms` (table rows skipped): a guard that fails toward pass; a fixture that cannot reach the failure mode; a proxy is not the property; verification that reads its own output; a guard's scope, escape hatches, and remedies; a fix lands in one of two callers that share a harness; restore the bug and prove the guard fires; a shared working tree; a wrapper's exit is not the work; zero-length, empty, and unset; the probe is broken before the world is; written data outlives the fix; serialization loses meaning silently; one fact derived twice. Not read in full: the 23 standalone/security/spreadsheet headings (index lines only).
- **code-check-shell.md** (67 H3s): read in full: empty arrays under `set -u`; `wait` with no argument; `if ! cmd; then rc=$?`; psql `:'var'` / `\quit N`; a second `trap … EXIT`; a `local` statement reading its own assignment; `grep -c`; a variable in a sed replacement; `exit` inside a loop condition; a failed `cd`; macOS bash 3.2 heredoc in `$( )`; Over Tailscale SSH to a Mac, ssh exits 0; put cleanup on EXIT not RETURN; Perl `$1` followed by a digit. 53 not read in full (index only).
- **code-check-r.md** (111 H3s): read in full: `on.exit()` at top level; a `data-raw/` script must load the source tree; `tempfile()` lives in the session tempdir; an `information_schema` lookup by literal name; `system2(stdout = TRUE)` warns on non-zero exit; `Rscript -e` supplies `--args`. 105 not read in full (index only).
- **code-check-spatial.md** (93 H3s): none applies to this diff (no spatial code); 93 not read.

## Verification done

- All seven changed test files pass in a scratch copy of the repo (`NOT_CRAN=true`, `testthat::test_file`, counting `failed` and `error`): remote 18, worker_prep 3, schema_consolidate 20, hosts 49, finish 34, phases 16, legs 15; 0 failed, 0 error, 0 skipped.
- Measured on the local fwapg (temp table only): psql prints no `COPY n` tag for `COPY … TO STDOUT` to stdout, and prints `COPY 2` for `-c "COPY … FROM STDIN" < file`. So `sent` (`wc -l` of the stage-1 file) and `took` (`consolidate_copy_count`) count the same rows, and the new per-table check does not fire on healthy input.
- `remote_redact_init` / `remote_redact_targets` under `set -euo pipefail` with bash 5: WK_TARGETS unset, empty, a target ending in `@`, `user@host`, an alias, and two targets sharing a prefix. No abort; longest-first ordering holds (`me@studio.local2` before `studio.local`); whole-name matching leaves `studio.local2` alone when redacting `studio.local`.
- Round-1 fixes: `consolidate_link_tables()` narrowing leaves `consolidate_missing_persist` / `dest_missing_tables`, the `copy_empty` bucket count, the log-table history path and step 5 consistent (all now derive from the narrowed `wgc_tables` / `skipped_source_only`). The persist tables `lnk_persist_init()` creates are exactly the six core names plus `streams_habitat_<sp>` (checked in `R/lnk_persist_init.R` and against the base tables carrying `watershed_group_code` in `fresh`, `fresh_default`, `fresh_parity361/362` locally). The bash `_HOSTS_PERSIST_CORE` and R `consolidate_persist_core` are the same six, and the habitat regexes are the same. No other driver path deletes or copies a non-link table. `.hosts_query` callers all pass `HOST_SSH` or `local`; an unset `HOST_SSH` now fails the query (`[ -n "$where" ]`) rather than probing `cypher@`.

## Findings

- **[fragile/security] data-raw/study_area_run.sh:376, data-raw/study_area_run.sh:405, data-raw/study_area_remote.sh:96.** The new `--workers=` target check and the `LNK_TEST_STALL_WSG` check validate with `printf '%s' "$v" | grep -qxE '<pattern>'`. `grep -x` matches per line and `-q` succeeds if any line matches, so a value with an embedded newline passes as long as one line fits. Both of these printed `PASSES` here: `$'good\nx\x27; touch /tmp/pwn; \x27'` against the worker pattern, and `$'ABCD\n\x27$(id)\x27'` against `[A-Z]{4}`. The rest of the value then reaches exactly the places the charset restriction exists to protect:
  - the R source `host_consolidate` builds (`list(host = '${HOST_SSH[$ws]}', …)`, study_area_legs.sh:94);
  - the dispatcher's `sh -c` in `consolidate_remote()` (`ssh '%s' …`);
  - the remote command string (`export LNK_TEST_STALL_WSG='…'` in `remote_leg_cmd`).

  The comment at run.sh:366-370 states the target "is pasted into ssh command lines and into R source, so the charset is restricted", which does not hold. The value is operator-supplied, so this is not a privilege boundary. It is still the one guard round 1 added for quoting, and it can be passed. Use a `case` glob, as the `LINK_BRANCH` check at run.sh:440 already does. For example: `case "$t" in ""|-*|*[!A-Za-z0-9._@-]*|local) FATAL ;; esac`, and `case "$s" in [A-Z][A-Z][A-Z][A-Z]) ;; *) FATAL ;; esac`.

- **[fragile] data-raw/study_area_remote.sh:108-117 (`worker_prep_env`).** The comment says every value is "one the driver already refused quotes in (branch, config, schema, wet load)". Branch (run.sh:440) and wet load (run.sh:506-510) are checked. `CONFIG` and `SCHEMA` are not: neither `--config=` nor `--schema=` is charset-checked anywhere in run.sh. Both are pasted inside single quotes into the worker prep command (`WORKER_PREP_CONFIG='${CONFIG:-}' WORKER_PREP_SCHEMA='${SCHEMA:-}'`), as they already were into the cypher prep and leg strings. A `'` in either closes the quote on the remote shell. The same holds for `'$CONFIG'` in `remote_leg_cmd`, `collect_stamps` and the vintage call. Either validate both where they are parsed (the `--run-label` pattern), or drop the claim from the comment.

- **[fragile] data-raw/study_area_run.sh:440-442.** The new `LINK_BRANCH` charset refusal runs at top level for every mode, including dispatcher-only runs and `--recompute-only`, which paste the branch into no remote string. A branch name git allows but this set excludes (`+`, `@`, `#`, …) now stops a purely local run that worked before #376. Scope the refusal to `N_HOSTS -gt 0`, where the branch reaches cypher_prep or worker_prep. (An empty branch, a detached HEAD, still passes this case, as before.)

No other real issues found. I checked the following and found each sound:
- the remote-status rule across `remote_run`, `remote_leg_status` and `consolidate_remote` (ssh non-zero wins, a missing trailer means 255, the leg needs its end marker);
- that no driver decision still reads an ssh exit status, apart from reachability and the cypher prep, which is gated on `=== READY`;
- the kind split in `burn_cyphers`, `hosts_kept_report` and `host_finish_leg`;
- `host_drop_partials`'s preconditions and its sentinel judgement;
- the ordering of the pre-spend worker checks: reach, identity and prior rows, all before the backup and the cypher spin;
- `set -e` around `|| rc=$?`, the `&&` lists inside loops, and `local`;
- worker_prep.sh under bash 3.2 (no arrays, `set -euo pipefail`, `Rscript -e` with trailing args, the install-fresh refusal).
