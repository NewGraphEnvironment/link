# lnk_aggregate() sums each species' habitat upstream of each crossing over
# the network (link#321). The live test builds a two-table persist schema on
# real FWA segments around one tributary junction, with habitat set by hand,
# so every expected km is a sum of known segment lengths.

test_that("lnk_aggregate validates its arguments before touching the database", {
  conn <- structure(list(), class = "DBIConnection")
  expect_error(lnk_aggregate(conn, "a.b", "Fresh", "a.c", "default"),
               "lower-case schema")
  expect_error(lnk_aggregate(conn, "a.b", "fresh", "a.c", ""),
               "non-empty string")
  expect_error(lnk_aggregate(conn, "a.b", "fresh", "a.c", NA_character_),
               "non-empty string")
  expect_error(lnk_aggregate(conn, "a b", "fresh", "a.c", "default"))
})

test_that("the metrics are exact numeric sums, rearing split by polygon", {
  m <- link:::.lnk_aggregate_metrics()
  expect_identical(names(m), c("spawning_km", "rearing_km", "rearing_stream_km",
                               "rearing_lake_km", "rearing_wetland_km",
                               "rearing_lake_connection_km"))
  expect_true(all(grepl("sum(f.length_metre::numeric)", m, fixed = TRUE)))
  expect_match(m[["rearing_km"]], "NOT f.connection", fixed = TRUE)
  expect_match(m[["rearing_lake_connection_km"]], "AND f.connection", fixed = TRUE)
})

test_that("lnk_aggregate counts tributaries, not the main stem below, and stops at barriers", {
  conn <- skip_if_no_db()
  has <- DBI::dbGetQuery(conn,
    "SELECT to_regclass('whse_basemapping.fwa_stream_networks_sp') IS NOT NULL AS f")$f
  skip_if(!isTRUE(has), "no FWA streams")
  s <- "zz_test_agg478"
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s)))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", s))

  # One junction: tributary t's first segment, the main stem's segment just
  # above the junction (up) and just below it (dn), and the one below that.
  j <- DBI::dbGetQuery(conn, "
    WITH t AS (
      SELECT * FROM whse_basemapping.fwa_stream_networks_sp
       WHERE watershed_group_code = 'ADMS' AND downstream_route_measure = 0
         AND edge_type = 1000 AND nlevel(wscode_ltree) >= 3
         AND localcode_ltree IS NOT NULL
       ORDER BY linear_feature_id LIMIT 500)
    SELECT t.linear_feature_id AS t_id, up.linear_feature_id AS up_id,
           dn.linear_feature_id AS dn_id, dn2.linear_feature_id AS dn2_id
      FROM t
      JOIN whse_basemapping.fwa_stream_networks_sp up
        ON up.localcode_ltree = t.wscode_ltree
       AND up.wscode_ltree = subpath(t.wscode_ltree, 0, nlevel(t.wscode_ltree) - 1)
       AND up.edge_type = 1000
      JOIN whse_basemapping.fwa_stream_networks_sp dn
        ON dn.blue_line_key = up.blue_line_key AND dn.edge_type = 1000
       AND abs(dn.upstream_route_measure - up.downstream_route_measure) < 0.01
       AND dn.localcode_ltree < t.wscode_ltree
      JOIN whse_basemapping.fwa_stream_networks_sp dn2
        ON dn2.blue_line_key = up.blue_line_key AND dn2.edge_type = 1000
       AND abs(dn2.upstream_route_measure - dn.downstream_route_measure) < 0.01
     ORDER BY t.linear_feature_id LIMIT 1")
  skip_if(nrow(j) == 0L, "no simple junction in ADMS on this database")
  ids <- c(t = j$t_id, up = j$up_id, dn = j$dn_id, dn2 = j$dn2_id)

  DBI::dbExecute(conn, sprintf("
    CREATE TABLE %s.streams AS
    SELECT row_number() OVER (ORDER BY linear_feature_id)::int AS id_segment,
           watershed_group_code, linear_feature_id, edge_type, blue_line_key,
           waterbody_key, wscode_ltree, localcode_ltree,
           downstream_route_measure, upstream_route_measure, length_metre
      FROM whse_basemapping.fwa_stream_networks_sp
     WHERE linear_feature_id IN (%s)", s, paste(ids, collapse = ", ")))
  # spawning below the crossing (dn2, dn) and on the main stem above (up);
  # rearing on the tributary (t)
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE %1$s.streams_habitat_bt AS
    SELECT id_segment, watershed_group_code,
           true AS accessible,
           linear_feature_id IN (%2$s, %3$s, %4$s) AS spawning,
           linear_feature_id = %5$s AS rearing,
           false AS lake_rearing, false AS wetland_rearing
      FROM %1$s.streams", s, ids[["dn2"]], ids[["dn"]], ids[["up"]], ids[["t"]]))
  len <- DBI::dbGetQuery(conn, sprintf(
    "SELECT linear_feature_id, length_metre::numeric AS l, downstream_route_measure AS ds,
            blue_line_key
       FROM %s.streams", s))
  L <- stats::setNames(len$l, as.character(len$linear_feature_id))
  ds_up <- len$ds[len$linear_feature_id == ids[["up"]]]
  ds_dn <- len$ds[len$linear_feature_id == ids[["dn"]]]
  blk <- len$blue_line_key[len$linear_feature_id == ids[["up"]]]

  # Crossing 1 on dn, between dn's start and the junction; crossing 2 on an
  # unrelated stream (nothing upstream); two barriers on up just above the
  # junction, 0.5 m apart (3, also a crossing, below 4). Within 1 m each is
  # upstream of the other under fwa_upstream's tolerance.
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE %1$s.crossings AS
    SELECT * FROM (VALUES
      (1, %2$d, %3$.17g::double precision),
      (2, 360886221, 10::double precision),
      (3, %2$d, %4$.17g::double precision)) v(aggregated_crossings_id, blue_line_key,
                                               downstream_route_measure)",
    s, as.integer(blk), ds_dn + 2, ds_up + 0.5))
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE %1$s.barriers AS
    SELECT * FROM (VALUES (3, %2$d, %3$.17g::double precision),
                          (4, %2$d, %4$.17g::double precision))
      v(barriers_anthropogenic_id, blue_line_key, downstream_route_measure)",
    s, as.integer(blk), ds_up + 0.5, ds_up + 1))

  suppressMessages(lnk_aggregate(conn, paste0(s, ".crossings"), schema = s,
                                 to = paste0(s, ".up"), config = "test",
                                 barriers = paste0(s, ".barriers")))
  got <- DBI::dbGetQuery(conn, sprintf(
    "SELECT aggregated_crossings_id AS id, config, species_code, spawning_km,
            rearing_km, rearing_stream_km, spawning_belowupstrbarriers_km,
            rearing_belowupstrbarriers_km
       FROM %s.up ORDER BY 1", s))
  num <- function(x) as.numeric(x)
  expect_identical(got$id, c(1L, 2L, 3L))
  expect_identical(unique(got$config), "test")
  expect_identical(unique(got$species_code), "BT")

  # 1: the main stem above (up) and the tributary (t) count; dn, which
  # starts below the crossing, and dn2 do not
  expect_equal(num(got$spawning_km[1]), num(L[[as.character(ids[["up"]])]]) / 1000)
  expect_equal(num(got$rearing_km[1]), num(L[[as.character(ids[["t"]])]]) / 1000)
  expect_equal(num(got$rearing_stream_km[1]), num(got$rearing_km[1]))
  # below the barriers: up's spawning is upstream of barrier 3 (within 1 m
  # of its start), the tributary joins below it. Only barrier 3 is
  # immediate: 4 lies above it, so up is subtracted once
  expect_equal(num(got$spawning_belowupstrbarriers_km[1]), 0)
  expect_equal(num(got$rearing_belowupstrbarriers_km[1]), num(got$rearing_km[1]))
  # 2: nothing upstream, zeros not a missing row
  expect_equal(num(unlist(got[2, 4:8])), rep(0, 5))
  # 3, the lower barrier: up only; barrier 4, 0.5 m above it, holds up too,
  # so nothing lies between them
  expect_equal(num(got$spawning_km[3]), num(L[[as.character(ids[["up"]])]]) / 1000)
  expect_equal(num(got$rearing_km[3]), 0)
  expect_equal(num(got$spawning_belowupstrbarriers_km[3]), 0)
  expect_true(all(num(unlist(got[, 7:8])) >= 0))
})

test_that("lnk_aggregate refuses a crossing id that is not unique", {
  conn <- skip_if_no_db()
  s <- "zz_test_agg478b"
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s)))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", s))
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s.streams (id_segment int, watershed_group_code text)", s))
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s.streams_habitat_bt (id_segment int, watershed_group_code text, spawning bool, rearing bool)", s))
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s.crossings AS SELECT * FROM (VALUES (1, 1, 1.0::float8), (1, 1, 2.0::float8)) v(aggregated_crossings_id, blue_line_key, downstream_route_measure)", s))
  expect_error(lnk_aggregate(conn, paste0(s, ".crossings"), s, paste0(s, ".up"), "test"),
               "not unique")
})
