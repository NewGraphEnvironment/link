#!/usr/bin/env Rscript
# habitat_variants_build.R — model habitat-threshold variants on ONE shared
# segmentation, for scoring against fish observations (link#284 step 5).
#
# Two full pipeline runs are not bit-reproducible (the PSCIS tie in
# lnk_pipeline_pscis_build.R moves a segment), so variants are never run
# independently. Instead:
#
#   base      lnk_pipeline_run() for the --base bundle (`default` unless
#             given) over the drainage closure of the focal WSGs, downstream
#             first, into <prefix><base variant>. The
#             focal WSGs keep their working schema (<working-prefix><wsg>), and
#             their access is re-settled against the whole closure
#             (lnk_access(merge = TRUE), as wsg_recompute_one.R does).
#   variants  per variant x focal WSG: re-run lnk_pipeline_classify() +
#             lnk_pipeline_connect() on that working schema with the
#             variant's thresholds, persist into <prefix><variant>, and copy
#             streams_access from the base schema (access does not read the
#             habitat thresholds).
#
# Each variant is a thin bundle generated from --variants (one cell of the
# base's parameters_habitat_thresholds.csv changed, plus any cells its
# optional `set` column fixes) into <out>/bundles/<variant>/, and loaded by
# path, so a scored schema always has a bundle on disk that says exactly what
# produced it. A variant whose optional `model` is `mad` (link#302) also
# carries a parameters_habitat_method.csv putting every WSG with a role for
# its species on `mad`; its working network must carry mad_m3s (#286). A
# model-only variant (link#300: no `column`, `model` mad, stepping from the
# base) changes no threshold cell, only the model. A variant with `dims`
# (link#364, "col=value;col=value" cells of the variant species' row in the
# base's dimensions.csv) carries its own dimensions.csv and a rules.yaml
# rebuilt from it by lnk_rules_build(). A structure variant (no `column`, on
# `cw`, stepping from the base, with `dims` and/or `set`) changes the rules or
# fixes cells without being a ladder rung, and is scored against the base.
#
# Invariants, asserted (the run stops on the first failure):
#   - every variant schema carries the same streams as the base schema, per
#     focal WSG (streams_access is copied from it, and checked after the copy);
#   - re-classifying with the base's own thresholds reproduces the base
#     run's working streams_habitat digest, so the re-classify path adds no
#     difference of its own;
#   - a variant marked `equals_bundle` has exactly that bundle's thresholds.
#
# Where the time goes (link#404): <out>/variant_timing.csv holds seconds per
# step for every pass (classify, connect, the working digest, persist, the
# access copy and ANALYZE, the gate, the persisted digests), which sum to the
# "done in" line, plus the discharge join before it and the base run's model
# and recompute per WSG, outside that total.
#
#   Rscript data-raw/habitat_variants_build.R \
#     [--variants=data-raw/habitat_score/variants.csv] \
#     [--roles=data-raw/habitat_score/wsg_roles.csv] \
#     [--wsgs=BULL]            focal subset (pre-flight); default: every
#                              WSG in --roles
#     [--only=default,x]       variant subset; default: all
#     [--step=all|base|variants|bundles] [--prefix=score284_]
#                              (bundles: write the variant bundles to --out and
#                              stop, touching no schema)
#     [--working-prefix=working_<prefix>]  (working_score_ for score284_)
#     [--out=data-raw/logs/habitat_score_284] [--allow-dirty]
#     [--base=default]         the base bundle; it must be the base row's
#                              `equals_bundle`
#     [--jobs=1]               groups of one variant's pass run at once
#                              (1 to 16; 1 is the serial loop)
#
# Width (link#406): with --jobs above 1 a variant's groups run on a PSOCK
# cluster started once for the variants step, each worker with its own
# connection and the longest groups dispatched first. Variants still run one
# after another (the base pass licenses the others), and only this process
# writes built.csv and variant_timing.csv, once a variant's groups return. A
# group that fails stops the build after the others return; every group whose
# checks passed is recorded first. A build killed mid-variant has recorded
# none of that variant's groups, though the schema may hold some of them, so
# re-run the variant before scoring it. Workers outlive a killed build, and a
# worker's database backend outlives the worker, still writing its group. The
# log names both ("variants: workers <R pid>:<backend pid> ..."): before
# relaunching, kill those R pids and pg_terminate_backend() those backends,
# or confirm in pg_stat_activity that none is left. `pkill -f workRSOCK`
# would also stop other sessions' workers.
#
# Resumable: a base WSG whose streams_access is already in the base schema
# (and, if focal, whose working schema survives) is not re-run. Variant passes
# always re-run; a variant classifies only its own species.
#
# Local docker fwapg (:5432) only. Launch long runs detached, and do not touch
# the repo while one runs: pkgload::load_all() and lnk_stamp read it.

suppressPackageStartupMessages({
  pkgload::load_all(quiet = TRUE)
  library(DBI)
})

opt <- function(name, default = NULL) {
  a <- grep(paste0("^--", name, "="), commandArgs(trailingOnly = TRUE),
            value = TRUE)
  if (length(a) == 0L) return(default)
  sub(paste0("^--", name, "="), "", a[length(a)])
}
split_csv <- function(x) {
  if (is.null(x)) return(character(0))
  v <- trimws(strsplit(x, ",")[[1]])
  v[nzchar(v)]
}
say <- function(...) {
  message(format(Sys.time(), "%H:%M:%S "), sprintf(...))
}

path_variants <- opt("variants", file.path("data-raw", "habitat_score",
                                           "variants.csv"))
path_roles <- opt("roles", file.path("data-raw", "habitat_score",
                                     "wsg_roles.csv"))
step <- opt("step", "all")
if (!step %in% c("all", "base", "variants", "bundles")) {
  stop("--step must be all, base, variants or bundles", call. = FALSE)
}
prefix <- opt("prefix", "score284_")
# The working schemas a base run keeps for its focal WSGs. #284's are
# working_score_<wsg>; a second scoring build needs its own, or its base run
# overwrites the first build's networks for the WSGs they share.
working_prefix <- opt("working-prefix",
                      if (identical(prefix, "score284_")) "working_score_" else
                        paste0("working_", prefix))
if (!grepl("^working_[a-z0-9_]*_$", working_prefix)) {
  stop("--working-prefix must start with 'working_', be lower-case and end in '_'",
       call. = FALSE)
}
if (!grepl("^[a-z][a-z0-9_]*_$", prefix)) {
  stop("--prefix must be lower-case and end in '_'", call. = FALSE)
}
dir_out <- opt("out", file.path("data-raw", "logs", "habitat_score_284"))
# The bundle the variants are generated from and the base is modelled with
# (link#300; #284 and #302 used `default`).
base_bundle <- opt("base", "default")
if (!grepl("^[a-z][a-z0-9_]*$", base_bundle)) {
  stop("--base must name a shipped bundle", call. = FALSE)
}
# Groups of one variant's pass run at once (link#406); 1 is the serial loop.
jobs <- opt("jobs", "1")
if (!grepl("^[0-9]{1,2}$", jobs) || !as.integer(jobs) %in% 1:16) {
  stop("--jobs must be a whole number from 1 to 16", call. = FALSE)
}
jobs <- as.integer(jobs)
# The defaults are #284's committed run; another variants file must not build
# into #284's schemas, working networks or logs.
if (!identical(path_variants, file.path("data-raw", "habitat_score", "variants.csv")) &&
    !all(c("prefix", "out") %in% sub("^--([^=]+)=.*", "\\1",
                                       commandArgs(trailingOnly = TRUE)))) {
  stop("--variants other than #284's needs an explicit --prefix and --out",
       call. = FALSE)
}

# A scored schema must be traceable to committed code and inputs.
dirty <- system(paste("git status --porcelain -- R inst/extdata/configs",
                      "data-raw/habitat_score data-raw/habitat_variants_build.R"),
                intern = TRUE)
head_sha <- system("git rev-parse --short HEAD", intern = TRUE)
if (length(dirty) > 0L && !"--allow-dirty" %in% commandArgs(TRUE)) {
  stop("uncommitted changes the build depends on (--allow-dirty to proceed):\n",
       paste(dirty, collapse = "\n"), call. = FALSE)
}

variants <- utils::read.csv(path_variants, colClasses = "character",
                            na.strings = "")
roles <- utils::read.csv(path_roles, colClasses = "character")
cols_variants <- c("variant", "species_code", "column", "value", "flag",
                   "obs_stage", "step_from", "equals_bundle")
# `model` and `set` (link#302) are optional, so #284's file stays valid: an
# absent or empty `model` is `cw`, an absent or empty `set` changes nothing.
# `discharge_source` and `discharge_fill` (link#331) are optional too: empty
# inherits the base bundle's, a value is written into the variant bundle's
# `pipeline:`, so one segmentation can score both sources and both fills.
# `dims` (link#364) is optional as well: empty changes no rule.
cols_optional <- c("model", "set", "discharge_source", "discharge_fill",
                   "dims")
for (k in cols_optional) {
  if (!k %in% names(variants)) variants[[k]] <- NA_character_
}
variants$model[is.na(variants$model)] <- "cw"
stopifnot(
  identical(setdiff(names(variants), cols_optional), cols_variants),
  all(is.na(variants$discharge_source) |
        variants$discharge_source %in% c("fwapg", "wet")),
  all(is.na(variants$discharge_fill) |
        variants$discharge_fill %in% c("TRUE", "FALSE")),
  all(variants$model %in% c("cw", "mad")),
  !anyDuplicated(variants$variant),
  all(grepl("^[a-z][a-z0-9_]*$", variants$variant)),
  sum(is.na(variants$step_from)) == 1L,
  identical(names(roles), c("watershed_group_code", "species_code", "role")),
  all(roles$role %in% c("held_out", "in_sample"))
)
# The base is the one row that steps from nothing (a model-only variant,
# link#300, also leaves `column` empty).
base_variant <- variants$variant[is.na(variants$step_from)]
# The base is modelled with the base bundle as it ships, so it sets neither.
if (!all(is.na(unlist(variants[variants$variant == base_variant,
                               c("discharge_source", "discharge_fill")])))) {
  stop("the base variant takes its discharge from --base; leave its ",
       "discharge_source and discharge_fill empty", call. = FALSE)
}
if (!is.na(variants$column[variants$variant == base_variant]) ||
    !is.na(variants$set[variants$variant == base_variant]) ||
    !is.na(variants$dims[variants$variant == base_variant])) {
  stop("the base variant changes no threshold or rule: its column, set and ",
       "dims must be empty", call. = FALSE)
}
if (!identical(variants$model[variants$variant == base_variant], "cw")) {
  stop("the base variant must be on the cw model", call. = FALSE)
}
# --base must be the bundle the base row says it equals, so a variants file
# cannot be built on a base it was not written for.
if (!identical(variants$equals_bundle[variants$variant == base_variant],
               base_bundle)) {
  stop("the base variant ", base_variant, " declares equals_bundle ",
       variants$equals_bundle[variants$variant == base_variant],
       ", not --base ", base_bundle, call. = FALSE)
}
# `set`: extra cells a variant fixes beside its `column`, as
# "col=value;col=value" (a MAD rung's open maximum, the spawning range a
# rearing ladder's clusters need). Parsed once, to a named character vector.
parse_set <- function(x) {
  if (is.na(x) || !nzchar(trimws(x))) return(stats::setNames(character(0), character(0)))
  kv <- strsplit(trimws(strsplit(x, ";", fixed = TRUE)[[1]]), "=", fixed = TRUE)
  if (!all(lengths(kv) == 2L)) stop("malformed set: ", x, call. = FALSE)
  out <- stats::setNames(trimws(vapply(kv, `[`, "", 2L)),
                         trimws(vapply(kv, `[`, "", 1L)))
  if (anyDuplicated(names(out)) || !all(nzchar(names(out))) ||
      !all(nzchar(out))) {
    stop("malformed set: ", x, call. = FALSE)
  }
  out
}
sets <- stats::setNames(lapply(variants$set, parse_set), variants$variant)
dims_of <- stats::setNames(lapply(variants$dims, parse_set), variants$variant)
# `set` may fix only MAD and near-river cells (link#364): a core is cut at
# default's gradient and width, so a set cell on either would make a band
# differ from the core on an axis the step is not about.
local({
  bad <- vapply(variants$variant, function(v) {
    !all(grepl("_mad_(min|max)$|_river_", names(sets[[v]])))
  }, logical(1))
  if (any(bad)) {
    stop("set may name only *_mad_min / *_mad_max / *_river_* cells: ",
         paste(variants$variant[bad], collapse = ", "), call. = FALSE)
  }
})
# A model-only variant (link#300) changes the habitat model and nothing else:
# it is on `mad`, steps from the base, names its species, and carries no
# value, flag or set (its bands are both flags, scored against the base).
model_only <- variants$variant[is.na(variants$column) &
                                 variants$variant != base_variant &
                                 variants$model == "mad"]
# A structure variant (link#364): no column, on cw, from the base, changing
# the rules (`dims`) and / or fixing cells (`set`), scored against the base
# as a model-only variant is, never a ladder rung.
structure_only <- variants$variant[is.na(variants$column) &
                                     variants$variant != base_variant &
                                     variants$model == "cw"]
local({
  r <- variants[variants$variant %in% model_only, ]
  bad <- r$variant[r$step_from != base_variant |
                     is.na(r$species_code) | !is.na(r$value) |
                     !is.na(r$flag) | lengths(sets[r$variant]) > 0L |
                     lengths(dims_of[r$variant]) > 0L |
                     !is.na(r$obs_stage) | !is.na(r$equals_bundle)]
  if (length(bad) > 0L) {
    stop("a mad variant with no column must be model-only (stepping from ",
         base_variant, ", with a species and no value, flag, obs_stage, ",
         "equals_bundle, set or dims): ", paste(bad, collapse = ", "),
         call. = FALSE)
  }
  r <- variants[variants$variant %in% structure_only, ]
  bad <- r$variant[r$step_from != base_variant |
                     is.na(r$species_code) | !is.na(r$value) |
                     !is.na(r$flag) | !is.na(r$obs_stage) |
                     !is.na(r$equals_bundle) |
                     (lengths(sets[r$variant]) == 0L &
                        lengths(dims_of[r$variant]) == 0L)]
  if (length(bad) > 0L) {
    stop("a cw variant with no column must be a structure variant (stepping ",
         "from ", base_variant, ", with a species, dims or set, and no value, ",
         "flag, obs_stage or equals_bundle): ", paste(bad, collapse = ", "),
         call. = FALSE)
  }
  # Nothing steps from either: neither is a ladder rung.
  off <- variants$variant[variants$step_from %in% c(model_only,
                                                     structure_only)]
  if (length(off) > 0L) {
    stop("no variant may step from a model-only or structure variant: ",
         paste(off, collapse = ", "), call. = FALSE)
  }
})
# The ladders must be well formed before anything runs: every step_from names
# a listed variant, and each variant is stepped from by at most one other, so
# every ladder is one chain out from the base (no cycle, no branch below it).
local({
  steps_from <- variants$step_from[variants$variant != base_variant]
  if (!all(steps_from %in% variants$variant)) {
    stop("step_from names no listed variant: ",
         paste(setdiff(steps_from, variants$variant), collapse = ", "),
         call. = FALSE)
  }
  below <- steps_from[steps_from != base_variant]
  if (anyDuplicated(below)) {
    stop("a ladder branches below the base at: ",
         paste(unique(below[duplicated(below)]), collapse = ", "),
         call. = FALSE)
  }
  for (v in variants$variant) {
    seen <- character(0)
    while (!identical(v, base_variant)) {
      if (v %in% seen) stop("step_from cycle through ", v, call. = FALSE)
      seen <- c(seen, v)
      v <- variants$step_from[variants$variant == v]
    }
  }
})
only <- split_csv(opt("only"))
if (length(only) > 0L) {
  bad <- setdiff(only, variants$variant)
  if (length(bad) > 0L) stop("--only names no variant: ", paste(bad, collapse = ", "),
                             call. = FALSE)
}
# Once each: two workers given one group would rebuild one working schema at
# once (link#406).
focal <- unique(toupper(split_csv(opt("wsgs"))))
if (length(focal) == 0L) focal <- unique(roles$watershed_group_code)
if (length(setdiff(focal, roles$watershed_group_code)) > 0L) {
  stop("--wsgs outside --roles: ",
       paste(setdiff(focal, roles$watershed_group_code), collapse = ", "),
       call. = FALSE)
}
# paste0() with a zero-length argument returns the bare prefix, not nothing.
schema_of <- function(v) if (length(v) == 0L) character(0) else paste0(prefix, v)
working_of <- function(w) paste0(working_prefix, tolower(w))

# One set of connection arguments, for this process and every worker.
conn_args <- list(dbname = "fwapg", host = "localhost", port = 5432L,
                  user = "postgres", password = "postgres")
conn <- do.call(lnk_db_conn, conn_args)
fs::dir_create(file.path(dir_out, "bundles"))

# -- the base bundle, and one thin bundle per variant --------------------------------
cfg_base <- lnk_config(base_bundle)
cfg_base$pipeline$schema <- schema_of(base_variant)
loaded <- suppressWarnings(lnk_load_overrides(cfg_base))
path_thr_base <- cfg_base$files$parameters_habitat_thresholds$path
thr_base <- utils::read.csv(path_thr_base, colClasses = "character")
meth_base <- utils::read.csv(cfg_base$files$parameters_habitat_method$path,
                                colClasses = "character")
dims_base <- utils::read.csv(cfg_base$dimensions, colClasses = "character",
                             check.names = FALSE, na.strings = character(0))
local({
  bad <- setdiff(unlist(lapply(dims_of, names)), names(dims_base))
  if (length(bad) > 0L) {
    stop("dims names no column of ", base_bundle, "'s dimensions.csv: ",
         paste(unique(bad), collapse = ", "), call. = FALSE)
  }
})
# Write a thresholds table in the shipped CSVs' shape: header and text columns
# quoted, numbers bare, NA bare. Proven on the base itself before any variant
# is written, so a variant bundle differs from the base in its own cells only.
write_thresholds <- function(thr, path) {
  # Quote the columns the committed file quotes: those holding a value that
  # is not a number (species_code, the edge-type lists, and since #364
  # rear_river_measure). A name list went stale when #364 added a column
  # (link#404), and the md5 check below is what catches that.
  is_text <- vapply(thr, function(x) {
    any(!is.na(x) & is.na(suppressWarnings(as.numeric(x))))
  }, logical(1))
  utils::write.csv(thr, path, row.names = FALSE, na = "NA",
                   quote = which(is_text))
}
local({
  tmp <- tempfile(fileext = ".csv")
  write_thresholds(thr_base, tmp)
  if (!identical(unname(tools::md5sum(tmp)),
                 unname(tools::md5sum(path_thr_base)))) {
    stop("re-writing ", base_bundle, "'s thresholds does not reproduce ",
         path_thr_base, " byte for byte", call. = FALSE)
  }
  unlink(tmp)
})

bundle_dir <- function(v) file.path(dir_out, "bundles", v)
write_bundle <- function(r) {
  thr <- thr_base
  is_model_only <- r$variant %in% c(model_only, structure_only)
  if (!is_model_only && !r$column %in% names(thr)) {
    stop("variant ", r$variant, ": no column ", r$column, call. = FALSE)
  }
  i <- which(thr$species_code == r$species_code)
  if (length(i) != 1L) {
    stop("variant ", r$variant, ": species ", r$species_code,
         " not in ", base_bundle, "'s thresholds", call. = FALSE)
  }
  # A model-only variant changes no cell (its `set` is empty, checked above);
  # a structure variant only its `set` cells.
  cells <- if (is_model_only) sets[[r$variant]] else
    c(stats::setNames(r$value, r$column), sets[[r$variant]])
  if (anyDuplicated(names(cells)) || !all(names(cells) %in% names(thr))) {
    stop("variant ", r$variant, ": set repeats its column or names no ",
         "threshold column", call. = FALSE)
  }
  # The rung's own cell must move: a rung that changes nothing is not a step.
  # A `set` cell the base already carries is dropped (link#331): #302's rungs
  # fix `*_mad_max = 9999`, which `default` has carried since #307.
  if (!is_model_only && identical(thr[[r$column]][i], r$value)) {
    stop("variant ", r$variant, " equals ", base_bundle, ": ", r$column,
         " is already ", r$value, call. = FALSE)
  }
  same <- names(cells)[vapply(names(cells), function(k) {
    identical(thr[[k]][i], cells[[k]])
  }, logical(1))]
  if (length(same) > 0L) {
    say("variant %s: %s already %s in %s, dropped from its set", r$variant,
        paste(same, collapse = ", "),
        paste(cells[same], collapse = ", "), base_bundle)
    cells <- cells[setdiff(names(cells), same)]
  }
  for (k in names(cells)) thr[[k]][i] <- cells[[k]]
  # Dims (link#364): the cells that move, and a structure variant must move
  # something, or it equals the base.
  dc <- dims_of[[r$variant]]
  j <- which(dims_base$species == r$species_code)
  if (length(dc) > 0L && length(j) != 1L) {
    stop("variant ", r$variant, ": species ", r$species_code, " not in ",
         base_bundle, "'s dimensions.csv", call. = FALSE)
  }
  dc <- dc[vapply(names(dc), function(k) {
    !identical(dims_base[[k]][j], dc[[k]])
  }, logical(1))]
  if (r$variant %in% structure_only && length(cells) == 0L &&
      length(dc) == 0L) {
    stop("variant ", r$variant, " equals ", base_bundle, ": its dims and set ",
         "change nothing", call. = FALSE)
  }
  n_diff <- sum(mapply(function(a, b) {
    sum(!((a == b) %in% TRUE) & !(is.na(a) & is.na(b)))
  }, thr, thr_base))
  if (n_diff != length(cells)) {
    stop("variant ", r$variant, " differs from ", base_bundle, " in ", n_diff,
         " cells, not ", length(cells), call. = FALSE)
  }
  d <- bundle_dir(r$variant)
  fs::dir_create(d)
  path_thr <- file.path(d, "parameters_habitat_thresholds.csv")
  write_thresholds(thr, path_thr)
  files <- list(parameters_habitat_thresholds = list(
    path = "parameters_habitat_thresholds.csv"))
  src_note <- sprintf("link (generated from configs/%s; %s row %s)",
                      base_bundle, basename(path_variants), r$variant)
  # Its own entry, or the inherited one would verify the base's copy.
  prov <- list(parameters_habitat_thresholds.csv = list(
    source = src_note,
    checksum = paste0("sha256:", digest::digest(file = path_thr,
                                                algo = "sha256"))))
  # Its own rules whenever they differ from the base's: when its dims move a
  # cell, and also when a threshold the builder bakes into the rules moves
  # (rear_lake_ha_min; rear_gradient_max on a `gradient` door), so a ladder on
  # such a cell classifies with the rules its value gives.
  dims <- dims_base
  for (k in names(dc)) dims[[k]][j] <- dc[[k]]
  path_dims <- file.path(d, "dimensions.csv")
  path_rules <- file.path(d, "rules.yaml")
  utils::write.csv(dims, path_dims, row.names = FALSE, na = "")
  suppressMessages(lnk_rules_build(path_dims, path_rules,
                                   thresholds = path_thr,
                                   edge_types = "explicit"))
  own_rules <- length(dc) > 0L ||
    !identical(yaml::read_yaml(path_rules), yaml::read_yaml(cfg_base$rules))
  if (!own_rules) unlink(c(path_dims, path_rules))
  if (own_rules) {
    for (f in c(path_dims, path_rules)) {
      prov[[basename(f)]] <- list(
        source = src_note,
        checksum = paste0("sha256:", digest::digest(file = f,
                                                    algo = "sha256")))
    }
  }
  if (identical(r$model, "mad")) {
    # Every WSG with a role for this species on `mad`, the rest as the base.
    path_meth <- file.path(d, "parameters_habitat_method.csv")
    w_mad <- unique(roles$watershed_group_code[
      roles$species_code == r$species_code])
    meth <- meth_base
    meth$model[meth$watershed_group_code %in% w_mad] <- "mad"
    meth <- rbind(meth, data.frame(
      watershed_group_code = setdiff(w_mad, meth$watershed_group_code),
      model = rep("mad", length(setdiff(w_mad, meth$watershed_group_code)))))
    meth <- meth[order(meth$watershed_group_code), ]
    utils::write.csv(meth, path_meth, row.names = FALSE, quote = FALSE)
    files$parameters_habitat_method <- list(
      path = "parameters_habitat_method.csv")
    prov$parameters_habitat_method.csv <- list(
      source = sprintf("link (generated from configs/%s; %s row %s)",
                       base_bundle, basename(path_variants), r$variant),
      checksum = paste0("sha256:", digest::digest(file = path_meth,
                                                  algo = "sha256")))
  }
  yaml::write_yaml(list(
    name = r$variant,
    description = sprintf(paste(
      "Habitat-threshold scoring variant, generated by",
      "data-raw/habitat_variants_build.R from %s: `%s` on the %s model",
      "with %s %s%s."), basename(path_variants), base_bundle, r$model,
      r$species_code,
      if (length(cells) == 0L) "on the base's thresholds" else
        paste(names(cells), cells, sep = " = ", collapse = ", "),
      if (length(dc) == 0L) "" else
        paste0("; dims ", paste(names(dc), dc, sep = " = ", collapse = ", "))),
    extends = base_bundle,
    rules = if (own_rules) "rules.yaml",
    dimensions = if (own_rules) "dimensions.csv",
    files = files,
    # Resolved and written, never inherited (link#331): the bundle extends
    # its base by name, so an inherited value would follow the base if it
    # later moved, and the bundle would no longer say what it was built on.
    pipeline = list(
      schema = schema_of(r$variant),
      discharge_source = if (is.na(r$discharge_source)) {
        .lnk_discharge_source(cfg_base)
      } else {
        r$discharge_source
      },
      discharge_fill = if (is.na(r$discharge_fill)) {
        .lnk_discharge_fill(cfg_base)
      } else {
        as.logical(r$discharge_fill)
      }),
    provenance = prov),
    file.path(d, "config.yaml"))
  cfg <- lnk_config(normalizePath(d))
  ver <- lnk_config_verify(cfg)
  if (own_rules) {
    # The bundle must resolve to its own rules and dimensions, verified
    # against its own provenance entries, not the base's.
    for (f in c("rules.yaml", "dimensions.csv")) {
      vf <- ver[ver$file == f, ]
      if (nrow(vf) != 1L || isTRUE(vf$byte_drift)) {
        stop("variant ", r$variant, ": its ", f, " does not verify against ",
             "its own provenance", call. = FALSE)
      }
    }
    if (!identical(normalizePath(cfg$rules), normalizePath(path_rules)) ||
        !identical(normalizePath(cfg$dimensions), normalizePath(path_dims))) {
      stop("variant ", r$variant, ": its rules or dimensions did not resolve ",
           "to the ones written for it", call. = FALSE)
    }
  }
  for (f in sub("$", ".csv", names(files))) {
    vf <- ver[ver$file == f, ]
    if (nrow(vf) != 1L || isTRUE(vf$byte_drift)) {
      stop("variant ", r$variant, ": its ", f, " does not verify against ",
           "its own provenance", call. = FALSE)
    }
  }
  if (!identical(normalizePath(cfg$files$parameters_habitat_method$path),
                 normalizePath(if (identical(r$model, "mad")) path_meth else
                   cfg_base$files$parameters_habitat_method$path))) {
    stop("variant ", r$variant, ": its method table did not resolve to the ",
         "one written for it", call. = FALSE)
  }
  if (!is.na(r$equals_bundle)) {
    a <- tools::md5sum(cfg$files$parameters_habitat_thresholds$path)
    b <- tools::md5sum(
      lnk_config(r$equals_bundle)$files$parameters_habitat_thresholds$path)
    if (!identical(unname(a), unname(b))) {
      stop("variant ", r$variant, " is declared equal to bundle ",
           r$equals_bundle, " but its thresholds differ", call. = FALSE)
    }
  }
  cfg
}
# The base re-classify is what licenses every variant (its digest check), so
# it runs in every variants pass, --only or not.
run_variants <- unique(c(base_variant,
                         if (length(only) > 0L) only else variants$variant))
# A bundle is written when its variant is built (run_variant()), and
# built.csv records the bundle sha each schema was built from once that
# schema's checks pass; the score stops when the two disagree.
cfgs <- list()
cfgs[[base_variant]] <- cfg_base
path_built <- file.path(dir_out, "built.csv")
# One row per variant x WSG, replaced only for the pair just built, so a
# build over a WSG subset cannot vouch for the WSGs it did not touch.
record_built <- function(v, w, built_at = Sys.time()) {
  row <- data.frame(
    variant = v, watershed_group_code = w, schema = schema_of(v),
    thresholds_sha256 = digest::digest(
      file = cfgs[[v]]$files$parameters_habitat_thresholds$path,
      algo = "sha256"),
    method_sha256 = digest::digest(
      file = cfgs[[v]]$files$parameters_habitat_method$path,
      algo = "sha256"),
    # The rules and dimensions it classified with (link#364): its own when
    # it carries dims, else the base's.
    rules_sha256 = digest::digest(file = cfgs[[v]]$rules, algo = "sha256"),
    dimensions_sha256 = digest::digest(file = cfgs[[v]]$dimensions,
                                       algo = "sha256"),
    # The discharge the variant classified on (#305): run_variant() refills
    # the working streams to the fill the bundle applies to w before
    # classify.
    discharge_fill = .lnk_discharge_fill_applied(cfgs[[v]], w),
    # and its source (#331): run_variant() rejoins from it.
    discharge_source = .lnk_discharge_source(cfgs[[v]]),
    link_head = head_sha, dirty = length(dirty) > 0L,
    built_at = format(built_at, "%Y-%m-%d %H:%M:%S %Z"))
  old <- if (file.exists(path_built)) {
    utils::read.csv(path_built, colClasses = "character")
  } else {
    NULL
  }
  # A built.csv from before link#302 has no method column: its schemas were
  # all built on default's method table, which is not recorded, so NA.
  if (!is.null(old) && !"method_sha256" %in% names(old)) {
    old$method_sha256 <- NA_character_
  }
  # Nor, before link#305, a fill column: those schemas were built raw.
  if (!is.null(old) && !"discharge_fill" %in% names(old)) {
    old$discharge_fill <- "FALSE"
  }
  # Nor, before link#331, a source column: those schemas read fwapg.
  if (!is.null(old) && !"discharge_source" %in% names(old)) {
    old$discharge_source <- "fwapg"
  }
  # Nor, before link#364, rules or dimensions shas: not recorded, so NA.
  for (k in c("rules_sha256", "dimensions_sha256")) {
    if (!is.null(old) && !k %in% names(old)) old[[k]] <- NA_character_
  }
  if (!is.null(old)) old <- old[names(row)]
  keep <- !(old$variant == v & old$watershed_group_code == w)
  utils::write.csv(rbind(old[keep, , drop = FALSE], row), path_built,
                   row.names = FALSE)
}

# -- digests: the invariants ------------------------------------------------------------
digest_sql <- list(
  streams = "SELECT md5(string_agg(id_segment::text || ':' ||
               round(length_metre::numeric, 3)::text, '|' ORDER BY id_segment))
               FROM %s.streams WHERE watershed_group_code = $1",
  streams_access = "SELECT md5(string_agg(t::text, '|' ORDER BY t.id_segment))
               FROM (SELECT * FROM %s.streams_access
                      WHERE watershed_group_code = $1) t")
digest_of <- function(schema, table, wsg) {
  dbGetQuery(conn, sprintf(digest_sql[[table]], schema),
             params = list(wsg))[[1]]
}
working_habitat_digest <- function(wsg) {
  dbGetQuery(conn, sprintf(
    "SELECT md5(string_agg(t::text, '|' ORDER BY id_segment, species_code))
       FROM %s.streams_habitat t", working_of(wsg)))[[1]]
}
path_base_digest <- file.path(dir_out, "base_habitat_digest.csv")
path_recompute <- file.path(dir_out, "base_recompute.csv")

# -- timing: where a pass's time goes (link#404) -----------------------------------------
# One row per variant x WSG x step in variant_timing.csv. A variant pass's
# seven steps (in_total TRUE) sum to the minutes its "done in" line prints;
# the discharge join before it, and the base run's model and recompute per
# WSG, are rows outside that total, for reference. Rows for the (variant,
# WSG, step) just written replace earlier ones, as built.csv's do.
path_timing <- file.path(dir_out, "variant_timing.csv")
secs_since <- function(t) as.numeric(difftime(Sys.time(), t, units = "secs"))
# The 1-minute load average when a pass starts: another session's load on
# this host is the known cause of a slow step (observation_breaks_396).
load_1min <- function() {
  up <- tryCatch(system("uptime", intern = TRUE), error = function(e) "")
  m <- regmatches(up, regexpr("load averages?: *[0-9.]+", up))
  if (length(m) == 0L) return(NA_real_)
  as.numeric(sub(".*: *", "", m))
}
n_segments_of <- function(wsg) {
  sch <- schema_of(base_variant)
  if (!dbExistsTable(conn, Id(schema = sch, table = "streams"))) return(NA_integer_)
  dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM %s.streams WHERE watershed_group_code = $1",
    sch), params = list(wsg))$n
}
record_timing <- function(v, w, species, seconds, in_total, load,
                          n_segments = n_segments_of(w), jobs = 1L,
                          built_at = Sys.time()) {
  row <- data.frame(
    variant = v, watershed_group_code = w,
    species = if (is.null(species)) "all" else paste(species, collapse = ","),
    step = names(seconds), seconds = round(unname(seconds), 3),
    in_total = rep_len(in_total, length(seconds)),
    n_segments = n_segments, load_1min = load,
    # The width the pass ran at (link#406); the base run is always serial.
    jobs = jobs,
    built_at = format(built_at, "%Y-%m-%d %H:%M:%S %Z"),
    link_head = head_sha,
    fresh_version = as.character(utils::packageVersion("fresh")))
  old <- if (file.exists(path_timing)) {
    utils::read.csv(path_timing, colClasses = "character")
  } else {
    NULL
  }
  # A variant_timing.csv from before link#406 has no jobs column: every pass
  # in it ran serially.
  if (!is.null(old) && !"jobs" %in% names(old)) old$jobs <- "1"
  if (!is.null(old)) {
    old <- old[names(row)]
    keep <- !(old$variant == v & old$watershed_group_code == w &
                old$step %in% names(seconds))
    old <- old[keep, , drop = FALSE]
  }
  utils::write.csv(rbind(old, row), path_timing, row.names = FALSE)
}

# -- base: the --base bundle over the closure, downstream first --------------------------
run_base <- function() {
  closure <- lnk_wsg_resolve(cfg_base, loaded, wsgs = focal, expand = TRUE,
                             conn = conn)
  say("base: %s, %d WSGs (focal %s) into %s", cfg_base$name,
      length(closure), paste(focal, collapse = ","), cfg_base$pipeline$schema)
  writeLines(closure, file.path(dir_out, "closure.txt"))
  sch <- cfg_base$pipeline$schema
  for (w in closure) {
    active <- lnk_pipeline_species(cfg_base, loaded, w)
    if (length(active) == 0L) {
      say("base %s: no modelled species, skipped", w)
      next
    }
    # Resume: access is persisted last, so it marks a finished WSG. It is
    # reused only when it was built from this commit with a clean tree (its
    # run-log row) and, if focal, its working schema and its digest in this
    # --out survive; anything else is re-run.
    done <- dbExistsTable(conn, Id(schema = sch, table = "streams_access")) &&
      nrow(dbGetQuery(conn, sprintf(
        "SELECT 1 FROM %s.streams_access WHERE watershed_group_code = $1
          LIMIT 1", sch), params = list(w))) > 0L &&
      isTRUE(dbGetQuery(conn, sprintf(
        "SELECT NOT link_dirty AND left(link_sha, %d) = $2 AS ok
           FROM %s.log WHERE watershed_group_code = $1
          ORDER BY date_start DESC LIMIT 1", nchar(head_sha), sch),
        params = list(w, head_sha))$ok) &&
      (!w %in% focal ||
         (dbExistsTable(conn, Id(schema = working_of(w), table = "streams")) &&
            file.exists(path_base_digest) &&
            w %in% utils::read.csv(path_base_digest)$watershed_group_code))
    if (done) {
      say("base %s: already persisted, skipped", w)
      next
    }
    guard <- lnk_wsg_downstream_check(conn, aoi = w, cfg = cfg_base,
                                      loaded = loaded, on_fail = "error")
    load <- load_1min()
    t0 <- Sys.time()
    lnk_pipeline_run(conn, aoi = w, cfg = cfg_base, loaded = loaded,
                     schema = working_of(w), mapping_code = FALSE,
                     cleanup_working = !w %in% focal, notes = guard$note)
    record_timing(base_variant, w, active, c(base_model = secs_since(t0)),
                  in_total = FALSE, load = load)
    if (w %in% focal) {
      # Written per WSG, so a resumed run keeps the digests already taken.
      dg <- if (file.exists(path_base_digest)) {
        utils::read.csv(path_base_digest, colClasses = "character")
      } else {
        data.frame(watershed_group_code = character(0), digest = character(0))
      }
      dg <- rbind(dg[dg$watershed_group_code != w, ],
                  data.frame(watershed_group_code = w,
                             digest = working_habitat_digest(w)))
      utils::write.csv(dg[order(dg$watershed_group_code), ], path_base_digest,
                       row.names = FALSE)
    }
    say("base %s done in %.1f min", w,
        as.numeric(difftime(Sys.time(), t0, units = "mins")))
  }
  # Re-settle access on the focal WSGs against the whole closure, after every
  # base WSG, as the post-consolidate recompute does (wsg_recompute_one.R,
  # whose timeouts, habitat gate and log_recompute row this repeats; its
  # mapping_code step does not apply, since the base run builds none).
  dbExecute(conn, "SET statement_timeout = '600000'")
  dbExecute(conn, "SET lock_timeout = '60000'")
  rc <- list()
  for (w in focal) {
    active <- lnk_pipeline_species(cfg_base, loaded, w)
    before <- digest_of(sch, "streams_access", w)
    load <- load_1min()
    t0 <- Sys.time()
    rlog <- .lnk_log_recompute_start(conn, cfg = cfg_base, aoi = w,
                                     views_prebuilt = FALSE)
    prior <- paste0(sch, ".zz_lnk_access_prior_", tolower(w))
    gate <- tryCatch({
      dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", prior))
      dbExecute(conn, sprintf(
        "CREATE TABLE %s AS SELECT * FROM %s.streams_access
          WHERE watershed_group_code = $1", prior, sch), params = list(w))
      lnk_access(conn, cfg_base, aoi = w,
                 table_streams = paste0(sch, ".streams"),
                 table_barriers = paste0(sch, ".barriers"),
                 table_to = paste0(sch, ".streams_access"),
                 merge = TRUE,
                 presence = lnk_presence(loaded$wsg_species_presence, w),
                 species = active)
      # Settle the persisted habitat on the recomputed access (link#349).
      g <- lnk_habitat_gate(conn, aoi = w,
                            table_habitat = paste0(sch, ".streams_habitat"),
                            table_access = paste0(sch, ".streams_access"),
                            table_streams = paste0(sch, ".streams"),
                            species = active,
                            overlay = .lnk_habitat_gate_overlay(cfg_base, loaded),
                            table_access_prior = prior)
      lnk_wsg_downstream_check(conn, aoi = w, cfg = cfg_base,
                               loaded = loaded, on_fail = "error")
      g
    }, error = function(e) {
      .lnk_log_recompute_fail(conn, cfg_base, rlog$recompute_id,
                              message = conditionMessage(e))
      stop(e)
    }, finally = dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", prior)))
    .lnk_log_recompute_finish(conn, cfg_base, rlog$recompute_id,
                              species = active, habitat_gate = gate)
    record_timing(base_variant, w, active, c(base_recompute = secs_since(t0)),
                  in_total = FALSE, load = load)
    same <- identical(before, digest_of(sch, "streams_access", w))
    rc[[w]] <- data.frame(watershed_group_code = w, access_unchanged = same)
    say("recompute %s: streams_access %s", w,
        if (same) "unchanged" else "CHANGED")
  }
  dbExecute(conn, "RESET statement_timeout")
  dbExecute(conn, "RESET lock_timeout")
  # Per WSG, so a base re-run over a subset keeps the others' rows. A report
  # only: a second recompute of merged access reads "unchanged" by design.
  old <- if (file.exists(path_recompute)) utils::read.csv(path_recompute) else NULL
  rc <- do.call(rbind, rc)
  rc <- rbind(old[!old$watershed_group_code %in% rc$watershed_group_code, ], rc)
  utils::write.csv(rc[order(rc$watershed_group_code), ], path_recompute,
                   row.names = FALSE)
}

# -- variants: re-classify on the shared network -------------------------------------------
copy_access <- function(from, to, wsg) {
  cols <- dbGetQuery(conn,
    "SELECT column_name FROM information_schema.columns
      WHERE table_schema = $1 AND table_name = 'streams_access'
      ORDER BY ordinal_position", params = list(to))$column_name
  cols_from <- dbGetQuery(conn,
    "SELECT column_name FROM information_schema.columns
      WHERE table_schema = $1 AND table_name = 'streams_access'",
    params = list(from))$column_name
  if (!setequal(cols, cols_from)) {
    stop("streams_access columns differ between ", from, " and ", to,
         call. = FALSE)
  }
  cl <- paste(cols, collapse = ", ")
  dbWithTransaction(conn, {
    dbExecute(conn, sprintf(
      "DELETE FROM %s.streams_access WHERE watershed_group_code = $1", to),
      params = list(wsg))
    dbExecute(conn, sprintf(
      "INSERT INTO %1$s.streams_access (%3$s)
       SELECT %3$s FROM %2$s.streams_access WHERE watershed_group_code = $1",
      to, from, cl), params = list(wsg))
  })
}

# One group's pass of variant v (link#406: the body of what was run_variant()'s
# loop). It runs in this process or on a cluster worker, so it reads only its
# arguments and the helpers every worker is given (variant_helpers), and it
# writes no file: it returns its step seconds, discharge-join seconds, load,
# working digest and, on failure, the message, and the caller records them.
# `want` is the base run's habitat digest for w (base pass only, else NA).
variant_pass <- function(w, v, cfg, sp, want, is_mad, sch_base) {
  sch <- cfg$pipeline$schema
  out <- list(watershed_group_code = w, error = NA_character_, tm = c(),
              s_join = NA_real_, load = NA_real_, digest = NA_character_,
              finished = NULL)
  tryCatch({
    if (!dbExistsTable(conn, Id(schema = working_of(w), table = "streams"))) {
      stop(working_of(w), " is gone: run --step=base first", call. = FALSE)
    }
    # The working streams carry the discharge of whichever bundle last
    # touched them; set it to this variant's fill (#305) and source (#331)
    # before classify, so a base built on one can score variants on another.
    out$load <- load_1min()
    t1 <- Sys.time()
    .lnk_discharge_join(conn, paste0(working_of(w), ".streams"), w,
                        fill = .lnk_discharge_fill_applied(cfg, w),
                        source = .lnk_discharge_source(cfg))
    out$s_join <- secs_since(t1)
    # A `mad` variant classifies on the discharge prepare joined onto the
    # working streams (#286). A working schema built before that join, or a
    # WSG with no discharge, would classify every inheriting stream rule
    # FALSE and read as a threshold verdict.
    if (is_mad) {
      has_col <- nrow(dbGetQuery(conn,
        "SELECT 1 FROM information_schema.columns
          WHERE table_schema = $1 AND table_name = 'streams'
            AND column_name = 'mad_m3s'", params = list(working_of(w)))) > 0L
      n_mad <- if (has_col) dbGetQuery(conn, sprintf(
        "SELECT count(mad_m3s) AS n FROM %s.streams", working_of(w)))$n else 0
      if (n_mad == 0) {
        stop(working_of(w), ".streams carries no mad_m3s: rebuild the base ",
             "(--step=base) at this HEAD", call. = FALSE)
      }
    }
    # The pass: seven steps, each timed into variant_timing.csv (link#404),
    # and their total on the "done in" line.
    t0 <- Sys.time()
    tm <- c()
    t1 <- Sys.time()
    lnk_pipeline_classify(conn, aoi = w, cfg = cfg, loaded = loaded,
                          schema = working_of(w), species = sp)
    tm["classify"] <- secs_since(t1)
    t1 <- Sys.time()
    lnk_pipeline_connect(conn, aoi = w, cfg = cfg, loaded = loaded,
                         schema = working_of(w), species = sp)
    tm["connect"] <- secs_since(t1)
    t1 <- Sys.time()
    dg <- working_habitat_digest(w)
    tm["digest_working"] <- secs_since(t1)
    out$digest <- dg
    if (!is.na(want) && !identical(dg, want)) {
      stop("re-classifying ", w, " with ", base_bundle, "'s thresholds gave habitat ",
           "digest ", dg, ", not the base run's ", want,
           ": the re-classify path is not a pure threshold change",
           call. = FALSE)
    }
    if (!is.null(sp)) {
      t1 <- Sys.time()
      lnk_pipeline_persist(conn, aoi = w, cfg = cfg, species = sp,
                           schema = working_of(w))
      tm["persist"] <- secs_since(t1)
      # The persisted access is the working copy, for this species only, and
      # from before the base's recompute. Access reads no habitat threshold
      # (classify and connect never touch it), so the base's recomputed rows,
      # every species, replace it.
      t1 <- Sys.time()
      copy_access(sch_base, sch, w)
      # Fresh statistics before the gate: its counts join the rows just
      # inserted, and planned on stale statistics (the planner sees about one
      # row for the group) one count ran for over 10 min where it takes 0.2 s
      # (link#364 build, CLWR / SQAM / BULK).
      for (tb in c("streams", "streams_access",
                   paste0("streams_habitat_", tolower(sp)))) {
        dbExecute(conn, sprintf("ANALYZE %s.%s", sch, tb))
      }
      tm["copy_access_analyze"] <- secs_since(t1)
      # The variant's persisted habitat follows that access, as the base's
      # does after its recompute (link#349).
      t1 <- Sys.time()
      lnk_habitat_gate(conn, aoi = w,
                       table_habitat = paste0(sch, ".streams_habitat"),
                       table_access = paste0(sch, ".streams_access"),
                       table_streams = paste0(sch, ".streams"),
                       species = sp,
                       overlay = .lnk_habitat_gate_overlay(cfg, loaded))
      tm["gate"] <- secs_since(t1)
    }
    t1 <- Sys.time()
    for (tb in names(digest_sql)) {
      if (!identical(digest_of(sch, tb, w), digest_of(sch_base, tb, w))) {
        stop(sch, ".", tb, " differs from ", sch_base, " in ", w,
             call. = FALSE)
      }
    }
    tm["digest_persist"] <- secs_since(t1)
    out$tm <- tm
    out$finished <- Sys.time()
    say("variant %s %s steps (min): %s", v, w,
        paste(sprintf("%s %.2f", names(tm), tm / 60), collapse = ", "))
    say("variant %s %s done in %.1f min (habitat %s)", v, w,
        secs_since(t0) / 60, substr(dg, 1, 8))
  }, error = function(e) {
    out$error <<- conditionMessage(e)
    say("variant %s %s FAILED: %s", v, w, conditionMessage(e))
  })
  out
}
# The worker's call: `want` is the named vector of every group's base digest,
# so one function and one set of arguments serve every group of a pass.
variant_pass_lb <- function(w, want, ...) variant_pass(w, want = want[[w]], ...)
# What a cluster worker needs to run variant_pass() (link#406): the helpers
# it calls and the objects they read, besides its own `conn`.
variant_helpers <- c("variant_pass", "variant_pass_lb", "working_prefix",
                     "working_of",
                     "digest_sql", "digest_of", "working_habitat_digest",
                     "copy_access", "secs_since", "load_1min", "say",
                     "base_bundle", "loaded")
start_cluster <- function(n) {
  say("variants: starting %d workers", n)
  cl <- parallel::makeCluster(n, outfile = "")
  ok <- FALSE
  on.exit(if (!ok) parallel::stopCluster(cl))
  parallel::clusterCall(cl, setwd, getwd())
  parallel::clusterExport(cl, c(variant_helpers, "conn_args"))
  parallel::clusterEvalQ(cl, {
    suppressPackageStartupMessages({
      pkgload::load_all(quiet = TRUE)
      library(DBI)
    })
    conn <- do.call(lnk_db_conn, conn_args)
    NULL
  })
  pids <- parallel::clusterEvalQ(cl, sprintf("%d:%d", Sys.getpid(),
    DBI::dbGetQuery(conn, "SELECT pg_backend_pid()")[[1]]))
  say("variants: workers %s", paste(unlist(pids), collapse = " "))
  ok <- TRUE
  cl
}

# The record of one group's pass: built.csv once its checks passed, and its
# rows in variant_timing.csv, stamped when the group finished (a cluster's
# results are recorded only once every group has returned).
record_pass <- function(v, sp, r) {
  record_built(v, r$watershed_group_code, built_at = r$finished)
  record_timing(v, r$watershed_group_code, sp, c(discharge_join = r$s_join, r$tm),
                in_total = c(FALSE, rep(TRUE, length(r$tm))), load = r$load,
                jobs = jobs, built_at = r$finished)
}

run_variant <- function(v, cl = NULL) {
  if (!identical(v, base_variant)) {
    cfgs[[v]] <<- write_bundle(as.list(variants[variants$variant == v, ]))
  }
  cfg <- cfgs[[v]]
  sch <- cfg$pipeline$schema
  sch_base <- schema_of(base_variant)
  base_digest <- utils::read.csv(path_base_digest, colClasses = "character")
  sp_v <- variants$species_code[variants$variant == v]
  # The base re-classifies every species (its digest is the whole table); a
  # variant only its own, in the WSGs where that species has a role.
  is_base <- identical(v, base_variant)
  wsgs_v <- if (is_base) focal else
    intersect(focal, roles$watershed_group_code[roles$species_code == sp_v])
  sp <- if (is_base) NULL else sp_v
  # The base pass is checked against the base run's digest of each group.
  want <- stats::setNames(rep(NA_character_, length(wsgs_v)), wsgs_v)
  if (is_base) {
    for (w in wsgs_v) {
      d <- base_digest$digest[base_digest$watershed_group_code == w]
      # NA means "no check" to variant_pass(), so a base digest that is NA
      # (a working table with no rows) must not reach it.
      if (length(d) != 1L || is.na(d)) {
        stop("no base habitat digest for ", w, " in ", path_base_digest,
             ": run --step=base with this --out first", call. = FALSE)
      }
      want[[w]] <- d
    }
  }
  is_mad <- identical(variants$model[variants$variant == v], "mad")
  say("variant %s into %s (%s)%s", v, sch, paste(wsgs_v, collapse = ","),
      if (is.null(cl)) "" else sprintf(", %d jobs", length(cl)))
  # Sized to the whole bundle (link#194), as lnk_pipeline_run does. Once per
  # variant, so its row has no group.
  load <- load_1min()
  t1 <- Sys.time()
  lnk_persist_init(conn, cfg, species = cfg$species)
  record_timing(v, "", NULL, c(persist_init = secs_since(t1)),
                in_total = FALSE, load = load, n_segments = NA_integer_,
                jobs = jobs)
  t_pass <- Sys.time()
  if (is.null(cl)) {
    # Serial: each group is recorded as it finishes, and the first failure
    # stops the build.
    for (w in wsgs_v) {
      r <- variant_pass(w, v, cfg, sp, want[[w]], is_mad, sch_base)
      if (!is.na(r$error)) stop(r$error, call. = FALSE)
      record_pass(v, sp, r)
    }
  } else {
    # Longest groups first, so the last to start is a short one.
    n_seg <- vapply(wsgs_v, n_segments_of, integer(1))
    ord <- wsgs_v[order(-n_seg, wsgs_v)]
    res <- parallel::clusterApplyLB(cl, ord, variant_pass_lb, want = want,
                                    v = v, cfg = cfg, sp = sp, is_mad = is_mad,
                                    sch_base = sch_base)
    names(res) <- ord
    # Recorded in the order the serial loop records them.
    res <- res[wsgs_v]
    failed <- character(0)
    for (w in wsgs_v) {
      if (is.na(res[[w]]$error)) record_pass(v, sp, res[[w]]) else failed <- c(failed, w)
    }
    if (length(failed) > 0L) {
      stop("variant ", v, " failed in ", paste(failed, collapse = ", "), ":\n",
           paste(vapply(res[failed], `[[`, "", "error"), collapse = "\n"),
           call. = FALSE)
    }
  }
  # First dispatch to last return: the number a width is judged on (#406).
  record_timing(v, "", sp, c(pass_wall = secs_since(t_pass)), in_total = FALSE,
                load = load, n_segments = NA_integer_, jobs = jobs)
  say("variant %s: %d groups in %.1f min at %d job%s", v, length(wsgs_v),
      secs_since(t_pass) / 60, jobs, if (jobs == 1L) "" else "s")
}

# -- stamp ---------------------------------------------------------------------------------
write_stamp <- function() {
  fresh_sha <- .lnk_pkg_git_sha("fresh")
  bundle_hash <- vapply(names(cfgs), function(v) {
    substr(digest::digest(file = cfgs[[v]]$files$parameters_habitat_thresholds$path,
                          algo = "sha256"), 1, 12)
  }, character(1))
  run_uid <- dbGetQuery(conn, sprintf(
    "SELECT string_agg(DISTINCT run_uid, ', ') FROM %s.log
      WHERE watershed_group_code = ANY($1)", schema_of(base_variant)),
    params = list(paste0("{", paste(focal, collapse = ","), "}")))[[1]]
  # Appended, one block per invocation: a resumed or partial run must not
  # erase the record of the one before it.
  cat(c(
    "---",
    sprintf("date: %s", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
    sprintf("step: %s; focal: %s; variants: %s", step,
            paste(focal, collapse = ","), paste(run_variants, collapse = ",")),
    sprintf("link: %s @ %s%s (at launch)", utils::packageVersion("link"),
            head_sha,
            if (length(dirty) > 0L) " (dirty, --allow-dirty)" else ""),
    sprintf("base: %s", base_bundle),
    sprintf("variants: %s (md5 %s); roles: %s (md5 %s)", path_variants,
            unname(tools::md5sum(path_variants)), path_roles,
            unname(tools::md5sum(path_roles))),
    sprintf("fresh: %s @ %s", utils::packageVersion("fresh"),
            if (is.na(fresh_sha)) "no recorded sha" else fresh_sha),
    "db: docker fwapg localhost:5432",
    sprintf("base run_uid(s) in %s.log: %s", schema_of(base_variant),
            if (is.na(run_uid)) "none" else run_uid),
    sprintf("bcfishobs.observations rows: %s",
            dbGetQuery(conn, "SELECT count(*) FROM bcfishobs.observations")[[1]]),
    sprintf("thresholds sha256 (12): %s",
            paste(names(bundle_hash), bundle_hash, sep = "=", collapse = ", ")),
    ""), file = file.path(dir_out, "stamp_build.txt"), sep = "\n",
    append = TRUE)
}

t_all <- Sys.time()
if (identical(step, "bundles")) {
  for (v in setdiff(run_variants, base_variant)) {
    write_bundle(as.list(variants[variants$variant == v, ]))
  }
  say("bundles written to %s", file.path(dir_out, "bundles"))
  dbDisconnect(conn)
  quit(save = "no")
}
if (step %in% c("all", "base")) run_base()
if (step %in% c("all", "variants")) {
  # Started after the base, so no worker holds a connection through it, and
  # stopped however the variants end (on.exit() never fires at top level).
  cl <- if (jobs > 1L) start_cluster(jobs) else NULL
  tryCatch({
    # The base variant first: its digest check is what licenses the others.
    for (v in run_variants) {
      run_variant(v, cl)
    }
  }, finally = if (!is.null(cl)) parallel::stopCluster(cl))
}
write_stamp()
say("build %s done in %.1f min", step,
    as.numeric(difftime(Sys.time(), t_all, units = "mins")))
dbDisconnect(conn)
