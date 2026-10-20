#!/usr/bin/env Rscript
# access_disagree_349.R — where `streams_habitat_<sp>.accessible` (fresh's flag,
# which gates spawning and rearing at classify time) and
# `streams_access.access_<sp>` (link's, settled province-wide) disagree, split
# by mechanism (link#349).
#
# Forward direction (`accessible` TRUE, `access_<sp>` = 0), one class per row,
# first match wins:
#   A_rounding         a species-blocking natural barrier on the same line within
#                      1 m, BELOW the segment start, whose metre-rounded break
#                      lands above it (fresh blocks on `b.drm <= s.drm`)
#   A_prime_ltree      the same, with the barrier AT or ABOVE the start (0-5 mm):
#                      link blocks by the barrier's ltree, fresh's exact `<=` never
#   A_other            a blocking barrier within 1 m that is neither of the above
#   B_cross_group      the group's outlet has an un-lifted, species-blocking
#                      natural barrier downstream of it in another group, which
#                      fresh's AOI-filtered breaks table cannot see
#   residual           none of the above (by group in residual_groups.csv)
# Class B's barriers are un-lifted partly because observations are counted only
# inside the group that holds the barrier (mechanism C): groups_blocked.csv
# carries the upstream observation counts both ways.
#
# Reverse direction (`accessible` FALSE, `access_<sp>` > 0):
#   R_override_scope   a natural barrier in the group, downstream of the
#                      segment, lifted for <sp> only by ANOTHER group's override
#                      row (link's view reads every group's; fresh its own)
#   R_near_1m          a species-blocking natural barrier on the same line within
#                      1 m (fresh's `<=` blocks it, link's 1 m tolerance does not)
#   R_other            none of the above
#
# Writes to --out (default data-raw/logs/access_disagree_349):
#   classes.csv        species x direction x class: segments, km, spawning,
#                      rearing, lake_rearing, wetland_rearing segments
#   groups_blocked.csv species x group at >= 99 % forward disagreement: each
#                      blocking barrier downstream of the outlet, observations
#                      upstream (province-wide by each record's own group's
#                      presence, and inside the holding groups), km at stake
#   residual_groups.csv  the residual class by species x group
#   side_effects.csv   per species: rows `access_<sp>` = 0 with spawning /
#                      rearing that user_habitat_classification sets (what the
#                      settle exempts); lake polygons whose surviving lake_rearing
#                      would lose every connected spawning segment; the #351
#                      check (`-9` rows, disagreeing rows in absent groups)
#   summary.md         environment stamp + the tables
#
# Asserts each species' forward classes sum to its forward total.
#
# Loads the source tree (pkgload::load_all), never the installed link.
#
# Usage: Rscript data-raw/access_disagree_349.R [--schema=fresh_default]
#          [--config=default] [--wsgs=DUNC,CARP] [--out=<dir>]

suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
suppressPackageStartupMessages(library(DBI))

arg <- function(name, default) {
  a <- commandArgs(trailingOnly = TRUE)
  hit <- grep(paste0("^--", name, "="), a, value = TRUE)
  if (length(hit)) sub(paste0("^--", name, "="), "", hit[1]) else default
}
schema <- arg("schema", "fresh_default")
config <- arg("config", "default")
out    <- arg("out", "data-raw/logs/access_disagree_349")
wsgs   <- toupper(strsplit(arg("wsgs", ""), ",")[[1]])
wsgs   <- wsgs[nzchar(wsgs)]
stopifnot(grepl("^[a-z_][a-z0-9_]*$", schema), all(grepl("^[A-Z]{3,5}$", wsgs)))
dir.create(out, showWarnings = FALSE, recursive = TRUE)

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
q <- function(sql) DBI::dbGetQuery(conn, sql)
x <- function(sql) invisible(DBI::dbExecute(conn, sql))
lit <- function(v) paste(DBI::dbQuoteLiteral(conn, v), collapse = ", ")
t_start <- Sys.time()

cfg    <- lnk_config(config)
loaded <- lnk_load_overrides(cfg)
params <- loaded$parameters_fresh

# Which groups to read: --wsgs, else every group in <schema>.streams_access.
wsg_all <- q(sprintf("SELECT DISTINCT watershed_group_code AS w FROM %s.streams_access",
                     schema))$w
if (length(wsgs)) {
  stopifnot(all(wsgs %in% wsg_all))
  wsg_all <- wsgs
}
wsg_filter <- function(alias) {
  if (length(wsgs)) sprintf("AND %s.watershed_group_code IN (%s)", alias, lit(wsgs)) else ""
}

# Species: every streams_habitat_<sp> table with an access_<sp> column.
hab_tabs <- q(sprintf("SELECT table_name FROM information_schema.tables
                       WHERE table_schema = %s AND table_name ~ '^streams_habitat_[a-z]+$'
                         AND table_type = 'BASE TABLE'", lit(schema)))$table_name
acc_cols <- q(sprintf("SELECT column_name FROM information_schema.columns
                       WHERE table_schema = %s AND table_name = 'streams_access'
                         AND column_name ~ '^access_'", lit(schema)))$column_name
species <- sort(intersect(sub("^streams_habitat_", "", hab_tabs), sub("^access_", "", acc_cols)))

# ---- shared scratch: presence (long), observations with ltree indexes, UHC ----
pres <- loaded$wsg_species_presence
pres_long <- do.call(rbind, lapply(seq_len(nrow(pres)), function(i) {
  sp <- .lnk_wsg_species_present(pres[i, ])
  if ("CT" %in% sp) sp <- c(sp, "CCT", "ACT", "CT/RB")
  if (!length(sp)) return(NULL)
  data.frame(watershed_group_code = pres$watershed_group_code[i], species_code = sp)
}))
DBI::dbWriteTable(conn, "ad_presence", pres_long, temporary = TRUE, overwrite = TRUE)

excl <- loaded$observation_exclusions
excl_keys <- if (!is.null(excl)) {
  excl$observation_key[excl$data_error %in% c(TRUE, "t") | excl$release_exclude %in% c(TRUE, "t")]
} else character(0)
DBI::dbWriteTable(conn, "ad_excl", data.frame(observation_key = as.character(excl_keys)),
                  temporary = TRUE, overwrite = TRUE)
x("CREATE TEMP TABLE ad_obs AS
   SELECT o.observation_key, o.species_code, o.watershed_group_code, o.observation_date,
          o.blue_line_key, o.downstream_route_measure, o.wscode, o.localcode,
          EXISTS (SELECT 1 FROM ad_presence p
                   WHERE p.watershed_group_code = o.watershed_group_code
                     AND p.species_code = o.species_code) AS present_own_group
   FROM bcfishobs.observations o
   WHERE NOT EXISTS (SELECT 1 FROM ad_excl e WHERE e.observation_key = o.observation_key::text)")
x("CREATE INDEX ON ad_obs USING gist (wscode)")
x("CREATE INDEX ON ad_obs USING gist (localcode)")
x("ANALYZE ad_obs")

uhc <- as.data.frame(loaded$user_habitat_classification)
uhc <- data.frame(
  species_code = uhc$species_code, blue_line_key = as.integer(uhc$blue_line_key),
  downstream_route_measure = as.numeric(uhc$downstream_route_measure),
  upstream_route_measure = as.numeric(uhc$upstream_route_measure),
  spawning = tolower(trimws(as.character(uhc$spawning))) %in% c("1", "t", "true"),
  rearing = tolower(trimws(as.character(uhc$rearing))) %in% c("1", "t", "true"))
DBI::dbWriteTable(conn, "ad_uhc", uhc, temporary = TRUE, overwrite = TRUE)
x("CREATE INDEX ON ad_uhc (blue_line_key)")

outlets <- fresh::frs_wsg_outlets()
outlets <- outlets[outlets$watershed_group_code %in% wsg_all, , drop = FALSE]
outlet_values <- paste(sprintf("(%s, %s, %s::double precision, %s::ltree, %s::ltree)",
  DBI::dbQuoteLiteral(conn, outlets$watershed_group_code), outlets$blue_line_key,
  outlets$downstream_route_measure, DBI::dbQuoteLiteral(conn, outlets$wscode_ltree),
  DBI::dbQuoteLiteral(conn, outlets$localcode_ltree)), collapse = ",\n")

natural <- "('GRADIENT', 'FALLS', 'SUBSURFACE_FLOW')"
flag_sums <- "count(*) AS n_segments, round((sum(length_metre) / 1000)::numeric, 3) AS km,
  count(*) FILTER (WHERE spawning) AS n_spawning,
  count(*) FILTER (WHERE rearing) AS n_rearing,
  count(*) FILTER (WHERE lake_rearing) AS n_lake_rearing,
  count(*) FILTER (WHERE wetland_rearing) AS n_wetland_rearing,
  round((sum(length_metre) FILTER (WHERE spawning) / 1000)::numeric, 3) AS km_spawning,
  round((sum(length_metre) FILTER (WHERE rearing) / 1000)::numeric, 3) AS km_rearing"

classes <- list(); blocked <- list(); side <- list(); residual <- list()

for (sp in species) {
  t_sp <- Sys.time()
  sp_up <- toupper(sp)
  hab <- sprintf("%s.streams_habitat_%s", schema, sp)
  acc <- sprintf("access_%s", sp)
  view <- sprintf("%s.barriers_%s_access", schema, sp)

  # Forward and reverse rows, with what the classes need.
  x("DROP TABLE IF EXISTS ad_rows")
  x(sprintf("
    CREATE TEMP TABLE ad_rows AS
    SELECT s.id_segment, s.watershed_group_code, s.blue_line_key,
           s.downstream_route_measure AS drm, s.wscode_ltree, s.localcode_ltree,
           s.length_metre, s.waterbody_key,
           h.spawning, h.rearing, h.lake_rearing, h.wetland_rearing,
           CASE WHEN h.accessible THEN 'forward' ELSE 'reverse' END AS direction
    FROM %1$s h
    JOIN %2$s.streams_access a USING (id_segment, watershed_group_code)
    JOIN %2$s.streams s USING (id_segment, watershed_group_code)
    WHERE ((h.accessible AND a.%3$s = 0) OR (NOT h.accessible AND a.%3$s > 0)) %4$s",
    hab, schema, acc, wsg_filter("h")))
  x("ANALYZE ad_rows")

  # Groups whose outlet has an un-lifted blocking natural barrier downstream,
  # outside the group (class B), with the barrier's FWA group.
  x("DROP TABLE IF EXISTS ad_outlet_block")
  x(sprintf("
    CREATE TEMP TABLE ad_outlet_block AS
    WITH o(wsg, blk, drm, wsc, loc) AS (VALUES %1$s)
    SELECT o.wsg, b.blue_line_key, b.downstream_route_measure, b.barrier_source,
           b.wscode_ltree, b.localcode_ltree,
           string_agg(DISTINCT b.watershed_group_code, ';') AS persisted_wsgs,
           (SELECT f.watershed_group_code FROM whse_basemapping.fwa_stream_networks_sp f
             WHERE f.blue_line_key = b.blue_line_key
               AND b.downstream_route_measure >= f.downstream_route_measure
               AND b.downstream_route_measure <  f.upstream_route_measure
             LIMIT 1) AS fwa_wsg
    FROM o JOIN %2$s b
      ON b.barrier_source IN %3$s
     AND whse_basemapping.fwa_downstream(o.blk, o.drm, o.wsc, o.loc,
           b.blue_line_key, b.downstream_route_measure, b.wscode_ltree, b.localcode_ltree)
    GROUP BY o.wsg, b.blue_line_key, b.downstream_route_measure, b.barrier_source,
             b.wscode_ltree, b.localcode_ltree", outlet_values, view, natural))
  x("DELETE FROM ad_outlet_block WHERE fwa_wsg = wsg")

  # Forward classes.
  x("DROP TABLE IF EXISTS ad_class")
  x(sprintf("
    CREATE TEMP TABLE ad_class AS
    SELECT r.*, nb.b_drm, nb.barrier_source AS near_source,
      CASE
        WHEN r.direction = 'forward' AND nb.b_drm IS NOT NULL
             AND nb.b_drm < r.drm AND round(nb.b_drm) > r.drm THEN 'A_rounding'
        WHEN r.direction = 'forward' AND nb.b_drm IS NOT NULL
             AND nb.b_drm >= r.drm THEN 'A_prime_ltree'
        WHEN r.direction = 'forward' AND nb.b_drm IS NOT NULL THEN 'A_other'
        WHEN r.direction = 'forward' AND r.watershed_group_code IN
             (SELECT wsg FROM ad_outlet_block) THEN 'B_cross_group'
        WHEN r.direction = 'forward' THEN 'residual'
      END AS class
    FROM ad_rows r
    LEFT JOIN LATERAL (
      SELECT b.downstream_route_measure AS b_drm, b.barrier_source
      FROM %1$s b
      WHERE b.blue_line_key = r.blue_line_key
        AND b.barrier_source IN %2$s
        AND abs(b.downstream_route_measure - r.drm) < 1
      ORDER BY abs(b.downstream_route_measure - r.drm), b.downstream_route_measure
      LIMIT 1) nb ON r.direction = 'forward'", view, natural))

  # Reverse classes. The natural-barrier candidates are the group's own
  # persisted rows (what the group's fresh run read), ignoring overrides.
  x(sprintf("
    UPDATE ad_class r SET class = CASE
      WHEN EXISTS (
        SELECT 1 FROM %1$s.barriers b
        WHERE b.watershed_group_code = r.watershed_group_code
          AND %2$s = ANY (b.blocks_species)
          AND b.barrier_source IN %3$s
          AND whse_basemapping.fwa_downstream(r.blue_line_key, r.drm,
                r.wscode_ltree, r.localcode_ltree,
                b.blue_line_key, b.downstream_route_measure,
                b.wscode_ltree, b.localcode_ltree)
          AND EXISTS (SELECT 1 FROM %1$s.barrier_overrides o
                       WHERE o.species_code = %2$s AND o.blue_line_key = b.blue_line_key
                         AND abs(o.downstream_route_measure - b.downstream_route_measure) < 1
                         AND o.watershed_group_code <> r.watershed_group_code)
          AND NOT EXISTS (SELECT 1 FROM %1$s.barrier_overrides o
                       WHERE o.species_code = %2$s AND o.blue_line_key = b.blue_line_key
                         AND abs(o.downstream_route_measure - b.downstream_route_measure) < 1
                         AND o.watershed_group_code = r.watershed_group_code))
        THEN 'R_override_scope'
      WHEN EXISTS (
        SELECT 1 FROM %1$s.barriers b
        WHERE b.blue_line_key = r.blue_line_key
          AND %2$s = ANY (b.blocks_species)
          AND b.barrier_source IN %3$s
          AND abs(b.downstream_route_measure - r.drm) < 1)
        THEN 'R_near_1m'
      ELSE 'R_other' END
    WHERE r.direction = 'reverse'", schema, lit(sp_up), natural))

  cl <- q(sprintf("SELECT %s AS species, direction, class, %s
                   FROM ad_class GROUP BY direction, class ORDER BY direction, class",
                  lit(sp), flag_sums))
  tot <- q(sprintf("SELECT count(*) FILTER (WHERE h.accessible AND a.%1$s = 0) AS fwd,
                           count(*) FILTER (WHERE h.accessible) AS n_accessible
                    FROM %2$s h JOIN %3$s.streams_access a USING (id_segment, watershed_group_code)
                    WHERE TRUE %4$s", acc, hab, schema, wsg_filter("h")))
  fwd_sum <- sum(cl$n_segments[cl$direction == "forward"])
  if (fwd_sum != tot$fwd) {
    stop(sprintf("%s: forward classes sum to %s, total is %s", sp, fwd_sum, tot$fwd),
         call. = FALSE)
  }
  cl$share_of_accessible <- round(cl$n_segments / tot$n_accessible, 5)
  classes[[sp]] <- cl
  rg <- q(sprintf("SELECT %s AS species, watershed_group_code, %s FROM ad_class
                   WHERE class = 'residual' GROUP BY watershed_group_code
                   ORDER BY count(*) DESC", lit(sp), flag_sums))
  if (nrow(rg)) residual[[sp]] <- rg

  # ---- groups at >= 99 % forward disagreement, and what blocks them -----------
  gb <- q(sprintf("
    WITH acc AS (
      SELECT h.watershed_group_code, count(*) AS n_accessible
      FROM %1$s h WHERE h.accessible %2$s GROUP BY 1),
    dis AS (
      SELECT watershed_group_code, %3$s FROM ad_class
      WHERE direction = 'forward' GROUP BY 1)
    SELECT d.watershed_group_code, a.n_accessible, d.n_segments, d.km,
           d.km_spawning, d.km_rearing
    FROM dis d JOIN acc a USING (watershed_group_code)
    WHERE d.n_segments >= 0.99 * a.n_accessible", hab, wsg_filter("h"), flag_sums))
  if (nrow(gb)) {
    rule <- params[params$species_code == sp_up, , drop = FALSE][1, ]
    obs_sp <- if (is.na(rule$observation_species)) sp_up else
      trimws(strsplit(rule$observation_species, ";")[[1]])
    date_min <- if (is.na(rule$observation_date_min)) "1900-01-01" else
      as.character(rule$observation_date_min)
    buffer_m <- if (is.na(rule$observation_buffer_m)) 20 else rule$observation_buffer_m
    bb <- q(sprintf("
      SELECT ob.wsg AS watershed_group_code, ob.barrier_source, ob.blue_line_key,
             round(ob.downstream_route_measure::numeric, 1) AS downstream_route_measure,
             ob.fwa_wsg, ob.persisted_wsgs,
             (SELECT count(*) FROM ad_obs o
               WHERE o.species_code IN (%1$s) AND o.observation_date >= %2$s
                 AND whse_basemapping.fwa_upstream(ob.blue_line_key, ob.downstream_route_measure,
                       ob.wscode_ltree, ob.localcode_ltree, o.blue_line_key,
                       o.downstream_route_measure, o.wscode, o.localcode, false, %3$s))
               AS obs_upstream_all,
             (SELECT count(*) FROM ad_obs o
               WHERE o.species_code IN (%1$s) AND o.observation_date >= %2$s
                 AND o.present_own_group
                 AND whse_basemapping.fwa_upstream(ob.blue_line_key, ob.downstream_route_measure,
                       ob.wscode_ltree, ob.localcode_ltree, o.blue_line_key,
                       o.downstream_route_measure, o.wscode, o.localcode, false, %3$s))
               AS obs_upstream_province,
             (SELECT max(n) FROM (
                SELECT count(*) AS n FROM ad_obs o
                JOIN ad_presence p ON p.watershed_group_code = o.watershed_group_code
                                  AND p.species_code = o.species_code
                WHERE o.watershed_group_code = ANY (string_to_array(ob.persisted_wsgs, ';'))
                  AND o.species_code IN (%1$s) AND o.observation_date >= %2$s
                  AND whse_basemapping.fwa_upstream(ob.blue_line_key, ob.downstream_route_measure,
                        ob.wscode_ltree, ob.localcode_ltree, o.blue_line_key,
                        o.downstream_route_measure, o.wscode, o.localcode, false, %3$s)
                GROUP BY o.watershed_group_code) g) AS obs_upstream_in_holding_group
      FROM ad_outlet_block ob
      WHERE ob.wsg IN (%4$s)
      ORDER BY ob.wsg, ob.blue_line_key, ob.downstream_route_measure",
      lit(obs_sp), lit(date_min), buffer_m, lit(gb$watershed_group_code)))
    bb$obs_upstream_in_holding_group[is.na(bb$obs_upstream_in_holding_group)] <- 0L
    bb$rule_threshold <- rule$observation_threshold
    gbj <- merge(gb, bb, by = "watershed_group_code", all.x = TRUE)
    blocked[[sp]] <- cbind(species = sp, gbj)
  }

  # ---- side effects -----------------------------------------------------------
  se <- q(sprintf("
    WITH z AS (
      SELECT s.id_segment, s.watershed_group_code, s.blue_line_key,
             s.downstream_route_measure, s.upstream_route_measure, s.length_metre,
             h.spawning, h.rearing
      FROM %1$s h
      JOIN %2$s.streams_access a USING (id_segment, watershed_group_code)
      JOIN %2$s.streams s USING (id_segment, watershed_group_code)
      WHERE a.%3$s = 0 AND (h.spawning OR h.rearing) %4$s)
    SELECT count(*) FILTER (WHERE z.spawning) AS access0_spawning,
           count(*) FILTER (WHERE z.rearing) AS access0_rearing,
           count(*) FILTER (WHERE z.spawning AND EXISTS (
             SELECT 1 FROM ad_uhc k WHERE k.species_code = %5$s AND k.spawning
               AND k.blue_line_key = z.blue_line_key
               AND z.downstream_route_measure >= k.downstream_route_measure
               AND z.upstream_route_measure <= k.upstream_route_measure)) AS access0_spawning_overlay,
           count(*) FILTER (WHERE z.rearing AND EXISTS (
             SELECT 1 FROM ad_uhc k WHERE k.species_code = %5$s AND k.rearing
               AND k.blue_line_key = z.blue_line_key
               AND z.downstream_route_measure >= k.downstream_route_measure
               AND z.upstream_route_measure <= k.upstream_route_measure)) AS access0_rearing_overlay
    FROM z", hab, schema, acc, wsg_filter("h"), lit(sp_up)))

  # Lake polygons whose lake_rearing survives the settle (access > 0), with
  # spawning the settle blanks within 10 km (default's connected distance) and
  # no surviving spawning within 10 km. The blanked spawning is taken from the
  # A / residual classes only: a B group is blanked whole, its lakes with it.
  # Each side is a temp table with a GiST index, so both distance tests are
  # index scans.
  x("DROP TABLE IF EXISTS ad_bl, ad_lr, ad_sp")
  x(sprintf("CREATE TEMP TABLE ad_bl AS SELECT s.geom FROM ad_class c
             JOIN %s.streams s USING (id_segment, watershed_group_code)
             WHERE c.direction = 'forward' AND c.spawning
               AND c.class <> 'B_cross_group'", schema))
  x(sprintf("CREATE TEMP TABLE ad_lr AS SELECT s.waterbody_key, s.geom FROM %1$s h
             JOIN %2$s.streams_access a USING (id_segment, watershed_group_code)
             JOIN %2$s.streams s USING (id_segment, watershed_group_code)
             WHERE h.lake_rearing AND a.%3$s > 0 AND s.waterbody_key IS NOT NULL %4$s",
            hab, schema, acc, wsg_filter("h")))
  x(sprintf("CREATE TEMP TABLE ad_sp AS SELECT s.geom FROM %1$s h
             JOIN %2$s.streams_access a USING (id_segment, watershed_group_code)
             JOIN %2$s.streams s USING (id_segment, watershed_group_code)
             WHERE h.spawning AND a.%3$s > 0 %4$s", hab, schema, acc, wsg_filter("h")))
  for (tb in c("ad_bl", "ad_lr", "ad_sp")) {
    x(sprintf("CREATE INDEX ON %s USING gist (geom)", tb))
    x(sprintf("ANALYZE %s", tb))
  }
  lk <- q("
    WITH cand AS (
      SELECT DISTINCT l.waterbody_key FROM ad_lr l
      WHERE EXISTS (SELECT 1 FROM ad_bl b WHERE ST_DWithin(b.geom, l.geom, 10000)))
    SELECT count(*) AS lake_polygons_near_blanked_spawning,
           count(*) FILTER (WHERE NOT EXISTS (
             SELECT 1 FROM ad_lr l JOIN ad_sp p ON ST_DWithin(p.geom, l.geom, 10000)
             WHERE l.waterbody_key = cand.waterbody_key)) AS lake_polygons_lose_spawning
    FROM cand")

  ck <- q(sprintf("
    SELECT (SELECT count(*) FROM %1$s.streams_access a WHERE a.%2$s = -9 %3$s) AS n_minus9,
           (SELECT count(*) FROM ad_class c WHERE c.direction = 'forward'
              AND NOT EXISTS (SELECT 1 FROM ad_presence p
                               WHERE p.watershed_group_code = c.watershed_group_code
                                 AND p.species_code = %4$s)) AS n_forward_in_absent_group",
    schema, acc, wsg_filter("a"), lit(sp_up)))
  side[[sp]] <- cbind(species = sp, se, lk, ck)

  message(sprintf("[%s] %s forward / %s accessible; %.1f s", sp, tot$fwd, tot$n_accessible,
                  as.numeric(difftime(Sys.time(), t_sp, units = "secs"))))
}

classes <- do.call(rbind, classes)
blocked <- if (length(blocked)) do.call(rbind, blocked) else data.frame()
side    <- do.call(rbind, side)
utils::write.csv(classes, file.path(out, "classes.csv"), row.names = FALSE)
utils::write.csv(blocked, file.path(out, "groups_blocked.csv"), row.names = FALSE)
utils::write.csv(side, file.path(out, "side_effects.csv"), row.names = FALSE)
residual <- if (length(residual)) do.call(rbind, residual) else data.frame()
utils::write.csv(residual, file.path(out, "residual_groups.csv"), row.names = FALSE)

# ---- stamp + summary ----------------------------------------------------------
git <- function(...) tryCatch(system2("git", c(...), stdout = TRUE), error = function(e) NA_character_)
dirty <- length(git("status", "--porcelain", "--untracked-files=no")) > 0
runs <- q(sprintf("SELECT run_uid, count(*) AS n_groups FROM (
                     SELECT DISTINCT ON (watershed_group_code) watershed_group_code, run_uid
                     FROM %s.log WHERE watershed_group_code IN (%s)
                     ORDER BY watershed_group_code, date_end DESC NULLS LAST) l
                   GROUP BY run_uid ORDER BY n_groups DESC", schema, lit(wsg_all)))
fresh_desc <- utils::packageDescription("fresh")
md_table <- function(d) {
  d[] <- lapply(d, function(v) if (is.numeric(v)) format(v, big.mark = ",", trim = TRUE) else v)
  c(paste0("| ", paste(names(d), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(d)), collapse = "|"), "|"),
    apply(d, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}
writeLines(c(
  "# accessible vs access_<sp> disagreement by mechanism (link#349)", "",
  sprintf("- run: %s UTC, %.1f min", format(Sys.time(), "%Y-%m-%d %H:%M", tz = "UTC"),
          as.numeric(difftime(Sys.time(), t_start, units = "mins"))),
  sprintf("- script: `data-raw/access_disagree_349.R --schema=%s --config=%s%s`", schema, config,
          if (length(wsgs)) paste0(" --wsgs=", paste(wsgs, collapse = ",")) else ""),
  sprintf("- link %s @ %s%s; fresh %s @ %s", utils::packageVersion("link"),
          git("rev-parse", "--short", "HEAD"), if (dirty) " (dirty)" else "",
          fresh_desc$Version, substr(fresh_desc$RemoteSha %||% NA_character_, 1, 7)),
  sprintf("- groups read: %d; newest log row per group by run_uid: %s", length(wsg_all),
          paste(sprintf("%s (%d)", runs$run_uid, as.integer(runs$n_groups)), collapse = ", ")),
  sprintf("- bcfishobs.observations rows: %s",
          q("SELECT count(*) AS n FROM bcfishobs.observations")$n),
  "", "## Classes (segments; `share_of_accessible` against the species' accessible segments)", "",
  md_table(classes[, c("species", "direction", "class", "n_segments", "km", "n_spawning",
                       "n_rearing", "share_of_accessible")]),
  "", "## Side effects of a settle on `access_<sp>`", "", md_table(side)),
  file.path(out, "summary.md"))
message("wrote ", out)
DBI::dbDisconnect(conn)
