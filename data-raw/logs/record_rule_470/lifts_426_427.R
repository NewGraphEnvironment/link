# Lifts under #426's date comparison and #427's salmon thresholds (link#470).
#
#   Rscript data-raw/logs/record_rule_470/lifts_426_427.R
#
# Runs lnk_barrier_overrides() at this checkout's code over each group's
# persisted natural barriers (FALLS, GRADIENT and, for bcfishpass,
# SUBSURFACE_FLOW rows of <schema>.barriers: the positions a build's
# natural_barriers holds) and the province's fish records built under the
# record rule (.lnk_pipeline_prep_obs_province(), as prepare builds them),
# once per variant, into scratch schema zz470_lifts. Nothing persisted is
# written.
#
# #426: the bcfishpass bundle with its salmon and steelhead floors at
#   1990-01-01 (>=, link before #470) and 1990-01-02 (> 1990-01-01, as
#   bcfishpass), on the parity groups BULK, PARS, ADMS, BABL and ELKR, and on
#   CHWK, HARR, LFRA, LSKE and KLUM, which hold bcfishpass salmon lifts and
#   records dated 1990-01-01 (fresh.barriers).
# #427: the default bundle with CH, CM, CO, PK, SK, ST, GR and KO lift
#   thresholds 5 (shipped), 2 and 1, on BULK, LSKE, SQAM, MORR, HARR
#   (fresh_default.barriers). For each variant: lifts per species, the lifts
#   added over 5, how many of those rest on a single record, and an upper
#   bound on the km they open: the length of the group's segments upstream of
#   a newly lifted barrier that fresh_default.streams_access reads as blocked
#   for the species (access_<sp> = 0). Other barriers above a lift still block
#   some of it, so the true gain is lower. KO has no build to read
#   (paused, #432): its km are NA.
#
# Writes lifts_426.csv, lifts_427.csv and lifts_stamp.txt beside this script.
pkgload::load_all(quiet = TRUE)
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
out <- "data-raw/logs/record_rule_470"
s <- "zz470_lifts"
ex <- function(sql) invisible(DBI::dbExecute(conn, sql))
q <- function(sql) DBI::dbGetQuery(conn, sql)
ex(sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
ex(sprintf("CREATE SCHEMA %s", s))

obs_province <- function(cfg, loaded) {
  keys <- .lnk_observation_exclusion_keys(loaded)
  excl <- if (length(keys)) sprintf("AND o.observation_key NOT IN (%s)",
    paste(vapply(keys, .lnk_quote_literal, character(1)), collapse = ", ")) else ""
  map <- .lnk_observation_species_map(cfg, loaded,
                                      loaded$wsg_species_presence$watershed_group_code)
  .lnk_pipeline_prep_obs_province(conn, s, "bcfishobs.observations", map, excl)
}

natural <- function(src, w, sources) {
  ex(sprintf("DROP TABLE IF EXISTS %s.nb", s))
  ex(sprintf(
    "CREATE TABLE %s.nb AS
     SELECT DISTINCT blue_line_key, downstream_route_measure, wscode_ltree,
            localcode_ltree
     FROM %s.barriers
     WHERE watershed_group_code = %s AND barrier_source IN (%s)",
    s, src, .lnk_quote_literal(w),
    paste(sprintf("'%s'", sources), collapse = ", ")))
}

lifts <- function(params, tag) {
  lnk_barrier_overrides(conn, barriers = paste0(s, ".nb"),
                        observations = paste0(s, ".observations_province"),
                        params = params, to = sprintf("%s.bo_%s", s, tag),
                        evidence = sprintf("%s.ev_%s", s, tag), verbose = FALSE)
}

# -- #426 ---------------------------------------------------------------------
cfg <- lnk_config("bcfishpass")
ld <- suppressWarnings(lnk_load_overrides(cfg))
obs_province(cfg, ld)
pf_gt <- ld$parameters_fresh
pf_ge <- pf_gt
pf_ge$observation_date_min[pf_ge$observation_date_min == "1990-01-02"] <- "1990-01-01"
stopifnot(sum(pf_ge$observation_date_min == "1990-01-01", na.rm = TRUE) == 6L)
r426 <- do.call(rbind, lapply(c("BULK", "PARS", "ADMS", "BABL", "ELKR",
                                "CHWK", "HARR", "LFRA", "LSKE", "KLUM"), function(w) {
  natural("fresh", w, c("FALLS", "GRADIENT", "SUBSURFACE_FLOW"))
  lifts(pf_ge, "ge"); lifts(pf_gt, "gt")
  q(sprintf(
    "SELECT %s AS wsg, coalesce(a.species_code, b.species_code) AS species_code,
            count(a.*) FILTER (WHERE a.species_code IS NOT NULL)::int AS lifts_ge,
            count(b.*) FILTER (WHERE b.species_code IS NOT NULL)::int AS lifts_gt,
            count(*) FILTER (WHERE b.species_code IS NULL)::int AS lost_with_gt,
            count(*) FILTER (WHERE a.species_code IS NULL)::int AS gained_with_gt
     FROM %s.bo_ge a
     FULL JOIN %s.bo_gt b USING (blue_line_key, downstream_route_measure, species_code)
     GROUP BY 2 ORDER BY 2", .lnk_quote_literal(w), s, s))
}))
utils::write.csv(r426, file.path(out, "lifts_426.csv"), row.names = FALSE)
print(r426)

# -- #427 ---------------------------------------------------------------------
cfg <- lnk_config("default")
ld <- suppressWarnings(lnk_load_overrides(cfg))
obs_province(cfg, ld)
sal <- c("CH", "CM", "CO", "PK", "SK", "ST", "GR", "KO")
pf5 <- ld$parameters_fresh
variant <- function(t) { p <- pf5; p$observation_threshold[p$species_code %in% sal] <- t; p }
acc_cols <- q("SELECT column_name FROM information_schema.columns
               WHERE table_schema = 'fresh_default' AND table_name = 'streams_access'")$column_name
r427 <- do.call(rbind, lapply(c("BULK", "LSKE", "SQAM", "MORR", "HARR"), function(w) {
  natural("fresh_default", w, c("FALLS", "GRADIENT"))
  for (t in c(5L, 2L, 1L)) lifts(variant(t), paste0("t", t))
  do.call(rbind, lapply(sal, function(sp) {
    n <- function(t) q(sprintf("SELECT count(*)::int n FROM %s.bo_t%d WHERE species_code = '%s'",
                               s, t, sp))$n
    do.call(rbind, lapply(c(2L, 1L), function(t) {
      new <- sprintf(
        "SELECT b.blue_line_key, b.downstream_route_measure FROM %1$s.bo_t%2$d b
         WHERE b.species_code = '%3$s' AND NOT EXISTS (
           SELECT 1 FROM %1$s.bo_t5 f WHERE f.species_code = '%3$s'
             AND f.blue_line_key = b.blue_line_key
             AND f.downstream_route_measure = b.downstream_route_measure)",
        s, t, sp)
      one <- q(sprintf(
        "SELECT count(*)::int n FROM (
           SELECT e.blue_line_key, e.downstream_route_measure
           FROM %s.ev_t%d e JOIN (%s) n USING (blue_line_key, downstream_route_measure)
           WHERE e.species_code = '%s' AND e.evidence = 'observation'
           GROUP BY 1, 2 HAVING count(DISTINCT e.evidence_key) = 1) x",
        s, t, new, sp))$n
      col <- paste0("access_", tolower(sp))
      km <- if (col %in% acc_cols) q(sprintf(
        "SELECT coalesce(sum(st.length_metre), 0) / 1000 AS km
         FROM fresh_default.streams st
         JOIN fresh_default.streams_access a USING (id_segment, watershed_group_code)
         WHERE st.watershed_group_code = %1$s AND a.%2$s = 0
           AND EXISTS (
             SELECT 1 FROM (%3$s) n
             JOIN %4$s.nb b USING (blue_line_key, downstream_route_measure)
             WHERE whse_basemapping.fwa_upstream(
               b.blue_line_key, b.downstream_route_measure, b.wscode_ltree,
               b.localcode_ltree, st.blue_line_key, st.downstream_route_measure,
               st.wscode_ltree, st.localcode_ltree))",
        .lnk_quote_literal(w), col, new, s))$km else NA_real_
      data.frame(wsg = w, species_code = sp, threshold = t, lifts_t5 = n(5L),
                 lifts = n(t), added = n(t) - n(5L), added_one_record = one,
                 blocked_km_above_added_max = round(km, 1))
    }))
  }))
}))
utils::write.csv(r427, file.path(out, "lifts_427.csv"), row.names = FALSE)
print(r427[r427$added > 0, ])

writeLines(c(
  sprintf("date: %s", format(Sys.time(), "%Y-%m-%d %H:%M UTC", tz = "UTC")),
  sprintf("link: %s @ %s", utils::packageVersion("link"),
          system("git rev-parse --short HEAD", intern = TRUE)),
  sprintf("bcfishobs.observations: %d rows",
          q("SELECT count(*)::int n FROM bcfishobs.observations")$n),
  sprintf("barriers read: fresh (bcfishpass build) and fresh_default (link %s)",
          paste(q("SELECT DISTINCT link_version FROM fresh_default.log
                    WHERE date_end IS NOT NULL ORDER BY 1 DESC LIMIT 1")$link_version)),
  "db: docker fwapg localhost:5432"), file.path(out, "lifts_stamp.txt"))
ex(sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
