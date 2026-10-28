# Question 3 (#396): how much of the sampling bias is left? Segment length, and
# segment gradient against the FWA line's, at sites with fish against sites
# without, BEFORE (zz396_default_pre) and AFTER (zz396_default_post).
#
#   LNK_KNOWLEDGE_DIR=<knowledge checkout> \
#     Rscript data-raw/logs/observation_breaks_396/bias.R
#
# Site classes:
#   - obs: bcfishobs locations of the group's `default` observation set
#     (zz396_cuts.obs_<wsg>, build_obs.R), every group;
#   - fiss_fish / fiss_no_fish: FISS sites that were sampled (effort recorded
#     or no-fish-caught) with species listed, or no-fish-caught and none
#     listed. Read from the private knowledge repo, snapped to the nearest
#     FWA line within 100 m as hv_fiss_absences() does
#     (data-raw/habitat_validate_inputs.R), and kept only in the group whose
#     snapshot holds them. Only UPCE of the built groups has a snapshot.
#     Aggregates only are written: link is public.
#   - network: every metre of the group's network, i.e. segment length
#     weighted by length (what a randomly placed site would see).
# A site attaches to the segment starting within 1 m of it, else the one
# holding it (lnk_habitat_validate()'s rule). The FWA gradient is that of the
# fwa_stream_networks_sp line holding the site.
pkgload::load_all(quiet = TRUE)
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
out <- "data-raw/logs/observation_breaks_396"
wsgs <- c("LKEL", "BULK", "UPCE", "PARS", "ELKR")
schemas <- c(before = "zz396_default_pre", after = "zz396_default_post")
q <- function(sql) DBI::dbGetQuery(conn, sql)
x <- function(sql) invisible(DBI::dbExecute(conn, sql))

# -- sites --------------------------------------------------------------------
sites <- do.call(rbind, lapply(wsgs, function(w) {
  d <- q(sprintf(
    "SELECT DISTINCT '%s' AS wsg, 'obs' AS class, blue_line_key AS blk,
            downstream_route_measure AS m
       FROM zz396_cuts.obs_%s", w, tolower(w)))
}))
dir_k <- Sys.getenv("LNK_KNOWLEDGE_DIR", "")
fiss_note <- "not measured: LNK_KNOWLEDGE_DIR unset"
if (nzchar(dir_k)) {
  files <- Sys.glob(file.path(dir_k, "data", tolower(wsgs),
                              "fiss_sites_*_all.csv"))
  if (length(files)) {
    num <- function(v) suppressWarnings(as.numeric(v))
    f <- do.call(rbind, lapply(files, function(p) {
      d <- utils::read.csv(p, colClasses = "character",
                           na.strings = c("", "NA"))
      listed <- nzchar(trimws(ifelse(is.na(d$species_list), "",
                                     d$species_list)))
      nfc <- d$nfc %in% "TRUE"
      sampled <- d$effort_recorded %in% "TRUE" | nfc
      data.frame(site_key = d$site_key, utm_zone = num(d$utm_zone),
                 utm_easting = num(d$utm_easting),
                 utm_northing = num(d$utm_northing),
                 cls = ifelse(listed, "fiss_fish",
                              ifelse(nfc, "fiss_no_fish", NA)),
                 snap = toupper(basename(dirname(p))),
                 keep = sampled, stringsAsFactors = FALSE)
    }))
    f <- f[f$keep & !is.na(f$cls) & !is.na(f$utm_zone) &
             !is.na(f$utm_easting) & !is.na(f$utm_northing), ]
    f <- f[!duplicated(f$site_key), ]
    DBI::dbWriteTable(conn, "b396_fiss", f[, c("site_key", "utm_zone",
      "utm_easting", "utm_northing", "cls", "snap")],
      temporary = TRUE, overwrite = TRUE)
    snapped <- q("
      WITH p AS (
        SELECT site_key, cls, snap,
               st_transform(st_setsrid(st_makepoint(utm_easting, utm_northing),
                                       26900 + utm_zone::int), 3005) AS geom
          FROM pg_temp.b396_fiss)
      SELECT f.watershed_group_code AS wsg, p.cls AS class,
             f.blue_line_key AS blk,
             f.downstream_route_measure
               + st_linelocatepoint(st_force2d(f.geom), p.geom) * f.length_metre
               AS m, p.snap
        FROM p
        JOIN LATERAL (
          SELECT f.watershed_group_code, f.blue_line_key,
                 f.downstream_route_measure, f.length_metre, f.geom
            FROM whse_basemapping.fwa_stream_networks_sp f
           WHERE st_dwithin(f.geom, p.geom, 100) AND f.edge_type <> 1425
           ORDER BY f.geom <-> p.geom LIMIT 1) f ON true")
    snapped <- snapped[snapped$wsg == snapped$snap, c("wsg", "class", "blk", "m")]
    sites <- rbind(sites, snapped)
    fiss_note <- paste("FISS snapshots read for:",
                       paste(toupper(basename(dirname(files))), collapse = ", "))
  } else {
    fiss_note <- "not measured: no FISS snapshot for the built groups"
  }
}
DBI::dbWriteTable(conn, "b396_sites", sites, temporary = TRUE, overwrite = TRUE)

# -- per schema ---------------------------------------------------------------
res <- list()
for (k in names(schemas)) {
  s <- schemas[[k]]
  r <- q(sprintf(
    "WITH att AS (
       SELECT t.wsg, t.class, x.len, x.on_start,
              abs(x.gradient - g.gradient) AS grad_diff
         FROM pg_temp.b396_sites t
         JOIN LATERAL (
           SELECT s.length_metre AS len, s.gradient,
                  abs(s.downstream_route_measure - t.m) < 1 AS on_start
             FROM %1$s.streams s
            WHERE s.blue_line_key = t.blk AND s.watershed_group_code = t.wsg
              AND (abs(s.downstream_route_measure - t.m) < 1
                   OR (s.downstream_route_measure <= t.m
                       AND t.m < s.upstream_route_measure))
            ORDER BY (abs(s.downstream_route_measure - t.m) < 1) DESC,
                     s.downstream_route_measure DESC
            LIMIT 1) x ON true
         LEFT JOIN LATERAL (
           SELECT f.gradient FROM whse_basemapping.fwa_stream_networks_sp f
            WHERE f.blue_line_key = t.blk
              AND f.downstream_route_measure <= t.m
              AND t.m < f.upstream_route_measure
            ORDER BY f.downstream_route_measure DESC LIMIT 1) g ON true)
     SELECT wsg, class, count(*) AS n,
            round(avg(on_start::int)::numeric, 3) AS share_on_segment_start,
            round(percentile_cont(0.5) WITHIN GROUP (ORDER BY len)::numeric, 1)
              AS median_segment_m,
            round(percentile_cont(0.5) WITHIN GROUP (ORDER BY grad_diff)::numeric, 4)
              AS median_abs_gradient_diff_fwa,
            round(avg(grad_diff)::numeric, 4) AS mean_abs_gradient_diff_fwa
       FROM att GROUP BY wsg, class", s))
  # network: segment length weighted by length (median metre of network)
  n <- q(sprintf(
    "WITH s AS (
       SELECT watershed_group_code AS wsg, length_metre AS len,
              sum(length_metre) OVER (PARTITION BY watershed_group_code
                                      ORDER BY length_metre, id_segment) AS cum,
              sum(length_metre) OVER (PARTITION BY watershed_group_code) AS tot
         FROM %s.streams)
     SELECT wsg, 'network' AS class, count(*) AS n,
            NULL::numeric AS share_on_segment_start,
            round(min(len) FILTER (WHERE cum >= tot / 2)::numeric, 1)
              AS median_segment_m,
            NULL::numeric AS median_abs_gradient_diff_fwa,
            NULL::numeric AS mean_abs_gradient_diff_fwa
       FROM s GROUP BY wsg", s))
  r <- rbind(r, n)
  r$build <- k
  res[[k]] <- r
}
d <- do.call(rbind, res)
d <- d[order(d$wsg, d$class, d$build != "before"), c("wsg", "class", "build",
  "n", "share_on_segment_start", "median_segment_m",
  "median_abs_gradient_diff_fwa", "mean_abs_gradient_diff_fwa")]
utils::write.csv(d, file.path(out, "bias.csv"), row.names = FALSE)
writeLines(fiss_note, file.path(out, "bias_fiss_note.txt"))
message(fiss_note)
print(d, row.names = FALSE)
DBI::dbDisconnect(conn)
