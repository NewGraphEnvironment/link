# Which groups' persisted barrier rows a group's downstream walk reads (#374,
# #465). The walk (lnk_pipeline_access() through lnk_barriers_views()) reads
# every group's `barriers` and `barrier_overrides` by position, not by group,
# so a group reads the rows of every group that holds one on its downstream
# path. This is the line rule of data-raw/recompute_deps.R, kept here so the
# recompute scheduler and the habitat export answer from one query.

#' Groups whose barrier rows a group's downstream walk can read (line rule)
#'
#' For every watershed group, every other group touching a blue line that
#' carries a code which is an ancestor of, or equal to, one of the group's own
#' codes. Complete by construction: gradient barriers are found along the whole
#' of every line a group touches and persisted under its own code, an override
#' is written at the group's own barrier positions, and every other barrier
#' source is filtered to the group's own segments. It errs wide (a group can be
#' listed whose rows lie upstream of the reader), because a walk that reads too
#' little cannot be told from a right one. The outlet closure
#' ([fresh::frs_wsg_drainage()]) is narrower than this and misses readers.
#'
#' FWA's unassigned codes (`999...`, construction lines) are left out: no
#' persisted segment carries one, and `999` is never an ancestor of a real code.
#' Reads FWA only (`whse_basemapping.fwa_stream_networks_sp`), never a persist
#' schema, so it answers the same before a run as after it. Province-wide it
#' takes about 70 s.
#'
#' @param conn DBI connection to a database holding FWA.
#' @param fwa Schema-qualified stream network table with
#'   `watershed_group_code`, `blue_line_key` and `wscode_ltree`. Tests pass a
#'   fixture.
#' @return A data frame with `wsg` (the reader) and `dep` (a group it reads),
#'   one row per pair, ordered by `wsg` then `dep` in `C` collation. A group
#'   with no dependency has no row.
#' @noRd
.lnk_wsg_deps_line <- function(conn,
                               fwa = "whse_basemapping.fwa_stream_networks_sp") {
  stopifnot(inherits(conn, "DBIConnection"),
            is.character(fwa), length(fwa) == 1L)
  .lnk_validate_identifier(fwa, "fwa")
  tmp <- c("lnk_deps_seg", "lnk_deps_anc", "lnk_deps_pathblk")
  drop <- function() {
    for (t in tmp) {
      DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS pg_temp.%s", t))
    }
  }
  drop()
  on.exit(drop(), add = TRUE)
  # Every segment, local code or not: the line rule needs none, and leaving
  # the 158,188 segments FWA gives no local code out dropped 52 pairs (#374).
  DBI::dbExecute(conn, sprintf("
    CREATE TEMP TABLE lnk_deps_seg AS
    SELECT watershed_group_code w, blue_line_key blk, wscode_ltree ws
    FROM %s
    WHERE watershed_group_code IS NOT NULL AND wscode_ltree IS NOT NULL
      AND NOT wscode_ltree ~ '999.*'::lquery", fwa))
  # Every ancestor-or-equal code of each group's codes.
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE lnk_deps_anc AS
    SELECT DISTINCT g.w, subpath(g.ws, 0, i) a
    FROM (SELECT DISTINCT w, ws FROM lnk_deps_seg) g,
         generate_series(1, nlevel(g.ws)) i")
  # Lines on the path, by blue_line_key, then every group touching them.
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE lnk_deps_pathblk AS
    SELECT DISTINCT a.w, s.blk
    FROM lnk_deps_anc a JOIN lnk_deps_seg s ON s.ws = a.a")
  DBI::dbExecute(conn, "CREATE INDEX ON lnk_deps_pathblk (blk)")
  line <- DBI::dbGetQuery(conn, "
    SELECT DISTINCT p.w::text AS wsg, t.w::text AS dep
    FROM lnk_deps_pathblk p
    JOIN (SELECT DISTINCT w, blk FROM lnk_deps_seg) t USING (blk)
    WHERE t.w <> p.w")
  # Nothing from FWA is a broken source (an empty or unpopulated table), not a
  # province with no dependencies: a reader would then fetch nothing.
  if (nrow(line) == 0L) {
    stop("FWA gave no line-rule dependency pairs; refusing an empty map",
         call. = FALSE)
  }
  # radix: a byte order, whatever the session's locale (a shipped table)
  line <- line[order(line$wsg, line$dep, method = "radix"), , drop = FALSE]
  rownames(line) <- NULL
  line
}
