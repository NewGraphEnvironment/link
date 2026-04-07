setup_custom_table <- function(conn) {
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_custom")
  DBI::dbExecute(conn, "
    CREATE TABLE working.test_custom (
      id integer PRIMARY KEY,
      severity text,
      spawning_km numeric
    )")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_custom VALUES
      (1, 'high',     12.5),
      (2, 'moderate',  0.3),
      (3, 'low',       8.0),
      (4, 'high',      0.1)")
}

tbl_custom <- "working.test_custom"

teardown_custom <- function(conn) {
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_custom")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_custom_copy")
}

# --- Input validation ---

test_that("score_custom errors on empty rules", {
  conn <- skip_if_no_db()
  expect_error(lnk_score_custom(conn, tbl_custom, rules = list()), "non-empty")
})

test_that("score_custom errors on unnamed rules", {
  conn <- skip_if_no_db()
  expect_error(
    lnk_score_custom(conn, tbl_custom, rules = list(list(col = "x"))),
    "named list"
  )
})

test_that("score_custom errors on rule without col or sql", {
  conn <- skip_if_no_db()
  setup_custom_table(conn)
  on.exit(teardown_custom(conn))

  expect_error(
    lnk_score_custom(
      conn, tbl_custom, rules = list(bad = list(weight = 1)),
      verbose = FALSE
    ),
    "col.*sql"
  )
})

test_that("score_custom errors on bad weight", {
  conn <- skip_if_no_db()
  setup_custom_table(conn)
  on.exit(teardown_custom(conn))

  expect_error(
    lnk_score_custom(
      conn, tbl_custom,
      rules = list(r = list(col = "spawning_km", weight = -1)),
      verbose = FALSE
    ),
    "positive"
  )
})

# --- Scoring ---

test_that("score_custom computes weighted rank scores", {
  conn <- skip_if_no_db()
  setup_custom_table(conn)
  on.exit(teardown_custom(conn))

  lnk_score_custom(
    conn, tbl_custom, col_id = "id",
    rules = list(
      habitat = list(col = "spawning_km", weight = 1, direction = "higher")
    ),
    verbose = FALSE
  )

  r <- DBI::dbGetQuery(conn, paste(
    "SELECT id, priority_score FROM", tbl_custom, "ORDER BY id"
  ))
  # spawning_km DESC: 12.5(rank1), 8.0(rank2), 0.3(rank3), 0.1(rank4)
  # score = 1 * rank
  expect_equal(r$priority_score[r$id == 1], 1)  # best habitat
  expect_equal(r$priority_score[r$id == 4], 4)  # worst habitat
})

test_that("score_custom supports SQL expressions", {
  conn <- skip_if_no_db()
  setup_custom_table(conn)
  on.exit(teardown_custom(conn))

  sev_sql <- paste("CASE severity WHEN 'high' THEN 3",
                   "WHEN 'moderate' THEN 2 ELSE 1 END")
  rules <- list(
    sev_num = list(sql = sev_sql, weight = 1, direction = "higher")
  )
  lnk_score_custom(conn, tbl_custom, rules = rules, col_id = "id",
                   verbose = FALSE)

  r <- DBI::dbGetQuery(conn, paste(
    "SELECT id, priority_score FROM", tbl_custom, "ORDER BY id"
  ))
  # IDs 1,4 are high (3), ID 2 is moderate (2), ID 3 is low (1)
  # Rank DESC: high ties at rank 1, moderate rank 3, low rank 4
  expect_true(r$priority_score[r$id == 3] > r$priority_score[r$id == 1])
})

test_that("score_custom writes to new table", {
  conn <- skip_if_no_db()
  setup_custom_table(conn)
  on.exit(teardown_custom(conn))

  result <- lnk_score_custom(
    conn, tbl_custom, col_id = "id",
    rules = list(h = list(col = "spawning_km")),
    to = "working.test_custom_copy", verbose = FALSE
  )
  expect_equal(result, "working.test_custom_copy")

  orig_cols <- .lnk_table_columns(conn, tbl_custom)
  expect_false("priority_score" %in% orig_cols)

  copy_cols <- .lnk_table_columns(conn, "working.test_custom_copy")
  expect_true("priority_score" %in% copy_cols)
})

test_that("score_custom verbose reports distribution", {
  conn <- skip_if_no_db()
  setup_custom_table(conn)
  on.exit(teardown_custom(conn))

  rules <- list(h = list(col = "spawning_km"))
  expect_message(
    lnk_score_custom(conn, tbl_custom, rules = rules, col_id = "id"),
    "min:"
  )
})
