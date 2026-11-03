#!/usr/bin/env Rscript
# streams_parent_build.R — build <schema>.streams_parent, each full segment's
# minimal parent, for every group both networks hold (link#444).
#
#   Rscript data-raw/streams_parent_build.R --schema=fresh_default \
#     --schema-minimal=fresh_default_minimal [--wsgs=BULK,SETN | all] \
#     [--out=<dir>] [--verify]
#
# Runs on the host holding both persist schemas (the dispatcher), against its
# local fwapg, from a clean checkout loaded with pkgload::load_all().
#
# First it judges the pair once (data-raw/streams_parent.R): both builds
# closed and clean, one code, config, fresh and acc/flow/grad token per schema
# and the same across them, cut-min against a cut-full-* token, the same
# species per group, and the same modelling code between the two link_shas, as
# the pre-run gate judges a record. Whether a file mapped `none` is reached from
# wsg_run_one.R is judged on the code loaded here (HEAD), the same limit the
# gate accepts. Then it calls lnk_streams_parent() per group, largest first,
# and writes <out>/pair.tsv (the judged pair) and <out>/build.tsv (one row per
# group, appended as each finishes).
#
# --verify builds nothing: it names groups whose rows no longer match the
# newest builds (a re-model of either network leaves streams_parent behind),
# groups with no rows, segments without a row, and rows whose overlap_m +
# straddle_m is not the segment's length. Writes <out>/verify.tsv.
#
# Exit 0 when everything passed; 1 on a refusal, a failed group, or a stale
# group, each named.

main <- function() {
  argv <- commandArgs(trailingOnly = TRUE)
  opt <- function(name, default = "") {
    hit <- grep(sprintf("^--%s=", name), argv, value = TRUE)
    if (length(hit)) sub(sprintf("^--%s=", name), "", hit[length(hit)]) else default
  }
  known <- "^--(schema|schema-minimal|wsgs|out)=|^--verify$"
  bad <- argv[!grepl(known, argv)]
  if (length(bad)) stop("unknown argument: ", paste(bad, collapse = " "), call. = FALSE)
  schema <- opt("schema")
  schema_minimal <- opt("schema-minimal")
  if (!nzchar(schema) || !nzchar(schema_minimal)) {
    stop("give --schema=<full persist schema> and --schema-minimal=<minimal persist schema>",
         call. = FALSE)
  }
  for (s in c(schema, schema_minimal)) {
    if (!grepl("^[a-z_][a-z0-9_]*$", s)) stop("not a schema name: ", s, call. = FALSE)
  }
  wsgs <- toupper(opt("wsgs", "all"))
  verify <- "--verify" %in% argv
  out <- opt("out", file.path("data-raw", "logs", "streams_parent_444"))
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  repo <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg[1])), ".."))
  suppressPackageStartupMessages(pkgload::load_all(repo, quiet = TRUE))
  e <- new.env()
  sys.source(file.path(repo, "data-raw", "pretest.R"), envir = e)
  sys.source(file.path(repo, "data-raw", "streams_parent.R"), envir = e)

  conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "postgres")
  on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)
  DBI::dbExecute(conn, "SET client_min_messages = warning")

  pair <- e$streams_parent_pair_read(conn, schema, schema_minimal)
  if (!identical(wsgs, "ALL")) {
    want <- strsplit(wsgs, ",", fixed = TRUE)[[1]]
    if (!all(grepl("^[A-Z]{4}$", want))) stop("--wsgs takes group codes or all", call. = FALSE)
    miss <- setdiff(want, intersect(pair$wsg[pair$side == "full"], pair$wsg[pair$side == "minimal"]))
    if (length(miss)) {
      stop("not built in both schemas: ", paste(miss, collapse = ", "), call. = FALSE)
    }
    pair <- pair[pair$wsg %in% want, , drop = FALSE]
  }
  if (verify) return(verify_groups(conn, pair, schema, out))

  dirty <- e$pretest_git(repo, c("status", "--porcelain", "--untracked-files=no"))
  if (length(dirty)) {
    stop("the checkout has uncommitted changes; build from a clean tree:\n",
         paste(dirty, collapse = "\n"), call. = FALSE)
  }
  ns <- asNamespace("link")
  if (is.null(attr(get("lnk_pipeline_run", ns), "srcref"))) {
    stop("link loaded without srcrefs; the modelling path's reach cannot be read", call. = FALSE)
  }
  reached <- e$pretest_reach(ns, e$pretest_entries(file.path(repo, "data-raw", "wsg_run_one.R"), ns))
  if (!all(c("lnk_pipeline_run.R", "lnk_pipeline_prepare.R") %in% reached)) {
    stop("the modelling path's reach is missing the pipeline (", length(reached), " files)",
         call. = FALSE)
  }
  map <- e$pretest_map_read(file.path(repo, "data-raw", "pretest_inputs.csv"))
  why <- e$streams_parent_pair_why(pair, repo, map, reached)

  head_sha <- e$pretest_git(repo, c("rev-parse", "HEAD"))
  sides <- do.call(rbind, lapply(split(pair, pair$side), function(d) {
    data.frame(side = d$side[1], schema = d$schema[1], n_groups = nrow(d),
               config_name = paste(unique(d$config_name), collapse = ","),
               config_hash = paste(unique(d$config_hash), collapse = ","),
               link_sha = paste(unique(d$link_sha), collapse = ","),
               fresh_sha = paste(unique(d$fresh_sha), collapse = ","),
               token_cut = paste(unique(d$token_cut), collapse = ","),
               token_acc = paste(unique(d$token_acc), collapse = ","),
               token_grad = paste(unique(d$token_grad), collapse = ","),
               token_flow = paste(unique(d$token_flow), collapse = ","),
               run_uid = paste(sort(unique(d$run_uid)), collapse = ","),
               judged_at_link_sha = head_sha, verdict = if (nzchar(why)) "refused" else "pass",
               why = why, stringsAsFactors = FALSE)
  }))
  utils::write.table(sides, file.path(out, "pair.tsv"), sep = "\t", quote = FALSE,
                     row.names = FALSE, na = "")
  if (nzchar(why)) {
    message("[streams_parent] pair refused: ", why)
    return(1L)
  }
  message("[streams_parent] pair passes: ", schema, " (", sides$link_sha[sides$side == "full"],
          ") on ", schema_minimal, " (", sides$link_sha[sides$side == "minimal"], ")")

  sql_sizes <- sprintf(
    "SELECT watershed_group_code AS wsg, count(*) AS n FROM %s.streams GROUP BY 1",
    schema
  )
  sizes <- DBI::dbGetQuery(conn, sql_sizes)
  sizes$n <- as.numeric(sizes$n)
  groups <- unique(pair$wsg)
  groups <- groups[order(-sizes$n[match(groups, sizes$wsg)], groups)]

  build_tsv <- file.path(out, "build.tsv")
  if (file.exists(build_tsv)) file.remove(build_tsv)
  failed <- character()
  for (i in seq_along(groups)) {
    w <- groups[i]
    t0 <- Sys.time()
    res <- tryCatch(lnk_streams_parent(conn, w, schema, schema_minimal),  # nolint: object_usage_linter.
                    error = function(err) err)
    mins <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
    if (inherits(res, "error")) {
      failed <- c(failed, w)
      message(sprintf("[streams_parent] %d/%d %s FAILED: %s", i, length(groups), w,
                      conditionMessage(res)))
      row <- data.frame(wsg = w, status = "failed", minutes = round(mins, 3),
                        n_full = NA, n_minimal = NA, km = NA, n_straddle = NA,
                        km_straddle = NA, max_straddle_m = NA,
                        why = gsub("[\t\n]+", " ", conditionMessage(res)))
    } else {
      message(sprintf("[streams_parent] %d/%d %s done in %.2f min", i, length(groups), w, mins))
      row <- cbind(data.frame(wsg = w, status = "ok", minutes = round(mins, 3)),
                   res[, setdiff(names(res), "wsg")], why = "")
    }
    utils::write.table(row, build_tsv, sep = "\t", quote = FALSE, row.names = FALSE,
                       col.names = !file.exists(build_tsv), append = file.exists(build_tsv),
                       na = "")
  }
  if (length(failed)) {
    message("[streams_parent] ", length(failed), " group(s) failed: ", paste(failed, collapse = ", "))
    return(1L)
  }
  message("[streams_parent] built ", length(groups), " group(s) into ", schema, ".streams_parent")
  0L
}

# Groups whose streams_parent rows no longer describe the builds they sit on.
verify_groups <- function(conn, pair, schema, out) {
  sql_has <- sprintf(
    "SELECT to_regclass('%s.streams_parent') IS NOT NULL AS ok",
    schema
  )
  has <- DBI::dbGetQuery(conn, sql_has)$ok
  if (!isTRUE(has)) {
    message("[streams_parent] ", schema, ".streams_parent does not exist")
    return(1L)
  }
  sql_rows <- sprintf(
    "SELECT p.watershed_group_code AS wsg, count(*) AS n_rows,
            string_agg(DISTINCT p.run_id_full, ',') AS run_id_full,
            string_agg(DISTINCT p.run_id_minimal, ',') AS run_id_minimal,
            string_agg(DISTINCT p.schema_minimal, ',') AS schema_minimal,
            count(*) FILTER (WHERE s.id_segment IS NULL) AS n_no_segment,
            count(*) FILTER (WHERE abs(p.overlap_m + p.straddle_m - s.length_metre) > 1e-3)
              AS n_length_off
       FROM %1$s.streams_parent p
       LEFT JOIN %1$s.streams s USING (id_segment, watershed_group_code)
      GROUP BY 1",
    schema
  )
  rows <- DBI::dbGetQuery(conn, sql_rows)
  sql_segs <- sprintf(
    "SELECT s.watershed_group_code AS wsg, count(*) AS n_segments,
            count(*) FILTER (WHERE p.id_segment IS NULL) AS n_no_row
       FROM %1$s.streams s
       LEFT JOIN %1$s.streams_parent p USING (id_segment, watershed_group_code)
      GROUP BY 1",
    schema
  )
  segs <- DBI::dbGetQuery(conn, sql_segs)
  f <- pair[pair$side == "full", c("wsg", "run_id", "date_end")]
  m <- pair[pair$side == "minimal", c("wsg", "run_id", "date_end", "schema")]
  names(f)[2:3] <- c("newest_run_id_full", "newest_full_end")
  names(m)[2:4] <- c("newest_run_id_minimal", "newest_minimal_end", "newest_schema_minimal")
  v <- merge(merge(f, m, by = "wsg", all = TRUE), segs, by = "wsg", all.x = TRUE)
  v <- merge(v, rows, by = "wsg", all.x = TRUE)
  num <- c("n_segments", "n_no_row", "n_rows", "n_no_segment", "n_length_off")
  v[num] <- lapply(v[num], function(x) {
    x <- as.numeric(x)
    x[is.na(x)] <- 0
    x
  })
  v$why <- vapply(seq_len(nrow(v)), function(i) {
    r <- v[i, ]
    w <- character()
    if (r$n_rows == 0) w <- c(w, "no rows")
    if (r$n_rows > 0 && !identical(r$run_id_full, r$newest_run_id_full)) w <- c(w, "full re-modelled")
    if (r$n_rows > 0 && !identical(r$run_id_minimal, r$newest_run_id_minimal)) w <- c(w, "minimal re-modelled")
    if (r$n_rows > 0 && !identical(r$schema_minimal, r$newest_schema_minimal)) w <- c(w, "another minimal schema")
    if (is.na(r$newest_full_end) || is.na(r$newest_minimal_end)) w <- c(w, "newest build open")
    if (r$n_no_row > 0) w <- c(w, sprintf("%d segments without a row", as.integer(r$n_no_row)))
    if (r$n_no_segment > 0) w <- c(w, sprintf("%d rows without a segment", as.integer(r$n_no_segment)))
    if (r$n_length_off > 0) w <- c(w, sprintf("%d rows off the segment's length", as.integer(r$n_length_off)))
    paste(w, collapse = "; ")
  }, "")
  utils::write.table(v, file.path(out, "verify.tsv"), sep = "\t", quote = FALSE,
                     row.names = FALSE, na = "")
  stale <- v$wsg[nzchar(v$why)]
  if (length(stale)) {
    message("[streams_parent] ", length(stale), " group(s) stale: ", paste(stale, collapse = ", "))
    return(1L)
  }
  message("[streams_parent] all ", nrow(v), " group(s) current")
  0L
}

status <- main()
quit(status = status, save = "no")
