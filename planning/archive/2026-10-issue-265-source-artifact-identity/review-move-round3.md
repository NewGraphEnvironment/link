## Findings (round 3, commits dba635e6 / 28e288c5 / 22f0eae8)

### The mechanism

The record is stored **outside the thing it describes, and nothing ties their
lifetimes or contents**. `provenance.source_artifact` names a load of table T,
but T can be dropped, or dropped and re-created from something else, by a path
that never touches the record. Only one path keeps them in step:
`snapshot_bcfp.sh`, which `--clear`s this host's loader rows, loads, and then
records. Any other drop or replace leaves one of two divergent states:

- **A, the record outlives its table.** The record names a load the database no
  longer holds.
- **B, the table is replaced and the record is not.** The record names a
  different load from the one present, and `loaded_at` vouches for content it
  never saw.

(C, a table with no record, fails loud as `unstamped`, so it is not a hazard.)

Before the move, A and B were already possible for three of the four snapshot
primitives (`bcfishobs`, `cabd`, `whse_fish`) and for every FWA primitive,
because their records already lived in another schema. The move extends both
states to `fresh.modelled_stream_crossings`, the one primitive whose record used
to share a schema, and so a drop, with its table. 22f0eae8 handled state A in
one reader. Each place the mechanism reaches is enumerated below.

### Findings

- **[severity: fragile] R/lnk_log.R:716-760, `.lnk_log_inputs()`: the same
  state A as round 2, in the second reader, unfixed.** The artifact join is
  `LEFT JOIN provenance.source_artifact a ON a.table_name = p.tbl AND a.url = p.url AND a.host = ...`.
  Nothing in it refers to `c` (`pg_class` via `to_regclass`), so a record for a
  dropped table is copied into `<schema>.log_input.artifact_*`, with `row_count`
  and `size_bytes` NULL beside it.
  - **Reachability:** `lnk_pipeline_run()` calls `.lnk_log_inputs()` at run open
    (R/lnk_pipeline_run.R:167), before anything reads crossings. The vintage gate
    runs only from `study_area_run.sh` (`host_vintage.R`); `wsg_run_one.R` and
    the cypher path through `wsgs_run_pipeline.sh` do not run it.
  - **States that reach it:**
    1. A `state_clean.sh` full wipe whose step-5 snapshot dies before
       `--clear`. The prereq checks run first (snapshot_bcfp.sh:90-109), and
       state_clean does not check the snapshot's exit (bare `wait`).
    2. A scoped `--schemas=fresh` drop, which `wsgs_run_pipeline.sh
       --reset-schema --schema=fresh` issues to every cypher tofu reports. A
       later non-`--force` snapshot (cypher_prep.sh:251) can ledger-skip
       (snapshot_bcfp.sh:121), which leaves the table absent and the record in
       place.
  - **Harm:** the run fails when it reaches crossings, but its `log_input` rows
    persist. `schema_consolidate.R` carries them home before the cypher is
    burned, so the durable run log names an exact object version for a table
    the run could not read. This is the round-2 defect that was fixed in
    `lnk_artifact_read()` and left in its sibling, which is why it counts as
    unfixed.
  - **Fix (one clause):** add `AND c.oid IS NOT NULL` to the artifact join's
    `ON`, after the `pg_class` join, so an absent table gets NULL identity. A
    regression test that captures the SQL can assert the clause.

- **[severity: fragile, low] state B through a manual restore of the
  consolidate backup.** `schema_consolidate.R:117-123` runs
  `pg_dump --schema=<persist>`. For `--schema=fresh` that dump holds
  `fresh.modelled_stream_crossings`. Before the move it also held the record, so
  a `pg_restore --clean` of it restored table and record together and they
  stayed consistent. After the move the record is not in the dump.
  - Suppose a snapshot ran between the dump and the restore: a re-run, or a
    restore from an older `/tmp/fresh_pre_consolidate_*.dump`. The restored
    table is then the older crossings, while the loader row still names the
    newer version and `loaded_at`.
  - `lnk_preflight_vintage()` judges the table on that stamp, so it can pass
    content older than the window. `lnk_artifact_read()` reports `recorded`.
  - The path is manual and nothing automates the restore. It is still a new
    reach of the mechanism, and it fails toward pass.
  - **Cheapest detector:** the record already holds `n_rows`. A `recorded` row
    whose current count differs from `n_rows` could read `table_changed`, or the
    restore step could be documented as "re-run `snapshot_bcfp.sh --force`
    after". The FWA probe rows cannot use the count test, because a reload that
    keeps the row count is invisible to it, as already documented.

- **[severity: fragile, doc] RUNBOOK §6b's new sentence "`table_absent` ... the
  next snapshot clears it" holds only for a snapshot that runs.** A
  non-`--force` snapshot whose ledger row is current exits 0 before `--clear`
  and before any load (snapshot_bcfp.sh:121-125). It checks no table exists, so
  `table_absent` survives it. This is the scheduler's mode and cypher_prep's
  mode. The gate's own fix line names `--force`, so the operator is pointed
  correctly there. The RUNBOOK sentence should say `--force`.

### Enumeration

| place | holds / fails | why |
|---|---|---|
| `lnk_artifact_read()` (22f0eae8), state A | holds | `status = table_absent` via `.lnk_artifact_exists()` per expected table; `missing` takes precedence; version still shown. Verified by reading: pre-fix code returns `recorded`, so the new test goes red without the fix. |
| `lnk_artifact_read()`, state B | fails (low) | Reports `recorded` for a table replaced outside the snapshot; `n_rows` is available but not compared. Reachable by manual restore (finding 2). |
| `lnk_artifact_read()`, per-WSG stream rows | holds | The expected set comes from the groups loaded, and `merge(all.x = TRUE)` drops records for unloaded groups. |
| `.lnk_log_inputs()` (R/lnk_log.R), state A | **fails** | Join not conditioned on `c.oid`; copies identity for an absent table (finding 1). |
| `.lnk_log_inputs()`, state B | fails (low) | Copies the stale record's identity; same root as finding 2. |
| `.lnk_vintage_stamp()` / `lnk_preflight_vintage()`, state A | holds | An absent table is classed `absent` before stamps apply (`present <- setdiff(found, absent)`), so a stale stamp cannot pass a dropped table. |
| `lnk_preflight_vintage()`, state B | fails (low) | `loaded_at` of the newer load vouches for restored older content (finding 2). |
| `lnk_artifact_probe()` + upsert, probe row whose table is gone | holds | `.lnk_artifact_count()` gives `n_rows` NULL and a note. `t.n_rows IS DISTINCT FROM EXCLUDED.n_rows` lets the absent-time probe replace the old one, and a later probe after reload (NULL vs N) replaces it again. A probe never touches a loader row, so a loader row for a gone table stays: state A, handled by the readers above, except finding 1. |
| `lnk_artifact_record()` loader upsert | holds | A loader row always replaces; `artifact_record.R --clear` runs before any load. |
| `data-raw/artifact_record.R` | holds | `--clear` creates `provenance` itself, so it no longer depends on `fresh`. The manifest read-back runs right after the loads, so the tables exist. |
| `data-raw/host_vintage.R` | holds | Thin wrapper on `lnk_preflight_vintage()`; A fails loud. B as above. |
| `state_clean.sh` full mode | holds if the snapshot runs; A otherwise | A persists until a snapshot `--clear`s it. A failed step-5 snapshot is not detected (bare `wait`; this predates the move). Readers: `lnk_artifact_read()` and the gate hold, `.lnk_log_inputs()` fails. |
| `state_clean.sh --schemas=` scoped | A when `fresh` is listed | The script assumes "canonical fresh untouched", but `--schemas=fresh` drops `modelled_stream_crossings` and skips the snapshot. Before the move the record went with it (C, unstamped); now it is A. Same reader split. |
| `wsgs_run_pipeline.sh --reset-schema --schema=fresh` | holds on M4/M1; A possible on cyphers | M4/M1 run `snapshot --force` right after and fail on error. The scoped drop also reaches cyphers already in tofu; their later snapshot (cypher_prep, no `--force`) can ledger-skip. |
| Full-DB / disk-image restore (cypher warm image, volume restore) | holds | `provenance` and the tables are restored together and stay consistent. Rows are keyed by `host`, so a mismatched label reads as unstamped (C, fails loud). Same as before the move. |
| Schema-scoped restore (`pg_dump --schema=fresh` from consolidate) | fails (low) | The record is no longer in the dump (finding 2). An old pre-move dump restored now would also re-create an orphan `fresh.log_source_artifact`, which nothing reads, so that is harmless. |

### 22f0eae8 itself

- **Empty input:** `.lnk_artifact_exists(conn, character(0))` returns
  `logical(0)` (vapply), so `tbls[...]` is `character(0)`. The `expected` set is
  never empty, because the 11 non-`{wsg}` rows are always there, and `ifelse`
  over a 0-row frame is also fine.
- **Vectorisation:** `.lnk_artifact_exists()` returns one logical per input,
  unnamed, via `vapply`. That is one query per distinct table, 12 at most. The
  "one shape" test's mock was changed to `rep(FALSE, length(tables))`. The old
  scalar `FALSE` would also have worked, because a logical index recycles, so
  the change is correct but was not required.
- **The new test's mock:** `real_exists` is captured before
  `local_mocked_bindings()`, so it holds the original. The mock is vectorised
  (`e[tables == gone] <- FALSE`) and leaves the artifact-table and stream-table
  probes real. The test depends on the test DB holding
  `whse_basemapping.fwa_obstructions_sp`; it does here (`to_regclass` checked).
  On a DB without that table the `kept` assertion fails rather than skips. That
  is a fixture dependency, not a defect.
- **Not run:** the DB tests and a restore-the-bug mutation run, because both
  write to the DB, which this review was told not to do. The red-without-fix
  claim comes from reading the code: the old line is
  `ifelse(is.na(recorded_by), "missing", "recorded")`.
- **Live state:** local fwapg holds `provenance.source_artifact` with 4 loader
  and 253 probe rows, none with an absent table.
