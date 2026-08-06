# #127 — run provenance log on the persist schema

## Outcome

Shipped as v0.45.0. A network in `<persist_schema>` now says what produced it:
four sidecar tables mirroring `bcfishpass.log` and its `log_parameters_*` children
— `log` (one row per `lnk_pipeline_run()`), `log_parameters_fresh` and
`log_dimensions` (the **full** CSV rows, so `observation_species = BT;DV` at
threshold 1 with no date floor is recorded *in the database*, not as a pointer to
a file that will move on), and `log_input` (per-primitive fingerprints), read via
the new `lnk_log_read()`. This is what makes #236 tractable: scenario runs with
and without the DV override otherwise land in the same schema indistinguishable a
week later.

The issue was originally scoped as a single `persist_log` table carrying config
*name* plus package versions. Inventorying what can actually change between two
runs is what grew it — five categories, of which the config bundle was the only
one already covered (by git), and the DB primitives were covered by nothing at all.

## Three blockers found by pre-commit Plan-agent review

Each would have shipped a quiet defect:

1. **`run_id bigserial` breaks multi-host consolidation.** `schema_consolidate.R`
   COPYs literal values between hosts whose sequences both start at 1 → PK
   violation → the table lands in `errored_tables` and that source's entire run
   history is silently dropped. Fixed by `run_id text`, generated R-side as
   `<host>-<UTC ms>-<6 hex>`. It also avoids a `RETURNING` round-trip that would
   have broken the `.lnk_db_execute` mocking the tests depend on.
2. **`CREATE TABLE IF NOT EXISTS` can never ship a *new* config column** — and
   config columns are the entire point. Bundles already differ (bcfishpass's
   `dimensions.csv` has 30 columns to the `default*` bundles' 32), so a newly
   added parameter would have been silently never logged, reintroducing one layer
   up the exact silent drift the issue exists to prevent. Fixed by
   `.lnk_log_align_columns()` issuing `ALTER TABLE … ADD COLUMN IF NOT EXISTS` on
   every init.
3. **`config_hash` must hash the resolved file set, not the declared
   `provenance:` block** — `config.yaml` is absent from its own block, so a
   declared-set hash would be blind to `pipeline$schema`, `break_order` and
   `gradient_classes`, all of which change output. `config_drift` is kept as the
   separate "did it match what it claimed" axis.

## What the input-provenance investigation established

The most useful finding, and worth not re-deriving:

- **`bcdata.log` covers only `bc2pg` downloads** — the 4 `whse_fish.pscis_*`
  tables, cutblocks, fire polys. It has **zero** `whse_basemapping` rows.
- **FWA did not come from bcdata.** `fwa_stream_networks_sp` carries
  `wscode_ltree`/`localcode_ltree`, so it is the fwapg-*processed* layer, loaded
  by fwapg's own `load.sh` from
  `nrs.objectstore.gov.bc.ca/bchamp/fwapg/…parquet` out of a mounted checkout
  (`FWAPG_DIR`).
- Its `pg_stat_user_tables` row is entirely empty (`n_live_tup = 0`, every
  timestamp NULL — bulk-restored, never analyzed), so the `last_autoanalyze`
  load-date proxy that works for the other primitives **fails on the single most
  load-bearing input**.
- Therefore the only real version FWA has is the **fwapg checkout commit**,
  captured as `fwapg_sha`. Everything else records what exists and NULLs what
  doesn't — honest absence beats fabricated precision.

`last_autoanalyze` cross-checks convincingly where it is present:
`modelled_stream_crossings` 2026-05-26, and `wsg_outlet` 16:29 against the
16:28:50 `CREATE TABLE` recovered from a session transcript earlier the same day.

No `count(*)` anywhere: exact counts on a 4.9M-row / 9.8 GB table across a
246-WSG pass would add hours, so row counts are `reltuples` estimates flagged by
`row_count_estimated`.

## Design decisions worth keeping

- **`lnk_pipeline_run` owns the log, not `lnk_pipeline_persist`** — the latter is
  called *twice* per run (pre-persist and final), so anything appended there
  double-fires, and it has no access to `date_start` or the run args.
- **The open row is written before anything else**, because `wsg_upstream` has to
  reflect the cross-WSG state the run started from and the pre-persist mutates it.
  In link a WSG's downstream barrier tokens depend on which other WSGs were
  persisted first (RUNBOOK §5) — bcfp never has this problem, building the
  province in one shot.
- **`on.exit` + a `completed` flag, not `tryCatch`** — `tryCatch` unwinds the
  stack before the handler runs, destroying `traceback()` for a pipeline people
  debug interactively; `withCallingHandlers` would have meant reindenting a
  170-line body. Three lines, and `invisible(conn)` is preserved. The failure
  write is `try(silent)`-wrapped so a dropped connection cannot mask the original
  error.
- **Loud open, soft everything-after.** The open row costs nothing and runs in the
  first second, so a failure there means the schema is broken and is worth knowing
  before 80 minutes of modelling. Config snapshot, input fingerprints and the
  finish/fail updates all degrade to warnings — provenance must never kill a run.
- Result: a three-state completion signal — `date_end` set = success; NULL with
  notes = R error or interrupt; NULL without = SIGKILL / OOM / reboot.
- **Column lists are dictionary-driven** off #233's `dictionary_parameters_fresh.csv`
  and `dictionary_dimensions.csv`, verified to cover the union of all four bundles
  exactly. Adding a parameter updates the dictionary and the log table together.

## Verified live

Full PINE run against local fwapg, 4.2 min: `log` closed with
`species {BT,RB,GR}` and 52 upstream WSGs, `host m1` via `LNK_HOST_ALIAS`,
`link_dirty` correctly true against an uncommitted tree; 13 parameter rows and 13
dimension rows under one `config_hash`; all 12 primitives in `log_input` with
`source_at` populated only for `pscis_assessment_svw` and `fwa_obstacles_sp`
recording NULLs rather than erroring because it is not loaded here.

Suite 1452 pass. The one failure (`test-lnk_wsg_resolve.R:138`) is pre-existing
and tracked by #227.

## Incidental correction to #236

Verifying the smoke run disproved a claim this session had put on #236: we do
**not** model DV as its own species. DV has rows in the default bundle's
`dimensions.csv` and `parameters_fresh.csv` and presence flags in 194 WSGs, but
`lnk_rules_build()` skips it — `Skipping DV: no thresholds in fresh CSV` — because
fresh's `parameters_habitat_thresholds.csv` covers only BT, CH, CM, CO, GR, KO,
PK, RB, SK, ST, WCT. Same for CT. So `rules.yaml` has 11 species and no
`mapping_code_dv` column exists. #236 was corrected: modelling DV independently
needs a fresh-side threshold addition first; until then DV can only act as
*evidence* for BT's override, which `observation_species = BT;DV` already does.

## Left out of scope

`schema_consolidate.R` support for the two `config_hash`-keyed tables (they carry
no `watershed_group_code`, so the auto-discovery keyed on that column skips them —
they do not yet travel between hosts; needs live fleet time). Backfill is
impossible by design: absence of a `log` row means pre-provenance vintage, and a
synthetic row would be fabricated provenance — audit query in RUNBOOK §6b.
Teaching `snapshot_bcfp.sh` to stamp load events at load time would fill
`log_input.source_at`; the column ships now so that lands as an UPDATE rather
than a migration.

Closed by: commits `6f98cdd` → `c2e2afd` (v0.45.0) on
`127-run-provenance-log-on-persist-schema`.
