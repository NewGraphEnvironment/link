# link's head-measure locates against fwapg#41's rework (link#383, #478).
#
# lnk_barriers_unify() locates stored measures with .lnk_sql_locate(), whose
# first arm is FWA_LocateAlong and whose fallback (nearest segment on the line)
# hides a miss; data-raw/query_habitat_thresholds_obs.R locates a record's
# upper point at its blue line's top when the record is within 100 m of it.
# Before the rework FWA_LocateAlong cannot place a measure at a stream's head:
# it compares bounds rounded to 4 decimals with the top open, so
# `round(us, 4) > round(us, 4)` is false by construction. These run against a
# database that has the rework or one trialled through LNK_FWAPG_TRIAL;
# otherwise they skip, naming the migration (helper-fwapg.R).

# Willow River, the blue line of #383's 08KD006 tie.
head_blk <- 356360570L

blk_top <- function(conn, blk) {
  DBI::dbGetQuery(conn, sprintf(
    "SELECT max(upstream_route_measure) AS m
     FROM whse_basemapping.fwa_stream_networks_sp WHERE blue_line_key = %d", blk))$m
}

# The head case as the property that makes it one, checked without the
# migration: no segment holds the measure under the old rounded, open-top
# rule, and one does under the closed top.
skip_unless_head_case <- function(conn, blk, m) {
  n <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*) FILTER (
              WHERE round(downstream_route_measure::numeric, 4) <= round(%1$.17g::numeric, 4)
                AND round(upstream_route_measure::numeric, 4) > round(%1$.17g::numeric, 4))::int AS old_rule,
            count(*) FILTER (
              WHERE round(downstream_route_measure::numeric, 4) <= round(%1$.17g::numeric, 4)
                AND round(upstream_route_measure::numeric, 4) >= round(%1$.17g::numeric, 4))::int AS closed
     FROM whse_basemapping.fwa_stream_networks_sp WHERE blue_line_key = %2$d", m, blk))
  skip_if_not(n$old_rule == 0L && n$closed >= 1L,
              sprintf("blue line %d at %.17g is not a head case on this database", blk, m))
}

first_arm <- function(conn, blk, m) {
  DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM FWA_LocateAlong(%d, %.17g)", blk, m))$n
}

test_that("a stored measure at a stream's head is located by FWA_LocateAlong itself", {
  conn <- local_fwapg_current()
  m <- blk_top(conn, head_blk)
  skip_if(is.na(m), sprintf("blue line %d is not on this database", head_blk))
  skip_unless_head_case(conn, head_blk, m)

  # The red side, on a second connection with no trial: committed state.
  plain <- local_fwapg()
  if (!lnk_indexpoint_current(plain)) {
    expect_identical(first_arm(plain, head_blk, m), 0L)
  }
  expect_identical(first_arm(conn, head_blk, m), 1L)

  # .lnk_sql_locate() places it either way (its fallback hid the miss), and
  # FWA_LocateAlong now gives the same point, the line's top vertex.
  got <- DBI::dbGetQuery(conn, sprintf(
    "SELECT ST_Distance(%s, (SELECT ST_Force2D(l.geom) FROM FWA_LocateAlong(%d, %.17g) l LIMIT 1)) AS d",
    link:::.lnk_sql_locate(as.character(head_blk), sprintf("%.17g", m)), head_blk, m))$d
  expect_lt(got, 0.001)
})

test_that("the threshold script's upper locate finds a point at the blue line's top", {
  conn <- local_fwapg_current()
  m <- blk_top(conn, head_blk)
  skip_if(is.na(m), sprintf("blue line %d is not on this database", head_blk))
  skip_unless_head_case(conn, head_blk, m)
  # the script's form: LEFT JOIN LATERAL fwa_locatealong(blk, least(m + 100, top))
  z <- DBI::dbGetQuery(conn, sprintf(
    "SELECT st_z(u.geom) AS z FROM (SELECT %d AS blk, %.17g AS m_up) b
     LEFT JOIN LATERAL whse_basemapping.fwa_locatealong(b.blk, b.m_up) u ON true",
    head_blk, m))$z
  expect_false(is.na(z))
})

# -- the gate ------------------------------------------------------------------

# FAILS rather than skips when LNK_FWAPG_CURRENT says the database should be
# current. Its own direct connection, reading committed state: never
# skip_if_no_db(), local_fwapg_current() or a trial's connection, so neither an
# unreachable database, a stale one nor a rolled-back trial can pass it.
test_that("LNK_FWAPG_CURRENT=true means the database really is current", {
  skip_if_not(lnk_fwapg_current_wanted(),
              "LNK_FWAPG_CURRENT is not set: nothing is claimed about this database")
  conn <- lnk_fwapg_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  args <- DBI::dbGetQuery(conn,
    "SELECT pg_get_function_arguments('whse_basemapping.fwa_indexpoint'::regproc) AS a")$a
  expect_match(paste(args, collapse = " "), "include_disconnected")
})

test_that("LNK_FWAPG_CURRENT refuses a value that is neither true nor false", {
  withr::local_envvar(LNK_FWAPG_CURRENT = "true ")
  expect_true(lnk_fwapg_current_wanted())
  withr::local_envvar(LNK_FWAPG_CURRENT = "maybe")
  expect_error(lnk_fwapg_current_wanted(), "neither true nor false")
  withr::local_envvar(LNK_FWAPG_CURRENT = "")
  expect_false(lnk_fwapg_current_wanted())
})
