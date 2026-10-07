#!/usr/bin/env Rscript
# query_width_mad_equivalent.R — the mean annual discharge at which streams
# persisted in `fresh_default` reach `default`'s channel-width minima, and the
# MAD minima that converts them to (link#307).
#
# `default` gives BT, GR, KO and RB a channel-width floor (spawning 2 m, GR
# 4 m; rearing 1.5 m) and, before #307, no MAD range, so under the `mad`
# habitat model they kept no stream habitat. #307 converts the width floor
# itself to discharge, so `cw` and `mad` inside `default` test one biological
# stream size two ways. #302 measured the relation once with an ad-hoc query
# (data-raw/logs/habitat_thresholds_302/width_mad_equivalent.txt); this is
# that query with a producer.
#
# Method, as #302 ran it:
#   - segments: `schema`.streams on stream edges (1000/1100/2000/2300)
#     outside any waterbody (waterbody_key IS NULL), whose channel_width is
#     MODELLED (not measured, not a river polygon), so the relation is the
#     one `cw` applies where it has nothing better;
#   - bin: channel_width within +/- 0.1 m of each width minimum;
#   - mad_m3s joined from whse_basemapping.fwa_stream_networks_discharge on
#     linear_feature_id (unique there); segments with none are left out;
#   - the converted minimum is the bin's median, floored to two significant
#     figures (#302's rounding rule, data-raw/query_habitat_thresholds_mad.R).
#   - Only stages a stream rule inherits a size range for (rules.yaml): KO
#     rearing is lake-only, so KO converts its spawning floor only.
#   - Every `*_mad_max` is open (9999), as #302 decided.
#
#   Rscript data-raw/query_width_mad_equivalent.R \
#     [--species=BT,GR,KO,RB] [--schema=fresh_default]
#     [--out=data-raw/logs/habitat_thresholds_307]
#
# Writes to --out:
#   width_mad_equivalent.csv   n, q25, median, q75 of mad_m3s per width bin
#   width_mad_conversion.csv   per species x stage: width minimum -> MAD minimum
#   stamp.txt                  environment stamp
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
split_csv <- function(x) {
  v <- toupper(trimws(strsplit(x, ",")[[1]]))
  v[nzchar(v)]
}

species <- split_csv(opt("species", "BT,GR,KO,RB"))
schema <- opt("schema", "fresh_default")
dir_out <- opt("out", file.path("data-raw", "logs", "habitat_thresholds_307"))
fs::dir_create(dir_out)
half_bin <- 0.1
edges_stream <- c(1000L, 1100L, 2000L, 2300L)

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")

cfg <- lnk_config("default")
th <- utils::read.csv(cfg$files$parameters_habitat_thresholds$path)
rules <- yaml::read_yaml(cfg$rules)
if (!all(species %in% th$species_code)) {
  stop("--species not in default's thresholds: ",
       paste(setdiff(species, th$species_code), collapse = ", "), call. = FALSE)
}

# A stage converts only if a stream rule inherits its size range (the test
# data-raw/query_habitat_thresholds_mad.R applies).
inherits_size <- function(sp, stage) {
  r <- rules[[sp]][[stage]]
  any(vapply(r, function(x) {
    !identical(x$thresholds, FALSE) && is.null(x$waterbody_type) &&
      any(c(1000L, 1100L) %in% as.integer(unlist(x$edge_types_explicit)))
  }, logical(1)))
}
floor_signif2 <- function(x) {
  if (is.na(x) || x <= 0) return(if (is.na(x)) NA_real_ else 0)
  e <- 10^(floor(log10(x)) - 1)
  signif(floor(round(x / e, 9)) * e, 2)
}

conv <- do.call(rbind, lapply(species, function(sp) {
  do.call(rbind, lapply(c("spawn", "rear"), function(stage) {
    w <- th[th$species_code == sp, paste0(stage, "_channel_width_min")]
    if (!inherits_size(sp, stage) || is.na(w)) return(NULL)
    data.frame(species_code = sp, stage = stage, width_min = w)
  }))
}))
widths <- sort(unique(conv$width_min))
message("width minima to convert: ", paste(widths, collapse = ", "), " m")

# -- the width bins -----------------------------------------------------------
q <- sprintf("
  WITH bins(w_bin) AS (VALUES %s)
  SELECT b.w_bin, count(*) AS n,
         percentile_cont(0.25) WITHIN GROUP (ORDER BY d.mad_m3s) AS q25,
         percentile_cont(0.50) WITHIN GROUP (ORDER BY d.mad_m3s) AS median,
         percentile_cont(0.75) WITHIN GROUP (ORDER BY d.mad_m3s) AS q75
    FROM bins b
    JOIN %s.streams s
      ON s.channel_width BETWEEN b.w_bin - %s AND b.w_bin + %s
    JOIN whse_basemapping.fwa_stream_networks_discharge d
      ON d.linear_feature_id = s.linear_feature_id
   WHERE s.edge_type IN (%s)
     AND s.waterbody_key IS NULL
     AND s.channel_width_source = 'MODELLED'
     AND d.mad_m3s IS NOT NULL
   GROUP BY b.w_bin ORDER BY b.w_bin",
  paste0("(", widths, "::double precision)", collapse = ", "), schema,
  half_bin, half_bin, paste(edges_stream, collapse = ", "))
bins <- dbGetQuery(conn, q)
if (!setequal(bins$w_bin, widths)) {
  stop("a width bin returned no segments: ",
       paste(setdiff(widths, bins$w_bin), collapse = ", "), call. = FALSE)
}
bins$n <- as.integer(bins$n)
bins$mad_min <- vapply(bins$median, floor_signif2, numeric(1))

conv$mad_median <- bins$median[match(conv$width_min, bins$w_bin)]
conv$mad_min <- bins$mad_min[match(conv$width_min, bins$w_bin)]
conv$mad_max <- 9999
conv$parameter <- paste0(conv$stage, "_mad_min")

utils::write.csv(bins, file.path(dir_out, "width_mad_equivalent.csv"),
                 row.names = FALSE)
utils::write.csv(conv[, c("species_code", "stage", "parameter", "width_min",
                          "mad_median", "mad_min", "mad_max")],
                 file.path(dir_out, "width_mad_conversion.csv"),
                 row.names = FALSE)
print(bins, row.names = FALSE)
print(conv, row.names = FALSE)

# -- stamp --------------------------------------------------------------------
fresh_sha <- .lnk_pkg_git_sha("fresh")
link_dirty <- length(system(paste(
  "git status --porcelain -- R inst/extdata/configs/default",
  "data-raw/query_width_mad_equivalent.R"), intern = TRUE)) > 0L
writeLines(c(
  sprintf("date: %s", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
  sprintf("link: %s @ %s%s", utils::packageVersion("link"),
          system("git rev-parse --short HEAD", intern = TRUE),
          if (link_dirty) " (dirty)" else ""),
  sprintf("fresh installed: %s @ %s", utils::packageVersion("fresh"),
          if (is.na(fresh_sha)) "no recorded sha" else fresh_sha),
  "db: docker fwapg localhost:5432",
  sprintf("schema: %s; %s WSGs persisted", schema,
          dbGetQuery(conn, sprintf(
            "SELECT count(DISTINCT watershed_group_code) FROM %s.streams",
            schema))[[1]]),
  sprintf("discharge rows: %s (%s with mad_m3s)",
          dbGetQuery(conn, "SELECT count(*) FROM whse_basemapping.fwa_stream_networks_discharge")[[1]],
          dbGetQuery(conn, "SELECT count(mad_m3s) FROM whse_basemapping.fwa_stream_networks_discharge")[[1]]),
  sprintf("bin: modelled channel_width within +/- %s m; edges %s; outside waterbodies",
          half_bin, paste(edges_stream, collapse = "/"))),
  file.path(dir_out, "stamp.txt"))

dbDisconnect(conn)
