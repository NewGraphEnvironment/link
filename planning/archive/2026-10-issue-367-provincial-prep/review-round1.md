# Code-check round 1: #367 branch (base 67a410e2 to HEAD 4bdb7cc9)

## Checklist read

- **code-check.md:** I read the prose of all 14 H3s under `## Mechanisms`, skipping the `|` table rows. I read none of the 27 headings under "Rules that stand alone", Security, or Spreadsheets and PDFs; none of them matches a tool or shape this diff uses.
- **code-check-r.md:** I read 7 headings in full:
  - "Postgres row order is never fixed unless the query fixes it…"
  - "A database driver's value is not a base R type"
  - "A value compared as `::text` in SQL has PostgreSQL's spelling"
  - "`sprintf("%g", x)` writes `Inf` and `NA` into SQL…"
  - "An `information_schema` lookup by the literal table name…"
  - "`$` on a list partial-matches…"
  - "`deparse(body(f))` excludes formal defaults…" and "`deparse()` re-encodes non-ASCII…"

  I did not read the other roughly 115.
- **code-check-shell.md:** I read none of its roughly 100 headings. The diff has no shell code; the RUNBOOK prose is not code.
- **code-check-spatial.md:** I read 2 headings: "FWA `upstream_route_measure` misses the next segment's start" and "A Freshwater Atlas main stem's downstream end…". I did not read the other roughly 120.

## Clean

No issues found.

## What I checked (evidence, not findings)

All database work was on the local fwapg database, in the scratch schemas `zz_cc_r1_a` and `zz_cc_r1_b`. Both are dropped. The repo was not touched: R ran from an rsync copy in the scratchpad.

- **Step 3b against bcfishpass's `nearest` UPDATE (`02_pscis_streams_150m.sql`, which uses `a.id != n.id`).**
  - Input: a copy of `working_score364_bulk.pscis_streams_150m` (41,456 rows), with a row id added. I applied both variants and then the pick, with `.lnk_pscis_pick_order`.
  - Result: the 17,377 picks are identical in `(linear_feature_id, modelled_crossing_id, downstream_route_measure)` for every PSCIS crossing.
- **The KNN snap with the secondary key** (`ORDER BY str.geom <-> c.geom, str.linear_feature_id LIMIT 1` in `.lnk_dams_matched_sql()`).
  - This inner query has no `ST_DWithin` bound, so it depends on the index scan for its speed.
  - On PG 17.5 it plans as a GiST index scan with an Incremental Sort, presorted on the distance; 200 dams take 45 ms. It is not a full sort.
- **`prep_dams` for LARL under `default`** (run from the copy):
  - It writes `1200000002` to `1200000004` with `passability_status_code` 1.
  - The staged `barrier_ind` is text `'t'`, which the CASE matches.
  - The `placed` / `usa` UNION type-resolves: `downstream_route_measure` is integer in the staged CSV and double in `placed`.
- **The guard with `additions = TRUE`:** KOTL, UARL and CLRH each report `1200000002` (LARL). LARL and KETL report no placeholder, because each holds its own.
- **Id collision:** `fresh.modelled_stream_crossings` has a maximum `modelled_crossing_id` of 24,764,034. Offset by 1e9 for crossings, that stays far below the 1,200,000,001 to 1,200,000,005 placeholder range.

## Notes (not defects)

- **One comment in Step 3b is not accurate:** `R/lnk_pipeline_pscis_build.R:264-265` says `(stream_crossing_id, linear_feature_id, modelled_crossing_id)` identifies a row.
  - That is not true in general. Step 2's `LEFT JOIN whse_basemapping.fwa_rivers_poly r ON str.waterbody_key = r.waterbody_key` fans a candidate out once per river polygon. There are 84 duplicated triplets in the BULK-built table (Pine River, PSCIS 6943 and 7195; Murray Creek, PSCIS 199179, three copies).
  - The copies are byte-identical, because `r` is only tested for `waterbody_key IS NOT NULL`. So link's `IS DISTINCT FROM` keeps every copy of a winning row, where bcfishpass's id test nulls all but one (24 rows differ after the UPDATE).
  - The pick is unaffected: 0 differences, as measured above.
  - Worth rewording only if the comment is later used to argue equivalence somewhere else.

/Users/airvine/Projects/repo/link/planning/active/review-round1.md
