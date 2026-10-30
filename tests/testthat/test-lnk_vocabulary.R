# The output vocabulary (#414): the table's invariants, the append-only rule
# against the default branch, and the resolver on every shipped config.

vocab_path <- function() system.file("extdata", "vocabulary.csv", package = "link")

test_that("the vocabulary table holds its invariants", {
  v <- lnk_vocabulary_read()
  expect_gt(nrow(v), 0)
  expect_true(all(grepl("^[a-z0-9]+(-[a-z0-9]+)*$", v$token)))
  expect_false(anyDuplicated(v$token) > 0)
  expect_true(all(v$axis %in% c("cut", "acc", "grad", "flow")))
  prefix <- c(cut = "cut-", acc = "acc-", grad = "grad-", flow = "q-")
  expect_true(all(startsWith(v$token, prefix[v$axis])))
  for (col in c("definition", "spec", "introduced")) {
    expect_true(all(!is.na(v[[col]]) & nzchar(trimws(v[[col]]))), info = col)
  }
  expect_true(all(grepl("^[0-9]+\\.[0-9]+\\.[0-9]+$", v$introduced)))
  live <- v[is.na(v$retired), ]
  expect_false(anyDuplicated(paste(live$axis, live$spec)) > 0)
  ret <- v[!is.na(v$retired), ]
  expect_true(all(package_version(ret$retired) >=
                    package_version(ret$introduced)))
})

test_that("a vocabulary file with other columns is refused", {
  f <- withr::local_tempfile(fileext = ".csv")
  writeLines(c("token,axis,definition,spec,introduced",
               "cut-x,cut,d,s,0.1.0"), f)
  expect_error(link:::.lnk_vocabulary_read_path(f), "columns must be")
})

# A token is never renamed, removed or reused: against the default branch's
# copy, every row survives with its token, axis, spec and introduced version,
# and only an empty `retired` may be filled. Runs from a git checkout only.
vocab_base <- function() {
  root <- tryCatch(
    system2("git", c("-C", shQuote(testthat::test_path()), "rev-parse",
                     "--show-toplevel"), stdout = TRUE, stderr = FALSE),
    error = function(e) character(0), warning = function(w) character(0))
  if (length(root) != 1L) return(NULL)
  base <- tryCatch(
    system2("git", c("-C", shQuote(root), "show",
                     "origin/main:inst/extdata/vocabulary.csv"),
            stdout = TRUE, stderr = FALSE),
    error = function(e) character(0), warning = function(w) character(0))
  if (length(base) == 0L) return(NULL)
  f <- tempfile(fileext = ".csv")
  writeLines(base, f)
  list(base = link:::.lnk_vocabulary_read_path(f),
       head = link:::.lnk_vocabulary_read_path(
         file.path(root, "inst", "extdata", "vocabulary.csv")))
}

vocab_append_only <- function(base, head) {
  keep <- c("token", "axis", "spec", "introduced")
  gone <- setdiff(base$token, head$token)
  m <- match(base$token, head$token)
  b <- base[!is.na(m), , drop = FALSE]
  h <- head[m[!is.na(m)], , drop = FALSE]
  edited <- b$token[rowSums(b[keep] != h[keep]) > 0]
  unretired <- b$token[!is.na(b$retired) & (is.na(h$retired) |
                                              b$retired != h$retired)]
  c(gone, edited, unretired)
}

test_that("the append-only check catches a rename, an edit and an unretire", {
  base <- data.frame(token = c("cut-a", "acc-b"), axis = c("cut", "acc"),
                     definition = "d", spec = c("s1", "s2"),
                     introduced = "0.1.0", retired = c(NA, "0.2.0"))
  expect_length(vocab_append_only(base, base), 0)
  renamed <- base
  renamed$token[1] <- "cut-z"
  expect_identical(vocab_append_only(base, renamed), "cut-a")
  respec <- base
  respec$spec[1] <- "s9"
  expect_identical(vocab_append_only(base, respec), "cut-a")
  unret <- base
  unret$retired[2] <- NA
  expect_identical(vocab_append_only(base, unret), "acc-b")
  retire <- base
  retire$retired[1] <- "0.3.0"
  added <- rbind(retire, data.frame(token = "q-c", axis = "flow",
                                    definition = "d", spec = "s3",
                                    introduced = "0.3.0", retired = NA))
  expect_length(vocab_append_only(base, added), 0)
})

test_that("the vocabulary only grows against the default branch", {
  x <- vocab_base()
  skip_if(is.null(x), "no git checkout, or the default branch has no table")
  expect_identical(vocab_append_only(x$base, x$head), character(0))
})

test_that("each shipped config resolves to its tokens", {
  expect_identical(
    lnk_vocabulary_resolve(lnk_config("default")),
    c(cut = "cut-full-top", acc = "acc-v3", grad = "grad-seg",
      flow = "q-fwapg"))
  expect_identical(
    lnk_vocabulary_resolve(lnk_config("default_tuned")),
    c(cut = "cut-full-top", acc = "acc-v3", grad = "grad-seg",
      flow = "q-wet-fill"))
  expect_identical(
    lnk_vocabulary_resolve(lnk_config("bcfishpass")),
    c(cut = "cut-full-ssf-all", acc = "acc-bcfp-3", grad = "grad-seg",
      flow = "q-fwapg"))
})

test_that("the two stale gradient-class bundles have no tokens and refuse", {
  for (n in c("default_extrabreaks", "default_rearbreaks")) {
    expect_error(lnk_vocabulary_resolve(lnk_config(n)),
                 "no cut token .* has the spec", info = n)
  }
})

test_that("an edited break order or access gradient needs a new token", {
  cfg <- lnk_config("default")
  loaded <- lnk_load_overrides(cfg)

  moved <- cfg
  moved$pipeline$break_order <- rev(cfg$pipeline$break_order)
  expect_error(lnk_vocabulary_resolve(moved, loaded),
               "no cut token .* has the spec\n  break_order=crossings")

  steeper <- loaded
  steeper$parameters_fresh$access_gradient_max[
    steeper$parameters_fresh$species_code == "BT"] <- 0.18
  expect_error(lnk_vocabulary_resolve(cfg, steeper),
               "no acc token .* has the spec\n  sha256:")

  no_control <- loaded
  no_control$user_barriers_definite_control <- NULL
  expect_error(lnk_vocabulary_resolve(cfg, no_control),
               "no cut token .*barrier_inputs=user_barriers_definite,user_habitat")

  fewer <- cfg
  fewer$species <- setdiff(cfg$species, "GR")
  expect_error(lnk_vocabulary_resolve(fewer, loaded), "no acc token")

  present <- loaded
  present$wsg_species_presence$gr[1] <-
    if (identical(present$wsg_species_presence$gr[1], "t")) "" else "t"
  expect_error(lnk_vocabulary_resolve(cfg, present), "no acc token")
})

test_that("observation_breaks counts only when observations cut", {
  cfg <- lnk_config("default")
  no_obs <- cfg
  no_obs$pipeline$break_order <- setdiff(cfg$pipeline$break_order,
                                         "observations")
  a <- link:::.lnk_vocabulary_spec_cut(no_obs, lnk_load_overrides(cfg))
  no_obs$pipeline$observation_breaks <- "all"
  expect_identical(link:::.lnk_vocabulary_spec_cut(no_obs, lnk_load_overrides(cfg)), a)
  expect_false(grepl("observation_breaks", a))
})

test_that("the acc digest ignores how the files were written", {
  cfg <- lnk_config("default")
  loaded <- lnk_load_overrides(cfg)
  ref <- link:::.lnk_vocabulary_spec_acc(cfg, loaded)

  shuffled <- loaded
  pf <- shuffled$parameters_fresh
  pf <- pf[rev(seq_len(nrow(pf))), rev(names(pf))]
  pf$access_gradient_max <- as.character(pf$access_gradient_max)
  shuffled$parameters_fresh <- pf
  pres <- shuffled$wsg_species_presence
  pres$notes <- "edited free text"
  shuffled$wsg_species_presence <- pres[rev(seq_len(nrow(pres))), ]
  expect_identical(link:::.lnk_vocabulary_spec_acc(cfg, shuffled), ref)

  # A column the rules do not read (cluster geometry) is not access.
  clustered <- loaded
  clustered$parameters_fresh$cluster_bridge_distance <- 1
  expect_identical(link:::.lnk_vocabulary_spec_acc(cfg, clustered), ref)
})

test_that("a spelling the pipeline reads differently digests differently", {
  # .lnk_wsg_species_present() counts only "t": "TRUE" or " t" drops the
  # species from the model, so the rule set has changed.
  cfg <- lnk_config("default")
  loaded <- lnk_load_overrides(cfg)
  ref <- link:::.lnk_vocabulary_spec_acc(cfg, loaded)
  i <- which(loaded$wsg_species_presence$bt == "t")[1]
  for (v in c("TRUE", " t", "t ")) {
    l2 <- loaded
    l2$wsg_species_presence$bt[i] <- v
    expect_false(identical(link:::.lnk_vocabulary_spec_acc(cfg, l2), ref),
                 info = v)
  }
  na_vs_blank <- loaded
  j <- which(loaded$parameters_fresh$observation_species %in% NA)[1]
  na_vs_blank$parameters_fresh$observation_species[j] <- ""
  expect_false(identical(link:::.lnk_vocabulary_spec_acc(cfg, na_vs_blank),
                         ref))
})

test_that("the acc digest does not depend on the session's collation", {
  cfg <- lnk_config("default")
  loaded <- lnk_load_overrides(cfg)
  ref <- link:::.lnk_vocabulary_spec_acc(cfg, loaded)
  # Under a Czech collation "CH" sorts after "H", so after "GR".
  ok <- suppressWarnings(Sys.setlocale("LC_COLLATE", "cs_CZ.UTF-8"))
  skip_if(!nzchar(ok), "cs_CZ.UTF-8 collation not installed")
  withr::defer(Sys.setlocale("LC_COLLATE", "C"))
  skip_if(identical(sort(c("CH", "GR")), c("CH", "GR")),
          "this platform's cs_CZ collation does not reorder CH")
  expect_identical(link:::.lnk_vocabulary_spec_acc(cfg, loaded), ref)
})

test_that("what the pipeline reads exactly, the specs keep exactly", {
  cfg <- lnk_config("default")
  loaded <- lnk_load_overrides(cfg)
  cut <- link:::.lnk_vocabulary_spec_cut(cfg, loaded)
  acc <- link:::.lnk_vocabulary_spec_acc(cfg, loaded)

  # A gradient class's name is its label, which classify parses as the
  # threshold: the same values under another name are another cut.
  renamed <- cfg
  renamed$pipeline$gradient_classes <- list("1400" = 0.15, "2000" = 0.20,
                                            "2500" = 0.25, "3000" = 0.30)
  expect_false(identical(link:::.lnk_vocabulary_spec_cut(renamed, loaded),
                         cut))

  # Species codes are matched case-sensitively.
  lower <- cfg
  lower$species <- tolower(cfg$species)
  expect_false(identical(link:::.lnk_vocabulary_spec_acc(lower, loaded), acc))

  # A double that as.character() rounds is still another value.
  nudged <- loaded
  i <- which(nudged$parameters_fresh$species_code == "CH")
  nudged$parameters_fresh$access_gradient_max[i] <- 0.15000000000000002
  expect_false(identical(link:::.lnk_vocabulary_spec_acc(cfg, nudged), acc))

  # A date column (a classed double) is written as a date, not a number.
  dated <- loaded
  dated$parameters_fresh$observation_date_min <-
    as.Date(dated$parameters_fresh$observation_date_min)
  expect_identical(link:::.lnk_vocabulary_spec_acc(cfg, dated), acc)

  # Rows are sorted before hashing, so a duplicate key, whose first row the
  # pipeline reads, is refused.
  dup <- loaded
  dup$parameters_fresh <- rbind(dup$parameters_fresh,
                                dup$parameters_fresh[1, ])
  expect_error(link:::.lnk_vocabulary_spec_acc(cfg, dup),
               "duplicate parameters_fresh species_code")
  dup <- loaded
  dup$wsg_species_presence <- rbind(dup$wsg_species_presence,
                                    dup$wsg_species_presence[1, ])
  expect_error(link:::.lnk_vocabulary_spec_acc(cfg, dup),
               "duplicate wsg_species_presence")
})

test_that("a blank key cell in the table is refused, not matched", {
  f <- withr::local_tempfile(fileext = ".csv")
  writeLines(c("token,axis,definition,spec,introduced,retired",
               "cut-a,cut,d,,0.1.0,"), f)
  expect_error(link:::.lnk_vocabulary_read_path(f), "blank spec in row")
})

test_that("a retired match or two live matches refuse", {
  vocab <- data.frame(token = c("cut-a", "cut-b", "cut-c"), axis = "cut",
                      definition = "d", spec = c("s1", "s2", "s2"),
                      introduced = "0.1.0", retired = c("0.2.0", NA, NA))
  expect_error(link:::.lnk_vocabulary_match(c(cut = "s1"), vocab, "x"),
               "matches only the retired token cut-a")
  expect_error(link:::.lnk_vocabulary_match(c(cut = "s2"), vocab, "x"),
               "2 live cut tokens share one spec")
  vocab$retired[1] <- NA
  expect_identical(link:::.lnk_vocabulary_match(c(cut = "s1"), vocab, "x"),
                   c(cut = "cut-a"))
  # A retired token and its live successor share a spec when the code changed
  # the output and the spec did not (acc-v1 -> acc-v2, #399): the live one wins.
  vocab$retired[2] <- "0.2.0"
  expect_identical(link:::.lnk_vocabulary_match(c(cut = "s2"), vocab, "x"),
                   c(cut = "cut-c"))
})

test_that("the acc digest moves with observation_upstream (#401)", {
  cfg <- lnk_config("default")
  loaded <- lnk_load_overrides(cfg)
  a <- .lnk_vocabulary_spec_acc(cfg, loaded)
  cfg$pipeline$observation_upstream <- "group_gated"
  expect_false(identical(a, .lnk_vocabulary_spec_acc(cfg, loaded)))
  # Absent reads as group_gated, so it is the same rule set.
  g <- .lnk_vocabulary_spec_acc(cfg, loaded)
  cfg$pipeline$observation_upstream <- NULL
  expect_identical(.lnk_vocabulary_spec_acc(cfg, loaded), g)
})
