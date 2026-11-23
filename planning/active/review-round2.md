# Code-check round 2 (#478), branch head a47bb402

## Checklist read

- **code-check.md:** the prose of every H3 under `## Mechanisms` (table rows skipped), read in full for "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output" and "A guard's scope, escape hatches, and remedies"; the other nine mechanism headings read from the index line only. The 21 non-mechanism headings were not read in full.
- **code-check-r.md:** read in full: "Postgres row order is never fixed unless the query fixes it…" and "An `information_schema` lookup by the literal table name misses what Postgres resolves". Checked against their index lines: "A `data-raw/` script must load the source tree…", "`on.exit()` at a script's top level never fires", "A database driver's value is not a base R type…", "Under `R CMD check`, tests run from a temp dir…", "A `pkg::` call in a test…", "`sort()` and `order()` collate by `LC_COLLATE`…" and "`system2(stdout = TRUE)` warns on a non-zero exit…". About 185 headings were not read.
- **code-check-shell.md:** checked against their index lines for `run.sh`: "A failed `cd` lets every later command run in the directory you were already in", "Quoting" and "`&` binds to the whole `&&` list…". About 115 headings were not read.
- **code-check-spatial.md:** checked against their index lines: "FWA `upstream_route_measure` misses the next segment's start", "A relation between FWA watershed codes is not a place" and "FWA main flow is not edge type 1000 alone". About 145 headings were not read.

## What was verified (no finding)

- **The 1 m barrier fix (`.lnk_aggregate_barrier_pairs`) is correct.** I read the database's 11-argument `fwa_upstream`. On one blue line with equivalents it is `b > a OR abs(a - b) <= tol`, so two points are each upstream of the other exactly when `|diff| <= 1`, which is the fix's test. Across blue lines, being upstream of each other is impossible: the distributary exclusion and the localcode ordering prevent it.
  - On a three-barrier chain within 1 m, and on a crossing that is not a barrier with a barrier just below it, the EXCEPT now leaves the lowest barrier as the only immediate one. Before the fix, a barrier within 1 m below a crossing was counted as "upstream" of it, which could make that crossing's below-barrier total negative.
  - The test goes red on the old code: the mutual pair made the EXCEPT drop both barriers, so `spawning_belowupstrbarriers_km[1]` came out equal to the total.
- **The `lnk_points_snap()` lookup through `to_regclass` + `pg_attribute` resolves as the FROM does.** The id check and the two `FROM`s use the same case and pg_temp resolution, and a table that is missing is refused.
- **Tests run in the review copy (NOT_CRAN=true): all pass.**

  | test file | result |
  |---|---|
  | `test-lnk_aggregate.R` | 22 pass |
  | `test-lnk_points_snap.R` | 64 pass |
  | `test-lnk_pipeline_pscis_build.R` | 49 pass |
  | `test-lnk_wsg_downstream_check.R` | 62 pass |
  | `test-lnk_preflight_fresh.R` | 43 pass |
  | `test-lnk_vocabulary.R` | 82 pass |
  | `test-lnk_fwapg_gate.R` | 3 pass, 3 skip (no migration) |

- **Numbers checked against the committed CSVs, all correct:**
  - NEWS and research:
    - 98–100 % (the lowest is 5425/5537 = 97.98 %);
    - ADMS within 2.1 km, with SK 12.8 and PK 8.3 as the exceptions;
    - totals within 1.5 %;
    - BT rearing below 36,331 against 34,483;
    - 1.2 and 1.3 minutes;
    - 9,145 and 9,173 crossings;
    - 19 / 8 on one side only, 42 CABD, 4 not within 1 m.
  - crossing_snap.md:
    - the before/after table (37,992→37,972; 20→0; 17,377→17,369; 11→0; 305; 33; 2,554);
    - 14 picks (8 dropped, 3 to a stream, 3 by measure);
    - 17,363 unchanged;
    - 17 dams;
    - the 10 pick groups, and the 13 dam groups (queried from the after lfids);
    - KETL, JERV and LILL's barrier rows.
- **The pretest map** covers `frs_point_snap.R`'s helpers (`utils.R` is `any`). No hard-coded `-2` tokens remain in code. I found no host names, addresses or private references in the new scripts or logs.

## Findings

- **[severity: bug]** research/crossing_snap.md:45 — "one row moves in each of GUIC, SHUL and USHU (a dam on the segment starting at its vertex, under 1 mm of measure)" is wrong for SHUL.
  - No moved dam lies in SHUL. The 13 groups of `dams_moved.csv`'s `lfid_after` segments are BULK, BULL, FRAN, GUIC, HORS, KNIG, LARL, LNIC, NICL, OKAN, SQAM, USHU and VICT.
  - SHUL's moved barrier row is PSCIS 3703 (one of the three 1 m pick moves in `picks_moved.csv`). A diff of `zz478_build_{before,after}_bcfishpass.barriers` gives `PSCIS SHUL 356136396 63.0000` before only and `64.0000` after only, and the after row has `id_barrier` 3703.
  - So the sentence should say that GUIC and USHU each move a dam by under 1 mm, and that SHUL moves PSCIS 3703 by 1 m to the segment starting at its vertex.
  - **Rule:** code-check.md "Verification that reads its own output"

- **[severity: bug]** research/bcfishpass_parity.md:57 — "Three (8733, 8745, 8758) are crossings bcfishpass placed from PSCIS where link keeps the modelled crossing 3 to 6 m away": the range is wrong.
  - From `crossings_parity_rows.csv`: 8758 is at 559 m on blue line 360856432, and link's modelled crossing 1001804827 on that line is at 556.77 m, which is 2.2 m apart.
  - The other two: 8745 at 2972 against 1024704538 at 2969.12 (2.9 m), and 8733 at 1889 against 1001803546 at 1894.64 (5.6 m).
  - The range is 2 to 6 m.
  - **Rule:** code-check.md "Verification that reads its own output"
