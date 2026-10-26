#!/usr/bin/env Rscript
# recompute_deps.R — which groups a group's recompute reads (link#374).
#
# A group's post-consolidate recompute (wsg_recompute_one.R) walks DOWNSTREAM
# from its own segments through the persist schema's barrier views, which read
# every group's `barriers` and `barrier_overrides` by position, not by group.
# So a group can be recomputed early only once every group holding a row on its
# downstream path has landed on the dispatcher. This writes that set, three ways:
#
#   closure  fresh::frs_wsg_drainage(): the groups the group's OUTLET flows
#            through. What #374 proposed. Too narrow: a group is not one
#            drainage (coastal groups hold many rivers, inland groups hold
#            tributaries that enter another group's main stem), so its own
#            segments can drain through groups its outlet never reaches.
#   owner    groups with a SEGMENT on the group's downstream path: for every
#            line the group touches, the most downstream segment of each other
#            group on each ancestor-or-equal line, kept when FWA's
#            fwa_downstream() puts it below the group's lowest segment on that
#            line. Complete only if every row is also held, identically, by
#            the group that owns the segment it sits on: true of this build's
#            data save a handful of rows (recompute_early_374/README.md), not
#            by construction.
#   line     groups touching ANY part of a line on the path: every blue line
#            carrying a code that is an ancestor of, or equal to, one of the
#            group's codes. Complete by construction, which is what the
#            scheduler uses: gradient barriers are found along the whole of
#            every line a group touches and persisted under its own code
#            (R/lnk_pipeline_prepare.R, R/lnk_barriers_unify.R), an override
#            is written at the group's own barrier positions, and every other
#            barrier source is filtered to the group's own segments. An early
#            recompute that reads too little cannot be undone (the habitat
#            gate is one-way), so the rule errs wide.
#
# FWA's unassigned codes (`999…`, construction lines) are left out on both
# sides: no persisted segment carries one, and `999` is never an ancestor of a
# real code, so no walk starts from or reaches one through code ancestry.
#
# Reads FWA only (whse_basemapping.fwa_stream_networks_sp), never a persist
# schema, so it answers the same before a run as after it.
#
# Usage: Rscript data-raw/recompute_deps.R <out.tsv> [rule=line] [wsgs csv]
#   out.tsv   columns wsg, rule, dep (one row per pair; a group with no
#             dependency has no row)
#   rule      line (default), owner, closure, or all
#   wsgs      restrict to these groups (default: every FWA group)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) {
  stop("usage: recompute_deps.R <out.tsv> [rule=line|owner|closure|all] [wsgs csv]",
    call. = FALSE
  )
}
out <- args[1]
rule <- if (length(args) >= 2L && nzchar(args[2])) args[2] else "line"
if (!rule %in% c("line", "owner", "closure", "all")) {
  stop("rule must be line, owner, closure or all (got '", rule, "')", call. = FALSE)
}
rules <- if (rule == "all") c("line", "owner", "closure") else rule
wsgs <- if (length(args) >= 3L && nzchar(args[3])) {
  toupper(strsplit(args[3], ",", fixed = TRUE)[[1]])
} else {
  NULL
}

suppressPackageStartupMessages({
  library(DBI)
  library(RPostgres)
})
conn <- DBI::dbConnect(RPostgres::Postgres(),
  dbname = "fwapg", host = "localhost",
  port = 5432L, user = "postgres", password = "postgres"
)

deps_fwa <- function(conn) {
  t0 <- Sys.time()
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.rd_seg")
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE rd_seg AS
    SELECT watershed_group_code w, blue_line_key blk, wscode_ltree ws,
           localcode_ltree loc, downstream_route_measure dm
    FROM whse_basemapping.fwa_stream_networks_sp
    WHERE watershed_group_code IS NOT NULL AND wscode_ltree IS NOT NULL
      AND NOT wscode_ltree ~ '999.*'::lquery")
  # One representative per (group, code): the group's most downstream segment.
  # The owner rule needs a local code to place it; the line rule does not, so
  # the 158,188 segments FWA leaves without one stay in rd_seg for the line
  # rule (leaving them out there dropped 52 of its pairs).
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.rd_rep")
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE rd_rep AS
    SELECT DISTINCT ON (w, ws) w, ws, loc FROM rd_seg
    WHERE loc IS NOT NULL ORDER BY w, ws, loc, dm")
  DBI::dbExecute(conn, "CREATE INDEX ON rd_rep (ws)")
  DBI::dbExecute(conn, "ANALYZE rd_rep")
  # Every ancestor-or-equal code of each group's codes.
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.rd_anc")
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE rd_anc AS
    SELECT r.w, r.ws, r.loc, subpath(r.ws, 0, i) a
    FROM rd_rep r, generate_series(1, nlevel(r.ws)) i")
  owner <- DBI::dbGetQuery(conn, "
    SELECT DISTINCT a.w AS wsg, r2.w AS dep
    FROM rd_anc a JOIN rd_rep r2 ON r2.ws = a.a AND r2.w <> a.w
    WHERE whse_basemapping.fwa_downstream(a.ws, a.loc, r2.ws, r2.loc)")
  # Lines on the path, by blue_line_key, then every group touching them. The
  # codes come from every segment, not only the representatives.
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.rd_anc_all")
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE rd_anc_all AS
    SELECT DISTINCT g.w, subpath(g.ws, 0, i) a
    FROM (SELECT DISTINCT w, ws FROM rd_seg) g, generate_series(1, nlevel(g.ws)) i")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.rd_pathblk")
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE rd_pathblk AS
    SELECT DISTINCT a.w, s.blk
    FROM rd_anc_all a JOIN rd_seg s ON s.ws = a.a")
  DBI::dbExecute(conn, "CREATE INDEX ON rd_pathblk (blk)")
  line <- DBI::dbGetQuery(conn, "
    SELECT DISTINCT p.w AS wsg, t.w AS dep
    FROM rd_pathblk p JOIN (SELECT DISTINCT w, blk FROM rd_seg) t USING (blk)
    WHERE t.w <> p.w")
  # Nothing from FWA is a broken source (an empty or unpopulated table), not
  # a province with no dependencies: refused, because the scheduler would then
  # start every landed group at once.
  if (nrow(line) == 0L || nrow(owner) == 0L) {
    stop("recompute_deps: FWA gave no dependency pairs; refusing to write an empty map",
      call. = FALSE
    )
  }
  message(sprintf(
    "[recompute_deps] FWA rules in %.1f s",
    as.numeric(difftime(Sys.time(), t0, units = "secs"))
  ))
  list(owner = owner, line = line)
}

res <- list()
if (any(c("line", "owner") %in% rules)) {
  f <- deps_fwa(conn)
  for (r in intersect(c("line", "owner"), rules)) res[[r]] <- f[[r]]
}
if ("closure" %in% rules) {
  groups <- if (is.null(wsgs)) fresh::frs_wsg_outlets()$watershed_group_code else wsgs
  res$closure <- do.call(rbind, lapply(groups, function(g) {
    d <- setdiff(fresh::frs_wsg_drainage(conn, g), g)
    if (length(d) == 0L) {
      return(NULL)
    }
    data.frame(wsg = g, dep = d)
  }))
}
DBI::dbDisconnect(conn)

tab <- do.call(rbind, lapply(names(res), function(r) {
  x <- res[[r]]
  if (is.null(x) || nrow(x) == 0L) {
    return(NULL)
  }
  data.frame(wsg = x$wsg, rule = r, dep = x$dep)
}))
if (is.null(tab)) tab <- data.frame(wsg = character(), rule = character(), dep = character())
if (!is.null(wsgs)) tab <- tab[tab$wsg %in% wsgs, , drop = FALSE]
tab <- tab[order(tab$rule, tab$wsg, tab$dep), , drop = FALSE]
utils::write.table(tab, out, sep = "\t", quote = FALSE, row.names = FALSE)
for (r in rules) {
  n <- table(factor(tab$wsg[tab$rule == r]))
  message(sprintf(
    "[recompute_deps] %s: %d pairs over %d groups (median %s per group with any)",
    r, sum(tab$rule == r), length(n), stats::median(as.integer(n))
  ))
}
