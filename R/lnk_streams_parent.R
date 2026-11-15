#' Columns of `<schema>.streams_parent`
#'
#' One row per full segment: the minimal segment it lies in (by largest
#' measure overlap on its `blue_line_key`), that segment's gradient and
#' length, how much of the full segment lies in it (`overlap_m`) and outside
#' it (`straddle_m`), and which two builds the row was joined from.
#' `overlap_m + straddle_m` is the full segment's length, which a reader
#' compares with `streams.length_metre` to tell a stale row.
#' @noRd
cols_streams_parent <- c(
  id_segment           = "integer NOT NULL",
  watershed_group_code = "varchar(4) NOT NULL",
  id_segment_minimal   = "integer NOT NULL",
  gradient_minimal     = "double precision",
  length_minimal       = "double precision",
  overlap_m            = "double precision NOT NULL",
  straddle_m           = "double precision NOT NULL",
  schema_minimal       = "text NOT NULL",
  run_id_minimal       = "text NOT NULL",
  run_uid_minimal      = "text",
  config_hash_minimal  = "text",
  link_sha_minimal     = "text",
  run_id_full          = "text NOT NULL",
  built_at             = "timestamptz NOT NULL DEFAULT now()"
)

#' Create `<schema>.streams_parent` and its group index, if absent
#'
#' Only [lnk_streams_parent()] creates it, never [lnk_persist_init()]:
#' consolidate copies the persist tables it knows, and a table every host
#' created would be one it does not.
#' @noRd
.lnk_streams_parent_create <- function(conn, schema) {
  cols <- .lnk_cols_clause(cols_streams_parent, c("id_segment", "watershed_group_code"))
  sql <- sprintf("CREATE TABLE IF NOT EXISTS %s.streams_parent (\n  %s\n)", schema, cols)
  .lnk_db_execute(conn, sql)
  have <- .lnk_schema_indexes(conn, schema)
  on <- sprintf("%s.streams_parent (watershed_group_code)", schema)
  .lnk_index_create(conn, have, "streams_parent_wsg_idx", on)
  invisible(TRUE)
}

# .lnk_streams_parent_builds() lives in R/lnk_gradient_parent.R, beside the
# build-time judgement that also reads it (#463).

#' Join each full segment to the minimal segment it was cut from
#'
#' Builds `<schema>.streams_parent` for one watershed group: for every
#' segment of the full network (`schema`, for example `fresh_default`) the
#' segment of the minimal network (`schema_minimal`, for example
#' `fresh_default_minimal`) it lies in, with that segment's gradient and
#' length. A habitat rule tuned on the minimal network can then read the
#' gradient it was tuned on at each full segment.
#'
#' Segments are matched by measure overlap on each `blue_line_key`, never by
#' `id_segment` (each build numbers its own). Pieces shorter than `sliver_m`
#' are dropped (an FWA segment's upstream measure can overshoot the next one's
#' start by a few millimetres), and each full segment takes the minimal
#' segment it overlaps most. The join is refused unless every minimal cut
#' above `cut_floor_m` on its line has a full cut within `tol_m` of it, so a
#' full segment straddles a minimal cut by at most about `tol_m`; the full
#' build skips a cut within 1 m of an existing end. It is also refused when
#' the pieces do not cover both networks' km, or when a full segment would get
#' no row.
#'
#' The group's rows are replaced in one transaction, so a refusal leaves its
#' earlier rows in place. Nothing on the modelling path reads or writes the
#' table: a re-model of either network leaves its rows behind, and
#' `run_id_full`, `run_id_minimal` and `overlap_m + straddle_m` (the full
#' segment's length) are what tell a stale row. Whether the two builds ran the
#' same modelling code is judged by the caller
#' (`data-raw/streams_parent_build.R`).
#'
#' @param conn A [DBI::DBIConnection-class] to the database holding both
#'   persist schemas.
#' @param wsg Character. One watershed group code.
#' @param schema Character. The full network's persist schema; the table is
#'   written there.
#' @param schema_minimal Character. The minimal network's persist schema.
#' @param tol_m Numeric. How far, in metres, a minimal cut may lie from the
#'   nearest full cut.
#' @param sliver_m Numeric. Overlap pieces shorter than this, in metres, are
#'   dropped.
#' @param cut_floor_m Numeric. A minimal segment starting above this measure
#'   is a cut; one starting at or below it starts its line.
#' @param run_id_full,run_id_minimal Character or `NULL`. When given, the
#'   `log.run_id` of the build a caller judged on each side; the join is
#'   refused if the group's newest build is another one (it was re-modelled
#'   after the judgement).
#' @return A one-row data frame, invisibly: `wsg`, `n_full`, `n_minimal`,
#'   `km`, `n_straddle` (full segments with `straddle_m` of `sliver_m` or
#'   more), `km_straddle`, `max_straddle_m`.
#' @export
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
#'                     user = "postgres", password = "postgres")
#' lnk_streams_parent(conn, "BULK", schema = "fresh_default",
#'                    schema_minimal = "fresh_default_minimal")
#' DBI::dbGetQuery(conn, "
#'   SELECT s.id_segment, s.gradient, p.gradient_minimal, p.straddle_m
#'     FROM fresh_default.streams s
#'     JOIN fresh_default.streams_parent p USING (id_segment, watershed_group_code)
#'    WHERE s.watershed_group_code = 'BULK' LIMIT 5")
#' }
lnk_streams_parent <- function(conn, wsg, schema, schema_minimal,
                               tol_m = 1.01, sliver_m = 0.01, cut_floor_m = 0.5,
                               run_id_full = NULL, run_id_minimal = NULL) {
  if (!is.character(wsg) || length(wsg) != 1L || !grepl("^[A-Z]{4}$", wsg)) {
    stop("wsg must be one watershed group code (four capital letters)", call. = FALSE)
  }
  for (s in list(schema, schema_minimal)) {
    # Lower case and at most 63 bytes: the SQL names them unquoted, so Postgres
    # folds case and truncates past 63 bytes, and two names it reads as one
    # would pass the different-schemas test below.
    if (!is.character(s) || length(s) != 1L || !grepl("^[a-z_][a-z0-9_]{0,62}$", s)) {
      stop("schema and schema_minimal must each be one plain lower-case schema name", call. = FALSE)
    }
  }
  if (identical(schema, schema_minimal)) {
    stop("schema and schema_minimal must be two different schemas", call. = FALSE)
  }
  for (v in list(tol_m, sliver_m, cut_floor_m)) {
    if (!is.numeric(v) || length(v) != 1L || is.na(v) || v < 0) {
      stop("tol_m, sliver_m and cut_floor_m must each be one non-negative number",
           call. = FALSE)
    }
  }

  builds <- .lnk_streams_parent_builds(conn, schema, schema_minimal, wsg)
  bf <- builds[builds$side == "full", ]
  bm <- builds[builds$side == "minimal", ]
  for (x in list(list(run_id_full, bf, "full"), list(run_id_minimal, bm, "minimal"))) {
    if (!is.null(x[[1]]) && !identical(as.character(x[[1]]), x[[2]]$run_id)) {
      stop(sprintf("the newest %s build of %s is %s, not the judged %s: it was re-modelled since",
                   x[[3]], wsg, x[[2]]$run_id, paste(x[[1]], collapse = ",")), call. = FALSE)
    }
  }
  num <- function(sql) {
    d <- DBI::dbGetQuery(conn, sql)
    d[] <- lapply(d, as.numeric)
    d
  }
  lit <- .lnk_quote_literal
  na_lit <- function(x) if (is.na(x)) "NULL" else lit(as.character(x))
  fmt <- function(x) format(x, digits = 17)

  tmp <- c("lnk_sp_f", "lnk_sp_m", "lnk_sp_pc", "lnk_sp_parent")
  drop_tmp <- function() {
    for (t in tmp) .lnk_db_execute(conn, sprintf("DROP TABLE IF EXISTS pg_temp.%s", t))
  }
  drop_tmp()
  on.exit(try(drop_tmp(), silent = TRUE), add = TRUE)
  for (p in list(c("lnk_sp_f", schema), c("lnk_sp_m", schema_minimal))) {
    sql <- sprintf(
      "CREATE TEMP TABLE %1$s AS
       SELECT id_segment, blue_line_key AS blk, downstream_route_measure AS dm,
              upstream_route_measure AS um, gradient, length_metre
         FROM %2$s.streams WHERE watershed_group_code = %3$s",
      p[1], p[2], lit(wsg)
    )
    .lnk_db_execute(conn, sql)
    .lnk_db_execute(conn, sprintf("CREATE INDEX ON pg_temp.%s (blk, dm)", p[1]))
    .lnk_db_execute(conn, sprintf("ANALYZE pg_temp.%s", p[1]))
  }
  sql <- sprintf(
    "CREATE TEMP TABLE lnk_sp_pc AS
     SELECT f.id_segment AS fid, m.id_segment AS mid,
            least(f.um, m.um) - greatest(f.dm, m.dm) AS len
       FROM pg_temp.lnk_sp_f f JOIN pg_temp.lnk_sp_m m
         ON f.blk = m.blk AND f.dm < m.um AND m.dm < f.um
      WHERE least(f.um, m.um) - greatest(f.dm, m.dm) >= %s",
    fmt(sliver_m)
  )
  .lnk_db_execute(conn, sql)

  seg <- num(
    "SELECT (SELECT count(*) FROM pg_temp.lnk_sp_f) AS n_full,
            (SELECT count(*) FROM pg_temp.lnk_sp_m) AS n_minimal,
            (SELECT coalesce(sum(um - dm), 0) FROM pg_temp.lnk_sp_f) AS m_full,
            (SELECT coalesce(sum(um - dm), 0) FROM pg_temp.lnk_sp_m) AS m_minimal,
            (SELECT coalesce(sum(len), 0) FROM pg_temp.lnk_sp_pc) AS m_pieces"
  )
  if (seg$n_full == 0 || seg$n_minimal == 0) {
    empty <- if (seg$n_full == 0) schema else schema_minimal
    stop(wsg, " has no segments in ", empty, ".streams", call. = FALSE)
  }
  # The pieces must cover both networks: 1 m per 1,000 segments.
  cover_m <- max(seg$n_full, seg$n_minimal) / 1000
  if (abs(seg$m_pieces - seg$m_full) > cover_m || abs(seg$m_pieces - seg$m_minimal) > cover_m) {
    msg <- sprintf(
      "%s: the overlap pieces (%.3f km) do not cover both networks (full %.3f km, minimal %.3f km)",
      wsg, seg$m_pieces / 1000, seg$m_full / 1000, seg$m_minimal / 1000
    )
    stop(msg, call. = FALSE)
  }

  sql <- sprintf(
    "SELECT count(*) AS n FROM pg_temp.lnk_sp_m m
      WHERE m.dm > %s AND NOT EXISTS (
        SELECT 1 FROM pg_temp.lnk_sp_f f
         WHERE f.blk = m.blk AND abs(f.dm - m.dm) <= %s)",
    fmt(cut_floor_m), fmt(tol_m)
  )
  unmatched <- num(sql)$n
  if (unmatched > 0) {
    msg <- sprintf(
      paste("%s: %d minimal cut%s in %s ha%s no full cut within %s m in %s,",
            "so a full segment there would straddle a minimal segment"),
      wsg, as.integer(unmatched), if (unmatched == 1) "" else "s", schema_minimal,
      if (unmatched == 1) "s" else "ve", format(tol_m), schema
    )
    stop(msg, call. = FALSE)
  }

  .lnk_db_execute(conn,
    "CREATE TEMP TABLE lnk_sp_parent AS
     SELECT DISTINCT ON (pc.fid) pc.fid AS id_segment,
            pc.mid AS id_segment_minimal, m.gradient AS gradient_minimal,
            m.length_metre AS length_minimal, pc.len AS overlap_m,
            (f.um - f.dm) - pc.len AS straddle_m
       FROM pg_temp.lnk_sp_pc pc
       JOIN pg_temp.lnk_sp_f f ON f.id_segment = pc.fid
       JOIN pg_temp.lnk_sp_m m ON m.id_segment = pc.mid
      ORDER BY pc.fid, pc.len DESC, pc.mid"
  )

  .lnk_streams_parent_create(conn, schema)
  sql_delete <- sprintf("DELETE FROM %s.streams_parent WHERE watershed_group_code = %s",
                        schema, lit(wsg))
  sql_insert <- sprintf(
    "INSERT INTO %1$s.streams_parent (id_segment, watershed_group_code,
       id_segment_minimal, gradient_minimal, length_minimal, overlap_m, straddle_m,
       schema_minimal, run_id_minimal, run_uid_minimal, config_hash_minimal,
       link_sha_minimal, run_id_full)
     SELECT id_segment, %2$s, id_segment_minimal, gradient_minimal, length_minimal,
            overlap_m, straddle_m, %3$s, %4$s, %5$s, %6$s, %7$s, %8$s
       FROM pg_temp.lnk_sp_parent",
    schema, lit(wsg), lit(schema_minimal), lit(bm$run_id), na_lit(bm$run_uid),
    na_lit(bm$config_hash), na_lit(bm$link_sha), lit(bf$run_id)
  )
  DBI::dbWithTransaction(conn, {
    .lnk_db_execute(conn, sql_delete)
    n_ins <- .lnk_db_execute(conn, sql_insert)
    if (n_ins != seg$n_full) {
      msg <- sprintf(
        paste("%s: the join gives %d rows for %d full segments (a full segment shorter",
              "than %s m gets none); %s.streams_parent left as it was"),
        wsg, as.integer(n_ins), as.integer(seg$n_full), format(sliver_m), schema
      )
      stop(msg, call. = FALSE)
    }
  })

  sql <- sprintf(
    "SELECT count(*) AS n_rows, sum(overlap_m + straddle_m) / 1000 AS km,
            count(*) FILTER (WHERE straddle_m >= %1$s) AS n_straddle,
            coalesce(sum(straddle_m) FILTER (WHERE straddle_m >= %1$s), 0) / 1000 AS km_straddle,
            max(straddle_m) AS max_straddle_m
       FROM pg_temp.lnk_sp_parent",
    fmt(sliver_m)
  )
  out <- num(sql)
  res <- data.frame(wsg = wsg, n_full = seg$n_full, n_minimal = seg$n_minimal,
                    km = out$km, n_straddle = out$n_straddle,
                    km_straddle = out$km_straddle, max_straddle_m = out$max_straddle_m,
                    stringsAsFactors = FALSE)
  message(sprintf("%s: %d full segments on %d minimal, %.1f km, %d straddle (max %.2f m)",
                  wsg, as.integer(res$n_full), as.integer(res$n_minimal), res$km,
                  as.integer(res$n_straddle), res$max_straddle_m))
  invisible(res)
}
