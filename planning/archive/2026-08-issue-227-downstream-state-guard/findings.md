# Findings — Single-WSG downstream-state guard (#227)

## Verified against live docker fwapg (2026-08-28)

### Membership vs path — the finding that reshapes the issue's design

The issue proposes flagging when the downstream *closure* contains WSGs holding
blocking dams. That is a membership test and it over-fires:

| focal | membership | path (dams below the outlet) | which |
|---|---|---|---|
| PARS | fires | **3** | Peace Canyon@UPCE, Site C@UPCE, Bennett@PCEA |
| BULK | fires (18 across LSKE/KISP/KLUM) | 1 | Dasque Creek@LSKE |
| SLOC | fires | 1 | Brilliant Dam@KOTL |
| KOTL | fires | 0 | — |

PARS surfacing exactly the three Peace dams matches RUNBOOK section 5's documented
case, so the path predicate is correct.

**Method caution:** my first attempt picked outlets with `nlevel(wscode_ltree) ASC`
and returned 0 for PARS — wrong, because that is the deprecated heuristic RUNBOOK
section 8b now warns about. The correct source is `fresh::frs_wsg_outlets()`
(246 rows: watershed_group_code, blue_line_key, downstream_route_measure,
wscode_ltree, localcode_ltree) with the 8-arg measure-aware
`whse_basemapping.fwa_downstream(blk_a, drm_a, ws_a, lc_a, blk_b, drm_b, ws_b, lc_b)`.

## The dam path

`.lnk_pipeline_prep_dams(conn, conn_tunnel, aoi, schema, loaded)` —
`R/lnk_pipeline_prepare.R:750-907`.

- **`conn_tunnel` is a misnomer.** Every caller passes the *local* conn
  (`lnk_pipeline_run.R:169` `conn_tunnel = if (dams) conn else NULL`). `cabd.dams` is
  loaded locally by `snapshot_bcfp.sh` (2,594 rows). Zero tunnel dependency.
- Writes 6 tables, then `DELETE FROM <schema>.dams WHERE watershed_group_code <> aoi`
  (L896-899). Cannot answer the guard's question — it deletes exactly the rows needed —
  and needs a working schema that does not exist at pre-flight time.
- Edit CSVs in the `cabd` CTE: `cabd_exclusions` (anti-join on cabd_id),
  `cabd_blkey_xref` (constrains the snap), `cabd_passability_status_updates`
  (COALESCE over psc), `cabd_additions` (separate `usa` CTE, UNION ALL).
- Snap: `CROSS JOIN LATERAL` nearest stream, `ST_Distance <= 65`,
  `DISTINCT ON (c.dam_id)`, excludes `wscode_ltree <@ '999'`.

### "Blocking" needs three filters that live DOWNSTREAM of prep_dams

1. `passability_status_code IN (1,2)` → `barrier_status IN ('BARRIER','POTENTIAL')`
   (CASE at `lnk_crossings_union.R:164-171`). NULL is **not** blocking.
2. `INNER JOIN fwa_stream_networks_sp` on `linear_feature_id`
   (`lnk_crossings_union.R:188-189`).
3. `blue_line_key = watershed_key` — mainstem only (`lnk_barriers_emit.R:126`,
   `lnk_barriers_unify.R:201`).

### cabd_additions dams are structurally non-blocking

The `usa` CTE hardcodes `NULL::integer AS passability_status_code`, and the CASE has no
NULL arm, so Grand Coulee / Chief Joseph can never become barriers despite
`barrier_ind = t` in the CSV. Verified: 0 rows in `fresh.barriers` matching `^12000`.
The guard must mirror this. Latent bug -> separate issue (Phase 5).

## Integration points

- `wsg_run_one.R`: guard slots between L53 and L55. `conn`/`cfg`/`loaded`/`wsg` all in
  scope. The #157 species skip (L45-53) is the precedent; it uses `quit(status = 0)`.
  There is no `quit(status = 1)` in the repo today.
- `lnk_wsg_resolve(cfg, loaded, wsgs, expand = TRUE, conn)` returns the DS-first closure,
  **species-filtered**. A dam in a species-less WSG is never persisted as a barrier, so
  demanding it is an unfixable false alarm — intersect.
- `.lnk_wsg_persisted_all(conn, cfg)` (`R/utils.R:212-262`) — all persisted WSGs in one
  round trip. Use for the "not yet in <persist>.streams" message line only; dam-level
  presence is the real test.
- `notes` exists on `lnk_pipeline_run()` (L109-117) -> `.lnk_log_run_start()` ->
  `<schema>.log.notes`. `.lnk_log_run_fail()` appends via `concat_ws`, so the note
  survives a later crash. `wsg_upstream text[]` independently records what was persisted
  at open, so an override is provable from two directions.
- `wsg_run_one.R` currently passes **neither** `notes` nor `run_label`.

## The study_area_run.sh tension

Buckets are drainage-closed and DS-first per host, but the script documents (L272-290)
that downstream barriers can be **cross-bucket** on multi-host runs, remedied by an
unconditional post-consolidate `lnk_access(merge = TRUE)` recompute.

A hard pre-flight there is not merely noisy — per-WSG failures soft-fail with
`|| echo "[WARN] ..."`, so a blocked WSG is **skipped entirely**, and the recompute
cannot repair a WSG that was never modelled. That is strictly worse than the bug.
Hence `warn` mode + a post-condition in `wsg_recompute_one.R`.

## Test patterns

- `skip_if_no_db()` — `tests/testthat/setup.R:19-45`, tries local docker then
  `lnk_db_conn()`, verifies write permission.
- `local_mocked_bindings(.lnk_db_execute = ...)` for SQL capture;
  `with_mocked_bindings(dbGetQuery=, dbQuoteLiteral=, .package = "DBI")` for probes;
  `fake_conn <- structure(list(), class = "DBIConnection")`.
- **The guard's mock needs four branches**, not two: `information_schema`,
  `WITH RECURSIVE` (`.lnk_wsg_persisted_all`), `fwa_downstream` (the probe), and
  `barrier_source` (persistence). Every one of these mentions `watershed_group_code`,
  so a single regex mis-routes.
