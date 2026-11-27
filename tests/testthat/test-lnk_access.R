cfg_bcfp <- function() lnk_config("bcfishpass")
fake_conn <- function() structure(list(), class = "DBIConnection")

# The three arguments every call below shares. merge = FALSE returns straight
# after lnk_pipeline_access, which keeps these tests on the view-handling
# branch rather than dragging in the UPDATE path.
access_args <- function(...) {
  c(list(conn = fake_conn(), cfg = cfg_bcfp(), aoi = "PARS",
         table_streams  = "fresh.streams",
         table_barriers = "fresh.barriers",
         table_to       = "working_pars.streams_access",
         merge = FALSE, species = c("BT", "SK")),
    list(...))
}

test_that("build_views = TRUE (default) builds the views", {
  built <- 0L
  local_mocked_bindings(
    lnk_barriers_views = function(...) { built <<- built + 1L; invisible(NULL) },
    lnk_pipeline_access = function(...) invisible(NULL),
    .lnk_db_execute = function(conn, sql) invisible(NULL)
  )
  do.call(lnk_access, access_args())
  expect_equal(built, 1L)
})

test_that("build_views = FALSE skips the build when the views are present", {
  built <- 0L
  asked <- character(0)
  local_mocked_bindings(
    lnk_barriers_views = function(...) { built <<- built + 1L; invisible(NULL) },
    lnk_pipeline_access = function(...) invisible(NULL),
    .lnk_db_execute = function(conn, sql) invisible(NULL),
    .lnk_table_exists = function(conn, table) { asked <<- c(asked, table); TRUE }
  )
  do.call(lnk_access, access_args(build_views = FALSE))

  expect_equal(built, 0L)

  # It must verify the views it is about to READ, not an arbitrary subset --
  # the per-species _access views plus all three source _unified views.
  expect_setequal(
    asked,
    c("fresh.barriers_bt_access", "fresh.barriers_sk_access",
      "fresh.barriers_anthropogenic_unified",
      "fresh.barriers_pscis_unified",
      "fresh.barriers_dams_unified"))
})

test_that("build_views = FALSE errors, naming the absent views and the fix", {
  # The whole point of verifying rather than trusting: an absent view
  # otherwise fails deep inside the network walk with a bare "relation does
  # not exist", which under a fan-out reads as one WSG's [WARN].
  local_mocked_bindings(
    lnk_barriers_views = function(...) stop("must not be called"),
    lnk_pipeline_access = function(...) stop("must not be reached"),
    .lnk_db_execute = function(conn, sql) stop("must not be reached"),
    .lnk_table_exists = function(conn, table) !grepl("_sk_access$", table)
  )
  err <- tryCatch(do.call(lnk_access, access_args(build_views = FALSE)),
                  error = conditionMessage)

  expect_match(err, "fresh\\.barriers_sk_access")
  expect_match(err, "lnk_barriers_views")
  expect_match(err, "build_views = TRUE")
  # It must not blame a view that is present.
  expect_false(grepl("barriers_bt_access", err, fixed = TRUE))
})

test_that("build_views rejects non-logical values", {
  expect_error(do.call(lnk_access, access_args(build_views = NA)))
  expect_error(do.call(lnk_access, access_args(build_views = "no")))
  expect_error(do.call(lnk_access, access_args(build_views = c(TRUE, TRUE))))
})

test_that(".lnk_table_exists is TRUE for a VIEW, not only a table", {
  # The premise the build_views = FALSE guard rests on. If dbExistsTable were
  # false for views the guard would always fire and every recompute would
  # break -- loudly, but for a reason nobody would look for here. Asserted
  # against a real view so an RPostgres change fails by naming the cause.
  skip_if_no_db()
  conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "postgres")
  withr::defer(DBI::dbDisconnect(conn))

  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS zz_lnk_view_probe")
  withr::defer(
    try(DBI::dbExecute(conn, "DROP SCHEMA zz_lnk_view_probe CASCADE"),
        silent = TRUE))
  DBI::dbExecute(conn,
    "CREATE OR REPLACE VIEW zz_lnk_view_probe.v AS SELECT 1 AS a")

  expect_true(link:::.lnk_table_exists(conn, "zz_lnk_view_probe.v"))
  expect_false(link:::.lnk_table_exists(conn, "zz_lnk_view_probe.absent"))
})

test_that("the merge keeps an absent species' -9 (#351)", {
  # Every rollup counts access IN (1, 2) as accessible, so a -9 merged to 1
  # would reach accessible_km. Each row: recomputed (sc), persisted (t), wanted.
  skip_if_no_db()
  conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "postgres")
  withr::defer(DBI::dbDisconnect(conn))
  cases <- data.frame(
    sc   = c(-9L, -9L, -9L, 0L, 0L, 1L, 1L, 2L, 1L),
    t    = c(NA,  -9L, 2L,  2L, 1L, 2L, 1L, 1L, NA),
    want = c(-9L, -9L, -9L, 0L, 0L, 2L, 1L, 1L, 1L))
  expr <- link:::.lnk_access_merge_case("access_bt")
  got <- vapply(seq_len(nrow(cases)), function(i) {
    lit <- function(x) if (is.na(x)) "NULL::int" else as.character(x)
    DBI::dbGetQuery(conn, sprintf(
      "SELECT %s AS v FROM (VALUES (%s)) sc(access_bt), (VALUES (%s)) t(access_bt)",
      expr, lit(cases$sc[i]), lit(cases$t[i])))$v
  }, integer(1))
  expect_identical(got, cases$want)
})

test_that("merge = TRUE writes the -9 rule into every access column's UPDATE (#351)", {
  sql <- character(0)
  local_mocked_bindings(
    lnk_barriers_views = function(...) invisible(NULL),
    lnk_pipeline_access = function(...) invisible(NULL),
    .lnk_db_execute = function(conn, s) { sql <<- c(sql, s); invisible(NULL) }
  )
  local_mocked_bindings(
    dbGetQuery = function(conn, s, ...) {
      data.frame(column_name = c("id_segment", "access_bt", "access_sk",
                                 "has_barriers_bt_dnstr"))
    },
    dbQuoteString = function(conn, x, ...) paste0("'", x, "'"),
    dbQuoteLiteral = function(conn, x, ...) paste0("'", x, "'"),
    .package = "DBI"
  )
  do.call(lnk_access, utils::modifyList(access_args(), list(merge = TRUE)))
  upd <- grep("^UPDATE", sql, value = TRUE)
  expect_length(upd, 1L)
  for (col in c("access_bt", "access_sk")) {
    expect_true(grepl(sprintf("%s = CASE WHEN sc.%s = -9 THEN -9", col, col),
                      upd, fixed = TRUE))
  }
})
