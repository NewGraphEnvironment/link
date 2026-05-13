# data-raw/compare_bcfishpass_wsg.R
#
# Thin wrapper around `link::lnk_compare_wsg(reference = "bcfishpass")`
# for the targets pipeline in data-raw/_targets.R and the orchestrator
# scripts (run_provincial_parity.R, trifecta_*.sh).
#
# Responsibilities NOT in the library:
#   - resolve local fwapg + bcfp tunnel env vars into DBI connections
#   - emit the lnk_stamp markdown block (run provenance for logs)
#   - rename `ref_value` -> `bcfishpass_value` on the rollup so existing
#     RDS consumers (compare_rollups.R, regress_dams_isolation.R,
#     rule_flexibility_render.R) and cached `provincial_parity/*.rds`
#     read without a column rename
#
# Return shape (`with_mapping_code = FALSE`, the default):
#   tibble with columns wsg, species, habitat_type, unit, link_value,
#   bcfishpass_value, diff_pct — same shape `_targets.R` has consumed
#   since v0.5.0.
#
# Return shape (`with_mapping_code = TRUE`):
#   list(rollup = <renamed tibble>, mapping_code = <per-species stats>)

compare_bcfishpass_wsg <- function(wsg, config, dams = TRUE,
                                   species = NULL,
                                   cleanup_working = TRUE,
                                   with_mapping_code = FALSE) {
  stopifnot(
    is.character(wsg), length(wsg) == 1L, nzchar(wsg),
    grepl("^[A-Z]{3,5}$", wsg),
    inherits(config, "lnk_config"),
    is.logical(dams), length(dams) == 1L,
    is.null(species) || is.character(species),
    is.logical(cleanup_working), length(cleanup_working) == 1L,
    is.logical(with_mapping_code), length(with_mapping_code) == 1L
  )

  conn <- DBI::dbConnect(RPostgres::Postgres(),
    host = "localhost", port = 5432, dbname = "fwapg",
    user = "postgres", password = "postgres")
  on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

  tunnel_pass <- Sys.getenv("PG_PASS_SHARE", "")
  if (!nzchar(tunnel_pass)) {
    stop("PG_PASS_SHARE env var is not set - needed to connect to the ",
         "bcfishpass reference tunnel (localhost:63333). Set it in ",
         "~/.Renviron.", call. = FALSE)
  }
  conn_ref <- DBI::dbConnect(RPostgres::Postgres(),
    host = "localhost", port = 63333, dbname = "bcfishpass",
    user = Sys.getenv("PG_USER_SHARE", "newgraph"),
    password = tunnel_pass)
  on.exit(try(DBI::dbDisconnect(conn_ref), silent = TRUE), add = TRUE)

  # Stamp the run before doing any work - captures config provenance,
  # software versions, and DB snapshot counts so two runs on the same
  # state can be diffed for what changed.
  stamp <- link::lnk_stamp(config, conn = conn, aoi = wsg)
  message(format(stamp, "markdown"))

  loaded <- link::lnk_load_overrides(config)

  result <- link::lnk_compare_wsg(
    conn              = conn,
    aoi               = wsg,
    cfg               = config,
    loaded            = loaded,
    reference         = "bcfishpass",
    with_mapping_code = with_mapping_code,
    conn_ref          = conn_ref,
    species           = species,
    dams              = dams,
    cleanup_working   = cleanup_working
  )

  # Rename ref_value -> bcfishpass_value for downstream RDS consumers.
  # The library is reference-agnostic (ref_value); the data-raw wrapper
  # is bcfishpass-specific by name and contract.
  rollup <- result$rollup
  names(rollup)[names(rollup) == "ref_value"] <- "bcfishpass_value"

  if (isTRUE(with_mapping_code)) {
    list(rollup = rollup, mapping_code = result$mapping_code)
  } else {
    rollup
  }
}
