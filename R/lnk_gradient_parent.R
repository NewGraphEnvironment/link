# The gradient a build classifies on (#463): each segment's own (`segment`, the
# value when absent), or the gradient of the minimal-network segment it lies in
# (`parent`), read from `<schema_full>.streams_parent`, which
# lnk_streams_parent() builds after both networks are modelled.
#
#   pipeline:
#     gradient:
#       source: parent
#       minimal_config: default_minimal  # the cut-min bundle the parents come from
#       schema_full: fresh_default       # the full build streams_parent sits in
#       schema_minimal: ...              # optional; must equal minimal_config's schema
#
# A `parent` build re-cuts the network the parent table was joined on, maps each
# of its segments to that build's segment by position, and sets its working
# `streams.gradient` to the parent's before classify, so classify, the habitat
# overlay, frs_order_child() and connect all read it, and the persisted
# `gradient` is the value classify read. Breaks and access never read segment
# gradient. This file is on the modelling path; R/lnk_streams_parent.R (the join
# itself) is not.

.lnk_gradient_keys <- c("source", "minimal_config", "schema_full", "schema_minimal")

#' Validate a `pipeline: gradient:` setting when the manifest loads
#'
#' Checks its shape only: a map whose keys are known, `source` one of `segment`
#' or `parent`, and for `parent` a `minimal_config` and `schema_full` (and an
#' optional `schema_minimal`) that are plain names. Reading the minimal config
#' waits for [.lnk_gradient_parent()].
#' @noRd
.lnk_gradient_check <- function(g, what = "gradient") {
  if (!is.list(g) || is.null(names(g)) || any(!nzchar(names(g)))) {
    stop(what, ": pipeline: gradient must be a map with a `source` key",
         call. = FALSE)
  }
  bad <- setdiff(names(g), .lnk_gradient_keys)
  if (length(bad) > 0L) {
    stop(what, ": pipeline: gradient has unknown key(s) ",
         paste(bad, collapse = ", "), " (known: ",
         paste(.lnk_gradient_keys, collapse = ", "), ")", call. = FALSE)
  }
  src <- g$source
  if (!.lnk_gradient_name_ok(src, "^(segment|parent)$")) {
    stop(what, ": pipeline: gradient: source must be segment or parent",
         call. = FALSE)
  }
  extra <- setdiff(names(g), "source")
  if (identical(src, "segment")) {
    if (length(extra) > 0L) {
      stop(what, ": pipeline: gradient: source segment takes no other key (",
           paste(extra, collapse = ", "), ")", call. = FALSE)
    }
    return(g)
  }
  for (k in c("minimal_config", "schema_full")) {
    if (is.null(g[[k]])) {
      stop(what, ": pipeline: gradient: source parent needs ", k, call. = FALSE)
    }
  }
  if (!.lnk_gradient_name_ok(g$minimal_config, "^[A-Za-z0-9_.-]+$")) {
    stop(what, ": pipeline: gradient: minimal_config must be one bundle name",
         call. = FALSE)
  }
  for (k in intersect(c("schema_full", "schema_minimal"), names(g))) {
    # Lower case and at most 63 bytes, as lnk_streams_parent() names them:
    # the SQL names them unquoted, and Postgres folds case and truncates.
    if (!.lnk_gradient_name_ok(g[[k]], "^[a-z_][a-z0-9_]{0,62}$")) {
      stop(what, ": pipeline: gradient: ", k,
           " must be one plain lower-case schema name", call. = FALSE)
    }
  }
  g
}

.lnk_gradient_name_ok <- function(v, pattern) {
  is.character(v) && length(v) == 1L && !is.na(v) && grepl(pattern, v)
}

#' The gradient source a config builds on: `segment` or `parent`
#' @noRd
.lnk_gradient_source <- function(cfg) {
  g <- cfg$pipeline[["gradient"]]
  if (is.null(g)) return("segment")
  .lnk_gradient_check(g, paste0("config '", cfg$name %||% "", "'"))$source
}

#' Resolve a `parent` gradient setting against its minimal config
#'
#' Loads `minimal_config` and refuses one whose own gradient source is
#' `parent` (a parent of a parent), and a `schema_minimal` that is not the
#' minimal config's persist schema.
#'
#' @return A list: `minimal_cfg` (the loaded config), `schema_full`,
#'   `schema_minimal`.
#' @noRd
.lnk_gradient_parent <- function(cfg) {
  g <- .lnk_gradient_check(cfg$pipeline[["gradient"]],
                           paste0("config '", cfg$name %||% "", "'"))
  if (!identical(g$source, "parent")) {
    stop("config '", cfg$name, "' does not read the parent gradient",
         call. = FALSE)
  }
  m <- lnk_config(g$minimal_config)
  if (!identical(.lnk_gradient_source(m), "segment")) {
    stop("config '", cfg$name, "': minimal_config '", g$minimal_config,
         "' itself reads a parent gradient; its segments must carry their own",
         call. = FALSE)
  }
  schema_minimal <- m$pipeline$schema
  if (!is.null(g$schema_minimal) && !identical(g$schema_minimal, schema_minimal)) {
    stop("config '", cfg$name, "': pipeline: gradient: schema_minimal ",
         g$schema_minimal, " is not minimal_config '", g$minimal_config,
         "''s schema (", schema_minimal, ")", call. = FALSE)
  }
  if (!.lnk_gradient_name_ok(schema_minimal, "^[a-z_][a-z0-9_]{0,62}$")) {
    stop("config '", cfg$name, "': minimal_config '", g$minimal_config,
         "' has no plain lower-case pipeline: schema", call. = FALSE)
  }
  list(minimal_cfg = m, schema_full = g$schema_full,
       schema_minimal = schema_minimal)
}

#' The grad axis's spec for a config
#'
#' `gradient=segment`, or for `parent`
#' `gradient=parent;parent_cut=<the minimal config's cut token>`. A minimal
#' config whose access or flow spec differs from this config's is refused:
#' the parent's gradient is comparable only on a network cut by the same
#' access rules from the same flow.
#' @param specs This config's `cut`, `acc` and `flow` specs.
#' @noRd
.lnk_vocabulary_spec_grad <- function(cfg, specs) {
  if (identical(.lnk_gradient_source(cfg), "segment")) {
    return("gradient=segment")
  }
  p <- .lnk_gradient_parent(cfg)
  m <- p$minimal_cfg
  ms <- .lnk_vocabulary_specs(m, lnk_load_overrides(m))
  for (axis in c("acc", "flow")) {
    if (!identical(ms[[axis]], specs[[axis]])) {
      stop("config '", cfg$name, "': minimal_config '", m$name, "' has another ",
           axis, " spec than this config; the parent gradient is read only ",
           "from a minimal network cut by the same rules", call. = FALSE)
    }
  }
  cut <- .lnk_vocabulary_match(ms["cut"], lnk_vocabulary_read(), m$name)
  paste0("gradient=parent;parent_cut=", cut[["cut"]])
}

#' The parent cut token a resolved grad token names
#' @noRd
.lnk_gradient_parent_cut <- function(token_grad) {
  v <- lnk_vocabulary_read()
  spec <- v$spec[v$axis == "grad" & v$token == token_grad]
  cut <- sub("^.*parent_cut=([^;]+).*$", "\\1", spec)
  if (length(cut) != 1L || identical(cut, spec)) {
    stop("grad token ", token_grad, " names no parent cut", call. = FALSE)
  }
  cut
}

#' The newest build of a group on each side of a parent join
#'
#' The newest `log` row by `date_start` must be closed: an open newest row is
#' a build that is running or failed part-way, so `streams` may not be the
#' build a closed row describes.
#'
#' @return A two-row data frame (`side` `full`, `minimal`) of the log columns
#'   a parent join records and a pair guard reads.
#' @noRd
.lnk_streams_parent_builds <- function(conn, schema, schema_minimal, wsg) {
  one <- function(side, s) {
    sql <- sprintf(
      "SELECT run_id, run_uid, date_start, date_end, config_hash, link_sha,
              link_dirty, fresh_sha, fresh_dirty, token_cut, token_acc,
              token_grad, token_flow, array_to_string(species, ',') AS species
         FROM %s.log WHERE watershed_group_code = %s
        ORDER BY date_start DESC LIMIT 1",
      s, .lnk_quote_literal(wsg)
    )
    d <- DBI::dbGetQuery(conn, sql)
    if (nrow(d) != 1L) {
      stop("no build of ", wsg, " in ", s, ".log", call. = FALSE)
    }
    if (is.na(d$date_end)) {
      stop("the newest build of ", wsg, " in ", s, ".log is open (run_id ",
           d$run_id, "): it is running or failed, so ", s,
           ".streams may not be a finished build", call. = FALSE)
    }
    cbind(data.frame(side = side, schema = s, stringsAsFactors = FALSE), d)
  }
  rbind(one("full", schema), one("minimal", schema_minimal))
}

#' What `<schema>.streams_parent` holds for each group, against `streams`
#'
#' One row per group `<schema>.streams` holds (or each of `wsgs`): its segment
#' count, segments with no parent row (`n_no_row`), parent rows, rows with no
#' segment (`n_no_segment`), rows whose `overlap_m + straddle_m` is more than
#' 1 mm off the segment's length (`n_length_off`), and the distinct
#' `run_id_full`, `run_id_minimal` and `schema_minimal` its rows name
#' (comma-separated). The caller judges them against the newest builds:
#' `data-raw/streams_parent_build.R --verify` and a `parent` build.
#'
#' @return A data frame; counts numeric, 0 where a group has none. `NULL`
#'   when `<schema>.streams_parent` does not exist.
#' @noRd
.lnk_streams_parent_state <- function(conn, schema, wsgs = NULL) {
  sql_has <- sprintf("SELECT to_regclass(%s) IS NOT NULL AS ok",
                     .lnk_quote_literal(paste0(schema, ".streams_parent")))
  has <- DBI::dbGetQuery(conn, sql_has)$ok
  if (!isTRUE(has)) return(NULL)
  where <- ""
  if (!is.null(wsgs)) {
    where <- sprintf("WHERE watershed_group_code IN (%s)",
                     paste(vapply(wsgs, .lnk_quote_literal, ""), collapse = ", "))
  }
  sql_rows <- sprintf(
    "SELECT p.watershed_group_code AS wsg, count(*) AS n_rows,
            string_agg(DISTINCT p.run_id_full, ',') AS run_id_full,
            string_agg(DISTINCT p.run_id_minimal, ',') AS run_id_minimal,
            string_agg(DISTINCT p.schema_minimal, ',') AS schema_minimal,
            count(*) FILTER (WHERE s.id_segment IS NULL) AS n_no_segment,
            count(*) FILTER (WHERE abs(p.overlap_m + p.straddle_m - s.length_metre) > 1e-3)
              AS n_length_off
       FROM (SELECT * FROM %1$s.streams_parent %2$s) p
       LEFT JOIN %1$s.streams s USING (id_segment, watershed_group_code)
      GROUP BY 1",
    schema, where
  )
  sql_segs <- sprintf(
    "SELECT s.watershed_group_code AS wsg, count(*) AS n_segments,
            count(*) FILTER (WHERE p.id_segment IS NULL) AS n_no_row
       FROM (SELECT * FROM %1$s.streams %2$s) s
       LEFT JOIN %1$s.streams_parent p USING (id_segment, watershed_group_code)
      GROUP BY 1",
    schema, where
  )
  rows <- DBI::dbGetQuery(conn, sql_rows)
  segs <- DBI::dbGetQuery(conn, sql_segs)
  out <- merge(segs, rows, by = "wsg", all = TRUE)
  if (!is.null(wsgs)) {
    out <- merge(data.frame(wsg = wsgs, stringsAsFactors = FALSE), out,
                 by = "wsg", all.x = TRUE)
  }
  num <- c("n_segments", "n_no_row", "n_rows", "n_no_segment", "n_length_off")
  out[num] <- lapply(out[num], function(x) {
    x <- as.numeric(x)
    x[is.na(x)] <- 0
    x
  })
  out
}

#' Judge whether a `parent` build of one group may read its parent rows
#'
#' Run before the build's log opens. Refuses unless:
#' - the persist schema is neither `schema_full` nor `schema_minimal`, and the
#'   two differ;
#' - the group's newest build in each of `schema_full` and `schema_minimal` is
#'   closed, built from a clean tree (`link_dirty`, `fresh_dirty` FALSE) on one
#'   known `fresh_sha`, with the same species;
#' - the full build is `grad-seg` with this build's cut, acc and flow tokens,
#'   and the minimal build is `grad-seg` cut at the parent cut this build's
#'   grad token names, with the same acc and flow;
#' - `<schema_full>.streams_parent` holds rows for every segment of the group,
#'   joined from exactly those two builds and `schema_minimal`, each the
#'   segment's length.
#'
#' Whether the two builds ran the same modelling code (their `link_sha`s) is
#' the builder's judgement (`data-raw/streams_parent_build.R`), which this
#' trusts through the rows' run ids.
#'
#' @param tokens The build's resolved tokens ([lnk_vocabulary_resolve()]).
#' @return A list: `schema_full`, `schema_minimal`, `run_id_full`,
#'   `run_id_minimal`, `n_rows`, and `note` (one line for the log row).
#' @noRd
.lnk_gradient_parent_judge <- function(conn, cfg, aoi, tokens) {
  p <- .lnk_gradient_parent(cfg)
  sf <- p$schema_full
  sm <- p$schema_minimal
  persist <- .lnk_table_names(cfg)$schema
  if (identical(sf, sm)) {
    stop("config '", cfg$name, "': schema_full and the minimal schema are both ",
         sf, call. = FALSE)
  }
  if (persist %in% c(sf, sm)) {
    stop("config '", cfg$name, "': the persist schema ", persist, " is the ",
         if (identical(persist, sf)) "full" else "minimal",
         " schema the parent gradient is read from; a parent build writes ",
         "its own schema", call. = FALSE)
  }
  why <- function(...) {
    stop(aoi, ": cannot read the parent gradient from ", sf,
         ".streams_parent: ", ..., call. = FALSE)
  }
  b <- .lnk_streams_parent_builds(conn, sf, sm, aoi)
  bf <- b[b$side == "full", ]
  bm <- b[b$side == "minimal", ]
  dirty <- !(b$link_dirty %in% FALSE) | !(b$fresh_dirty %in% FALSE)
  if (any(dirty)) why("built from a dirty or unknown tree (", paste(b$schema[dirty], collapse = ", "), ")")
  if (anyNA(b$fresh_sha)) why("no fresh sha recorded")
  if (!identical(bf$fresh_sha, bm$fresh_sha)) {
    why("fresh_sha differs: ", sf, " ", bf$fresh_sha, ", ", sm, " ", bm$fresh_sha)
  }
  if (!identical(bf$species, bm$species)) {
    why("species differ: ", sf, " ", bf$species, ", ", sm, " ", bm$species)
  }
  parent_cut <- .lnk_gradient_parent_cut(tokens[["grad"]])
  want <- list(
    list(bf, "token_cut", tokens[["cut"]]), list(bf, "token_acc", tokens[["acc"]]),
    list(bf, "token_flow", tokens[["flow"]]), list(bf, "token_grad", "grad-seg"),
    list(bm, "token_cut", parent_cut), list(bm, "token_acc", tokens[["acc"]]),
    list(bm, "token_flow", tokens[["flow"]]), list(bm, "token_grad", "grad-seg")
  )
  for (w in want) {
    have <- w[[1]][[w[[2]]]]
    if (!identical(have, w[[3]])) {
      why(w[[1]]$schema, "'s newest ", aoi, " build has ", w[[2]], " ",
          if (is.na(have)) "NULL" else have, ", not ", w[[3]])
    }
  }
  st <- .lnk_streams_parent_state(conn, sf, aoi)
  if (is.null(st)) why("the table does not exist")
  bad <- character()
  if (st$n_rows == 0) bad <- c(bad, "no rows")
  if (st$n_rows > 0 && !identical(st$run_id_full, bf$run_id)) bad <- c(bad, "full re-modelled since the join")
  if (st$n_rows > 0 && !identical(st$run_id_minimal, bm$run_id)) bad <- c(bad, "minimal re-modelled since the join")
  if (st$n_rows > 0 && !identical(st$schema_minimal, sm)) {
    bad <- c(bad, paste("joined on another minimal schema:", st$schema_minimal))
  }
  if (st$n_no_row > 0) bad <- c(bad, sprintf("%d segments without a row", as.integer(st$n_no_row)))
  if (st$n_no_segment > 0) bad <- c(bad, sprintf("%d rows without a segment", as.integer(st$n_no_segment)))
  if (st$n_length_off > 0) {
    bad <- c(bad, sprintf("%d rows off the segment's length", as.integer(st$n_length_off)))
  }
  if (length(bad) > 0L) {
    why(paste(bad, collapse = "; "),
        " (rebuild it: data-raw/streams_parent_build.R)")
  }
  list(schema_full = sf, schema_minimal = sm, run_id_full = bf$run_id,
       run_id_minimal = bm$run_id, n_rows = st$n_rows,
       note = sprintf("gradient from %s.streams_parent (run_id_full %s, run_id_minimal %s in %s)",
                      sf, bf$run_id, bm$run_id, sm))
}

#' Set a working network's gradient to its parents'
#'
#' Maps each segment of `<schema>.streams` (the group's working network, after
#' break) to the segment of `<schema_full>.streams` at the same position: the
#' same `blue_line_key`, and `downstream_route_measure` and
#' `upstream_route_measure` each within 1 mm. Refuses unless the mapping is one
#' to one over the whole group (equal counts, each segment on either side
#' matched exactly once) and every full segment has a parent row from the runs
#' the judgement named (a row left by a re-model since reads as none): that proves
#' this build cut the network the parent table was joined on. Then drops
#' working `gradient`'s generation expression (fresh makes it a generated
#' column) and sets it to the parent's `gradient_minimal`, in one transaction.
#'
#' @param judged The list [.lnk_gradient_parent_judge()] returned.
#' @return The number of segments set, invisibly.
#' @noRd
.lnk_gradient_parent_apply <- function(conn, aoi, schema, judged) {
  sf <- judged$schema_full
  lit <- .lnk_quote_literal
  tmp <- c("lnk_gp_f", "lnk_gp_w", "lnk_gp_m")
  drop_tmp <- function() {
    for (t in tmp) .lnk_db_execute(conn, sprintf("DROP TABLE IF EXISTS pg_temp.%s", t))
  }
  drop_tmp()
  on.exit(try(drop_tmp(), silent = TRUE), add = TRUE)
  sql_f <- sprintf(
    "CREATE TEMP TABLE lnk_gp_f AS
     SELECT f.id_segment, f.blue_line_key AS blk, f.downstream_route_measure AS dm,
            f.upstream_route_measure AS um, p.gradient_minimal,
            p.id_segment IS NOT NULL AS has_parent
       FROM %1$s.streams f
       LEFT JOIN %1$s.streams_parent p
         ON p.id_segment = f.id_segment AND p.watershed_group_code = f.watershed_group_code
        AND p.run_id_full = %3$s AND p.run_id_minimal = %4$s AND p.schema_minimal = %5$s
      WHERE f.watershed_group_code = %2$s",
    sf, lit(aoi), lit(judged$run_id_full), lit(judged$run_id_minimal),
    lit(judged$schema_minimal)
  )
  sql_w <- sprintf(
    "CREATE TEMP TABLE lnk_gp_w AS
     SELECT id_segment, blue_line_key AS blk, downstream_route_measure AS dm,
            upstream_route_measure AS um
       FROM %s.streams",
    schema
  )
  .lnk_db_execute(conn, sql_f)
  .lnk_db_execute(conn, sql_w)
  for (t in c("lnk_gp_f", "lnk_gp_w")) {
    .lnk_db_execute(conn, sprintf("CREATE INDEX ON pg_temp.%s (blk, dm)", t))
    .lnk_db_execute(conn, sprintf("ANALYZE pg_temp.%s", t))
  }
  .lnk_db_execute(
    conn,
    "CREATE TEMP TABLE lnk_gp_m AS
     SELECT w.id_segment AS wid, f.id_segment AS fid, f.gradient_minimal
       FROM pg_temp.lnk_gp_w w
       JOIN pg_temp.lnk_gp_f f
         ON f.blk = w.blk AND f.dm BETWEEN w.dm - 0.001 AND w.dm + 0.001
        AND abs(f.um - w.um) <= 0.001"
  )
  n <- DBI::dbGetQuery(
    conn,
    "SELECT (SELECT count(*) FROM pg_temp.lnk_gp_w) AS n_w,
            (SELECT count(*) FROM pg_temp.lnk_gp_f) AS n_f,
            (SELECT count(*) FROM pg_temp.lnk_gp_f WHERE NOT has_parent) AS n_no_parent,
            (SELECT count(*) FROM pg_temp.lnk_gp_m) AS n_pairs,
            (SELECT count(DISTINCT wid) FROM pg_temp.lnk_gp_m) AS n_wid,
            (SELECT count(DISTINCT fid) FROM pg_temp.lnk_gp_m) AS n_fid"
  )
  n[] <- lapply(n, as.numeric)
  bad <- character()
  if (n$n_w != n$n_f) {
    bad <- c(bad, sprintf("%d working segments against %d in %s",
                          as.integer(n$n_w), as.integer(n$n_f), sf))
  }
  if (n$n_w - n$n_wid > 0) bad <- c(bad, sprintf("%d working segments match none", as.integer(n$n_w - n$n_wid)))
  if (n$n_f - n$n_fid > 0) bad <- c(bad, sprintf("%d %s segments match none", as.integer(n$n_f - n$n_fid), sf))
  if (n$n_pairs > n$n_wid || n$n_pairs > n$n_fid) bad <- c(bad, "a segment matches more than one")
  if (n$n_no_parent > 0) bad <- c(bad, sprintf("%d %s segments have no parent row", as.integer(n$n_no_parent), sf))
  if (length(bad) > 0L) {
    stop(aoi, ": this build's segments are not ", sf, "'s, so its parents ",
         "cannot be read (", paste(bad, collapse = "; "), ")", call. = FALSE)
  }
  sql_drop <- sprintf("ALTER TABLE %s.streams ALTER COLUMN gradient DROP EXPRESSION", schema)
  sql_set <- sprintf(
    "UPDATE %s.streams w SET gradient = m.gradient_minimal
       FROM pg_temp.lnk_gp_m m WHERE w.id_segment = m.wid",
    schema
  )
  DBI::dbWithTransaction(conn, {
    .lnk_db_execute(conn, sql_drop)
    set <- .lnk_db_execute(conn, sql_set)
    if (set != n$n_w) {
      stop(aoi, ": set the parent gradient on ", set, " of ", n$n_w,
           " segments", call. = FALSE)
    }
  })
  message(sprintf("[lnk_pipeline_run] %s: gradient from %s.streams_parent on %d segments",
                  aoi, sf, as.integer(n$n_w)))
  invisible(n$n_w)
}
