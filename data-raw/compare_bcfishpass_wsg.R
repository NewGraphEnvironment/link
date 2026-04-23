# data-raw/compare_bcfishpass_wsg.R
#
# Per-AOI target function for the targets pipeline in data-raw/_targets.R.
# Runs the six lnk_pipeline_* phases for one watershed group and returns
# a small comparison tibble against the bcfishpass reference on the
# tunnel DB.
#
# Return is KB-scale only — safe to ship over SSH for distributed runs.
# Heavy tables (fresh.streams, working_<wsg>.*) stay on the worker's
# local fwapg.

compare_bcfishpass_wsg <- function(wsg, config) {
  stopifnot(
    is.character(wsg), length(wsg) == 1L, nzchar(wsg),
    grepl("^[A-Z]{3,5}$", wsg),
    inherits(config, "lnk_config")
  )
  schema <- paste0("working_", tolower(wsg))

  conn <- DBI::dbConnect(RPostgres::Postgres(),
    host = "localhost", port = 5432, dbname = "fwapg",
    user = "postgres", password = "postgres")
  on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

  tunnel_pass <- Sys.getenv("PG_PASS_SHARE", "")
  if (!nzchar(tunnel_pass)) {
    stop("PG_PASS_SHARE env var is not set — needed to connect to the ",
         "bcfishpass reference tunnel (localhost:63333). Set it in ",
         "~/.Renviron.", call. = FALSE)
  }
  conn_ref <- DBI::dbConnect(RPostgres::Postgres(),
    host = "localhost", port = 63333, dbname = "bcfishpass",
    user = Sys.getenv("PG_USER_SHARE", "newgraph"),
    password = tunnel_pass)
  on.exit(try(DBI::dbDisconnect(conn_ref), silent = TRUE), add = TRUE)

  # Defensive reset of shared-schema outputs from any prior partial run.
  # Matches the findings.md note: fresh.streams is a shared schema;
  # targets sequences WSGs via workers = 1, but an errored run can leave
  # half-built state that would make the next target's ours-query wrong.
  DBI::dbExecute(conn,
    "DROP TABLE IF EXISTS fresh.streams, fresh.streams_habitat,
     fresh.streams_breaks CASCADE")

  # -------------------------------------------------------------------------
  # Pipeline
  # -------------------------------------------------------------------------
  link::lnk_pipeline_setup(conn, schema, overwrite = TRUE)
  link::lnk_pipeline_load(conn, aoi = wsg, cfg = config, schema = schema)
  link::lnk_pipeline_prepare(conn, aoi = wsg, cfg = config, schema = schema)
  link::lnk_pipeline_break(conn, aoi = wsg, cfg = config, schema = schema)
  link::lnk_pipeline_classify(conn, aoi = wsg, cfg = config, schema = schema)
  link::lnk_pipeline_connect(conn, aoi = wsg, cfg = config, schema = schema)

  # -------------------------------------------------------------------------
  # Compare against bcfishpass reference
  # -------------------------------------------------------------------------
  species <- link::lnk_pipeline_species(config, wsg)

  species_sql <- paste(
    vapply(species,
      function(s) as.character(DBI::dbQuoteLiteral(conn, s)),
      character(1)),
    collapse = ", ")
  ours <- DBI::dbGetQuery(conn, sprintf("
    SELECT h.species_code,
      round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric
        / 1000, 2) AS spawning_km,
      round(SUM(CASE WHEN h.rearing THEN s.length_metre ELSE 0 END)::numeric
        / 1000, 2) AS rearing_km
    FROM fresh.streams s JOIN fresh.streams_habitat h
      ON s.id_segment = h.id_segment
    WHERE s.watershed_group_code = %s
      AND h.species_code IN (%s)
    GROUP BY h.species_code ORDER BY h.species_code",
    DBI::dbQuoteLiteral(conn, wsg),
    species_sql))

  ref_list <- lapply(species, function(sp) {
    ref_cols <- DBI::dbGetQuery(conn_ref, sprintf(
      "SELECT column_name FROM information_schema.columns
       WHERE table_schema = 'bcfishpass'
         AND table_name = 'habitat_linear_%s'", tolower(sp)))
    has_rear <- "rearing" %in% ref_cols$column_name
    rear_expr <- if (has_rear) {
      "CASE WHEN h.rearing THEN s.length_metre ELSE 0 END"
    } else {
      "0"
    }
    DBI::dbGetQuery(conn_ref, sprintf("
      SELECT %s AS species_code,
        round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric
          / 1000, 2) AS spawning_km,
        round(SUM(%s)::numeric / 1000, 2) AS rearing_km
      FROM bcfishpass.streams s
      JOIN bcfishpass.habitat_linear_%s h
        ON s.segmented_stream_id = h.segmented_stream_id
      WHERE s.watershed_group_code = %s",
      DBI::dbQuoteLiteral(conn_ref, sp),
      rear_expr,
      tolower(sp),
      DBI::dbQuoteLiteral(conn_ref, wsg)))
  })
  ref <- do.call(rbind, ref_list)

  # -------------------------------------------------------------------------
  # Return: ~2 rows per species (spawning + rearing) as a small tibble
  # -------------------------------------------------------------------------
  n_species <- length(species)
  sp_col  <- rep(species, each = 2)
  hab_col <- rep(c("spawning", "rearing"), n_species)
  out <- tibble::tibble(
    wsg           = wsg,
    species       = sp_col,
    habitat_type  = hab_col,
    link_km       = NA_real_,
    bcfishpass_km = NA_real_,
    diff_pct      = NA_real_
  )
  for (i in seq_len(nrow(out))) {
    sp  <- out$species[i]
    hab <- out$habitat_type[i]
    ours_row <- ours[ours$species_code == sp, ]
    ref_row  <- ref[ref$species_code  == sp, ]
    out$link_km[i] <-
      if (nrow(ours_row) > 0) ours_row[[paste0(hab, "_km")]] else 0
    out$bcfishpass_km[i] <-
      if (nrow(ref_row) > 0) ref_row[[paste0(hab, "_km")]] else 0
  }
  out$diff_pct <- ifelse(out$bcfishpass_km == 0, NA_real_,
    round(100 * (out$link_km - out$bcfishpass_km) / out$bcfishpass_km, 1))

  out
}
