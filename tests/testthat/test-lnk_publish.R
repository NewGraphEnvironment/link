# What stops a built habitat export from being published (#334).

clean_manifest <- function() {
  list(configs = list(list(
    config = "default",
    exported_by = list(link_dirty = FALSE),
    thresholds_logged = list(`sha256:A` = TRUE),
    runs = list(
      list(run_id = "r1", watershed_group_code = "ADMS", run_uid = "U1",
           link_dirty = FALSE, fresh_dirty = FALSE, config_hash = "sha256:A",
           recompute_keys = list()),
      list(run_id = "r2", watershed_group_code = "BULK", run_uid = "U1",
           link_dirty = FALSE, fresh_dirty = FALSE, config_hash = "sha256:A",
           recompute_keys = list())))))
}

test_that("a tree of named, clean, thresholded builds has no refusal", {
  expect_identical(.lnk_publish_refusals(clean_manifest(), tempdir()),
                   character(0))
  expect_null(.lnk_publish_gate(character(0)))
})

test_that("each kind of build a consumer cannot name or rebuild is refused", {
  m <- clean_manifest()
  m$configs[[1]]$runs[[1]]$run_uid <- NULL
  m$configs[[1]]$runs[[2]]$link_dirty <- TRUE
  m$configs[[1]]$runs[[2]]$fresh_dirty <- TRUE
  m$configs[[1]]$exported_by$link_dirty <- TRUE
  r <- .lnk_publish_refusals(m, tempdir())
  expect_true("default ADMS run r1: no run_uid" %in% r)
  expect_true("default BULK run r2: link_dirty" %in% r)
  expect_true("default BULK run r2: fresh_dirty" %in% r)
  expect_true("default: exported from a dirty link tree" %in% r)

  m <- clean_manifest()
  m$configs[[1]]$thresholds_logged$`sha256:A` <- FALSE
  r <- .lnk_publish_refusals(m, tempdir())
  expect_length(r, 2L)
  expect_match(r[1], "no thresholds logged at sha256:A")
  # a tree state that was not recorded is not a clean one
  m <- clean_manifest()
  m$configs[[1]]$runs[[1]]$link_dirty <- NULL
  m$configs[[1]]$exported_by$link_dirty <- NA
  r <- .lnk_publish_refusals(m, tempdir())
  expect_true("default ADMS run r1: link_dirty" %in% r)
  expect_true("default: exported from a dirty link tree" %in% r)
  # a run whose hash the manifest does not know is refused, not passed
  m <- clean_manifest()
  m$configs[[1]]$runs[[1]]$config_hash <- "sha256:Z"
  expect_match(.lnk_publish_refusals(m, tempdir()), "sha256:Z")
})

test_that("a recompute without a run_uid or from a dirty tree is refused", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  write_rc <- function(id, uid, dirty) {
    k <- paste0("provenance/recompute_id=", id)
    link:::.lnk_parquet_write(
      data.frame(recompute_id = id, run_uid = uid, link_dirty = dirty,
                 stringsAsFactors = FALSE),
      file.path(root, k, "log_recompute.parquet"))
    k
  }
  m <- clean_manifest()
  m$configs[[1]]$runs[[1]]$recompute_keys <- list(
    write_rc("rc1", "U1", FALSE), write_rc("rc2", NA_character_, TRUE))
  r <- .lnk_publish_refusals(m, root)
  expect_identical(r, c("default ADMS recompute rc2: no run_uid",
                        "default ADMS recompute rc2: link_dirty"))
  m$configs[[1]]$runs[[1]]$recompute_keys <- list("provenance/recompute_id=gone")
  expect_error(.lnk_publish_refusals(m, root), "missing")
})

test_that("refusals stop the publish unless a reason is given, which is kept", {
  expect_error(.lnk_publish_gate(c("a: no run_uid", "b: link_dirty")),
               "PUBLISH refused.*2 build")
  expect_error(.lnk_publish_gate("a: no run_uid", "   "), "PUBLISH refused")
  g <- .lnk_publish_gate("a: no run_uid", " test tree for the webmap ")
  expect_identical(g$reason, "test tree for the webmap")
  expect_identical(as.character(g$refusals), "a: no run_uid")
})
