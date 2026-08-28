# Task: Single-WSG downstream-state guard (#227)

`data-raw/wsg_run_one.R` states its precondition in its own header — run a drainage
DS-first so downstream dam barriers are already persisted — and **nothing enforces it**.
Accessibility is not computed from the focal WSG alone: link reads the *already-persisted*
barriers of downstream WSGs. Run against an empty or partial persist schema and the access
query finds no downstream dams, concludes nothing blocks, writes `streams_access` /
`streams_mapping_code` marking segments accessible that are in fact dammed off, prints
`done in N min`, and **exits 0**. A wrong answer indistinguishable from a right one.

The `public.wsg_outlet` half of #227 closed via fresh 0.33.0 (#238). This is the rest.

## The correction that shapes the design

The issue proposes checking for **blocking dams in the downstream closure's WSGs** — a
*membership* test. Verified against the live DB, it cries wolf:

| focal | membership | **path** (dams actually below the outlet) |
|---|---|---|
| **PARS** | fires | **3 — Peace Canyon, Site C, W.A.C. Bennett** ✓ |
| **BULK** | fires (18 across LSKE/KISP/KLUM) | 1 |
| SLOC | fires | 1 — Brilliant Dam ✓ |
| KOTL | fires | 0 |

Use the **path** predicate: test each dam with measure-aware
`whse_basemapping.fwa_downstream()` from the focal outlet (`fresh::frs_wsg_outlets()`).
Same cost (~0.3 s). Defensible on link's own semantics — access walks downstream from
every segment, and every focal segment exits through the focal outlet.

Two further corrections to the issue body:
- **Not `fwa_watershed_groups_poly`** — its code columns are NULL on docker fwapg (#222).
  Take `watershed_group_code` from the snapped `fwa_stream_networks_sp` row.
- **`.lnk_wsg_persisted()` is the wrong granularity** — cannot distinguish a WSG persisted
  with `dams = FALSE`. Use dam-level presence in `<persist>.barriers`.

## Decisions (user-approved)

- **Multi-host:** `warn` mode + post-condition. A hard pre-flight would make blocked WSGs
  **skip** (per-WSG soft-fail), and the recompute cannot repair a WSG never modelled —
  strictly worse than the bug.
- **Anti-drift:** extract shared snap SQL used by *both* `prep_dams` and the guard.
  Golden regression test on `prep_dams` **first**.

## Phase 0 — Regression net (blocking)

- [x] Golden test for current `.lnk_pipeline_prep_dams` (row count + `dam_id` set + psc
      distribution for one dam-bearing WSG)
- [x] Confirm `DESCRIPTION` pins `fresh (>= 0.33.0)`
- [x] Absence policy: missing `fwa_downstream` ⇒ `stop()`, never auto-pass

## Phase 1 — Factor the dam-snap SQL (no behaviour change)

- [x] `.lnk_dams_matched_sql()` — lateral-snap CTE, verbatim
- [x] `.lnk_dams_cabd_sql(dams_expr, excl_ref, xref_ref, upd_ref)` — parameterized source
- [x] `.lnk_dams_edit_values_sql(conn, loaded)` — VALUES fragments, `dbQuoteLiteral`, typed
      NULL sentinel for empty CSVs
- [x] Rewrite `.lnk_pipeline_prep_dams` step 3 to compose from builders
- [x] Tests: golden still passes; DDL retains `CROSS JOIN LATERAL` / `<= 65` /
      `DISTINCT ON (c.dam_id)` / `UNION ALL`; VALUES escapes a `'`

## Phase 2 — Probe + guard

- [x] `.lnk_dams_blocking_downstream(conn, aoi, loaded, outlets)` — one read-only query
- [x] `.lnk_barriers_cabd_persisted(conn, cfg, dam_ids)` — dam-level presence
- [x] `lnk_wsg_downstream_check(conn, aoi, cfg, loaded, on_fail, override, outlets)` —
      exported, `@family wsg`; intersect with species-filtered closure; `setdiff` not
      positional slicing; `override = ""` errors
- [x] Tests: arg validation; empty override errors; mocked `dbGetQuery` with **four**
      branches (`information_schema`, `WITH RECURSIVE`, `fwa_downstream`, `barrier_source`);
      all four statuses; message names the dam
- [x] Live: PARS fails naming 3 dams; **BULK passes** (anti-cry-wolf); elapsed < 5 s
- [x] Live anti-drift: `prep_dams` blocking subset == guard probe for the same WSG

## Phase 3 — Script integration

- [x] `wsg_run_one.R`: read `LNK_GUARD_DOWNSTREAM` (default `error`, unrecognised value
      errors) + `LNK_GUARD_DOWNSTREAM_NOTE`; call guard; `quit(status = 1)` on fail;
      thread `notes = guard$note`
- [x] `study_area_run.sh`: export `LNK_GUARD_DOWNSTREAM=warn` on the dispatcher leg **and
      inside the ssh string**
- [x] Update header contract + the L272-290 comment block

## Phase 4 — Post-condition

- [x] `wsg_recompute_one.R`: re-run guard with `on_fail = "error"` after consolidate —
      what makes Phase 3's `warn` a deferral rather than a hole

## Phase 5 — Docs, release, follow-up

- [ ] `RUNBOOK.md` §8c — membership ≠ path, with the BULK counterexample; note the
      single-outlet-per-group bound
- [ ] `RUNBOOK.md` §6b — `guard(...)` note strings
- [ ] `NEWS.md` + `DESCRIPTION` bump (final commit); `CLAUDE.md` status
- [ ] File follow-up: `cabd_additions` psc NULL ⇒ US placeholder dams structurally never
      barriers (0 rows in `fresh.barriers`)

## Validation

- [ ] `devtools::test()` green; `lintr::lint_package()` no new lint classes
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` then `/gh-pr-push`
