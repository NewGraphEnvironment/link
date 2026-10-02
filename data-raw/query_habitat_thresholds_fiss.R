# FISS site-level evidence for habitat thresholds: CH and BT gradient and
# width (link#284), and the snapped segment's mean annual discharge for the
# MAD ranges (link#302).
#
# Provincial FISS data submissions (the .xls behind FISS sample sites), as
# parsed into per-WSG snapshots by the `knowledge` repo (scripts 0200-0220).
# Each site carries field-measured channel width and gradient, effort, and the
# species caught, including explicit no-fish-captured records. That gives what
# bcfishobs cannot: absences at measured sites.
#
# Two questions:
#   1. At measured sites, do CH / BT presence and absence separate at the
#      current width and gradient cutoffs?
#   2. How far is the modelled channel width the cutoffs actually test from the
#      width a crew measured at the same place?
#
# Read-only against docker fwapg (:5432); temp tables only.
#
#   LNK_KNOWLEDGE_DIR=~/Projects/repo/knowledge Rscript data-raw/query_habitat_thresholds_fiss.R \
#     [--species=CH,BT] [--out=data-raw/logs/habitat_thresholds_284]
#
# --species takes any of CH, BT, GR, KO, RB (matched on the common name in the
# FISS species list). The defaults reproduce #284's run.
#
# Writes to --out:
#   (site rows only when LNK_FISS_SITES_OUT names a path: `knowledge` is a
#   private repo and link is public, so only aggregates are committed here)
#   fiss_presence.csv     presence vs absence against current cutoffs, per species,
#                         plus the snapped segment's mad_m3s (`segment mad_m3s`)
#   fiss_width_error.csv  measured vs segment channel width, by segment width source
#   fiss_stamp.txt        knowledge SHA, WSGs, counts

pkgload::load_all(quiet = TRUE)
suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
})

opt <- function(name, default) {
  a <- grep(paste0("^--", name, "="), commandArgs(trailingOnly = TRUE),
            value = TRUE)
  if (length(a) == 0L) default else sub(paste0("^--", name, "="), "", a[length(a)])
}
dir_out <- opt("out", file.path("data-raw", "logs", "habitat_thresholds_284"))
# FISS lists species by common name.
species_names <- c(CH = "Chinook", BT = "Bull Trout", GR = "Arctic Grayling",
                   KO = "Kokanee", RB = "Rainbow Trout")
species <- toupper(trimws(strsplit(opt("species", "CH,BT"), ",")[[1]]))
# The default --out is #284's committed evidence; another species set must
# not overwrite it.
if (!any(grepl("^--out=", commandArgs(trailingOnly = TRUE))) &&
    !identical(species, c("CH", "BT"))) {
  stop("--species other than CH,BT needs an explicit --out", call. = FALSE)
}
if (!all(species %in% names(species_names))) {
  stop("--species takes ", paste(names(species_names), collapse = ", "),
       call. = FALSE)
}
fs::dir_create(dir_out)
dir_knowledge <- Sys.getenv("LNK_KNOWLEDGE_DIR",
                            fs::path_expand("~/Projects/repo/knowledge"))
stopifnot(fs::dir_exists(file.path(dir_knowledge, "data")))

# Every WSG the knowledge repo has FISS snapshots for; `fresh` is the one
# persist schema holding all of them (UNTH and LNTH are not in fresh_default).
wsgs <- fs::dir_ls(file.path(dir_knowledge, "data"), type = "directory") |>
  fs::path_file() |>
  Filter(f = function(w) fs::file_exists(
    file.path(dir_knowledge, "data", w, sprintf("fiss_sites_%s_all.csv", w))))
schema <- "fresh"

cfg <- lnk_config("default")
th <- readr::read_csv(cfg$files$parameters_habitat_thresholds$path,
                      show_col_types = FALSE) |>
  filter(species_code %in% species)
presence <- readr::read_csv(cfg$files$wsg_species_presence$path,
                            show_col_types = FALSE,
                            col_types = readr::cols(.default = "c"))

num <- function(x) suppressWarnings(as.numeric(x))
sites <- bind_rows(lapply(wsgs, function(w) {
  readr::read_csv(
    file.path(dir_knowledge, "data", w, sprintf("fiss_sites_%s_all.csv", w)),
    show_col_types = FALSE, col_types = readr::cols(.default = "c"), na = c("", "NA"))
})) |>
  transmute(
    site_key, report_id, watershed_group_code = toupper(watershed_group_code),
    survey_date, utm_zone = num(utm_zone), utm_easting = num(utm_easting),
    utm_northing = num(utm_northing),
    channel_width_m = num(avg_channel_width_m),
    wetted_width_m = num(avg_wetted_width_m),
    # Named percent, holds proportions: all 469 values are <= 0.43 (median
    # 0.08) and 0.4 sits on 0.6 m headwater channels. Read as a proportion;
    # the naming is reported upstream rather than corrected here.
    gradient = num(average_gradient_percent),
    effort_recorded = effort_recorded %in% "TRUE",
    nfc = nfc %in% "TRUE",
    species_list)
for (sp in species) {
  sites[[tolower(sp)]] <- grepl(species_names[[sp]], sites$species_list,
                                ignore.case = TRUE)
}

# An absence is a site that was sampled with recorded effort (or an explicit
# no-fish-captured) and did not catch the species.
sites <- sites |>
  mutate(sampled = effort_recorded | nfc)

# -- snap to the modelled network --------------------------------------------
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
pts <- sites |>
  filter(!is.na(utm_zone), !is.na(utm_easting), !is.na(utm_northing)) |>
  distinct(site_key, watershed_group_code, utm_zone, utm_easting, utm_northing)
dbWriteTable(conn, "t_fiss", pts, temporary = TRUE, overwrite = TRUE)
snap <- dbGetQuery(conn, sprintf("
  WITH p AS (
    SELECT site_key, watershed_group_code,
           st_transform(st_setsrid(st_makepoint(utm_easting, utm_northing),
                                   26900 + utm_zone::int), 3005) AS geom
    FROM t_fiss)
  SELECT p.site_key, p.watershed_group_code, s.id_segment, s.gradient AS seg_gradient,
         s.channel_width AS seg_channel_width, s.channel_width_source,
         s.stream_order, s.edge_type, s.dist_m,
         (SELECT d.mad_m3s FROM whse_basemapping.fwa_stream_networks_discharge d
           WHERE d.linear_feature_id = s.linear_feature_id) AS seg_mad_m3s
  FROM p
  JOIN LATERAL (
    SELECT s.id_segment, s.gradient, s.channel_width, s.channel_width_source,
           s.stream_order, s.edge_type, s.linear_feature_id,
           st_distance(s.geom, p.geom) AS dist_m
    FROM %s.streams s
    WHERE s.watershed_group_code = p.watershed_group_code
      AND st_dwithin(s.geom, p.geom, 150)
    ORDER BY s.geom <-> p.geom
    LIMIT 1) s ON true", schema))
dbDisconnect(conn)

# A report spanning two groups appears in both snapshots under one site_key.
# Keep one row per site: the one that snapped closest.
sites <- sites |>
  left_join(snap, by = c("site_key", "watershed_group_code")) |>
  arrange(site_key, is.na(dist_m), dist_m) |>
  distinct(site_key, .keep_all = TRUE)
path_sites <- Sys.getenv("LNK_FISS_SITES_OUT", "")
if (nzchar(path_sites)) readr::write_csv(sites, path_sites, na = "")

# -- presence vs absence against current cutoffs ------------------------------
pres_one <- function(sp) {
  t <- th[th$species_code == sp, ]
  col <- tolower(sp)
  in_range <- presence$watershed_group_code[presence[[col]] %in% "t"]
  d <- sites |>
    filter(watershed_group_code %in% in_range, sampled | .data[[col]]) |>
    mutate(outcome = if_else(.data[[col]], "present", "absent"))
  bind_rows(
    d |> filter(!is.na(channel_width_m)) |>
      group_by(outcome) |>
      summarise(metric = "channel_width_m (site measured)", n = n(),
                p05 = quantile(channel_width_m, 0.05), p50 = median(channel_width_m),
                p95 = quantile(channel_width_m, 0.95),
                share_below_spawn_min = mean(channel_width_m < t$spawn_channel_width_min),
                share_below_rear_min = mean(channel_width_m < t$rear_channel_width_min),
                .groups = "drop"),
    d |> filter(!is.na(gradient)) |>
      group_by(outcome) |>
      summarise(metric = "gradient (site measured)", n = n(),
                p05 = quantile(gradient, 0.05), p50 = median(gradient),
                p95 = quantile(gradient, 0.95),
                share_above_spawn_max = mean(gradient > t$spawn_gradient_max),
                share_above_rear_max = mean(gradient > t$rear_gradient_max),
                .groups = "drop"),
    d |> filter(!is.na(seg_channel_width), dist_m <= 50) |>
      group_by(outcome) |>
      summarise(metric = "segment channel_width (snapped <= 50 m)", n = n(),
                p05 = quantile(seg_channel_width, 0.05), p50 = median(seg_channel_width),
                p95 = quantile(seg_channel_width, 0.95),
                share_below_spawn_min = mean(seg_channel_width < t$spawn_channel_width_min),
                share_below_rear_min = mean(seg_channel_width < t$rear_channel_width_min),
                .groups = "drop"),
    # Discharge is modelled, never measured at the site: the segment's value.
    d |> filter(!is.na(seg_mad_m3s), dist_m <= 50) |>
      group_by(outcome) |>
      summarise(metric = "segment mad_m3s (snapped <= 50 m)", n = n(),
                p05 = quantile(seg_mad_m3s, 0.05), p50 = median(seg_mad_m3s),
                p95 = quantile(seg_mad_m3s, 0.95),
                share_below_spawn_min = mean(seg_mad_m3s < t$spawn_mad_min),
                share_below_rear_min = mean(seg_mad_m3s < t$rear_mad_min),
                .groups = "drop")) |>
    mutate(species_code = sp, wsgs = paste(intersect(in_range, unique(d$watershed_group_code)),
                                           collapse = " "), .before = 1)
}
readr::write_csv(bind_rows(lapply(species, pres_one)),
                 file.path(dir_out, "fiss_presence.csv"), na = "")

# -- modelled vs measured width at the same place ------------------------------
err <- sites |>
  filter(!is.na(channel_width_m), !is.na(seg_channel_width), dist_m <= 50) |>
  mutate(ratio = seg_channel_width / channel_width_m,
         diff_m = seg_channel_width - channel_width_m) |>
  group_by(channel_width_source) |>
  summarise(
            # fwapg builds FIELD_MEASURMENT widths from FISS sample sites, so
            # that row compares FISS with itself; only MODELLED is a test.
            independent = !identical(first(channel_width_source), "FIELD_MEASURMENT"),
            n = n(),
            median_measured_m = median(channel_width_m),
            median_segment_m = median(seg_channel_width),
            median_ratio = median(ratio),
            p10_ratio = quantile(ratio, 0.10), p90_ratio = quantile(ratio, 0.90),
            median_abs_diff_m = median(abs(diff_m)),
            share_within_25pct = mean(abs(ratio - 1) <= 0.25),
            .groups = "drop")
readr::write_csv(err, file.path(dir_out, "fiss_width_error.csv"), na = "")

git1 <- function(dir, args) system(sprintf("git -C %s %s", shQuote(dir), args), intern = TRUE)
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
vintage <- dbGetQuery(conn, sprintf(
  "SELECT string_agg(watershed_group_code || ' ' || date_end::date || ' fresh ' || fresh_version
                     || '@' || coalesce(left(fresh_sha, 7), 'NA'),
                     '; ' ORDER BY watershed_group_code)
   FROM (SELECT DISTINCT ON (watershed_group_code) watershed_group_code, date_end, fresh_version,
                fresh_sha
         FROM %s.log WHERE watershed_group_code = ANY($1)
         ORDER BY watershed_group_code, date_end DESC) x", schema),
  params = list(paste0("{", paste(toupper(wsgs), collapse = ","), "}")))[[1]]
dbDisconnect(conn)
writeLines(c(
  sprintf("date: %s", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
  sprintf("link: %s @ %s%s", utils::packageVersion("link"),
          git1(".", "rev-parse --short HEAD"),
          if (length(git1(".", paste("status --porcelain -- R inst/extdata/configs/default",
                                     "data-raw/query_habitat_thresholds_fiss.R"))))
            " (dirty: R/, configs/default or this script uncommitted)" else ""),
  "db: docker fwapg localhost:5432",
  sprintf("thresholds: %s", fs::path_rel(cfg$files$parameters_habitat_thresholds$path,
                                          fs::path_abs("."))),
  sprintf("knowledge: %s @ %s%s", fs::path_file(dir_knowledge),
          git1(dir_knowledge, "rev-parse --short HEAD"),
          if (length(git1(dir_knowledge, "status --porcelain -- data"))) " (dirty data/)" else ""),
  sprintf("wsgs: %s", paste(toupper(wsgs), collapse = " ")),
  sprintf("species: %s", paste(species, collapse = ",")),
  sprintf("schema snapped to: %s (nearest segment within 150 m, same WSG); last logged run per WSG: %s",
          schema, if (is.na(vintage)) "none logged" else vintage),
  sprintf("sites: %d; with measured channel width: %d; with gradient: %d; snapped: %d",
          nrow(sites), sum(!is.na(sites$channel_width_m)), sum(!is.na(sites$gradient)),
          sum(!is.na(sites$id_segment)))),
  file.path(dir_out, "fiss_stamp.txt"))
message("wrote ", dir_out)
