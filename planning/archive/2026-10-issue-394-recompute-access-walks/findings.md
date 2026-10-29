# Findings: Recompute: test existence instead of building natural-barrier arrays, and walk each barrier set once (#394)

## Issue context

**If we do it:** the recompute stops building arrays it throws away, and stops walking the same barrier set up to seven times a group; the output-bound groups that NewGraphEnvironment/fresh#272's prefilter barely helps (SETN 1.2×) get faster too. **If we never do:** after NewGraphEnvironment/fresh#272 the recompute's remaining cost sits in those groups and in repeated walks, and the next provincial run pays it.

Found by #261 (`research/recompute_cost.md`), not measured there.

## Two levers in link's natural-barrier walks

1. **Ask whether a barrier lies downstream, not which.** `lnk_pipeline_access()` reduces each natural view's arrays to `has_barriers_<sp>_dnstr` (only the anthropogenic and remediation arrays' first element is read). Building full arrays is what makes SETN output-bound: 4.83 M (segment, feature) pairs for its CH walk and a 526 MiB sort spill to disk. An existence test per segment (an `EXISTS` on the same `fwa_downstream()` predicate, or a fresh option on `frs_network_features()`) returns the same booleans without the pairs.
2. **Walk each distinct barrier set once.** Before overrides, the natural set has three shapes province-wide: CH = CM = CO = GR = KO = PK = SK (7.24 M rows), BT = DV = RB (3.48 M), ST = WCT (5.36 M). CHWK walks five identical CH-shaped views (161,974 pairs each). Overrides differ per species, so walk the un-overridden shape once and apply each species' overrides after, or walk once per distinct overridden set.

## Order against NewGraphEnvironment/fresh#272

Not a code dependency; a measuring one, and the two touch the same walks. Lever 1 written as link's own `EXISTS` on `fwa_downstream()` would leave `frs_network_features()`, so fresh#272's prefilter would no longer reach those walks and the `EXISTS` would need the same prefilter; written as an existence option on `frs_network_features()`, it inherits it. The anthropogenic and remediation walks (`dam_dnstr_ind`) and the observation walk keep using `frs_network_features()` either way. Lever 2 (each distinct set walked once) is link-only and can be built independently; measure it on top of fresh#272's release, as #377 orders.

## How to measure

Re-run `data-raw/logs/recompute_cost_261/walk_prefilter.R`'s pattern: the current walk against the changed one on SALR, CHWK, SETN and LFRA, with `has_barriers_<sp>_dnstr` compared per segment (must be identical), after NewGraphEnvironment/fresh#272 lands so the gain is measured on top of it.

Tracked on #377.



## Found at the plan gate (2026-10-28)

- fresh v0.47.0 (2026-10-29 UTC) ships `result = "exists"` (fresh#281, PR #283): `SELECT DISTINCT` segment ids over the array walk's own join, 1.00x (SALR) to 1.24x (SETN) faster end to end; a correlated EXISTS was slower. So lever 1 is a link-side argument.
- `lnk_pipeline_access()` reduces per-species and `pscis` results to `id %in% result$id`; `anthropogenic` + `dams` arrays feed `dam_dnstr_ind`, `remediations` feeds `remediated_dnstr_ind`, the observation walk feeds species codes. The returned tibble carries no barrier arrays.
- Each species has its own `barriers_<sp>_access` view, so the per-table cache never hits across species.
- `fresh_default.barriers` on m1: 7.7 M rows, 7.4 GB; `barrier_overrides` 44 k rows. A province-wide fingerprint per job is too dear, and in early mode (#374) the table changes during the run.
- m1 has fresh 0.44.0 installed (RemoteSha 22034c1a), so the `base044` baseline runs before the install.
- The #261 scripts set `default_transaction_read_only = on`; fresh >= 0.45 creates temp tables, so they cannot be reused as is.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `load_all()` of the branch refuses while the shared library holds fresh 0.44.0 (the floor is 0.47.0), and the baseline needs 0.44.0 there | fresh v0.47.0 installed into a scratch library (`R CMD INSTALL -l <scratch>/lib047` from a worktree at the tag, `2c35e3eb`); 0.47.0 variants run with `R_LIBS=<scratch>/lib047`, so the shared library stays at 0.44.0 until the end and the variants can be interleaved |

## Another client on m1's database (2026-10-29 03:05 UTC on)

A client reaching m1's postgres through an ssh tunnel from another tailnet host runs short `frs_network_features()` array walks over `barriers_*_access` views in bursts (sampled 24 × 5 s: active in 9). It is not this session and not the wet duckdb job on m1. measure.R refuses beside it, so the variants run with `--allow-busy`, interleaved per group, with the other backends counted at each walk (`walks.tsv`, `other_backends`) and per run (`other_backends_max`).

## A live recompute on m1, and my collision with it (2026-10-29 03:05–03:14 UTC)

The other client (through the ssh tunnel) is recomputing on `fresh_default`: `zz_lnk_access_prior_setn` and `zz_lnk_streams_setn` are its tables, and the plan review saw it run a habitat-gate `UPDATE`. measure.R called `lnk_access()`, which drops and recreates `zz_lnk_streams_<aoi>`, the same name a live recompute of that group uses. The round was stopped before it reached SETN. Killing the R client left its backend walking my `zz_lnk_streams_chwk` (CHWK BT); `pg_terminate_backend` was refused by the auto-mode classifier, the walk ended on its own within two minutes, and I dropped the table. measure.R now uses its own `zz394_streams_<aoi>`, a `lock_timeout`, and drops its tables on exit. The SALR rows taken before the change are kept as `measure_round0.tsv` / `walks_round0.tsv` (the `lnk_access()` path; all six digests identical: 27.6 / 26.4 s at `base044`, 3.7 / 3.7 at `prefilter`, 3.7 / 3.7 at `exists`).
