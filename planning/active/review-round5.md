# Code review — round 5 (#246 branch, narrow: commit `13051e2` only)

Scope as briefed: round 4's five changes and their immediate blast radius in
`data-raw/study_area_run.sh`. Not a re-review of the rest of the diff.

Every claim below was **executed**, not read. Test harnesses were faithful
extracts of `:717-912` run under `set -euo pipefail` on the same bash the
script uses.

## Verdict: Clean

Round 4 is the first round that does not contain a defect of the class it was
written to remove. All five changes are sound and all five are load-bearing —
each was verified by restoring the bug and confirming the failure returns.

---

## Restore-the-bug: every fix is load-bearing, not decoration

| fix | reverted form | round 4 form |
|---|---|---|
| `csv_lines` on an empty bucket | `grep -v '^$'` → **exit 1, script aborts, guard unreachable** | exit 0, `WARN: cy[job2] reported no WSGs — skipping` **prints** |
| `bucket_done` on a missing log | `sed … 2>/dev/null \| sort -u` → **exit 1, script aborts** | exit 0, bucket `[]` |
| `printf '%s\n'` | `printf '%s'` on 2 items → `wc -l` = **1** | `wc -l` = **2** |

The first two both aborted with `CYPHERS_UP=1` in round 3, i.e. into the
trap-burn. Both now reach their guards.

## `csv_lines` / `csv_count` — correct across 16 inputs

```
empty string      count=0    only blanks ",,,"   count=0    only spaces "   " count=0
single "ADMS"     count=1    trailing comma      count=2    leading comma     count=1
two               count=2    embedded blank      count=2
value with space  count=2    glob char "*"       count=2 (literal `*`, no expansion)
single quote      count=2    double quote        count=2
"-n" / "-e"       count=2 (operands, not printf options — format is arg 1)
backslash 'A\nB'  count=2 (literal — %s does not interpret escapes)
csv_count with NO argument            -> 0   (`${1:-}` covers set -u)
csv_count "${assoc[missing]:-}"       -> 0
```

No word-splitting or globbing hazard: `printf '%s\n' "${1:-}"` is fully
quoted, and the format string is a literal so a value beginning `-` cannot be
read as an option. `sed '/^[[:space:]]*$/d'` deletes only all-blank lines — it
does not trim interior whitespace, so `"ADMS , BULK"` yields `"ADMS "` and
`" BULK"`. Not reachable: `CY_BUCKET_DONE` comes from `bucket_done`'s
`([A-Z]{4})` capture, and `CY_BUCKET` is `tr -d '[:space:]'`-ed at `:581`/`:587`.

## No remaining pipeline in the completeness/consolidate path aborts

Measured, all under `set -euo pipefail`, all `rc=0`:

| pipeline | full | empty file | no matching lines | no trailing newline | missing file | unreadable (mode 000) |
|---|---|---|---|---|---|---|
| `bucket_done \| paste -sd, -` (`:748`, `:766`) | 0 | 0 | 0 | 0 | **0** | **0** |
| `csv_lines \| sed \| paste` (`:787`) | 0 | 0 | 0 | — | — | — |
| `grep -c '^\[WARN\] '` (`:749`) | 0 | 0 | 0 | — | 0 | 0 |

- `paste -sd, -` on empty input emits a bare `\n` and exits 0; `$( )` strips it
  to `""`, which `csv_count` reports as 0. `sort -u` on empty input emits
  nothing and exits 0.
- `:766` is the one call **not** wrapped in `||`, so it is the one that had to
  be made exit-0 in its own right. It is — via `[ -r "$1" ]`.
- `grep -c` exits 1 on zero matches but is caught by `|| warn_n=0`, and prints
  `0` first so the value is right either way.

## `complete_fail` / `RUN_INCOMPLETE`

`complete_fail` is a top-level global (`:759`), never `local`, so it is in
scope at `:861`. `report_completeness` is called only as `f || complete_fail=1`,
which suspends errexit for the whole function body — confirmed by the `nologs`
scenario, where all three `csv_count` calls run against absent files and the
script survives.

Five scenarios, end to end:

| scenario | per-host | `complete_fail` | consolidate | post-burn `CYPHERS_UP` | trap | exit |
|---|---|---|---|---|---|---|
| all hosts complete | 2/2 ×3 | 0 | both cyphers | 0 | no-op | **0** |
| one cypher reported nothing | 0/2 on job2 | 1 | job1 only, job2 skipped **loudly** | 0 | no-op | **1** |
| every host reported nothing | 0/2 ×3 | 1 | `✗ no cypher reported any WSG` | 0 | no-op | **1** |
| no log files at all | 0/2 ×3 | 1 | same | 0 | no-op | **1** |
| dispatcher failed, cyphers fine | 0/2 disp | 1 | both cyphers | 0 | no-op | **1** |

`RUN_INCOMPLETE` is reachable: `:861` is unconditional in the main flow, and
every `exit` between it and `:905` (`:891` compare) is `exit 1`. There is no
`exit 0` and no early return in that range, so `${RUN_INCOMPLETE:-0}` cannot
mask anything — the `:-0` is redundant belt-and-braces, not a hole. The
coverage check at `:848`/`:851` can `exit 1` first; that is correct and still
non-zero.

`N_CY = 0` case: `:861` and `:905` are outside the `if [ "$N_CY" -gt 0 ]`
block, so a dispatcher-only run with a partial bucket still exits 1.

## Trap interaction with the new `exit 1`

At `:905`, `CYPHERS_UP` is 0 — set by `burn_cyphers`'s own `:227` during the
explicit `burn_cyphers || true` at `:818`. Verified in all five scenarios: the
trap re-entry prints only `trap: CYPHERS_UP=0, no-op (rc=1)` and **does not
re-burn**. `exit 1` survives the trap's `return $rc` — `SCRIPT EXIT=1`.

`--keep-cyphers` leaves `CYPHERS_UP=1` (the early return at `:196` skips
`:227`), so the trap prints `=== trap EXIT: --keep-cyphers; NOT burning ===` a
second time. Verified it does **not** burn, and the exit status is still 1.
Cosmetic duplicate line, pre-existing shape, no behavioural consequence.

---

## Notes — not findings

**Two `grep -v '^$'` instances remain un-swept** (`:597` DUP, `:823`
`ALL_WSGS`). Round 4's stated aim was to put the safe form in one helper
rather than remember it per call site, and these two were not converted.
Both are **unreachable today**, proven rather than assumed:

- Each aborts only if *every* bucket string is blank.
- `study_area_wsgs.R:44` `stop()`s when the resolve returns zero WSGs, so the
  bare assignments at `:580`/`:586` abort first under `set -e` — `DISP_BUCKET`
  can never be empty.
- `:597` and `:823` read the *same* input set, so `:823` additionally cannot
  fire where `:597` did not, and `:597` runs pre-spin (no spend, no data).

Confirmed the shape does abort if the premise is removed (`DISP_BUCKET=""` →
exit 1 before the next line). Worth converting for uniformity, but it is not a
live failure and changing it now would widen a round scoped to converge.

**`exp_n` counts raw CSV items, `got_n` counts `sort -u` output.** A duplicate
WSG inside a single host's bucket would read as incomplete. Not reachable
(`frs_wsg_drainage` returns a closure set) and not a round-4 change — round 3's
`grep -c '[^[:space:]]'` had the identical asymmetry.

---

## Summary

Rounds 1→4 each landed a blocker inside the previous round's fix. Round 4 does
not. The centralised helper is correct on every input tried including the
adversarial ones, the two abort paths that caused the round-3 trap-burn are
closed and their guards now demonstrably execute, and `RUN_INCOMPLETE` reaches
the end of the script and produces a non-zero exit in every incomplete
scenario without re-triggering the burn. This is convergence.
