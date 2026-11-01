# An overlay is a link-owned file of cell changes on top of a copied
# upstream table: one row per (key, column), each with a reason. The loader
# applies it, so readers see one table and the copy stays verbatim (#429).

overlay_fixture <- function(dir, base_lines, overlay_lines) {
  base <- file.path(dir, "base.csv")
  ovl <- file.path(dir, "base_overlay.csv")
  writeLines(base_lines, base)
  writeLines(overlay_lines, ovl)
  list(base = base, overlay = ovl)
}

base_lines <- c("watershed_group_code,bt,ch,notes",
                "ADMS,t,,",
                "BULK,t,t,a note")

test_that("an overlay sets a cell and adds a column", {
  tmp <- withr::local_tempdir()
  f <- overlay_fixture(tmp, base_lines, c(
    "watershed_group_code,column,value,reason,issue",
    "ADMS,ch,t,recorded above the falls,#1",
    "BULK,ko,t,kokanee recorded,#2"))
  out <- link:::.lnk_load_local("x", f$base, overlay = f$overlay)

  expect_s3_class(out, "tbl_df")
  expect_identical(out$ch, c("t", "t"))
  # The added column holds the overlay's value where set, and the empty
  # field a CSV would give elsewhere.
  expect_identical(out$ko, c("", "t"))
  # Inserted before the first column that sorts after it (notes), not
  # appended: column order reaches readers.
  expect_identical(names(out), c("watershed_group_code", "bt", "ch", "ko", "notes"))
  expect_identical(out$notes, c("", "a note"))
})

test_that("a table with an overlay reads as read.csv reads it without one", {
  tmp <- withr::local_tempdir()
  f <- overlay_fixture(tmp, c("k,n,f", "a,1,x", "b,2,"),
                       c("k,column,value,reason,issue"))
  expect_identical(link:::.lnk_load_local("x", f$base, overlay = f$overlay),
                   tibble::as_tibble(utils::read.csv(f$base,
                                                     stringsAsFactors = FALSE)))
})

test_that("an overlay types a changed column as read.csv would", {
  tmp <- withr::local_tempdir()
  f <- overlay_fixture(tmp, c("k,n", "a,1", "b,2"), c(
    "k,column,value,reason,issue",
    "b,n,3,corrected,#3"))
  out <- link:::.lnk_load_local("x", f$base, overlay = f$overlay)
  expect_identical(out$n, c(1L, 3L))
})

test_that("an overlay refuses a key the base does not hold", {
  tmp <- withr::local_tempdir()
  f <- overlay_fixture(tmp, base_lines, c(
    "watershed_group_code,column,value,reason,issue",
    "ZZZZ,ch,t,typo,#1"))
  expect_error(link:::.lnk_load_local("x", f$base, overlay = f$overlay),
               "ZZZZ")
})

test_that("an overlay refuses a repeated key and column", {
  tmp <- withr::local_tempdir()
  f <- overlay_fixture(tmp, base_lines, c(
    "watershed_group_code,column,value,reason,issue",
    "ADMS,ch,t,one,#1",
    "ADMS,ch,,two,#1"))
  expect_error(link:::.lnk_load_local("x", f$base, overlay = f$overlay),
               "ADMS")
})

test_that("an overlay refuses a row with no reason", {
  tmp <- withr::local_tempdir()
  f <- overlay_fixture(tmp, base_lines, c(
    "watershed_group_code,column,value,reason,issue",
    "ADMS,ch,t,,#1"))
  expect_error(link:::.lnk_load_local("x", f$base, overlay = f$overlay),
               "reason")
})

test_that("an overlay refuses columns other than key, column, value, reason, issue", {
  tmp <- withr::local_tempdir()
  f <- overlay_fixture(tmp, base_lines, c(
    "watershed_group_code,column,value,why",
    "ADMS,ch,t,x"))
  expect_error(link:::.lnk_load_local("x", f$base, overlay = f$overlay),
               "column, value, reason, issue")
})

test_that("an overlay refuses a key column the base lacks, or the key itself as a target", {
  tmp <- withr::local_tempdir()
  f <- overlay_fixture(tmp, base_lines, c(
    "wsg,column,value,reason,issue", "ADMS,ch,t,x,#1"))
  expect_error(link:::.lnk_load_local("x", f$base, overlay = f$overlay), "wsg")

  f <- overlay_fixture(tmp, base_lines, c(
    "watershed_group_code,column,value,reason,issue",
    "ADMS,watershed_group_code,ADMX,rename,#1"))
  expect_error(link:::.lnk_load_local("x", f$base, overlay = f$overlay),
               "key column")
})

test_that("an overlay refuses a base whose key repeats", {
  tmp <- withr::local_tempdir()
  f <- overlay_fixture(tmp, c(base_lines, "ADMS,,,"), c(
    "watershed_group_code,column,value,reason,issue"))
  expect_error(link:::.lnk_load_local("x", f$base, overlay = f$overlay),
               "repeat")
})

test_that("the local read does not warn on a short file with no final newline", {
  tmp <- withr::local_tempdir()
  p <- file.path(tmp, "short.csv")
  writeBin(charToRaw("a,b\n1,2"), p)
  expect_no_warning(out <- link:::.lnk_load_local("x", p))
  expect_identical(out$b, 2L)
})

test_that("an overlay declared on a crate-ingested entry is refused", {
  expect_error(
    link:::.lnk_load_entry("x", list(path = "a.csv",
                                     canonical_schema = "bcfp/x",
                                     overlay = "b.csv")),
    "overlay")
})

test_that("the bcfishpass bundle's presence copy is verbatim and ko is an overlay", {
  cfg <- lnk_config("bcfishpass")
  copy <- utils::read.csv(cfg$files$wsg_species_presence$path,
                          nrows = 1)
  expect_false("ko" %in% names(copy))
  loaded <- lnk_load_overrides(cfg)
  expect_true("ko" %in% names(loaded$wsg_species_presence))
  nm <- names(loaded$wsg_species_presence)
  expect_identical(match("ko", nm), match("gr", nm) + 1L)
  expect_true(all(loaded$wsg_species_presence$ko %in% c("t", "")))
})

test_that("a bundle extending one with an overlay applies the parent's overlay", {
  parent <- lnk_config("bcfishpass")
  child_dir <- withr::local_tempdir()
  yaml::write_yaml(list(name = "child", extends = parent$dir),
                   file.path(child_dir, "config.yaml"))
  child <- lnk_config(child_dir)
  expect_identical(child$files$wsg_species_presence$overlay,
                   parent$files$wsg_species_presence$overlay)
  expect_identical(lnk_load_overrides(child)$wsg_species_presence,
                   lnk_load_overrides(parent)$wsg_species_presence)
})

test_that("an overlay enters the config hash even with no provenance entry", {
  parent <- lnk_config("bcfishpass")
  child_dir <- withr::local_tempdir()
  writeLines(c("watershed_group_code,column,value,reason,issue",
               "ADMS,ko,t,a test row,#429"),
             file.path(child_dir, "own_overlay.csv"))
  yaml::write_yaml(list(
    name = "child", extends = parent$dir,
    files = list(wsg_species_presence = list(
      path = parent$files$wsg_species_presence$path,
      overlay = "own_overlay.csv"))),
    file.path(child_dir, "config.yaml"))
  child <- lnk_config(child_dir)
  expect_null(child$provenance[["own_overlay.csv"]])
  expect_true("own_overlay.csv" %in% link:::.lnk_config_files(child)$rel)
  h1 <- link:::.lnk_config_hash(child)
  write("ADMS,ch,t,another row,#429", file.path(child_dir, "own_overlay.csv"),
        append = TRUE)
  expect_false(identical(h1, link:::.lnk_config_hash(lnk_config(child_dir))))
})
