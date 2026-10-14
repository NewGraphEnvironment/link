# lnk_catalog() (#308)

test_that("a local manifest reads one row per part, hive fields from the key", {
  skip_if_not_installed("duckdb")
  root <- local_export_tree()
  cat <- lnk_catalog(file.path(root, "manifest.json"))
  expect_identical(nrow(cat), 1L)
  expect_identical(cat$config, "cfgx")
  expect_identical(cat$species, "BT")
  expect_identical(cat$code, "100")
  expect_identical(cat$href, file.path(root, cat$key))
  expect_identical(attr(cat, "id"), "habitat/fwa/v1")
  expect_identical(attr(cat, "configs")[[1]]$config, "cfgx")
})

test_that("a manifest with a bad md5, key or version is refused", {
  skip_if_not_installed("duckdb")
  root <- local_export_tree()
  mp <- file.path(root, "manifest.json")
  m <- jsonlite::fromJSON(mp, simplifyVector = FALSE)
  edit <- function(f) {
    x <- f(m)
    jsonlite::write_json(x, mp, auto_unbox = TRUE, null = "null")
  }
  edit(function(x) {
    x$parts[[1]]$md5 <- "nope"
    x
  })
  expect_error(lnk_catalog(mp), "no valid md5")
  edit(function(x) {
    x$parts[[1]]$key <- "segment/part-100.parquet"
    x
  })
  expect_error(lnk_catalog(mp), "not a habitat part key")
  edit(function(x) {
    x$parts[[1]]$key <- "segment/config=cfgx/species=bt/part-100.parquet"
    x
  })
  expect_error(lnk_catalog(mp), "not a habitat part key")
  edit(function(x) {
    x$manifest_version <- 2L
    x
  })
  expect_error(lnk_catalog(mp), "unsupported manifest_version")
  expect_error(lnk_catalog(file.path(root, "absent.json")), "no such file")
})

test_that("an s3:// manifest is read through aws, and parts resolve under it", {
  skip_if_not_installed("duckdb")
  root <- local_export_tree()
  calls <- list()
  local_mocked_bindings(.lnk_aws = function(args) {
    calls[[length(calls) + 1L]] <<- args
    file.copy(file.path(root, "manifest.json"),
              gsub("^'|'$", "", args[4]), overwrite = TRUE)
    character(0)
  })
  cat <- lnk_catalog("s3://fresh-bc/habitat/fwa/v1/manifest.json")
  expect_identical(calls[[1]][1:3],
                   c("s3", "cp", "'s3://fresh-bc/habitat/fwa/v1/manifest.json'"))
  expect_identical(cat$href, paste0("s3://fresh-bc/habitat/fwa/v1/", cat$key))
})

test_that("a failed aws copy stops with its exit status", {
  local_mocked_bindings(.lnk_aws = function(args) {
    structure("An error occurred (403) when calling the HeadObject operation",
              status = 1L)
  })
  expect_error(lnk_catalog("s3://fresh-bc/habitat/fwa/v1/manifest.json"),
               "exit 1.*403")
})

test_that("a bare manifest filename resolves parts beside it", {
  skip_if_not_installed("duckdb")
  root <- local_export_tree()
  withr::local_dir(root)
  cat <- lnk_catalog("manifest.json")
  expect_true(file.exists(cat$href))
})
