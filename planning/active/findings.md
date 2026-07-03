# Findings — accessible_km segmentation-frontier fix (#223)

## Root cause (from research/accessible_km_divergence.md + code trace 2026-07-03)

The BT/ST `accessible_km` over-credit is a **segmentation** defect, not an
access-decision defect. At co-located segment positions link and bcfp agree on BT
accessibility at 99.99% (`link_only` = link-acc & bcfp-blocked = 0 km). The gap is
that link's streams don't break at the per-species gradient/falls barriers, so one
segment straddles the frontier and the whole reach is credited accessible.

## The code path

1. `R/lnk_pipeline_run.R:216-224` — access set `barriers_<sp>_access` passed to
   `lnk_pipeline_access()`. Correct — holds the frontier barrier.
2. `R/lnk_pipeline_prepare.R:566-594` builds `barriers_<model>` = class-filtered
   `gradient_barriers_raw` ∪ falls, then `:592` runs `frs_barriers_minimal()`, and
   `:637-651` unions results into `gradient_barriers_minimal` (the break source).
3. `fresh/R/frs_barriers_minimal.R:114-134` — DELETEs every barrier with another
   downstream on the same flow path (keeps downstream-most). Correct for a decision,
   wrong as a segmentation source.
4. `R/lnk_pipeline_access.R:155-165` / `:356` / `:364` — a segment is blocked only if a
   barrier sits downstream of its downstream route measure. A straddling segment has
   its measure below the barrier → labelled accessible.

## Why the fix is safe + isolated

- `frs_barriers_minimal` used **once** in link (`prepare.R:592`).
- `gradient_barriers_minimal` consumed **only** by `lnk_pipeline_break.R:110`.
- `barriers_<sp>_access` built independently by `lnk_barriers_unify` +
  `lnk_barriers_views.R:171` (anti-join over unified post-override barriers) — does not
  touch `gradient_barriers_minimal` / `_min`.

## Decisive evidence — blk 359209845 (FINA, BT)

| set | count on blk | frontier 3834.78? |
|---|---|---|
| `working_fina.barriers_bt` (pre-minimal) | 16 | yes |
| `gradient_barriers_minimal` (via `_min`) | 0 | no |
| `barriers_bt_access` (decision) | 16 | yes |

`frs_barriers_minimal` pruned all 16 tributary barriers because two BT barriers on the
parent mainstem blk 359572348 (measures 1684183.02 / 1706109.93) are downstream of the
confluence per `fwa_upstream()` — but those parents are overridden OUT of
`barriers_bt_access`, so the segmentation frontier and access frontier disagree.

Result: link `[3391,7998]` = 4607 m accessible (whole); bcfp `[3391,3835]` 444 m
accessible + `[3835,7998]` **4163 m blocked**. Over-credit = 4163 m on this one blk.
Aggregate: FINA +1438 km, PCEA +2021 km, PARS +238 km.

## bcfp reference identity

Tunnel-free `fresh.streams_vw_bcfp`: `smnorris/bcfishpass@v0.7.15-41-g2917790`
(head_sha 29177906, date_completed 2026-07-01), `db/model/model_access_bt.sql`.

## Encodings / gotchas

- `access_<sp>` int: −9 absent / 0 blocked / 1 modelled / 2 observed. accessible = IN(1,2).
- bcfp predicate: `barriers_<group>_dnstr = ''` (empty string, char varying — NOT text[]).
- gradient_class: link ×10000 (0.25→2500), bcfp ×100 (0.25→25).
- #203: join persisted `fresh.*` on full PK `(id_segment, watershed_group_code)`.
- Cross-DB: :5432 (link/fresh) and :63333 (bcfp tunnel, intermittent) — no direct join.
  accessible_km stays tunnel-free via `fresh.streams_vw_bcfp` on :5432.
