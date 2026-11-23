# Code-check round 3 (#478), branch head a5acaa56

## Checklist read

- **code-check.md**: under `## Mechanisms`, read in full the prose of "A guard that fails toward pass", "A fixture that cannot reach the failure mode" and "A proxy is not the property". Read the opening paragraphs of the other eleven H3s ("Verification that reads its own output", "A guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that share a harness", "Restore the bug and prove the guard fires", and the rest). Table rows and evidence blocks skipped. Did not read the 30-odd H3s under `## Rules that stand alone`, `## Security` or `## Spreadsheets and PDFs`, apart from their index lines.
- **code-check-spatial.md**: read "FWA `upstream_route_measure` misses the next segment's start" and "A relation between FWA watershed codes is not a place". Did not read the other ~100 headings beyond their index lines.
- **code-check-r.md**: read "Postgres row order is never fixed unless the query fixes it…", "An `information_schema` lookup by the literal table name misses what Postgres resolves" and "`on.exit()` at a script's top level never fires". Did not read the other ~150 headings beyond their index lines.
- **code-check-shell.md**: index only (run.sh is the only shell in the diff). Did not read any of its ~110 headings in full.

## The mechanism behind rounds 1 and 2

Every earlier finding came from a value written down from a picture of the system instead of being read from the artifact:

- fwa_upstream was assumed to be antisymmetric, and with its 1 m tolerance it is not;
- the snap input's columns were looked up by the name as spelled, not resolved the way the snap's `FROM` resolves it;
- a stamp recorded HEAD instead of the code that ran;
- research sentences were written from memory of a run, not from its CSV.

The same assumption reaches the FWA data itself. The code assumes `[downstream_route_measure, upstream_route_measure)` splits a blue line into segments that do not overlap, so every point falls in exactly one segment. That is false: in ADMS and BULK alone, 14,124 segment starts lie below the previous segment's `upstream_route_measure`. Findings 1 to 3 below are instances of this mechanism. Finding 4 is a guard scoped narrower than what it protects.

## Findings

- **[severity: bug]** R/lnk_aggregate.R:209 (the `fresh::frs_aggregate()` call), and the `ra`/`rb` joins at :343. **A point in an FWA overlap is summed twice.**
  - `frs_aggregate()` resolves each point's codes with `JOIN fwa_stream_networks_sp ref ON blk AND m >= ref.downstream_route_measure AND m < ref.upstream_route_measure`, then sums `GROUP BY p.pt_id`.
  - Where the next FWA segment starts before the previous one ends (`upstream_route_measure` overshoots, the spatial rule's 1 mm to 1 cm), a point sitting at that start matches two `ref` rows. Every feature upstream of both rows is then joined and summed twice.
  - **Measured.** 2 of the 9,192 ADMS and BULK crossings match two `ref` rows (`1000100373`, `1000103592`), as does 1 of ADMS's `barriers_anthropogenic`. Province-wide, 225 rows of `fresh.modelled_stream_crossings` do.
  - **Probe.** I ran the branch's `lnk_aggregate()` on a scratch copy of `zz478_parity.streams`, with every segment marked BT spawning (`zz_test_r3overlap`, since dropped). It returned:
    - `1000100373`: 0.2753 km, against 0.1376 km of distinct upstream segments, exactly double (both `ref` rows share one code pair);
    - `1000103592`: 3.120 km against 1.852 km (14 joined rows for 8 segments; the two `ref` rows differ in local code).
  - The parity run did not see it, because those two crossings have no habitat upstream in this build.
  - **What it breaks.** For any crossing at an overlap with habitat upstream, the totals are inflated. A barrier at an overlap has its total doubled, and that doubled total is then subtracted from every crossing whose immediate upstream barrier it is. Their `*_belowupstrbarriers_km` comes out too low, and can go negative; the test's `>= 0` check covers only its own fixture.
  - **Where to fix it.** Resolve each point to one segment before the walk: the one starting at or below the point with the highest `downstream_route_measure`, which matches the tie rule this branch adopts. bcfishpass carries codes on the crossing and has no such join. The double count happens inside fresh's `ref` join, so it is fresh's to fix as well (surface it there). The `ra`/`rb` joins in `.lnk_aggregate_barrier_pairs()` have the same shape; they are harmless only because the `EXCEPT` deduplicates.
  - **Rule:** code-check-spatial.md, "FWA `upstream_route_measure` misses the next segment's start"

- **[severity: fragile]** research/crossing_snap.md:35. **"8 now have no pick (no other candidate passes the scores)" is not what happened.**
  - Each of the 8 dropped PSCIS (1632, 1646, 2718, 3329, 8120, 63502, 69319, 123540) had exactly one candidate at main, and it was the placeholder (`zz478_before.pscis_stream_candidates`: n = 1 and n999 = 1 for each).
  - At the branch they have no candidate within 150 m at all: 0 rows in `zz478_after.pscis_stream_candidates` and in `pscis_streams_150m`. No score was applied.
  - This is the same mechanism as round 2's prose findings: a reason inferred from how the pick works, not read from the tables.
  - Suggested wording: "8 now have no pick: the placeholder was their only stream within 150 m".
  - **Rule:** none

- **[severity: fragile]** research/bcfishpass_parity.md:67. **The cost line names the wrong workload.**
  - "1.2 minutes on ADMS and 1.3 on BULK (3,608 and 5,537 main-stem crossings)": 3,608 and 5,537 are the main-stem crossings both sides hold, the parity subset (`distribution.csv`).
  - `lnk_aggregate()` ran over every crossing in `working_<wsg>.crossings`: 3,615 and 5,577 (`defect_*.csv` `n_crossings`; `stamp.csv` `n_link_crossings` 9,192), plus the barriers as points.
  - **Rule:** none

- **[severity: fragile]** R/lnk_aggregate.R:121 with :227. **The `to` guard does not cover the tables the function reads.**
  - It refuses `to` equal to `crossings` or `barriers`.
  - It does not refuse `<schema>.streams` or `<schema>.streams_habitat_<sp>`, which the function reads. After the walk, `DROP TABLE IF EXISTS <to>` at :227 would drop that persist table and recreate it as the output, destroying a provincial build's rows.
  - fresh's `frs_point_snap()` guards the same case for the network table it reads.
  - Add `paste0(schema, ".streams")` and each `paste0(schema, ".streams_habitat_", tolower(species))` to the refused set.
  - **Rule:** code-check.md, "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** data-raw/logs/crossings_upstream_478/parity.R:121. **The parity stamp still has no dirty flag.**
  - It records `link_sha` (7175014f) without the dirty flag that round 1 added to `snap_pick.R` and that `crossings_parity.R` carries. It ran seconds before a47bb402 was committed, so whether `R/` was clean when `lnk_aggregate()` was loaded is not recorded.
  - `defect.R` records nothing about the main worktree it loads (sha or dirty).
  - Round 1's stamp fix landed in one of three sibling measurement scripts.
  - **Rule:** code-check.md, "A fix lands in one of two callers that share a harness"

## Where the mechanism reaches in this diff, each place checked

**Assuming one FWA segment holds each point:**

| place | verdict |
|---|---|
| `frs_aggregate()` `ref` join, through `lnk_aggregate()` | bug (finding 1) |
| `.lnk_aggregate_barrier_pairs()` `ra`/`rb` | duplicate rows, deduplicated by `EXCEPT`: harmless |
| `compare_builds.R` `moved_pos` (closed interval) and `explain()` (`LIMIT 1`) | used only for `EXISTS`: harmless |
| the gap case (`upstream_route_measure` below the next start) | 0 of 9,192 crossings match no segment, because a point at a segment start falls in the next segment |
| `lnk_aggregate()` docs | name the stream-top case only |

**Prose against the committed CSVs and scratch schemas, re-derived:**

- **research/bcfishpass_parity.md, crossings.** 9,173 both; status agrees on all; all but 4 on the same stream within 1 m; 27 one-sided (19 and 8); 42 CABD; 15 and 1 modelled; 2 on another stream and 1 at 1.6 m; PSCIS 7 and 4; pairs 198104/198113 and 198105/198114; 123530/123529 20 m apart; 8733, 8745 and 8758 at 5.6, 2.9 and 2.2 m; 199455 at 3 m. All ok.
- **research/bcfishpass_parity.md, per crossing.** 9,145; 98 to 100 %; ADMS maxima 2.04, 12.79 (SK) and 8.32 (PK); totals within 1.5 % for spawning and rearing, with the listed exceptions; BT below 36,331 against 34,483; defect figures. All ok.
- **research/bcfishpass_parity.md, cost line.** Wrong workload (finding 3). 15.4 and 91.5 minutes have no committed producer; not verified.
- **research/crossing_snap.md.** Table (37,992/37,972, 20/0, 17,377/17,369, 11/0, 305, 33, 2,554) ok. 14/11/3/3 and the named ids ok. The reason for the 8 is wrong (finding 2). 17,363 unchanged and 1.6e-10 m ok. 17 dams on the same stream, under 1 mm, and their 13 groups ok (DB). 50 dam ties, 49 on one stream and 1 across two: ok (recomputed from `cabd.dams`). Pick groups ok. Re-model barrier, segment and LILL claims, including 63445's fifth candidate changing streams, ok. Sweep table ok. Gate tests "3 skip, 3 pass" ok (ran the file). "10 of 14 in FWA's gap" and "17,656 segments (7,892 km)" have no committed producer; not verified.
- **NEWS.md.** Every figure matches the above.
- **RUNBOOK.md.** "11 provincial PSCIS picks" ok.

**Stamps:**

| script | verdict |
|---|---|
| `snap_pick.R` | sha and dirty |
| `crossings_parity.R` | sha and dirty (of the reading script; the build sha is in `zz478_parity.log`, 2b12adf0, clean) |
| `run.sh` | prints sha and dirty |
| `parity.R` | sha only (finding 5) |
| `defect.R` | nothing (finding 5) |
| `zz478_build_*` and `zz478_parity` log rows | 2b12adf0, `link_dirty` f |

**Catalog lookups by spelled name:** `lnk_points_snap()` now resolves through `to_regclass` (ok). The `species` discovery in `lnk_aggregate()` uses `information_schema` with a lower-case `schema` that the validator enforces (ok). `compare_builds.R` uses literal lower-case scratch schema names (ok).

**Row order:** the `ORDER BY` in both threshold scripts ends on the full group key; `lnk_aggregate()` output orders on `(species_code, id)`; the pick and dam-snap orders end on unique keys. All ok.

**Public-repo hygiene:** no host names, tunnel ports, home paths or private repo references in the added lines or in the new log directories.
