# Code review, round 2: link#349 branch (`branch_r2.diff`)

## Checklist read

All four FULL TEXT files are over 40,000 bytes, so I read sections, not whole files.

- **code-check.md (329 KB):** I read the prose of all 14 H3s under `## Mechanisms`, without the table rows. I read no other sections (34 headings unread).
- **code-check-r.md (175 KB):** I read 9 sections:
  - "`on.exit()` at a script's top level never fires"
  - "A `data-raw/` script must load the source tree"
  - "Postgres row order is never fixed…"
  - "`sprintf("%g", x)` writes `Inf` and `NA`…"
  - "An `information_schema` lookup by the literal table name…"
  - "A database driver's value is not a base R type"
  - "Rscript reads a script as it runs"
  - "`paste()` with a zero-length argument"
  - "`ifelse()` with an all-NA test"

  I did not read the remaining ~140 headings, because none names a tool or shape this diff uses.
- **code-check-shell.md (121 KB):** I read 6 sections:
  - "psql does not interpolate `:'var'`…"
  - "A second `trap … EXIT` replaces the first"
  - "Empty arrays under `set -u`"
  - "`grep -c` prints the count AND exits 1"
  - "`for x in $(cmd | grep … || true)` hides a failing `cmd`"
  - "Quoting"

  I did not read the other ~95.
- **code-check-spatial.md (154 KB):** I read 0 sections. The diff has no spatial code; its FWA-measure items concern fresh's predicate, which this branch does not change.

## What I checked, and what was clean

- **Round 1, fix 1 (the model leg gates on a dispatch).** `study_area_run.sh` sets `LNK_HABITAT_GATE=0` on both legs. Those are the only two `wsg_run_one.R` invocations in `study_area_run.sh`, `study_area_hosts.sh` and `study_area_finish.sh` (the latter two only echo it). `test-lnk_pipeline_prepare.R:1140` pins both legs.
  - Model-time gating is safe on a single-host, downstream-first run. `lnk_barriers_views.R:212` anti-joins `barrier_overrides` by position, not by group, so any holder's lift lifts every persisted copy of a shared barrier.
  - So model-time access is more closed than final access only when a stale or not-yet-rebuilt group holds the barrier alone. See finding 2.
- **Round 1, fix 2 (the province observations copy stays in every kept working schema).**
  - `observations_province` has one production reader: `lnk_barrier_overrides()` in `.lnk_pipeline_prep_overrides()`. The table is dropped right after it.
  - `overrides_scope_time_349.R` builds its own copy and never calls `prep_overrides`, so the drop does not affect it.
  - `<schema>.observations` (break source, access code 2) is unchanged.
  - The province SQL uses the alias `o` that `excl_filter` expects. `bcfishobs.observations` has `wscode` / `localcode` ltree columns, which the GiST indexes need (checked by psql).
- **`lnk_habitat_gate()`.**
  - Joins use the full key.
  - The overlay match is the same as `frs_habitat_overlay`'s bridge predicate. The overlay applies only `spawning` / `rearing`, so blanking `lake_rearing` / `wetland_rearing` matches classify.
  - `truthy()` handles the CSV's `1` and blank values.
  - The temp overlay is session-scoped.
  - Counts are taken in the same transaction as the update.
- **`.lnk_mapping_code_persist()`.** `lnk_persist_init` creates `streams_mapping_code` and `streams_habitat_long_vw` unconditionally. `lnk_pipeline_setup(overwrite=TRUE)` drops the working schema, so no stale working `streams_mapping_code` reaches the second persist.
- **Log columns.** `R/lnk_log.R:504` adds columns with `ADD COLUMN IF NOT EXISTS`, so log tables gain the four new columns. Consolidate copies the column intersection (`schema_consolidate.R:357`).
- **`study_area_verify.sql`.**
  - `v_sch` / `v_run` are declared.
  - `substr(...,17)` is right for `streams_habitat_`.
  - `streams_habitat_long_vw` is excluded both by the regex and by `BASE TABLE`.
  - The species loop guards a missing `access_<sp>` column.
- **Negative case 6d.** It fails closed (SKIPPED counts as a failure). It restores what it mutates. The scratch habitat copy is settled, so case 1 holds.
- **Doc numbers.** I re-derived these against the committed evidence, and they match:
  - every row of the `research/access_columns.md` species table (forward, share, A, A′, B, residual, reverse);
  - side_effects (CH 189 … ST 110; lake polygons 0);
  - ELKR RB 6,623;
  - R_override_scope 169 / 299 / 2;
  - gate.csv (UPCE 396 / 51.6 km, CARP 77 / 9.7 km, DUNC 694 / 249.9 km, lifted 0);
  - access_transitions (CARP KO 3,694.8 km, RB 4,419.7 km; UPCE RB 843.4; DUNC RB 4.6);
  - rollup deltas (UPCE RB +197.7 / +345.9 km, GR +22.9; DUNC BT −0.01 / −0.14);
  - baseline B for CARP (13,982 / 17,578);
  - overrides_scope_time (DUNC 27.6 → 18.6 s, CARP 18.0 → 17.5 s, prep 3.9 s);
  - KO 17 records against a threshold of 5.

## Findings

- **[bug — doc an operator acts on] CLAUDE.md:20, RUNBOOK.md:193, research/access_columns.md:118.**
  - **What's wrong.** All three name the command that settles `fresh_default` as `study_area_finish.sh --recompute-only --run-uid=<uid>`.
    - `data-raw/study_area_finish.sh` is a library sourced by `study_area_run.sh`. Its header says "Sourcing defines functions and declares CY_BUCKET_DONE …, nothing else".
    - It parses no arguments. `--recompute-only)` is parsed only at `study_area_run.sh:172`.
  - **Why it matters.** `bash data-raw/study_area_finish.sh --recompute-only --run-uid=…` defines functions and exits 0 having run nothing. The operator would then believe `fresh_default` is re-gated, when its verify will still fail. That is the very step CLAUDE.md's status block hands to the operator.
  - **The fix.** The command is `bash data-raw/study_area_run.sh --recompute-only --run-uid=20261017_004619-3f4c713b --config=default --schema=fresh_default`, the form `study_area_finish.sh:673` and RUNBOOK §8d already print. Without `--config` it defaults to `bcfishpass` (`study_area_run.sh:126`) and `run_config_check` refuses.

- **[fragile — the round-1 defect class, on the dispatch's own recovery path] data-raw/study_area_finish.sh:663-670 (printed remedy), RUNBOOK.md:1310-1312 (§8d snippet).**
  - **What's wrong.** The re-model command printed for a run's missing groups is `LNK_RUN_UID=… LNK_SCHEMA=… LNK_GUARD_DOWNSTREAM=warn LNK_LOAD=loadall Rscript data-raw/wsg_run_one.R <WSG> <config>`, with no `LNK_HABITAT_GATE=0`. So the recovery re-model gates at model time, followed by `--recompute-only`.
  - **When it loses habitat.** The remedy says outright that a group may be re-modelled while its downstream neighbour is still missing ("a group whose downstream neighbour is missing too…"). #348's COV_STALE class is a failed group that still holds an earlier run's rows.
    - On every current schema those earlier rows are pre-#349: no province-wide lifts, no RB rule.
    - Suppose group G is re-modelled while a stale downstream group M alone holds a barrier that M's rebuild will lift (an RB barrier, say). G's habitat is then blanked against M's stale overrides.
    - M is re-modelled next and lifts the barrier. The `--recompute-only` lifts G's access but cannot restore its habitat.
  - **How it surfaces.** It is detected (`habitat_gate_lifted`, and "need a re-model"), but the cure is another re-model plus another recompute.
  - **The fix.** Add `LNK_HABITAT_GATE=0` to both copies of the remedy. A `--recompute-only` always follows it and settles every group. Optionally pin the printed remedy in `test-study_area_finish.R`, as the two dispatch legs are pinned.

- **[fragile — low] data-raw/wsgs_run_host.R:311 → R/lnk_compare_wsg.R:192.**
  - **What's wrong.** The older multi-host orchestrator (`wsgs_dispatch.sh` / `wsgs_run_pipeline.sh`) models each group through `lnk_compare_wsg()`. That calls `lnk_pipeline_run()` with the new default `habitat_gate = TRUE`, and `lnk_compare_wsg()` has no argument to turn the gate off.
  - **Why it matters.**
    - That path runs no post-consolidate recompute, so the gate settles each group on host-local access, which is what it ships. That is consistent for now.
    - But a later recompute of that schema (`--recompute-only`, `wsg_recompute_one.R`) makes the losses permanent, exactly as round 1 described.
    - If the path is still live, it needs the same switch (an `habitat_gate` passthrough on `lnk_compare_wsg`, or `LNK_HABITAT_GATE` read in `wsgs_run_host.R`). If it is retired, nothing.

- **[doc — wrong against the cited evidence] research/access_columns.md:56-59 ("B, cross-group barriers. Whole groups: RB in 25 (…), … GR in ELKR, TURN and BULL (KOTL rows with 1–3 GR records upstream …)").**
  - **The RB count.** `groups_blocked.csv`, the file the paragraph cites, lists **27** RB groups blocked whole (≥ 99 % of accessible):
    - 16 behind the UPCE Peace rows;
    - 4 behind the REVL rows;
    - 3 behind the LNRS rows;
    - 3 behind the CLWR falls (the Clearwater: BRID, MAHD, MURT);
    - **TURN, behind the UKEC falls** (359571382 @ 52.2 m), which the parenthetical's list of drainages omits.
  - **The GR attribution.** GR TURN is blocked by that same UKEC falls (3 GR records upstream), not by a KOTL row. Only BULL and ELKR are behind the KOTL rows (1 record each).

- **[doc — low] data-raw/study_area_hosts.sh:124-126.**
  - **What's wrong.** `host_complete()`'s rationale says `streams_mapping_code` rows are written only by "lnk_pipeline_run()'s FINAL persist". Since this branch, the persist no longer writes them. `.lnk_mapping_code_persist()` writes them after the gate.
  - **Why it is low.** The completeness signal still holds, because mapping codes are still the last persisted write before the log row closes. But the comment names a mechanism that no longer exists, in the code that decides which host may be burned.
