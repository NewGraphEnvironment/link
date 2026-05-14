# data-raw/wsg_compare.R
#
# Compare-only wrapper around `link::lnk_compare_rollup(reference = "bcfishpass")`
# for the targets pipeline in data-raw/_targets.R and the orchestrator
# scripts (run_provincial_parity.R, trifecta_*.sh).
#
# Reads persisted state in <persist_schema>.streams + streams_habitat_<sp>
# (written by `wsg_pipeline_run.R` or any prior modelling call), queries
# the bcfishpass tunnel, returns a renamed long-format rollup tibble.
#
# Responsibilities NOT in the library:
#   - resolve local fwapg + bcfp tunnel env vars into DBI connections
#   - rename `ref_value` -> `bcfishpass_value` on the rollup so existing
#     RDS consumers (compare_rollups.R, regress_dams_isolation.R,
#     rule_flexibility_render.R) and cached `provincial_parity/*.rds`
#     read without a column rename
#
# Return shape: tibble with columns wsg, species, habitat_type, unit,
# link_value, bcfishpass_value, diff_pct.

wsg_compare <- function(wsg, config, species = NULL,
                        reference = "bcfishpass") {
  stopifnot(
    is.character(wsg), length(wsg) == 1L, nzchar(wsg),
    grepl("^[A-Z]{3,5}$", wsg),
    inherits(config, "lnk_config"),
    is.null(species) || is.character(species),
    is.character(reference), length(reference) == 1L, nzchar(reference)
  )

  conn <- DBI::dbConnect(RPostgres::Postgres(),
    host = "localhost", port = 5432, dbname = "fwapg",
    user = "postgres", password = "postgres")
  on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

  conn_ref <- NULL
  if (reference == "bcfishpass") {
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
  }

  rollup <- link::lnk_compare_rollup(
    conn      = conn,
    aoi       = wsg,
    cfg       = config,
    reference = reference,
    conn_ref  = conn_ref,
    species   = species
  )

  # Rename ref_value -> bcfishpass_value for downstream RDS consumers
  # when the reference IS bcfishpass. The library is reference-agnostic
  # (ref_value); this wrapper is bcfishpass-specific by name when that
  # reference is selected.
  if (reference == "bcfishpass") {
    names(rollup)[names(rollup) == "ref_value"] <- "bcfishpass_value"
  }
  rollup
}
