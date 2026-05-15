#!/usr/bin/env Rscript
# data-raw/schema_consolidate.R
#
# Consolidate a Postgres schema from multiple remote hosts onto the
# local fwapg via `pg_dump -Fc` + scp + `pg_restore --data-only`.
#
# Usage:
#   Source this file (or Rscript), then:
#     schema_consolidate(
#       schema = "fresh",
#       sources = list(
#         list(host = "m1",                 via = "docker", container = "fresh-db"),
#         list(host = "cypher@100.72.81.25", via = "docker", container = "fresh-db")),
#       backup = TRUE,
#       verbose = TRUE)
#
# Status: draft. Shape is parametric enough to handle our trifecta
# pattern (fresh schema across M4 + M1 + cypher) but not generalized
# to arbitrary table subsets, alternative protocols (COPY streaming,
# logical replication), or arbitrary destination conns. Promote to
# `lnk_schema_consolidate()` only after using it 2-3 times for
# different schemas — the right API will emerge from real usage.
#
# Why pg_dump/restore not COPY streaming: per-host dumps act as
# automatic backups + idempotent re-runs (DELETE-WHERE keys in the
# persist step ensure re-restore overwrites cleanly without unique-
# constraint violations).
#
# Cross-refs: rtj#94 (general orchestrator); link#112 (first usage).

#' Consolidate a Postgres schema from N remote hosts onto local fwapg.
#'
#' @param schema Character. Schema to dump on each source + restore locally.
#' @param sources List of source-host specs. Each list element:
#'   \itemize{
#'     \item `host` — SSH target (e.g. `"m1"`, `"cypher@100.72.81.25"`).
#'     \item `via` — `"docker"` (run pg_dump inside container) or
#'           `"psql"` (host has pg_dump in PATH).
#'     \item `container` — Docker container name when `via = "docker"`.
#'           Defaults to `"fresh-db"`.
#'     \item `pg_user`, `pg_db` — Postgres user + db. Default `"postgres"` /
#'           `"fwapg"`.
#'     \item `bucket` — optional character vector of `watershed_group_code`
#'           values. When provided, the source's bucket is DELETEd from
#'           every destination table that has a `watershed_group_code`
#'           column BEFORE pg_restore. Prevents duplicate-key violations
#'           when re-consolidating after a prior partial restore.
#'   }
#' @param backup Logical. If TRUE (default), pg_dump local destination
#'   before restoring — rollback safety net. Saved to
#'   `/tmp/<schema>_pre_consolidate_<TS>.dump`.
#' @param dest_conn DBI connection for verification queries + (optional)
#'   for invoking lnk_db_conn-style auth. Default `link::lnk_db_conn()`.
#' @param verbose Logical.
#' @param keep_source Logical. When FALSE (default), drop the source
#'   schema on each remote host after a successful pg_restore — workers
#'   are one-shot ETL and the source copy is dead weight once consolidated.
#'   Pass TRUE to preserve the source for debugging or re-restore. Drop
#'   is rc-guarded: failed pg_restore leaves source schema in place for
#'   retry.
#'
#' @return Invisibly: list of per-source pg_dump + restore outcomes.
schema_consolidate <- function(schema,
                                sources,
                                backup = TRUE,
                                dest_conn = link::lnk_db_conn(),
                                verbose = TRUE,
                                keep_source = FALSE) {
  stopifnot(
    is.character(schema), length(schema) == 1L, nzchar(schema),
    is.list(sources), length(sources) > 0L
  )

  ts <- format(Sys.time(), "%Y%m%d%H%M")
  log <- function(...) if (verbose) cat(sprintf("[%s] %s\n",
    format(Sys.time(), "%H:%M:%S"), paste0(...)))

  # 1. Backup destination (rollback safety net).
  if (backup) {
    backup_path <- sprintf("/tmp/%s_pre_consolidate_%s.dump", schema, ts)
    log("backup local ", schema, " -> ", backup_path)
    cmd <- sprintf(
      "PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg PGUSER=postgres PGPASSWORD=postgres pg_dump --schema=%s -Fc -f %s",
      schema, backup_path)
    system(cmd, intern = FALSE)
  }

  results <- list()
  for (i in seq_along(sources)) {
    src <- sources[[i]]
    via <- src$via %||% "psql"
    pg_user <- src$pg_user %||% "postgres"
    pg_db   <- src$pg_db   %||% "fwapg"
    container <- src$container %||% "fresh-db"
    remote_dump <- sprintf("/tmp/%s_%s.dump", schema, ts)

    # 2. pg_dump on the source host.
    log(src$host, " -> pg_dump --schema=", schema, " (via ", via, ")")
    pg_dump_cmd <- if (via == "docker") {
      sprintf("docker exec %s pg_dump --schema=%s -Fc -U %s %s > %s",
        container, schema, pg_user, pg_db, remote_dump)
    } else {
      sprintf("PGHOST=localhost PGPORT=5432 PGDATABASE=%s PGUSER=%s PGPASSWORD=postgres pg_dump --schema=%s -Fc -f %s",
        pg_db, pg_user, schema, remote_dump)
    }
    rc <- system(sprintf("ssh '%s' '%s'", src$host, pg_dump_cmd))
    if (rc != 0L) {
      results[[src$host]] <- list(ok = FALSE, stage = "pg_dump", rc = rc)
      next
    }

    # 3. scp dump local.
    local_dump <- sprintf("/tmp/%s_%s_%s.dump", schema,
      gsub("[^A-Za-z0-9_]", "_", src$host), ts)
    log(src$host, " -> scp ", remote_dump, " (local: ", local_dump, ")")
    rc <- system(sprintf("scp -q '%s:%s' '%s'", src$host, remote_dump, local_dump))
    if (rc != 0L) {
      results[[src$host]] <- list(ok = FALSE, stage = "scp", rc = rc)
      next
    }

    # 3.5. Bucket-aware destination cleanup. When the source spec carries
    # `bucket = c(...)`, DELETE those WSG codes from every destination
    # table that has a `watershed_group_code` column, so pg_restore
    # --data-only INSERTs land on empty rows instead of hitting a
    # duplicate-key violation (each persist table has a PK on
    # (id_segment, watershed_group_code) or similar).
    if (!is.null(src$bucket) && length(src$bucket) > 0L) {
      wgc_tables <- DBI::dbGetQuery(dest_conn, sprintf(
        "SELECT table_name FROM information_schema.columns
         WHERE table_schema = '%s' AND column_name = 'watershed_group_code'
         ORDER BY table_name", schema))$table_name
      if (length(wgc_tables) > 0L) {
        wsg_list <- paste0("'", src$bucket, "'", collapse = ", ")
        log(src$host, " -> DELETE bucket (", length(src$bucket),
            " WSGs) from ", length(wgc_tables), " tables")
        for (t in wgc_tables) {
          DBI::dbExecute(dest_conn, sprintf(
            "DELETE FROM %s.%s WHERE watershed_group_code IN (%s)",
            schema, t, wsg_list))
        }
      }
    }

    # 3.6. Snapshot pre-restore row count across the schema. The post-
    # restore check requires `restored_rows > pre_rows` (a strict
    # increase), not just "non-zero". A non-zero check would falsely
    # pass any iteration after the first source — the schema already
    # has rows from prior iterations, so the second source's bad
    # restore wouldn't be caught.
    pre_tables <- DBI::dbGetQuery(dest_conn, sprintf(
      "SELECT tablename FROM pg_tables WHERE schemaname = '%s'",
      schema))$tablename
    pre_rows <- 0L
    for (t in pre_tables) {
      n <- DBI::dbGetQuery(dest_conn, sprintf(
        "SELECT count(*)::bigint AS n FROM %s.%s", schema, t))$n
      if (!is.na(n)) pre_rows <- pre_rows + n
    }

    # 4. pg_restore --data-only onto destination.
    log(src$host, " -> pg_restore --data-only ", local_dump)
    cmd <- sprintf(
      "PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg PGUSER=postgres PGPASSWORD=postgres pg_restore --data-only --no-owner --schema=%s -d fwapg %s",
      schema, local_dump)
    rc <- system(cmd)
    if (rc != 0L) {
      results[[src$host]] <- list(ok = FALSE, stage = "pg_restore", rc = rc,
                                   local_dump = local_dump)
      next
    }

    # 4.5. Verify pg_restore actually moved data. Exit code 0 + no
    # net new rows in the target schema means the source dump was
    # empty (e.g. a host that ran zero WSGs because its bucket was
    # misconfigured) — flag as failure so the operator notices
    # instead of treating it as a successful no-op.
    #
    # `count(*)` is the authoritative source (NOT
    # `pg_stat_user_tables.n_live_tup`, which lags the commit
    # asynchronously). Strict increase against `pre_rows` snapshot
    # so multi-source loops catch a bad source-N after source-1
    # already populated the schema.
    post_tables <- DBI::dbGetQuery(dest_conn, sprintf(
      "SELECT tablename FROM pg_tables WHERE schemaname = '%s'",
      schema))$tablename
    post_rows <- 0L
    for (t in post_tables) {
      n <- DBI::dbGetQuery(dest_conn, sprintf(
        "SELECT count(*)::bigint AS n FROM %s.%s", schema, t))$n
      if (!is.na(n)) post_rows <- post_rows + n
    }
    if (post_rows <= pre_rows) {
      log(src$host, " -> WARN: pg_restore rc=0 but row count did not ",
          "increase (", pre_rows, " -> ", post_rows, ") — flagging as failure")
      results[[src$host]] <- list(ok = FALSE, stage = "pg_restore_empty",
                                   rc = 0L, local_dump = local_dump,
                                   pre_rows = pre_rows, post_rows = post_rows)
      next
    }

    # 5. Drop source schema (rc-guarded — only on successful restore).
    # Worker hosts are one-shot ETL; once data lives on the destination
    # it's dead weight on the source. Saves ~25–30 GB per consolidated
    # bundle on M1 / cypher. Pass keep_source = TRUE to opt out (e.g.
    # debug, manual re-restore).
    if (!isTRUE(keep_source)) {
      drop_cmd <- if (via == "docker") {
        sprintf("docker exec %s psql -U %s -d %s -c \"DROP SCHEMA %s CASCADE\"",
          container, pg_user, pg_db, schema)
      } else {
        sprintf("PGHOST=localhost PGPORT=5432 PGDATABASE=%s PGUSER=%s PGPASSWORD=postgres psql -c \"DROP SCHEMA %s CASCADE\"",
          pg_db, pg_user, schema)
      }
      log(src$host, " -> DROP SCHEMA ", schema, " CASCADE (post-restore cleanup)")
      drop_rc <- system(sprintf("ssh '%s' '%s'", src$host, drop_cmd))
      if (drop_rc != 0L) {
        log(src$host, " -> WARN: DROP SCHEMA returned rc=", drop_rc,
            " — restore succeeded, source not cleaned, recoverable")
      }
    }

    results[[src$host]] <- list(ok = TRUE, stage = "complete",
                                 local_dump = local_dump)
  }

  # 5. Verification: per-table row + WSG counts on destination.
  log("verify destination tables in schema '", schema, "'")
  tables <- DBI::dbGetQuery(dest_conn, sprintf(
    "SELECT tablename FROM pg_tables WHERE schemaname = '%s' ORDER BY tablename",
    schema))$tablename
  if (length(tables) > 0L) {
    counts <- lapply(tables, function(t) {
      qry <- sprintf("SELECT '%s' AS tbl, count(*) AS rows FROM %s.%s",
        t, schema, t)
      DBI::dbGetQuery(dest_conn, qry)
    })
    print(do.call(rbind, counts))
  }

  invisible(list(sources = results, tables = tables))
}

# ---------------------------------------------------------------------------
# Default invocation — link#112 trifecta consolidation.
# ---------------------------------------------------------------------------
if (!interactive() && length(commandArgs(trailingOnly = TRUE)) == 0L &&
    sys.nframe() == 0L) {
  schema_consolidate(
    schema = "fresh",
    sources = list(
      list(host = "m1",                  via = "docker"),
      list(host = "cypher@100.72.81.25", via = "docker")
    ),
    backup = TRUE)
}
