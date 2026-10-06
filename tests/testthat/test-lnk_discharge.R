# -- the knob (no DB) ----------------------------------------------------------

test_that("default_tuned fills discharge; default and bcfishpass do not (#305)", {
  expect_true(link:::.lnk_discharge_fill(lnk_config("default_tuned")))
  expect_false(link:::.lnk_discharge_fill(lnk_config("default")))
  expect_false(link:::.lnk_discharge_fill(lnk_config("bcfishpass")))
  expect_false(link:::.lnk_discharge_fill(list(pipeline = list())))
})

test_that("the fill needs a scope; the raw table does not", {
  expect_error(link:::.lnk_discharge_sql(fill = TRUE), "wsg or lines")
  expect_error(link:::.lnk_discharge_sql(character(0), fill = TRUE),
               "at least one")
  raw <- link:::.lnk_discharge_sql(fill = FALSE)
  expect_match(raw, "fwa_stream_networks_discharge", fixed = TRUE)
  expect_false(grepl("LATERAL", raw, fixed = TRUE))
  sc <- link:::.lnk_discharge_sql("ADMS", fill = TRUE, lines = "SELECT 1")
  expect_match(sc, "s.watershed_group_code IN ('ADMS')", fixed = TRUE)
  expect_match(sc, "s.linear_feature_id IN (SELECT 1)", fixed = TRUE)
})

# -- against fwapg -------------------------------------------------------------

discharge_conn <- function(env = parent.frame()) {
  skip_if_no_db()
  conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "postgres")
  withr::defer(DBI::dbDisconnect(conn), envir = env)
  if (!DBI::dbExistsTable(conn, DBI::Id(schema = "whse_basemapping",
                                        table = "fwa_stream_networks_discharge"))) {
    testthat::skip("no fwa_stream_networks_discharge in this database")
  }
  conn
}

# One line of each fill tier, from the raw tables, independent of the builder.
discharge_cases <- function(conn) {
  DBI::dbGetQuery(conn,
    "SELECT
       (SELECT s.linear_feature_id
          FROM whse_basemapping.fwa_stream_networks_sp s
          LEFT JOIN whse_basemapping.fwa_stream_networks_discharge d
            ON d.linear_feature_id = s.linear_feature_id
         WHERE s.edge_type = 1250 AND d.linear_feature_id IS NULL
           AND EXISTS (
             SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp s2
               JOIN whse_basemapping.fwa_stream_networks_discharge d2
                 ON d2.linear_feature_id = s2.linear_feature_id
              WHERE s2.blue_line_key = s.blue_line_key
                AND s2.downstream_route_measure > s.downstream_route_measure
                AND d2.mad_m3s IS NOT NULL)
         ORDER BY s.linear_feature_id LIMIT 1) AS absent_up,
       (SELECT s.linear_feature_id
          FROM whse_basemapping.fwa_stream_networks_sp s
          JOIN whse_basemapping.fwa_stream_networks_discharge d
            ON d.linear_feature_id = s.linear_feature_id
         WHERE s.edge_type = 1000 AND d.mad_m3s IS NULL
         ORDER BY s.linear_feature_id LIMIT 1) AS null_1000,
       (SELECT s.linear_feature_id
          FROM whse_basemapping.fwa_stream_networks_sp s
          JOIN whse_basemapping.fwa_stream_networks_discharge d
            ON d.linear_feature_id = s.linear_feature_id
         WHERE s.edge_type = 1250 AND d.mad_m3s IS NOT NULL
         ORDER BY s.linear_feature_id LIMIT 1) AS valued_1250,
       (SELECT s.linear_feature_id
          FROM whse_basemapping.fwa_stream_networks_sp s
         WHERE s.blue_line_key = 359572281 AND s.edge_type = 1250
         ORDER BY s.downstream_route_measure LIMIT 1) AS beatton")
}

fill_of <- function(conn, lfid, ...) {
  DBI::dbGetQuery(conn, sprintf(
    "SELECT linear_feature_id, mad_m3s, mad_m3s_source FROM %s d",
    link:::.lnk_discharge_sql(fill = TRUE, lines = format(lfid,
                                                         scientific = FALSE),
                              ...)))
}

test_that("an absent edge 1250 line takes the nearest valued line upstream", {
  conn <- discharge_conn()
  k <- discharge_cases(conn)
  skip_if(is.na(k$absent_up), "no absent edge 1250 line with a valued line upstream")
  want <- DBI::dbGetQuery(conn, sprintf(
    "SELECT d2.mad_m3s
       FROM whse_basemapping.fwa_stream_networks_sp s
       JOIN whse_basemapping.fwa_stream_networks_sp s2
         ON s2.blue_line_key = s.blue_line_key
        AND s2.downstream_route_measure > s.downstream_route_measure
       JOIN whse_basemapping.fwa_stream_networks_discharge d2
         ON d2.linear_feature_id = s2.linear_feature_id
      WHERE s.linear_feature_id = %s AND d2.mad_m3s IS NOT NULL
      ORDER BY s2.downstream_route_measure LIMIT 1",
    format(k$absent_up, scientific = FALSE)))$mad_m3s
  got <- fill_of(conn, k$absent_up)
  expect_equal(nrow(got), 1L)
  expect_identical(got$mad_m3s_source, "fill_upstream")
  expect_identical(got$mad_m3s, want)
  # The value is the line's, whatever the scope that asked for it.
  w <- DBI::dbGetQuery(conn, sprintf(
    "SELECT watershed_group_code FROM whse_basemapping.fwa_stream_networks_sp
      WHERE linear_feature_id = %s",
    format(k$absent_up, scientific = FALSE)))$watershed_group_code
  by_wsg <- DBI::dbGetQuery(conn, sprintf(
    "SELECT mad_m3s FROM %s d WHERE d.linear_feature_id = %s",
    link:::.lnk_discharge_sql(w, fill = TRUE),
    format(k$absent_up, scientific = FALSE)))
  expect_identical(by_wsg$mad_m3s, want)
})

test_that("only edge 1250 is filled, and a valued line keeps its value", {
  conn <- discharge_conn()
  k <- discharge_cases(conn)
  skip_if(is.na(k$null_1000) || is.na(k$valued_1250), "no test lines")
  n <- fill_of(conn, k$null_1000)
  expect_true(is.na(n$mad_m3s))
  expect_true(is.na(n$mad_m3s_source))
  v <- fill_of(conn, k$valued_1250)
  raw <- DBI::dbGetQuery(conn, sprintf(
    "SELECT mad_m3s FROM whse_basemapping.fwa_stream_networks_discharge
      WHERE linear_feature_id = %s",
    format(k$valued_1250, scientific = FALSE)))$mad_m3s
  expect_identical(v$mad_m3s, raw)
  expect_identical(v$mad_m3s_source, "modelled")
})

test_that("a river with no value anywhere takes its largest upstream tributary", {
  conn <- discharge_conn()
  k <- discharge_cases(conn)
  skip_if(is.na(k$beatton), "no Beatton River in this database")
  got <- fill_of(conn, k$beatton)
  skip_if(!identical(got$mad_m3s_source, "fill_tributary_max"),
          "the Beatton has discharge in this database")
  want <- DBI::dbGetQuery(conn, sprintf(
    "SELECT max(d2.mad_m3s) AS m
       FROM whse_basemapping.fwa_stream_networks_sp s
       JOIN whse_basemapping.fwa_stream_networks_sp s2
         ON s2.wscode_ltree <@ s.wscode_ltree
        AND whse_basemapping.fwa_upstream(s.wscode_ltree, s.localcode_ltree,
                                          s2.wscode_ltree, s2.localcode_ltree)
        AND s2.blue_line_key <> s.blue_line_key
       JOIN whse_basemapping.fwa_stream_networks_discharge d2
         ON d2.linear_feature_id = s2.linear_feature_id
      WHERE s.linear_feature_id = %s",
    format(k$beatton, scientific = FALSE)))$m
  expect_identical(got$mad_m3s, want)
  # Never the receiving river: the Peace carries far more than any tributary.
  expect_lt(got$mad_m3s, 100)
})

test_that("the join writes double precision, and moves between fill states", {
  conn <- discharge_conn()
  k <- discharge_cases(conn)
  skip_if(is.na(k$absent_up), "no absent edge 1250 line")
  s <- "zz_lnk_discharge_probe"
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", s))
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", s)))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.streams AS
     SELECT linear_feature_id, watershed_group_code, edge_type
       FROM whse_basemapping.fwa_stream_networks_sp
      WHERE linear_feature_id IN (%s, %s)", s,
    format(k$absent_up, scientific = FALSE),
    format(k$valued_1250, scientific = FALSE)))
  aoi <- DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT watershed_group_code FROM %s.streams", s))[[1]]
  type_of <- function() {
    DBI::dbGetQuery(conn,
      "SELECT column_name, data_type FROM information_schema.columns
        WHERE table_schema = $1 AND table_name = 'streams'
          AND column_name IN ('mad_m3s', 'mad_m3s_source')
        ORDER BY column_name", params = list(s))$data_type
  }
  row_of <- function(lf) {
    DBI::dbGetQuery(conn, sprintf(
      "SELECT mad_m3s, mad_m3s_source FROM %s.streams
        WHERE linear_feature_id = %s", s, format(lf, scientific = FALSE)))
  }

  link:::.lnk_discharge_join(conn, paste0(s, ".streams"), aoi, fill = FALSE)
  expect_identical(type_of(), c("double precision", "text"))
  expect_true(is.na(row_of(k$absent_up)$mad_m3s))
  expect_identical(row_of(k$valued_1250)$mad_m3s_source, "modelled")

  link:::.lnk_discharge_join(conn, paste0(s, ".streams"), aoi, fill = TRUE)
  expect_identical(type_of(), c("double precision", "text"))
  expect_identical(row_of(k$absent_up)$mad_m3s_source, "fill_upstream")

  link:::.lnk_discharge_join(conn, paste0(s, ".streams"), aoi, fill = FALSE)
  expect_true(is.na(row_of(k$absent_up)$mad_m3s))
  expect_true(is.na(row_of(k$absent_up)$mad_m3s_source))
})

test_that("the fill applies only where something reads discharge", {
  # No shipped rules set a rule-level `mad`; a custom one does, in any YAML
  # style fresh parses (round-3 review: flow style beat a text grep).
  tuned0 <- lnk_config("default_tuned")
  expect_false(link:::.lnk_rules_read_mad(tuned0))
  txt <- readLines(tuned0$rules)
  i <- grep("^  - waterbody_type: R$", txt)[1]
  expect_identical(txt[i + 1:3], c("    channel_width:", "    - 0.0", "    - 9999.0"))
  y <- withr::local_tempfile(fileext = ".yaml")
  writeLines(c(txt[seq_len(i - 1)], "  - {waterbody_type: R, mad: [0.5, 9999]}",
               txt[-seq_len(i + 3)]), y)
  flow <- tuned0
  flow$rules <- y
  expect_true(link:::.lnk_rules_read_mad(flow))
  # ...and a filling bundle then fills even an all-cw group.
  expect_true(link:::.lnk_discharge_fill_applied(flow, "ADMS"))

  # default_tuned fills, but every group is cw: nothing is applied.
  tuned <- lnk_config("default_tuned")
  expect_false(link:::.lnk_discharge_fill_applied(tuned, c("ADMS", "UBTN")))
  # A group moved to mad is filled; the other group of the same call is not.
  csv <- withr::local_tempfile(fileext = ".csv")
  writeLines("watershed_group_code,model\nUBTN,mad", csv)
  tuned$files$parameters_habitat_method$path <- csv
  expect_true(link:::.lnk_discharge_fill_applied(tuned, "UBTN"))
  expect_false(link:::.lnk_discharge_fill_applied(tuned, "ADMS"))
  expect_true(link:::.lnk_discharge_fill_applied(tuned, c("ADMS", "UBTN")))
  # The knob off wins, whatever the model.
  tuned$pipeline$discharge_fill <- FALSE
  expect_false(link:::.lnk_discharge_fill_applied(tuned, "UBTN"))
  # Not applied anywhere: the raw relation, and no DB touched.
  expect_identical(
    link:::.lnk_hv_discharge_src("no-conn", "s", "ADMS", tuned),
    link:::.lnk_discharge_sql(fill = FALSE))
})

test_that("a group the discharge table does not cover is never filled", {
  conn <- discharge_conn()
  # An edge 1250 line in a group with no valued row; its upstream reaches
  # covered groups, so without the gate the tributary tier would fill it.
  lf <- DBI::dbGetQuery(conn,
    "SELECT s.linear_feature_id
       FROM whse_basemapping.fwa_stream_networks_sp s
      WHERE s.edge_type = 1250
        AND s.watershed_group_code NOT IN (
          SELECT watershed_group_code
            FROM whse_basemapping.fwa_stream_networks_discharge
           WHERE mad_m3s IS NOT NULL)
        AND EXISTS (
          SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp s2
            JOIN whse_basemapping.fwa_stream_networks_discharge d2
              ON d2.linear_feature_id = s2.linear_feature_id
           WHERE s2.blue_line_key = s.blue_line_key
             AND d2.mad_m3s IS NOT NULL)
      ORDER BY s.linear_feature_id LIMIT 1")$linear_feature_id
  skip_if(length(lf) == 0L, "no uncovered edge 1250 line beside a valued one")
  got <- fill_of(conn, lf)
  expect_true(is.na(got$mad_m3s))
  expect_true(is.na(got$mad_m3s_source))
})
