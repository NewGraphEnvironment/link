# Review round 4 — attacking the round-3 fixes (#250)

Method: empirical. Restored the round-1/round-2 defects into a copy of
`study_area_run.sh` and re-ran the shipped probe against it; ran the shipped
digest SQL against the live `fwapg`; exercised `lnk_fanout_judge()` across the
five-status branch table; measured `10#` overflow and `seq` behaviour on both
bash 5.3.9 and /bin/bash 3.2.57.

Round-3 fix #4 (`recompute_parity.sh` `2 x N_WSG`) verified **correct** — see
"Checked and clean" below. Three findings against fixes #1–#3.

---

## Findings

### 1. MEDIUM — `data-raw/pool_probe.sh:387-396` — the `010` leading-zero assertion cannot fail

The loop asserts that `08` and `010` are "read as decimal and ran", checking
`rc == 0 && 3 of 3 .rc files`. Restoring the pre-fix guard (numeric-only
`[ "$width" -lt 1 ]`, no `10#`) into a copy of `study_area_run.sh` and running
the shipped probe against it:

```
  ok   width 0 refused (rc=1)
  FAIL width 'abc' rc=124 (124 = hung, 0 = accepted)
  ...
  FAIL width '08' rc=124, 0/3 jobs (124 = hung)
  ok   width '010' read as decimal and ran        <-- passes ON THE DEFECT
PASS=28 FAIL=7
```

With the octal bug present, `[ 010 -lt 1 ]` is false (`test` reads base 10), so
the pool proceeds and `$((010 - 1))` is `7` → an **8-slot pool** instead of the
10 the operator asked for. Three jobs still run, all still exit 0, three `.rc`
files still land. The assertion is satisfied by the defect.

So of the two halves of the leading-zero class, the probe only guards the half
that fails **loudly** (`08` → `value too great for base` → hang → 124). The half
that fails **silently** — a pool narrower than requested and than the banner
reports, which is the dangerous direction and the one the round-2 comment calls
out by name ("`010` silently became an 8-slot pool") — is unguarded.

The job count is a proxy for the width and cannot distinguish 8 slots from 10.
Assert the width that was actually achieved: with `STUB_SLEEP=1` and **more than
8** jobs, decimal-10 completes in one wave (~1 s) and octal-8 takes two (~2 s) —
the same timing arm already used for the `width 4` vs `width 12` bound.

### 2. LOW-MEDIUM — `R/lnk_fanout_judge.R:166-189` — `allow_empty = TRUE` makes the verdict unfailable when jobs did report

`none_expected` is the first branch, and `ok <- if (st == "none_expected") allow_empty`.
So with `expected = character(0)` and `allow_empty = TRUE`, **every** other
problem is recorded and then overridden:

```
expected=character(0), allow_empty=TRUE, rc = data.frame(job="A", rc="1")

status=none_expected ok=TRUE n_exp=0 n_ok=0 unexpected=[A]
problems: no jobs were expected (allowed)
        | 1 job(s) exited non-zero: A(rc=1)
        | 1 job(s) reported but were not asked for: A
message:  [fanout] fanout - OK (none_expected): 0/0 job(s) succeeded
```

A job that ran and failed is reported as OK. The dedup added in round 3 is
correctly placed (verified: `unique()` at line 114 precedes `missing`,
`unexpected`, and `n_expected`; duplicate `expected` correctly yields `partial`
/ `none_ran` / `all_failed` in every combination tested) — this is the other
half of the question, and it is the branch that got missed.

The existing guard for this, `test-lnk_fanout_judge.R:36` "allow_empty does not
excuse a non-empty run that failed", passes a **non-empty** `expected`, which
routes past the `none_expected` branch entirely — so its premise makes the
failing case structurally unreachable. Same shape as the round-3 findings.

Latent today: `data-raw/fanout_judge.R` never passes `allow_empty`, and no other
caller does, so the reachable path is the exported API only. Fix is one line —
`ok <- st == "ok" || (st == "none_expected" && allow_empty && n_ran == 0L)` — plus
a test whose `expected` is empty.

### 3. LOW — `data-raw/study_area_run.sh:697` — `10#` wraps on overflow, so an all-digit width can still reach `seq` and hang

The round-3 comment says "one normalisation ends the class". It does not quite:
`$(( ))` wraps silently at `intmax_t`, so an all-digit string long enough to
overflow passes the `case` shape check, is normalised to a large **positive**,
passes `[ "$width" -lt 1 ]`, and reaches `seq`. Measured identically on 5.3.9 and
3.2.57:

```
99999999999999999999            -> 10# = 7766279631452241919  -> ACCEPTED
seq 0 7766279631452241918       -> STILL RUNNING after 5s (hang)
```

That is the exact failure the guard's own header says it prevents ("Width must be
a positive integer or this HANGS rather than failing").

The `--recompute-jobs=` parser is safe by accident — its `-le 16` bound rejects
the wrapped value. But the pool has **no upper bound**, and its comment claims
the guard "belongs HERE where all three callers meet it": `recompute_parity.sh`
(`WIDTH="${3:-4}"`) and `recompute_sweep.sh` (`WIDTHS=("$@")`) pass an operator
width straight to `run_recompute_pool` with nothing above it. Adding
`[ "$width" -le 64 ] || return 1` after the `-lt 1` check closes both the
overflow and the "1000 slots" case, and puts the pool's ceiling where the comment
says it lives.

Reachability is low (requires a ~20-digit typo), which is why this is LOW and not
higher.

---

## Checked and clean

- **Round-3 fix #4, `recompute_parity.sh:589-599` (`2 x N_WSG`).** Multiplier
  verified against live `fwapg`: `recompute_checksum.sql` emits one header plus
  one row per (table, WSG) over exactly two tables — 9 lines for 4 WSGs, 8 data
  rows = 2 x 4. `\gset` and the `DO` guard emit no rows, `\gexec` emits one
  result set, so the `wc -l - 1` header arithmetic is right. A WSG absent from
  either table (the `GROUP BY` over zero rows case the comment describes) drops
  out and is caught. The failure branch lists the (table, WSG) pairs it *does*
  have, which is enough to name the gap.
- **`with_deadline` distinguishes hang from non-zero exit.** Proven by the
  restore above: bad widths returned `rc=1` (refused) against the fixed pool and
  `rc=124` (deadline) against the broken one, and the probe reported FAIL rather
  than sitting there. `[ "$rc" -ge 128 ]` mis-reporting a legitimate `>=128` exit
  as 124 is a false *alarm*, the safe direction, and unreachable here —
  `run_recompute_pool` only ever returns 0 or 1. The orphaned `sleep` left by
  killing the killer subshell exits on its own within the deadline.
- **`10#` is safe for every string the shape check admits** other than the
  overflow case in finding 3 — `0`, `00`, `000000000` all normalise to 0 and are
  refused; `0x10`, `08e1`, `1e1`, `2x`, `" 2"`, `-1`, `""` are all rejected by the
  shape check before any arithmetic. Confirmed on both bash versions.
- **Normalisation order.** `case` → `10#` → `-lt 1` is correct: nothing consumes
  `width` between the assignment and the bound, and `seq`/`$((width - 1))` and
  `SLOT_PID` all read the normalised value.
- **Dedup placement in `lnk_fanout_judge()`** — before `missing`, `unexpected`,
  `n_expected`; interacts correctly with all five statuses.
- **`set -e` on `SEC_A=$(run_pass ...)`** — a `run_pass` FATAL does abort the
  parent script (verified on 5.3.9 and 3.2.57); the subshell `exit 1` is not
  swallowed, and the FATAL text reaches the operator because it goes to stderr,
  outside the command substitution.
- **`pool_probe.sh` on the shipped tree:** PASS=35 FAIL=0 on both 5.3.9 and
  3.2.57.
