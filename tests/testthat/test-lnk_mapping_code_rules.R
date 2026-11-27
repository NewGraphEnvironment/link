# Mapping-code barrier tokens as rules (link#197).

# The chains coded before link#197 (lnk_pipeline_mapping_code.R at 0.94.0),
# kept here as the reference the shipped rules must reproduce.
old_token2 <- function(access) {
  n <- nrow(access)
  has <- function(col) {
    if (col %in% names(access)) !is.na(access[[col]]) & as.logical(access[[col]])
    else rep(FALSE, n)
  }
  any_anth <- has("has_barriers_anthropogenic_dnstr")
  any_pscis <- has("has_barriers_pscis_dnstr")
  any_dam_resident <- if ("dam_dnstr_ind" %in% names(access)) has("dam_dnstr_ind")
                      else has("has_barriers_dams_dnstr")
  any_dam_anadr <- has("has_barriers_dams_dnstr")
  any_remed <- if ("remediated_dnstr_ind" %in% names(access)) has("remediated_dnstr_ind")
               else has("has_remediated_dnstr")
  r <- rep(NA_character_, n)
  r[any_remed] <- "REMEDIATED"
  r[is.na(r) & any_dam_resident] <- "DAM"
  r[is.na(r) & any_anth & any_pscis & !any_dam_resident] <- "ASSESSED"
  r[is.na(r) & any_anth & !any_pscis & !any_dam_resident] <- "MODELLED"
  r[is.na(r) & !any_anth] <- "NONE"
  a <- rep(NA_character_, n)
  a[any_remed] <- "REMEDIATED"
  a[is.na(a) & any_dam_anadr] <- "DAM"
  a[is.na(a) & any_pscis] <- "ASSESSED"
  a[is.na(a) & any_anth] <- "MODELLED"
  a[is.na(a) & !any_anth] <- "NONE"
  list(resident = r, anadromous = a)
}

new_token2 <- function(access, rules = .lnk_mc_rules()) {
  v <- .lnk_mc_alias_values(access)
  list(resident = .lnk_mc_rules_eval(rules, v, "resident"),
       anadromous = .lnk_mc_rules_eval(rules, v, "anadromous"))
}

test_that("the package rules reproduce the old chains on every alias combination", {
  g <- expand.grid(rep(list(c(FALSE, TRUE)), 5))
  names(g) <- c("any_anth", "any_pscis", "any_dam_resident", "any_dam_anadr",
                "any_remed")
  rules <- .lnk_mc_rules()
  for (res in c("resident", "anadromous")) {
    got <- .lnk_mc_rules_eval(rules, as.list(g), res)
    # The old chains over the same aliases, written as raw columns.
    acc <- data.frame(
      has_barriers_anthropogenic_dnstr = g$any_anth,
      has_barriers_pscis_dnstr = g$any_pscis,
      dam_dnstr_ind = if (res == "resident") g$any_dam_resident else FALSE,
      has_barriers_dams_dnstr = if (res == "resident") FALSE else g$any_dam_anadr,
      remediated_dnstr_ind = g$any_remed)
    expect_identical(got, old_token2(acc)[[res]], info = res)
    expect_false(anyNA(got))
  }
})

test_that("the package rules reproduce the old chains over the raw columns, NA cells and fallbacks", {
  cols <- c("has_barriers_anthropogenic_dnstr", "has_barriers_pscis_dnstr",
            "has_barriers_dams_dnstr", "dam_dnstr_ind", "remediated_dnstr_ind",
            "has_remediated_dnstr")
  g <- expand.grid(rep(list(c(FALSE, TRUE, NA)), length(cols)))
  names(g) <- cols
  # Every subset of the optional columns the aliases fall back between.
  for (drop in list(character(0), "dam_dnstr_ind", "remediated_dnstr_ind",
                    c("dam_dnstr_ind", "remediated_dnstr_ind"),
                    c("remediated_dnstr_ind", "has_remediated_dnstr"),
                    cols)) {
    acc <- g[, setdiff(cols, drop), drop = FALSE]
    if (ncol(acc) == 0L) acc <- data.frame(x = seq_len(nrow(g)))
    expect_identical(new_token2(acc), old_token2(acc),
                     info = paste(drop, collapse = ","))
  }
})

test_that("every bundle declaring the rules ships the package copy", {
  pkg <- utils::read.csv(system.file("extdata", "parameters_mapping_code_rules.csv",
                                     package = "link"), colClasses = "character")
  for (b in c("default", "bcfishpass")) {
    cfg <- lnk_config(b)
    path <- cfg$files$parameters_mapping_code_rules$path
    expect_false(is.null(path), info = b)
    expect_identical(utils::read.csv(path, colClasses = "character"), pkg, info = b)
  }
  # A bundle declaring none reads the package copy.
  expect_identical(.lnk_mc_rules(lnk_config("default_rearbreaks"))[, 1:4],
                   .lnk_mc_rules()[, 1:4])
})

base_rules <- function() {
  utils::read.csv(system.file("extdata", "parameters_mapping_code_rules.csv",
                              package = "link"), colClasses = "character")
}
with_row <- function(i, col, value) {
  r <- base_rules()
  r[[col]][i] <- value
  r
}

test_that("the validator refuses rules that would leave a token unset or corrupt one", {
  expect_error(.lnk_mc_rules_validate(base_rules()[, -4]), "lacks column")
  expect_error(.lnk_mc_rules_validate(base_rules()[0, ]), "no rows")
  expect_error(.lnk_mc_rules_validate(with_row(1, "residence", "fluvial")),
               "resident or anadromous")
  expect_error(.lnk_mc_rules_validate(base_rules()[base_rules()$residence == "resident", ]),
               "no rows for: anadromous")
  expect_error(.lnk_mc_rules_validate(with_row(2, "precedence", "1")),
               "precedence repeats")
  expect_error(.lnk_mc_rules_validate(with_row(2, "precedence", "1.5")),
               "whole number")
  for (tok in c("DAM;X", "dam", "", "ACCESS", "INTERMITTENT", "2DAM")) {
    expect_error(.lnk_mc_rules_validate(with_row(2, "token", tok)),
                 "token must be", info = tok)
  }
  expect_error(.lnk_mc_rules_validate(with_row(5, "when", "!any_anth")),
               "last resident row must be")
  expect_error(.lnk_mc_rules_validate(with_row(1, "when", "any_remedied")),
               "unknown name")
  for (w in c("any_anth && any_pscis", "any_anth || any_pscis", "T", "F",
              "1", "isTRUE(any_anth)", "any_anth; any_pscis", "system('x')",
              "FALSE", "any_anth == TRUE", "(any_anth")) {
    expect_error(.lnk_mc_rules_validate(with_row(1, "when", w)),
                 "parameters_mapping_code_rules", info = w)
  }
  # Allowed: the full grammar.
  ok <- with_row(1, "when", "(any_remed | any_anth) & !(any_pscis)")
  expect_silent(.lnk_mc_rules_validate(ok))
})

test_that("a bundle adds a token with no code change", {
  r <- base_rules()
  r$precedence <- as.character(as.integer(r$precedence) * 10L)
  r <- rbind(r, data.frame(residence = "resident", precedence = "25",
                           token = "DAM_ASSESSED",
                           when = "any_pscis & any_anth"))
  path <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(r, path, row.names = FALSE)
  cfg <- lnk_config("default")
  cfg$files$parameters_mapping_code_rules$path <- path
  acc <- data.frame(id_segment = 1:2, has_barriers_bt_dnstr = FALSE,
                    has_barriers_anthropogenic_dnstr = TRUE,
                    has_barriers_pscis_dnstr = c(TRUE, FALSE),
                    dam_dnstr_ind = FALSE)
  hab <- data.frame(id_segment = 1:2, spawning_bt = 0, rearing_bt = 0)
  fc <- data.frame(id_segment = 1:2, feature_code = "X")
  out <- lnk_pipeline_mapping_code(acc, hab, fc, cfg = cfg,
                                   species_resident = "bt",
                                   species_anadromous = character(0),
                                   species_spawn_only = character(0))
  expect_identical(out$mapping_code_bt, c("ACCESS;DAM_ASSESSED", "ACCESS;MODELLED"))
  # The same rules passed as a data frame give the same codes.
  expect_identical(
    lnk_pipeline_mapping_code(acc, hab, fc, rules_mapping_code = r,
                              species_resident = "bt",
                              species_anadromous = character(0),
                              species_spawn_only = character(0)),
    out)
})

test_that("the evaluator reaches no function outside the grammar", {
  rules <- .lnk_mc_rules()
  v <- list(any_anth = TRUE, any_pscis = FALSE, any_dam_resident = FALSE,
            any_dam_anadr = FALSE, any_remed = FALSE)
  expect_identical(.lnk_mc_rules_eval(rules, v, "resident"), "MODELLED")
  # A walker slip handing eval a call outside the grammar fails in the empty
  # environment instead of running it.
  bad <- rules
  bad$expr[[which(bad$residence == "resident")[1]]] <- quote(print(any_anth))
  expect_error(.lnk_mc_rules_eval(bad, v, "resident"), "print")
})

test_that("a species in both residence sets is refused", {
  expect_error(.lnk_mc_species(NULL, resident = c("bt", "ct"),
                               anadromous = c("ct", "ch")),
               "both.*CT")
  expect_identical(.lnk_mc_species(NULL),
                   list(resident = c("bt", "wct"),
                        anadromous = c("ch", "cm", "co", "pk", "sk", "st"),
                        spawn_only = c("cm", "pk")))
})
