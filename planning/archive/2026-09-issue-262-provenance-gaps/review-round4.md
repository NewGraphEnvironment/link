# Review — round 4 (link#262, branch `262-provenance-gaps-before-217-wsg-run`)

Fourth pass, scoped at the **round-3 fixes only** (`round3fix.diff`). Round 3 read first;
both target files read in full at their current state. Nothing from rounds 1–3 repeated.

**Direct answer to the headline question: the *shadowing* class is eliminated. The class
it was a symptom of — a `FAIL` that exits 0 — is not; it was fixed on one arm and left on
the sibling arm two lines above it.** Enumeration behind both halves below.

## The shadowing class: eliminated

Enumerated the complete candidate set — every way `concat_ws` can drop or hide a
condition — rather than asserting it:

1. **A false condition.** `CASE WHEN <false> ... END` with no `ELSE` → NULL; `concat_ws`
   skips NULLs. Correct and intended.
2. **A NULL condition.** `count(*) FILTER (...) > 0` cannot be NULL (`count` never
   returns NULL), so all four count-only arms are two-valued. The two arms carrying a
   `host` term (`host <> 'm1'`, `host = 'm1'`) would go NULL on a NULL `host` — but
   `.lnk_host()` (`R/utils.R:202-208`) falls back to `"unknown"`, so the column is never
   NULL or empty by construction at the writer. Not reachable.
3. **An empty-string arm.** `nullif(concat_ws(...), '')` → `coalesce(..., 'OK')` would
   turn a firing-but-empty arm into `OK`. Every arm's `THEN` is a non-empty literal, so
   no arm can produce `''`. The only path to `''` is all-arms-NULL, which is what `OK`
   means.
4. **`concat_ws` itself returning NULL.** Only when the separator is NULL. It is `'; '`.
5. **The nested `CASE` in the bcfp arm.** Its inner `CASE` has both branches populated
   (`FAIL:` / `NOTE:`), so the arm is never NULL when the outer condition holds. If the
   inner `ELSE` were ever dropped, the arm would silently vanish rather than mis-label —
   the one place in §1b where a future edit could reintroduce a *drop*. Worth a one-line
   comment; not a defect today.

Ordering is now genuinely not load-bearing: reordering the seven arms changes only the
order of the semicolon-joined tokens. That is the property round 3 asked for.

### The GUC read is correct in all three states

`current_setting('lnk.unpinned_ok', true)` inside §1b, all three states traced against the
`set_config` at :125-129 (which is unconditional and now precedes §1b, so `missing_ok`
never actually fires in-script — it is correct belt-and-braces for someone running §1b
standalone):

| state | `current_setting` | after `coalesce`/`btrim`/`nullif` | verdict text |
|---|---|---|---|
| unset (standalone §1b) | NULL | NULL | `FAIL:` |
| `-v unpinned_ok=` → `''` | `''` | NULL | `FAIL:` |
| `'   '` (whitespace) | `'   '` | NULL | `FAIL:` |
| `'tunnel down'` | `'tunnel down'` | non-NULL | `NOTE:` |

**And it is the same predicate the DO block uses** — `nullif(btrim(...), '')` at :319 vs
:218-219. That cross-function agreement is the thing that matters here (two places
deciding "is this a written reason" with different comparisons is a silent bug class), and
it holds term for term. The only difference is `missing_ok`, which cannot diverge because
both read a GUC set by the same statement.

## Findings

- **[bug] data-raw/study_area_verify.sql:209-210 and :213-215 — the new comment's stated
  invariant is false on the arm directly above it, and the DO block does not raise for
  that arm.** The comment added by this fix reads *"Escape-aware, so the word FAIL never
  appears on a run this script then declares OK. A wrapper grepping for FAIL must not hit
  on a sanctioned run; that is how the word stops being read."*

  `FAIL: fresh_sha NULL on a cypher` (:209-210) does exactly that. The DO block
  deliberately omits `fresh_sha` (:384-387, correctly — NULL is expected on the
  dispatcher), so a cypher row with a NULL `fresh_sha` prints `FAIL:` in §1b and then
  `=== verify: OK ===` at rc 0. Round 3 already measured this as its own control:

  ```
  cypher-job1 | FAIL: fresh_sha NULL on a cypher                  rc=0
  ```

  The severity-labelling problem the escape-aware rewrite was written to close is
  therefore half-closed. Enumerating all seven arms against the DO block, reported-vs-
  enforced:

  | §1b arm | enforced by the DO block? |
  |---|---|
  | `FAIL: link_sha NULL` | yes — `n_prov` (:392-401) |
  | `FAIL: fwapg_sha NULL` | yes — `n_prov` |
  | `FAIL: link_dirty set` | yes — `n_prov` |
  | `FAIL: bcfp_model_version NULL` | yes — `n_pin` (:404-414), with the escape |
  | **`FAIL: fresh_sha NULL on a cypher`** | **no — nothing raises** |
  | `NOTE: link_dirty NULL` | no, by design and labelled NOTE |
  | `NOTE: dispatcher now carries a fresh_sha` | no, by design and labelled NOTE |

  So `fresh_sha` is the **only** arm labelled `FAIL:` that no assertion backs. Every other
  reported-but-not-enforced condition is already labelled `NOTE:`. That is not an
  arbitrary inconsistency — it is the file's own convention, applied to six of seven arms.

  Two coherent resolutions; the current state is neither:

  - **Raise it, host-aware.** The §1b arm proves the predicate is expressible:
    `... WHERE run_uid = $1 AND host <> 'm1' AND fresh_sha IS NULL`. This is link#246's
    acceptance criterion, and the reason it is worth raising is exactly the reason round 3
    gave for keeping it visible — §1b is its only reporter, so if nobody reads §1b it is
    unreported.
  - **Relabel to `NOTE: fresh_sha NULL on a cypher -- reported, not enforced`**, and say
    in the comment that one arm is deliberately advisory.

  Either way the comment at :213-215 needs to stop claiming an invariant the file does not
  hold, or it becomes the fourth iteration of "a rule written in a comment that the next
  arm quietly breaks" — which is the thing this round's rewrite was meant to end.

- **[fragile] data-raw/study_area_verify_negative.sh:203-205 — the case-4 "restore" is
  not correlated, so it does not restore; it flattens.** It sets *every* row of
  `${SCRATCH}.log` to the `bcfp_model_version` of one arbitrary source row
  (`LIMIT 1`, no `ORDER BY`, no join key). Two consequences:

  - **Today: harmless but load-bearing on a coincidence.** Nothing runs after :205, and
    §2 of the verify script asserts the hosts agree on `bcfp_model_version`, so the
    flattening is currently a no-op *because of a property another check enforces*. A
    case 5 appended after :205 inherits a table whose pin column is uniform by
    construction, and a per-host pin defect would then be structurally untestable — the
    fixture-cannot-reach-the-failure shape, arriving through a cleanup step.
  - **If the source run is itself partly unpinned**, the arbitrary `LIMIT 1` row may carry
    NULL and the "restore" writes NULL everywhere.

  Correlated form, same cost:

  ```sql
  UPDATE ${SCRATCH}.log t SET bcfp_model_version = s.bcfp_model_version
    FROM ${SRC_SCHEMA}.log s
   WHERE s.run_uid = '${RUN_UID}'
     AND s.host = t.host AND s.watershed_group_code = t.watershed_group_code;
  ```

- **[fragile] data-raw/study_area_verify_negative.sh:179-187 — case 4 has no premise
  guard, and case 2 (the case it is modelled on) does.** If the run under test is already
  unpinned — every `bcfp_model_version` NULL, which is precisely the situation
  `unpinned_ok` exists for and which `preflight_local()` sanctions — then the `UPDATE` at
  :179 is a no-op and 4a/4b/4c exercise nothing while printing three ✓ marks.

  It is not fully silent: case 1 fails in that state and says so. But the file's own
  standard is higher than that, and it already meets it three lines up — case 2 refuses to
  claim a pass when `VICTIM` is empty, prints `⊘ SKIPPED`, and increments `fails`
  (:137-142), with the comment *"Absence reported as absence — this is NOT a pass."* Case
  4 wants the same three lines:

  ```bash
  N_PINNED=$("${PSQL[@]}" -c "SELECT count(*) FROM ${SCRATCH}.log
                               WHERE bcfp_model_version IS NOT NULL")
  # 0 -> ⊘ SKIPPED, fails=$((fails+1)), skip 4a-4c
  ```

## Checked, no finding

- **`SCRATCH_MADE=1` moved before the heredoc (:85) introduces nothing.** Enumerated every
  path it changes: (a) the heredoc aborts mid-way under `ON_ERROR_STOP` → trap now drops,
  which is the round-3 fix working; (b) the heredoc's own first statement fails (server
  unreachable, no permission) → the trap attempts a drop of a schema this run did not
  create, but the handler is `-c "DROP SCHEMA IF EXISTS ... " >/dev/null 2>&1 || true`, so
  it cannot fail the script or destroy anything; (c) success → unchanged. `SCRATCH` is a
  fixed dedicated name (`zz_lnk_verify_negative`), so the only thing an over-eager drop can
  hit is a **concurrent** run of this same script — and two concurrent runs already clobber
  each other at the heredoc's own `DROP SCHEMA IF EXISTS` on line 87, so the exposure is
  not new and not widened in kind. The comment at :76-84 states the flag's meaning
  correctly (*"may have created it"*, not *"finished"*), which is what makes the early arm
  sound.
- **`SCRATCH_MADE=1` is still after the `RUN_UID` resolution and its `exit 1` (:45-55),** so
  the early-exit path that legitimately has nothing to clean is unaffected.
- **Cases 4a/4b/4c cannot interfere with each other.** They share one mutation (:179) and
  differ only in psql `-v` flags; none writes. 4b and 4c depend on 4a's `UPDATE` having
  run, which it does unconditionally two lines above.
- **Reordering 4 ahead of 1–3 would not corrupt them**, given the flattening above is
  currently a no-op — but that is a coincidence, which is the point of the second finding.
  Cases 1–3 touch `log_recompute` and `expected_n`; case 4 touches
  `log.bcfp_model_version`. Disjoint columns.
- **Case 2's restore is correlated and correct** (`INSERT ... SELECT ... WHERE run_uid AND
  watershed_group_code`, :156-158) — which is the contrast that makes case 4's worth
  fixing rather than a matter of taste.
- **`-v unpinned_ok='   '` survives the shell → psql → `:'unpinned_ok'` → `set_config`
  round trip as three spaces**, so 4c genuinely reaches the `btrim` guard rather than
  degenerating into the empty-string case that 4a already covers. Two distinct inputs, two
  distinct paths through the same predicate.
- **`PASS (UNPINNED)` / `PASS` split (:416-422) is driven by `n_pin`, not by `v_unpin`.**
  Correct: reaching that point with `n_pin > 0` implies `v_unpin` is non-NULL (the raise at
  :409 is the only other exit), so the two conditions cannot disagree, and keying on `n_pin`
  is the one that stays true if the escape mechanism is ever changed.
- **Moving the `set_config` block above §1b (:120-129) does not change what the DO block
  reads.** `is_local = false`, so the settings persist for the session across psql's
  implicit per-statement transactions; there is no `ROLLBACK` path between :129 and :311
  (every intervening statement is a `SELECT`). `\gset assert_` still consumes the row, so
  nothing new prints. The comment at :305-309 explaining why the block uses
  `current_setting` remains accurate even though the call site moved.
- **`host <> 'm1'` as the dispatcher discriminator is a hardcoded literal**, but it is the
  established convention (`LNK_HOST_ALIAS=m1` per `R/utils.R:193-206`, and the same literal
  is the reference host across `lnk_preflight_parity`'s tests). Pre-existing, unchanged by
  this diff, not raised.

## Convergence

**Not yet — one class remains open, and I can name it precisely rather than gesture at it.**

- The **shadowing** class is closed. Candidate set enumerated above (five ways `concat_ws`
  could drop or hide an arm); none is reachable, and arm order no longer affects output.
- The **`FAIL` that exits 0** class is open on exactly one arm. Candidate set: the seven
  §1b arms, checked one by one against the DO block's five `RAISE`s. Six are consistent
  (four `FAIL` + enforced, two `NOTE` + not enforced); `fresh_sha` is the single residual.
  There is no eighth arm and no other reporter, so fixing that one arm terminates the
  class — this is an enumeration, not an estimate.

The negative-script findings are both about *test* strength, not about behaviour the
217-WSG run depends on. The `fresh_sha` finding is not: it is link#246's acceptance
criterion reporting `FAIL` on a run this script declares good.

/Users/airvine/Projects/repo/link/planning/active/review-round4.md
