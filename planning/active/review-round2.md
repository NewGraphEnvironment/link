# Code-check round 2 (#265) — branch vs main

Scope: round-1 fixes (probe-over-probe ON CONFLICT rule, artifact_record.R table
set, lnk_artifact_read shape) plus the rest of the code diff. Probes were
read-only: SELECTs against local fwapg, `lnk_artifact_read()` (read-only), and
throwaway R in a scratch session.

## Findings

- **[severity: fragile]** R/lnk_artifact.R:421-431 — fix #3 does not make the
  two shapes bindable, which is what its comment says it is for. A real read
  returns `n_rows` as **integer64** (RPostgres' default for `bigint`; checked
  against local fwapg: `$ n_rows :integer64`). The fallback frame used when the
  table does not exist has `n_rows = numeric(0)`, and after `merge()` that
  becomes an all-NA double column. `rbind(<read from a DB without the table>,
  <read from a DB with it>)` (the "all-missing host and a recorded one" case in
  the comment) gives garbage with no warning: base `[<-` on the double column
  puts integer64's raw bits in as doubles. Reproduced:
  `rbind(data.frame(n = c(1, 2)), data.frame(n = bit64::as.integer64(5)))`
  gives `2.470328e-323` for the 5. Binding in the other order works. It only
  fires when a read from a database with no `fresh.log_source_artifact` is
  combined with one that has it (cross-host), and nothing in the tree does that
  yet. Still, the comment invites exactly that call. Fix: cast in the SELECT
  (`n_rows::float8`, as `.lnk_artifact_count()` already does), or make the
  fallback `bit64::integer64(0)`.

- **[severity: fragile]** data-raw/study_area_run.sh:1291 vs :1405 (with
  data-raw/schema_consolidate.R:213-262) — a cypher's `log_input.artifact_*`
  can be dropped on the way home. Those columns are what "carries the identity
  home from a cypher" (R/lnk_artifact.R:12-13). But consolidate copies only the
  columns the source and destination share, and logs a NOTE for the rest. The
  destination's `log_input` gains the new columns only when something on the
  dispatcher runs `.lnk_log_create_tables()`. That happens either in a
  dispatcher model run before consolidate, or at the explicit call at :1405,
  which is *after* consolidate. So on the first run of this release into an
  existing persist schema where the dispatcher models nothing (the
  "every focal WSG on the dispatcher species-skips" case :1394 already names),
  every cypher's artifact identity is silently dropped. The cypher database is
  then burned, so it cannot be recovered. This is narrow, and the mechanism is
  pre-existing for any new column, but this branch is the first whose new
  columns are meant to survive the burn. Cheap fix: call
  `.lnk_log_create_tables()` on the destination before `schema_consolidate()`,
  or move the :1405 call up.

## Checked and clean

- ON CONFLICT rule (fix #1): went through every case (loader→anything;
  probe over loader; probe over probe with NULL, same, different or failed
  version, with and without a changed `n_rows`; derived rows). A failed HEAD
  (`EXCLUDED.version_id` NULL) evaluates NULL → no update, so it cannot blank an
  earlier probe. The `INSERT ... AS t ... ON CONFLICT DO UPDATE ... WHERE`
  syntax is valid. No duplicate conflict keys within one VALUES list (WSGs are
  DISTINCT, manifest one row per table).
- artifact_record.R (fix #2): `.lnk_vintage_primitives()` gives the 4 snapshot
  tables, and the manifest has 4 rows. The DATABASE_URL regex group indices
  (user m[3], password m[5], host m[6], port m[8], dbname m[9]) are correct.
  `snapshot_bcfp.sh` cds to the repo root (:68), so the relative
  `Rscript data-raw/artifact_record.R` and the DESCRIPTION probe resolve,
  including under cypher_prep.sh's `cd data-raw`.
- The `--clear` runs after the ledger skip-guard, so a skipped snapshot keeps
  its stamps. There is one EXIT trap. The awk under `pipefail` cannot SIGPIPE
  (headers fit the pipe buffer before awk reads them).
- `.lnk_log_inputs()`: column order in both branches matches the INSERT list,
  and the join on the (host, table_name, url) PK cannot fan out.
- Vintage gate: `split`/`vapply` on an empty stamp is safe. A stamp never
  rescues an absent table, and the OK-branch message excludes NA ages.
- Host label: the snapshot writer, the run log and the gate all use
  `.lnk_host()`, and `LNK_HOST_ALIAS` is set nowhere in the shell drivers, so the
  three agree on each host.
