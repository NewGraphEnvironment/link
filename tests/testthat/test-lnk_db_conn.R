test_that("lnk_db_conn returns a DBI connection when DB available", {
  conn <- skip_if_no_db()
  expect_s4_class(conn, "DBIConnection")
})

test_that("lnk_db_conn reads PGDATABASE env var", {
  conn_check <- skip_if_no_db()
  DBI::dbDisconnect(conn_check)
  withr::with_envvar(c(PGDATABASE = "postgis"), {
    conn <- lnk_db_conn()
    on.exit(DBI::dbDisconnect(conn))
    expect_s4_class(conn, "DBIConnection")
  })
})

test_that("lnk_db_conn errors on bad host", {
  expect_error(
    lnk_db_conn(host = "nonexistent.invalid.host.example", port = 1L),
    class = "simpleError"
  )
})

test_that("lnk_db_conn accepts explicit parameters", {
  # Just test the function signature accepts all params without error
  # (actual connection tested by skip_if_no_db)
  expect_true(is.function(lnk_db_conn))
  args <- formals(lnk_db_conn)
  expect_true("dbname" %in% names(args))
  expect_true("host" %in% names(args))
  expect_true("port" %in% names(args))
  expect_true("user" %in% names(args))
  expect_true("password" %in% names(args))
})
