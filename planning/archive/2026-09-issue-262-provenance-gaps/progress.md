# Progress — Provenance gaps before the 217-WSG run (#262)

## Session 2026-09-01

- Plan-mode exploration; verified all four gap counts against `fresh.log` rather than
  reading the schema
- Found three corrections to the issue body: `run_label` is plumbed and unfed;
  `.lnk_bcfp_log_current()` exists and its source is unreachable by design; the
  deterministic bcfp ref is the local ledger, not the tunnel
- Four design decisions approved by the user (own `log_recompute` table; keep untracked
  in the dirty predicate; ledger fallback at run open; `run_uid`)
- Created branch `262-provenance-gaps-before-217-wsg-run` off main
- Scaffolded PWF baseline with the approved phases
- Next: Phase 1 — `run_uid` + `run_label` end to end

### Implementation (same session)

All six phases implemented. Notable events, in the order they happened:

- **Phase 4 bug caught on the first probe.** `system2()` shell-quotes the command
  and pastes arguments on raw, so the parentheses in `:(top,exclude)` were parsed
  by the shell (`syntax error near unexpected token '('`). The command never ran
  and `.lnk_pkg_git_dirty()` returned `NA` for every input — a net regression over
  the always-TRUE bug it replaced. Fixed with `shQuote()`. Invisible by reading.
- **Every new guard negative-tested** by restoring its defect and confirming red:
  bare pathspec → 2 failures; identity `.lnk_blank_to_na` → 3; ledger tier removed
  → 4. All green again on restore.
- **Plan review (concurrent) returned 3 blockers, 9 gaps, 3 ordering notes.** Five
  of its findings were already fixed by the time it landed (it read a mid-edit
  tree). Four were real and acted on: dead top-level `on.exit`; the cypher ledger
  hole; the circular expected-set; benchmark rows polluting `log_recompute`.
- **`on.exit` at an Rscript's top level never fires** — measured on both `stop()`
  and `quit()`. My first draft's fail-mark was dead code and its justifying
  comment was false. Work now runs inside a function.
- **End-to-end run found what unit tests could not.** Modelled + recomputed UTRE
  with `LNK_RUN_UID` set: the recompute row landed with `run_uid` NULL, because
  the env default was wired into `lnk_pipeline_run()` only. The tests passed the
  value explicitly and so never exercised the default. Fixed; regression test added.
- **psql does not interpolate `:'var'` inside a dollar-quoted string.** The
  assertion block failed at run time (`syntax error at or near ":"`) while reading
  perfectly. Parameters now arrive via `set_config`. Found by running it.
- Suite: **FAIL 0 | WARN 16 | PASS 1825**, against a HEAD baseline of
  **WARN 16 | PASS 1719** — +106 tests, no new warnings.

### Post-merge follow-up scoping (same session, 2026-09-01)

Traced what the provenance record can and cannot recover, by measurement:

- **link's 17 config files round-trip byte-exact.** `git archive` at a row's
  `link_sha`, recompute `.lnk_config_hash()` -> matches the stored value. So
  `link_sha` finds the files and `config_hash` proves those bytes were read.
- **fresh's CSVs**: exact on cyphers via `fresh_sha`; on m1 `fresh_version`
  0.33.0 -> tag `v0.33.0` recovers 7 of 7 data files byte-identical, but that is
  an inference the record cannot confirm.
- **Corrected a claim I had repeated all session**: m1's fresh DOES carry a
  `RemoteSha`, identical to the cyphers'. `.lnk_pkg_git_sha()` never reads it.
- **bcfishobs has no code pin at all** — a row count and a literal string.
- **The FWA object store is versioned** (`x-amz-version-id`, `?versionId=`
  re-fetch works) but **refuses listing**, so unrecorded ids are unrecoverable.

Two issue bodies drafted and preserved unfiled at `planning/active/`.
