#!/usr/bin/env Rscript
# access_verify_349.R — compare the link#349 verification build (scratch
# schema fresh_349) with the province-wide build it replaces (fresh_default),
# group by group.
#
# The build: data-raw/logs/access_disagree_349/verify_build_349.sh, which seeds
# fresh_349 with fresh_default's barriers and overrides, builds the groups under
# `default` with the habitat gate off, measures (before/), recomputes (which
# settles), and measures again (after/).
#
# Writes to data-raw/logs/access_disagree_349/after/:
#   access_transitions.csv  per group x species: segments open in fresh_default
#                           (access_<sp> 1/2) and closed in fresh_349, and the
#                           reverse, joined on (blue_line_key,
#                           downstream_route_measure). open -> closed must be 0:
#                           counting lifts over every group's observations can
#                           only add lifts (the mechanism-C regression check).
#   rollup.csv              lnk_rollup_wsg() on both schemas, per group x species
#   gate.csv                the recompute's habitat_gate_* columns per group
#   bcfp_dunc_bt.csv        DUNC BT spawning / rearing km: fresh_default,
#                           fresh_349, and bcfishpass (fresh.streams_vw_bcfp,
#                           codes 1/2)
#
# Loads the source tree (pkgload::load_all), never the installed link.
#
# Usage: Rscript data-raw/access_verify_349.R [WSG ...]   (default UPCE CARP DUNC)

suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
wsgs <- toupper(commandArgs(trailingOnly = TRUE))
if (!length(wsgs)) wsgs <- c("UPCE", "CARP", "DUNC")
stopifnot(all(grepl("^[A-Z]{3,5}$", wsgs)))
out <- "data-raw/logs/access_disagree_349/after"
dir.create(out, showWarnings = FALSE, recursive = TRUE)

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
q <- function(sql) DBI::dbGetQuery(conn, sql)
cfg <- lnk_config("default")
loaded <- lnk_load_overrides(cfg)

trans <- list(); roll <- list()
for (w in wsgs) {
  sp <- tolower(lnk_pipeline_species(cfg, loaded, w))
  wl <- DBI::dbQuoteLiteral(conn, w)
  for (s in sp) {
    acc <- paste0("access_", s)
    t <- q(sprintf(
      "WITH o AS (SELECT s.blue_line_key, s.downstream_route_measure, s.length_metre, a.%1$s AS v
                    FROM fresh_default.streams s
                    JOIN fresh_default.streams_access a USING (id_segment, watershed_group_code)
                   WHERE s.watershed_group_code = %2$s),
            n AS (SELECT s.blue_line_key, s.downstream_route_measure, a.%1$s AS v
                    FROM fresh_349.streams s
                    JOIN fresh_349.streams_access a USING (id_segment, watershed_group_code)
                   WHERE s.watershed_group_code = %2$s)
       SELECT count(*) AS n_joined,
              count(*) FILTER (WHERE o.v IN (1, 2) AND n.v = 0) AS open_to_closed,
              count(*) FILTER (WHERE o.v = 0 AND n.v IN (1, 2)) AS closed_to_open,
              round((sum(o.length_metre) FILTER (WHERE o.v = 0 AND n.v IN (1, 2)) / 1000)::numeric, 3)
                AS closed_to_open_km,
              (SELECT count(*) FROM o) AS n_default, (SELECT count(*) FROM n) AS n_349
       FROM o JOIN n USING (blue_line_key, downstream_route_measure)", acc, wl))
    trans[[paste(w, s)]] <- cbind(watershed_group_code = w, species = toupper(s), t)
  }
  for (sch in c("fresh_default", "fresh_349")) {
    r <- lnk_rollup_wsg(conn, aoi = w, species = toupper(sp), schema = sch)
    roll[[paste(w, sch)]] <- cbind(schema = sch, r)
  }
}
trans <- do.call(rbind, trans)
roll <- do.call(rbind, roll)
for (n in names(trans)) if (inherits(trans[[n]], "integer64")) trans[[n]] <- as.numeric(trans[[n]])
utils::write.csv(trans, file.path(out, "access_transitions.csv"), row.names = FALSE)
utils::write.csv(roll, file.path(out, "rollup.csv"), row.names = FALSE)

gate <- q(sprintf(
  "SELECT 'log_recompute' AS log_table, watershed_group_code, date_end, link_sha, link_dirty,
          habitat_gate_n, habitat_gate_km, habitat_gate_lifted, habitat_gate_species::text
     FROM fresh_349.log_recompute WHERE watershed_group_code IN (%s)
   UNION ALL
   SELECT 'log', watershed_group_code, date_end, link_sha, link_dirty,
          habitat_gate_n, habitat_gate_km, habitat_gate_lifted, habitat_gate_species::text
     FROM fresh_349.log WHERE watershed_group_code IN (%s)
   ORDER BY 1, 2, 3", paste(DBI::dbQuoteLiteral(conn, wsgs), collapse = ", "),
  paste(DBI::dbQuoteLiteral(conn, wsgs), collapse = ", ")))
utils::write.csv(gate, file.path(out, "gate.csv"), row.names = FALSE)

if ("DUNC" %in% wsgs) {
  link_km <- function(sch) q(sprintf(
    "SELECT %s AS source,
            round((sum(s.length_metre) FILTER (WHERE h.spawning) / 1000)::numeric, 2) AS spawning_km,
            round((sum(s.length_metre) FILTER (WHERE h.rearing) / 1000)::numeric, 2) AS rearing_km
       FROM %s.streams_habitat_bt h
       JOIN %s.streams s USING (id_segment, watershed_group_code)
      WHERE h.watershed_group_code = 'DUNC'", DBI::dbQuoteLiteral(conn, sch), sch, sch))
  bcfp <- q("SELECT 'bcfishpass' AS source,
                    round((sum(length_metre) FILTER (WHERE spawning_bt IN (1, 2)) / 1000)::numeric, 2) AS spawning_km,
                    round((sum(length_metre) FILTER (WHERE rearing_bt IN (1, 2)) / 1000)::numeric, 2) AS rearing_km
               FROM fresh.streams_vw_bcfp WHERE watershed_group_code = 'DUNC'")
  utils::write.csv(rbind(link_km("fresh_default"), link_km("fresh_349"), bcfp),
                   file.path(out, "bcfp_dunc_bt.csv"), row.names = FALSE)
}
print(trans); print(gate)
DBI::dbDisconnect(conn)
