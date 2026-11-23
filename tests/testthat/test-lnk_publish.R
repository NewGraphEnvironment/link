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

# ---- The pool and the listings (link#488) ------------------------------------

# A stub `aws` (Python, so it can time calls to the millisecond on macOS) that
# keeps a local directory as the bucket; see fixtures/publish_488/aws.
stub_aws <- function(env = parent.frame(), sleep = "0") {
  skip_if(!nzchar(Sys.which("python3")), "python3 not on PATH")
  d <- withr::local_tempdir(.local_envir = env)
  bin <- file.path(d, "bin")
  dir.create(bin)
  file.copy(testthat::test_path("fixtures", "publish_488", "aws"), bin)
  Sys.chmod(file.path(bin, "aws"), "755")
  dir.create(file.path(d, "store"))
  withr::local_envvar(PATH = paste(bin, Sys.getenv("PATH"), sep = ":"),
                      STUB_DIR = d, STUB_SLEEP = sleep, .local_envir = env)
  d
}

stub_log <- function(d) {
  f <- file.path(d, "log.jsonl")
  if (!file.exists(f)) return(data.frame())
  do.call(rbind, lapply(readLines(f), function(l) {
    x <- jsonlite::fromJSON(l)
    data.frame(op = x$op, key = x$key %||% NA_character_, start = x$start,
               end = x$end, rc = x$rc, inflight = x$inflight %||% NA_integer_,
               stringsAsFactors = FALSE)
  }))
}

test_that("LNK_PUBLISH_JOBS is a whole number from 1 to 64, 8 when unset", {
  expect_identical(.lnk_publish_jobs(""), 8L)
  expect_identical(.lnk_publish_jobs("3"), 3L)
  for (x in c("0", "65", "2.5", "-1", "eight", " 4")) {
    expect_error(.lnk_publish_jobs(x), "LNK_PUBLISH_JOBS", info = x)
  }
})

test_that("the pool runs calls at most `jobs` at once and checks every result", {
  d <- stub_aws(sleep = "0.4")
  f <- file.path(d, "x.txt")
  writeLines("x", f)
  md5 <- unname(tools::md5sum(f))
  calls <- lapply(sprintf("k/%02d", 1:8), function(k)
    .lnk_publish_put_call("b", k, f, "text/plain", md5))
  res <- .lnk_publish_run(calls, jobs = 3L)
  expect_length(res, 8L)
  lg <- stub_log(d)
  expect_identical(sort(lg$key), sprintf("k/%02d", 1:8))
  expect_lte(max(lg$inflight), 3L)
  expect_gte(max(lg$inflight), 2L)
  # results come back in the order of the calls, each with its reply's version
  v <- vapply(res, .lnk_publish_put_version, character(1))
  versions <- jsonlite::fromJSON(file.path(d, "versions.json"))
  expect_identical(v, unname(unlist(versions[sprintf("k/%02d", 1:8)])))
})

test_that("one failed call stops the pool, naming it, after every call has returned", {
  d <- stub_aws(sleep = "0.2")
  withr::local_envvar(STUB_FAIL_KEY = "k/03")
  f <- file.path(d, "x.txt")
  writeLines("x", f)
  calls <- lapply(sprintf("k/%02d", 1:5), function(k)
    .lnk_publish_put_call("b", k, f, "text/plain", unname(tools::md5sum(f))))
  expect_error(.lnk_publish_run(calls, jobs = 2L), "1 of 5 aws call\\(s\\) failed:\n  put k/03")
  expect_identical(nrow(stub_log(d)), 5L)
})

test_that("a put reply with no VersionId is refused", {
  expect_error(.lnk_publish_put_version(list(label = "put a/b", out = "None\t\"x\"")),
               "a/b has no VersionId")
  expect_error(.lnk_publish_put_version(list(label = "put a/b", out = character(0))),
               "no VersionId")
  expect_identical(.lnk_publish_put_version(list(label = "put a/b", out = c("", "v1\t\"x\""))),
                   "v1")
})

test_that("a listing reads every row, and an empty one is empty", {
  d <- stub_aws()
  expect_length(.lnk_publish_list("b", "p/", "etag"), 0L)
  dir.create(file.path(d, "store", "p", "q"), recursive = TRUE)
  writeLines("a", file.path(d, "store", "p", "q", "one"))
  writeLines("b", file.path(d, "store", "p", "two"))
  e <- .lnk_publish_list("b", "p/", "etag")
  expect_identical(names(e), c("p/q/one", "p/two"))
  expect_identical(unname(e), unname(tools::md5sum(file.path(d, "store", c("p/q/one", "p/two")))))
})

# ---- PUBLISH end to end, on the stub (link#488) ------------------------------

publish_script <- function() {
  p <- normalizePath(testthat::test_path("..", "..", "data-raw", "habitat_publish.R"),
                     mustWork = FALSE)
  skip_if_not(file.exists(p), "data-raw/habitat_publish.R absent")
  p
}

# A tree of n_parts parts and n_gp per-group parts, all copies of one part
# file under other keys, with the manifest's entries to match.
publish_tree <- function(env = parent.frame(), n_parts = 6L, n_gp = 4L) {
  root <- local_export_tree(env = env)
  mp <- file.path(root, "manifest.json")
  m <- jsonlite::fromJSON(mp, simplifyVector = FALSE)
  p0 <- m$parts[[1]]
  copy_to <- function(key) {
    dir.create(dirname(file.path(root, key)), recursive = TRUE, showWarnings = FALSE)
    file.copy(file.path(root, p0$key), file.path(root, key))
  }
  sp <- c("CH", "CO", "SK", "ST", "RB", "WCT", "GR", "KO")
  for (i in seq_len(n_parts - 1L)) {
    p <- p0
    p$species <- sp[i]
    p$key <- sprintf("segment/config=cfgx/species=%s/part-100.parquet", sp[i])
    copy_to(p$key)
    m$parts[[length(m$parts) + 1L]] <- p
  }
  m$group_parts <- lapply(seq_len(n_gp), function(i) {
    k <- sprintf("barriers/config=cfgx/watershed_group_code=G%d/part.parquet", i)
    copy_to(k)
    list(key = k, config = "cfgx", watershed_group_code = sprintf("G%d", i),
         bytes = p0$bytes, md5 = p0$md5)
  })
  jsonlite::write_json(m, mp, auto_unbox = TRUE, pretty = TRUE, digits = NA,
                       null = "null", na = "null")
  root
}

run_publish <- function(root, jobs = "3") {
  script <- publish_script()
  out <- withr::with_envvar(
    c(LNK_PUBLISH = "1", LNK_PUBLISH_ALLOW = "a test tree", LNK_PUBLISH_JOBS = jobs),
    withr::with_dir(dirname(dirname(script)), suppressWarnings(system2(
      file.path(R.home("bin"), "Rscript"),
      c(script, paste0("--root=", root), "--target=s3://stub-bkt/habitat/fwa/v1"),
      stdout = TRUE, stderr = TRUE))))
  list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L)
}

test_that("PUBLISH puts every part on the pool and the manifest only after them all", {
  publish_script()
  d <- stub_aws(sleep = "0.3")
  root <- publish_tree()
  r <- run_publish(root)
  expect_equal(r$status, 0L, info = r$out)
  lg <- stub_log(d)
  puts <- lg[lg$op == "put-object", ]
  man <- puts[puts$key == "habitat/fwa/v1/manifest.json", ]
  rest <- puts[puts$key != "habitat/fwa/v1/manifest.json", ]
  expect_identical(nrow(man), 1L)
  expect_identical(nrow(rest), 10L)
  expect_gt(man$start, max(rest$end))
  expect_lte(max(rest$inflight), 3L)
  expect_gte(max(rest$inflight), 2L)
  # no head-object per key: one for the live manifest, none for parts
  expect_identical(sum(lg$op == "head-object"), 1L)
  # the manifest names each part's version as the stub answered its put
  versions <- jsonlite::fromJSON(file.path(d, "versions.json"))
  pub <- jsonlite::fromJSON(file.path(d, "store", "habitat/fwa/v1/manifest.json"),
                            simplifyVector = FALSE)
  for (p in c(pub$parts, pub$group_parts)) {
    expect_identical(p$version_id, versions[[paste0("habitat/fwa/v1/", p$key)]], info = p$key)
  }
  expect_match(r$out, "put 0 new files, 6 parts, 4 of 4 per-group parts \\(3 at once\\)")
  expect_match(r$out, "min in all")
})

test_that("a second PUBLISH skips unchanged per-group parts and names their versions from a listing", {
  publish_script()
  d <- stub_aws()
  root <- publish_tree()
  expect_equal(run_publish(root)$status, 0L)
  v1 <- jsonlite::fromJSON(file.path(d, "versions.json"))
  unlink(file.path(d, "log.jsonl"))
  r <- run_publish(root)
  expect_equal(r$status, 0L, info = r$out)
  lg <- stub_log(d)
  expect_false(any(grepl("^habitat/fwa/v1/barriers/", lg$key[lg$op == "put-object"])))
  expect_identical(sum(lg$op == "list-object-versions"), 1L)
  pub <- jsonlite::fromJSON(file.path(d, "store", "habitat/fwa/v1/manifest.json"),
                            simplifyVector = FALSE)
  for (p in pub$group_parts) {
    expect_identical(p$version_id, v1[[paste0("habitat/fwa/v1/", p$key)]], info = p$key)
  }
})

test_that("a failed part put stops PUBLISH before the manifest", {
  publish_script()
  d <- stub_aws()
  withr::local_envvar(STUB_FAIL_KEY = "species=SK")
  r <- run_publish(publish_tree())
  expect_false(r$status == 0L)
  expect_match(r$out, "put habitat/fwa/v1/segment/config=cfgx/species=SK/part-100.parquet")
  lg <- stub_log(d)
  expect_false("habitat/fwa/v1/manifest.json" %in% lg$key[lg$op == "put-object"])
  expect_false(file.exists(file.path(d, "store", "habitat/fwa/v1/manifest.json")))
})

test_that("a put answered with no VersionId stops PUBLISH before the manifest", {
  publish_script()
  d <- stub_aws()
  withr::local_envvar(STUB_NONE_KEY = "watershed_group_code=G2")
  r <- run_publish(publish_tree())
  expect_false(r$status == 0L)
  expect_match(r$out, "G2/part.parquet has no VersionId")
  expect_false(file.exists(file.path(d, "store", "habitat/fwa/v1/manifest.json")))
})
