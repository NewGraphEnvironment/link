# Output vocabulary (#414): one tracked table of permanent tokens that say
# what an output is, and the resolver that derives a build's tokens from its
# config. Four axes, each an input choice, never a result or a data vintage:
#
#   cut   how streams were cut: break sources in order, observation breaks,
#         gradient classes
#   acc   the access rules that decide which gradient positions cut (#326):
#         modelled species, per-species access gradients and observation
#         lifts, species presence
#   grad  how a segment's gradient was measured
#   flow  where a stream's discharge came from
#
# Threshold tuning, width against flow, and data vintage (observation records,
# the bcfishpass correction CSVs, FWA) get no token: the build record carries
# them (`config_hash`, `log_input`).

#' Read link's output vocabulary
#'
#' The table of tokens that name what an output is: how its streams were cut
#' (`cut`), which access rules decided where gradient barriers cut them
#' (`acc`), how its gradient was measured (`grad`) and where its discharge came
#' from (`flow`). [lnk_vocabulary_resolve()] matches a config against it, and
#' every [lnk_pipeline_run()] records the four tokens in its `<schema>.log`
#' row.
#'
#' Tokens are lowercase, never renamed and never reused. A changed definition
#' is a new token, and a retired token stays in the table so old names still
#' decode. Consumers read this table (or `inst/extdata/vocabulary.csv` at a
#' release tag) rather than copying it.
#'
#' @return A data frame, one row per token, with columns `token`, `axis`
#'   (`cut`, `acc`, `grad` or `flow`), `definition` (prose), `spec` (the
#'   canonical string or digest [lnk_vocabulary_resolve()] matches),
#'   `introduced` (the link version that added it) and `retired` (the link
#'   version that retired it, `NA` while live).
#'
#' @family vocabulary
#' @export
#'
#' @examples
#' v <- lnk_vocabulary_read()
#' v[, c("token", "axis", "introduced")]
lnk_vocabulary_read <- function() {
  path <- system.file("extdata", "vocabulary.csv", package = "link")
  if (!nzchar(path)) {
    stop("link's vocabulary.csv not found: is link installed?", call. = FALSE)
  }
  .lnk_vocabulary_read_path(path)
}

.lnk_vocabulary_read_path <- function(path) {
  v <- utils::read.csv(path, colClasses = "character", na.strings = "",
                       strip.white = FALSE, encoding = "UTF-8")
  cols <- c("token", "axis", "definition", "spec", "introduced", "retired")
  if (!identical(names(v), cols)) {
    stop("vocabulary.csv columns must be ", paste(cols, collapse = ", "),
         "; found ", paste(names(v), collapse = ", "), call. = FALSE)
  }
  # A blank key cell would match nothing and everything (NA comparisons), so
  # the table refuses it here rather than letting a resolve return NA.
  for (col in c("token", "axis", "spec", "introduced")) {
    bad <- which(is.na(v[[col]]) | !nzchar(trimws(v[[col]])))
    if (length(bad) > 0L) {
      stop("vocabulary.csv: blank ", col, " in row(s) ",
           paste(bad, collapse = ", "), call. = FALSE)
    }
  }
  v
}

#' Name a config's output in the vocabulary
#'
#' Derives each axis's specification from what a build under `cfg` would
#' actually read, and matches it against [lnk_vocabulary_read()]:
#'
#' - **cut:** the break sources in the order applied (`pipeline:
#'   break_order`, or its default), the observation breaks (`all` or
#'   `top_per_species`; only when `observations` is a source) and the
#'   gradient classes streams are broken at (`pipeline: gradient_classes`,
#'   or bcfishpass's 15 / 20 / 25 / 30 %), and which of the definite
#'   barrier, barrier control and habitat classification files the bundle
#'   declares (their rows are data, which the build record carries).
#' - **acc:** a sha256 digest of the access rules, which decide where
#'   gradient barriers cut streams as well as what is accessible: the
#'   species the rules model, each species' `access_gradient_max` and
#'   `observation_*` lift parameters, the species presence table, which fish
#'   records make code 2 (`pipeline: observation_upstream`, resolved), and the
#'   two access rules held in code (the gradient class each access label
#'   maps to, and [lnk_presence()]'s species groups). The
#'   digest is over the parsed values, so a change in quoting or column
#'   order is not a new rule set.
#' - **grad:** `gradient=segment`, the only measure link builds today.
#' - **flow:** `pipeline: discharge_source` and `pipeline: discharge_fill`.
#'
#' A config whose specification matches no token, or only a retired one,
#' is refused: the new output gets a name (a row in
#' `inst/extdata/vocabulary.csv`) before anything is built.
#'
#' @param cfg An `lnk_config` object from [lnk_config()].
#' @param loaded Named list from [lnk_load_overrides()]. Loaded from `cfg`
#'   when `NULL`.
#'
#' @return A named character vector `c(cut = , acc = , grad = , flow = )`.
#'
#' @family vocabulary
#' @export
#'
#' @examples
#' lnk_vocabulary_resolve(lnk_config("default"))
#' lnk_vocabulary_resolve(lnk_config("bcfishpass"))
lnk_vocabulary_resolve <- function(cfg, loaded = NULL) {
  stopifnot(inherits(cfg, "lnk_config"))
  if (is.null(loaded)) loaded <- lnk_load_overrides(cfg)
  stopifnot(is.list(loaded))
  .lnk_vocabulary_match(.lnk_vocabulary_specs(cfg, loaded),
                        lnk_vocabulary_read(), cfg$name)
}

# The four specification strings for `cfg`, named by axis.
.lnk_vocabulary_specs <- function(cfg, loaded) {
  c(cut  = .lnk_vocabulary_spec_cut(cfg, loaded),
    acc  = .lnk_vocabulary_spec_acc(cfg, loaded),
    grad = "gradient=segment",
    flow = .lnk_vocabulary_spec_flow(cfg))
}

.lnk_vocabulary_spec_cut <- function(cfg, loaded) {
  order <- .lnk_break_order(cfg)
  # Names and values as the pipeline reads them: the name is the class a
  # gradient break is labelled with, which classify parses as its threshold.
  classes <- .lnk_resolve_classes(NULL, cfg)
  parts <- c(
    paste0("break_order=", paste(order, collapse = ",")),
    if ("observations" %in% order) {
      paste0("observation_breaks=", .lnk_observation_breaks(cfg))
    },
    paste0("gradient_classes=",
           paste(names(classes), .lnk_vocabulary_num(classes), sep = ":",
                 collapse = ",")),
    paste0("barrier_inputs=",
           paste(Filter(function(k) !is.null(loaded[[k]]),
                        .lnk_vocabulary_barrier_inputs),
                 collapse = ",")))
  paste(parts, collapse = ";")
}

# Bundle files whose presence, not just their rows, switches a cut or a lift
# on: definite barriers join every species' barrier set and cut streams, the
# control table prunes gradient barriers and lifts, and the habitat
# classification adds habitat lifts and the habitat end points cuts. Their
# rows are data vintage (the build record); whether the run has them is
# method, read from `loaded` as prepare reads it (`!is.null(loaded$<key>)`).
.lnk_vocabulary_barrier_inputs <- c(
  "user_barriers_definite", "user_barriers_definite_control",
  "user_habitat_classification")

.lnk_vocabulary_spec_flow <- function(cfg) {
  sprintf("discharge_source=%s;discharge_fill=%s",
          .lnk_discharge_source(cfg),
          tolower(as.character(.lnk_discharge_fill(cfg))))
}

# The access columns of parameters_fresh that move barriers: each species'
# access gradient and the observation lifts (RUNBOOK §7, "Who owns which
# parameters_fresh column").
.lnk_vocabulary_acc_cols <- c(
  "species_code", "access_gradient_max", "observation_threshold",
  "observation_date_min", "observation_buffer_m", "observation_species",
  "observation_control_apply")

.lnk_vocabulary_spec_acc <- function(cfg, loaded) {
  pf <- loaded$parameters_fresh
  pres <- loaded$wsg_species_presence
  if (is.null(pf) || is.null(pres)) {
    stop("config '", cfg$name, "': the acc axis needs parameters_fresh and ",
         "wsg_species_presence", call. = FALSE)
  }
  miss <- setdiff(.lnk_vocabulary_acc_cols, names(pf))
  if (length(miss) > 0L) {
    stop("config '", cfg$name, "': parameters_fresh lacks ",
         paste(miss, collapse = ", "), call. = FALSE)
  }
  pres <- pres[, c("watershed_group_code",
                   .lnk_presence_species_cols(pres)), drop = FALSE]
  # Rows are sorted before hashing, which is safe only while each key is
  # unique: the pipeline takes a species' first parameters_fresh row and
  # refuses a group with two presence rows (lnk_presence()).
  for (k in list(list(pf$species_code, "parameters_fresh species_code"),
                 list(pres$watershed_group_code,
                      "wsg_species_presence watershed_group_code"))) {
    dup <- unique(k[[1]][duplicated(k[[1]])])
    if (length(dup) > 0L) {
      stop("config '", cfg$name, "': duplicate ", k[[2]], ": ",
           paste(dup, collapse = ", "), call. = FALSE)
    }
  }
  # Two rules held in code also decide access: the gradient classes a
  # species' access label maps to, and which present species make another
  # present (lnk_presence()'s groups). A change to either is a new rule set.
  groups <- eval(formals(lnk_presence)$groups)
  payload <- paste(
    paste0("species=", paste(cfg$species, collapse = ",")),
    paste0("observation_upstream=", .lnk_observation_upstream(cfg)),
    paste0("access_classes=",
           paste(names(.lnk_classes_bcfp),
                 .lnk_vocabulary_num(.lnk_classes_bcfp), sep = ":",
                 collapse = ",")),
    paste0("presence_groups=",
           paste(names(groups),
                 vapply(groups, paste, character(1), collapse = ","),
                 sep = ":", collapse = ";")),
    .lnk_vocabulary_canonical(pf[, .lnk_vocabulary_acc_cols, drop = FALSE]),
    .lnk_vocabulary_canonical(pres),
    sep = "\n--\n")
  paste0("sha256:",
         digest::digest(payload, algo = "sha256", serialize = FALSE))
}

# A double as text that reads back to the same double: as.character() where
# it round-trips (0.15), 17 significant digits where it does not
# (0.15000000000000002), so two values the pipeline compares differently
# never share a spec.
.lnk_vocabulary_num <- function(x) {
  out <- as.character(x)
  lossy <- !is.na(x) & as.numeric(out) != x
  out[lossy] <- sprintf("%.17g", x[lossy])
  unname(out)
}

# A data frame as text that does not depend on how its file was written:
# columns by name, rows sorted, each value as R reads it (doubles exactly), with
# NA kept apart from "" and the delimiters escaped. Values are never folded
# (no trimming, no "t" = "TRUE"): readers of these tables test values
# exactly (`.lnk_wsg_species_present()` counts only "t"), so two spellings
# can model different species and must digest differently. Radix sorts are
# C-locale, so the digest does not depend on the session's collation.
.lnk_vocabulary_canonical <- function(df) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  cols <- sort(names(df), method = "radix")
  enc <- function(v) {
    num <- is.double(v) && !inherits(v, c("Date", "POSIXt", "difftime"))
    out <- if (num) .lnk_vocabulary_num(v) else as.character(v)
    out <- gsub("\\", "\\\\", out, fixed = TRUE)
    out <- gsub("\t", "\\t", out, fixed = TRUE)
    out <- gsub("\n", "\\n", out, fixed = TRUE)
    out[is.na(v)] <- "\\N"
    out
  }
  header <- paste(enc(cols), collapse = "\t")
  if (nrow(df) == 0L) return(header)
  txt <- matrix(vapply(cols, function(c) enc(df[[c]]), character(nrow(df))),
                nrow = nrow(df))
  rows <- apply(txt, 1L, paste, collapse = "\t")
  paste(c(header, sort(rows, method = "radix")), collapse = "\n")
}

# Match each axis's spec to one live token, or refuse with the spec that
# needs a row.
.lnk_vocabulary_match <- function(specs, vocab, name = "") {
  out <- vapply(names(specs), function(axis) {
    hit <- vocab[which(vocab$axis == axis & vocab$spec == specs[[axis]]), ,
                 drop = FALSE]
    live <- hit[is.na(hit$retired), , drop = FALSE]
    if (nrow(live) == 1L) return(live$token)
    if (nrow(live) > 1L) {
      stop("vocabulary.csv: ", nrow(live), " live ", axis, " tokens share ",
           "one spec (", paste(live$token, collapse = ", "), ")",
           call. = FALSE)
    }
    if (nrow(hit) > 0L) {
      stop("config '", name, "': its ", axis, " spec matches only the ",
           "retired token ", paste(hit$token, collapse = ", "),
           "; a build under a retired definition needs a new token in ",
           "inst/extdata/vocabulary.csv", call. = FALSE)
    }
    stop("config '", name, "': no ", axis, " token in ",
         "inst/extdata/vocabulary.csv has the spec\n  ", specs[[axis]],
         "\nAdd a row naming this output before building it ",
         "(RUNBOOK, \"Output vocabulary\")", call. = FALSE)
  }, character(1))
  names(out) <- names(specs)
  out
}
