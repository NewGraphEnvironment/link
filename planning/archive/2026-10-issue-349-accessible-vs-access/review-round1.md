## Checklist read

- code-check.md (329 KB): the prose of all 14 H3s under `## Mechanisms`, table rows skipped. The other sections (Rules that stand alone, Security, Spreadsheets) were not read: about 20 headings.
- code-check-r.md (175 KB): 5 of 111 headings read: "A database driver's value is not a base R type", "Postgres row order is never fixed…", "An `information_schema` lookup by the literal table name…", "`system2(stdout = TRUE)` warns…", "`sprintf("%g", x)` writes `Inf`…". The other 106 were not read. `on.exit` at top level and the data-raw load_all rule were checked against the repo conventions in the brief.
- code-check-shell.md (121 KB): 2 of 67 headings read: "`for x in $(cmd | grep … || true)` hides a failing `cmd`" and "psql does not interpolate `:'var'` inside a dollar-quoted string…". The other 65 were not read.
- code-check-spatial.md (154 KB): 0 of 92 headings read. The diff calls no spatial tooling except `ST_DWithin` in a measurement script.

## Findings

- **[severity: fragile / data loss]** R/lnk_pipeline_run.R:303-311 (the model-time `lnk_habitat_gate()` call)
  A group is settled at model time against the persisted barriers and overrides of other groups as they stand on that host. Off-host, those can be a previous run's rows. The post-consolidate recompute can lift such a segment (`access_<sp>` 0 to more than 0), but the settle is one-way, so its habitat stays FALSE until the group is re-modelled. `n_lifted_settled` / `habitat_gate_lifted` counts these segments; nothing restores them.
  - **Without the model-time gate there would be no loss.** fresh's `accessible` only sees the group's own breaks, so a segment blocked only by a cross-group barrier keeps its classify-time habitat. The recompute gate would then settle it against the final access, losing nothing.
  - **The next run is the bad case.** m1's persist holds the 2026-10-17 build of all 241 groups: AOI-scoped override counting and no RB observation rule. This branch makes override counting province-wide and adds an RB rule (threshold 1). Both newly lift barriers in downstream groups, but a group modelled on one host reads its cross-bucket downstream groups' old overrides. The model-time gate then blanks habitat (RB above all) that the recompute will lift, and it stays blank.
  - CLAUDE.md records that drainage-closed DS-first buckets are not sufficient and cross-bucket dependencies exist, so this is not hypothetical.
  - **The one-way settle is the operator's decision.** Gating at model time as well as in the recompute is what turns it into a systematic loss on multi-host runs.
  - **Options:** gate only in the recompute when one follows (e.g. `study_area_run.sh` exports `LNK_HABITAT_GATE=0` for the model leg on both the local and ssh legs), or make the run-time gate opt-in. The verify invariant already enforces that the recompute's settle happened.

- **[severity: fragile / disk]** R/lnk_pipeline_prepare.R:353-383, with data-raw/wsg_run_one.R:92 (`cleanup_working = FALSE`)
  - **What it does.** `.lnk_pipeline_prep_observations_province()` writes a province-wide copy of `bcfishobs.observations` into every working schema, filtered by presence, with two GiST ltree indexes. The source heap is 212 MB with 376k rows (measured).
  - **Why it piles up.** `wsg_run_one.R`, which `study_area_run.sh` drives, keeps every `working_<wsg>` schema. A 241-group run therefore keeps 241 copies of an identical table, roughly 150–250 MB each and tens of GB in all. The local working schemas already total 84 GB across 147 schemas (measured), and the fwapg volume has filled before (#331).
  - **What reads it.** The table does not depend on `aoi` (its rows come from `loaded` only). Its only consumer is `.lnk_pipeline_prep_overrides()`, a few lines later.
  - **Fix:** drop it after `lnk_barrier_overrides()` returns, or build it once per run in a shared schema.

No other real issues found. Checked:
- **The gate's SQL:** full-key joins; the overlay match against `fresh::frs_habitat_overlay`'s; count and update consistency; the per-species transaction; integer64 coercion of `count(*)`.
- **The log writes:** the second soft statement and column alignment through `.lnk_log_align_columns`.
- **Mapping codes:** `.lnk_mapping_code_persist`, which matches the removed recompute code and finds the long view and table that `lnk_persist_init(cfg$species)` creates.
- **Callers:** `lnk_pipeline_run` callers all pass named arguments.
- **Scripts and config:** the recompute's prior-table lifecycle (inside the function, so `on.exit` fires); the verify loop and its negative case (fails closed when no candidate is found); the RB row (the NA date floor becomes 1900-01-01 in `lnk_barrier_overrides`); and the config checksum, which matches the CSV's sha256.
