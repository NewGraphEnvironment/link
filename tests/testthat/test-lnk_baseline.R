test_that("lnk_baseline_append creates the file with canonical header on first call", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  log <- list(
    model_version = "v0.7.14-125-g6e9cf1c",
    date_completed = "2026-05-06T04:15:41Z",
    head_sha = "6e9cf1c928ac01aae7e3aa5789ac9c29957e847b"
  )
  lnk_baseline_append(log, run_label = "csv-sync-20260507", path = tmp)

  expect_true(file.exists(tmp))
  lines <- readLines(tmp)
  expect_length(lines, 2L)
  expect_equal(strsplit(lines[1], ",")[[1]],
               c("run_started_pdt", "host", "run_label", "link_schema",
                 "bcfp_model_run_id", "bcfp_model_version",
                 "bcfp_date_completed", "notes"))
})

test_that("lnk_baseline_append appends without rewriting the header", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  log <- list(model_version = "vA", date_completed = "2026-01-01")
  lnk_baseline_append(log, run_label = "first", path = tmp)
  lnk_baseline_append(log, run_label = "second", path = tmp)

  lines <- readLines(tmp)
  expect_length(lines, 3L)  # header + 2 rows
  expect_match(lines[2], "first")
  expect_match(lines[3], "second")
})

test_that("lnk_baseline_append populates bcfp_model_run_id when log has it", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  log <- list(model_version = "vA", date_completed = "2026-01-01",
              model_run_id = 121)
  lnk_baseline_append(log, run_label = "with-id", path = tmp)

  df <- lnk_baseline_read(tmp)
  expect_equal(df$bcfp_model_run_id, "121")
})

test_that("lnk_baseline_append leaves bcfp_model_run_id empty when log lacks it (Path 2)", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  log <- list(model_version = "vA", date_completed = "2026-01-01")
  lnk_baseline_append(log, run_label = "no-id", path = tmp)

  df <- lnk_baseline_read(tmp)
  expect_equal(df$bcfp_model_run_id, "")
})

test_that("lnk_baseline_append fails loud on column-shape drift in existing file", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  writeLines(c("wrong,header,shape", "x,y,z"), tmp)
  log <- list(model_version = "vA", date_completed = "2026-01-01")
  expect_error(
    lnk_baseline_append(log, run_label = "x", path = tmp),
    "column shape mismatch"
  )
})

test_that("lnk_baseline_append CSV-quotes notes containing commas", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  log <- list(model_version = "vA", date_completed = "2026-01-01")
  lnk_baseline_append(log, run_label = "x",
                      notes = "head_sha=abc, model_run_id=121",
                      path = tmp)
  df <- lnk_baseline_read(tmp)
  expect_equal(df$notes, "head_sha=abc, model_run_id=121")
})

test_that("lnk_baseline_read errors when file is missing", {
  tmp <- withr::local_tempfile(fileext = ".csv")  # not created
  expect_error(lnk_baseline_read(tmp), "file not found")
})

test_that("lnk_baseline_read errors on shape drift", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  writeLines(c("a,b,c", "1,2,3"), tmp)
  expect_error(lnk_baseline_read(tmp), "column shape mismatch")
})
