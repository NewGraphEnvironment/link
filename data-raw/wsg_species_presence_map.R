#!/usr/bin/env Rscript
# wsg_species_presence_map.R — an interactive map of the fish records the
# proposed presence record rules would drop (link#402, decision session).
#
# Read-only against docker fwapg (:5432): session temp tables only. Writes no
# tracker, no presence table and nothing in the repo; the map goes to --out.
#
#   Rscript data-raw/wsg_species_presence_map.R
#     [--out=$TMPDIR/presence_map_402.html] [--gpkg=<path>.gpkg]
#     [--cache=<path>.rds]
#
# The records are measured again here with .lnk_presence_measures(), as
# wsg_species_presence_check.R does (about the same inputs and the same
# counting rule), so the script needs only the database and this checkout.
# --cache saves the measures, points and barriers on the first run and reads
# them on later ones (delete it after the database changes).
#
# Layers, each a rule proposed for the review, applied to counting records
# (the rules the review chose: research/species_presence.md, "The first review"):
#   barrier, salmon and steelhead  CH CM CO PK SK ST above the nearest natural
#                                  barrier that blocks them, with at most 2
#                                  counting records of the lift pool above it
#   barrier applied to KO          the same rule on kokanee (option C)
#   KO, no lake above barrier      KO above a blocking barrier with no lake
#                                  above it
#   elevation, salmon/steelhead    CH CM CO PK SK ST above 1,400 m
#   elevation, other species       every other species above 1,400 m
#   known errors                   the data_error rows of
#                                  observation_exclusions.csv (rings). They are
#                                  excluded, so never counting records and never
#                                  in a rule layer: a ring with no point inside
#                                  is not a miss (recall.csv scores the rules
#                                  against them)
#   barriers                       the barrier each barrier-rule record sits
#                                  behind, by kind
# Colour is the barrier kind (falls, gradient, user definite) for the barrier
# layers. Each popup has the record, its measures, the cell's presence and
# tracker flag, and whether the rule empties the cell.

pkgload::load_all(quiet = TRUE)
suppressPackageStartupMessages({
  library(DBI)
  library(sf)
  library(mapgl)
})
sf::sf_use_s2(FALSE)

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit) == 0L) default else sub(paste0("^--", name, "="), "", hit[1])
}
known <- c("--out", "--gpkg", "--cache")
bad <- args[!sub("=.*$", "", args) %in% known]
if (length(bad) > 0L) stop("unknown arguments: ", paste(bad, collapse = " "))
out <- arg("out", file.path(Sys.getenv("TMPDIR", "."), "presence_map_402.html"))
gpkg <- arg("gpkg", "")
cache <- arg("cache", "")

anad <- c("CH", "CM", "CO", "PK", "SK", "ST")
elev_max <- 1400
class_above_max <- 2L

cfg <- lnk_config("default")
loaded <- lnk_load_overrides(cfg)
excl <- loaded$observation_exclusions
dir_log <- "data-raw/logs/presence_check_402"
nz <- function(x) ifelse(is.na(x), "", x)

# ---- measures, points, barriers ---------------------------------------------
if (nzchar(cache) && file.exists(cache)) {
  message("reading ", cache)
  got <- readRDS(cache)
} else {
  conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "postgres")
  zones <- utils::read.csv(file.path(dir_log, "evidence", "hist_zones.csv"),
                           colClasses = "character")
  sockeye <- utils::read.csv(file.path(cfg$dir, "overrides",
                                       "dfo_known_sockeye_lakes.csv"))$waterbody_poly_id
  sp_barrier <- c(anad, "KO")
  pf <- loaded$parameters_fresh
  pools <- stats::setNames(lapply(sp_barrier, function(s) {
    trimws(strsplit(pf$observation_species[pf$species_code == s], ";")[[1]])
  }), sp_barrier)
  message("measuring records (several minutes)")
  meas <- .lnk_presence_measures(
    conn, zones, sp_barrier, pools, sockeye,
    excl_keys = .lnk_observation_exclusion_keys(loaded),
    incl_keys = excl$observation_key[excl$release_include %in% c(TRUE, "t")],
    year_min = 1950L)

  # The barrier each record sits behind: pg_temp.pm_bar is left in this
  # session by .lnk_presence_measures(). A barrier is persisted once per
  # group holding it, so one row per position.
  bars <- dbGetQuery(conn, "
SELECT DISTINCT ON (p.observation_key) p.observation_key,
       b.id_barrier, b.barrier_source, b.barrier_subtype,
       b.watershed_group_code AS barrier_wsg,
       ST_X(ST_Transform(ST_Force2D(b.geom), 4326)) AS lon,
       ST_Y(ST_Transform(ST_Force2D(b.geom), 4326)) AS lat
FROM pg_temp.pm_bar p
JOIN fresh_default.barriers b
  ON b.blue_line_key = p.b_blk AND b.downstream_route_measure = p.b_drm
 AND b.barrier_source = p.barrier_source
ORDER BY p.observation_key, b.watershed_group_code, b.id_barrier")

  pts <- dbGetQuery(conn, "
SELECT observation_key, observation_date, source, gazetted_name,
       waterbody_type, match_type, round(distance_to_stream::numeric, 1) AS distance_to_stream,
       ST_X(ST_Transform(ST_Force2D(geom), 4326)) AS lon,
       ST_Y(ST_Transform(ST_Force2D(geom), 4326)) AS lat
FROM bcfishobs.observations")
  dbDisconnect(conn)
  got <- list(meas = meas, bars = bars, pts = pts)
  if (nzchar(cache)) saveRDS(got, cache)
}
meas <- got$meas
stopifnot(!anyDuplicated(meas$observation_key),
          !anyDuplicated(got$pts$observation_key),
          !anyDuplicated(got$bars$observation_key))

# ---- the proposed rules -----------------------------------------------------
m <- meas[meas$counting %in% TRUE, ]
blocked <- !is.na(m$barrier_below)
few_above <- blocked & m$n_class_above <= class_above_max
high <- !is.na(m$elevation_m) & m$elevation_m > elev_max
rules <- list(
  bar_anad = list(label = "Barrier rule: salmon and steelhead",
                  hit = few_above & m$species_code %in% anad, on = TRUE),
  bar_ko = list(label = "Barrier rule applied to KO",
                hit = few_above & m$species_code == "KO", on = FALSE),
  ko_lake = list(label = "KO above a barrier, no lake above",
                 hit = blocked & m$species_code == "KO" & is.na(m$rearing_lake_ha),
                 on = TRUE),
  elev_anad = list(label = "Above 1,400 m: salmon and steelhead",
                   hit = high & m$species_code %in% anad, on = TRUE),
  elev_other = list(label = "Above 1,400 m: other species",
                    hit = high & !m$species_code %in% anad, on = FALSE)
)

# ---- cell context -----------------------------------------------------------
pres <- loaded$wsg_species_presence
tracker <- utils::read.csv(file.path(cfg$dir, "wsg_species_presence_review.csv"),
                           colClasses = "character")
cell <- paste(m$watershed_group_code, m$species_code)
col <- tolower(m$species_code)
row <- match(m$watershed_group_code, pres$watershed_group_code)
present <- vapply(seq_len(nrow(m)), function(i) {
  if (is.na(row[i]) || !col[i] %in% names(pres)) return(NA)
  pres[[col[i]]][row[i]] %in% c("t", TRUE)
}, logical(1))
flag <- tracker$flag[match(cell, paste(tracker$watershed_group_code,
                                       tracker$species_code))]
n_cell <- as.integer(table(cell)[cell])
status <- ifelse(is.na(present), "species not in the presence table",
          ifelse(present, "marked present", "not marked"))
status <- ifelse(is.na(flag), status, paste0(status, "; tracker: ", flag))

known_err <- excl$observation_key[excl$data_error %in% c(TRUE, "t")]

# ---- layers -----------------------------------------------------------------
kind_col <- c(FALLS = "#1f77b4", GRADIENT = "#ff7f0e", USER_DEFINITE = "#9467bd")
rule_col <- c(elev_anad = "#d62728", elev_other = "#8c564b")
fmt <- function(x, d = 0) ifelse(is.na(x), "", format(round(x, d), big.mark = ","))

layer_sf <- function(key) {
  r <- rules[[key]]
  i <- which(r$hit)
  d <- m[i, ]
  drop_cell <- as.integer(table(cell[i])[cell[i]])
  d$cell_records <- n_cell[i]
  d$rule_empties_cell <- drop_cell == n_cell[i]
  d$cell_status <- status[i]
  d <- merge(d, got$pts, by = "observation_key", all.x = TRUE)
  d <- d[!is.na(d$lon), ]
  gmap <- sprintf("https://www.google.com/maps/@%.6f,%.6f,1200m/data=!3m1!1e3",
                  d$lat, d$lon)
  d$popup <- paste0(
    "<b>", d$species_code, " in ", d$watershed_group_code, "</b> (", r$label, ")<br>",
    "date ", d$observation_date, "; ", htmltools::htmlEscape(d$source), "<br>",
    "waterbody ", htmltools::htmlEscape(nz(d$gazetted_name)), " (", d$waterbody_type, ")<br>",
    "elevation ", fmt(d$elevation_m), " m; gradient ", fmt(d$gradient, 3), "<br>",
    ifelse(is.na(d$barrier_below), "no blocking barrier below",
           paste0("barrier below: ", d$barrier_below, "; class records above it: ",
                  d$n_class_above)),
    ifelse(d$species_code == "KO" & !is.na(d$barrier_below),
           paste0("; largest lake above it: ",
                  ifelse(is.na(d$rearing_lake_ha), "none", paste(fmt(d$rearing_lake_ha), "ha"))),
           ""), "<br>",
    "cell: ", d$cell_status, "; ", d$cell_records, " counting records",
    ifelse(d$rule_empties_cell, " <b>(this rule drops all of them)</b>", ""), "<br>",
    "match: ", htmltools::htmlEscape(d$match_type), " (", d$distance_to_stream, " m)<br>",
    "key ", d$observation_key, " · <a href='", gmap, "' target='_blank'>imagery (Google)</a>")
  d$rule <- key
  sf::st_as_sf(d, coords = c("lon", "lat"), crs = 4326)
}
lyr <- lapply(stats::setNames(names(rules), names(rules)), layer_sf)

bar_keys <- unique(c(lyr$bar_anad$observation_key, lyr$bar_ko$observation_key,
                     lyr$ko_lake$observation_key))
b <- got$bars[got$bars$observation_key %in% bar_keys, ]
# id_barrier is numbered within a group, so one position held by several
# groups is one row per group: keep one per kind and position.
b <- b[!duplicated(paste(b$barrier_source, b$lon, b$lat)), ]
b$popup <- paste0("<b>", b$barrier_source, "</b> ", nz(b$barrier_subtype),
                  "<br>held by ", b$barrier_wsg, "<br>id ", b$id_barrier)
b_sf <- sf::st_as_sf(b, coords = c("lon", "lat"), crs = 4326)

err <- merge(data.frame(observation_key = known_err), got$pts, by = "observation_key")
err <- merge(err, meas[, c("observation_key", "species_code", "watershed_group_code")],
             by = "observation_key")
err$popup <- paste0("<b>known data error</b>: ", err$species_code, " in ",
                    err$watershed_group_code, "<br>key ", err$observation_key)
err_sf <- sf::st_as_sf(err, coords = c("lon", "lat"), crs = 4326)

for (k in names(rules)) {
  message(sprintf("%-11s %6d records, %3d cells emptied", k, nrow(lyr[[k]]),
                  length(unique(paste(lyr[[k]]$watershed_group_code,
                                      lyr[[k]]$species_code)[lyr[[k]]$rule_empties_cell]))))
}
message(sprintf("barriers %d, known errors %d", nrow(b_sf), nrow(err_sf)))

# ---- map --------------------------------------------------------------------
kind_expr <- match_expr("barrier_below", values = names(kind_col),
                        stops = unname(kind_col), default = "#7f7f7f")
map <- maplibre(style = carto_style("positron"), bounds = sf::st_bbox(lyr$bar_anad)) |>
  add_raster_source(
    id = "esri", tileSize = 256,
    tiles = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
    attribution = "Esri, Maxar, Earthstar Geographics") |>
  add_raster_layer(id = "Imagery (Esri)", source = "esri", visibility = "none")

ids <- character()
for (k in names(rules)) {
  id <- rules[[k]]$label
  ids <- c(ids, id)
  map <- map |> add_circle_layer(
    id = id, source = lyr[[k]],
    circle_color = if (k %in% names(rule_col)) rule_col[[k]] else kind_expr,
    circle_radius = list("interpolate", list("linear"), list("zoom"), 4, 3, 12, 7),
    circle_stroke_color = "#ffffff", circle_stroke_width = 0.8,
    circle_opacity = 0.85, popup = "popup",
    visibility = if (rules[[k]]$on) "visible" else "none")
}
map <- map |>
  add_circle_layer(id = "Known data errors", source = err_sf,
                   circle_color = "#000000", circle_opacity = 0,
                   circle_radius = 9, circle_stroke_color = "#000000",
                   circle_stroke_width = 2, popup = "popup") |>
  add_circle_layer(id = "Barriers behind barrier-rule records", source = b_sf,
                   circle_color = match_expr("barrier_source", values = names(kind_col),
                                             stops = unname(kind_col)),
                   circle_radius = 4, circle_stroke_color = "#000000",
                   circle_stroke_width = 1.5, popup = "popup", min_zoom = 7) |>
  add_layers_control(position = "top-left", collapsible = TRUE,
                     layers = c(ids, "Known data errors",
                                "Barriers behind barrier-rule records", "Imagery (Esri)")) |>
  add_legend("Barrier below the record", values = c("Falls", "Gradient", "User definite"),
             colors = unname(kind_col), type = "categorical", patch_shape = "circle",
             position = "bottom-left") |>
  add_legend("Above 1,400 m", values = c("Salmon and steelhead", "Other species"),
             colors = unname(rule_col), type = "categorical", patch_shape = "circle",
             position = "bottom-left", add = TRUE)

htmlwidgets::saveWidget(map, out, selfcontained = TRUE, title = "Presence record rules")
message("map: ", normalizePath(out))

if (nzchar(gpkg)) {
  if (file.exists(gpkg)) unlink(gpkg)
  for (k in names(lyr)) {
    sf::st_write(lyr[[k]][, setdiff(names(lyr[[k]]), "popup")], gpkg, layer = k, quiet = TRUE)
  }
  sf::st_write(b_sf[, setdiff(names(b_sf), "popup")], gpkg, layer = "barriers", quiet = TRUE)
  sf::st_write(err_sf[, setdiff(names(err_sf), "popup")], gpkg, layer = "known_errors", quiet = TRUE)
  message("gpkg: ", normalizePath(gpkg))
}
