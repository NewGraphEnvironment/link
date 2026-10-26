#!/usr/bin/env Rscript
# digest_test.R — link#374: is a group's recompute right when only its
# dependency rule's groups are present? For one group G and each variant, a
# scratch schema gets the `barriers` and `barrier_overrides` rows of:
#
#   all      every other group in the source schema (the full-run state)
#   line     G's line-rule dependencies (recompute_deps.R; what the
#            scheduler waits for)
#   closure  G's outlet closure (#374's proposal; the negative control)
#
# then G is modelled into it as a run models it (LNK_HABITAT_GATE=0), and
# recomputed as the driver recomputes it (wsg_recompute_one.R, LNK_LOG=0).
# G's streams_access, streams_mapping_code and gated habitat flags are then
# compared row by row with the `all` variant. `line` must match; `closure`
# must not, for a group whose line dependencies reach outside its closure
# (otherwise the test cannot tell the rules apart).
#
# Usage (repo root): Rscript data-raw/logs/recompute_early_374/digest_test.R \
#   <WSG> <deps.tsv> <out dir> [source schema] [config]
args   <- commandArgs(trailingOnly = TRUE)
g      <- toupper(args[1]); deps_path <- args[2]; out <- args[3]
src    <- if (length(args) >= 4L) args[4] else "fresh_default"
config <- if (length(args) >= 5L) args[5] else "default"
dir.create(out, showWarnings = FALSE, recursive = TRUE)

suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")
q <- function(sql) DBI::dbGetQuery(conn, sql)
x <- function(sql) DBI::dbExecute(conn, sql)
lit <- function(v) paste(DBI::dbQuoteString(conn, v), collapse = ",")

deps <- utils::read.delim(deps_path, stringsAsFactors = FALSE)
sets <- list(
  all     = setdiff(q(sprintf("SELECT DISTINCT watershed_group_code w FROM %s.barriers", src))$w, g),
  line    = deps$dep[deps$rule == "line" & deps$wsg == g],
  closure = deps$dep[deps$rule == "closure" & deps$wsg == g])
cat(sprintf("%s: line %d groups, closure %d; line outside closure: %s\n", g,
            length(sets$line), length(sets$closure),
            paste(setdiff(sets$line, sets$closure), collapse = ",")))

run <- function(env, script, log) {
  rc <- system2("env", c(env, "Rscript", script, g, config), stdout = log, stderr = log)
  if (!identical(as.integer(rc), 0L)) stop(script, " failed for ", g, "; see ", log, call. = FALSE)
}

cfg <- lnk_config(config)
sp <- tolower(cfg$species)
res <- list()
for (v in names(sets)) {
  s <- paste0("fresh_374d_", tolower(v))
  t0 <- Sys.time()
  x(sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
  cfg$pipeline$schema <- s
  lnk_persist_init(conn, cfg, species = cfg$species)
  for (tb in c("barriers", "barrier_overrides")) {
    cols <- q(sprintf("SELECT column_name FROM information_schema.columns
      WHERE table_schema = '%s' AND table_name = '%s' ORDER BY ordinal_position", s, tb))$column_name
    if (length(sets[[v]])) {
      x(sprintf("INSERT INTO %s.%s (%s) SELECT %s FROM %s.%s WHERE watershed_group_code IN (%s)",
                s, tb, paste(cols, collapse = ","), paste(cols, collapse = ","), src, tb,
                lit(sets[[v]])))
    }
    x(sprintf("ANALYZE %s.%s", s, tb))
  }
  run(c(paste0("LNK_SCHEMA=", s), "LNK_LOAD=loadall", "LNK_GUARD_DOWNSTREAM=warn",
        "LNK_HABITAT_GATE=0"), "data-raw/wsg_run_one.R", file.path(out, paste0(g, "_", v, "_model.log")))
  run(c(paste0("LNK_SCHEMA=", s), "LNK_LOAD=loadall", "LNK_LOG=0"),
      "data-raw/wsg_recompute_one.R", file.path(out, paste0(g, "_", v, "_recompute.log")))
  cat(sprintf("  %-8s built in %.1f min\n", v, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

# Row-by-row comparison with `all`, per table, on the full key.
cmp <- function(tb, cols) {
  a <- "fresh_374d_all"
  do.call(rbind, lapply(c("line", "closure"), function(v) {
    b <- paste0("fresh_374d_", v)
    have <- q(sprintf("SELECT 1 FROM information_schema.tables WHERE table_schema = '%s' AND table_name = '%s'", a, tb))
    if (!nrow(have)) return(NULL)
    if (is.null(cols)) {
      cols <- setdiff(q(sprintf("SELECT column_name FROM information_schema.columns
        WHERE table_schema = '%s' AND table_name = '%s'", a, tb))$column_name, "geom")
    }
    r <- q(sprintf(
      "WITH x AS (SELECT %1$s FROM %2$s.%4$s WHERE watershed_group_code = '%5$s'),
            y AS (SELECT %1$s FROM %3$s.%4$s WHERE watershed_group_code = '%5$s')
       SELECT (SELECT count(*) FROM x) n_all, (SELECT count(*) FROM y) n_variant,
              (SELECT count(*) FROM (SELECT * FROM x EXCEPT SELECT * FROM y) d) only_all,
              (SELECT count(*) FROM (SELECT * FROM y EXCEPT SELECT * FROM x) d) only_variant",
      paste(cols, collapse = ","), a, b, tb, g))
    data.frame(wsg = g, table = tb, variant = v, r)
  }))
}
flags <- c("id_segment", "watershed_group_code", "accessible", "spawning", "rearing",
           "lake_rearing", "wetland_rearing")
out_tab <- rbind(
  cmp("streams_access", NULL),
  cmp("streams_mapping_code", NULL),
  do.call(rbind, lapply(sp, function(s) {
    tb <- paste0("streams_habitat_", s)
    have <- q(sprintf("SELECT column_name FROM information_schema.columns
      WHERE table_schema = 'fresh_374d_all' AND table_name = '%s'", tb))$column_name
    if (!length(have)) return(NULL)
    cmp(tb, intersect(flags, have))
  })))
print(out_tab, row.names = FALSE)
utils::write.table(out_tab, file.path(out, paste0(g, "_digest.tsv")), sep = "\t",
                   quote = FALSE, row.names = FALSE)
acc <- out_tab[out_tab$table == "streams_access" & out_tab$variant == "line", ]
if (nrow(acc) != 1L || acc$n_all == 0L) stop(g, ": no streams_access rows in the all variant; nothing was compared", call. = FALSE)
line_ok <- all(out_tab$only_all[out_tab$variant == "line"] == 0 &
               out_tab$only_variant[out_tab$variant == "line"] == 0)
closure_differs <- any(out_tab$only_all[out_tab$variant == "closure"] > 0 |
                       out_tab$only_variant[out_tab$variant == "closure"] > 0)
cat(sprintf("%s: line matches all: %s; closure differs: %s\n", g, line_ok, closure_differs))
for (v in names(sets)) x(sprintf("DROP SCHEMA IF EXISTS fresh_374d_%s CASCADE", tolower(v)))
DBI::dbDisconnect(conn)
# The negative control is part of the verdict: a group whose closure gives the
# same answer as the line rule cannot tell the rules apart.
if (!closure_differs) message(g, ": the closure gives the same result; this group discriminates nothing")
quit(status = if (line_ok && closure_differs) 0 else 1)
