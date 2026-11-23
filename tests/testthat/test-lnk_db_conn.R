test_that("lnk_db_conn returns a DBI connection when DB available", {
  conn <- skip_if_no_db()
  expect_s4_class(conn, "DBIConnection")
})

test_that("lnk_db_conn errors on bad host", {
  expect_error(
    lnk_db_conn(host = "nonexistent.invalid.host.example", port = 1L,
                connect_timeout = 2),
    class = "simpleError"
  )
})

# What reaches DBI::dbConnect, with the connection environment set as given
# and everything else about it cleared (#288).
conn_vars <- c("PGHOST", "PGHOSTADDR", "PGPORT", "PGDATABASE", "PGUSER",
               "PGSERVICE", "PGPASSWORD", "PGCONNECT_TIMEOUT",
               "PG_DB_SHARE", "PG_HOST_SHARE", "PG_PORT_SHARE",
               "PG_USER_SHARE", "PG_PASS_SHARE")
share_env <- c(PG_DB_SHARE = "sharedb", PG_HOST_SHARE = "sharehost",
               PG_PORT_SHARE = "63333", PG_USER_SHARE = "shareuser",
               PG_PASS_SHARE = "sharepass")
reset_share_msg <- function() {
  assign("share_msg_shown", FALSE,
         envir = utils::getFromNamespace(".frs_state", "fresh"))
}
connect_args <- function(env = character(0), ...) {
  unset <- stats::setNames(rep(NA_character_, length(conn_vars)), conn_vars)
  unset[names(env)] <- env
  withr::local_envvar(unset)
  got <- NULL
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      got <<- list(...)
      "conn"
    },
    .package = "DBI"
  )
  lnk_db_conn(...)
  got
}

test_that("explicit arguments win over both groups of variables", {
  got <- connect_args(c(share_env, PGHOST = "stdhost"),
                      dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "pw")
  expect_identical(got[c("dbname", "host", "port", "user", "password")],
                   list(dbname = "fwapg", host = "localhost", port = 5432L,
                        user = "postgres", password = "pw"))
})

test_that("with any PG* variable set, no PG_*_SHARE value reaches the call", {
  got <- connect_args(c(share_env, PGDATABASE = "stddb"))
  expect_false(any(c("sharedb", "sharehost", "63333", "shareuser", "sharepass")
                   %in% unlist(got)))
  expect_null(got$dbname)   # left for libpq to read from PGDATABASE
  # and a given field still rides with them
  got <- connect_args(c(share_env, PGHOST = "stdhost"), port = 5433L)
  expect_identical(got$port, 5433L)
  expect_null(got$host)
  expect_null(got$password)
})

test_that("PG_*_SHARE fills the fields not given only when no PG* is set", {
  reset_share_msg()
  expect_message(got <- connect_args(share_env, dbname = "fwapg"),
                 "PG_\\*_SHARE")
  expect_identical(got[c("dbname", "host", "port", "user", "password")],
                   list(dbname = "fwapg", host = "sharehost", port = "63333",
                        user = "shareuser", password = "sharepass"))
})

test_that("with no variables set, libpq's defaults apply", {
  got <- connect_args()
  expect_false(any(c("dbname", "host", "port", "user", "password")
                   %in% names(got)))
})

test_that("a fully explicit call says nothing of PG_*_SHARE", {
  reset_share_msg()
  expect_no_message(connect_args(share_env, dbname = "fwapg",
                                 host = "localhost", port = 5432L,
                                 user = "postgres", password = "postgres"))
  # The premise: a call that leaves a field to the environment does say it.
  reset_share_msg()
  expect_message(connect_args(share_env, dbname = "fwapg"), "PG_\\*_SHARE")
})

test_that("fresh's connection bounds reach the call", {
  got <- connect_args(dbname = "fwapg")
  expect_identical(got$connect_timeout, 10L)
  expect_identical(got$keepalives, 1L)
  got <- connect_args(dbname = "fwapg", connect_timeout = 30, keepalives = 0L)
  expect_identical(got$connect_timeout, 30L)
  expect_identical(got$keepalives, 0L)
})
