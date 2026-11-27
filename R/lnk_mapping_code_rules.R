#' Mapping-code barrier tokens, as rules
#'
#' The second token of `mapping_code_<sp>` (which human-made barrier kind lies
#' downstream of an accessible segment) is decided by a bundle's
#' `parameters_mapping_code_rules.csv` (link#197): per residence (`resident`,
#' `anadromous`), the rows in `precedence` order, first match wins. Each row's
#' `when` is a boolean expression over five aliases of the access columns:
#'
#' - `any_anth`: `has_barriers_anthropogenic_dnstr`
#' - `any_pscis`: `has_barriers_pscis_dnstr`
#' - `any_dam_resident`: `dam_dnstr_ind` (the next barrier down is a dam), or
#'   `has_barriers_dams_dnstr` where the access table has no `dam_dnstr_ind`
#' - `any_dam_anadr`: `has_barriers_dams_dnstr` (any dam downstream)
#' - `any_remed`: `remediated_dnstr_ind`, or `has_remediated_dnstr` where the
#'   access table has no `remediated_dnstr_ind`
#'
#' A missing column reads `FALSE`, and so does an `NA` cell. `when` may use
#' only those aliases, `&`, `|`, `!`, parentheses and `TRUE`, and each
#' residence ends on a `TRUE` row, so every accessible segment gets a token.
#' A bundle that declares no file reads the package copy,
#' `inst/extdata/parameters_mapping_code_rules.csv`.
#'
#' @name lnk_mapping_code_rules
#' @noRd
NULL

.lnk_mc_rules_cols <- c("residence", "precedence", "token", "when")
.lnk_mc_aliases <- c("any_anth", "any_pscis", "any_dam_resident",
                     "any_dam_anadr", "any_remed")
.lnk_mc_tokens_reserved <- c("ACCESS", "SPAWN", "REAR", "INTERMITTENT")

#' The mapping-code rules a call reads
#'
#' `rules` if given (a data frame), else the file `cfg` declares, else the
#' package copy. Every column is read as text, then validated.
#' @noRd
.lnk_mc_rules <- function(cfg = NULL, rules = NULL) {
  if (is.null(rules)) {
    path <- cfg$files$parameters_mapping_code_rules$path %||%
      system.file("extdata", "parameters_mapping_code_rules.csv",
                  package = "link", mustWork = TRUE)
    rules <- utils::read.csv(path, colClasses = "character",
                             stringsAsFactors = FALSE, check.names = FALSE,
                             na.strings = character())
  }
  .lnk_mc_rules_validate(rules)
}

#' Refuse rules that could leave a segment without a token, or corrupt one
#' @return The rules, ordered by residence then precedence, with `when`
#'   parsed into a list column `expr`.
#' @noRd
.lnk_mc_rules_validate <- function(rules) {
  if (!is.data.frame(rules)) {
    stop("parameters_mapping_code_rules must be a data frame", call. = FALSE)
  }
  miss <- setdiff(.lnk_mc_rules_cols, names(rules))
  if (length(miss)) {
    stop("parameters_mapping_code_rules lacks column(s): ",
         paste(miss, collapse = ", "), call. = FALSE)
  }
  r <- data.frame(lapply(rules[.lnk_mc_rules_cols], function(x) trimws(as.character(x))),
                  stringsAsFactors = FALSE)
  if (nrow(r) == 0L) {
    stop("parameters_mapping_code_rules has no rows", call. = FALSE)
  }
  bad_res <- setdiff(unique(r$residence), c("resident", "anadromous"))
  if (length(bad_res)) {
    stop("parameters_mapping_code_rules: residence must be resident or ",
         "anadromous, not: ", paste(bad_res, collapse = ", "), call. = FALSE)
  }
  absent_res <- setdiff(c("resident", "anadromous"), r$residence)
  if (length(absent_res)) {
    stop("parameters_mapping_code_rules has no rows for: ",
         paste(absent_res, collapse = ", "), call. = FALSE)
  }
  if (!all(grepl("^[0-9]+$", r$precedence))) {
    stop("parameters_mapping_code_rules: precedence must be a whole number ",
         "on every row", call. = FALSE)
  }
  r$precedence <- as.integer(r$precedence)
  dup <- duplicated(r[c("residence", "precedence")])
  if (any(dup)) {
    stop("parameters_mapping_code_rules: precedence repeats within a ",
         "residence: ", paste(r$residence[dup], r$precedence[dup], collapse = ", "),
         call. = FALSE)
  }
  bad_tok <- !grepl("^[A-Z][A-Z_]*$", r$token) | r$token %in% .lnk_mc_tokens_reserved
  if (any(bad_tok)) {
    stop("parameters_mapping_code_rules: a token must be upper-case letters ",
         "and underscores, and not ", paste(.lnk_mc_tokens_reserved, collapse = ", "),
         "; refused: ", paste(sQuote(r$token[bad_tok], FALSE), collapse = ", "),
         call. = FALSE)
  }
  r$expr <- lapply(seq_len(nrow(r)), function(i) .lnk_mc_when_parse(r$when[i]))
  r <- r[order(r$residence, r$precedence), , drop = FALSE]
  for (res in c("resident", "anadromous")) {
    last <- utils::tail(r$when[r$residence == res], 1L)
    if (!identical(last, "TRUE")) {
      stop("parameters_mapping_code_rules: the last ", res, " row must be ",
           "when = TRUE, so every accessible segment gets a token", call. = FALSE)
    }
  }
  rownames(r) <- NULL
  r
}

#' Parse one `when` into an expression of the allowed grammar, or refuse
#' @noRd
.lnk_mc_when_parse <- function(when) {
  ex <- tryCatch(parse(text = when, keep.source = FALSE),
                 error = function(e) NULL)
  if (is.null(ex) || length(ex) != 1L) {
    stop("parameters_mapping_code_rules: when must be one expression: ",
         sQuote(when, FALSE), call. = FALSE)
  }
  walk <- function(e) {
    if (is.symbol(e)) {
      if (!as.character(e) %in% .lnk_mc_aliases) {
        stop("parameters_mapping_code_rules: unknown name ",
             sQuote(as.character(e), FALSE), " in ", sQuote(when, FALSE),
             "; allowed: ", paste(.lnk_mc_aliases, collapse = ", "), call. = FALSE)
      }
      return(invisible())
    }
    if (is.logical(e) && length(e) == 1L && isTRUE(e)) return(invisible())
    if (is.call(e)) {
      f <- as.character(e[[1L]])
      ok <- (f %in% c("&", "|") && length(e) == 3L) ||
        (f %in% c("!", "(") && length(e) == 2L)
      if (!ok) {
        stop("parameters_mapping_code_rules: ", sQuote(when, FALSE),
             " uses ", sQuote(f, FALSE), "; allowed: &, |, !, ( ), TRUE",
             call. = FALSE)
      }
      for (a in as.list(e)[-1L]) walk(a)
      return(invisible())
    }
    stop("parameters_mapping_code_rules: ", sQuote(when, FALSE),
         " holds a value other than TRUE", call. = FALSE)
  }
  walk(ex[[1L]])
  ex[[1L]]
}

#' The five aliases, as logical vectors over the access rows
#' @noRd
.lnk_mc_alias_values <- function(access) {
  n <- nrow(access)
  has <- function(col) {
    if (col %in% names(access)) {
      x <- access[[col]]
      !is.na(x) & as.logical(x)
    } else {
      rep(FALSE, n)
    }
  }
  pick <- function(first, second) if (first %in% names(access)) has(first) else has(second)
  list(any_anth = has("has_barriers_anthropogenic_dnstr"),
       any_pscis = has("has_barriers_pscis_dnstr"),
       any_dam_resident = pick("dam_dnstr_ind", "has_barriers_dams_dnstr"),
       any_dam_anadr = has("has_barriers_dams_dnstr"),
       any_remed = pick("remediated_dnstr_ind", "has_remediated_dnstr"))
}

#' Token 2 for one residence: first matching rule wins
#' @param rules Validated rules (`.lnk_mc_rules_validate()`).
#' @param values The aliases (`.lnk_mc_alias_values()`).
#' @noRd
.lnk_mc_rules_eval <- function(rules, values, residence) {
  n <- length(values[[1L]])
  env <- list2env(values, parent = emptyenv())
  for (op in c("&", "|", "!", "(")) assign(op, get(op, envir = baseenv()), envir = env)
  out <- rep(NA_character_, n)
  sel <- rules[rules$residence == residence, , drop = FALSE]
  for (i in seq_len(nrow(sel))) {
    hit <- rep_len(eval(sel$expr[[i]], env), n)
    out[is.na(out) & hit] <- sel$token[i]
  }
  out
}

#' The resident, anadromous and spawn-only sets a mapping-code call reads
#'
#' Each set passed is used as given; each left `NULL` comes from `cfg`'s
#' `dimensions.csv` over `cfg$species` ([.lnk_species_residence()], link#512),
#' or with no `cfg` from the sets bcfishpass codes. Shared by
#' [lnk_mapping_code()] and [lnk_pipeline_mapping_code()], so both resolve
#' alike. A species in both the resident and anadromous sets is refused: its
#' barrier token would silently follow the resident rules.
#' @noRd
.lnk_mc_species <- function(cfg = NULL, resident = NULL, anadromous = NULL,
                            spawn_only = NULL) {
  from_cfg <- if (!is.null(cfg)) {
    if (!inherits(cfg, "lnk_config")) {
      stop("`cfg` must be an lnk_config object or NULL", call. = FALSE)
    }
    .lnk_species_residence(cfg, cfg$species)
  } else {
    list(resident = c("bt", "wct"),
         anadromous = c("ch", "cm", "co", "pk", "sk", "st"),
         spawn_only = c("cm", "pk"))
  }
  out <- list(resident = resident %||% from_cfg$resident,
              anadromous = anadromous %||% from_cfg$anadromous,
              spawn_only = spawn_only %||% from_cfg$spawn_only)
  for (k in names(out)) {
    if (!is.character(out[[k]])) {
      stop("species_", k, " must be a character vector", call. = FALSE)
    }
  }
  both <- intersect(tolower(out$resident), tolower(out$anadromous))
  if (length(both)) {
    stop("species in both species_resident and species_anadromous: ",
         paste(toupper(both), collapse = ", "), call. = FALSE)
  }
  out
}
