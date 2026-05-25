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
#' @param dest_conn DBI connection for verification queries. Default
#'   `NULL` — function constructs a connection to local fwapg
#'   (`localhost:5432/fwapg`, postgres/postgres) to match the COPY
#'   commands' hardcoded target. Pass an explicit connection only when
#'   you're running against a non-standard local fwapg layout. Note:
#'   `link::lnk_db_conn()` is NOT a safe default — on M4 it routes to
#'   the tunnel (`localhost:63333/bcfishpass`), which causes the
#'   `wgc_tables` enumeration to return empty and silently skip every
#'   source. Caught after #180 first integration run (Peace Tier 2,
#'   2026-05-15: 12 of 16 Peace WSGs lost because consolidate skipped
#'   M1 + both cyphers).
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
                                dest_conn = NULL,
                                verbose = TRUE,
                                keep_source = FALSE) {
  stopifnot(
    is.character(schema), length(schema) == 1L, nzchar(schema),
    is.list(sources), length(sources) > 0L
  )

  # Construct destination connection if not passed. Default is local
  # fwapg (matches the hardcoded `PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg`
  # in the COPY shellouts below). DO NOT default to `link::lnk_db_conn()`
  # — on M4 that returns a tunnel:63333/bcfishpass connection, which
  # silently breaks the `wgc_tables` enumeration and skips every source.
  if (is.null(dest_conn)) {
    dest_conn <- DBI::dbConnect(RPostgres::Postgres(),
      host = "localhost", port = 5432L,
      dbname = "fwapg", user = "postgres", password = "postgres")
    on.exit(try(DBI::dbDisconnect(dest_conn), silent = TRUE), add = TRUE)
  }

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

    # 3. Enumerate persistent tables on BOTH destination AND source,
    # then iterate the intersection. Destination accumulates tables
    # across runs (e.g. M4 carries `streams_habitat_<sp>` residue from
    # prior runs with study-area WSGs whose species presence covered
    # the full set). Source hosts only create habitat tables for
    # species their assigned bucket actually models (lnk_persist_init
    # is per-species-in-bucket). If we drove the loop off the
    # destination list, the COPY would hit the first dest-only table
    # and fail with `relation does not exist` on source — caught
    # 2026-05-15 in Peace Tier 2: cyphers had BT/GR/RB habitat only;
    # M4 had all 9 species; loop broke at `_ch` so `_gr`/`_rb` never
    # copied (link#185). Driving off intersection avoids that class.
    # JOIN against information_schema.tables WHERE table_type = 'BASE
    # TABLE' so views with a watershed_group_code column don't land
    # in the loop (DELETE + COPY FROM STDIN both fail on views).
    wgc_query <- sprintf(
      "SELECT c.table_name FROM information_schema.columns c
       JOIN information_schema.tables t
         ON t.table_schema = c.table_schema AND t.table_name = c.table_name
       WHERE c.table_schema = '%s' AND c.column_name = 'watershed_group_code'
         AND t.table_type = 'BASE TABLE'
       ORDER BY c.table_name", schema)
    dest_wgc <- DBI::dbGetQuery(dest_conn, wgc_query)$table_name
    if (length(dest_wgc) == 0L) {
      log(src$host, " -> ERROR: no tables with watershed_group_code in '",
          schema, "' on destination (did lnk_persist_init run?)")
      results[[src$host]] <- list(ok = FALSE, stage = "no_wgc_tables", rc = -1L)
      next
    }
    # Source enumeration via SSH + psql. Same query, same shape, just
    # tab-separated rows piped back over ssh. `\t` + `\a` for clean
    # parse-as-lines. Quote-escape pattern matches the COPY shellouts
    # below (single-quoted outer ssh arg; inner `'` -> `'\''`).
    src_wgc_sql <- gsub("\n\\s+", " ", wgc_query)
    src_wgc_inner <- if (via == "docker") {
      sprintf("docker exec %s psql -U %s -d %s -t -A -c \"%s\"",
              container, pg_user, pg_db, src_wgc_sql)
    } else {
      sprintf("PGHOST=localhost PGPORT=5432 PGDATABASE=%s PGUSER=%s PGPASSWORD=postgres psql -t -A -c \"%s\"",
              pg_db, pg_user, src_wgc_sql)
    }
    src_wgc_inner_esc <- gsub("'", "'\\''", src_wgc_inner, fixed = TRUE)
    src_wgc_raw <- system(sprintf("ssh '%s' '%s'", src$host, src_wgc_inner_esc),
                          intern = TRUE)
    src_wgc <- src_wgc_raw[nzchar(src_wgc_raw)]
    if (length(src_wgc) == 0L) {
      log(src$host, " -> ERROR: no tables with watershed_group_code in '",
          schema, "' on source (lnk_persist_init may not have run)")
      results[[src$host]] <- list(ok = FALSE, stage = "no_source_wgc_tables",
                                   rc = -1L)
      next
    }
    wgc_tables <- intersect(src_wgc, dest_wgc)
    skipped_source_only <- setdiff(src_wgc, dest_wgc)
    skipped_dest_only <- setdiff(dest_wgc, src_wgc)
    if (length(skipped_source_only) > 0L) {
      log(src$host, " -> NOTE: skipping ", length(skipped_source_only),
          " source-only tables (absent on destination): ",
          paste(skipped_source_only, collapse = ", "))
    }
    if (length(skipped_dest_only) > 0L) {
      log(src$host, " -> NOTE: skipping ", length(skipped_dest_only),
          " destination-only tables (absent on source): ",
          paste(skipped_dest_only, collapse = ", "))
    }
    if (length(wgc_tables) == 0L) {
      log(src$host, " -> ERROR: no overlap between source and destination ",
          "tables in '", schema, "'")
      results[[src$host]] <- list(ok = FALSE, stage = "no_table_overlap",
                                   rc = -1L)
      next
    }

    # 3.4. Per-table SHARED-column resolution for shape-tolerant COPY.
    # `COPY (SELECT *) TO STDOUT` -> `COPY <t> FROM STDIN` is positional:
    # it breaks ("extra data after last expected column") the moment a
    # source table's column set differs from the destination's. This
    # happens across hosts whenever a wide per-species table
    # (streams_access, streams_mapping_code) was created from a different
    # species set — e.g. a warm cypher snapshot baked an 11-species
    # streams_access (ct/dv/rb included) while the dispatcher's persist
    # is 8-species. Caught 2026-05-25 in the 3-WSG smoke (link#175).
    #
    # Fix: enumerate columns on BOTH sides, COPY only the intersection,
    # BY NAME, in destination ordinal order. Source-only columns are
    # dropped at SELECT; destination-only columns take their default /
    # NULL. Both COPY statements list the same ordered column vector, so
    # ordinal drift between hosts no longer matters.
    tbl_list_sql <- paste(sprintf("'%s'", wgc_tables), collapse = ", ")
    cols_sql <- gsub("\n\\s+", " ", sprintf(
      "SELECT table_name, column_name FROM information_schema.columns
       WHERE table_schema = '%s' AND table_name IN (%s)
       ORDER BY table_name, ordinal_position", schema, tbl_list_sql))
    dest_cols_df <- DBI::dbGetQuery(dest_conn, cols_sql)
    dest_cols <- split(dest_cols_df$column_name, dest_cols_df$table_name)
    src_cols_inner <- if (via == "docker") {
      sprintf("docker exec %s psql -U %s -d %s -t -A -c \"%s\"",
              container, pg_user, pg_db, cols_sql)
    } else {
      sprintf("PGHOST=localhost PGPORT=5432 PGDATABASE=%s PGUSER=%s PGPASSWORD=postgres psql -t -A -c \"%s\"",
              pg_db, pg_user, cols_sql)
    }
    src_cols_inner_esc <- gsub("'", "'\\''", src_cols_inner, fixed = TRUE)
    src_cols_raw <- system(sprintf("ssh '%s' '%s'", src$host, src_cols_inner_esc),
                           intern = TRUE)
    src_cols_raw <- src_cols_raw[nzchar(src_cols_raw)]
    src_cols_split <- strsplit(src_cols_raw, "|", fixed = TRUE)
    src_cols <- split(
      vapply(src_cols_split, `[`, character(1), 2L),
      vapply(src_cols_split, `[`, character(1), 1L))
    # Destination ordinal order, restricted to columns present on source.
    shared_cols <- lapply(wgc_tables, function(t) {
      dc <- dest_cols[[t]]
      dc[dc %in% src_cols[[t]]]
    })
    names(shared_cols) <- wgc_tables
    for (t in wgc_tables) {
      dc <- dest_cols[[t]]; sc <- src_cols[[t]]; sh <- shared_cols[[t]]
      if (length(sh) < length(dc) || length(sh) < length(sc)) {
        log(src$host, " -> NOTE: column drift on '", t, "' — COPY ",
            length(sh), " shared cols (dest=", length(dc), ", src=",
            length(sc), "); src-only: ",
            paste(setdiff(sc, dc), collapse = ","), "; dest-only: ",
            paste(setdiff(dc, sc), collapse = ","))
      }
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
    # 4. Per-table COPY: accumulate copied vs errored sets, do NOT
    # break on the first per-table failure. Each table's COPY is
    # independent at the SQL level (separate ssh round-trip, separate
    # destination COPY transaction). Breaking would leak the partial-
    # transfer class — caught in link#185 where a fail at table N
    # silently skipped table N+1..M that DID exist on source.
    copied_tables <- character()
    errored_tables <- character()
    first_err_stage <- NA_character_
    first_err_table <- NA_character_
    log(src$host, " -> COPY (bucket-filtered) for ", length(wgc_tables),
        " tables")
    for (t in wgc_tables) {
      col_list <- paste(shared_cols[[t]], collapse = ", ")
      src_sql <- sprintf(
        "COPY (SELECT %s FROM %s.%s WHERE watershed_group_code IN (%s)) TO STDOUT",
        col_list, schema, t, wsg_list_sql)
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
        log(src$host, " -> WARN: source_copy failed on table '", t,
            "' (continuing)")
        errored_tables <- c(errored_tables, t)
        if (is.na(first_err_table)) {
          first_err_stage <- "source_copy"; first_err_table <- t
        }
        unlink(tmpf)
        next
      }
      # Stage 2: local temp file -> destination COPY FROM STDIN. Same
      # explicit shared-column list as the source SELECT so the transfer
      # is by-name (shape-tolerant), not positional.
      dest_sql <- sprintf("COPY %s.%s (%s) FROM STDIN", schema, t, col_list)
      stage2 <- sprintf(
        "PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg PGUSER=postgres PGPASSWORD=postgres psql -v ON_ERROR_STOP=1 -c \"%s\" < %s",
        dest_sql, shQuote(tmpf))
      rc_dest <- system(stage2)
      unlink(tmpf)
      if (rc_dest != 0L) {
        log(src$host, " -> WARN: dest_copy failed on table '", t,
            "' (continuing)")
        errored_tables <- c(errored_tables, t)
        if (is.na(first_err_table)) {
          first_err_stage <- "dest_copy"; first_err_table <- t
        }
        next
      }
      copied_tables <- c(copied_tables, t)
    }
    if (length(errored_tables) > 0L) {
      log(src$host, " -> ERROR: ", length(errored_tables),
          " of ", length(wgc_tables), " tables failed: ",
          paste(errored_tables, collapse = ", "),
          " (first failure: ", first_err_stage, " on '",
          first_err_table, "')")
      results[[src$host]] <- list(
        ok = FALSE, stage = first_err_stage, rc = -1L,
        table = first_err_table,
        copied = copied_tables, errored = errored_tables,
        skipped_source_only = skipped_source_only,
        skipped_dest_only = skipped_dest_only)
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
      # Build a single multi-statement psql -c "..." for tables we
      # successfully COPYed. `;`-separated DELETE statements wrapped in
      # one psql invocation — fewer ssh round-trips than per-table.
      # Use `copied_tables`, NOT `wgc_tables`: only delete from source
      # the tables we actually transferred; tables we didn't copy stay
      # intact on source (e.g. if a table errored, keep its data for
      # debugging or retry).
      delete_stmts <- paste(
        vapply(copied_tables, function(t) sprintf(
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

    results[[src$host]] <- list(
      ok = TRUE, stage = "complete",
      pre_rows = pre_rows, post_rows = post_rows,
      copied = copied_tables, errored = character(),
      skipped_source_only = skipped_source_only,
      skipped_dest_only = skipped_dest_only)
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
