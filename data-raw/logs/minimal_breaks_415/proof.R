# proof.R — #415: is the minimal network the full network with fewer cuts? One
# CSV per check, built on measure-overlap pieces per blue_line_key, never on
# id_segment (each build numbers its own).
#
#   Rscript data-raw/logs/minimal_breaks_415/proof.R --wsgs=ADMS [--out=<dir>]
#
# Reads the two scratch schemas run.sh builds. Pieces under 1 cm are dropped: a
# segment's upstream measure can overshoot the next one's start by up to
# 3.93 mm within one side (FWA).
#
# Checks, and what stops the script after every CSV is written:
#   builds.csv             both builds' newest log and log_recompute rows; stops
#                          unless one clean commit and fresh, this checkout's,
#                          the expected tokens,
#                          closed builds, and a recompute at or after each build
#                          that closed or failed only on the post-condition
#   segments.csv           segments and km per schema
#   superset.csv           every minimal cut has a full cut within tol_m of it, and
#                          km of full segments that straddle a minimal cut;
#                          stops on an unmatched cut
#   parent_<wsg>.csv       each full segment's largest-overlap minimal parent
#   access_km.csv          access_<sp> km by code per schema, both builds
#   access_open.csv        pieces whose species reads -9, 0 or open differently;
#                          stops on any outside slivers (len < 1.01 m), which the
#                          full build's 1 m skip rule leaves by construction
#   access_differences.csv those pieces, for reading
#   crossing_fields.csv    km on which each crossing-based field differs
#   overlay.csv            km of user habitat range each network applies
#   connectivity.csv       rearing km the predicate gives and the connectivity
#                          passes take away, both builds, split by polygon lines
#   gradient.csv           minimal gradient against length-weighted full gradient
#   breaks_census.csv      what put each minimal break there; stops on 'none'
#   placement.csv          bcfishobs records placed by knowledge's knw_link_place()
#                          rule on both networks, per branch
pkgload::load_all(quiet = TRUE)

argv <- commandArgs(trailingOnly = TRUE)
opt <- function(name, default) {
  hit <- grep(sprintf("^--%s=", name), argv, value = TRUE)
  if (length(hit)) sub(sprintf("^--%s=", name), "", hit[1]) else default
}
wsgs <- toupper(strsplit(opt("wsgs", ""), ",", fixed = TRUE)[[1]])
out <- opt("out", "data-raw/logs/minimal_breaks_415")
if (!length(wsgs)) stop("give --wsgs=<WSG>[,<WSG>...]", call. = FALSE)
stopifnot(all(grepl("^[A-Z]{4}$", wsgs)))
dir.create(out, recursive = TRUE, showWarnings = FALSE)

full <- "zz415_default"
minimal <- "zz415_minimal"
tol_m <- 1.01  # the full build skips a cut within 1 m of an existing end
start_window_m <- 5  # knw_link_place()'s default

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
q <- function(sql) DBI::dbGetQuery(conn, sql)
x <- function(sql) invisible(DBI::dbExecute(conn, sql))
num <- function(d) {
  i <- vapply(d, function(v) is.numeric(v) || inherits(v, "integer64"), TRUE)
  d[i] <- lapply(d[i], as.numeric)
  d
}
has_tbl <- function(schema, tbl) nrow(q(sprintf(
  "SELECT 1 FROM information_schema.tables
    WHERE table_schema = '%s' AND table_name = '%s'", schema, tbl))) > 0L
write_csv <- function(d, name) {
  utils::write.csv(d, file.path(out, name), row.names = FALSE)
}

cfg <- lnk_config("default_minimal")
loaded <- lnk_load_overrides(cfg)
params <- fresh::frs_params(csv = .lnk_habitat_thresholds_csv(cfg),
                            rules_yaml = cfg$rules)

# -- builds: one commit, clean, the expected tokens -------------------------
proof_sha <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE)
proof_dirty <- length(system2("git", c("status", "--porcelain", "--untracked-files=no"),
                              stdout = TRUE)) > 0L
builds <- do.call(rbind, lapply(wsgs, function(w) {
  do.call(rbind, lapply(c(full, minimal), function(s) {
    d <- q(sprintf(
      "SELECT watershed_group_code AS wsg, '%1$s' AS schema, link_sha, link_dirty,
              link_version, fresh_version, token_cut, token_acc, token_grad,
              token_flow, config_name, date_end
         FROM %1$s.log WHERE watershed_group_code = '%2$s'
        ORDER BY date_start DESC LIMIT 1", s, w))
    if (nrow(d) != 1L) stop(s, " has no log row for ", w, call. = FALSE)
    rc <- q(sprintf(
      "SELECT date_start AS recompute_start, date_end AS recompute_end,
              link_sha AS recompute_link_sha, link_dirty AS recompute_link_dirty,
              fresh_version AS recompute_fresh_version, notes AS recompute_notes
         FROM %1$s.log_recompute WHERE watershed_group_code = '%2$s'
        ORDER BY date_start DESC LIMIT 1", s, w))
    if (nrow(rc) != 1L) stop(s, " has no log_recompute row for ", w, call. = FALSE)
    cbind(d, rc)
  }))
}))
write_csv(builds, "builds.csv")
token_ok <- builds$token_cut == ifelse(builds$schema == minimal, "cut-min", "cut-full-top")
# The recompute writes the streams_access these checks read, so it counts too.
builds_ok <- length(unique(c(builds$link_sha, builds$recompute_link_sha))) == 1L &&
  !anyNA(builds$link_sha) &&
  all(builds$link_dirty %in% FALSE) && all(builds$recompute_link_dirty %in% FALSE) &&
  all(token_ok) &&
  length(unique(builds$token_acc)) == 1L && length(unique(builds$token_flow)) == 1L &&
  length(unique(c(builds$fresh_version, builds$recompute_fresh_version))) == 1L &&
  !anyNA(builds$date_end) &&
  # overlay.csv and connectivity.csv read this checkout's bundle and this fresh,
  # so a commit or an install since the builds would come out as km.
  identical(unique(builds$link_sha), proof_sha) && !proof_dirty &&
  identical(unique(builds$fresh_version), as.character(utils::packageVersion("fresh"))) &&
  all(builds$recompute_start >= builds$date_end) &&
  all(!is.na(builds$recompute_end) |
        grepl("BLOCKED (link#227)", builds$recompute_notes, fixed = TRUE))

# -- per group --------------------------------------------------------------
res <- list(segments = list(), superset = list(), access_km = list(),
            access_open = list(), access_differences = list(), crossing = list(),
            overlay = list(), connectivity = list(), gradient = list(),
            census = list(), placement = list())
add <- function(key, d) res[[key]][[length(res[[key]]) + 1L]] <<- d

acc_cols <- function(s) q(sprintf(
  "SELECT column_name FROM information_schema.columns
    WHERE table_schema = '%s' AND table_name = 'streams_access'", s))$column_name

for (w in wsgs) {
  message("[proof] ", w)
  for (t in c("sf", "sm", "af", "am", "pc")) {
    x(sprintf("DROP TABLE IF EXISTS pg_temp.%s", t))
  }
  for (p in list(c("sf", full), c("sm", minimal))) {
    x(sprintf(
      "CREATE TEMP TABLE %1$s AS
       SELECT id_segment, blue_line_key AS blk, downstream_route_measure AS dm,
              upstream_route_measure AS um, gradient, length_metre
         FROM %2$s.streams WHERE watershed_group_code = '%3$s'", p[1], p[2], w))
    x(sprintf("CREATE INDEX ON %s (blk, dm)", p[1]))
    x(sprintf("ANALYZE %s", p[1]))
  }
  x(sprintf("CREATE TEMP TABLE af AS SELECT * FROM %s.streams_access
              WHERE watershed_group_code = '%s'", full, w))
  x(sprintf("CREATE TEMP TABLE am AS SELECT * FROM %s.streams_access
              WHERE watershed_group_code = '%s'", minimal, w))
  x("CREATE UNIQUE INDEX ON af (id_segment)")
  x("CREATE UNIQUE INDEX ON am (id_segment)")
  x("CREATE TEMP TABLE pc AS
     SELECT f.id_segment AS fid, m.id_segment AS mid, f.blk,
            greatest(f.dm, m.dm) AS dm, least(f.um, m.um) AS um,
            least(f.um, m.um) - greatest(f.dm, m.dm) AS len
       FROM sf f JOIN sm m
         ON f.blk = m.blk AND f.dm < m.um AND m.dm < f.um
      WHERE least(f.um, m.um) - greatest(f.dm, m.dm) >= 0.01")
  x("ANALYZE pc")

  # Segments, and the overlap must cover both sides: 1 m per 1,000 segments.
  seg <- num(q(sprintf(
    "SELECT '%s' AS wsg,
            (SELECT count(*) FROM sf) AS n_full, (SELECT count(*) FROM sm) AS n_minimal,
            (SELECT sum(um - dm) FROM sf) / 1000 AS km_full,
            (SELECT sum(um - dm) FROM sm) / 1000 AS km_minimal,
            (SELECT sum(len) FROM pc) / 1000 AS km_pieces", w)))
  n_access <- num(q("SELECT (SELECT count(*) FROM sf s WHERE NOT EXISTS (
                               SELECT 1 FROM af a WHERE a.id_segment = s.id_segment)) AS f_missing,
                            (SELECT count(*) FROM sm s WHERE NOT EXISTS (
                               SELECT 1 FROM am a WHERE a.id_segment = s.id_segment)) AS m_missing"))
  seg$n_full_no_access <- n_access$f_missing
  seg$n_minimal_no_access <- n_access$m_missing
  add("segments", seg)
  tol <- max(seg$n_full, seg$n_minimal) / 1e6
  if (abs(seg$km_pieces - seg$km_full) > tol || abs(seg$km_pieces - seg$km_minimal) > tol) {
    print(seg)
    stop(w, ": overlap pieces do not cover both sides", call. = FALSE)
  }

  # Superset. A break is a start above the line's own zero (breaks_diff.R).
  parent <- num(q(sprintf(
    "SELECT DISTINCT ON (pc.fid) pc.fid AS id_segment, '%s' AS wsg,
            pc.mid AS id_segment_minimal, m.gradient AS gradient_minimal,
            m.length_metre AS length_minimal, pc.len AS overlap_m,
            (f.um - f.dm) - pc.len AS straddle_m
       FROM pc
       JOIN sf f ON f.id_segment = pc.fid
       JOIN sm m ON m.id_segment = pc.mid
      ORDER BY pc.fid, pc.len DESC, pc.mid", w)))
  write_csv(parent, sprintf("parent_%s.csv", tolower(w)))
  sup <- num(q(sprintf(
    "SELECT '%1$s' AS wsg,
            count(*) AS n_minimal_cuts,
            count(*) FILTER (WHERE EXISTS (
              SELECT 1 FROM sf f WHERE f.blk = m.blk AND abs(f.dm - m.dm) <= %2$s)) AS n_matched,
            count(*) FILTER (WHERE EXISTS (
              SELECT 1 FROM sf f WHERE f.blk = m.blk AND abs(f.dm - m.dm) < 0.01)) AS n_exact
       FROM sm m WHERE m.dm > 0.5", w, tol_m)))
  sup$n_unmatched <- sup$n_minimal_cuts - sup$n_matched
  sup$n_full_segments <- nrow(parent)
  sup$n_straddle_gt_tol <- sum(parent$straddle_m > tol_m)
  sup$km_straddle_gt_tol <- sum(parent$straddle_m[parent$straddle_m > tol_m]) / 1000
  sup$max_straddle_m <- max(parent$straddle_m)
  add("superset", sup)

  # Species: access on both networks.
  cols_f <- acc_cols(full)
  species <- sub("^access_", "", grep("^access_", cols_f, value = TRUE))
  species_minimal <- sub("^access_", "", grep("^access_", acc_cols(minimal), value = TRUE))
  if (!setequal(species, species_minimal)) {
    stop(w, ": the networks carry different species: ",
         paste(setdiff(union(species, species_minimal), intersect(species, species_minimal)),
               collapse = ", "), call. = FALSE)
  }
  for (sp in species) {
    a <- sprintf("access_%s", sp)
    km <- rbind(
      cbind(schema = full, num(q(sprintf(
        "SELECT '%1$s' AS wsg, '%2$s' AS sp, a.%3$s AS code,
                count(*) AS n, sum(s.um - s.dm) / 1000 AS km
           FROM sf s JOIN af a USING (id_segment) GROUP BY 3", w, sp, a)))),
      cbind(schema = minimal, num(q(sprintf(
        "SELECT '%1$s' AS wsg, '%2$s' AS sp, a.%3$s AS code,
                count(*) AS n, sum(s.um - s.dm) / 1000 AS km
           FROM sm s JOIN am a USING (id_segment) GROUP BY 3", w, sp, a)))))
    add("access_km", km)

    diff_sql <- sprintf(
      "FROM pc JOIN af ON af.id_segment = pc.fid JOIN am ON am.id_segment = pc.mid
       WHERE least(coalesce(af.%1$s, -99), 1) IS DISTINCT FROM
             least(coalesce(am.%1$s, -99), 1)", a)
    add("access_open", num(q(sprintf(
      "SELECT '%1$s' AS wsg, '%2$s' AS sp,
              count(*) FILTER (WHERE pc.len < 1.01) AS n_sliver,
              count(*) FILTER (WHERE pc.len >= 1.01) AS n_violation,
              coalesce(sum(pc.len) FILTER (WHERE pc.len >= 1.01), 0) AS m_violation
         %3$s", w, sp, diff_sql))))
    d <- num(q(sprintf(
      "SELECT '%1$s' AS wsg, '%2$s' AS sp, pc.blk, pc.dm, pc.um, pc.len,
              af.%4$s AS access_full, am.%4$s AS access_minimal %3$s
        ORDER BY pc.blk, pc.dm", w, sp, diff_sql, a)))
    if (nrow(d)) add("access_differences", d)
  }

  # Crossing-based fields, and every has_barriers flag. km by which side is TRUE.
  flags <- intersect(cols_f, acc_cols(minimal))
  flags <- flags[grepl("^has_barriers_|_dnstr_ind$", flags)]
  add("crossing", do.call(rbind, lapply(flags, function(fl) {
    num(q(sprintf(
      "SELECT '%1$s' AS wsg, '%2$s' AS field,
              coalesce(sum(pc.len) FILTER (WHERE af.%2$s), 0) / 1000 AS km_true_full,
              coalesce(sum(pc.len) FILTER (WHERE am.%2$s), 0) / 1000 AS km_true_minimal,
              coalesce(sum(pc.len) FILTER (WHERE af.%2$s IS TRUE AND am.%2$s IS NOT TRUE), 0) / 1000 AS km_full_only,
              coalesce(sum(pc.len) FILTER (WHERE am.%2$s IS TRUE AND af.%2$s IS NOT TRUE), 0) / 1000 AS km_minimal_only
         FROM pc JOIN af ON af.id_segment = pc.fid JOIN am ON am.id_segment = pc.mid",
      w, fl)))
  })))

  # User habitat overlay. fresh's match and lnk_habitat_gate() keep a flag only
  # where one row contains the whole segment, so km inside a range on a segment
  # that also runs past its end is not applied.
  # Rows are matched by line and measure, not by the group they are filed under,
  # as the gate and fresh's overlay match them.
  uhc <- loaded$user_habitat_classification
  truthy <- function(v) tolower(trimws(as.character(v))) %in% c("1", "t", "true")
  for (s in c(full, minimal)) {
    tbl <- if (s == full) "sf" else "sm"
    segs <- num(q(sprintf("SELECT blk, dm, um FROM %s", tbl)))
    uhc_w <- uhc[uhc$blue_line_key %in% segs$blk, , drop = FALSE]
    for (stage in c("spawning", "rearing")) {
      u <- uhc_w[truthy(uhc_w[[stage]]), , drop = FALSE]
      for (sp in unique(u$species_code)) {
        r <- u[u$species_code == sp, , drop = FALSE]
        tot <- c(covered_km = 0, applied_km = 0)
        for (b in unique(r$blue_line_key)) {
          rb <- r[r$blue_line_key == b, , drop = FALSE]
          sb <- segs[segs$blk == b, , drop = FALSE]
          # Ranges merged, so overlapping rows do not count km twice.
          rb <- rb[order(rb$downstream_route_measure), , drop = FALSE]
          lo <- rb$downstream_route_measure[1]; hi <- rb$upstream_route_measure[1]
          merged <- list()
          for (i in seq_len(nrow(rb))[-1L]) {
            if (rb$downstream_route_measure[i] <= hi) {
              hi <- max(hi, rb$upstream_route_measure[i])
            } else {
              merged[[length(merged) + 1L]] <- c(lo, hi)
              lo <- rb$downstream_route_measure[i]; hi <- rb$upstream_route_measure[i]
            }
          }
          merged[[length(merged) + 1L]] <- c(lo, hi)
          for (m in merged) {
            ov <- pmin(sb$um, m[2]) - pmax(sb$dm, m[1])
            tot["covered_km"] <- tot["covered_km"] + sum(ov[ov > 0]) / 1000
          }
          inside <- vapply(seq_len(nrow(sb)), function(i) {
            any(sb$dm[i] >= rb$downstream_route_measure &
                  sb$um[i] <= rb$upstream_route_measure)
          }, logical(1))
          tot["applied_km"] <- tot["applied_km"] + sum((sb$um - sb$dm)[inside]) / 1000
        }
        add("overlay", data.frame(wsg = w, schema = s, sp = sp, stage = stage,
                                  covered_km = tot[["covered_km"]],
                                  applied_km = tot[["applied_km"]],
                                  under_applied_km = tot[["covered_km"]] - tot[["applied_km"]]))
      }
    }
  }

  # Connectivity: km the rear predicate gives on accessible segments and the
  # persisted flag does not. The predicate ORs every rear rule, so the km split
  # into lake, reservoir and wetland polygon lines (requires_connected: spawning)
  # and the rest (cluster_rearing). The gate has already blanked inaccessible rows.
  model <- unique(.lnk_wsg_model(.lnk_habitat_method_read(.lnk_habitat_method_csv(cfg)), w))
  for (s in c(full, minimal)) {
    near <- if (has_tbl(s, "streams_near_river")) paste0(s, ".streams_near_river") else NULL
    for (sp in species) {
      SP <- toupper(sp)
      if (!has_tbl(s, paste0("streams_habitat_", sp)) || is.null(params[[SP]])) next
      n <- q(sprintf("SELECT count(*) AS n FROM %s.streams_habitat_%s
                       WHERE watershed_group_code = '%s'", s, sp, w))$n
      if (as.numeric(n) == 0) next
      pr <- fresh::frs_habitat_predicates(
        .lnk_hv_sp_params(params, loaded$parameters_fresh, SP),
        model = model, near_river_table = near)
      src <- if (grepl("\\bs\\.mad_m3s\\b", pr$rear, perl = TRUE)) {
        stop(w, " is on mad: proof.R reads channel width only", call. = FALSE)
      } else {
        paste0(s, ".streams")
      }
      add("connectivity", cbind(schema = s, num(q(sprintf(
        "SELECT '%1$s' AS wsg, '%2$s' AS sp,
                coalesce(sum(t.len) FILTER (WHERE t.acc AND t.pred), 0) / 1000 AS km_predicate,
                coalesce(sum(t.len) FILTER (WHERE t.rearing), 0) / 1000 AS km_rearing,
                coalesce(sum(t.len) FILTER (WHERE t.acc AND t.pred AND NOT t.rearing), 0) / 1000 AS km_dropped,
                coalesce(sum(t.len) FILTER (WHERE t.acc AND t.pred AND NOT t.rearing AND t.in_poly), 0) / 1000 AS km_dropped_polygon,
                coalesce(sum(t.len) FILTER (WHERE t.spawning), 0) / 1000 AS km_spawning
           FROM (SELECT s.length_metre AS len, h.accessible AS acc, h.rearing, h.spawning,
                        coalesce((%3$s), false) AS pred,
                        coalesce(s.waterbody_key IN (
                          SELECT waterbody_key FROM whse_basemapping.fwa_lakes_poly
                          UNION ALL SELECT waterbody_key FROM whse_basemapping.fwa_manmade_waterbodies_poly
                          UNION ALL SELECT waterbody_key FROM whse_basemapping.fwa_wetlands_poly), false) AS in_poly
                   FROM %4$s s
                   JOIN %5$s.streams_habitat_%6$s h
                     ON h.id_segment = s.id_segment
                    AND h.watershed_group_code = s.watershed_group_code
                  WHERE s.watershed_group_code = '%1$s') t",
        w, SP, pr$rear, src, s, sp)))))
    }
  }

  # Gradient: telescoping says each minimal segment's gradient is the
  # length-weighted gradient of its pieces, up to rounding and FWA's own gaps.
  g <- num(q(
    "SELECT m.id_segment, m.gradient AS g_min, (m.um - m.dm) AS len, count(*) AS n_pieces,
            sum(pc.len * f.gradient) / nullif(sum(pc.len), 0) AS g_full
       FROM pc JOIN sf f ON f.id_segment = pc.fid JOIN sm m ON m.id_segment = pc.mid
      WHERE f.gradient IS NOT NULL AND m.gradient IS NOT NULL
      GROUP BY m.id_segment, m.gradient, m.um, m.dm"))
  dg <- abs(g$g_min - g$g_full)
  qs <- stats::quantile(dg, c(0.5, 0.9, 0.99), names = FALSE, na.rm = TRUE)
  add("gradient", data.frame(
    wsg = w, n_minimal = nrow(g), n_split = sum(g$n_pieces > 1L),
    p50_abs_diff = qs[1], p90_abs_diff = qs[2], p99_abs_diff = qs[3],
    max_abs_diff = max(dg, na.rm = TRUE),
    km_within_0p001 = sum(g$len[dg <= 0.001], na.rm = TRUE) / 1000,
    km_within_0p01 = sum(g$len[dg <= 0.01], na.rm = TRUE) / 1000,
    km_total = sum(g$len) / 1000))

  # Census. run.sh builds minimal last, so working_<wsg> should hold it; proved
  # by count and summed starts, as breaks_diff.R does.
  working <- paste0("working_", tolower(w))
  fp <- function(tbl, where) num(q(sprintf(
    "SELECT count(*) AS n, round(sum(downstream_route_measure)::numeric, 0) AS m
       FROM %s %s", tbl, where)))
  same <- has_tbl(working, "streams") && identical(
    fp(paste0(working, ".streams"), ""),
    fp(paste0(minimal, ".streams"), sprintf("WHERE watershed_group_code = '%s'", w)))
  if (!same) {
    add("census", data.frame(wsg = w, source = "working_schema_not_this_build", n = NA_real_))
  } else {
    near <- function(t) sprintf(
      "EXISTS (SELECT 1 FROM %s z WHERE z.blue_line_key = m.blk
                  AND abs(z.downstream_route_measure - m.dm) <= %s)", t, tol_m)
    add("census", num(q(sprintf(
      "SELECT '%1$s' AS wsg,
              CASE WHEN %2$s THEN 'gradient_minimal'
                   WHEN %3$s THEN 'falls'
                   WHEN %4$s THEN 'barriers_definite'
                   WHEN %5$s THEN 'fwa_base_segment'
                   ELSE 'none' END AS source,
              count(*) AS n
         FROM sm m WHERE m.dm > 0.5 GROUP BY 2 ORDER BY 2",
      w,
      near(paste0(working, ".gradient_barriers_minimal")),
      near(paste0(working, ".falls")),
      near(paste0(working, ".barriers_definite")),
      sprintf("EXISTS (SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp z
                        WHERE z.blue_line_key = m.blk AND z.watershed_group_code = '%s'
                          AND abs(z.downstream_route_measure - m.dm) <= %s)", w, tol_m)))))
  }

  # Placement, by knw_link_place()'s rule: the lowest segment start within
  # [measure - 1, measure + window] wins, else the segment containing the point.
  for (p in list(c(full, "sf"), c(minimal, "sm"))) {
    add("placement", cbind(schema = p[1], num(q(sprintf(
      "WITH r AS (
         SELECT blue_line_key AS blk, downstream_route_measure AS m
           FROM bcfishobs.observations
          WHERE watershed_group_code = '%1$s' AND blue_line_key IS NOT NULL
            AND downstream_route_measure IS NOT NULL),
       placed AS (
         SELECT r.m, w.dm AS w_dm, w.um AS w_um, c.dm AS c_dm, c.um AS c_um
           FROM r
           LEFT JOIN LATERAL (SELECT s.dm, s.um FROM %2$s s
                               WHERE s.blk = r.blk AND s.dm BETWEEN r.m - 1 AND r.m + %3$s
                               ORDER BY s.dm LIMIT 1) w ON TRUE
           LEFT JOIN LATERAL (SELECT s.dm, s.um FROM %2$s s
                               WHERE s.blk = r.blk AND r.m >= s.dm AND r.m < s.um
                               ORDER BY s.dm DESC LIMIT 1) c ON TRUE),
       t AS (
         SELECT CASE WHEN w_dm IS NOT NULL THEN 'start_window'
                     WHEN c_dm IS NOT NULL THEN 'containing' ELSE 'none' END AS branch,
                coalesce(w_dm, c_dm) AS dm, coalesce(w_um, c_um) AS um, m
           FROM placed)
       SELECT '%1$s' AS wsg, branch, count(*) AS n,
              percentile_cont(0.5) WITHIN GROUP (ORDER BY dm - m) AS median_start_offset_m,
              percentile_cont(0.5) WITHIN GROUP (ORDER BY um - dm) AS median_segment_m,
              percentile_cont(0.5) WITHIN GROUP (ORDER BY um - m) / 1000 AS median_km_above,
              percentile_cont(0.5) WITHIN GROUP (ORDER BY m - dm) / 1000 AS median_km_below
         FROM t GROUP BY branch ORDER BY branch", w, p[2], start_window_m)))))
  }
}

bind <- function(key, template) {
  d <- do.call(rbind, res[[key]])
  if (is.null(d)) template else d
}
segments <- bind("segments", data.frame())
superset <- bind("superset", data.frame())
access_open <- bind("access_open", data.frame())
census <- bind("census", data.frame())
write_csv(segments, "segments.csv")
write_csv(superset, "superset.csv")
write_csv(bind("access_km", data.frame()), "access_km.csv")
write_csv(access_open, "access_open.csv")
write_csv(bind("access_differences", data.frame(
  wsg = character(), sp = character(), blk = numeric(), dm = numeric(), um = numeric(),
  len = numeric(), access_full = numeric(), access_minimal = numeric())),
  "access_differences.csv")
write_csv(bind("crossing", data.frame()), "crossing_fields.csv")
write_csv(bind("overlay", data.frame(
  wsg = character(), schema = character(), sp = character(), stage = character(),
  covered_km = numeric(), applied_km = numeric(),
  under_applied_km = numeric())), "overlay.csv")
write_csv(bind("connectivity", data.frame()), "connectivity.csv")
write_csv(bind("gradient", data.frame()), "gradient.csv")
write_csv(census, "breaks_census.csv")
write_csv(bind("placement", data.frame()), "placement.csv")
DBI::dbDisconnect(conn)

print(segments); print(superset)
print(access_open[access_open$n_violation > 0 | access_open$n_sliver > 0, ])
print(census)

defects <- c(
  if (!builds_ok) "the builds are not of one clean commit with the expected tokens (builds.csv)",
  if (any(superset$n_unmatched > 0)) "a minimal cut has no full cut within tol_m (superset.csv)",
  if (any(access_open$n_violation > 0)) "a species' access differs outside slivers (access_open.csv)",
  if (any(segments$n_full_no_access > 0 | segments$n_minimal_no_access > 0)) "a segment has no streams_access row (segments.csv)",
  if (any(census$source %in% c("none", "working_schema_not_this_build"))) "a minimal break has no named source (breaks_census.csv)")
if (length(defects)) stop("DEFECT: ", paste(defects, collapse = "; "), call. = FALSE)
message("[proof] every check passed for ", paste(wsgs, collapse = ", "))
