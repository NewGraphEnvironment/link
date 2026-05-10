# data-raw/compare_bcfp_mapping_code.R
#
# Phase A driver: per-segment per-species `mapping_code_<sp>` parity vs
# bcfp tunnel. See research/bcfp_compare_mapping_code.md for the full
# methodology, expected results, and history.
#
# Runs phases 1-6 of the existing pipeline (setup → load → prepare →
# crossings → break → classify → connect) into a working schema, then
# adds:
#
#   Phase 7: lnk_pipeline_access      (writes <schema>.streams_access)
#   Phase 8: lnk_pipeline_mapping_code (writes <schema>.streams_mapping_code)
#
# and compares <schema>.streams_mapping_code against
# bcfishpass.streams_mapping_code on the tunnel, joined by segment
# position keys (blue_line_key + downstream_route_measure + length_metre).
#
# Args:
#   --wsgs=ADMS,BULK,...   WSGs to run (required)
#   --config=bcfishpass    Bundle name (default: bcfishpass)
#
# Outputs (per WSG):
#   data-raw/logs/mapping_code_parity/<WSG>.rds  — per-species match counts
#   data-raw/logs/<TS>_mapping_code_parity.txt    — stamped run log (via tee)
#
# Run from data-raw/:
#   Rscript compare_bcfp_mapping_code.R --wsgs=ADMS \
#     2>&1 | tee logs/$(date +%Y%m%d%H%M)_mapping_code_parity.txt

suppressPackageStartupMessages({
  library(link); library(fresh); library(DBI); library(RPostgres); library(tidyr)
})

args <- commandArgs(trailingOnly = TRUE)

config_arg <- args[grep("^--config=", args)]
config_name <- if (length(config_arg) > 0) {
  sub("^--config=", "", config_arg[1])
} else "bcfishpass"

wsgs_arg <- args[grep("^--wsgs=", args)]
if (length(wsgs_arg) == 0L) {
  stop("--wsgs=<comma-list> required (e.g. --wsgs=ADMS,BULK)", call. = FALSE)
}
wsgs <- strsplit(sub("^--wsgs=", "", wsgs_arg[1]), ",", fixed = TRUE)[[1]]
wsgs <- trimws(wsgs)
wsgs <- wsgs[nzchar(wsgs)]

cfg <- lnk_config(config_name)
loaded <- lnk_load_overrides(cfg)

LOGDIR <- file.path(getwd(), "logs", "mapping_code_parity")
dir.create(LOGDIR, recursive = TRUE, showWarnings = FALSE)

cat("=== bcfp mapping_code parity run ===\n")
cat(sprintf("Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M %Z")))
cat(sprintf("link: %s   fresh: %s\n",
            packageVersion("link"), packageVersion("fresh")))
cat(sprintf("Config: %s\n", config_name))
cat(sprintf("WSGs: %s\n", paste(wsgs, collapse = ", ")))
cat(sprintf("Output dir: %s\n\n", LOGDIR))

# Per-WSG runner --------------------------------------------------------------

run_one <- function(wsg) {
  schema <- paste0("working_", tolower(wsg))
  out_rds <- file.path(LOGDIR, paste0(wsg, ".rds"))

  if (file.exists(out_rds)) {
    cat(sprintf("%s  %s ... (cached, skip)\n",
                format(Sys.time(), "%H:%M:%S"), wsg))
    return(invisible(readRDS(out_rds)))
  }

  conn <- DBI::dbConnect(RPostgres::Postgres(),
    host = "localhost", port = 5432, dbname = "fwapg",
    user = "postgres", password = "postgres")
  on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

  tunnel_pass <- Sys.getenv("PG_PASS_SHARE", "")
  if (!nzchar(tunnel_pass)) {
    stop("PG_PASS_SHARE env var is not set -- needed to connect to ",
         "the bcfp tunnel (localhost:63333). Set it in ~/.Renviron.",
         call. = FALSE)
  }
  conn_ref <- DBI::dbConnect(RPostgres::Postgres(),
    host = "localhost", port = 63333, dbname = "bcfishpass",
    user = Sys.getenv("PG_USER_SHARE", "newgraph"),
    password = tunnel_pass)
  on.exit(try(DBI::dbDisconnect(conn_ref), silent = TRUE), add = TRUE)

  t0 <- Sys.time()
  cat(sprintf("%s  %s ... ", format(Sys.time(), "%H:%M:%S"), wsg))

  # Phases 1-6 -----------------------------------------------------------------
  link::lnk_pipeline_setup(conn, schema, overwrite = TRUE)
  link::lnk_pipeline_load(conn, aoi = wsg, cfg = cfg, loaded = loaded,
                          schema = schema)
  # conn_tunnel = conn (LOCAL) -- per #137 snapshot_bcfp.sh loads cabd.dams
  # locally; we never read source tables from the bcfp tunnel during the
  # build phase. The tunnel (conn_ref) is reserved for the parity-comparison
  # query at the end.
  link::lnk_pipeline_prepare(conn, aoi = wsg, cfg = cfg, loaded = loaded,
                             schema = schema, conn_tunnel = conn)
  link::lnk_pipeline_crossings(conn, aoi = wsg, cfg = cfg, loaded = loaded,
                               schema = schema)
  link::lnk_pipeline_break(conn, aoi = wsg, cfg = cfg, loaded = loaded,
                           schema = schema)
  link::lnk_pipeline_classify(conn, aoi = wsg, cfg = cfg, loaded = loaded,
                              schema = schema)
  link::lnk_pipeline_connect(conn, aoi = wsg, cfg = cfg, loaded = loaded,
                             schema = schema)

  # Phase 7: streams_access ----------------------------------------------------
  # Self-sufficiency note: link doesn't yet build bcfp-shape per-species
  # barriers tables locally (link#152). For Phase A parity validation we
  # stage bcfp's per-species barriers from the tunnel into the working
  # schema, preserving the bcfp table name so `lnk_pipeline_access` derives
  # the correct `<table>_id` column. Tables are dropped with the schema at
  # end of run. After link#152 ships, this staging step is replaced by
  # reading link's locally-built `<schema>.barriers` directly.
  bcfp_per_sp <- list(
    bt  = "barriers_bt",
    ch  = "barriers_ch_cm_co_pk_sk",
    cm  = "barriers_ch_cm_co_pk_sk",
    co  = "barriers_ch_cm_co_pk_sk",
    pk  = "barriers_ch_cm_co_pk_sk",
    sk  = "barriers_ch_cm_co_pk_sk",
    st  = "barriers_st",
    wct = "barriers_wct"
  )
  for (tbl in unique(unlist(bcfp_per_sp))) {
    rows <- DBI::dbGetQuery(conn_ref, sprintf(
      "SELECT * FROM bcfishpass.%s WHERE watershed_group_code = '%s'",
      tbl, wsg))
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s.%s CASCADE",
                                 schema, tbl))
    DBI::dbWriteTable(conn,
      DBI::Id(schema = schema, table = tbl),
      rows, overwrite = TRUE)
    # dbWriteTable degrades ltree -> text. Re-cast for fwa_downstream.
    DBI::dbExecute(conn, sprintf(
      "ALTER TABLE %1$s.%2$s
         ALTER COLUMN wscode_ltree   TYPE ltree USING wscode_ltree::ltree,
         ALTER COLUMN localcode_ltree TYPE ltree USING localcode_ltree::ltree",
      schema, tbl))
  }
  pres <- link::lnk_presence(loaded$wsg_species_presence, wsg)
  barriers_per_sp <- setNames(
    lapply(names(bcfp_per_sp),
      function(sp) paste0(schema, ".", bcfp_per_sp[[sp]])),
    names(bcfp_per_sp))

  acc <- link::lnk_pipeline_access(
    conn,
    segments        = paste0(schema, ".streams"),
    aoi             = wsg,
    to              = paste0(schema, ".streams_access"),
    barriers_per_sp = barriers_per_sp,
    observations    = paste0(schema, ".observations"),
    presence        = pres,
    barrier_sources = list(
      anthropogenic = paste0(schema, ".barriers_anthropogenic"),
      pscis         = paste0(schema, ".barriers_pscis"),
      dams          = paste0(schema, ".barriers_dams"),
      remediations  = paste0(schema, ".barriers_remediations")),
    crossings_table = paste0(schema, ".crossings"))

  # Phase 8: streams_mapping_code ----------------------------------------------
  # Pivot link's long-format streams_habitat to wide-format spawning_<sp> +
  # rearing_<sp> as `lnk_pipeline_mapping_code` expects.
  hab_long <- DBI::dbGetQuery(conn, sprintf(
    "SELECT id_segment, lower(species_code) AS species_code,
            COALESCE(spawning::int, 0) AS spawning,
            COALESCE(rearing::int, 0)  AS rearing
       FROM %s.streams_habitat
      WHERE watershed_group_code = '%s'", schema, wsg))

  if (nrow(hab_long) == 0L) {
    stop(sprintf("%s.streams_habitat empty for WSG %s", schema, wsg),
         call. = FALSE)
  }

  hab_wide <- tidyr::pivot_wider(
    hab_long,
    id_cols = "id_segment",
    names_from = "species_code",
    values_from = c("spawning", "rearing"),
    values_fill = list(spawning = 0L, rearing = 0L))

  # bcfp pre-allocates spawning_<sp>/rearing_<sp> columns for all 8 mapping-
  # code species regardless of presence (classify runs everywhere, absent
  # species get 0). Link's classify only runs for `lnk_pipeline_species`
  # (no group expansion), so cm/pk columns are missing for ADMS even though
  # `lnk_presence` group-expands them. Fill the gap with 0 so mapping_code
  # logic matches bcfp. Real fix: align lnk_pipeline_species + lnk_presence
  # presence definitions (filed as separate link issue).
  for (sp in c("bt", "ch", "cm", "co", "pk", "sk", "st", "wct")) {
    for (col in c(paste0("spawning_", sp), paste0("rearing_", sp))) {
      if (!(col %in% names(hab_wide))) {
        hab_wide[[col]] <- 0L
      }
    }
  }

  fc <- DBI::dbGetQuery(conn, sprintf(
    "SELECT id_segment, feature_code FROM %s.streams
      WHERE watershed_group_code = '%s'", schema, wsg))

  link::lnk_pipeline_mapping_code(
    access       = acc,
    habitat      = hab_wide,
    feature_code = fc,
    to           = paste0(schema, ".streams_mapping_code"),
    conn         = conn,
    presence     = pres)

  # Comparison vs bcfp ---------------------------------------------------------
  link_mc <- DBI::dbGetQuery(conn, sprintf("
    SELECT lmc.*, ls.blue_line_key, ls.downstream_route_measure, ls.length_metre
      FROM %s.streams_mapping_code lmc
      JOIN %s.streams ls ON ls.id_segment = lmc.id_segment
     WHERE ls.watershed_group_code = '%s'", schema, schema, wsg))

  bcfp_mc <- DBI::dbGetQuery(conn_ref, sprintf("
    SELECT bmc.*, bs.blue_line_key, bs.downstream_route_measure, bs.length_metre
      FROM bcfishpass.streams_mapping_code bmc
      JOIN bcfishpass.streams bs
        ON bs.segmented_stream_id = bmc.segmented_stream_id
     WHERE bs.watershed_group_code = '%s'", wsg))

  joined <- merge(
    link_mc, bcfp_mc,
    by = c("blue_line_key", "downstream_route_measure", "length_metre"),
    suffixes = c("_link", "_bcfp"))

  species <- c("bt", "ch", "cm", "co", "pk", "sk", "st", "wct")
  rows <- lapply(species, function(sp) {
    link_col <- paste0("mapping_code_", sp, "_link")
    bcfp_col <- paste0("mapping_code_", sp, "_bcfp")
    if (!(link_col %in% names(joined)) || !(bcfp_col %in% names(joined))) {
      return(data.frame(
        wsg = wsg, species = sp,
        n_total = nrow(joined), n_match = NA_integer_,
        match_pct = NA_real_, n_diff = NA_integer_,
        stringsAsFactors = FALSE))
    }
    l <- joined[[link_col]]
    b <- joined[[bcfp_col]]
    # NA-aware: NA == NA → match, NA vs string → mismatch
    matches <- (is.na(l) & is.na(b)) | (!is.na(l) & !is.na(b) & l == b)
    n_match <- sum(matches)
    n_total <- nrow(joined)
    data.frame(
      wsg = wsg, species = sp,
      n_total = n_total, n_match = n_match,
      match_pct = round(100 * n_match / n_total, 2),
      n_diff = n_total - n_match,
      stringsAsFactors = FALSE)
  })
  result <- do.call(rbind, rows)

  # Diff distribution sample (top-10 link/bcfp value pairs that differ)
  diff_examples <- lapply(species, function(sp) {
    link_col <- paste0("mapping_code_", sp, "_link")
    bcfp_col <- paste0("mapping_code_", sp, "_bcfp")
    if (!(link_col %in% names(joined))) return(NULL)
    l <- joined[[link_col]]
    b <- joined[[bcfp_col]]
    diff_idx <- which(!((is.na(l) & is.na(b)) | (!is.na(l) & !is.na(b) & l == b)))
    if (length(diff_idx) == 0L) return(NULL)
    tab <- table(
      paste0(ifelse(is.na(l[diff_idx]), "<NA>", l[diff_idx]),
             " | ",
             ifelse(is.na(b[diff_idx]), "<NA>", b[diff_idx])))
    data.frame(
      species = sp,
      pattern = names(tab),
      n = as.integer(tab),
      stringsAsFactors = FALSE)
  })
  diff_examples <- do.call(rbind, Filter(Negate(is.null), diff_examples))

  dt <- as.numeric(Sys.time() - t0, units = "secs")
  cat(sprintf("done %.1fs, %d segs joined\n", dt, nrow(joined)))
  for (i in seq_len(nrow(result))) {
    cat(sprintf("  mapping_code_%-3s   %5d/%-5d (%6.2f%%)  diffs: %d\n",
                result$species[i],
                result$n_match[i], result$n_total[i],
                result$match_pct[i], result$n_diff[i]))
  }
  if (!is.null(diff_examples) && nrow(diff_examples) > 0L) {
    cat("  --- diff patterns (link | bcfp) ---\n")
    for (i in seq_len(nrow(diff_examples))) {
      cat(sprintf("  %-3s  %5d  %s\n",
                  diff_examples$species[i],
                  diff_examples$n[i],
                  diff_examples$pattern[i]))
    }
  }

  attr(result, "diff_examples") <- diff_examples
  saveRDS(result, out_rds)

  # Optional: keep the working schema for diagnostic inspection.
  # Set LNK_KEEP_WORKING=1 in env to skip the cleanup. Default drops.
  if (identical(Sys.getenv("LNK_KEEP_WORKING"), "1")) {
    cat(sprintf("  (LNK_KEEP_WORKING=1; preserving %s)\n", schema))
  } else {
    DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", schema))
  }

  invisible(result)
}

# Loop --------------------------------------------------------------------

results <- list()
for (wsg in wsgs) {
  res <- tryCatch(run_one(wsg), error = function(e) {
    cat(sprintf("ERROR on %s: %s\n", wsg, conditionMessage(e)))
    NULL
  })
  if (!is.null(res)) results[[wsg]] <- res
}

cat("\n=== DONE ===\n")
cat(sprintf("Ended: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M %Z")))
cat(sprintf("WSGs completed: %d / %d\n", length(results), length(wsgs)))
