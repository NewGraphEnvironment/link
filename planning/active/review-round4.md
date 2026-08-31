# Code review — round 4 (#246 branch, narrow: commit `f146b2e` only)

Scope as briefed: only round 3's three fixes and their immediate blast radius.
Not a re-review of the whole diff.

- **A.** completeness gate no longer aborts; consolidate buckets narrowed
  (`data-raw/study_area_run.sh:700-795`)
- **B.** `~/.Renviron` umask (`data-raw/cypher_prep.sh:158-187`)
- **C.** `burn_cyphers` doctl capture (`data-raw/study_area_run.sh:212-225`)

Verdict: **B and C are sound. A is not** — the two guards it adds are
structurally unreachable, and the path that replaces them is the same
trap-burn data loss round 3 set out to remove.

---

## Findings

### 1. [BLOCKER — data loss] `data-raw/study_area_run.sh:767`

`bucket_r=$(printf '%s' "${CY_BUCKET_DONE[$WS]}" | tr ',' '\n' | grep -v '^$' | ...)`

When `CY_BUCKET_DONE[$WS]` is empty, `grep -v '^$'` selects no lines and exits
**1**. Under `set -o pipefail` the pipeline is non-zero, so the bare assignment
is non-zero, so `set -e` **aborts the script on this line** — one line *above*
the `if [ -z "$bucket_r" ]` branch written to handle exactly this case.

The abort happens with `CYPHERS_UP=1` (set at `:615`), so `trap burn_cyphers
EXIT` at `:230` destroys every droplet, including the ones that succeeded and
whose rows have not been consolidated yet. That is verbatim the accident the
commit message says it removed.

**Consequences, both structural:**

- `:768-771` — the "reported no WSGs — skipping it in consolidate" branch
  **can never execute**. The only way to have an empty `bucket_r` is the empty
  `CY_BUCKET_DONE`, which aborts first.
- `:778-782` — the `n_src -eq 0` branch **can never execute** either. Reaching
  `n_src == 0` with `N_CY > 0` requires the loop to `continue` for every host,
  which requires reaching the dead branch above. So the answer to "is `n_src`
  correct when every cypher is skipped?" is: the state is unreachable. Both new
  guards are decoration in the CLAUDE.md sense — a guard that cannot fire.

**The trigger is the motivating case, not a corner case.** An empty
`CY_BUCKET_DONE[$WS]` means "this host reported nothing", which is precisely
the 2026-05 failure the completeness accounting exists for, and the failure
`cypher_prep.sh`'s own header describes (fresh 0.31.0 → every WSG on the host
fails → host exits 0). It is also the degradation `bucket_done`'s comment at
`:718-720` deliberately routes a reworded `cat()` into.

Reproduced against a faithful extract of `:717-795` (2 cyphers, job1 reports
both its WSGs, job2 reports none):

```
=== per-host completeness ===
  ok dispatcher: 1/1
  ok cy[job1]: 2/2
  X  cy[job2]: only 0/2 WSGs accounted for (2 [WARN])
  WARN: consolidating only the WSGs each host reported
=== consolidate ===
>>> BURN CYPHERS (trap EXIT) — droplets destroyed
SCRIPT EXIT=1
```

job1's two successfully-modelled WSGs were never consolidated and the droplet
holding them is gone. Neither WARN branch printed.

**Fix** (verified as valid bash) — test the source string, which is the
condition the branch is actually about, instead of inferring it from an exit
status that `pipefail` turns into an abort:

```bash
bucket_r=""
if [ -n "${CY_BUCKET_DONE[$WS]}" ]; then
  bucket_r=$(printf '%s' "${CY_BUCKET_DONE[$WS]}" | tr ',' '\n' \
    | grep -v '^$' | sed "s/.*/'&'/" | paste -sd, -)
fi
if [ -z "$bucket_r" ]; then
  echo "  WARN: cy[$WS] reported no WSGs — skipping it in consolidate"
  continue
fi
```

A bare `|| bucket_r=""` also stops the abort but swallows a real pipeline
error into "reported nothing"; the guarded form keeps the two distinguishable.

**Then restore the bug and confirm the guard fires.** Both branches have
existed since `f146b2e` without ever having been executed; feed the block a
cypher log containing only `[WARN]` lines and assert the WARN prints.

---

### 2. [HIGH — data loss, same class, different line] `data-raw/study_area_run.sh:746`

`CY_BUCKET_DONE[$WS]=$(bucket_done "$LOG_DIR/${TS}_run_$WS.log" | paste -sd, -)`

`bucket_done` is `sed ... "$1" 2>/dev/null | sort -u`. `2>/dev/null` silences
sed's message but not its **exit status**, so an absent or unreadable log file
makes the pipeline non-zero under `pipefail`, the bare assignment non-zero, and
`set -e` aborts — again at `CYPHERS_UP=1`, again into the trap burn. Measured:

| log file | `bucket_done \| paste` | script |
|---|---|---|
| missing | non-zero | **aborts, exit 1** |
| exists, no matching lines | 0, empty output | survives |
| exists, matches | 0 | survives |

Lower likelihood than finding 1 — `:688`'s redirect creates the file for every
`WS` — but it is reachable on a failed redirect (full disk, unwritable
`LOG_DIR`) and the blast radius is identical. Note that the *empty-file* case,
which is the common one, is safe: sed and sort both exit 0.

**Fix:**

```bash
if ! CY_BUCKET_DONE[$WS]=$(bucket_done "$LOG_DIR/${TS}_run_$WS.log" | paste -sd, -); then
  echo "  WARN: could not read cy[$WS] run log — treating as reported nothing"
  CY_BUCKET_DONE[$WS]=""
fi
```

---

### 3. [HIGH] `data-raw/study_area_run.sh:739-751` — `complete_fail` is computed and then discarded, and the named backstop cannot see the gap

`complete_fail` is set at `:741`/`:745`, read once at `:748` to print a WARN,
and **never read again**. There is no non-zero exit anywhere after it. A run
that knowingly modelled 27 of 28 WSGs on a host prints `=== study_area_run
done ===` and exits **0**.

The commit accepts that trade explicitly — "the gap is reported by the coverage
check after the cyphers are burned" — but the coverage check at `:816-832`
cannot report it in the normal case. It asserts only that each expected WSG has
**≥1 row** in `${SCHEMA}.streams`:

```sql
LEFT JOIN (SELECT DISTINCT watershed_group_code w FROM ${SCHEMA}.streams) g
```

The persist accumulates across runs — nothing in `study_area_run.sh` calls
`lnk_persist_init`, and `schema_consolidate`'s DELETE is bucket-scoped, so a
WSG excluded from a narrowed bucket **keeps its rows from a previous run**. The
check goes green, the compare then runs against a mixture of this run's output
and an older run's, and the exit status says success. The backstop only works
on a first-ever run into an empty schema.

Same hole covers the dispatcher question in the brief: the dispatcher writes
straight to the persist with no consolidate step, so a half-failed dispatcher
leaves the persist holding its successful WSGs plus stale rows for the failed
ones. `report_completeness "dispatcher"` detects it, sets `complete_fail`, and
the value is dropped.

**Fix** — carry the flag to the exit status, after the burn and the coverage
check so it cannot leak spend or pre-empt the compare:

```bash
[ "$complete_fail" = "0" ] || {
  echo "FATAL: run incomplete — see the per-host completeness block above"
  exit 1
}
```

Strengthening the coverage check to assert *this run's* rows (join on
`<schema>.log`, or compare a timestamp) is the durable fix and a larger change;
the exit-status fix is what makes the current WARN honest in the meantime.

---

## Verified sound — no change needed

**The narrowing safety claim holds at the scope level.** Checked
`data-raw/schema_consolidate.R` as briefed:

- DELETE (`:272-276`) iterates `wgc_tables` with `wsg_list_sql`; COPY
  (`:312-316`) iterates the **same** `wgc_tables` with the **same**
  `wsg_list_sql`. No table where the two scopes differ.
- `wgc_tables = intersect(src_wgc, dest_wgc)` (`:192`), so `skipped_dest_only`
  tables are correctly excluded from the DELETE as well as the COPY — they are
  not emptied and left unrepopulated.
- `keep_source = FALSE` post-COPY source DELETE (`:423-456`) uses
  `copied_tables` ⊆ `wgc_tables` and the same `wsg_list_sql`, so a narrowed
  bucket removes from the source exactly what was transferred. Un-reported
  WSGs' rows stay on the source (and are then burned, which is correct — they
  were never copied).
- Residual, **pre-existing and not worsened by the narrowing**: a per-table
  COPY failure (`:338-347`, `:357-365`) does `next` after the DELETE already
  ran, so that one table loses the bucket's destination rows without
  replacement. Narrowing strictly reduces the set exposed to this.

**`CY_BUCKET_DONE` reachability and `set -u`.** `declare -A` at `:742` is at
top level in the main shell, not inside a function, so it is the same global
the consolidate loop reads at `:767`. Every key read there is written by the
`:743-747` loop over the same `CY_WS_ARR`, so there is no unset-key `set -u`
hazard. The whole block is inside `if [ "$N_CY" -gt 0 ]`, so `N_CY == 0` never
reaches it.

**`report_completeness` returning non-zero.** Called only as
`report_completeness ... || complete_fail=1`, which suspends errexit for the
whole function body, and each of its three `grep -c` calls additionally carries
`|| var=0`. `grep -c` prints `0` and exits 1 on no match; the `|| var=0` lands
the same value. No abort, correct counts.

**`bucket_done`'s regex.** `([A-Z]{4})` matches all 246 watershed group codes
in `fresh`'s `wsg_outlet.csv` — checked, zero non-4-alpha codes. Matches both
`wsg_run_one.R:56` (`SKIP —`) and `:88` (`done in %.1f min`). Anchoring on the
code rather than the prose is the right call.

**B — `cypher_prep.sh:158-187` umask.** Correct.
- `RENV_UMASK=$(umask)` prints octal (`0022`); `umask "$RENV_UMASK"` accepts it.
- The `exit 1` at `:178` between set and restore is harmless — umask is
  per-process and the process is ending.
- The window is `:163-187` only; `snapshot_bcfp.sh` and `lnk_persist_init` run
  after the restore at `:187`, so nothing downstream inherits `077`.
- `mv` preserves the tmp's `0600`, and the explicit `chmod 600` covers the
  append. The pre-`umask` `touch` at `:157` can create a `0644` file, but only
  an empty one, and the `mv` replaces it before anything is written.

**C — `burn_cyphers` doctl capture.** Correct.
- `local rc=$?` is still the first statement in the function; `local dl` is
  declared at `:216`, well after `rc` is read, so `$?` is not clobbered.
- `local dl` on its own line then `if dl=$(...)` is the right split —
  `local dl=$(...)` would return `local`'s status and re-introduce the bug.
- Under the EXIT trap with `set -e`, an `if` condition suspends errexit, so a
  failing `doctl` takes the else branch rather than aborting the trap.
- Empty `$dl` on the success path correctly reads as "no cypher droplets";
  a `doctl` failure is now a third, distinct outcome that sets `clean=0`.
- `return $rc` preserved.

---

## Summary

Finding 1 is the same shape as rounds 2 and 3: the fix contains a defect of the
class it was written to remove. Rounds 1→2→3 each landed a blocker inside the
previous round's fix, and round 3's two new guards are unreachable, so this is
the third consecutive instance and **not convergence**. Recommend a round 5
scoped to the round-4 fixes alone, with the restore-the-bug check run against
both new branches before it is called clean.
