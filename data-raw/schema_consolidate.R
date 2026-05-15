#!/usr/bin/env Rscript
# data-raw/schema_consolidate.R
#
# Consolidate a Postgres schema from multiple remote hosts onto the
# local fwapg via bucket-filtered COPY streaming over SSH.
#
# Usage:
#   Source this file (or Rscript), then:
#     schema_consolidate(
#       schema = "fresh",
#       sources = list(
#         list(host = "m1",                  via = "docker",
#              bucket = c("ADMS","BULK","DEAD")),
#         list(host = "cypher@100.72.81.25", via = "docker",
#              bucket = c("ELKR","FOXR"))),
#       backup = TRUE,
#       verbose = TRUE)
#
# `bucket` is REQUIRED per source — whole-schema dump was removed in
# favour of per-table `COPY (SELECT * FROM <t> WHERE wsg IN (bucket))
# TO STDOUT` piped over SSH to local `COPY <t> FROM STDIN`. This
# filters at the source so any out-of-bucket rows the source happens
# to carry (leftover from prior runs in a different bucket) don't
# transfer + collide on destination PK.
#
# Why COPY streaming over pg_dump/restore: the old flow pg_dump'd the
# whole schema (no row-level filter), scp'd the binary archive, then
# pg_restore --data-only. When the source carried WSGs outside the
# bucket (e.g. M1 running Peace while still holding study-area
# leftover), pg_restore collided on destination's existing WSG rows.
# COPY-streaming with `WHERE wsg IN (bucket)` at source eliminates the
# over-fetch class entirely.
#
# Cross-refs: rtj#94 (general orchestrator); link#112 (first usage);
# link#180 (additive Step 0 unblocked by this source-filter fix).

#' Consolidate a Postgres schema from N remote hosts onto local fwapg.
#'
#' @param schema Character. Schema to consolidate (must already exist on
#'   destination with the expected tables; `lnk_persist_init` creates them).
#' @param sources List of source-host specs. Each list element:
#'   \itemize{
#'     \item `host` — SSH target (e.g. `"m1"`, `"cypher@100.72.81.25"`).
#'     \item `via` — `"docker"` (run psql inside container) or
#'           `"psql"` (host has psql in PATH).
#'     \item `container` — Docker container name when `via = "docker"`.
#'           Defaults to `"fresh-db"`.
#'     \item `pg_user`, `pg_db` — Postgres user + db. Default `"postgres"` /
#'           `"fwapg"`.
#'     \item `bucket` — REQUIRED character vector of `watershed_group_code`
#'           values. Drives both the source-side row filter (`COPY (SELECT
#'           * FROM <t> WHERE wsg IN (bucket)) TO STDOUT`) and the
#'           destination-side DELETE-WHERE-WSG (clears the bucket on
#'           destination before the inbound COPY-INSERTs so PK constraints
#'           don't fire).
#'   }
#' @param backup Logical. If TRUE (default), pg_dump local destination
#'   before consolidating — rollback safety net. Saved to
#'   `/tmp/<schema>_pre_consolidate_<TS>.dump`.
#' @param dest_conn DBI connection for verification queries + (optional)
#'   for invoking lnk_db_conn-style auth. Default `link::lnk_db_conn()`.
#' @param verbose Logical.
#' @param keep_source Logical. When FALSE (default), drop the source
#'   schema on each remote host after a successful COPY — workers
#'   are one-shot ETL and the source copy is dead weight once consolidated.
#'   Pass TRUE to preserve the source for debugging or re-restore. Drop
#'   is rc-guarded: failed COPY leaves source schema in place for retry.
#'
#' @return Invisibly: list of per-source COPY outcomes (ok, stage, rc,
#'   pre_rows, post_rows).
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
    # 2. Bucket required for bucket-filtered COPY streaming.
    # Previously this function pg_dump'd the whole source schema and
    # relied on a destination-only DELETE-WHERE-WSG to avoid collisions.
    # That approach failed when the source had WSGs outside the bucket
    # that overlapped the destination's existing data (e.g. M1 carries
    # leftover study-area WSGs while running a Peace bucket; pg_restore
    # then collided on the leftover). The new flow filters at the
    # source via per-table `COPY (SELECT ... WHERE wsg IN (bucket))`,
    # eliminating the over-fetch class.
    if (is.null(src$bucket) || length(src$bucket) == 0L) {
      stop("schema_consolidate: each source must specify `bucket = c(<WSGs>)`. ",
           "Whole-schema dump is no longer supported; bucket-filtered ",
           "COPY streaming is required.", call. = FALSE)
    }
    wsg_list_sql <- paste0("'", src$bucket, "'", collapse = ", ")

    # 3. Enumerate persistent tables on the destination (must already
    # exist via lnk_persist_init). Same wgc_tables set drives the
    # destination DELETE + per-table COPY streaming. JOIN against
    # information_schema.tables WHERE table_type = 'BASE TABLE' so
    # any future views in the schema with a watershed_group_code
    # column don't accidentally land in the table loop (DELETE +
    # COPY FROM STDIN both fail against views).
    wgc_tables <- DBI::dbGetQuery(dest_conn, sprintf(
      "SELECT c.table_name FROM information_schema.columns c
       JOIN information_schema.tables t
         ON t.table_schema = c.table_schema AND t.table_name = c.table_name
       WHERE c.table_schema = '%s' AND c.column_name = 'watershed_group_code'
         AND t.table_type = 'BASE TABLE'
       ORDER BY c.table_name", schema))$table_name
    if (length(wgc_tables) == 0L) {
      log(src$host, " -> ERROR: no tables with watershed_group_code in '",
          schema, "' on destination (did lnk_persist_init run?)")
      results[[src$host]] <- list(ok = FALSE, stage = "no_wgc_tables", rc = -1L)
      next
    }

    # 3.5. Bucket-aware destination cleanup. DELETE the bucket's WSGs
    # from every destination table BEFORE the COPY-INSERTs so PK
    # constraints don't fire on the inbound rows.
    log(src$host, " -> DELETE bucket (", length(src$bucket),
        " WSGs) from ", length(wgc_tables), " tables")
    for (t in wgc_tables) {
      DBI::dbExecute(dest_conn, sprintf(
        "DELETE FROM %s.%s WHERE watershed_group_code IN (%s)",
        schema, t, wsg_list_sql))
    }

    # 3.6. Snapshot pre-restore total row count across the schema. The
    # post-restore check requires `post_rows > pre_rows` (a strict
    # increase). A non-zero check would falsely pass any iteration
    # after the first source — the schema already has rows from prior
    # iterations.
    pre_rows <- 0L
    for (t in wgc_tables) {
      n <- DBI::dbGetQuery(dest_conn, sprintf(
        "SELECT count(*)::bigint AS n FROM %s.%s", schema, t))$n
      if (!is.na(n)) pre_rows <- pre_rows + as.numeric(n)
    }

    # 4. Per-table COPY: bucket-filtered SELECT on source via SSH ->
    # local temp file -> COPY FROM STDIN on destination.
    #
    # Two-stage (temp file) instead of one-pipe because the WSG list
    # literal `'A','B','C'` contains single quotes that conflict with
    # `bash -c 'set -o pipefail; ...'` body quoting. With the temp
    # file: each stage runs as its own system() call, each rc checked
    # explicitly, no pipefail magic required. Per-table file released
    # between tables; largest case (streams in a 13-WSG bucket) is
    # ~100 MB transient.
    copy_failed <- FALSE
    failed_table <- NA_character_
    failed_stage <- NA_character_
    log(src$host, " -> COPY (bucket-filtered) for ", length(wgc_tables),
        " tables")
    for (t in wgc_tables) {
      src_sql <- sprintf(
        "COPY (SELECT * FROM %s.%s WHERE watershed_group_code IN (%s)) TO STDOUT",
        schema, t, wsg_list_sql)
      src_inner <- if (via == "docker") {
        sprintf("docker exec -i %s psql -U %s -d %s -c \"%s\"",
                container, pg_user, pg_db, src_sql)
      } else {
        sprintf("PGHOST=localhost PGPORT=5432 PGDATABASE=%s PGUSER=%s PGPASSWORD=postgres psql -c \"%s\"",
                pg_db, pg_user, src_sql)
      }
      # Stage 1: source -> local temp file. Outer ssh arg is SINGLE-
      # quoted so the inner `psql -c "..."` double-quotes stay literal.
      # BUT the SQL contains its own single quotes (WSG list literals
      # like 'ADMS','BULK'), which bash's adjacent-quote concatenation
      # strips inside a single-quoted outer wrapper. Workaround: escape
      # each inner `'` to `'\''` (close-quote, escaped-quote, reopen-
      # quote — the standard bash idiom for embedding ' in a '-quoted
      # string).
      src_inner_esc <- gsub("'", "'\\''", src_inner, fixed = TRUE)
      tmpf <- tempfile(pattern = sprintf("consolidate_%s_", t),
                       fileext = ".tsv")
      stage1 <- sprintf("ssh '%s' '%s' > %s",
                        src$host, src_inner_esc, shQuote(tmpf))
      rc_src <- system(stage1)
      if (rc_src != 0L) {
        copy_failed <- TRUE; failed_table <- t; failed_stage <- "source_copy"
        unlink(tmpf)
        break
      }
      # Stage 2: local temp file -> destination COPY FROM STDIN.
      dest_sql <- sprintf("COPY %s.%s FROM STDIN", schema, t)
      stage2 <- sprintf(
        "PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg PGUSER=postgres PGPASSWORD=postgres psql -v ON_ERROR_STOP=1 -c \"%s\" < %s",
        dest_sql, shQuote(tmpf))
      rc_dest <- system(stage2)
      unlink(tmpf)
      if (rc_dest != 0L) {
        copy_failed <- TRUE; failed_table <- t; failed_stage <- "dest_copy"
        break
      }
    }
    if (isTRUE(copy_failed)) {
      log(src$host, " -> ERROR: COPY failed (", failed_stage,
          ") on table '", failed_table, "'")
      results[[src$host]] <- list(ok = FALSE, stage = failed_stage,
                                   rc = -1L, table = failed_table)
      next
    }

    # 4.5. Verify COPY pipeline moved data. Exit code 0 on every per-
    # table COPY + no net new rows in the target schema means the
    # source's filtered SELECT returned 0 rows (e.g. a host that ran
    # zero WSGs because its bucket was misconfigured, or a typo) —
    # flag as failure so the operator notices instead of treating it
    # as a successful no-op.
    #
    # `count(*)` is the authoritative source (NOT
    # `pg_stat_user_tables.n_live_tup`, which lags the commit
    # asynchronously). Strict increase against `pre_rows` snapshot
    # so multi-source loops catch a bad source-N after source-1
    # already populated the schema.
    post_rows <- 0L
    for (t in wgc_tables) {
      n <- DBI::dbGetQuery(dest_conn, sprintf(
        "SELECT count(*)::bigint AS n FROM %s.%s", schema, t))$n
      if (!is.na(n)) post_rows <- post_rows + as.numeric(n)
    }
    if (post_rows <= pre_rows) {
      log(src$host, " -> WARN: COPY pipeline rc=0 but row count did not ",
          "increase (", pre_rows, " -> ", post_rows, ") — flagging as failure")
      results[[src$host]] <- list(ok = FALSE, stage = "copy_empty",
                                   rc = 0L,
                                   pre_rows = pre_rows, post_rows = post_rows)
      next
    }

    # 5. Bucket-scoped source cleanup (rc-guarded — only on successful
    # COPY). Worker hosts are one-shot ETL for THIS bucket; the rows
    # we transferred are dead weight on the source.
    #
    # CRITICAL: bucket-scoped, NOT whole-schema. Under the old whole-
    # schema pg_dump flow, DROP SCHEMA was symmetric — everything on
    # source had transferred to destination. Under the new bucket-
    # filtered COPY flow, source may still hold WSGs outside the bucket
    # (the very leftover-WSG case this rewrite was designed to ignore
    # at SELECT time). DROP SCHEMA would silently destroy them. So we
    # do per-table DELETE-WHERE-WSG IN (bucket) instead.
    #
    # Pass keep_source = TRUE to skip the cleanup entirely (debug).
    if (!isTRUE(keep_source)) {
      log(src$host, " -> DELETE bucket from source (post-COPY cleanup)")
      # Build a single multi-statement psql -c "..." for all tables.
      # `;`-separated DELETE statements wrapped in one psql invocation
      # — fewer ssh round-trips than per-table.
      delete_stmts <- paste(
        vapply(wgc_tables, function(t) sprintf(
          "DELETE FROM %s.%s WHERE watershed_group_code IN (%s)",
          schema, t, wsg_list_sql), character(1)),
        collapse = "; ")
      # ON_ERROR_STOP=1 so mid-batch SQL error propagates as non-zero
      # rc (otherwise psql continues past failures and returns 0).
      cleanup_cmd <- if (via == "docker") {
        sprintf("docker exec %s psql -U %s -d %s -v ON_ERROR_STOP=1 -c \"%s\"",
                container, pg_user, pg_db, delete_stmts)
      } else {
        sprintf("PGHOST=localhost PGPORT=5432 PGDATABASE=%s PGUSER=%s PGPASSWORD=postgres psql -v ON_ERROR_STOP=1 -c \"%s\"",
                pg_db, pg_user, delete_stmts)
      }
      # Single-quoted outer ssh arg + escape inner single quotes via
      # bash's `'\''` idiom (the cleanup_cmd's DELETE statements
      # contain WSG-list single quotes that would otherwise leak out
      # of the outer quoting).
      cleanup_cmd_esc <- gsub("'", "'\\''", cleanup_cmd, fixed = TRUE)
      drop_rc <- system(sprintf("ssh '%s' '%s'", src$host, cleanup_cmd_esc))
      if (drop_rc != 0L) {
        log(src$host, " -> WARN: source DELETE returned rc=", drop_rc,
            " — COPY succeeded, source not cleaned, recoverable")
      }
    }

    results[[src$host]] <- list(ok = TRUE, stage = "complete",
                                 pre_rows = pre_rows, post_rows = post_rows)
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
