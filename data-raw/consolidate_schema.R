#!/usr/bin/env Rscript
# data-raw/consolidate_schema.R
#
# Consolidate a Postgres schema from multiple remote hosts onto the
# local fwapg via `pg_dump -Fc` + scp + `pg_restore --data-only`.
#
# Usage:
#   Source this file (or Rscript), then:
#     consolidate_schema(
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
# `lnk_consolidate_schema()` only after using it 2-3 times for
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
#'   }
#' @param backup Logical. If TRUE (default), pg_dump local destination
#'   before restoring — rollback safety net. Saved to
#'   `/tmp/<schema>_pre_consolidate_<TS>.dump`.
#' @param dest_conn DBI connection for verification queries + (optional)
#'   for invoking lnk_db_conn-style auth. Default `link::lnk_db_conn()`.
#' @param verbose Logical.
#'
#' @return Invisibly: list of per-source pg_dump + restore outcomes.
consolidate_schema <- function(schema,
                                sources,
                                backup = TRUE,
                                dest_conn = link::lnk_db_conn(),
                                verbose = TRUE) {
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
  consolidate_schema(
    schema = "fresh",
    sources = list(
      list(host = "m1",                  via = "docker"),
      list(host = "cypher@100.72.81.25", via = "docker")
    ),
    backup = TRUE)
}
