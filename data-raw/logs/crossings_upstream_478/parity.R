# Per-crossing upstream habitat, link against bcfishpass (link#321, #478).
#
#   LNK_REF_PGHOST=... LNK_REF_PGPORT=... LNK_REF_PGDATABASE=... \
#   LNK_REF_PGUSER=... LNK_REF_PGPASSWORD=... \
#   Rscript data-raw/logs/crossings_upstream_478/parity.R --schema=<persist> --wsgs=ADMS,BULK
#
# Link's side: lnk_aggregate() over each group's working-schema crossings
# (`working_<wsg>.crossings`, kept by wsg_run_one.R) and barriers
# (`working_<wsg>.barriers_anthropogenic`), reading the persist schema
# `--schema`, built under the bcfishpass config with every group upstream of
# the targets persisted. bcfishpass's side: bcfishpass.crossings_upstream_habitat
# on the reference database, connected only through LNK_REF_PG*.
#
# Compared per main-stem crossing (blue_line_key = watershed_key: bcfishpass
# reports no other) and species, on the crossings both sides hold:
#   spawning       link spawning_km                 vs <sp>_spawning_km
#   rearing        link rearing_km + rearing_lake_connection_km
#                                                    vs <sp>_rearing_km
#                  (bcfishpass counts lake connection lines in rearing)
#   *_below        the same, below the next barriers upstream
# Writes per_crossing.csv, distribution.csv and stamp.csv beside this script.
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) {
  a <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(a) != 1L) stop("--", name, "= is required", call. = FALSE)
  sub(paste0("^--", name, "="), "", a)
}
schema <- opt("schema")
wsgs <- toupper(strsplit(opt("wsgs"), ",", fixed = TRUE)[[1]])
out <- "data-raw/logs/crossings_upstream_478"
env <- function(k) {
  v <- Sys.getenv(k)
  if (!nzchar(v)) stop(k, " is not set", call. = FALSE)
  v
}

pkgload::load_all(quiet = TRUE)
lnk <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                      port = 5432L, user = "postgres", password = "postgres")
ref <- DBI::dbConnect(RPostgres::Postgres(), host = env("LNK_REF_PGHOST"),
                      port = as.integer(env("LNK_REF_PGPORT")),
                      dbname = env("LNK_REF_PGDATABASE"),
                      user = env("LNK_REF_PGUSER"),
                      password = env("LNK_REF_PGPASSWORD"))
num64 <- function(d) {
  d[] <- lapply(d, function(x) if (inherits(x, "integer64")) as.numeric(x) else x)
  d
}
species <- c("BT", "CH", "CM", "CO", "PK", "SK", "ST", "WCT")

timing <- list()
link_side <- do.call(rbind, lapply(wsgs, function(w) {
  ws <- paste0("working_", tolower(w))
  sp <- species[vapply(species, function(s) DBI::dbExistsTable(
    lnk, DBI::Id(schema = schema, table = paste0("streams_habitat_", tolower(s)))), TRUE)]
  to <- paste0(ws, ".crossings_upstream_habitat")
  t0 <- Sys.time()
  lnk_aggregate(lnk, paste0(ws, ".crossings"), schema = schema, to = to,
                config = "bcfishpass", species = sp,
                barriers = paste0(ws, ".barriers_anthropogenic"))
  timing[[w]] <<- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  d <- num64(DBI::dbGetQuery(lnk, sprintf(
    "SELECT u.*, c.watershed_group_code AS wsg, c.blue_line_key = c.watershed_key AS main_stem
       FROM %s u JOIN %s.crossings c USING (aggregated_crossings_id)", to, ws)))
  d$aggregated_crossings_id <- as.character(d$aggregated_crossings_id)
  d
}))

ref_side <- num64(DBI::dbGetQuery(ref, sprintf(
  "SELECT * FROM bcfishpass.crossings_upstream_habitat WHERE watershed_group_code IN (%s)",
  paste(sprintf("'%s'", wsgs), collapse = ", "))))
ref_side$aggregated_crossings_id <- as.character(ref_side$aggregated_crossings_id)

pairs <- do.call(rbind, lapply(unique(link_side$species_code), function(sp) {
  s <- tolower(sp)
  l <- link_side[link_side$species_code == sp & link_side$main_stem %in% TRUE, ]
  rc <- function(stem) {
    v <- ref_side[[paste0(s, "_", stem)]]
    if (is.null(v)) rep(NA_real_, nrow(ref_side)) else v
  }
  r <- data.frame(aggregated_crossings_id = ref_side$aggregated_crossings_id,
                  bcfp_spawning = rc("spawning_km"), bcfp_rearing = rc("rearing_km"),
                  bcfp_spawning_below = rc("spawning_belowupstrbarriers_km"),
                  bcfp_rearing_below = rc("rearing_belowupstrbarriers_km"))
  m <- merge(l, r, by = "aggregated_crossings_id")
  data.frame(
    wsg = m$wsg, aggregated_crossings_id = m$aggregated_crossings_id, species_code = sp,
    link_spawning = m$spawning_km, bcfp_spawning = m$bcfp_spawning,
    link_rearing = m$rearing_km + m$rearing_lake_connection_km, bcfp_rearing = m$bcfp_rearing,
    link_spawning_below = m$spawning_belowupstrbarriers_km,
    bcfp_spawning_below = m$bcfp_spawning_below,
    link_rearing_below = m$rearing_belowupstrbarriers_km +
      m$rearing_lake_connection_belowupstrbarriers_km,
    bcfp_rearing_below = m$bcfp_rearing_below)
}))
pairs <- pairs[order(pairs$wsg, pairs$species_code, pairs$aggregated_crossings_id,
                     method = "radix"), ]
for (k in c("spawning", "rearing", "spawning_below", "rearing_below")) {
  pairs[[paste0("diff_", k)]] <- round(pairs[[paste0("link_", k)]] - pairs[[paste0("bcfp_", k)]], 3)
}

dist <- do.call(rbind, lapply(split(pairs, list(pairs$wsg, pairs$species_code), drop = TRUE),
  function(g) do.call(rbind, lapply(c("spawning", "rearing", "spawning_below", "rearing_below"),
    function(k) {
      d <- g[[paste0("diff_", k)]]
      b <- g[[paste0("bcfp_", k)]]
      if (all(is.na(b))) return(NULL)
      data.frame(wsg = g$wsg[1], species_code = g$species_code[1], metric = k,
                 n_crossings = sum(!is.na(d)),
                 n_within_0_1km = sum(abs(d) <= 0.1, na.rm = TRUE),
                 n_within_1pct = sum(abs(d) <= pmax(0.01 * abs(b), 0.001), na.rm = TRUE),
                 median_diff_km = stats::median(d, na.rm = TRUE),
                 p05_diff_km = unname(stats::quantile(d, 0.05, na.rm = TRUE)),
                 p95_diff_km = unname(stats::quantile(d, 0.95, na.rm = TRUE)),
                 max_abs_diff_km = max(abs(d), na.rm = TRUE),
                 link_total_km = round(sum(g[[paste0("link_", k)]], na.rm = TRUE), 2),
                 bcfp_total_km = round(sum(b, na.rm = TRUE), 2))
    }))))
rownames(dist) <- NULL

stamp <- data.frame(
  link_sha = system2("git", c("rev-parse", "--short=8", "HEAD"), stdout = TRUE),
  # load_all() read this tree's R/, inst/ and DESCRIPTION, against that commit
  link_dirty = length(system2("git", c("status", "--porcelain", "--untracked-files=no",
                                       "--", "R", "inst", "DESCRIPTION"), stdout = TRUE)) > 0L,
  schema = schema,
  num64(DBI::dbGetQuery(ref, "SELECT model_run_id, date_completed::text AS date_completed,
                                     model_version
                                FROM bcfishpass.log ORDER BY model_run_id DESC LIMIT 1")),
  aggregate_minutes = paste(names(timing), round(unlist(timing), 2), collapse = "; "),
  n_link_crossings = nrow(unique(link_side[, c("wsg", "aggregated_crossings_id")])),
  n_link_main_stem = nrow(unique(link_side[link_side$main_stem %in% TRUE,
                                           c("wsg", "aggregated_crossings_id")])),
  n_bcfp_rows = nrow(ref_side),
  run_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
DBI::dbDisconnect(ref)
DBI::dbDisconnect(lnk)
utils::write.csv(pairs, file.path(out, "per_crossing.csv"), row.names = FALSE)
utils::write.csv(dist, file.path(out, "distribution.csv"), row.names = FALSE)
utils::write.csv(stamp, file.path(out, "stamp.csv"), row.names = FALSE)
print(dist)
print(stamp)
