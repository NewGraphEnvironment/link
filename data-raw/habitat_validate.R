#!/usr/bin/env Rscript
# habitat_validate.R — score persisted runs against fish observations (link#283).
#
# For each bundle:schema pair, runs lnk_habitat_validate() over every WSG the
# schema has `streams_access` for (or --wsgs=), at each buffer, and writes
# aggregates only. With two bundles, it diffs them on the WSGs both hold, after
# asserting both retained the same observations.
#
# Read-only against docker fwapg (:5432): session temp tables only.
#
#   Rscript data-raw/habitat_validate.R \
#     --bundles=default:fresh_default,bcfishpass:fresh \
#     [--wsgs=MORR,BULK] [--species=CH,BT] [--buffers=0,100] [--out=<dir>]
#
# Absences (optional): with LNK_KNOWLEDGE_DIR pointing at the private
# `knowledge` repo, FISS data-submission sites that were sampled (effort
# recorded or no-fish-captured) become absences of a species when either
#   - no fish were caught (`nfc`) and no species is listed, or
#   - species are listed, none is the species (BT: Bull Trout or Dolly
#     Varden, pooled as the observations are), and none is a taxon that could
#     be it (`Unidentified Species`; `Salmon (General)` for CH;
#     `Unidentifiable Trout` for BT).
# A site that caught fish but listed no species (most sites with an empty
# list) says nothing about which species were absent, and is left out.
# Sites snap to the nearest FWA stream within 100 m, the distance bcfishobs
# A/B matches (the observations kept) use. `knowledge` is private and link is public, so no site row is
# written here, only counts.
#
# Writes to data-raw/logs/habitat_validate_283/ (or --out):
#   summary.csv        lnk_habitat_validate()$summary, all bundles x buffers
#   totals.csv         summed over each bundle's WSGs, per species x stage x buffer
#   totals_shared.csv  the same over the WSGs both bundles hold (two bundles)
#   misses.csv         miss-reason counts per bundle x species x stage (buffer 0)
#   misses_binned.csv  missed locations by gradient x width bin (buffer 0)
#   diff.csv           bundle A vs B per WSG x species x stage x buffer
#   stamp.txt          environment stamp, including per-schema run-log coverage

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
split_csv <- function(x) {
  if (is.null(x)) return(NULL)
  v <- trimws(strsplit(x, ",")[[1]])
  v[nzchar(v)]
}

bundles_arg <- opt("bundles")
if (is.null(bundles_arg)) {
  stop("--bundles=<config>:<schema>[,<config>:<schema>] is required: a ",
       "bundle's pipeline.schema does not say which schema it built",
       call. = FALSE)
}
bundles <- do.call(rbind, lapply(split_csv(bundles_arg), function(b) {
  p <- strsplit(b, ":", fixed = TRUE)[[1]]
  if (length(p) != 2L || !all(nzchar(p))) {
    stop("bad --bundles entry '", b, "': want <config>:<schema>", call. = FALSE)
  }
  data.frame(config = p[1], schema = p[2], stringsAsFactors = FALSE)
}))
if (nrow(bundles) > 2L) stop("at most two bundles", call. = FALSE)
if (anyDuplicated(bundles$schema)) {
  stop("the two bundles name the same schema", call. = FALSE)
}
species <- toupper(split_csv(opt("species", "CH,BT")))
if (length(species) == 0L) stop("--species is empty", call. = FALSE)
buffers <- as.numeric(split_csv(opt("buffers", "0,100")))
if (anyNA(buffers) || !0 %in% buffers) {
  stop("--buffers must be numbers and include 0 (the misses are buffer 0)",
       call. = FALSE)
}
wsgs_arg <- toupper(split_csv(opt("wsgs")))
dir_out <- opt("out", file.path("data-raw", "logs", "habitat_validate_283"))
fs::dir_create(dir_out)
# Clear this script's outputs first, so a partial or one-bundle run cannot
# leave an older stamp or diff beside new CSVs.
outputs <- c("summary.csv", "totals.csv", "totals_shared.csv", "misses.csv",
             "misses_binned.csv", "diff.csv", "stamp.txt")
unlink(file.path(dir_out, outputs))

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")

# -- WSGs per bundle: those with access built ---------------------------------
bundle_wsgs <- lapply(seq_len(nrow(bundles)), function(i) {
  w <- dbGetQuery(conn, sprintf(
    "SELECT DISTINCT watershed_group_code FROM %s.streams_access
      ORDER BY 1", bundles$schema[i]))$watershed_group_code
  # toupper(NULL) is character(0), so test length, not NULL.
  if (length(wsgs_arg) > 0L) {
    miss <- setdiff(wsgs_arg, w)
    if (length(miss) > 0L) {
      stop(bundles$schema[i], " has no access for: ",
           paste(miss, collapse = ", "), call. = FALSE)
    }
    w <- wsgs_arg
  }
  w
})
if (nrow(bundles) == 2L &&
    length(intersect(bundle_wsgs[[1]], bundle_wsgs[[2]])) == 0L) {
  stop("the two bundles share no WSGs", call. = FALSE)
}

# -- absences from FISS sites (optional) --------------------------------------
fiss_absences <- function() {
  dir_k <- Sys.getenv("LNK_KNOWLEDGE_DIR", "")
  if (!nzchar(dir_k)) return(NULL)
  files <- Sys.glob(file.path(dir_k, "data", "*", "fiss_sites_*_all.csv"))
  if (length(files) == 0L) {
    stop("LNK_KNOWLEDGE_DIR set but no fiss_sites_*_all.csv under ", dir_k,
         call. = FALSE)
  }
  num <- function(x) suppressWarnings(as.numeric(x))
  sites <- do.call(rbind, lapply(files, function(f) {
    d <- utils::read.csv(f, colClasses = "character", na.strings = c("", "NA"))
    data.frame(site_key = d$site_key,
               utm_zone = num(d$utm_zone), utm_easting = num(d$utm_easting),
               utm_northing = num(d$utm_northing),
               sampled = d$effort_recorded %in% "TRUE" | d$nfc %in% "TRUE",
               nfc = d$nfc %in% "TRUE",
               species_list = ifelse(is.na(d$species_list), "",
                                     d$species_list),
               stringsAsFactors = FALSE)
  }))
  sites <- sites[sites$sampled & !is.na(sites$utm_zone) &
                   !is.na(sites$utm_easting) & !is.na(sites$utm_northing), ]
  # A report spanning two groups appears in both snapshots under one key.
  sites <- sites[!duplicated(sites$site_key), ]
  dbWriteTable(conn, "hv_fiss", sites[, c("site_key", "utm_zone",
                                          "utm_easting", "utm_northing")],
               temporary = TRUE, overwrite = TRUE)
  snap <- dbGetQuery(conn, "
    WITH p AS (
      SELECT site_key,
             st_transform(st_setsrid(st_makepoint(utm_easting, utm_northing),
                                     26900 + utm_zone::int), 3005) AS geom
        FROM pg_temp.hv_fiss)
    SELECT p.site_key, f.watershed_group_code, f.blue_line_key,
           f.downstream_route_measure
             + st_linelocatepoint(st_force2d(f.geom), p.geom) * f.length_metre
             AS downstream_route_measure
      FROM p
      JOIN LATERAL (
        SELECT f.watershed_group_code, f.blue_line_key,
               f.downstream_route_measure, f.length_metre, f.geom
          FROM whse_basemapping.fwa_stream_networks_sp f
         WHERE st_dwithin(f.geom, p.geom, 100)
           AND f.edge_type <> 1425
         ORDER BY f.geom <-> p.geom
         LIMIT 1) f ON true")
  sites <- merge(sites, snap, by = "site_key")
  # Only the snapshot WSGs were surveyed; a site snapping across a boundary
  # would give its neighbour a partial count that reads as coverage.
  covered <- toupper(basename(dirname(files)))
  sites <- sites[sites$watershed_group_code %in% covered, ]
  listed <- nzchar(trimws(sites$species_list))
  no_fish <- sites$nfc & !listed
  caught <- list(
    CH = grepl("Chinook", sites$species_list, ignore.case = TRUE),
    BT = grepl("Bull Trout|Dolly Varden", sites$species_list,
               ignore.case = TRUE))
  maybe <- list(
    CH = grepl("Unidentified|Salmon \\(General\\)", sites$species_list,
               ignore.case = TRUE),
    BT = grepl("Unidentified|Unidentifiable Trout", sites$species_list,
               ignore.case = TRUE))
  sp_abs <- intersect(species, names(caught))
  if (length(setdiff(species, sp_abs)) > 0L) {
    message("no FISS absence rule for: ",
            paste(setdiff(species, sp_abs), collapse = ", "),
            "; not assessed")
  }
  if (length(sp_abs) == 0L) {
    return(structure(list(), reason = "no FISS absence rule for the species"))
  }
  is_abs_of <- function(sp) no_fish | (listed & !caught[[sp]] & !maybe[[sp]])
  n_abs <- vapply(sp_abs, function(sp) sum(is_abs_of(sp)), integer(1))
  out <- do.call(rbind, lapply(sp_abs, function(sp) {
    s <- sites[is_abs_of(sp), ]
    data.frame(watershed_group_code = s$watershed_group_code,
               blue_line_key = s$blue_line_key,
               downstream_route_measure = s$downstream_route_measure,
               species_code = rep(sp, nrow(s)), stringsAsFactors = FALSE)
  }))
  attr(out, "n_sites_sampled") <- nrow(sites)
  attr(out, "n_absence_sites") <- n_abs
  attr(out, "covered") <- sort(unique(covered))
  sha <- suppressWarnings(tryCatch(
    system2("git", c("-C", shQuote(dir_k), "rev-parse", "--short", "HEAD"),
            stdout = TRUE, stderr = FALSE),
    error = function(e) character(0)))
  attr(out, "knowledge_sha") <- if (length(sha) == 1L) sha else "not a git repo"
  out
}
absences <- fiss_absences()
abs_note <- attr(absences, "reason")
if (!is.null(abs_note)) absences <- NULL

# -- validate ------------------------------------------------------------------
runs <- list()
for (i in seq_len(nrow(bundles))) {
  cfg <- lnk_config(bundles$config[i])
  loaded <- suppressWarnings(lnk_load_overrides(cfg))
  for (b in buffers) {
    message(sprintf("validating %s:%s, %d WSGs, buffer %s m",
                    bundles$config[i], bundles$schema[i],
                    length(bundle_wsgs[[i]]), b))
    runs[[length(runs) + 1L]] <- c(
      lnk_habitat_validate(conn, aoi = bundle_wsgs[[i]], cfg = cfg,
                           loaded = loaded, species = species,
                           schema = bundles$schema[i], buffer_m = b,
                           absences = absences),
      list(bundle = paste0(bundles$config[i], ":", bundles$schema[i])))
  }
}

summary <- do.call(rbind, lapply(runs, `[[`, "summary"))
utils::write.csv(summary, file.path(dir_out, "summary.csv"), row.names = FALSE,
                 na = "")

# -- totals over WSGs ------------------------------------------------------------
cols_n <- grep("^n_", names(summary), value = TRUE)
cols_km <- c("accessible_km", "spawning_km", "rearing_km")
key <- c("schema", "config_name", "buffer_m", "species_code", "stage")
make_totals <- function(s) {
  grp <- interaction(s[key], drop = TRUE, lex.order = TRUE)
  out <- do.call(rbind, lapply(split(s, grp), function(d) {
    # Absence columns stay NA when not assessed; everything else sums.
    sums <- lapply(d[c(cols_n, cols_km)], function(x) {
      if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
    })
    cbind(d[1, key], as.data.frame(sums), n_wsg = nrow(d),
          n_wsg_logged = sum(d$run_logged))
  }))
  for (k in c("accessible", "spawning", "rearing", "rearing_any", "habitat")) {
    out[[paste0("share_", k)]] <- ifelse(
      out$n_obs > 0, out[[paste0("n_", k)]] / out$n_obs, NA_real_)
  }
  out$share_spawning_outside_uhc <- ifelse(
    out$n_obs_outside_uhc_spawn > 0,
    out$n_spawning_outside_uhc / out$n_obs_outside_uhc_spawn, NA_real_)
  out$share_rearing_any_outside_uhc <- ifelse(
    out$n_obs_outside_uhc_rear > 0,
    out$n_rearing_any_outside_uhc / out$n_obs_outside_uhc_rear, NA_real_)
  rownames(out) <- NULL
  out
}
utils::write.csv(make_totals(summary), file.path(dir_out, "totals.csv"),
                 row.names = FALSE, na = "")
shared <- Reduce(intersect, bundle_wsgs)
if (nrow(bundles) == 2L) {
  # Each bundle's own totals are over different WSG sets; compare these.
  utils::write.csv(
    make_totals(summary[summary$watershed_group_code %in% shared, ]),
    file.path(dir_out, "totals_shared.csv"), row.names = FALSE, na = "")
}

# -- misses (buffer 0) -------------------------------------------------------------
# `any` is captured when the location is spawning or any rearing, matching
# totals' n_habitat; its reason is then the rear reason.
stage_rows <- function(obs) {
  base <- data.frame(
    species_code = obs$species_code, gradient = obs$gradient,
    channel_width = obs$channel_width, edge_type = obs$edge_type,
    is_spawn = obs$is_spawn, is_rear = obs$is_rear,
    reason_any = ifelse(obs$spawning %in% TRUE, NA_character_,
                        obs$miss_reason_rear),
    reason_spawn = obs$miss_reason_spawn,
    reason_rear = obs$miss_reason_rear, stringsAsFactors = FALSE)
  pick <- function(d, stage, col) {
    cbind(data.frame(stage = rep(stage, nrow(d))), d[, c("species_code",
      "gradient", "channel_width", "edge_type")], reason = d[[col]])
  }
  rbind(pick(base, "any", "reason_any"),
        pick(base[base$is_spawn, , drop = FALSE], "spawn", "reason_spawn"),
        pick(base[base$is_rear, , drop = FALSE], "rear", "reason_rear"))
}
breaks_g <- c(-Inf, 0.0025, 0.01, 0.02, 0.03, 0.045, 0.055, 0.07, 0.105,
              0.135, 0.15, 0.20, 0.25, Inf)
breaks_w <- c(0, 1.5, 2, 3, 4, 6, 10, 20, Inf)
misses <- list()
binned <- list()
for (r in runs[vapply(runs, function(r) r$summary$buffer_m[1] == 0, TRUE)]) {
  d <- stage_rows(r$observations)
  d$reason[is.na(d$reason)] <- "captured"
  tab <- as.data.frame(table(stage = d$stage, species_code = d$species_code,
                             reason = d$reason), stringsAsFactors = FALSE)
  tab <- tab[tab$Freq > 0, ]
  names(tab)[names(tab) == "Freq"] <- "n"
  misses[[length(misses) + 1L]] <- cbind(
    data.frame(bundle = rep(r$bundle, nrow(tab))), tab)
  m <- d[!d$reason %in% c("captured", "no_segment"), ]
  m$gradient_bin <- as.character(cut(m$gradient, breaks_g, right = TRUE))
  m$width_bin <- ifelse(is.na(m$channel_width), "NULL",
                        as.character(cut(m$channel_width, breaks_w,
                                         right = FALSE)))
  b <- as.data.frame(table(stage = m$stage, species_code = m$species_code,
                           reason = m$reason, gradient_bin = m$gradient_bin,
                           width_bin = m$width_bin, useNA = "ifany"),
                     stringsAsFactors = FALSE)
  b <- b[b$Freq > 0, ]
  names(b)[names(b) == "Freq"] <- "n"
  binned[[length(binned) + 1L]] <- cbind(
    data.frame(bundle = rep(r$bundle, nrow(b))), b)
}
utils::write.csv(do.call(rbind, misses), file.path(dir_out, "misses.csv"),
                 row.names = FALSE, na = "")
utils::write.csv(do.call(rbind, binned), file.path(dir_out, "misses_binned.csv"),
                 row.names = FALSE, na = "")

# -- diff (two bundles, shared WSGs) --------------------------------------------------
if (nrow(bundles) == 2L) {
  # Both bundles must be scored on the same observations, or the diff mixes
  # a filter difference into a model difference.
  keys <- lapply(runs[vapply(runs, function(r) r$summary$buffer_m[1] == 0,
                             TRUE)], function(r) {
    o <- r$observations[r$observations$watershed_group_code %in% shared, ]
    sort(paste(o$species_code, o$watershed_group_code, o$observation_key))
  })
  if (!identical(keys[[1]], keys[[2]])) {
    stop("the two bundles retained different observations on shared WSGs (",
         length(setdiff(keys[[1]], keys[[2]])), " only in A, ",
         length(setdiff(keys[[2]], keys[[1]])), " only in B)", call. = FALSE)
  }
  cols_cmp <- c("n_obs", "n_accessible", "n_spawning", "n_rearing",
                "n_rearing_any", "share_accessible", "share_spawning",
                "share_rearing", "share_rearing_any",
                "share_spawning_outside_uhc", "share_rearing_any_outside_uhc",
                "accessible_km", "spawning_km", "rearing_km")
  by <- c("watershed_group_code", "species_code", "stage", "buffer_m")
  a <- summary[summary$schema == bundles$schema[1] &
                 summary$watershed_group_code %in% shared, c(by, cols_cmp)]
  b <- summary[summary$schema == bundles$schema[2] &
                 summary$watershed_group_code %in% shared, c(by, cols_cmp)]
  d <- merge(a, b, by = by, suffixes = c("_a", "_b"))
  for (cl in setdiff(cols_cmp, "n_obs")) {
    d[[paste0(cl, "_delta")]] <- d[[paste0(cl, "_b")]] - d[[paste0(cl, "_a")]]
  }
  d <- cbind(data.frame(
    bundle_a = rep(paste0(bundles$config[1], ":", bundles$schema[1]), nrow(d)),
    bundle_b = rep(paste0(bundles$config[2], ":", bundles$schema[2]), nrow(d))),
    d)
  d <- d[order(d$buffer_m, d$species_code, d$stage, d$watershed_group_code), ]
  utils::write.csv(d, file.path(dir_out, "diff.csv"), row.names = FALSE,
                   na = "")
}

# -- stamp ---------------------------------------------------------------------------
fresh_sha <- .lnk_pkg_git_sha("fresh")
link_dirty <- length(system(paste(
  "git status --porcelain -- R inst/extdata/configs",
  "data-raw/habitat_validate.R"), intern = TRUE)) > 0L
log_lines <- vapply(seq_len(nrow(bundles)), function(i) {
  s <- bundles$schema[i]
  w <- bundle_wsgs[[i]]
  if (!dbExistsTable(conn, Id(schema = s, table = "log"))) {
    return(sprintf("bundle %s:%s — %d WSGs scored; no run log",
                   bundles$config[i], s, length(w)))
  }
  lg <- dbGetQuery(conn, sprintf(
    "SELECT count(DISTINCT watershed_group_code) AS n_wsg,
            string_agg(DISTINCT coalesce(fresh_version, 'NA'), ', ') AS fresh,
            min(date_start)::date AS first, max(date_start)::date AS last
       FROM %s.log WHERE watershed_group_code = ANY($1)", s),
    params = list(paste0("{", paste(w, collapse = ","), "}")))
  sprintf(paste("bundle %s:%s — %d WSGs scored; %d with a run-log row",
                "(fresh %s, %s to %s); the rest predate the log"),
          bundles$config[i], s, length(w), as.integer(lg$n_wsg),
          lg$fresh, lg$first, lg$last)
}, character(1))
stamp <- c(
  sprintf("date: %s", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
  sprintf("link: %s @ %s%s", utils::packageVersion("link"),
          system("git rev-parse --short HEAD", intern = TRUE),
          if (link_dirty) " (dirty)" else ""),
  sprintf("fresh installed (builds the miss-reason predicates): %s @ %s",
          utils::packageVersion("fresh"),
          if (is.na(fresh_sha)) "no recorded sha" else fresh_sha),
  "db: docker fwapg localhost:5432",
  log_lines,
  sprintf("species: %s; buffers: %s m", paste(species, collapse = ","),
          paste(buffers, collapse = ",")),
  sprintf("bcfishobs.observations rows: %s",
          dbGetQuery(conn, "SELECT count(*) FROM bcfishobs.observations")[[1]]),
  if (!is.null(abs_note)) sprintf("absences: none (%s)", abs_note) else
  if (is.null(absences)) "absences: none (LNK_KNOWLEDGE_DIR unset)" else
    sprintf(paste("absences: %d sampled FISS sites snapped within the",
                  "snapshot WSGs (%s); usable as absences, before presence:",
                  "%s; other WSGs report NA; knowledge @ %s"),
            attr(absences, "n_sites_sampled"),
            paste(attr(absences, "covered"), collapse = ","),
            paste(names(attr(absences, "n_absence_sites")),
                  attr(absences, "n_absence_sites"), collapse = ", "),
            attr(absences, "knowledge_sha")))
writeLines(stamp, file.path(dir_out, "stamp.txt"))

dbDisconnect(conn)
message("wrote ", dir_out)
