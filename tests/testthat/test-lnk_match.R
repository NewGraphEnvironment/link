test_that("lnk_match breaks distance ties on the other side's id (link#367)", {
  # DISTINCT ON keeps the first row per id; at equal distance, without a
  # final key, which match survives depends on row order.
  src <- paste(deparse(lnk_match), collapse = "\n")
  expect_match(src, "raw ORDER BY id_a, distance_m, id_b", fixed = TRUE)
  expect_match(src, "best_a ORDER BY id_b, distance_m, id_a", fixed = TRUE)
})
