# Review — round 2 (link#262, branch `262-provenance-gaps-before-217-wsg-run`)

Second pass, scoped at the round-1 **fixes**. Diff read in full; `.lnk_git_dirty_at()`
probed against a real checkout (13/13 pass, `git 2.54.0`); the `:(top,exclude)` pathspec
confirmed to work with no positive pathspec; `RECOMPUTE_FAIL_STAGE` readers enumerated;
`n_dirty_unknown` consumers grepped repo-wide.

## Findings

- **[bug] data-raw/study_area_verify.sql:172-175 — round-1 fix #4 inserted a NOTE arm
  above a FAIL arm, and it shadows it.** `CASE` returns the *first* matching arm. The new
  `WHEN count(*) FILTER (WHERE link_dirty IS NULL) > 0 THEN 'NOTE: …'` is placed at line
  172, above `WHEN host <> 'm1' AND count(*) FILTER (WHERE fresh_sha IS NULL) > 0 THEN
  'FAIL: fresh_sha NULL on a cypher'` at line 174. A host matching both reports the NOTE
  and the FAIL is never printed.

  This is not cosmetic, because §1b is the **only** reporter of that condition — the DO
  block at 338-348 deliberately omits `fresh_sha` from its assertion set (correctly, since
  NULL is expected on the dispatcher). So the arm that verifies link#246's acceptance
  criterion (`fresh_sha` non-NULL on cyphers, `NA` on every cypher before that work) is
  silently unreachable whenever `link_dirty` is also NULL on that host.

  The two conditions co-occur in exactly the case the section exists for: a cypher whose
  `cypher_prep.sh` did not complete writes no `LINK_GIT_DIRTY` into `~/.Renviron` (→
  `link_dirty` NULL, since a pak-installed package has no `.git`) *and* leaves `fresh`
  at the image's version with no `RemoteSha` (→ `fresh_sha` NULL). One partial prep
  produces both, and the verdict reads "provenance unknown" rather than "this cypher ran
  the wrong fresh".

  Fix: move the `link_dirty IS NULL` arm below every `FAIL:` arm, or stop using a single
  ordered `CASE` for a multi-condition verdict (e.g. `concat_ws('; ', …)` over per-condition
  expressions) so severity ordering stops being load-bearing.

  **Mechanism, not instance:** the ordered `CASE` carries an unwritten invariant — *every
  FAIL arm precedes every NOTE arm*. Round 1 added three arms (`bcfp_model_version`,
  `link_dirty` true, `link_dirty` NULL) and preserved it for two of them. Any future arm
  has the same trap, and nothing in the file states the invariant. Worth one comment above
  the `CASE` saying so.

- **[fragile] data-raw/study_area_verify.sql:161-162 + 341-347 vs
  data-raw/study_area_run.sh:527-533 — the driver permits an unpinned run and the verifier
  hard-fails it.** `preflight_local()` treats a missing bcfp baseline as a **WARN**, with
  the rationale stated inline: *"An unpinned run is worse provenance but still correct
  modelling, and refusing to run over it would make the pin a blocker rather than a
  record."* But `bcfp_model_version IS NULL` is now both a `FAIL` arm in §1b and a term in
  the DO block's provenance assertion, which `RAISE`s. There is no `-v` to relax it.

  So a run that the driver deliberately allowed to proceed cannot pass its own verifier,
  and the message the operator gets (`% row(s) missing link_sha / fwapg_sha /
  bcfp_model_version, or flagged link_dirty`) does not distinguish the sanctioned case
  from a genuine one. At 217 WSGs the natural response — re-run — is hours and real spend
  for a provenance-only shortfall.

  Pick one: promote the pre-flight to a hard gate (it already has `--preflight-note=` as
  the documented escape), or demote `bcfp_model_version` out of the DO block and report it
  the way `fresh_sha` is reported — printed in §1b, not raised.

- **[fragile] data-raw/study_area_verify_negative.sh:51-83 — the EXIT trap is installed
  after the scratch schema is created.** `CREATE SCHEMA zz_lnk_verify_negative` happens at
  51-62 and `trap cleanup EXIT` at 83. Under `set -euo pipefail`, a failure in between —
  the `N_WSG` query at 65, or `mktemp … || exit 1` / `[ -n "$VERIFY_LOG" ] || exit 1` at
  72-73 — exits with no trap registered and leaves the schema in the database. The
  `SCRATCH_MADE` guard inside `cleanup()` already exists for precisely this ordering, so
  the fix is to set `SCRATCH_MADE=0`, register the trap, then create the schema and set
  `SCRATCH_MADE=1`. Self-healing on the next run only because line 52 is
  `DROP SCHEMA IF EXISTS`; a run that never happens leaves it indefinitely.

- **[fragile] data-raw/study_area_verify_negative.sh:33 + 51-62 — the setup heredoc runs
  without `ON_ERROR_STOP`, so a partial scratch schema is built silently.** `PSQL=(psql -h
  … -t -A)` carries no `-v ON_ERROR_STOP=1`; psql continues past a failed statement in a
  multi-statement script and exits **0**. If `${SRC_SCHEMA}.log_recompute` is absent (an
  older persist schema, pre-#262) or `streams` is missing, that `CREATE TABLE AS` fails,
  the shell sees success, and case 1 then reports `✗ 1. healthy data -> FAILED, but should
  have passed` — pointing the operator at `study_area_verify.sql` when the fault is in this
  script's own setup. `show_verify` prints psql's error, so it is recoverable, but the
  first-order diagnosis is wrong. Add `-v ON_ERROR_STOP=1` to the array; it is inert for
  the single-statement `-c` probes that share it.

## Checked, no finding

- **`logtables` stage token reaches every reader.** `RECOMPUTE_FAIL_STAGE` is read in
  exactly one place (`study_area_run.sh:1416`/`:1419`); both the `logtables` and `views`
  branches name a file their own step actually wrote, and the `:-pool` default covers the
  pool branch. The nested `if [ "$RECOMPUTE_FAIL" = "0" ]` around the views build (rather
  than `&&`) does prevent the mis-attribution its comment describes.
- **`n_dirty_unknown` breaks no consumer.** Repo-wide grep: `study_area_verify.sql` is
  read only by humans, `RUNBOOK.md:586`, and `study_area_verify_negative.sh` (which parses
  nothing — it branches on exit status). No script or R function selects these columns.
- **`\quit 1` → `DO $$ RAISE EXCEPTION $$` (fix #1) is correct.** `\set ON_ERROR_STOP on`
  at line 53 precedes it, the `\if`/`\endif` nesting is intact, and the `\gset` on line 81
  guarantees `have_run` is always defined.
- **`.lnk_git_dirty_at()` pathspec.** Verified live: `git status --porcelain --
  ':(top,exclude)data-raw/logs'` with no positive pathspec returns rc 0 and matches
  everything else on git 2.54.0; `shQuote()` survives `system2()`; the `Sys.which("git")`
  pre-check is reachable (`attr(out,"status")` is NULL on success, so the skip is not dead
  code). Full test file passes 13/13.
- **`recompute_wsg()` wrapping in `wsg_recompute_one.R`.** No variable assigned inside the
  new function is read after it returns — `active` (line 53) and `pres`/`sch`/`wsg` are all
  top-level and precede it; `sp_set`, `mc_cols`, `mc_scratch` are local and unused
  downstream. The `on.exit()` DROP now fires. The species-skip early exit (54-57) runs
  before `.rc_start`, so a skipped WSG opens no recompute row.
- **`cypher_prep.sh:142` still uses a bare `git status --porcelain`**, not the new
  pathspec. Traced the ordering: it runs at line 142, before `snapshot_bcfp.sh` at line
  225 and immediately after `git reset --hard` at 97, so `LINK_GIT_DIRTY` is captured on a
  genuinely clean tree and the cyphers are unaffected today. Flagging only that the
  predicate is now defined in three places with two spellings, and the DO block newly
  makes `link_dirty` a hard failure — so a future reordering of `cypher_prep` reintroduces
  link#257 on the workers as a run-failing error rather than a cosmetic flag.
- **`.lnk_bcfp_log_current()` tier chain.** `.lnk_blank_to_na()` correctly turns
  `LNK_BCFP_MODEL_RUN_ID=""` into `NA_integer_`; `export LNK_BCFP_MODEL_VERSION` inside
  `preflight_local()` does reach the ssh legs (the function is called directly at line 748,
  not in a subshell). Note the roxygen claim *"a cypher has no row of its own"* is
  inaccurate — `cypher_prep.sh:225` does run `snapshot_bcfp.sh`, whose
  `lnk_baseline_append()` is not gated on `--with-bcfp-views` — but the behaviour is benign
  (tier 0 wins when exported; tier 2 finds the cypher's own honest row otherwise).
- **Negative script cannot report success without testing.** Case 1 runs first and is
  counted; the "no `log_recompute` rows" branch increments `fails` rather than passing;
  case 3 always runs. `set -e` is suspended inside every `if` condition, and
  `fails=$((fails + 1))` is an assignment (always status 0), so no accidental abort.
