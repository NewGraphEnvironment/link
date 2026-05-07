test_that("lnk_bucket_get builds the URL from prefix + name and returns raw bytes", {
  fake_resp <- structure(
    list(status_code = 200L, content = charToRaw("hello,world\n1,2\n"),
         url = "https://example.com/bucket/csvs/example.csv",
         headers = list(`content-type` = "text/csv")),
    class = "response"
  )
  m <- mockery::mock(fake_resp)
  with_mocked_bindings(GET = m, .package = "httr", {
    bytes <- lnk_bucket_get("csvs/example.csv",
                            prefix = "https://example.com/bucket")
    expect_type(bytes, "raw")
    expect_equal(rawToChar(bytes), "hello,world\n1,2\n")
  })

  call_args <- mockery::mock_args(m)[[1]]
  expect_equal(call_args[[1]], "https://example.com/bucket/csvs/example.csv")
})

test_that("lnk_bucket_get strips trailing slash on prefix and leading slash on name", {
  fake_resp <- structure(
    list(status_code = 200L, content = charToRaw("ok"),
         url = "https://example.com/bucket/log.json",
         headers = list(`content-type` = "application/json")),
    class = "response"
  )
  m <- mockery::mock(fake_resp)
  with_mocked_bindings(GET = m, .package = "httr", {
    lnk_bucket_get("/log.json", prefix = "https://example.com/bucket/")
  })
  expect_equal(mockery::mock_args(m)[[1]][[1]],
               "https://example.com/bucket/log.json")
})

test_that("lnk_bucket_get fails loud on non-2xx response", {
  fake_resp <- structure(
    list(status_code = 404L, content = charToRaw("not found"),
         url = "https://example.com/bucket/missing.csv",
         headers = list(`content-type` = "text/plain")),
    class = "response"
  )
  m <- mockery::mock(fake_resp)
  with_mocked_bindings(GET = m, .package = "httr", {
    expect_error(
      lnk_bucket_get("missing.csv", prefix = "https://example.com/bucket"),
      "HTTP 404"
    )
  })
})

test_that("lnk_bucket_get with `to` writes to disk and returns the path", {
  out <- withr::local_tempfile(fileext = ".csv")
  fake_resp <- structure(list(status_code = 200L), class = "response")
  m <- mockery::mock({
    writeLines("a,b\n1,2", out)
    fake_resp
  })
  with_mocked_bindings(GET = m, .package = "httr", {
    res <- lnk_bucket_get("csvs/x.csv",
                          prefix = "https://example.com/bucket",
                          to = out)
    expect_equal(res, out)
    expect_true(file.exists(out))
  })
})

test_that("lnk_bucket_log fetches log.json, parses, validates required keys", {
  payload <- jsonlite::toJSON(list(
    model_version = "v0.7.14-125-g6e9cf1c",
    date_completed = "2026-05-06T04:15:41Z",
    head_sha = "6e9cf1c928ac01aae7e3aa5789ac9c29957e847b"
  ), auto_unbox = TRUE)
  fake_resp <- structure(
    list(status_code = 200L,
         content = charToRaw(as.character(payload)),
         url = "https://example.com/bucket/log.json",
         headers = list(`content-type` = "application/json")),
    class = "response"
  )
  m <- mockery::mock(fake_resp)
  with_mocked_bindings(GET = m, .package = "httr", {
    log <- lnk_bucket_log(prefix = "https://example.com/bucket")
  })
  expect_equal(log$model_version, "v0.7.14-125-g6e9cf1c")
  expect_equal(log$head_sha, "6e9cf1c928ac01aae7e3aa5789ac9c29957e847b")
  expect_equal(mockery::mock_args(m)[[1]][[1]],
               "https://example.com/bucket/log.json")
})

test_that("lnk_bucket_log fails loud when log.json is missing required keys", {
  payload <- jsonlite::toJSON(list(model_version = "vX.Y.Z"),
                              auto_unbox = TRUE)
  fake_resp <- structure(
    list(status_code = 200L,
         content = charToRaw(as.character(payload)),
         url = "https://example.com/bucket/log.json",
         headers = list(`content-type` = "application/json")),
    class = "response"
  )
  m <- mockery::mock(fake_resp)
  with_mocked_bindings(GET = m, .package = "httr", {
    expect_error(
      lnk_bucket_log(prefix = "https://example.com/bucket"),
      "missing required keys"
    )
  })
})
