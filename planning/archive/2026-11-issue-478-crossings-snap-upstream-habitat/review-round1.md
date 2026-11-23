# Code-check round 1: branch 478 (HEAD 2abbba35, base 5be4fb32)

## Checklist read

- **code-check.md** (38 H3): read the prose of every H3 under `## Mechanisms` through
  "A wrapper's exit is not the work" and the start of "Zero-length, empty, and unset are three
  different things" (rows skipped). Not read: the rest of "Zero-length…", "The probe is broken
  before the world is", "Written data outlives the fix", "Serialization loses meaning silently",
  "One fact derived twice", and the H3s under `## Rules that stand alone`, Security and
  Spreadsheets (about 24 not read in full; their index lines were read).
- **code-check-r.md** (130 H3): read in full "A value compared as `::text` in SQL has
  PostgreSQL's spelling, not R's", "Postgres row order is never fixed unless the query fixes
  it…", "An `information_schema` lookup by the literal table name misses what Postgres
  resolves". 127 not read in full (index lines read).
- **code-check-spatial.md** (96 H3): read in full "FWA `upstream_route_measure` misses the next
  segment's start", "A relation between FWA watershed codes is not a place". 94 not read in full.
- **code-check-shell.md** (73 H3): none read in full (run.sh is a measurement driver; index
  lines read). 73 not read in full.

## Findings

- **[severity: bug]** R/lnk_aggregate.R:568-598 (`.lnk_aggregate_barrier_pairs()`), and the
  subtraction in `.lnk_aggregate_species()` — two barriers within 1 m of each other on one
  stream are each "upstream" of the other, so the `EXCEPT` removes both from every point's
  immediate-barrier set.
  `fwa_upstream(..., true, 1)` between two points counts b as upstream of a whenever
  `b.m >= a.m - 1` on the same blue line, so the relation is symmetric for any pair under 1 m
  apart. `lnk_agg_up` then holds (a,b) and (b,a), and for any point P below both, the `EXCEPT`
  removes (P,b2) through mid = b1 and (P,b1) through mid = b2. Results:
  (1) each barrier of the pair gets `*_belowupstrbarriers_km` = its total minus the other's
  total, i.e. 0 for the downstream one and 0 (or negative, if the downstream one's 1 m window
  catches a segment the upper one's does not) for the upstream one; (2) every crossing below the
  pair with no other barrier between keeps everything above the pair in its below-barrier total
  (nothing is subtracted).
  Measured in the committed parity CSV: BULK 197902 (PSCIS, 43 m) and 1001800360 (modelled,
  43.54 m) on blue line 360742836 both have `link_rearing_below` 0 against bcfishpass 1.996 and
  1.96 km (BT and ST, `data-raw/logs/crossings_upstream_478/per_crossing.csv`); local
  `working_bulk.barriers_anthropogenic` holds exactly this one pair under 1 m. Reproduced at HEAD
  in a scratch schema (`zz_test_rev478`, dropped): with crossing X at 10 m and the two barriers at
  43 / 43.54 m, X's `spawning_belowupstrbarriers_km` = 2.754665 = its full total (should be ~0),
  and both barriers' = 0 (the upper one should be ~2.75). The roxygen ("barriers upstream of it
  that have no other barrier between it and them") and the research file's explanation of the
  BULK below-barrier excess (attributed only to other groups' barriers) do not hold for this
  case. Fix direction: break the symmetry (e.g. treat a pair within the tolerance as ordered by
  measure, or use strict `false, 1`/measure ordering for the barrier-to-barrier relation).
  - **Rule:** none

- **[severity: fragile]** research/bcfishpass_parity.md (new section, first bullet under
  "Habitat upstream of each crossing") — "in ADMS every metric rounds to 100 %, with no crossing
  more than 2.1 km apart except in sockeye spawning (12.8 km at most)" is contradicted by
  `distribution.csv`: ADMS PK spawning `max_abs_diff_km` 8.318 and PK spawning_below 8.32. The
  quantifier ("no crossing … except sockeye") omits pink. (The next bullet mentions pink totals,
  but the per-crossing claim is still false as written.)
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** research/crossing_snap.md, "The re-model, main against the branch",
  Barriers bullet — "LILL gains one" is not what `compare_bcfishpass.csv` shows: LILL barriers
  are 63,218 before and 63,218 after, with 1 before-only and 1 after-only row (a replacement, net
  zero). Only the after-only row (10702238 at 356248078 / 64.14 m) is the one the next bullet
  explains.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** data-raw/logs/snap_tie_478/snap_pick.R:77 (stamp) vs
  research/crossing_snap.md header and "What moved, province-wide" — both committed
  `before/counts.csv` and `after/counts.csv` record `src_sha` 9b126d4f (the parked PWF baseline),
  while the research file says the runs were "at main (`5be4fb32`) and at the branch"
  (`2b12adf0`). The "after" counts (0 placeholder candidates) can only have come from an
  uncommitted tree at 9b126d4f, and the script records HEAD with no dirty flag, so the evidence
  does not show which code produced "after". Either re-run from a clean `2b12adf0` checkout or
  record the dirty state and correct the header.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** R/lnk_points_snap.R:123-146 — the new `id_col` existence check reads
  `information_schema.columns` with the literal schema and table text. For a session temp table
  (`pg_temp.<name>`; information_schema lists it under `pg_temp_N`) or a mixed-case/quoted name,
  `in_cols` is empty and the function now refuses with "id_col '…' is not a column of …", where
  before it snapped (the collision check was vacuous but harmless). `lnk_points_snap()` is
  exported; the pipeline's own caller passes `whse_fish.pscis_assessment_svw`, which works, so
  this bites only external callers. Ask the table itself (`SELECT * FROM <tbl> LIMIT 0`) or
  resolve through `'<tbl>'::regclass`.
  - **Rule:** code-check-r.md "An `information_schema` lookup by the literal table name misses what Postgres resolves"

## Checked and found sound (not findings)

- `lnk_points_snap()` wrapper: frs_point_snap(to=) columns, id join, rank ordering, scratch table
  dropped via `on.exit` inside the function, `exclude_edge_types = integer(0)` handled by fresh's
  guard, placeholder guard `NOT wscode <@ '999'`.
- PSCIS pick: `snap_at_segment_end` / `segment_downstream_route_measure` are non-NULL on every
  `pscis_streams_150m` row; the xref INSERT lists columns explicitly, so the new columns are NULL
  there and nothing positional breaks; no other reader of the intermediate tables.
- Dam snap ORDER BY: `cabd.dams.geom` is POINT, so `ST_LineLocatePoint` cannot error.
- `EXCEPT` vs the earlier `NOT EXISTS`: equivalent (the dropped `mid.bar_id <> u.bar_id` term is
  implied by `b.pt_id <> a.pt_id`).
- `lnk_aggregate()` ref join: no crossing in working_adms / bulk / lfra / hors falls in FWA's mm
  gap between segments (0 of 16,421), so the `[ds, us)` join loses none there.
- Crossings parity numbers in NEWS / research (9,173 both, 19 / 8 one-sided, 42 dams, 4 off
  stream or >1 m) match `crossings_parity_232/*.csv`; snap counts (14 picks, 8 / 3 / 3, 17,363,
  17 dams < 1 mm, sweep 22→14, 581→21) match `snap_tie_478/*.csv`.
- No host names, ports, private paths or credentials in committed logs; reference DB connection
  from `LNK_REF_PG*` only.
- Threshold scripts' `ORDER BY` ordinals are unique within each query.
