#!/usr/bin/env Rscript
# habitat_variants_build.R — model habitat-threshold variants on ONE shared
# segmentation, for scoring against fish observations (link#284 step 5).
#
# Two full pipeline runs are not bit-reproducible (the PSCIS tie in
# lnk_pipeline_pscis_build.R moves a segment), so variants are never run
# independently. Instead:
#
#   base      lnk_pipeline_run() for `default` over the drainage closure of
#             the focal WSGs, downstream first, into <prefix>default. The
#             focal WSGs keep their working schema (working_score_<wsg>), and
#             their access is re-settled against the whole closure
#             (lnk_access(merge = TRUE), as wsg_recompute_one.R does).
#   variants  per variant x focal WSG: re-run lnk_pipeline_classify() +
#             lnk_pipeline_connect() on that working schema with the
#             variant's thresholds, persist into <prefix><variant>, and copy
#             streams_access from <prefix>default (access does not read the
#             habitat thresholds).
#
# Each variant is a thin bundle generated from --variants (one cell of
# `default`'s parameters_habitat_thresholds.csv changed) into
# <out>/bundles/<variant>/, and loaded by path, so a scored schema always has
# a bundle on disk that says exactly what produced it.
#
# Invariants, asserted (the run stops on the first failure):
#   - every variant schema carries the same streams as <prefix>default, per
#     focal WSG (streams_access is copied from it, and checked after the copy);
#   - re-classifying with `default`'s own thresholds reproduces the base
#     run's working streams_habitat digest, so the re-classify path adds no
#     difference of its own;
#   - a variant marked `equals_bundle` has exactly that bundle's thresholds.
#
#   Rscript data-raw/habitat_variants_build.R \
#     [--variants=data-raw/habitat_score/variants.csv] \
#     [--roles=data-raw/habitat_score/wsg_roles.csv] \
#     [--wsgs=BULL]            focal subset (pre-flight); default: every
#                              WSG in --roles
#     [--only=default,x]       variant subset; default: all
#     [--step=all|base|variants] [--prefix=score284_]
#     [--out=data-raw/logs/habitat_score_284] [--allow-dirty]
#
# Resumable: a base WSG whose streams_access is already in <prefix>default
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
if (!step %in% c("all", "base", "variants")) {
  stop("--step must be all, base or variants", call. = FALSE)
}
prefix <- opt("prefix", "score284_")
if (!grepl("^[a-z][a-z0-9_]*_$", prefix)) {
  stop("--prefix must be lower-case and end in '_'", call. = FALSE)
}
dir_out <- opt("out", file.path("data-raw", "logs", "habitat_score_284"))

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
stopifnot(
  identical(names(variants), c("variant", "species_code", "column", "value",
                               "flag", "obs_stage", "step_from",
                               "equals_bundle")),
  !anyDuplicated(variants$variant),
  all(grepl("^[a-z][a-z0-9_]*$", variants$variant)),
  sum(is.na(variants$column)) == 1L,
  identical(names(roles), c("watershed_group_code", "species_code", "role")),
  all(roles$role %in% c("held_out", "in_sample"))
)
base_variant <- variants$variant[is.na(variants$column)]
# The ladders must be well formed before anything runs: every step_from names
# a listed variant, and each variant is stepped from by at most one other, so
# every ladder is one chain out from the base (no cycle, no branch below it).
local({
  steps_from <- variants$step_from[!is.na(variants$column)]
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
focal <- toupper(split_csv(opt("wsgs")))
if (length(focal) == 0L) focal <- unique(roles$watershed_group_code)
if (length(setdiff(focal, roles$watershed_group_code)) > 0L) {
  stop("--wsgs outside --roles: ",
       paste(setdiff(focal, roles$watershed_group_code), collapse = ", "),
       call. = FALSE)
}
schema_of <- function(v) paste0(prefix, v)
working_of <- function(w) paste0("working_score_", tolower(w))

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
fs::dir_create(file.path(dir_out, "bundles"))

# -- the base bundle, and one thin bundle per variant --------------------------------
cfg_default <- lnk_config("default")
cfg_default$pipeline$schema <- schema_of(base_variant)
loaded <- suppressWarnings(lnk_load_overrides(cfg_default))
path_thr_default <- cfg_default$files$parameters_habitat_thresholds$path
thr_default <- utils::read.csv(path_thr_default, colClasses = "character")
# Write a thresholds table in the shipped CSVs' shape: header and text columns
# quoted, numbers bare, NA bare. Proven on `default` itself before any variant
# is written, so a variant bundle differs from `default` in its one cell only.
write_thresholds <- function(thr, path) {
  utils::write.csv(thr, path, row.names = FALSE, na = "NA",
                   quote = which(names(thr) == "species_code" |
                                   grepl("_edge_types$", names(thr))))
}
local({
  tmp <- tempfile(fileext = ".csv")
  write_thresholds(thr_default, tmp)
  if (!identical(unname(tools::md5sum(tmp)),
                 unname(tools::md5sum(path_thr_default)))) {
    stop("re-writing default's thresholds does not reproduce ",
         path_thr_default, " byte for byte", call. = FALSE)
  }
  unlink(tmp)
})

bundle_dir <- function(v) file.path(dir_out, "bundles", v)
write_bundle <- function(r) {
  thr <- thr_default
  if (!r$column %in% names(thr)) {
    stop("variant ", r$variant, ": no column ", r$column, call. = FALSE)
  }
  i <- which(thr$species_code == r$species_code)
  if (length(i) != 1L) {
    stop("variant ", r$variant, ": species ", r$species_code,
         " not in default's thresholds", call. = FALSE)
  }
  if (identical(thr[[r$column]][i], r$value)) {
    stop("variant ", r$variant, " equals default: ", r$column, " is already ",
         r$value, call. = FALSE)
  }
  thr[[r$column]][i] <- r$value
  n_diff <- sum(mapply(function(a, b) {
    sum(!((a == b) %in% TRUE) & !(is.na(a) & is.na(b)))
  }, thr, thr_default))
  if (n_diff != 1L) {
    stop("variant ", r$variant, " differs from default in ", n_diff,
         " cells, not 1", call. = FALSE)
  }
  d <- bundle_dir(r$variant)
  fs::dir_create(d)
  path_thr <- file.path(d, "parameters_habitat_thresholds.csv")
  write_thresholds(thr, path_thr)
  yaml::write_yaml(list(
    name = r$variant,
    description = sprintf(paste(
      "link#284 step 5 scoring variant, generated by",
      "data-raw/habitat_variants_build.R from %s: `default` with %s %s",
      "%s -> %s."), basename(path_variants), r$species_code, r$column,
      thr_default[[r$column]][i], r$value),
    extends = "default",
    files = list(parameters_habitat_thresholds = list(
      path = "parameters_habitat_thresholds.csv")),
    pipeline = list(schema = schema_of(r$variant)),
    # Its own entry, or the inherited one would verify default's copy.
    provenance = list(parameters_habitat_thresholds.csv = list(
      source = sprintf("link (generated from configs/default; %s row %s)",
                       basename(path_variants), r$variant),
      checksum = paste0("sha256:", digest::digest(file = path_thr,
                                                  algo = "sha256"))))),
    file.path(d, "config.yaml"))
  cfg <- lnk_config(normalizePath(d))
  ver <- lnk_config_verify(cfg)
  ver <- ver[ver$file == "parameters_habitat_thresholds.csv", ]
  if (nrow(ver) != 1L || isTRUE(ver$byte_drift)) {
    stop("variant ", r$variant, ": its thresholds do not verify against ",
         "its own provenance", call. = FALSE)
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
cfgs[[base_variant]] <- cfg_default
path_built <- file.path(dir_out, "built.csv")
# One row per variant x WSG, replaced only for the pair just built, so a
# build over a WSG subset cannot vouch for the WSGs it did not touch.
record_built <- function(v, w) {
  row <- data.frame(
    variant = v, watershed_group_code = w, schema = schema_of(v),
    thresholds_sha256 = digest::digest(
      file = cfgs[[v]]$files$parameters_habitat_thresholds$path,
      algo = "sha256"),
    link_head = head_sha, dirty = length(dirty) > 0L,
    built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
  old <- if (file.exists(path_built)) {
    utils::read.csv(path_built, colClasses = "character")
  } else {
    NULL
  }
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

# -- base: default over the closure, downstream first ------------------------------------
run_base <- function() {
  closure <- lnk_wsg_resolve(cfg_default, loaded, wsgs = focal, expand = TRUE,
                             conn = conn)
  say("base: %s, %d WSGs (focal %s) into %s", cfg_default$name,
      length(closure), paste(focal, collapse = ","), cfg_default$pipeline$schema)
  writeLines(closure, file.path(dir_out, "closure.txt"))
  sch <- cfg_default$pipeline$schema
  for (w in closure) {
    active <- lnk_pipeline_species(cfg_default, loaded, w)
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
    guard <- lnk_wsg_downstream_check(conn, aoi = w, cfg = cfg_default,
                                      loaded = loaded, on_fail = "error")
    t0 <- Sys.time()
    lnk_pipeline_run(conn, aoi = w, cfg = cfg_default, loaded = loaded,
                     schema = working_of(w), mapping_code = FALSE,
                     cleanup_working = !w %in% focal, notes = guard$note)
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
  # whose timeouts and log_recompute row this repeats; its mapping_code step
  # does not apply, since the base run builds none).
  dbExecute(conn, "SET statement_timeout = '600000'")
  dbExecute(conn, "SET lock_timeout = '60000'")
  rc <- list()
  for (w in focal) {
    active <- lnk_pipeline_species(cfg_default, loaded, w)
    before <- digest_of(sch, "streams_access", w)
    rlog <- .lnk_log_recompute_start(conn, cfg = cfg_default, aoi = w,
                                     views_prebuilt = FALSE)
    tryCatch({
      lnk_access(conn, cfg_default, aoi = w,
                 table_streams = paste0(sch, ".streams"),
                 table_barriers = paste0(sch, ".barriers"),
                 table_to = paste0(sch, ".streams_access"),
                 merge = TRUE,
                 presence = lnk_presence(loaded$wsg_species_presence, w),
                 species = active)
      lnk_wsg_downstream_check(conn, aoi = w, cfg = cfg_default,
                               loaded = loaded, on_fail = "error")
    }, error = function(e) {
      .lnk_log_recompute_fail(conn, cfg_default, rlog$recompute_id,
                              message = conditionMessage(e))
      stop(e)
    })
    .lnk_log_recompute_finish(conn, cfg_default, rlog$recompute_id,
                              species = active)
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

run_variant <- function(v) {
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
  wsgs_v <- if (identical(v, base_variant)) focal else
    intersect(focal, roles$watershed_group_code[roles$species_code == sp_v])
  say("variant %s into %s (%s)", v, sch, paste(wsgs_v, collapse = ","))
  # Sized to the whole bundle (link#194), as lnk_pipeline_run does.
  lnk_persist_init(conn, cfg, species = cfg$species)
  for (w in wsgs_v) {
    if (!dbExistsTable(conn, Id(schema = working_of(w), table = "streams"))) {
      stop(working_of(w), " is gone: run --step=base first", call. = FALSE)
    }
    t0 <- Sys.time()
    sp <- if (identical(v, base_variant)) NULL else sp_v
    lnk_pipeline_classify(conn, aoi = w, cfg = cfg, loaded = loaded,
                          schema = working_of(w), species = sp)
    lnk_pipeline_connect(conn, aoi = w, cfg = cfg, loaded = loaded,
                         schema = working_of(w), species = sp)
    dg <- working_habitat_digest(w)
    if (identical(v, base_variant)) {
      want <- base_digest$digest[base_digest$watershed_group_code == w]
      if (length(want) != 1L) {
        stop("no base habitat digest for ", w, " in ", path_base_digest,
             ": run --step=base with this --out first", call. = FALSE)
      }
      if (!identical(dg, want)) {
        stop("re-classifying ", w, " with default's thresholds gave habitat ",
             "digest ", dg, ", not the base run's ", want,
             ": the re-classify path is not a pure threshold change",
             call. = FALSE)
      }
    }
    if (!identical(v, base_variant)) {
      lnk_pipeline_persist(conn, aoi = w, cfg = cfg, species = sp,
                           schema = working_of(w))
      # The persisted access is the working copy, for this species only, and
      # from before the base's recompute. Access reads no habitat threshold
      # (classify and connect never touch it), so the base's recomputed rows,
      # every species, replace it.
      copy_access(sch_base, sch, w)
    }
    for (tb in names(digest_sql)) {
      if (!identical(digest_of(sch, tb, w), digest_of(sch_base, tb, w))) {
        stop(sch, ".", tb, " differs from ", sch_base, " in ", w,
             call. = FALSE)
      }
    }
    record_built(v, w)
    say("variant %s %s done in %.1f min (habitat %s)", v, w,
        as.numeric(difftime(Sys.time(), t0, units = "mins")), substr(dg, 1, 8))
  }
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
if (step %in% c("all", "base")) run_base()
if (step %in% c("all", "variants")) {
  # The base variant first: its digest check is what licenses the others.
  for (v in run_variants) {
    run_variant(v)
  }
}
write_stamp()
say("build %s done in %.1f min", step,
    as.numeric(difftime(Sys.time(), t_all, units = "mins")))
dbDisconnect(conn)
