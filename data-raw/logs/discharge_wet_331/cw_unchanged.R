# link#331 Phase 5: `cw` classification does not depend on the discharge source.
# Prepare once under default_tuned, then re-join mad_m3s from each source on the
# same working schema and re-classify; compare per segment and per
# linear_feature_id, and assert mad_m3s differs between the passes.
#   Rscript data-raw/logs/discharge_wet_331/cw_unchanged.R <repo> <aoi> <out_dir>
args <- commandArgs(trailingOnly = TRUE)
repo <- args[1]; aoi <- args[2]; out <- args[3]
suppressMessages(pkgload::load_all(repo, quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config("default_tuned")
stopifnot(identical(link:::.lnk_discharge_source(cfg), "wet"))
loaded <- suppressWarnings(lnk_load_overrides(cfg))
schema <- paste0("zz_cw331_", tolower(aoi))
t0 <- Sys.time()
DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema))
lnk_pipeline_setup(conn, schema, overwrite = TRUE)
lnk_pipeline_load(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
lnk_pipeline_prepare(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema,
                     conn_tunnel = conn)
lnk_pipeline_crossings(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
lnk_pipeline_break(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
message("prepared in ", round(difftime(Sys.time(), t0, units = "mins"), 1), " min")

fill <- link:::.lnk_discharge_fill_applied(cfg, aoi)
pass <- function(source) {
  link:::.lnk_discharge_join(conn, paste0(schema, ".streams"), aoi,
                             fill = fill, source = source)
  lnk_pipeline_classify(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
  lnk_pipeline_connect(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
  h <- DBI::dbGetQuery(conn, sprintf(
    "SELECT h.*, s.linear_feature_id, s.mad_m3s
       FROM %1$s.streams_habitat h
       JOIN %1$s.streams s USING (id_segment)
      ORDER BY h.id_segment, h.species_code", schema))
  h
}
a <- pass("fwapg")
b <- pass("wet")

stopifnot(nrow(a) == nrow(b), identical(a$id_segment, b$id_segment),
          identical(a$species_code, b$species_code))
cols_hab <- setdiff(names(a), c("mad_m3s"))
# Column by column, vectorised: a row differs if any habitat column differs
# (NA-safe: NA on one side only counts as a difference).
seg_diff <- Reduce(`|`, lapply(cols_hab, function(col) {
  x <- a[[col]]; y <- b[[col]]
  xor(is.na(x), is.na(y)) | (!is.na(x) & !is.na(y) & x != y)
}))
by_lfid <- function(h) {
  aggregate(cbind(spawning = as.integer(h$spawning), rearing = as.integer(h$rearing)),
            by = list(linear_feature_id = h$linear_feature_id, species_code = h$species_code),
            FUN = sum)
}
la <- by_lfid(a); lb <- by_lfid(b)
la <- la[order(la$linear_feature_id, la$species_code), ]
lb <- lb[order(lb$linear_feature_id, lb$species_code), ]
mad_differs <- sum(xor(is.na(a$mad_m3s), is.na(b$mad_m3s)) |
                     (!is.na(a$mad_m3s) & !is.na(b$mad_m3s) & a$mad_m3s != b$mad_m3s))
res <- data.frame(
  aoi = aoi, config = cfg$name, fill_applied = fill,
  rows = nrow(a), species = paste(sort(unique(a$species_code)), collapse = ","),
  rows_habitat_differ = sum(seg_diff),
  lfid_rows = nrow(la),
  lfid_rows_differ = sum(la$spawning != lb$spawning | la$rearing != lb$rearing),
  rows_mad_differ = mad_differs,
  mad_na_fwapg = sum(is.na(a$mad_m3s)), mad_na_wet = sum(is.na(b$mad_m3s)),
  link_head = system2("git", c("-C", repo, "rev-parse", "--short", "HEAD"), stdout = TRUE),
  run_at = format(Sys.time(), tz = "UTC", usetz = TRUE))
print(res, row.names = FALSE)
dir.create(out, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(res, file.path(out, sprintf("cw_unchanged_%s.csv", tolower(aoi))),
                 row.names = FALSE)
stopifnot(res$rows_habitat_differ == 0, res$lfid_rows_differ == 0, res$rows_mad_differ > 0)
DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", schema))
DBI::dbDisconnect(conn)
message("cw unchanged: PASS")
