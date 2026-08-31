# #227 — single-WSG downstream-state guard

## Outcome

Shipped as v0.46.0. `data-raw/wsg_run_one.R` had stated the DS-first precondition in
its own header since #175 and **nothing enforced it**: accessibility is computed from
the *already-persisted* barriers of the WSGs downstream, so modelling out of order
writes `streams_access` / `streams_mapping_code` marking dammed-off segments accessible,
prints `done in N min`, and exits 0. New exported `lnk_wsg_downstream_check()` verifies
the precondition instead of trusting it.

## The finding that reshaped the issue

The issue proposed checking for **blocking dams in the downstream closure's WSGs** — a
*membership* test. Measured against the live DB, it cries wolf on the issue's own
motivating example:

| focal | membership | path | reality |
|---|---|---|---|
| **BULK** | fires — 18 dams across LSKE/KISP/KLUM | **0** | none below BULK's outlet |
| **PARS** | fires | **3** | Peace Canyon, Site C, W.A.C. Bennett — correct |
| SLOC | fires | 1 | Brilliant Dam — correct |

At that false-alarm rate operators reach for the override reflexively and the guard
stops meaning anything — the exact failure the issue's own "make or break" caveat
warns about, though it attributes the cause to edit-CSV fidelity rather than to the
predicate. The **path** form tests each dam with the measure-aware
`whse_basemapping.fwa_downstream()` from `fresh::frs_wsg_outlets()`. It is complete,
not merely cheaper: access walks downstream from every segment and every focal segment
exits through the focal outlet, so the out-of-WSG barriers reachable from *any* focal
segment are exactly those below the outlet. ~0.5 s against a 5 s budget.

`RUNBOOK.md` §8c carries the measurement precisely so nobody simplifies it back.

## Three further corrections to the issue body

- **Not `fwa_watershed_groups_poly`** for the proposed 2.4 s spatial join — its code
  columns are NULL on docker fwapg (#222). `watershed_group_code` comes from the snapped
  `fwa_stream_networks_sp` row, as `.lnk_pipeline_prep_dams` itself does. 8× faster too.
- **`.lnk_wsg_persisted()` is the wrong granularity** — it cannot distinguish a WSG
  persisted with `dams = FALSE`, which would pass a schema holding the streams but not
  the barriers. Persistence is checked per *dam* in `<persist>.barriers`.
- **"`study_area_run.sh` DS-first runs pass unchanged" is unachievable** by a hard
  pre-flight: on multi-host runs downstream groups are legitimately mid-flight on another
  cypher, and because per-WSG failures soft-fail the WSG would be **skipped** — which
  `lnk_access(merge = TRUE)` cannot repair. Strictly worse than the bug. Resolved with
  `warn` mode on both legs plus a post-condition in `wsg_recompute_one.R`, which is what
  makes the deferral honest rather than a hole.

## Anti-drift by construction

The guard must apply link's exact dam filters or it flags dams the pipeline treats as
passable. Rather than a second copy of the 25-line lateral snap with a comment asking
future readers to keep them in sync, the `cabd` and `matched` CTE bodies now live once
(`.lnk_dams_cabd_sql()` / `.lnk_dams_matched_sql()`) and are consumed by both
`.lnk_pipeline_prep_dams()` and the probe, parameterized on source — staged tables for
the pipeline, inline `(VALUES …)` for the guard, the pattern fresh 0.33.0 used to retire
`public.wsg_outlet`.

A golden capture was taken **before** the refactor and the result diffed against it:
byte-identical for ADMS (8 dams), KOTL (41) and PARS (0). Worth knowing: PARS has **0
dams in-WSG** — all three of its blocking dams are downstream in UPCE/PCEA, which is
exactly why the pre-flight exists.

## Defect found and fixed in passing

`.lnk_log_create_tables()` (shipped v0.45.0) built the run-log tables but never the
schema, so a brand-new persist schema failed with `schema does not exist`. The log is
opened before `lnk_persist_init` by design — the open row must predate any write so
`wsg_upstream` reflects the state the run started from — and every schema tested until
now already existed. Surfaced by running the guard's smoke tests into scratch schemas.

## Verified live, end to end

| case | result |
|---|---|
| typo'd `LNK_GUARD_DOWNSTREAM` | errors, names the valid values (a typo must not silently disable) |
| PARS, empty persist schema | **exit 1**, names all three dams + DS-first order |
| ADMS, brand-new schema | guard passes, models in 2.1 min, log row lands |
| override | proceeds; note reads `guard(override): 3 unmodelled downstream dam(s) — PCEA(1), UPCE(2) — Site C fishway operational, ref doc-123` |
| warn | proceeds; note reads `guard(warn): … at open` |

Suite 1513 pass, 0 failures. No new lint classes.

## Follow-up

**#244** — `cabd_additions` dams carry `barrier_ind = t` but the `usa` CTE hardcodes
`passability_status_code NULL` and the `barrier_status` CASE has no NULL arm, so Grand
Coulee / Chief Joseph can never become barriers (verified: 0 rows in `fresh.barriers`).
Left as a decision rather than fixed here — two of the three options change modelled
access in the Columbia and need a parity check. Pinned by a test either way, so any fix
is deliberate.

## Known bound

Inherits `frs_wsg_drainage()`'s one-outlet-per-group model. A WSG draining by two
independent paths would be under-covered. Recorded in RUNBOOK §8c.

Closed by: commits `3c593ab` → `225996f` (v0.46.0) on
`227-single-wsg-downstream-state-guard`.
