#!/usr/bin/env Rscript
# e2e.R — the round trip of #465 on one host: does a one-group run that reads
# its downstream groups' barriers from the export classify access as one that
# reads the same rows from the provincial schema?
#
# Target BULL (built on m1 in fresh_default, run 20261103_163715-269b585a),
# whose line-rule dependencies (11) exceed its outlet closure (2) and whose
# path holds 12 override rows of other groups. Four arms, each a scratch
# persist schema modelled with wsg_run_one.R BULL default:
#   a  dependencies' rows loaded from the export (lnk_downstream_load), guard
#      in error mode (the default)
#   b  control: the same rows copied by SQL from fresh_default
#   c  nothing loaded, LNK_GUARD_DOWNSTREAM=ignore with a note
#   d  barriers loaded, overrides not
# a must equal b exactly; c and d are expected to differ.
#
# Usage (repo root): Rscript data-raw/logs/downstream_export_465/e2e.R <root> <out>
#   root  an export of fresh_default holding BULL and its dependencies
#   out   directory for the summary
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
root <- normalizePath(args[1], mustWork = TRUE)
out <- args[2]
dir.create(out, recursive = TRUE, showWarnings = FALSE)
target <- "BULL"
src <- "fresh_default"
arms <- c(a = "zz465_a", b = "zz465_b", c = "zz465_c", d = "zz465_d")

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg_for <- function(schema) {
  cfg <- lnk_config("default")
  cfg$pipeline$schema <- schema
  cfg
}
for (s in c(arms, "working_bull")) {
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
}

files <- lnk_downstream_files(file.path(root, "manifest.json"), target,
                              "default", cache_dir = file.path(out, "cache"))
utils::write.csv(files[, c("wsg", "class", "table", "rows", "run_id",
                           "config_hash")],
                 file.path(out, "files.csv"), row.names = FALSE)
deps <- sort(unique(files$wsg[files$class == "exported"]))
cat("dependencies exported:", paste(deps, collapse = ","), "\n")
stopifnot(all(files$class %in% c("exported", "not_held")))

# a: from the export
lnk_downstream_load(conn, files, cfg_for(arms[["a"]]))
# b: control, the same rows by SQL
cb <- cfg_for(arms[["b"]])
lnk_persist_init(conn, cb, species = cb$species)
arr <- paste0("{", paste(deps, collapse = ","), "}")
for (t in c("barriers", "barrier_overrides")) {
  cols <- paste(names(link:::.lnk_export_group_tables()[[t]]$cols),
                collapse = ", ")
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.%s (%s) SELECT %s FROM %s.%s
      WHERE watershed_group_code = ANY($1)", arms[["b"]], t, cols, cols, src,
    t), params = list(arr))
}
# d: barriers only
lnk_downstream_load(conn, files[is.na(files$table) |
                                  files$table == "barriers", ],
                    cfg_for(arms[["d"]]))

model <- function(arm) {
  env <- c(paste0("LNK_SCHEMA=", arms[[arm]]), "LNK_LOAD=loadall",
           "LNK_RUN_LABEL=e2e_465")
  if (arm == "c") {
    env <- c(env, "LNK_GUARD_DOWNSTREAM=ignore",
             # system2() pastes env into a shell line unquoted
             paste0("LNK_GUARD_DOWNSTREAM_NOTE=",
                    shQuote("e2e 465 arm c: nothing downstream loaded")))
  }
  log <- file.path(out, sprintf("model_%s.log", arm))
  t0 <- Sys.time()
  st <- system2("Rscript", c("data-raw/wsg_run_one.R", target, "default"),
                env = env, stdout = log, stderr = log)
  DBI::dbExecute(conn, "DROP SCHEMA IF EXISTS working_bull CASCADE")
  data.frame(arm = arm, exit = st,
             minutes = round(as.numeric(difftime(Sys.time(), t0,
                                                 units = "mins")), 2))
}
runs <- do.call(rbind, lapply(names(arms), model))
print(runs)

digest_of <- function(schema, table) {
  if (!link:::.lnk_table_exists(conn, paste0(schema, ".", table))) {
    return(data.frame(n = NA_integer_, d = NA_character_))
  }
  DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n,
            md5(string_agg(t::text, '|' ORDER BY t.id_segment)) AS d
       FROM %s.%s t WHERE watershed_group_code = $1", schema, table),
    params = list(target))
}
tabs <- c("streams", "streams_access", "streams_mapping_code")
dig <- do.call(rbind, lapply(c(arms, src), function(s) {
  do.call(rbind, lapply(tabs, function(t) {
    x <- digest_of(s, t)
    data.frame(schema = s, table = t, rows = x$n, md5 = x$d)
  }))
}))
print(dig)

# per-segment differences of each arm from a, on the access and code columns
diff_from <- function(s, base = arms[["a"]]) {
  cols <- setdiff(link:::.lnk_table_columns(conn,
                                            paste0(base, ".streams_access")),
                  c("id_segment", "watershed_group_code"))
  do.call(rbind, lapply(c(cols, "mapping_code"), function(cl) {
    tbl <- if (cl == "mapping_code") "streams_mapping_code" else "streams_access"
    mcols <- if (cl == "mapping_code") {
      setdiff(link:::.lnk_table_columns(conn,
                                        paste0(base, ".streams_mapping_code")),
              c("id_segment", "watershed_group_code"))
    } else cl
    do.call(rbind, lapply(mcols, function(m) {
      n <- DBI::dbGetQuery(conn, sprintf(
        "SELECT count(*)::int AS n FROM %s.%s x JOIN %s.%s y
           USING (id_segment, watershed_group_code)
          WHERE x.watershed_group_code = $1
            AND x.%s::text IS DISTINCT FROM y.%s::text", s, tbl, base, tbl,
        m, m), params = list(target))$n
      data.frame(schema = s, column = m, segments_differ = n)
    }))
  }))
}
diffs <- do.call(rbind, lapply(c(arms[c("b", "c", "d")], src), diff_from))
diffs <- diffs[diffs$segments_differ > 0 | diffs$schema == arms[["b"]], ]
print(diffs)

ver <- DBI::dbGetQuery(conn, sprintf(
  "SELECT '%s' AS schema, run_id, link_sha, link_dirty, fresh_version, notes
     FROM %s.log WHERE watershed_group_code = $1
    ORDER BY date_start DESC LIMIT 1", src, src), params = list(target))
utils::write.csv(runs, file.path(out, "runs.csv"), row.names = FALSE)
utils::write.csv(dig, file.path(out, "digests.csv"), row.names = FALSE)
utils::write.csv(diffs, file.path(out, "diffs.csv"), row.names = FALSE)
utils::write.csv(ver, file.path(out, "reference_build.csv"), row.names = FALSE)
cat("stamp: link", as.character(utils::packageVersion("link")),
    link:::.lnk_pkg_git_sha("link"), "dirty", link:::.lnk_pkg_git_dirty("link"),
    "| fresh", as.character(utils::packageVersion("fresh")), "\n")
