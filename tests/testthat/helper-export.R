# Fixture persist schema for the habitat export (#308).
#
# Three real watershed groups, so the drainage lookup resolves: ADMS and LFRA
# drain to the Fraser (code 100), BULK to the Skeena (400). ADMS and BULK share
# id_segment 1 and 2, so a join on id_segment alone fans out. ADMS and LFRA
# modelled BT; BULK modelled CO and found none, so its CO rows read FALSE.
# streams_access covers ADMS only, as a build without mapping_code leaves it.
# Discharge comes from a fixture table, swapped in by mocking
# .lnk_discharge_tbl() and .lnk_discharge_rel().
local_export_fixture <- function(conn, env = parent.frame()) {
  schema <- paste0("lnk_test_export_", Sys.getpid())
  DBI::dbExecute(conn, "SET client_min_messages TO warning")
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema))
  withr::defer(
    DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema)),
    envir = env)
  link:::.lnk_log_create_tables(conn, schema)

  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.streams (
       id_segment integer, watershed_group_code varchar(4),
       linear_feature_id bigint, edge_type integer, blue_line_key integer,
       stream_order integer, channel_width double precision,
       channel_width_source text, gradient double precision,
       downstream_route_measure double precision,
       upstream_route_measure double precision, length_metre double precision,
       PRIMARY KEY (id_segment, watershed_group_code))", schema))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.streams VALUES
       (1, 'ADMS', 101, 1000, 10, 3, 4.0, 'MODELLED', 0.02,   0, 100, 100),
       (2, 'ADMS', 101, 1000, 10, 3, NULL, NULL,     0.20, 100, 250, 150),
       (1, 'BULK', 201, 1250, 20, 6, 30.0, 'MODELLED', 0.001,  0, 500, 500),
       (2, 'BULK', 202, 1000, 21, 2, 1.0, 'MODELLED', 0.05,   0,  80,  80),
       (1, 'LFRA', 301, 1000, 30, 4, 8.0, 'FIELD_MEASUREMENT', 0.01, 0, 40, 40)",
    schema))

  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.streams_habitat_bt (
       id_segment integer, watershed_group_code varchar(4),
       accessible boolean, spawning boolean, rearing boolean,
       lake_rearing boolean, wetland_rearing boolean,
       PRIMARY KEY (id_segment, watershed_group_code))", schema))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.streams_habitat_bt VALUES
       (1, 'ADMS', true,  true,  true,  false, false),
       (2, 'ADMS', true,  false, false, false, false),
       (1, 'LFRA', true,  false, true,  false, true)", schema))

  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.streams_habitat_co (LIKE %s.streams_habitat_bt
                                          INCLUDING ALL)", schema, schema))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.streams_habitat_co VALUES
       (1, 'BULK', false, false, false, false, false),
       (2, 'BULK', false, false, false, false, false)", schema))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.streams_access (
       id_segment integer, watershed_group_code varchar(4),
       has_barriers_bt_dnstr boolean, access_bt integer,
       PRIMARY KEY (id_segment, watershed_group_code))", schema))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.streams_access VALUES
       (1, 'ADMS', false, 1), (2, 'ADMS', true, 0)", schema))

  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.discharge (linear_feature_id bigint,
                                mad_m3s double precision)", schema))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.discharge VALUES (101, 0.5), (201, 40), (301, 0.02)",
    schema))

  # Thresholds logged for hash A only; hash B is a build from before #282.
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log_parameters_habitat_thresholds
       (config_hash, species_code, spawn_gradient_max, spawn_channel_width_min,
        spawn_mad_min, rear_gradient_max, rear_channel_width_min, rear_mad_min)
     VALUES ('sha256:A', 'BT', '0.05', '2', '0.25', '0.10', '', '0.02')",
    schema))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log_parameters_fresh (config_hash, species_code,
                                          access_gradient_max)
     VALUES ('sha256:A', 'BT', '0.25'), ('sha256:B', 'BT', '0.25')", schema))

  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log (run_id, watershed_group_code, date_start, date_end,
                         run_uid, host, config_name, config_hash,
                         discharge_fill, schema_persist, species, link_sha)
     VALUES
       ('r1', 'ADMS', '2026-10-01T00:00:00Z', '2026-10-01T01:00:00Z', 'U1',
        'h1', 'testcfg', 'sha256:A', false, '%1$s', '{BT}', 'abc'),
       ('r2', 'BULK', '2026-10-01T00:00:00Z', '2026-10-01T01:00:00Z', 'U1',
        'h1', 'testcfg', 'sha256:A', false, '%1$s', '{CO}', 'abc'),
       ('r0', 'LFRA', '2026-08-01T00:00:00Z', '2026-08-01T01:00:00Z', NULL,
        'h2', 'othercfg', 'sha256:B', NULL, '%1$s', '{BT}', 'old'),
       ('r3', 'LFRA', '2026-09-01T00:00:00Z', '2026-09-01T01:00:00Z', NULL,
        'h2', 'testcfg', 'sha256:B', NULL, '%1$s', '{BT}', 'def')",
    schema))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log_recompute (recompute_id, watershed_group_code,
                                   date_start, date_end, run_uid)
     VALUES ('rc1', 'ADMS', '2026-10-02T00:00:00Z', '2026-10-02T00:10:00Z', 'U1'),
            ('rc0', 'ADMS', '2026-09-02T00:00:00Z', '2026-09-02T00:10:00Z', NULL)",
    schema))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log_input (run_id, table_name) VALUES
       ('r1', 'whse_basemapping.fwa_stream_networks_sp'),
       ('r3', 'whse_basemapping.fwa_stream_networks_sp')", schema))

  schema
}

# Swap the export's discharge table for the fixture's.
local_export_discharge <- function(schema, env = parent.frame()) {
  testthat::local_mocked_bindings(
    .lnk_discharge_tbl = function(source = "fwapg") paste0(schema, ".discharge"),
    .lnk_discharge_rel = function(source = "fwapg") paste0(schema, ".discharge"),
    .package = "link", .env = env)
}

export_run <- function(conn, schema, wsg) {
  DBI::dbGetQuery(conn, sprintf(
    "SELECT * FROM %s.log WHERE watershed_group_code = $1
      ORDER BY date_start DESC LIMIT 1", schema), params = list(wsg))
}

read_parquet_duck <- function(path, sql = "SELECT * FROM read_parquet(%s, hive_partitioning = false)") {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbGetQuery(con, sprintf(sql, DBI::dbQuoteString(con, path)))
}

# A one-part export tree written without a database: synthetic rows in the
# column contract, a manifest from the export's own writer.
local_export_tree <- function(env = parent.frame(), n = 3L, config = "cfgx",
                              species = "BT", root = NULL) {
  if (is.null(root)) root <- withr::local_tempdir(.local_envir = env)
  cols <- link:::.lnk_export_cols()
  rows <- as.data.frame(lapply(cols, function(t) {
    switch(t, integer = seq_len(n), double = as.double(seq_len(n)) * 10,
           string = rep("ADMS", n), logical = rep(c(TRUE, FALSE), length.out = n))
  }), stringsAsFactors = FALSE)
  names(rows) <- names(cols)
  key <- sprintf("segment/config=%s/species=%s/part-100.parquet", config, species)
  link:::.lnk_parquet_write(rows, file.path(root, key))
  e <- link:::.lnk_file_entry(root, key)
  parts <- data.frame(key = key, dataset = "habitat/fwa/v1/segment",
                      config = config, species = species, code = "100",
                      drainage = "Fraser", wsgs = "ADMS", rows = n,
                      bytes = e$bytes, md5 = e$md5, stringsAsFactors = FALSE)
  link:::.lnk_manifest_write(root, parts, NULL,
                             list(list(config = config, runs = list())))
  root
}
