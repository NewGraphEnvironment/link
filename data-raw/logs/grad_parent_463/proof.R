#!/usr/bin/env Rscript
# proof.R — #463: does a default_parent build differ from a default build only
# where the parent gradient reaches? Reads persisted tables only (wsg_run_one.R
# overwrites the working tables between builds).
#
#   Rscript data-raw/logs/grad_parent_463/proof.R --wsgs=BULK,SETN,MORK,COTR [--out=<dir>]
#
# Schemas: zz469_control (default), fresh_default_parent (default_parent), and
# the pair the parents were joined from, fresh_default and fresh_default_minimal.
# Segments are keyed by (blue_line_key, downstream_route_measure to the mm),
# never by id_segment (each build numbers its own).
#
# Stops (exit 1), naming why, on:
#   builds    an open or dirty build; the two schemas not at one link_sha and
#             fresh_sha; tokens other than cut-full-top acc-v5 grad-seg q-fwapg
#             (control) and grad-parent in its place (parent); a parent row whose
#             notes do not name the group's newest fresh_default and
#             fresh_default_minimal runs; R/, inst/ or DESCRIPTION changed
#             between the builds' commit and HEAD
#   segments  control, parent and fresh_default not holding the same segments
#   gradient  a parent gradient that is not its streams_parent gradient_minimal,
#             or a control gradient that is not fresh_default's
#   access    any streams_access value differing between control and parent
#   habitat   a habitat flag differing on a segment whose gradient did not
#             change and that no connectivity reach explains (below)
#
# A habitat difference is classed:
#   own_gradient  the segment's gradient changed
#   connectivity  not accessible, the segment lies in a cluster, with links of
#                 at most 10 km straight-line (the connect pass's bridge and
#                 connected distances, a network distance no shorter than the
#                 straight line), of segments that changed gradient or differ in
#                 that species' habitat, and the cluster holds a changed segment
#   unexplained   anything else; `accessible` never moves by connectivity
#
# #462: CH rearing the near-river distance's transfer costs: CH 1050/1150
# segments of default_parent, accessible (access_ch >= 1, the same in both
# builds), failing CH's rear width (channel_width below 1.5 m, or none), whose
# parent's near-river distance (fresh_default_minimal.streams_near_river, the
# CH rear pair: channel_width 15 m within 1000 m) is within 1000 m while their
# own (fresh_default_parent.streams_near_river) is not, and not rearing in
# default_parent. Knowledge's 1,042 km applied the pair to every line; default
# applies it to 1050/1150 lines only, so the two are not comparable.

suppressPackageStartupMessages({
  library(DBI)
})

argv <- commandArgs(trailingOnly = TRUE)
opt <- function(name, default = "") {
  hit <- grep(sprintf("^--%s=", name), argv, value = TRUE)
  if (length(hit)) sub(sprintf("^--%s=", name), "", hit[length(hit)]) else default
}
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
here <- normalizePath(dirname(sub("^--file=", "", file_arg[1])))
repo <- normalizePath(file.path(here, "..", "..", ".."))
out <- opt("out", here)
wsgs <- strsplit(toupper(opt("wsgs")), ",", fixed = TRUE)[[1]]
stopifnot(length(wsgs) > 0, all(grepl("^[A-Z]{4}$", wsgs)))
dir.create(out, recursive = TRUE, showWarnings = FALSE)

S_CONTROL <- Sys.getenv("LNK463_CONTROL", "zz469_control")  # override for a smoke run only
S_PARENT <- Sys.getenv("LNK463_PARENT", "fresh_default_parent")
S_FULL <- "fresh_default"
S_MINIMAL <- "fresh_default_minimal"
SPECIES <- c("bt", "ch", "cm", "co", "pk", "sk", "st", "wct", "gr")
FLAGS <- c("accessible", "spawning", "rearing", "lake_rearing", "wetland_rearing")
REACH_M <- 10000

conn <- dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                  port = 5432L, user = "postgres", password = "postgres")
on.exit(try(dbDisconnect(conn), silent = TRUE), add = TRUE)
dbExecute(conn, "SET client_min_messages = warning")
q <- function(...) dbGetQuery(conn, sprintf(...))
lit <- function(x) paste0("'", gsub("'", "''", x), "'")
in_wsgs <- paste(vapply(wsgs, lit, ""), collapse = ", ")
fail <- character()
stop_on <- function(cond, msg) if (isTRUE(cond)) fail <<- c(fail, msg)
write <- function(d, f) {
  utils::write.csv(d, file.path(out, f), row.names = FALSE, na = "")
  message("[proof] wrote ", f, " (", nrow(d), " rows)")
}
git <- function(...) system2("git", c("-C", repo, ...), stdout = TRUE)

# --- builds ------------------------------------------------------------------
newest <- function(s) {
  q("SELECT DISTINCT ON (watershed_group_code) watershed_group_code AS wsg, %s AS schema,
            run_id, run_uid, date_start, date_end, config_name, link_sha, link_dirty,
            fresh_sha, fresh_dirty, token_cut, token_acc, token_grad, token_flow, notes
       FROM %s.log WHERE watershed_group_code IN (%s)
      ORDER BY watershed_group_code, date_start DESC", lit(s), s, in_wsgs)
}
b <- rbind(newest(S_CONTROL), newest(S_PARENT))
pair <- rbind(newest(S_FULL)[, c("wsg", "schema", "run_id")], newest(S_MINIMAL)[, c("wsg", "schema", "run_id")])
write(b, "builds.csv")
for (s in c(S_CONTROL, S_PARENT)) {
  miss <- setdiff(wsgs, b$wsg[b$schema == s])
  stop_on(length(miss) > 0, sprintf("builds: %s has no build of %s", s, paste(miss, collapse = ", ")))
}
stop_on(anyNA(b$date_end), "builds: an open build")
stop_on(!all(b$link_dirty %in% FALSE) || !all(b$fresh_dirty %in% FALSE), "builds: a dirty build")
stop_on(length(unique(b$link_sha)) != 1L || anyNA(b$link_sha), "builds: not one link_sha")
stop_on(length(unique(b$fresh_sha)) != 1L || anyNA(b$fresh_sha), "builds: not one fresh_sha")
want_tok <- function(s, grad) {
  d <- b[b$schema == s, ]
  all(d$token_cut == "cut-full-top" & d$token_acc == "acc-v5" & d$token_grad == grad &
        d$token_flow == "q-fwapg")
}
stop_on(!want_tok(S_CONTROL, "grad-seg"), "builds: control tokens are not cut-full-top acc-v5 grad-seg q-fwapg")
stop_on(!want_tok(S_PARENT, "grad-parent"), "builds: parent tokens are not cut-full-top acc-v5 grad-parent q-fwapg")
for (w in wsgs) {
  note <- b$notes[b$schema == S_PARENT & b$wsg == w]
  rf <- pair$run_id[pair$schema == S_FULL & pair$wsg == w]
  r_min <- pair$run_id[pair$schema == S_MINIMAL & pair$wsg == w]
  ok <- length(note) == 1L && grepl(sprintf("run_id_full %s, run_id_minimal %s in %s", rf, r_min, S_MINIMAL),
                                    note, fixed = TRUE)
  stop_on(!ok, sprintf("builds: %s's parent notes do not name %s and %s", w, rf, r_min))
}
sha <- unique(b$link_sha)[1]
if (!is.na(sha)) {
  moved <- git("diff", "--name-only", sha, "HEAD", "--", "R", "inst", "DESCRIPTION")
  stop_on(length(moved) > 0, paste("builds: changed since the builds:", paste(moved, collapse = ", ")))
}

# --- segments ----------------------------------------------------------------
key <- "blue_line_key, round(downstream_route_measure::numeric, 3) AS dm,
        round(upstream_route_measure::numeric, 3) AS um"
invisible(dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.k_c, pg_temp.k_p, pg_temp.k_f"))
for (x in list(c("k_c", S_CONTROL), c("k_p", S_PARENT), c("k_f", S_FULL))) {
  dbExecute(conn, sprintf(
    "CREATE TEMP TABLE %s AS SELECT watershed_group_code AS wsg, id_segment, %s, gradient,
            length_metre, edge_type, channel_width, geom
       FROM %s.streams WHERE watershed_group_code IN (%s)", x[1], key, x[2], in_wsgs))
  dbExecute(conn, sprintf("CREATE INDEX ON pg_temp.%s (wsg, blue_line_key, dm)", x[1]))
  dbExecute(conn, sprintf("ANALYZE pg_temp.%s", x[1]))
}
seg <- q(
  "SELECT w.wsg,
          (SELECT count(*) FROM pg_temp.k_c c WHERE c.wsg = w.wsg) AS n_control,
          (SELECT count(*) FROM pg_temp.k_p p WHERE p.wsg = w.wsg) AS n_parent,
          (SELECT count(*) FROM pg_temp.k_f f WHERE f.wsg = w.wsg) AS n_full,
          (SELECT count(*) FROM pg_temp.k_c c JOIN pg_temp.k_p p USING (wsg, blue_line_key, dm, um)
            WHERE c.wsg = w.wsg) AS n_control_parent,
          (SELECT count(*) FROM pg_temp.k_c c JOIN pg_temp.k_f f USING (wsg, blue_line_key, dm, um)
            WHERE c.wsg = w.wsg) AS n_control_full,
          (SELECT round(sum(length_metre)::numeric / 1000, 3) FROM pg_temp.k_p p WHERE p.wsg = w.wsg) AS km
     FROM unnest(ARRAY[%s]) AS w(wsg) ORDER BY 1", in_wsgs)
seg[-1] <- lapply(seg[-1], as.numeric)
write(seg, "segments.csv")
stop_on(any(seg$n_control != seg$n_parent | seg$n_control != seg$n_full |
              seg$n_control_parent != seg$n_control | seg$n_control_full != seg$n_control),
        "segments: control, parent and fresh_default do not hold the same segments")

# One row per segment: both builds' ids, gradients and the parent's.
dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.s")
dbExecute(conn, sprintf(
  "CREATE TEMP TABLE s AS
   SELECT c.wsg, c.id_segment AS id_c, p.id_segment AS id_p, f.id_segment AS id_f,
          c.blue_line_key, c.dm, c.length_metre, c.edge_type, c.channel_width, c.geom,
          c.gradient AS g_control, p.gradient AS g_parent, f.gradient AS g_full,
          pr.gradient_minimal AS g_minimal, pr.id_segment_minimal AS id_m
     FROM pg_temp.k_c c
     JOIN pg_temp.k_p p USING (wsg, blue_line_key, dm, um)
     JOIN pg_temp.k_f f USING (wsg, blue_line_key, dm, um)
     LEFT JOIN %s.streams_parent pr
       ON pr.id_segment = f.id_segment AND pr.watershed_group_code = f.wsg", S_FULL))
dbExecute(conn, "CREATE INDEX ON pg_temp.s (wsg, id_c)")
dbExecute(conn, "CREATE INDEX ON pg_temp.s (wsg, id_p)")
dbExecute(conn, "ANALYZE pg_temp.s")

# --- gradient ----------------------------------------------------------------
grad <- q(
  "SELECT wsg, count(*) AS n,
          count(*) FILTER (WHERE g_minimal IS NULL) AS n_no_parent,
          count(*) FILTER (WHERE g_parent IS DISTINCT FROM g_minimal) AS n_parent_not_minimal,
          count(*) FILTER (WHERE g_control IS DISTINCT FROM g_full) AS n_control_not_full,
          count(*) FILTER (WHERE g_parent IS DISTINCT FROM g_control) AS n_changed,
          round(sum(length_metre) FILTER (WHERE g_parent IS DISTINCT FROM g_control)::numeric / 1000, 3)
            AS km_changed,
          round(sum(length_metre)::numeric / 1000, 3) AS km
     FROM pg_temp.s GROUP BY 1 ORDER BY 1")
grad[-1] <- lapply(grad[-1], as.numeric)
write(grad, "gradient.csv")
stop_on(any(grad$n_no_parent > 0 | grad$n_parent_not_minimal > 0),
        "gradient: a parent gradient is not its streams_parent gradient_minimal")
stop_on(any(grad$n_control_not_full > 0), "gradient: a control gradient is not fresh_default's")

# --- access ------------------------------------------------------------------
acc_cols <- q("SELECT column_name FROM information_schema.columns
                WHERE table_schema = %s AND table_name = 'streams_access'
                  AND column_name NOT IN ('id_segment', 'watershed_group_code')
                ORDER BY ordinal_position", lit(S_CONTROL))$column_name
diffs <- paste(sprintf("count(*) FILTER (WHERE a.%1$s IS DISTINCT FROM b.%1$s) AS %1$s", acc_cols),
               collapse = ",\n")
acc <- q(
  "SELECT s.wsg, count(*) AS n, count(a.id_segment) AS n_control_rows,
          count(b.id_segment) AS n_parent_rows, %s
     FROM pg_temp.s s
     LEFT JOIN %s.streams_access a ON a.id_segment = s.id_c AND a.watershed_group_code = s.wsg
     LEFT JOIN %s.streams_access b ON b.id_segment = s.id_p AND b.watershed_group_code = s.wsg
    GROUP BY 1 ORDER BY 1", diffs, S_CONTROL, S_PARENT)
acc[-1] <- lapply(acc[-1], as.numeric)
write(acc, "access.csv")
stop_on(any(acc$n_control_rows != acc$n | acc$n_parent_rows != acc$n), "access: a segment has no access row")
stop_on(any(as.matrix(acc[acc_cols]) != 0), "access: control and parent differ")

# --- habitat -----------------------------------------------------------------
hab <- list()
cls <- list()
for (sp in SPECIES) {
  tc <- sprintf("%s.streams_habitat_%s", S_CONTROL, sp)
  tp <- sprintf("%s.streams_habitat_%s", S_PARENT, sp)
  dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.h")
  sel <- paste(sprintf("coalesce(hc.%1$s, false) AS c_%1$s, coalesce(hp.%1$s, false) AS p_%1$s", FLAGS),
               collapse = ", ")
  dbExecute(conn, sprintf(
    "CREATE TEMP TABLE h AS
     SELECT s.wsg, s.id_c, s.length_metre, s.geom,
            s.g_parent IS DISTINCT FROM s.g_control AS changed, %s
       FROM pg_temp.s s
       LEFT JOIN %s hc ON hc.id_segment = s.id_c AND hc.watershed_group_code = s.wsg
       LEFT JOIN %s hp ON hp.id_segment = s.id_p AND hp.watershed_group_code = s.wsg",
    sel, tc, tp))
  any_diff <- paste(sprintf("c_%1$s <> p_%1$s", FLAGS), collapse = " OR ")
  hab[[sp]] <- do.call(rbind, lapply(FLAGS, function(fl) {
    d <- q(
      "SELECT wsg, %1$s AS species, %2$s AS flag,
              round(sum(length_metre) FILTER (WHERE c_%3$s)::numeric / 1000, 3) AS km_control,
              round(sum(length_metre) FILTER (WHERE p_%3$s)::numeric / 1000, 3) AS km_parent,
              count(*) FILTER (WHERE c_%3$s <> p_%3$s) AS n_diff,
              round(coalesce(sum(length_metre) FILTER (WHERE p_%3$s AND NOT c_%3$s), 0)::numeric / 1000, 3)
                AS km_gained,
              round(coalesce(sum(length_metre) FILTER (WHERE c_%3$s AND NOT p_%3$s), 0)::numeric / 1000, 3)
                AS km_lost
         FROM pg_temp.h GROUP BY wsg ORDER BY wsg", lit(sp), lit(fl), fl)
    d
  }))
  # Clusters (10 km straight-line links) over the segments that changed gradient
  # or differ in this species' habitat; a difference is explained by
  # connectivity when its cluster holds a changed segment.
  dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.hc")
  dbExecute(conn, sprintf(
    "CREATE TEMP TABLE hc AS
     SELECT wsg, id_c, changed, %s,
            ST_ClusterDBSCAN(geom, eps := %d, minpoints := 1) OVER (PARTITION BY wsg) AS cid
       FROM pg_temp.h WHERE changed OR %s",
    paste(sprintf("c_%1$s, p_%1$s", FLAGS), collapse = ", "), REACH_M, any_diff))
  cls[[sp]] <- do.call(rbind, lapply(FLAGS, function(fl) {
    conn_ok <- if (fl == "accessible") "false" else "x.has_changed"
    q(
      "WITH x AS (SELECT wsg, cid, bool_or(changed) AS has_changed FROM pg_temp.hc GROUP BY 1, 2)
       SELECT hc.wsg, %1$s AS species, %2$s AS flag,
              CASE WHEN hc.changed THEN 'own_gradient'
                   WHEN %4$s THEN 'connectivity' ELSE 'unexplained' END AS class,
              count(*) AS n
         FROM pg_temp.hc hc JOIN x USING (wsg, cid)
        WHERE hc.c_%3$s <> hc.p_%3$s
        GROUP BY 1, 2, 3, 4 ORDER BY 1, 4", lit(sp), lit(fl), fl, conn_ok)
  }))
}
hab <- do.call(rbind, hab)
hab[c("km_control", "km_parent", "n_diff", "km_gained", "km_lost")] <-
  lapply(hab[c("km_control", "km_parent", "n_diff", "km_gained", "km_lost")], as.numeric)
cls <- do.call(rbind, cls)
cls$n <- as.numeric(cls$n)
write(hab, "habitat.csv")
write(cls, "habitat_classes.csv")
un <- cls[cls$class == "unexplained", ]
stop_on(nrow(un) > 0, sprintf("habitat: %d differences unexplained (%s)", as.integer(sum(un$n)),
                              paste(unique(paste(un$wsg, un$species, un$flag)), collapse = "; ")))

# --- #462: the near-river distance's transfer cost ----------------------------
nr <- q(
  "WITH own AS (
     SELECT id_segment, watershed_group_code, dist_m FROM %1$s.streams_near_river
      WHERE measure = 'channel_width' AND threshold = 15 AND distance_max = 1000),
   par AS (
     SELECT id_segment, watershed_group_code, dist_m FROM %2$s.streams_near_river
      WHERE measure = 'channel_width' AND threshold = 15 AND distance_max = 1000)
   SELECT s.wsg,
          count(*) AS n_ch_wetland_flow,
          count(*) FILTER (WHERE own.dist_m <= 1000) AS n_own_near,
          count(*) FILTER (WHERE par.dist_m <= 1000) AS n_parent_near,
          count(*) FILTER (WHERE (s.channel_width < 1.5 OR s.channel_width IS NULL)
                            AND par.dist_m <= 1000 AND (own.dist_m > 1000 OR own.dist_m IS NULL)
                            AND NOT coalesce(h.rearing, false)) AS n_cost,
          round(coalesce(sum(s.length_metre) FILTER (
                  WHERE (s.channel_width < 1.5 OR s.channel_width IS NULL)
                    AND par.dist_m <= 1000 AND (own.dist_m > 1000 OR own.dist_m IS NULL)
                    AND NOT coalesce(h.rearing, false)), 0)::numeric / 1000, 3) AS km_cost
     FROM pg_temp.s s
     JOIN %3$s.streams_access a ON a.id_segment = s.id_p AND a.watershed_group_code = s.wsg
     LEFT JOIN %3$s.streams_habitat_ch h ON h.id_segment = s.id_p AND h.watershed_group_code = s.wsg
     LEFT JOIN own ON own.id_segment = s.id_p AND own.watershed_group_code = s.wsg
     LEFT JOIN par ON par.id_segment = s.id_m AND par.watershed_group_code = s.wsg
    WHERE s.edge_type IN (1050, 1150) AND a.access_ch >= 1
    GROUP BY 1 ORDER BY 1", S_PARENT, S_MINIMAL, S_PARENT)
nr[-1] <- lapply(nr[-1], as.numeric)
write(nr, "near_river_462.csv")
# The pair rows must be unique per segment, or the joins above double count.
dup <- sum(vapply(c(S_PARENT, S_MINIMAL), function(sch) {
  as.numeric(q(
    "SELECT count(*) - count(DISTINCT (id_segment, watershed_group_code)) AS n
       FROM %s.streams_near_river
      WHERE measure = 'channel_width' AND threshold = 15 AND distance_max = 1000
        AND watershed_group_code IN (%s)", sch, in_wsgs)$n)
}, numeric(1)))
stop_on(as.numeric(dup) > 0, "near_river: more than one CH rear pair row per segment")

stamp <- data.frame(
  proof_link_sha = git("rev-parse", "HEAD"), builds_link_sha = sha,
  fresh_sha = unique(b$fresh_sha)[1], run_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  verdict = if (length(fail)) "fail" else "pass", why = paste(fail, collapse = " | "))
write(stamp, "verdict.csv")
if (length(fail)) {
  message("[proof] FAILED:\n  ", paste(fail, collapse = "\n  "))
  quit(status = 1, save = "no")
}
message("[proof] every check passed")
