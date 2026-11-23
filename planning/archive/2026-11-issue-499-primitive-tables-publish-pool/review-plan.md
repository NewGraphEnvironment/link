# Plan review: #499 (backlog move 14), 2026-11-22

Blockers raised: 1
Owner forks: 0

A synchronous `Plan` agent reviewed `task_plan.md` against #499, #494, #488 and #334 and the code they name. Each finding was probed before folding: the duckdb connection in the refusal gate (`R/lnk_publish.R:69`), `parallel` missing from `Imports`, the `pretest_inputs.csv` mappings (`:3`, `:93`), no version reads in `R/lnk_scenario_export.R`, and the local fwapg not answering on 5432 were each confirmed by grep or `pg_isready`. The review raised no new owner fork. Two findings reworded existing Open decisions (1 and 4).

| # | kind | finding | verdict |
|---|---|---|---|
| 1 | Blocker | Publishing the same root twice to one scratch prefix skips every file and per-group part already there (`habitat_publish.R:198-208`, `:228-233`), so the second run times nothing | Folded: two prefixes (`serial/`, `parallel/`), compare across them; `s3:DeleteObjectVersion` named in Open decision 4 |
| 2 | Gap | Pool mechanism and how a failure reaches R are unnamed; `mclapply` forks after duckdb has loaded; `parallel` is not in `Imports` | Folded: PSOCK cluster, every result checked before the manifest, `parallel` into `Imports` |
| 3 | Assumption | The put reply as JSON is fragile (`aws()` merges stderr; no `--output`) | Folded: `--query '[VersionId,ETag]' --output text`, refuse an empty, `None` or `null` VersionId |
| 4 | Gap | `list-object-versions` returns old versions and delete markers | Folded: `list-objects-v2` for existence and ETag; `list-object-versions` filtered to `IsLatest`, delete markers excluded, scoped to the per-group prefixes |
| 5 | Assumption | Whether `OGR_TRUNCATE` or `-overwrite` alone moves `geom` is unshown | Folded: Phase 1 loads twice without `OGR_TRUNCATE` and records which setting moves it |
| 6 | Gap | The proof omits column types (the export snapshot records `format_type`) and `ogc_fid` range; a saved GeoJSON's layer is not `OGRGeoJSON`; `cabd_load()` needs table arguments, a `DO` block for bash 3.2, and a committed fixture | Folded into Phase 1 |
| 7 | Assumption | ogr2ogr's drop may cascade over dependent views | Folded: plain `DROP` (fails loudly), `pg_depend` checked, §8d says so; the `CASCADE` behaviour itself was not confirmed by the reviewer and is not relied on |
| 8 | Assumption | The local fwapg was down at review | Folded: Phase 1 starts it first |
| 9 | Assumption | "Every recorded md5 stays valid" under decision 1a holds only while CABD returns the same features | Folded: Open decision 1a reworded to say what it buys |
| 10 | Gap | A stub `aws` timing with `date +%N` fails on macOS | Folded: stub in R or Python, a lock directory to count in-flight puts |
| 11 | Scope | Helpers in the existing `R/lnk_publish.R` (mapped `none`); leave `R/lnk_artifact.R` alone (mapped `any`); "R/ and data-raw/ changed" overstated the gate; `R/lnk_scenario_export.R` has no version reads | Folded into "Decided at the gate" and Owed |
| 12 | Acceptance | #488's measurement needs a full built root on this host, and a laptop ratio is not the cloud host's 53.5 min; the PR closes #494 and #488 and only references #334 | Folded into Phase 2 and Phase 3 |

## Files the plan names

data-raw/snapshot_bcfp.sh
data-raw/snapshot_bcfp_lib.sh
data-raw/habitat_publish.R
data-raw/pretest.R
data-raw/pretest_inputs.csv
data-raw/state_clean.sh
R/lnk_publish.R
R/lnk_artifact.R
R/lnk_export_inputs.R
R/lnk_downstream.R
tests/testthat/test-snapshot_bcfp_lib.R
tests/testthat/test-lnk_publish.R
tests/testthat/test-pretest.R
RUNBOOK.md
DESCRIPTION
NEWS.md
CLAUDE.md
data-raw/logs/cabd_shape_494/
data-raw/logs/publish_parallel_488/
