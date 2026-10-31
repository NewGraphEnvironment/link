# Code check, round 2: branch 402-screen-fish-records (ba5fef36...e5433d83; fixes 2e531774..e5433d83)

## Checklist read
- code-check.md: every H3 under `## Mechanisms` read as prose, tables skipped. I read these in full: "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", "Zero-length, empty, and unset are three different things" and "One fact derived twice". I skimmed the rest of the section.
- code-check-r.md: "`system2(stdout = TRUE)` warns on a non-zero exit instead of raising…", "Cross-function consistency for label/string normalization", "Postgres row order is never fixed unless the query fixes it…" and "A `data-raw/` script must load the source tree…". Other headings were not read, because nothing in the diff touches them.
- code-check-spatial.md: "The BC WFS caps an un-paged `GetFeature` at 10,000 features…" (the zones read returned 19,094 rows, so it is past the cap). Other headings not read.
- code-check-shell.md: none read. The diff has no shell code.

## How it was checked
- **Re-run:** I re-ran `.lnk_presence_measures()` from the worktree against local fwapg, read-only with temp tables only. The cell rollup reproduces the committed `measures.csv` exactly: all 6,111 cells, with 0 differences on `n_counting`, `n_sites`, `n_waterbodies`, `n_hist_zone`, `n_above_barrier`, `n_ko_no_lake`, `n_main_stem` and `n_code_other_group`. `test-lnk_presence_measures.R` passes 42/42 (`NOT_CRAN=true`).
- **Numbers reproduced against the committed outputs or the database:**
  - Recall (`recall.csv`): 36 / 21 / 10 / 6 / 46 / 21; own code 67 of 67; zoned 49.
  - Absent-recorded cells: 121 on one waterbody and 94 on one site, out of 327.
  - Anadromous cells: 168 in all; 12 with every record above a barrier, 6 of them with at most 2 above; 21 on a main stem only; 59 with no zoned record; 11 / 7 / 3 Columbia / Mackenzie / Yukon, by drainage code.
  - KO: 137 / 123 / 0 / 15, and 3,374 / 42 / 15 of 140.
  - Stories: 319 of 351 carry measures, and the other 32 are 24 + 8 BT.
  - In SQL: 2,574 records (counted over all records, not counting ones) and 179,815 species-locations.
- **Both round-1 examples:** KTSU CM now reads 14 waterbodies; LPCE WCT still reads 1 (see finding 3).

## Findings

- **[severity: fragile]** data-raw/wsg_species_presence_check.R:172-222 (the recount of the measures), and every claim built on it. The comment says the recount reads bcfishobs and FWA "rather than from the measures' own tables" and writes each test "another way". So do the 3ef7be22 commit message, `task_plan.md:43` ("it no longer reads the measures' own tables"), the stamp, and the README's "SQL recount of the measures … all agree". Three things are not as described:
  - **(a) The zones come from the measures' own table.** `n_hist_zone` reads `pg_temp.pm_zones`, the table `.lnk_presence_measures()` wrote after folding the cutthroat aliases in R. Round 1's defect 2 (the zone fold) would still pass this recount. Read `evidence/hist_zones.csv` again and fold it in the SQL, or join a raw copy.
  - **(b) The main stem is the same predicate.** `max(s.upstream_route_measure) … IS NOT NULL` runs over the same WHERE as the measure's `EXISTS` (same `blue_line_key`, `watershed_group_code <>`, `downstream_route_measure >`). That is the same predicate, not "the line reaching higher outside the group than inside it", and it cannot disagree with the measure's definition.
  - **(c) Most measures are not recounted.** Only 7 columns are checked. `n_waterbodies`, the measure round 1 found wrong, is not recounted at all, and neither are `n_years`, `n_lake_records`, `n_known_sockeye_lake`, `n_ko_no_lake`, `min_class_above` / `max_class_above`, the elevations or `barriers_known`.
  - Only the barrier test is a genuinely different formulation. "All agree" therefore vouches for less than the README and stamp say.
  - The same mechanism reaches finding 2: the recount would not have caught it either.
  - **Rule:** code-check.md "Verification that reads its own output"

- **[severity: bug]** R/lnk_presence_measures.R:126. `'lake:' || o.waterbody_identifier` is NULL for the 52 lake records that have no `waterbody_identifier`. `ndist()` drops NA, so those records count toward no waterbody instead of falling through to the 50k code or the blue line.
  - In the committed `measures.csv`, MFRA LDC reads `n_waterbodies = 0` on 1 counting record.
  - LFRA CH, CT, PK and SK, NARC PK, VICT CO, HARR LDC and TABR LDC also each hold such records, so each can read 1 too few.
  - No flagged cell's story is affected today. The fix introduced this: the old column was the raw identifier, and the new CASE never tests it for NULL.
  - Fix: `WHEN o.waterbody_type = 'Lake' AND o.waterbody_identifier IS NOT NULL`.
  - **Rule:** code-check.md "Zero-length, empty, and unset are three different things"

- **[severity: fragile]** R/lnk_presence_measures.R:43-46 and :126-129 (roxygen and the CASE); also CLAUDE.md:26 ("every stream and wetland record in a group one shared `waterbody_identifier`"), research/species_presence.md:93 and RUNBOOK. The premise is false for wetlands.
  - Wetland records carry their own identifiers: 2,298 records, 245 distinct ids, none of the form `00000<group>`, and 59 groups with more than one wetland id. Only stream records share `00000<group>` (229,336 of 235,036).
  - The code keys wetlands by the 50k code anyway. Keying them by their own id would change `n_waterbodies` in 144 of the 6,111 cells of `measures.csv`. None of these is among the 121 single-waterbody flagged cells.
  - Separately, the 50k code is the source's location code, not the stream the record sits on. Some records carry a main river's code (`230-000000-…`, the Peace, which trims to `code:23`) while bcfishobs places them on other lines. LPCE WCT, the example round 1 cited, still reads "35 sites on 1 waterbody": its 50 records lie on 14 blue lines (Peace, Pine, unnamed). Of the 121 "rests on a single waterbody" cells, 10 have records on more than one blue line. 5 of those are KO on one lake, which is legitimate. 5 are not: LCHL PK, LPCE KO, LPCE WCT, NAKR PK and NASR PK.
  - The headline "121 rest on one waterbody" is the number the operator's lone-record decision reads. Either key wetlands by their id and say the 50k code is the source's code (which can be a main stem's), or report the blue-line count beside it.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** data-raw/wsg_species_presence_check.R:66-69 (the `code_dirty` stamp guard). It fails toward clean in three ways:
  - **(a) Untracked files.** `--untracked-files=no` hides a new untracked file under `R/`, and `load_all()` loads it. That is the round-1 situation: new code that had not been committed.
  - **(b) A git failure reads as clean.** If git fails (not a repo, or a cwd other than the root with an absolute `--out`), `system2(stdout = TRUE)` returns `character(0)` and only warns. Its `status` attribute is never read.
  - **(c) Data inputs are not covered.** Only `R/` and two drivers are watched. Uncommitted edits to inputs that change these outputs (`observation_exclusions.csv`, `parameters_fresh.csv`, `dfo_known_sockeye_lakes.csv`, the presence CSV, `wsg_regions.csv`, all under `inst/extdata/`) leave the stamp reading as if the named commit produced the outputs.
  - Fix: drop `--untracked-files=no` (or use `normal`), check `attr(code_dirty, "status")`, and add `inst/extdata`.
  - **Rule:** code-check.md "A guard that fails toward pass"; code-check-r.md "`system2(stdout = TRUE)` warns on a non-zero exit instead of raising, so a `tryCatch(error =)` around it never fires"

/Users/airvine/Projects/repo/link/planning/active/review-round2.md
