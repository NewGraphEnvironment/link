#!/usr/bin/env Rscript
# discharge_fill_count.R — where `fwa_stream_networks_discharge` has no value,
# and how well a fill along the line would replace it (link#305).
#
# #300 found that `mad` loses river-polygon main stems (edge type 1250)
# because they carry no discharge, and that these are the most-used water in
# the cw/mad comparison. Before the fill lands this script counts the gap and
# measures the fill, using the SQL the pipeline ships
# (`.lnk_discharge_candidates_sql()`, R/lnk_discharge.R), so the numbers
# describe the fill that classify will use.
#
#   Rscript data-raw/discharge_fill_count.R \
#     [--out=data-raw/logs/discharge_fill_305] [--prefix=score300]
#     [--base=default_tuned] [--roles=data-raw/habitat_score/wsg_roles_300.csv]
#     [--long-gap=10000]
#
# "Covered" WSGs are those with any non-NULL mad_m3s. The gap outside them is
# whole groups the discharge layer does not model, which no fill addresses.
#
# Writes to --out:
#   coverage_edge.csv   km and lines by edge type x order class x state
#                       (absent from the table, row with NULL value, valued),
#                       covered WSGs
#   coverage_1250.csv   edge 1250 by WSG x state, covered WSGs
#   root_cause.csv      edge 1250 by state x whether the line has a fundamental
#                       watershed in fwa_streams_watersheds_lut
#   accuracy.csv        valued edge 1250 lines masked one at a time: the error
#                       of the upstream and the downstream neighbour's value
#                       against the line's own, by gap-length class; and, on a
#                       1-in-50 sample, the first valued line at least
#                       --long-gap m upstream and the tributary tier
#   accuracy_min.csv    how often the neighbour's value falls on the other side
#                       of a species' MAD minimum from the line's own value
#   reach.csv           NULL edge 1250 lines by the tier that fills them, and
#                       the gap to the neighbour that does
#   band_reach.csv      #300's cw-only band segments with no discharge (from the
#                       `<prefix>_*` schemas), by fill tier and whether the
#                       filled value clears the species' MAD minimum
#   stamp.txt           environment stamp
#
# Read-only against docker fwapg (:5432).

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
dir_out <- opt("out", file.path("data-raw", "logs", "discharge_fill_305"))
prefix <- opt("prefix", "score300")
base <- opt("base", "default_tuned")
path_roles <- opt("roles", file.path("data-raw", "habitat_score",
                                     "wsg_roles_300.csv"))
fs::dir_create(dir_out)

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
write <- function(x, f) {
  utils::write.csv(x, file.path(dir_out, f), row.names = FALSE, na = "")
  message("wrote ", f, " (", nrow(x), " rows)")
}
order_class <- "CASE WHEN s.stream_order >= 4 THEN '4+'
                     ELSE coalesce(s.stream_order::text, 'unknown') END"
state <- "CASE WHEN d.linear_feature_id IS NULL THEN 'absent'
               WHEN d.mad_m3s IS NULL THEN 'row_null' ELSE 'valued' END"
tbl <- .lnk_hv_discharge_tbl()

covered <- dbGetQuery(conn, sprintf(
  "SELECT watershed_group_code FROM %s GROUP BY 1 HAVING count(mad_m3s) > 0
    ORDER BY 1", tbl))$watershed_group_code
message(length(covered), " covered WSGs")
cov_in <- paste0("{", paste(covered, collapse = ","), "}")

# -- coverage --------------------------------------------------------------------
cov <- dbGetQuery(conn, sprintf(
  "SELECT s.edge_type, %s AS order_class, %s AS state,
          sum(s.length_metre) / 1000 AS km, count(*) AS n_lines
     FROM whse_basemapping.fwa_stream_networks_sp s
     LEFT JOIN %s d ON d.linear_feature_id = s.linear_feature_id
    WHERE s.watershed_group_code = ANY($1)
      AND s.edge_type NOT IN (6010) AND s.localcode_ltree IS NOT NULL
    GROUP BY 1, 2, 3 ORDER BY 1, 2, 3", order_class, state, tbl),
  params = list(cov_in))
write(cov, "coverage_edge.csv")

cov_1250 <- dbGetQuery(conn, sprintf(
  "SELECT s.watershed_group_code, %s AS state,
          sum(s.length_metre) / 1000 AS km, count(*) AS n_lines
     FROM whse_basemapping.fwa_stream_networks_sp s
     LEFT JOIN %s d ON d.linear_feature_id = s.linear_feature_id
    WHERE s.watershed_group_code = ANY($1) AND s.edge_type = 1250
    GROUP BY 1, 2 ORDER BY 1, 2", state, tbl), params = list(cov_in))
write(cov_1250, "coverage_1250.csv")

# -- root cause (diagnosis only) -------------------------------------------------
# fwapg's discharge extra joins each line to its fundamental watershed
# (fwa_streams_watersheds_lut) and that watershed's accumulated discharge; a
# line with no row either has no watershed in the lookup or a watershed with
# no discharge row. The intermediate per-watershed tables are not in this DB.
rc <- dbGetQuery(conn, sprintf(
  "SELECT %s AS state,
          l.linear_feature_id IS NOT NULL AS in_lut,
          sum(s.length_metre) / 1000 AS km, count(*) AS n_lines,
          count(DISTINCT s.watershed_group_code) AS n_wsg
     FROM whse_basemapping.fwa_stream_networks_sp s
     LEFT JOIN %s d ON d.linear_feature_id = s.linear_feature_id
     LEFT JOIN (SELECT DISTINCT linear_feature_id
                  FROM whse_basemapping.fwa_streams_watersheds_lut) l
       ON l.linear_feature_id = s.linear_feature_id
    WHERE s.watershed_group_code = ANY($1) AND s.edge_type = 1250
    GROUP BY 1, 2 ORDER BY 1, 2", state, tbl), params = list(cov_in))
write(rc, "root_cause.csv")

# -- fill candidates over every edge 1250 line in covered WSGs ------------------
# The subquery returns every line (the fill coalesces over them all); the
# lookups ran for edge 1250 only, so keep those.
cand <- dbGetQuery(conn, sprintf(
  "SELECT * FROM %s c WHERE c.edge_type = 1250",
  .lnk_discharge_candidates_sql(covered, "all", tributary = FALSE)))
message(nrow(cand), " edge 1250 lines with candidates")
gap_class <- function(g) {
  cut(g, c(-Inf, 0, 500, 2000, 10000, Inf), right = TRUE,
      labels = c("adjacent", "0-500 m", "0.5-2 km", "2-10 km", ">10 km"))
}

# -- accuracy: mask each valued line, compare its neighbours' values --------------
val <- cand[!is.na(cand$mad_m3s), ]
acc_one <- function(tier, est, gap) {
  ok <- !is.na(est)
  x <- data.frame(tier = tier, gap_class = gap_class(gap[ok]),
                  truth = val$mad_m3s[ok], est = est[ok],
                  km = val$length_metre[ok] / 1000)
  x$rel <- (x$est - x$truth) / x$truth
  x
}
acc <- rbind(acc_one("upstream", val$mad_m3s_up, val$gap_up_m),
             acc_one("downstream", val$mad_m3s_dn, val$gap_dn_m))
# The rule as it will run: upstream first, else downstream.
first <- ifelse(!is.na(val$mad_m3s_up), val$mad_m3s_up, val$mad_m3s_dn)
first_gap <- ifelse(!is.na(val$mad_m3s_up), val$gap_up_m, val$gap_dn_m)
acc <- rbind(acc, acc_one("rule", first, first_gap))
acc <- acc[is.finite(acc$rel), ]
summ <- function(x) {
  data.frame(n_lines = nrow(x), km = sum(x$km),
             rel_median = stats::median(x$rel),
             abs_rel_median = stats::median(abs(x$rel)),
             abs_rel_p90 = unname(stats::quantile(abs(x$rel), 0.9)),
             share_under = mean(x$rel < 0), share_over = mean(x$rel > 0))
}
acc_out <- do.call(rbind, lapply(split(acc, list(acc$tier, acc$gap_class),
                                       drop = TRUE), function(x) {
  cbind(x[1, c("tier", "gap_class")], summ(x))
}))
acc_all <- do.call(rbind, lapply(split(acc, acc$tier), function(x) {
  cbind(data.frame(tier = x$tier[1], gap_class = "all"), summ(x))
}))
acc_out <- rbind(acc_all, acc_out)
acc_out <- acc_out[order(acc_out$tier, acc_out$gap_class), ]

# Masking one line at a time puts its neighbour next to it (same fundamental
# watershed, nearly the same value), but real gaps run tens of km. So, on a
# sample: the first valued line upstream at least --long-gap metres away on
# the same blue_line_key (what a fill across a long absent run returns), and
# the tributary tier, which never reads the line's own blue_line_key.
long_gap <- as.numeric(opt("long-gap", "10000"))
smp <- dbGetQuery(conn, sprintf(
  "SELECT c.linear_feature_id, c.length_metre, c.mad_m3s AS truth,
          c.mad_m3s_trib AS est_trib,
          (SELECT d2.mad_m3s
             FROM whse_basemapping.fwa_stream_networks_sp s1
             JOIN whse_basemapping.fwa_stream_networks_sp s2
               ON s2.blue_line_key = s1.blue_line_key
              AND s2.downstream_route_measure >= s1.upstream_route_measure + $1
             JOIN %s d2 ON d2.linear_feature_id = s2.linear_feature_id
            WHERE s1.linear_feature_id = c.linear_feature_id
              AND d2.mad_m3s IS NOT NULL
            ORDER BY s2.downstream_route_measure, s2.linear_feature_id
            LIMIT 1) AS est_long_up
     FROM %s c
    WHERE c.edge_type = 1250 AND c.mad_m3s IS NOT NULL",
  tbl, .lnk_discharge_candidates_sql(covered, "all",
                                     where = "s.linear_feature_id % 50 = 0")),
  params = list(long_gap))
message(nrow(smp), " sampled valued edge 1250 lines")
smp_acc <- function(tier, est) {
  ok <- !is.na(est) & smp$truth > 0
  x <- data.frame(tier = tier, gap_class = "sample",
                  km = smp$length_metre[ok] / 1000, truth = smp$truth[ok],
                  est = est[ok])
  x$rel <- (x$est - x$truth) / x$truth
  x
}
smp_l <- rbind(smp_acc(sprintf("upstream_beyond_%gm", long_gap),
                       smp$est_long_up),
               smp_acc("tributary_max", smp$est_trib))
acc_smp <- do.call(rbind, lapply(split(smp_l, smp_l$tier), function(x) {
  cbind(x[1, c("tier", "gap_class")], summ(x))
}))
write(rbind(acc_out, acc_smp), "accuracy.csv")
acc <- rbind(acc, smp_l)

th <- utils::read.csv(lnk_config(base)$files$parameters_habitat_thresholds$path)
mins <- rbind(
  data.frame(species_code = th$species_code, stage = "spawn",
             mad_min = th$spawn_mad_min),
  data.frame(species_code = th$species_code, stage = "rear",
             mad_min = th$rear_mad_min))
mins <- mins[!is.na(mins$mad_min), ]
crossings <- function(tr, i) {
  rule <- acc[acc$tier == tr, ]
  m <- mins$mad_min[i]
  data.frame(tier = tr, mins[i, ], n_lines = nrow(rule),
             n_true_in = sum(rule$truth >= m),
             n_lost = sum(rule$truth >= m & rule$est < m),
             n_gained = sum(rule$truth < m & rule$est >= m),
             km_true_in = sum(rule$km[rule$truth >= m]),
             km_lost = sum(rule$km[rule$truth >= m & rule$est < m]),
             km_gained = sum(rule$km[rule$truth < m & rule$est >= m]))
}
acc_min <- do.call(rbind, lapply(
  c("rule", sprintf("upstream_beyond_%gm", long_gap), "tributary_max"),
  function(tr) {
    do.call(rbind, lapply(seq_len(nrow(mins)), function(i) crossings(tr, i)))
  }))
write(acc_min, "accuracy_min.csv")

# -- reach: the NULL lines, by the tier that fills them --------------------------
# The tier comes from the shipping fill itself, over every covered WSG.
fill_all <- dbGetQuery(conn, sprintf(
  "SELECT f.linear_feature_id, f.mad_m3s_source FROM %s f
     JOIN whse_basemapping.fwa_stream_networks_sp s
       ON s.linear_feature_id = f.linear_feature_id
    WHERE s.edge_type = 1250",
  .lnk_discharge_sql(covered, fill = TRUE)))
nul <- cand[is.na(cand$mad_m3s), ]
nul$tier <- fill_all$mad_m3s_source[match(nul$linear_feature_id,
                                          fill_all$linear_feature_id)]
nul$tier[is.na(nul$tier)] <- "none"
nul$gap <- ifelse(nul$tier == "fill_upstream", nul$gap_up_m,
                  ifelse(nul$tier == "fill_downstream", nul$gap_dn_m, NA))
nul$gap_class <- as.character(gap_class(nul$gap))
# No gap for the tributary tier or an unfilled line; aggregate() would drop
# an NA group silently.
nul$gap_class[is.na(nul$gap_class)] <- ""
nul$state <- ifelse(nul$in_table, "row_null", "absent")
reach <- stats::aggregate(
  cbind(km = nul$length_metre / 1000, n_lines = 1),
  nul[c("state", "tier", "gap_class")], sum)
write(reach[order(reach$state, reach$tier, reach$gap_class), ], "reach.csv")

# Lines a fill cannot reach: is the whole blue_line_key without discharge?
none_blk <- unique(nul$blue_line_key[nul$tier == "none"])
message(length(none_blk), " blue_line_keys with an unfillable edge 1250 line")

# -- #300's cw-only bands: segments with no discharge, by fill tier ---------------
roles <- utils::read.csv(path_roles)
roles <- roles[roles$role == "held_out", ]
sch_base <- paste0(prefix, "_", base)
band <- do.call(rbind, lapply(unique(roles$species_code), function(sp) {
  sch_v <- paste0(prefix, "_", tolower(sp), "_mad")
  w <- roles$watershed_group_code[roles$species_code == sp]
  ok <- dbGetQuery(conn, "SELECT to_regclass($1) IS NOT NULL AS ok",
                   params = list(paste0(sch_v, ".streams_habitat_",
                                        tolower(sp))))$ok
  if (!ok) return(NULL)
  do.call(rbind, lapply(c("spawning", "rearing"), function(fl) {
    d <- dbGetQuery(conn, sprintf(
      "SELECT s.watershed_group_code, s.linear_feature_id, s.edge_type,
              s.length_metre / 1000 AS km
         FROM %1$s.streams s
         JOIN %1$s.streams_habitat_%3$s b
           ON b.id_segment = s.id_segment
          AND b.watershed_group_code = s.watershed_group_code
         LEFT JOIN %2$s.streams_habitat_%3$s m
           ON m.id_segment = s.id_segment
          AND m.watershed_group_code = s.watershed_group_code
         LEFT JOIN %5$s q ON q.linear_feature_id = s.linear_feature_id
        WHERE s.watershed_group_code = ANY($1)
          AND coalesce(b.%4$s, false) AND NOT coalesce(m.%4$s, false)
          AND q.mad_m3s IS NULL",
      sch_base, sch_v, tolower(sp), fl, tbl),
      params = list(paste0("{", paste(w, collapse = ","), "}")))
    if (nrow(d) == 0L) return(NULL)
    f <- dbGetQuery(conn, sprintf(
      "SELECT linear_feature_id, mad_m3s, mad_m3s_source FROM %s f",
      .lnk_discharge_sql(w, fill = TRUE)))
    d <- merge(d, f, by = "linear_feature_id", all.x = TRUE)
    stage <- if (identical(fl, "spawning")) "spawn" else "rear"
    m <- mins$mad_min[mins$species_code == sp & mins$stage == stage]
    d$tier <- ifelse(is.na(d$mad_m3s_source), "none", d$mad_m3s_source)
    d$clears_min <- if (length(m) == 1L) d$mad_m3s >= m else NA
    d$is_1250 <- d$edge_type == 1250
    a <- stats::aggregate(cbind(km = d$km, n_segments = 1),
                          d[c("is_1250", "tier")], sum)
    a2 <- stats::aggregate(cbind(km_clears_min = d$km * (d$clears_min %in% TRUE)),
                           d[c("is_1250", "tier")], sum)
    cbind(data.frame(species_code = sp, flag = fl),
          merge(a, a2, by = c("is_1250", "tier")))
  }))
}))
if (!is.null(band)) write(band, "band_reach.csv")

# -- stamp -------------------------------------------------------------------------
fresh_sha <- .lnk_pkg_git_sha("fresh")
link_dirty <- length(system(paste(
  "git status --porcelain -- R data-raw/discharge_fill_count.R"),
  intern = TRUE)) > 0L
writeLines(c(
  sprintf("date: %s", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
  sprintf("link: %s @ %s%s", utils::packageVersion("link"),
          system("git rev-parse --short HEAD", intern = TRUE),
          if (link_dirty) " (dirty)" else ""),
  sprintf("fresh installed: %s @ %s", utils::packageVersion("fresh"),
          if (is.na(fresh_sha)) "no recorded sha" else fresh_sha),
  "db: docker fwapg localhost:5432",
  sprintf("discharge rows: %s (%s with mad_m3s); %d covered WSGs",
          dbGetQuery(conn, sprintf("SELECT count(*) FROM %s", tbl))[[1]],
          dbGetQuery(conn, sprintf("SELECT count(mad_m3s) FROM %s", tbl))[[1]],
          length(covered)),
  sprintf("bands: %s_* schemas, held-out roles from %s; MAD minima from %s",
          prefix, path_roles, base)),
  file.path(dir_out, "stamp.txt"))

dbDisconnect(conn)
message("wrote ", dir_out)
