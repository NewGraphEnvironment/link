#!/usr/bin/env Rscript
# readers.R — the groups outside a partial run that read its barriers (link#274).
#
# For each partial run below and the schema it wrote (and, as the every-group
# case, fresh_default), lists the groups outside the run that read a run group
# under recompute_deps.R's line rule, which of them the schema holds, and for
# each held reader the facts the compatibility rule tests against today's HEAD:
# its newest log row's config_hash against the config's hash at HEAD, its
# fresh_sha against the installed fresh, link_dirty, whether git can resolve its
# link_sha, and the files changed since that sha on the recompute's path.
#
# Reads the database (local fwapg) and git; writes nothing but its outputs.
#
# Usage: Rscript data-raw/logs/partial_readers_274/readers.R
#   (from the repo root; writes readers.tsv and summary.tsv beside itself)

suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
here <- "data-raw/logs/partial_readers_274"
deps <- utils::read.delim(file.path(here, "deps_line.tsv"),
  colClasses = "character", quote = "", na.strings = character(), comment.char = ""
)
stopifnot(identical(names(deps), c("wsg", "rule", "dep")), all(deps$rule == "line"))

logs <- "data-raw/logs/study_area_run"
csv_wsgs <- function(f) {
  x <- utils::read.csv(file.path(logs, f), colClasses = "character")
  sort(unique(x$wsg))
}
tsv_wsgs <- function(f) {
  x <- utils::read.delim(file.path(logs, f), colClasses = "character", quote = "")
  sort(unique(x$wsg[x$skip != "yes"]))
}
runs <- list(
  field_20260831 = list(wsgs = csv_wsgs("20260831_232553_compare.csv"), schema = "fresh"),
  nthompson_20260903 = list(wsgs = csv_wsgs("20260903_173205_compare.csv"), schema = "fresh"),
  parity_20261023 = list(wsgs = tsv_wsgs("20261023_215312_run_wsgs.tsv"), schema = "fresh_parity361"),
  dunc_20261012 = list(wsgs = "DUNC", schema = "fresh_default")
)
stopifnot(
  length(runs$field_20260831$wsgs) == 34L, length(runs$nthompson_20260903$wsgs) == 6L,
  length(runs$parity_20261023$wsgs) == 17L
)

# The recompute's path, as the classifier will test it.
paths <- c("R/", "inst/extdata/", "DESCRIPTION", "data-raw/wsg_recompute_one.R",
           "data-raw/barriers_views_build.R")
head_sha <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE)
fresh_sha <- link:::.lnk_pkg_git_sha("fresh")
stopifnot(nzchar(head_sha), !is.na(fresh_sha))
changed <- function(sha) {
  if (is.na(sha) || !nzchar(sha)) {
    return(NA_integer_)
  }
  ok <- system2("git", c("cat-file", "-e", paste0(sha, "^{commit}")),
    stdout = FALSE, stderr = FALSE
  )
  if (ok != 0L) {
    return(NA_integer_)
  }
  out <- system2("git", c("diff", "--name-only", sha, "HEAD", "--", paths), stdout = TRUE)
  length(out)
}
hash_at_head <- function(name) {
  tryCatch(link:::.lnk_config_hash(lnk_config(name)), error = function(e) NA_character_)
}

conn <- lnk_db_conn(
  dbname = "fwapg", host = "localhost", port = 5432L,
  user = "postgres", password = "postgres"
)
schema_facts <- function(schema) {
  held <- DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT watershed_group_code AS wsg FROM %s.streams", schema
  ))$wsg
  last <- DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT ON (watershed_group_code) watershed_group_code AS wsg,
            config_name, config_hash, link_sha, link_dirty, fresh_sha
       FROM %s.log ORDER BY watershed_group_code, date_start DESC", schema
  ))
  list(held = held, last = last)
}
schemas <- unique(c(vapply(runs, `[[`, "", "schema"), "fresh_default"))
facts <- stats::setNames(lapply(schemas, schema_facts), schemas)
DBI::dbDisconnect(conn)

hashes <- list()
rows <- list()
for (rn in names(runs)) {
  run <- runs[[rn]]$wsgs
  outside <- sort(unique(deps$wsg[deps$dep %in% run & !deps$wsg %in% run]))
  for (sch in unique(c(runs[[rn]]$schema, "fresh_default"))) {
    f <- facts[[sch]]
    for (g in outside) {
      held <- g %in% f$held
      l <- f$last[f$last$wsg == g, , drop = FALSE]
      has_log <- nrow(l) == 1L
      cn <- if (has_log) l$config_name else NA_character_
      if (!is.na(cn) && is.null(hashes[[cn]])) hashes[[cn]] <- hash_at_head(cn)
      rows[[length(rows) + 1L]] <- data.frame(
        run = rn, schema = sch, wsg = g, held = held, has_log = has_log,
        reads = paste(sort(deps$dep[deps$wsg == g & deps$dep %in% run]), collapse = ","),
        config_name = cn,
        config_same = if (has_log) identical(l$config_hash, hashes[[cn]]) else NA,
        fresh_same = if (has_log) identical(l$fresh_sha, fresh_sha) else NA,
        link_dirty = if (has_log) l$link_dirty else NA,
        link_sha = if (has_log) l$link_sha else NA_character_,
        path_files_changed = if (has_log) changed(l$link_sha) else NA_integer_
      )
    }
  }
}
tab <- do.call(rbind, rows)
tab$compatible <- with(
  tab,
  held & has_log & config_same & fresh_same & !is.na(link_dirty) & !link_dirty &
    !is.na(path_files_changed) & path_files_changed == 0L
)
tab$compatible[is.na(tab$compatible)] <- FALSE
utils::write.table(tab, file.path(here, "readers.tsv"),
  sep = "\t", quote = FALSE, row.names = FALSE, na = "NA"
)

summ <- do.call(rbind, lapply(split(tab, list(tab$run, tab$schema), drop = TRUE), function(x) {
  h <- x[x$held, , drop = FALSE]
  data.frame(
    run = x$run[1], schema = x$schema[1], run_groups = length(runs[[x$run[1]]]$wsgs),
    outside = nrow(x), held = nrow(h),
    no_log = sum(!h$has_log), config_differs = sum(h$has_log & !h$config_same),
    fresh_differs = sum(h$has_log & !h$fresh_same),
    dirty_or_unknown = sum(h$has_log & (is.na(h$link_dirty) | h$link_dirty)),
    sha_unresolvable = sum(h$has_log & is.na(h$path_files_changed)),
    path_changed = sum(h$has_log & !is.na(h$path_files_changed) & h$path_files_changed > 0),
    compatible = sum(h$compatible)
  )
}))
summ <- summ[order(summ$run, summ$schema), ]
utils::write.table(summ, file.path(here, "summary.tsv"),
  sep = "\t", quote = FALSE, row.names = FALSE
)
cat(sprintf("HEAD %s, fresh %s\n", head_sha, fresh_sha))
print(summ, row.names = FALSE)
