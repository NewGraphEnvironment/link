# Plan review — #404 (Plan agent, 2026-10-28, on baseline `00dce074`)

Findings as returned, most severe first; the disposition of each is in `progress.md`.

- **Blocker (replace key):** `record_built()` keeps `!(variant == v & wsg == w)`; copied to the timing file that would delete a pair's earlier step rows and the base rows keyed on `variant = default`. → Write once per (variant, wsg) after the group; key the replace on (variant, wsg, step).
- **Gap (`t0` window):** the base-pass digest compare, `record_built()` (four sha256 digests + a `built.csv` rewrite) and the planned `n_segments` / `uptime` / CSV write would sit inside the total untimed. → Take `total` right after step 7, then query and write; name `record_built` or document it as the residual. `lnk_persist_init()` runs once per variant outside `t0`: give it a row (wsg NA, `in_total = FALSE`).
- **Ordering:** the dirty check covers the script, so Phase 2 must be committed (and on the branch the worktree checks out) before any build; `--allow-dirty` would stamp the run dirty.
- **Gap (base rows on resume):** `run_base()` `next`s before `t0` for a resumed group, so "17 `base_model` rows" fails on a retried base. → "one per group modelled in this run".
- **Assumption (`write_bundle` self-check):** `write_thresholds()` must reproduce `default`'s thresholds CSV byte for byte; the file changed at `1ae0c34f` (#364) after the last build. → Run `--step=bundles` first thing. Everything else in `write_bundle()` is fine for `bt_rear_wet_p10`.
- **Acceptance (fresh#275):** `classify` / `connect` rows wrap link's entry points (`frs_params()` + `frs_habitat_classify()`; `.frs_run_connectivity`, cluster plus connected waterbody), not `frs_cluster()` alone. → Say so in the README and the comment.
- **Scope (statement depth):** `PGOPTIONS` reaches the R session only, but the container log holds every session's statements. → Filter by `pg_backend_pid()` printed at launch.
- **Acceptance (shared database):** the issue's Environment list names it; the load average alone does not record it. → `pg_stat_activity` snapshot at launch and end.

Checked and fine: a fresh `--out` after `--step=base` holds everything the variants pass reads; `score404_` / `working_score404_` collide with nothing on the host; `n_segments` from the base schema's `streams` is right for both passes; the `default` pass runs steps 1, 2, 3 and 7 only; the acceptance boxes map to Phases 3–5.
