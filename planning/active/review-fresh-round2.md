# Code-check round 2: fresh branch `order-child-width-gradient` (vs origin/main, HEAD e863155)

## Checklist read
- code-check-infra.md (38,115 B): in full.
- code-check.md (330,698 B): prose of every H3 under `## Mechanisms` (all 14, table rows skipped); plus standalone "Bare `y`, `n`, `on`, `off`, `yes`, `no` are booleans in YAML 1.1". The other standalone, Security and Spreadsheets/PDF headings were not read (none names a tool or shape this diff uses).
- code-check-r.md (178,405 B): read "R's `yaml` returns a mixed int/float sequence…", "Tests that silently do not run", "A `skip_if_not()` skips only its own `test_that()` block", "A `function(...)` mock hides arguments…", "`sprintf("%g", x)` writes `Inf` and `NA` into SQL…", "`$` on a list partial-matches…", "testthat counts an uncaught error under `error`…" (7); the rest (~120) not read in full, index lines checked.
- code-check-shell.md (125,440 B): no heading names a tool this diff uses (no shell); 0 read in full, index checked.
- code-check-spatial.md (155,517 B): read "FWA main flow is not edge type 1000 alone" and "FWA `upstream_route_measure` misses the next segment's start" (2); rest index only.

## What was run
- Copied the branch to a scratch dir; `NOT_CRAN=true` `testthat::test_file()` on test-frs_order_child.R (12 blocks, 0 failed, 0 error, live block NOT skipped: 3 expectations ran) and test-frs_params.R (new blocks 91, 92 pass).
- Mutations on the copy, counting `failed > 0 | error`: `<` -> `<=` in the width clause: 2 red blocks; gradient clause removed: 2 red; `v < 0` check removed: 1 red. The new guards are tested. (`IS NOT NULL` is redundant with `<` under SQL NULL semantics, so its removal cannot redden anything; harmless.)
- Read bcfishpass `@7f444f1b` `load_habitat_linear_{bt,ch,co,st,wct}.sql`, all three rearing blocks each, and `model/01_access/sql/load_streams.sql`.
- Probed local `fresh.streams` (ADMS, BULK, ELKR, BABL) for exception-eligible lines (order 1, parent >= 5, width < 1.5, gradient <= 0.1049).

## Verified true
- The quoted predicate and the cite `load_habitat_linear_bt.sql:88-97` match the file at 7f444f1b.
- `NULL <= max` excludes NULL widths, and the gradient test sits outside the cw/mad branches, in all three rearing blocks of all five species.
- The exception sits inside the `cw` branch only in all five files (so "a `mad` group never takes it" holds for BT, CH, CO, ST, WCT).
- Every exception row in bcfishpass also needs spawning on the segment (block 1) or connectivity to spawning (blocks 2, 3): true in all five.
- Rd matches roxygen; the validator change and its tests are correct (`~` -> NULL accepted, string/int/length-2 refused).

## Findings

- **[fragile: doc false by omission]** R/frs_order_child.R:43-48 (and man/frs_order_child.Rd, same paragraph) — "Two of bcfishpass's conditions are the caller's, not this function's" presents the caller-owned list as complete, and it is not for four of the five species. In CH, CO, ST and WCT every rearing block that carries the exception also restricts rows by waterbody / edge type: CH and WCT block 1 `wb.waterbody_type = 'R' OR (wb.waterbody_type IS NULL AND s.edge_type IN (1000,1100,2000,2300))` (`load_habitat_linear_ch.sql:88-94`, `_wct.sql:88-94`), ST `... IS NULL OR edge_type IN (...)` (`_st.sql:88-92`, 138-142, 229-233), CO the same with 1050/1150 added (`_co.sql:88-94`). BT's rearing blocks have no such filter. `frs_order_child()` tests no edge or waterbody type, so it admits order-1 direct children that sit in lake or wetland polygons (edge 1200 / 1050 / 1400 / 1450 with waterbody L or W, or 1410 with none) that bcfishpass would not rear for those species. Measured in local `fresh.streams` over ADMS, BULK, ELKR, BABL at BT's bounds: 60 of 276 eligible direct-child segments (~7 of 62 km) are such lines (1450/R 23, 1200/L 12, 1050/W 8, 1200/W 7, 1410/none 6, ...). Either say the waterbody/edge-type filter is also the caller's (species-specific: CH/CO/ST/WCT, not BT), or say the list is not exhaustive. The caller (link) needs this to know whether its CH/CO/ST/WCT exception matches bcfishpass.

- **[fragile: doc false, pre-existing but now contradicted in the same block]** R/frs_order_child.R:153-158 (Rd examples) — the example still reads "Reproduce bcfishpass exactly: direct children of order-5+ rivers, no distance cap, for BT/CH/CO/ST/WCT" with no `channel_width_lt` / `gradient_max`. The branch's own new paragraph (lines 39-41) now says that call admits "every direct child … whatever its width or gradient", which bcfishpass does not. It is also not exact for a second, pre-existing reason the new paragraph does not list: bcfishpass's exception has no `stream_order = stream_order_max` test (its `stream_order_parent` is per `blue_line_key`, `load_streams.sql` join on `fwa_stream_networks_order_parent`; the rearing SQL never reads `stream_order_max`), so it admits order-1 headwater reaches of higher-order BLKs that drain to an order-5+ river; fresh excludes them by design (fresh#158). In the same four groups that is 173 segments / ~57 km beside the 62 km fresh admits. Since round 1's fix was about over-claimed parity, the "exactly" example and the default-call parity framing (also the test name "default emits canonical bcfishpass-parity SQL", test file line 34) remain the over-claim. Reword the example (e.g. "bcfishpass's order and parent tests") and, if the paragraph is meant to enumerate divergences, add the `stream_order_max` one beside the caller-owned conditions.

No bugs found in the code, the validator or the tests; the tests can fail (mutation table above).
