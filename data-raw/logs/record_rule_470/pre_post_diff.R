# What the record rule moved (link#470): BEFORE (zz470_<config>_pre, main at
# 2da2db35) against AFTER (zz470_<config>_post, the Phase 2 commit 09e8339d),
# per config, group and species, on measure-overlap pieces per blue_line_key,
# never on id_segment.
#
#   Rscript data-raw/logs/record_rule_470/pre_post_diff.R
#
# Pieces under 1 cm are dropped: a segment's upstream measure can overshoot the
# next one's start by up to 3.93 mm within one side (FWA).
#
# The two record sets are rebuilt here, independently of the builds' tables
# (the working tables were dropped): BEFORE's rule is each present species'
# own code plus CCT, ACT and CT/RB where CT is present, any date; AFTER's is
# .lnk_observation_species_map() at this checkout. D_sp is the records that
# count as sp under one rule and not the other.
#
# A piece whose access code changed is explained when:
#   1 <-> 2  a record of D_sp is upstream of the piece's AFTER segment start
#            (the walk's own test, fwa_upstream(..., false, 1));
#   0 <-> 1/2  the group's lifts for sp differ (barrier_overrides, BEFORE
#            against AFTER), or a record of D_sp is upstream (its 2 rides on
#            the same lift change);
#   any      the piece is under 2 m and a record of D (any species) sits on
#            its line within 2 m: a cut at a record that one rule counts and
#            the other does not moved, and a barrier break within 1 m of it
#            then applies or not (RUNBOOK §2, a break within 1 m of an
#            existing end is skipped), so the strip between changes segment.
# Anything else is unexplained and printed. Writes segments.csv, lifts.csv,
# transitions.csv and unexplained.csv beside this script.
pkgload::load_all(quiet = TRUE)
# nolint start: line_length_linter
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
out <- "data-raw/logs/record_rule_470"
q <- function(sql) DBI::dbGetQuery(conn, sql)
ex <- function(sql) invisible(DBI::dbExecute(conn, sql))
groups <- list(default = c("LSKE", "KLUM", "SQAM", "HOMA", "VICT", "MFRA", "UFRT", "FINA"),
               bcfishpass = c("BULK", "PARS", "SQAM"))
lit <- function(x) paste(vapply(x, .lnk_quote_literal, character(1)), collapse = ", ")

record_sets <- function(config) {
  cfg <- lnk_config(config)
  ld <- suppressWarnings(lnk_load_overrides(cfg))
  pres <- ld$wsg_species_presence
  post <- .lnk_observation_species_map(cfg, ld, pres$watershed_group_code)
  pre <- do.call(rbind, lapply(seq_len(nrow(pres)), function(i) {
    sp <- toupper(.lnk_wsg_species_present(pres[i, ]))
    if (!length(sp)) return(NULL)
    obs <- c(sp, if ("CT" %in% sp) c("CCT", "ACT", "CT/RB"))
    data.frame(watershed_group_code = pres$watershed_group_code[i],
               species_obs = obs,
               species_code = ifelse(obs %in% c("CCT", "ACT", "CT/RB"), "CT", obs),
               date_min = as.Date(NA), year_max = NA_integer_)
  }))
  keys <- .lnk_observation_exclusion_keys(ld)
  excl <- if (length(keys)) sprintf("AND o.observation_key NOT IN (%s)", lit(keys)) else ""
  for (side in c("pre", "post")) {
    m <- if (side == "pre") pre else post
    .lnk_observation_table_build(conn, sprintf("pg_temp.rec_%s", side),
                                 "bcfishobs.observations", m, excl_filter = excl)
  }
  ex("DROP TABLE IF EXISTS pg_temp.rec_diff")
  ex("CREATE TEMP TABLE rec_diff AS
      SELECT species_code, observation_key, blue_line_key, downstream_route_measure,
             wscode, localcode, 'post_only' AS side FROM (
        SELECT species_code, observation_key FROM pg_temp.rec_post
        EXCEPT SELECT species_code, observation_key FROM pg_temp.rec_pre) d
      JOIN (SELECT DISTINCT observation_key, blue_line_key, downstream_route_measure,
                   wscode, localcode FROM bcfishobs.observations) o USING (observation_key)
      UNION ALL
      SELECT species_code, observation_key, blue_line_key, downstream_route_measure,
             wscode, localcode, 'pre_only' FROM (
        SELECT species_code, observation_key FROM pg_temp.rec_pre
        EXCEPT SELECT species_code, observation_key FROM pg_temp.rec_post) d
      JOIN (SELECT DISTINCT observation_key, blue_line_key, downstream_route_measure,
                   wscode, localcode FROM bcfishobs.observations) o USING (observation_key)")
  ex("CREATE INDEX ON pg_temp.rec_diff USING gist (wscode)")
  ex("ANALYZE pg_temp.rec_diff")
  q("SELECT side, species_code, count(*)::int AS records FROM pg_temp.rec_diff
     GROUP BY 1, 2 ORDER BY 1, 2")
}

seg <- list(); lifts <- list(); trans <- list(); unexpl <- list(); recs <- list()
for (config in names(groups)) {
  pre_s <- sprintf("zz470_%s_pre", config); post_s <- sprintf("zz470_%s_post", config)
  rd <- record_sets(config); rd$config <- config; recs[[config]] <- rd
  acc <- intersect(
    q(sprintf("SELECT column_name FROM information_schema.columns WHERE table_schema = '%s' AND table_name = 'streams_access' AND column_name LIKE 'access_%%'", pre_s))$column_name,
    q(sprintf("SELECT column_name FROM information_schema.columns WHERE table_schema = '%s' AND table_name = 'streams_access' AND column_name LIKE 'access_%%'", post_s))$column_name)
  for (w in groups[[config]]) {
    seg[[length(seg) + 1]] <- data.frame(config = config, wsg = w,
      q(sprintf("SELECT (SELECT count(*) FROM %s.streams WHERE watershed_group_code = '%s')::int AS segments_pre,
                        (SELECT count(*) FROM %s.streams WHERE watershed_group_code = '%s')::int AS segments_post",
                pre_s, w, post_s, w)))
    lifts[[length(lifts) + 1]] <- data.frame(config = config, wsg = w, q(sprintf(
      "SELECT coalesce(a.species_code, b.species_code) AS species_code,
              count(*) FILTER (WHERE a.species_code IS NOT NULL)::int AS lifts_pre,
              count(*) FILTER (WHERE b.species_code IS NOT NULL)::int AS lifts_post,
              count(*) FILTER (WHERE b.species_code IS NULL)::int AS lost,
              count(*) FILTER (WHERE a.species_code IS NULL)::int AS gained
       FROM (SELECT * FROM %s.barrier_overrides WHERE watershed_group_code = '%s') a
       FULL JOIN (SELECT * FROM %s.barrier_overrides WHERE watershed_group_code = '%s') b
         USING (blue_line_key, downstream_route_measure, species_code)
       GROUP BY 1 ORDER BY 1", pre_s, w, post_s, w)))
    for (col in acc) {
      sp <- toupper(sub("^access_", "", col))
      ex("DROP TABLE IF EXISTS pg_temp.pieces")
      ex(sprintf(
        "CREATE TEMP TABLE pieces AS
         WITH a AS (SELECT s.blue_line_key, s.downstream_route_measure dm, s.upstream_route_measure um,
                           x.%3$s AS acc
                      FROM %1$s.streams s JOIN %1$s.streams_access x USING (id_segment, watershed_group_code)
                     WHERE s.watershed_group_code = '%4$s'),
              b AS (SELECT s.blue_line_key, s.downstream_route_measure dm, s.upstream_route_measure um,
                           s.wscode_ltree, s.localcode_ltree, x.%3$s AS acc
                      FROM %2$s.streams s JOIN %2$s.streams_access x USING (id_segment, watershed_group_code)
                     WHERE s.watershed_group_code = '%4$s')
         SELECT b.blue_line_key, b.dm AS post_start, b.wscode_ltree, b.localcode_ltree,
                a.acc AS pre, b.acc AS post,
                least(a.um, b.um) - greatest(a.dm, b.dm) AS len
           FROM a JOIN b ON a.blue_line_key = b.blue_line_key
            AND a.dm < b.um AND b.dm < a.um
          WHERE least(a.um, b.um) - greatest(a.dm, b.dm) > 0.01",
        pre_s, post_s, col, w))
      t <- q("SELECT pre, post, round(sum(len)::numeric / 1000, 3)::float8 AS km
              FROM pg_temp.pieces GROUP BY 1, 2 ORDER BY 1, 2")
      if (!nrow(t)) next
      trans[[length(trans) + 1]] <- data.frame(config = config, wsg = w, species_code = sp, t)
      lift_moved <- nrow(subset(lifts[[length(lifts)]], species_code == sp & (lost > 0 | gained > 0))) > 0
      u <- q(sprintf(
        "SELECT pre, post, count(*)::int AS pieces,
                round(sum(len)::numeric / 1000, 3)::float8 AS km
           FROM pg_temp.pieces p
          WHERE pre IS DISTINCT FROM post
            AND NOT EXISTS (
              SELECT 1 FROM pg_temp.rec_diff d
               WHERE d.species_code = '%s'
                 AND whse_basemapping.fwa_upstream(
                       p.blue_line_key, p.post_start, p.wscode_ltree, p.localcode_ltree,
                       d.blue_line_key, d.downstream_route_measure, d.wscode, d.localcode,
                       false, 1))
            AND NOT (%s AND (pre = 0 OR post = 0))
            AND NOT (len < 2 AND EXISTS (
              SELECT 1 FROM pg_temp.rec_diff d
               WHERE d.blue_line_key = p.blue_line_key
                 AND abs(d.downstream_route_measure - p.post_start) < 2))
          GROUP BY 1, 2", sp, if (lift_moved) "TRUE" else "FALSE"))
      if (nrow(u)) unexpl[[length(unexpl) + 1]] <- data.frame(config = config, wsg = w, species_code = sp, u)
    }
  }
}
seg <- do.call(rbind, seg); lifts <- do.call(rbind, lifts)
trans <- do.call(rbind, trans); recs <- do.call(rbind, recs)
unexpl <- if (length(unexpl)) do.call(rbind, unexpl) else
  data.frame(config = character(0), wsg = character(0), species_code = character(0),
             pre = integer(0), post = integer(0), pieces = integer(0), km = numeric(0))
utils::write.csv(seg, file.path(out, "segments.csv"), row.names = FALSE)
utils::write.csv(lifts, file.path(out, "lifts.csv"), row.names = FALSE)
utils::write.csv(trans, file.path(out, "transitions.csv"), row.names = FALSE)
utils::write.csv(recs, file.path(out, "records_diff.csv"), row.names = FALSE)
utils::write.csv(unexpl, file.path(out, "unexplained.csv"), row.names = FALSE)
cat("\n== segments\n"); print(seg)
cat("\n== lifts that moved\n"); print(lifts[lifts$lost > 0 | lifts$gained > 0, ])
cat("\n== access km that moved\n"); print(trans[trans$pre != trans$post | is.na(trans$pre) != is.na(trans$post), ])
cat("\n== records counted under one rule only (province-wide)\n"); print(recs)
cat("\n== unexplained\n"); print(unexpl)
cat(sprintf("\nunexplained pieces: %d\n", sum(unexpl$pieces)))
# nolint end
