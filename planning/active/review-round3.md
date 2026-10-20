# Code-check round 3 — #349 (branch_r3.diff)

## Checklist read

Every FULL TEXT file is over 40,000 bytes, so none was read in full.

- code-check.md (329 KB): all prose of the 14 H3s under `## Mechanisms` (table rows skipped), plus
  "Documentation Staleness", "A preview flag is only safe if it previews", "An assertion that
  matches an interpolated value cannot see the claim around it". Remaining standalone/security/
  spreadsheet headings not read (~25): no tool or shape in this diff.
- code-check-r.md (175 KB): `on.exit()` at a script's top level; `data-raw/` must load the source
  tree; A database driver's value is not a base R type; `::text` spelling; `tryCatch(warning = )`;
  `tryCatch()` nests its handlers; Postgres row order; `information_schema` lookup by literal name;
  `sprintf("%g")` Inf/NA; Rscript reads a script as it runs; `vapply(USE.NAMES = FALSE)`; `$`
  partial-match. 12 read; ~150 headings not read (no matching tool/shape).
- code-check-shell.md (121 KB): psql `:'var'` in dollar-quotes / `\quit`; `for x in $(cmd | grep
  || true)`; Tailscale ssh exit status; `&` binds to the `&&` list; Quoting; Heredoc precedence;
  A heredoc whose body contains its delimiter. 7 read; ~95 not read.
- code-check-spatial.md (154 KB): FWA `upstream_route_measure` misses the next segment's start;
  FWA main flow is not edge type 1000. 2 read; ~110 not read.

## Mechanism

The gate turned the post-consolidate recompute from an idempotent "re-run it and it is right"
step into one that performs a **one-way write** (`streams_habitat_<sp>` flags go FALSE and only a
re-model brings them back). Everything in the repo that was built on the old contract — "the
recompute writes `streams_access` and `streams_mapping_code`, and re-running it repairs whatever
model time got wrong" — is now a list that only happens to agree with the code:

1. every sequence that gates and then lets something *later* lift access (R1, R2's remedy and
   RUNBOOK copy — and, below, the documented order for settling `fresh_default`);
2. every hand-kept list of "what the recompute writes" (`recompute_checksum.sql`, the
   snapshot/restore in `recompute_parity.sh`, the `LNK_LOG=0` benchmark rationale);
3. every reader of the recompute's outcome that would have to notice a loss (the driver's report,
   verify): nothing reads `habitat_gate_lifted`.

Checked and not defects: both `study_area_run.sh` legs, `study_area_finish.sh`'s printed re-model,
RUNBOOK §8d copy (all `LNK_HABITAT_GATE=0`); `habitat_variants_build.R` base (single host, DS-first;
overrides are matched by position and now computed from the same province table, the same control
and habitat tables by every holder, so the recompute has nothing to lift); `wsg_pipeline_run.R` /
`_targets.R` / `lnk_compare_wsg()` / `wsgs_run_host.R` (no recompute follows); the
`lnk_wsg_downstream_check()` remedy (the later recompute only adds the unmodelled groups' barriers,
which block, never lift); `recompute_sweep.sh` (no restore; its writes are a real recompute's).
Commands verified against argument parsing: `study_area_run.sh --recompute-only --run-uid=20261017_004619-3f4c713b
--config=default --schema=fresh_default` (uid regex, config-name check and the pre-#358 log fallback
all pass); verify.sql's `wsg_recompute_one.R <WSG> <config>` (positional args, `LNK_SCHEMA` honoured);
the finish/RUNBOOK re-model line.

## Findings

- **[severity: bug]** CLAUDE.md:20, RUNBOOK.md:195-197, research/access_columns.md:117-122 — the
  documented way to settle `fresh_default` loses habitat that the documented follow-up then cannot
  restore. All three present "re-gate with `study_area_run.sh --recompute-only …`" as the step (and
  CLAUDE.md says verify fails until it runs), then "the RB / KO / BT lifts behind shared barriers
  need a re-model of the groups that hold those barriers". In that order: the re-gate settles every
  group on `fresh_default`'s *current* access, in which the Peace rows are un-lifted, so CARP's KO
  (13,982 segments) and the 27 RB groups' habitat (457,912 B-class segments) go FALSE. Re-modelling
  the holders (UPCE etc.) then writes the province-wide lifts, and the next recompute lifts those
  segments' `access_<sp>` 0 → 1 while their habitat stays FALSE — one-way. Restoring them needs a
  re-model of every *upstream* group whose access the lift opens (CARP, NATR, PARS, the 27 RB
  groups), not "the groups that hold those barriers". Done the other way round (re-model the holders
  first, then one `--recompute-only`), the gate never blanks them. Worse, nothing would tell the
  operator: `habitat_gate_lifted` and the "N lifted segments need a re-model" line exist only in
  `log_recompute` and each group's `$RC_DIR/<WSG>.log`; `study_area_finish.sh` / `study_area_run.sh`
  never read or report either (grep: no `lifted`/`habitat_gate` in either driver), and
  `study_area_verify.sql`'s invariant (`accessible AND access = 0`) passes on exactly this state.
  Fix the docs' order (holders first, then re-gate) and name the upstream groups; consider having
  run_finish report any `habitat_gate_lifted > 0` for the run.

- **[severity: fragile]** data-raw/recompute_parity.sh:77-102 and data-raw/recompute_checksum.sql:1-2,57-66
  — the parity tool's list of what the recompute writes is now short by the table the gate writes.
  `snapshot()` / `restore()` and the digest cover only `streams_access` and `streams_mapping_code`
  (the checksum header still says it digests "everything the post-consolidate recompute writes"), so:
  pass C no longer starts "from the SAME snapshot as A" (habitat is still gated by A), the "A == B
  == C, byte-identical" verdict says nothing about the gate's output, and — because these benchmarks
  run with `LNK_LOG=0` — on a schema not yet settled the benchmark performs the one-way habitat
  write with no `log_recompute` row, so the `habitat_gate_{n,km,lifted}` record of that settle never
  exists (default target is `fresh`, which is unsettled today). Add the per-species habitat tables to
  the snapshot/restore and the digest, or refuse to run on a schema whose recompute has not settled.

- **[severity: fragile]** research/access_columns.md:117 ("Any build or recompute at or after the
  #349 merge" is settled) and inst/extdata/schemas/habitat_fwa_v1_segment.yaml:104-107 — a build
  at or after the merge is *not* settled when it ran gate-off (every `study_area_run.sh` model leg,
  `lnk_pipeline_run(habitat_gate = FALSE)`) and its recompute has not run or failed (the run's
  `not_consolidated` / `no_rows` / `not_this_run` groups are never recomputed). An exporter reading
  that sentence would treat such a group's `accessible` as settled; the exported manifest carries no
  per-group gate flag to tell them apart. State it as "a build whose last write was a gate (model
  with the gate on, or a recompute) after #349".

/private/tmp/claude-501/-Users-airvine-Projects-repo-link/aa5910b1-8014-4753-9f3f-2e3e62f9d8e2/scratchpad/review-round3.md
