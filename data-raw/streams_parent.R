# data-raw/streams_parent.R — the pair guard for lnk_streams_parent() (link#444).
# Sourced by streams_parent_build.R and tests/testthat/test-streams_parent_build.R,
# after data-raw/pretest.R (whose functions it calls). Sourcing defines functions
# only.
#
# A full segment can read its minimal parent's gradient only if the two
# networks were cut by one modelling code from one set of inputs: then every
# minimal cut is a full cut (#415's proof), and the join is well defined. So a
# pair is refused unless, over every group it joins:
#   - both builds are closed, neither link nor fresh was dirty, fresh's sha
#     is known;
#   - each schema holds one link_sha, fresh_sha, config_name, config_hash,
#     token_acc, token_flow and token_grad;
#   - the two sides share fresh_sha, token_acc, token_flow and token_grad, and
#     each group's species;
#   - the minimal side's cut token is cut-min and the full side's a cut-full-*
#     token (so a schema is never paired with itself);
#   - the code between the two link_shas is the same on the modelling path,
#     judged as the pre-run gate judges a record (pretest_record_check()):
#     the same fresh pin in DESCRIPTION, and every file changed between the
#     two shas under PRETEST_LINK_PATHS maps to `none` in pretest_inputs.csv
#     and is not reached from wsg_run_one.R's entry points. An unmapped file
#     refuses. Raw sha equality is not required: a version bump keeps a pair.
#
# The pretest_* calls resolve in the environment both files are sourced into,
# which the linter cannot see (hence the object_usage_linter exclusions).
#
# `reached` is computed by the caller at HEAD (the gate's own limit): a `none`
# file is judged not reached by the code checked out, not by the code at either
# sha.

# The newest log row of every group in one persist schema, closed or not.
streams_parent_side_sql <- function(schema) {
  sql <- "SELECT DISTINCT ON (watershed_group_code)
            watershed_group_code AS wsg, run_id, run_uid, date_start, date_end,
            config_name, config_hash, link_sha, link_dirty, fresh_sha, fresh_dirty,
            token_cut, token_acc, token_grad, token_flow,
            array_to_string(species, ',') AS species
       FROM %s.log
      ORDER BY watershed_group_code, date_start DESC"
  sprintf(sql, schema)
}

# Both sides, keyed by `side` (full, minimal), for the groups in `wsgs`.
streams_parent_pair_read <- function(conn, schema, schema_minimal) {
  one <- function(side, s) {
    d <- DBI::dbGetQuery(conn, streams_parent_side_sql(s))
    cbind(data.frame(side = rep(side, nrow(d)), schema = rep(s, nrow(d)),
                     stringsAsFactors = FALSE), d)
  }
  rbind(one("full", schema), one("minimal", schema_minimal))
}

# "" when the rows of a pair can be joined, else the first reason they cannot.
# `pair` holds one row per side per group (streams_parent_pair_read()).
streams_parent_rows_why <- function(pair) {
  if (!nrow(pair)) return("no builds to pair")
  f <- pair[pair$side == "full", , drop = FALSE]
  m <- pair[pair$side == "minimal", , drop = FALSE]
  only <- c(setdiff(f$wsg, m$wsg), setdiff(m$wsg, f$wsg))
  if (length(only)) {
    return(paste0("groups built on one side only: ", paste(sort(only), collapse = ", ")))
  }
  if (anyDuplicated(f$wsg) || anyDuplicated(m$wsg)) return("a group appears twice on one side")
  grp <- function(d, v) paste(sort(unique(d$wsg[v])), collapse = ", ")
  open <- is.na(pair$date_end)
  if (any(open)) return(paste0("open builds (running or failed): ", grp(pair, open)))
  dirty <- !(pair$link_dirty %in% FALSE) | !(pair$fresh_dirty %in% FALSE)
  if (any(dirty)) return(paste0("builds from a dirty or unknown tree: ", grp(pair, dirty)))
  if (anyNA(pair$fresh_sha)) return(paste0("no fresh sha: ", grp(pair, is.na(pair$fresh_sha))))
  per_side <- c("link_sha", "fresh_sha", "config_name", "config_hash",
                "token_acc", "token_flow", "token_grad")
  for (side in list(f, m)) {
    for (col in per_side) {
      v <- unique(side[[col]])
      if (length(v) != 1L || is.na(v)) {
        return(sprintf("%s holds %d values of %s (want one): %s", side$schema[1],
                       length(v), col, paste(v, collapse = ", ")))
      }
    }
  }
  for (col in c("fresh_sha", "token_acc", "token_flow", "token_grad")) {
    if (!identical(f[[col]][1], m[[col]][1])) {
      return(sprintf("%s differs: %s %s, %s %s", col, f$schema[1], f[[col]][1],
                     m$schema[1], m[[col]][1]))
    }
  }
  if (!all(m$token_cut %in% "cut-min")) {
    return(sprintf("%s is not cut at cut-min: %s", m$schema[1],
                   paste(sort(unique(m$token_cut)), collapse = ", ")))
  }
  if (!all(grepl("^cut-full-", f$token_cut))) {
    return(sprintf("%s is not cut at a cut-full-* token: %s", f$schema[1],
                   paste(sort(unique(f$token_cut)), collapse = ", ")))
  }
  sp <- merge(f[, c("wsg", "species")], m[, c("wsg", "species")], by = "wsg",
              suffixes = c("_full", "_minimal"))
  diff <- !(sp$species_full == sp$species_minimal) |
    is.na(sp$species_full) != is.na(sp$species_minimal)
  diff[is.na(diff)] <- FALSE
  if (any(diff)) {
    return(paste0("species differ: ", paste(sort(sp$wsg[diff]), collapse = ", ")))
  }
  ""
}

# "" when the code at `sha_a` and `sha_b` is the same on the modelling path,
# else why not. `chain` is the configs either build read (and what they
# extend); `reached` the basenames wsg_run_one.R's entry points reach.
streams_parent_code_why <- function(repo, sha_a, sha_b, map, chain, reached) {
  if (is.null(reached) || !length(reached)) return("no reach of the modelling path to judge none against")
  desc_pin <- function(ref) {
    desc <- pretest_git(repo, c("show", paste0(ref, ":DESCRIPTION")))  # nolint: object_usage_linter.
    pretest_fresh_pin(desc)  # nolint: object_usage_linter.
  }
  pa <- desc_pin(sha_a)
  pb <- desc_pin(sha_b)
  if (!identical(pa, pb)) return(sprintf("DESCRIPTION pins fresh %s at one build and %s at the other", pa, pb))
  ch <- pretest_changed_link(repo, sha_a, sha_b, chain)  # nolint: object_usage_linter.
  m <- pretest_match(ch, map, chain)  # nolint: object_usage_linter.
  if (nrow(m$unmapped)) {
    return(paste0("changed between the builds and unmapped: ", paste(m$unmapped$path, collapse = ", ")))
  }
  reached_none <- pretest_none_reached(m$hits, reached)  # nolint: object_usage_linter.
  moved <- unique(c(m$hits$path[m$hits$input != "none"], reached_none))
  if (length(moved)) {
    return(paste0("changed between the builds, on the modelling path: ", paste(moved, collapse = ", ")))
  }
  ""
}

# The whole judgement: the rows, then the code between the two link_shas.
streams_parent_pair_why <- function(pair, repo, map, reached) {
  why <- streams_parent_rows_why(pair)
  if (nzchar(why)) return(why)
  f <- pair[pair$side == "full", , drop = FALSE]
  m <- pair[pair$side == "minimal", , drop = FALSE]
  configs <- file.path(repo, "inst", "extdata", "configs")
  chain <- unique(c(pretest_config_chain(configs, f$config_name[1]),  # nolint: object_usage_linter.
                    pretest_config_chain(configs, m$config_name[1])))  # nolint: object_usage_linter.
  streams_parent_code_why(repo, m$link_sha[1], f$link_sha[1], map, chain, reached)
}
