# Province-wide PSCIS snap, pick and CABD dam snap, for link#478 (#313, #314).
#
# Runs link's own code from --src (load_all) into scratch schema
# zz478_<label> on the local docker fwapg, then counts placeholder (999.*)
# candidates and picks, and exact-distance ties on one stream. Run once at
# the old code ("before") and once at the new ("after"); diff.R compares them.
#
#   Rscript data-raw/logs/snap_tie_478/snap_pick.R --label=before --src=<tree>
#
# Steps 1-4 of the PSCIS build (snap, score, dedup, pick) are province-wide;
# the AOI passed only filters Step 4b's `<schema>.pscis`, which this ignores.
# No `loaded`, so no xref overrides: the comparison is the snap and the pick.

args <- commandArgs(trailingOnly = TRUE)
arg <- function(k) {
  v <- sub(paste0("^--", k, "="), "", grep(paste0("^--", k, "="), args, value = TRUE))
  if (length(v) != 1L || !nzchar(v)) stop("--", k, "= is required", call. = FALSE)
  v
}
label <- arg("label")
src <- arg("src")
stopifnot(grepl("^[a-z]+$", label))
out <- file.path("data-raw/logs/snap_tie_478", label)
dir.create(out, showWarnings = FALSE, recursive = TRUE)

pkgload::load_all(src, quiet = TRUE)
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")
on_exit <- function() DBI::dbDisconnect(conn)
s <- paste0("zz478_", label)
DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", s))

t0 <- Sys.time()
link:::.lnk_pipeline_pscis_build(conn, aoi = "ADMS", schema = s)
# nearest-only snap, as the function's default
snap_args <- list(conn, "whse_fish.pscis_assessment_svw", paste0(s, ".pscis_snap1"),
                  snap_tolerance = 150, num_features = 1L)
if ("id_col" %in% names(formals(link::lnk_points_snap))) {
  snap_args$id_col <- "stream_crossing_id"
}
do.call(link::lnk_points_snap, snap_args)

# Dam snap: the shared CTEs, with no edit tables
none <- "(SELECT NULL::varchar AS cabd_id, NULL::integer AS blue_line_key,
                 NULL::integer AS passability_status_code WHERE false)"
DBI::dbExecute(conn, sprintf(
  "CREATE TABLE %s.dams_matched AS
   WITH cabd AS (%s), matched AS (%s)
   SELECT dam_id, linear_feature_id, blue_line_key, downstream_route_measure,
          wscode_ltree, localcode_ltree, watershed_group_code, distance_to_stream
   FROM matched",
  s,
  link:::.lnk_dams_cabd_sql(
    dams_expr = "(SELECT cabd_id, passability_status_code, dam_name_en,
                         height_m, owner, dam_use, operating_status,
                         ST_Transform(geom, 3005) AS geom FROM cabd.dams)",
    excl_ref = none, xref_ref = none, upd_ref = none),
  link:::.lnk_dams_matched_sql()))
secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

q <- function(sql) DBI::dbGetQuery(conn, sprintf(sql, s))
# A tie: two candidates of one point on one stream at exactly the same distance
tie_sql <- "
  SELECT count(DISTINCT c.%2$s) AS n
  FROM %1$s.%3$s c JOIN %1$s.%3$s d
    ON c.%2$s = d.%2$s AND c.%4$s = d.%4$s
   AND c.distance_to_stream = d.distance_to_stream
   AND c.linear_feature_id < d.linear_feature_id"
q2 <- function(tbl, id, blk) q(gsub("%2$s", id, gsub("%3$s", tbl, gsub("%4$s", blk,
  tie_sql, fixed = TRUE), fixed = TRUE), fixed = TRUE))$n

counts <- data.frame(
  label = label,
  src_sha = system2("git", c("-C", src, "rev-parse", "--short=8", "HEAD"), stdout = TRUE),
  # the code under R/ and inst/ that load_all() read, against that commit
  src_dirty = length(system2("git", c("-C", src, "status", "--porcelain",
                                      "--untracked-files=no", "--", "R", "inst",
                                      "DESCRIPTION"), stdout = TRUE)) > 0L,
  fresh = as.character(packageVersion("fresh")),
  pscis_rows = q("SELECT count(*) AS n FROM whse_fish.pscis_assessment_svw")$n,
  cand5_rows = q("SELECT count(*) AS n FROM %s.pscis_stream_candidates")$n,
  cand5_points = q("SELECT count(DISTINCT stream_crossing_id) AS n FROM %s.pscis_stream_candidates")$n,
  cand5_on_999 = q("SELECT count(*) AS n FROM %s.pscis_stream_candidates WHERE wscode_ltree <@ '999'::ltree")$n,
  cand5_points_tied = q2("pscis_stream_candidates", "stream_crossing_id", "snapped_blue_line_key"),
  snap1_rows = q("SELECT count(*) AS n FROM %s.pscis_snap1")$n,
  snap1_on_999 = q("SELECT count(*) AS n FROM %s.pscis_snap1 WHERE wscode_ltree <@ '999'::ltree")$n,
  picked_rows = q("SELECT count(*) AS n FROM %s.pscis_picked")$n,
  picked_on_999 = q("SELECT count(*) AS n FROM %s.pscis_picked WHERE wscode_ltree <@ '999'::ltree")$n,
  # picks whose point had a tied candidate on the picked stream
  picked_tied = q("
    SELECT count(*) AS n FROM %1$s.pscis_picked p
    WHERE EXISTS (SELECT 1 FROM %1$s.pscis_streams_150m a
                  WHERE a.stream_crossing_id = p.stream_crossing_id
                    AND a.blue_line_key = p.blue_line_key
                    AND a.distance_to_stream = p.distance_to_stream
                    AND a.linear_feature_id <> p.linear_feature_id)")$n,
  dams_rows = q("SELECT count(*) AS n FROM %s.dams_matched")$n,
  dams_on_999 = q("SELECT count(*) AS n FROM %s.dams_matched WHERE wscode_ltree <@ '999'::ltree")$n,
  seconds = round(secs, 1)
)
counts[] <- lapply(counts, function(x) if (inherits(x, "integer64")) as.numeric(x) else x)
utils::write.csv(counts, file.path(out, "counts.csv"), row.names = FALSE)
print(t(counts))
on_exit()
