#' Every observation-lift rule a bundle applies, one row per species and rule
#'
#' A species' first rule, `own`, is its `parameters_fresh.csv` row (the first
#' row per species, as the pipeline reads that table). Further rules come from
#' the bundle's `parameters_barrier_lifts.csv`, when it declares one (link#236):
#' "BT on one BT record of any date" beside "BT on two salmon records since
#' 1990" is two rules. A barrier is lifted for a species where any of its rules
#' is met; the records of two rules never add together.
#'
#' Rule `own` stays in `parameters_fresh.csv` because its `observation_date_min`
#' is also the species' record floor (`.lnk_observation_species_map()`), so each
#' rule lives in exactly one file.
#'
#' Refused at load, so [lnk_vocabulary_resolve()] refuses before a run's log
#' row opens (it reaches this through `.lnk_observation_species_map()`):
#' a lifts table missing a column; a duplicate (species, rule); a rule named
#' `own`; a species absent from `parameters_fresh`; a `barrier_kinds` other than
#' `natural`; a threshold that is not a positive whole number; and, under
#' `pipeline: observation_record_date: lift_floor`, a rule with a threshold
#' above 0 whose listed species' record floors differ from the rule's own floor.
#' That last test is equality, as it was for the `parameters_fresh` rows: a
#' looser floor would silently lose records, and a stricter one is a later
#' relaxation.
#'
#' @param cfg A config from [lnk_config()].
#' @param loaded Named list from [lnk_load_overrides()]; needs
#'   `parameters_fresh`.
#' @return Data frame with `species_code`, `rule`, `barrier_kinds` and the
#'   `.lnk_lift_rules_params` columns, rule `own` first for each species, then
#'   the further rules in `C` order of their names.
#' @noRd
.lnk_lift_rules <- function(cfg, loaded) {
  pf <- loaded$parameters_fresh
  if (!is.data.frame(pf) || !"species_code" %in% names(pf)) {
    stop("lift rules need parameters_fresh with species_code", call. = FALSE)
  }
  for (col in .lnk_lift_rules_params) {
    if (!col %in% names(pf)) pf[[col]] <- NA
  }
  key <- toupper(trimws(as.character(pf$species_code)))
  first <- !duplicated(key)
  own <- data.frame(species_code = key[first], rule = "own",
                    barrier_kinds = "natural", stringsAsFactors = FALSE)
  for (col in .lnk_lift_rules_params) own[[col]] <- pf[[col]][first]

  lifts <- loaded$parameters_barrier_lifts
  rules <- own
  if (!is.null(lifts)) {
    miss <- setdiff(.lnk_lift_rules_required, names(lifts))
    if (length(miss) > 0L) {
      stop("parameters_barrier_lifts lacks column(s): ",
           paste(miss, collapse = ", "), call. = FALSE)
    }
    if (nrow(lifts) > 0L) {
      x <- data.frame(
        species_code = toupper(trimws(as.character(lifts$species_code))),
        rule = trimws(as.character(lifts$rule)),
        barrier_kinds = trimws(as.character(lifts$barrier_kinds)),
        stringsAsFactors = FALSE)
      for (col in .lnk_lift_rules_params) x[[col]] <- lifts[[col]]
      # The grammar lnk_barrier_overrides() enforces, refused here so a bad
      # name stops before a run's log row opens.
      bad_name <- is.na(x$rule) | !grepl("^[A-Za-z0-9_.-]+$", x$rule)
      if (any(bad_name)) {
        stop("parameters_barrier_lifts: a rule name holds letters, digits, ",
             "'_', '.' or '-': ", paste(x$rule[bad_name], collapse = ", "),
             call. = FALSE)
      }
      if (any(x$rule == "own")) {
        stop("parameters_barrier_lifts: a rule may not be named 'own', which ",
             "names each species' parameters_fresh row", call. = FALSE)
      }
      k <- paste(x$species_code, x$rule)
      if (any(duplicated(k))) {
        stop("parameters_barrier_lifts: duplicate (species, rule): ",
             paste(unique(k[duplicated(k)]), collapse = ", "), call. = FALSE)
      }
      absent <- setdiff(x$species_code, own$species_code)
      if (length(absent) > 0L) {
        stop("parameters_barrier_lifts: species absent from parameters_fresh: ",
             paste(absent, collapse = ", "), call. = FALSE)
      }
      kinds <- strsplit(ifelse(is.na(x$barrier_kinds), "", x$barrier_kinds),
                        ";", fixed = TRUE)
      bad_kind <- !vapply(kinds, function(v) {
        v <- trimws(v)
        length(v) > 0L && all(v == "natural")
      }, logical(1))
      if (any(bad_kind)) {
        stop("parameters_barrier_lifts: barrier_kinds must be 'natural' ",
             "(human-made barriers block no species yet): ",
             paste(k[bad_kind], collapse = ", "), call. = FALSE)
      }
      thr <- suppressWarnings(as.numeric(x$observation_threshold))
      bad_thr <- is.na(thr) | thr <= 0 | thr != round(thr)
      if (any(bad_thr)) {
        stop("parameters_barrier_lifts: observation_threshold must be a ",
             "positive whole number: ", paste(k[bad_thr], collapse = ", "),
             call. = FALSE)
      }
      # Read as the runner reads them: a blank date is no floor and anything
      # else must parse; a yes/no cell is one of the spellings
      # .lnk_flag_true() reads, or blank.
      d <- .lnk_date_col(x$observation_date_min,
                         "parameters_barrier_lifts observation_date_min")
      x$observation_date_min <- ifelse(is.na(d), NA_character_, format(d))
      bf <- trimws(as.character(x$observation_buffer_m))
      ok_bf <- is.na(bf) | bf %in% c("", "NA") |
        !is.na(suppressWarnings(as.numeric(bf)))
      if (!all(ok_bf)) {
        stop("parameters_barrier_lifts: observation_buffer_m must be a number ",
             "or blank: ", paste(k[!ok_bf], collapse = ", "), call. = FALSE)
      }
      ca <- tolower(trimws(as.character(x$observation_control_apply)))
      ok_ca <- is.na(ca) | ca %in% c("", "na", "true", "false", "t", "f", "yes",
                                     "no", "y", "n", "1", "0")
      if (!all(ok_ca)) {
        stop("parameters_barrier_lifts: observation_control_apply must be yes/no ",
             "or TRUE/FALSE: ", paste(k[!ok_ca], collapse = ", "), call. = FALSE)
      }
      x <- x[order(x$species_code, x$rule, method = "radix"), , drop = FALSE]
      rules <- rbind(own, x)
      rules <- rules[order(match(rules$species_code, own$species_code),
                           rules$rule != "own"), , drop = FALSE]
    }
  }
  rownames(rules) <- NULL

  if (identical(.lnk_observation_record_date(cfg), "lift_floor")) {
    floor_of <- .lnk_date_col(pf$observation_date_min[first],
                              "parameters_fresh observation_date_min")
    rule_floor <- .lnk_date_col(rules$observation_date_min,
                                "lift rule observation_date_min")
    thr <- suppressWarnings(as.numeric(rules$observation_threshold))
    # A lift counts the rows of every species its list names, each already
    # held to its own floor, and then applies the rule's floor again
    # (lnk_barrier_overrides()). A list whose floors differ from the rule's
    # would silently take the stricter one, so it is refused.
    for (i in which(!is.na(thr) & thr > 0)) {
      lst <- as.character(rules$observation_species[i])
      lst <- if (is.na(lst) || !nzchar(trimws(lst))) {
        rules$species_code[i]
      } else {
        toupper(trimws(strsplit(lst, ";", fixed = TRUE)[[1]]))
      }
      f <- floor_of[match(lst, own$species_code)]
      r <- rule_floor[i]
      same <- (is.na(f) & is.na(r)) | (!is.na(f) & !is.na(r) & f == r)
      if (!all(same)) {
        who <- if (rules$rule[i] == "own") {
          rules$species_code[i]
        } else {
          paste0(rules$species_code[i], " rule ", rules$rule[i])
        }
        stop("observation_record_date: lift_floor: ", who, "'s lift counts ",
             paste(lst[!same], collapse = ", "), ", whose date floor differs ",
             "from its own; give them one floor", call. = FALSE)
      }
    }
  }
  rules
}

#' The rule parameters a lift reads, in `parameters_fresh.csv`'s names
#' @noRd
.lnk_lift_rules_params <- c(
  "observation_species", "observation_threshold", "observation_date_min",
  "observation_buffer_m", "observation_control_apply")

#' The columns `parameters_barrier_lifts.csv` must carry (its dictionary,
#' `dictionary_parameters_barrier_lifts.csv`, is tested against this)
#' @noRd
.lnk_lift_rules_required <- c(
  "species_code", "rule", "barrier_kinds", .lnk_lift_rules_params,
  "date", "source", "notes")

#' A date column read strictly: blank or `NA` is no floor, anything else must
#' parse
#' @noRd
.lnk_date_col <- function(x, what) {
  raw <- trimws(as.character(x))
  raw[raw %in% c("", "NA")] <- NA
  out <- as.Date(raw, optional = TRUE)
  if (any(!is.na(raw) & is.na(out))) {
    stop(what, " is not a date: ",
         paste(raw[!is.na(raw) & is.na(out)], collapse = ", "), call. = FALSE)
  }
  out
}
