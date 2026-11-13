# Code-check round 3 (#474), branch against 50a5d58e

## Checklist read

- **code-check.md**: the prose of all 14 H3s under `## Mechanisms` (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice). Rules-that-stand-alone, Security and Spreadsheets sections: not read (no pattern in this diff), about 20 headings.
- **code-check-shell.md**: Over Tailscale SSH to a Mac, `ssh` exits 0 whatever the remote command returned; `a && b || c` runs `c` when any step before the `||` fails; `if ! cmd; then rc=$?` captures the negation; psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0; A heredoc whose body contains its own delimiter; macOS `/bin/bash` 3.2 quote-matches a heredoc inside `$( )`; `grep -c` prints the count AND exits 1; macOS `sed` dies on an invalid byte; On this Mac `stat` and `date` are GNU; A failed `cd` lets every later command run; `curl -o` without `-L`. Not read: about 75 others (no matching tool use).
- **code-check-r.md**: A database driver's value is not a base R type; A value compared as `::text` in SQL has PostgreSQL's spelling; as.POSIXct on a Date / on a character; Postgres row order is never fixed unless the query fixes it; An `information_schema` lookup by the literal table name; `read.delim()` quotes by default; `Rscript -e` supplies `--args` itself; Inside a dplyr verb, a column named like a local variable wins; `[[` on a named ATOMIC vector. Not read: about 140 others.
- **code-check-spatial.md**: none in full (ogr2ogr flags here are config spelling, not a spatial trap); index scanned.

## Mechanism

Every round-1 and round-2 defect was a check that took its evidence of success from the channel being judged, so silence or a stand-in read as a pass: the hosts that answered stood for the hosts of the run; ssh's exit stood for the remote command's; the session's zone stood for the zone the writer used; a NULL sorting first stood for the newest row; a process substitution's start stood for the file being whole; a loader row's existence stood for the table still holding that load. The general shape: an expected value derived from the input itself, or "no answer" folded into the passing branch rather than kept as a third state. The enumeration below walks every place in the branch's diff that judges an outcome, guards on an input, or converts an instant, and asks which branch the empty / unreadable case lands in.

## Enumeration

### (a) Remote and subprocess outcomes

| place (file:line) | what is judged | by what | verdict |
|---|---|---|---|
| scripts/update_hosts.sh:116-127 `on_host_checked` | pak install, fresh RemoteSha re-check | ssh exit AND `__UH_OK__` on its own line; remote `set -e` / explicit `exit 1` before the marker | holds |
| scripts/update_hosts.sh:150-168 `install_pak` | install + RemoteSha equality | marker; RemoteSha compared to the sha resolved up front | holds |
| scripts/update_hosts.sh:278-282 fresh re-check | fresh still at pin after link | marker; empty `got` fails the equality | holds |
| scripts/update_hosts.sh `install_remote` | tarball install | ssh exit status | accepted (listed tradeoff) |
| scripts/update_hosts.sh `resolve_sha` | GitHub sha | 40-hex anchor | holds |
| data-raw/study_area_run.sh `compare_inputs` dispatcher read | host_inputs.R | local Rscript exit | holds |
| data-raw/study_area_run.sh `compare_inputs` remote read | host_inputs.R piped on stdin | `remote_run` printed `__LNK_RC__` (subshell, so `exit $rc` reaches the trailer); missing trailer = 255 | holds |
| data-raw/study_area_run.sh `compare_inputs` judge | `.lnk_inputs_agree` | Rscript exit; a stop() (stray host) exits 1 = refuse | holds |
| data-raw/study_area_run.sh bcfp pin (≈1203) | ledger tier | Rscript exit AND non-empty; else WARN (by design) | holds |
| data-raw/study_area_run.sh `collect_stamps` | host_stamp.R | `remote_run` trailer (unchanged) | holds |
| data-raw/snapshot_bcfp.sh skip guard | `lnk_baseline_current` | stdout == "TRUE"; any failure prints FALSE = reload | holds (fails toward reload) |
| data-raw/snapshot_bcfp_lib.sh `bc2pg_load` | bcdata bc2pg | `if` exit status, then `snap_check` row count | holds, except snap_check (below) |
| data-raw/snapshot_bcfp_lib.sh:60 `snap_check` re-count | WFS numberMatched | `curl -s` + grep; empty = "no count" | **defect**: a known mismatch passes when the re-count is unreadable (Finding 1) |
| data-raw/snapshot_bcfp_lib.sh `wfs_load` | ogr2ogr WFS + DO block | ogr2ogr exit; `$PSQL` carries `-v ON_ERROR_STOP=1` so heredoc errors exit 3 | holds |
| data-raw/snapshot_bcfp_lib.sh `obs_parquet_fallback` | uv/pyarrow, \copy, INSERT | exit statuses; ON_ERROR_STOP; table freshly created before (snapshot_bcfp.sh:283) | holds (no row check on observations, as for the GDAL path) |
| data-raw/snapshot_bcfp.sh pyarrow download | `curl -fsSL` | exit status with `-f` | holds |
| data-raw/fwapg_load_capture.sh:67 | load.sh | `pipefail` pipeline status (tee waited for) | holds |
| data-raw/fwapg_load_capture.sh:77 | artifact_record.R | exit under `set -e` | holds |
| data-raw/artifact_record.R:103-110 | loader rows written | read-back count of distinct urls (loader upsert always overwrites) | holds |
| data-raw/pretest_run.sh `history.txt` read | pick's resolution | `sed` in an assignment under `set -e` (missing file aborts); schema regex | holds |
| data-raw/pretest_run.sh `CREATE SCHEMA` | psql | `psql_q` exit under `set -e` | holds |
| R/lnk_preflight_vintage.R `.lnk_vintage_heads` | HEAD | status 200 else NA, kept as `head_failed` (third state) | holds |
| R/lnk_artifact.R `.lnk_fwa_load_record` HEADs | HEAD per URL | NA rows recorded with notes; downstream compare reads NULL version as unrecorded | holds (recorder, fails safe downstream) |

### (b) New guards and their empty / missing / unparseable direction

| place | guard | empty/missing/unparseable lands in | verdict |
|---|---|---|---|
| R/lnk_artifact.R `.lnk_inputs_agree` | hosts agree | `hosts` from the caller; host with no row = refuse; blank version = refuse; blank n_rows = refuse; stray host = error | holds |
| R/lnk_artifact.R `.lnk_inputs_agree` API branch | md5, else n_rows | one host without md5 falls back to n_rows | holds (documented weaker) |
| data-raw/host_inputs.R | newest loader row per table | no provenance table = header only = refuse; `NULLS LAST`; no host filter, so a leaked test row reads as another version = refuse | holds (fails toward refuse) |
| data-raw/host_inputs.R `tables` vs `.lnk_vintage_primitives()` | two lists | agree today (checked); a new primitive missing here = refuse | holds |
| data-raw/study_area_run.sh worker pre-spend compare | workers vs dispatcher | unreachable = "could not be read" = refuse | holds |
| data-raw/study_area_run.sh cloud-host gate | `--refresh-primitives` | refuse; WARN under `--preflight-only` | holds |
| data-raw/study_area_run.sh date regex | ISO UTC | empty allowed (no date); malformed refused | holds |
| R/lnk_baseline_current.R | version AND date | missing column / zoneless / `?` date = NA = not current = reload | holds |
| R/lnk_log.R `.lnk_baseline_loaded_views` | views rows | NA label/notes = FALSE | holds |
| R/lnk_preflight_vintage.R ETag | changed since load | NA live ETag = age; NA stored ETag = age; both sides `.lnk_etag_normalise`d; URL is the unpinned dictionary URL | holds |
| R/lnk_artifact.R FWA loader-yields clause | loader replaced on row-count change | NULL n_rows (table absent) is DISTINCT, so a probe noting absence replaces it | holds |
| data-raw/pretest.R `pretest_record_history` / `_check` every_input | record picked on every input | missing `range_source` column = NULL = refuse; only with `own_n == 0` | holds |
| data-raw/pretest.R `pretest_build_minutes_read` | committed minutes | absent file = empty; bad row = stop (pick refuses) | holds |
| data-raw/pretest.R `pretest_minutes` | bound per group | no minutes = fixed 60; unknown host = median speed | holds |
| data-raw/pretest.R `pretest_ancestor_pick` | ancestor schema | none = NULL → every_input (own_n 0) or refuse | holds |
| data-raw/pretest_verdict.R history.txt | range_source | missing key = NA = stop | holds |
| data-raw/snapshot_bcfp_lib.sh `bc2pg_load` tunables | attempts/backoff | non-numeric / 0 refused | holds |
| data-raw/snapshot_bcfp_lib.sh `snap_check` | table whole | 0 rows / absent refused; unreadable first count = pass (documented); mismatch + unreadable re-count = **pass** | **defect** (Finding 1) |
| data-raw/study_area_verify.sql 2c + assertion | hosts read same inputs | NULL version = FAIL; one host without md5 = NOTE (documented) | holds |
| data-raw/study_area_verify_negative.sh 6/6a | prove 2c fires | a skip counts as a failure | holds |

### (c) Timestamp / zone conversions

| place | conversion | verdict |
|---|---|---|
| R/lnk_log.R `.lnk_instant_utc` | POSIXct via `format(tz="UTC")`; string only with an explicit zone, offset subtracted | holds (fraction dropped on both sides alike) |
| R/lnk_log.R `.lnk_log_timestamptz` | UTC Z literal `::timestamptz` | holds |
| R/lnk_log.R db tier | `timestamp AT TIME ZONE pg_settings.reset_val` (RPostgres 1.4.10 issues `SET TIMEZONE`, so reset_val is the server/db/role default); `NULLS LAST` | holds under the documented assumption (a client PGTZ startup option would also move reset_val) |
| R/lnk_log.R env and ledger tiers | Z strings | holds |
| data-raw/study_area_run.sh pin export | `format(..., tz="UTC")` Z | holds |
| data-raw/host_inputs.R | `loaded_at AT TIME ZONE 'UTC'` then to_char Z | holds |
| data-raw/build_minutes_append.R | timestamptz → POSIXct → `format(tz="UTC")` | holds |
| data-raw/pretest.R reader | `as.POSIXct(format=...Z, tz="UTC")` | holds |
| data-raw/artifact_record.R `when()` | `%Y-%m-%dT%H:%M:%SZ`, tz UTC | holds |
| data-raw/fwapg_load_capture.sh | `date -u`, `date -u -r` | holds |
| R/lnk_artifact.R `.lnk_fwa_load_record` | numeric compare; `lit()` writes `+00` | holds |

## Findings

- **[severity: bug]** data-raw/snapshot_bcfp_lib.sh:60 (`snap_check`) — `[ -z "$expect" ] || [ "$SNAP_N" = "$expect" ] && return 0` returns 0 when the second WFS count cannot be read, even though the first count was read and disagreed with the table. Reproduced with stubs: a table of 100 rows, first count 19905, second curl answering an error page → `snap_check` passes, `SNAP_N=100`, and `bc2pg_load` reports success with `SNAP_PATH="bcdata bc2pg"`. That is the very case the check exists for (a flaky WFS during a bc2pg load leaves a short table, and the same flakiness blanks the re-count), and it hands a truncated PSCIS view to `artifact_row` as a clean loader row. The re-ask was meant to tolerate an edit between count and load; an unreadable re-count is no evidence of that. Fix: when the first count disagreed, an empty re-count should fail (or fall back to comparing against the first count), e.g. `[ -n "$expect" ] && [ "$SNAP_N" = "$expect" ] && return 0`, with `SNAP_WHY` naming the first count when the second is empty. Also note the line is the `a || b && c` shape. (The documented "first count unreadable = accept any non-zero table" is a separate, stated weakening and is not flagged.)
  - **Inside a previous fix?** no
  - **Rule:** code-check.md "A guard that fails toward pass"; code-check-shell.md "`a && b || c` runs `c` when any step before the `||` fails"

Nothing else found. Round 2's fixes (FWA loader-yields clause, reset_val zone and NULLS LAST, the tee pipeline, `on_host_checked` and its marker, `dependencies = NA`, the pre-spend worker compare with piped `host_inputs.R`, the `--preflight-only` warn) each hold on their own inputs and on the empty case.
