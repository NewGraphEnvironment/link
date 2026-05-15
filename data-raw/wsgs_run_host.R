# Provincial parity-only run — single-host orchestrator loop.
#
# For each WSG with any modelled species present: run the link
# pipeline (wsg_pipeline_run) and compare its persisted state against
# bcfishpass (wsg_compare). Saves per-WSG rollup tibbles to
# `data-raw/logs/provincial_parity/<WSG>.rds`.
#
# Resume gate (#168 — PG state is canonical, RDS is diagnostic):
#   pipeline_done = fresh.streams has rows for WSG
#                   (via link:::.lnk_wsg_persisted)
#   rollup_ok     = RDS exists, isn't an error stub, and (for
#                   --with-mapping-code) has $mapping_code present
#
#   force          → re-run pipeline + compare
#   both done      → skip
#   pipeline only  → re-run compare only (~1-2s)
#   neither        → run pipeline + compare
#
# `--force` bypasses both checks. Error-tolerant: a per-WSG failure
# saves an error stub and moves on (or aborts the loop with
# `--fail-fast`). Logs progress + timing to
# `data-raw/logs/<TS>_provincial_parity.txt`.
#
# Known residuals at link 0.20.0:
#   - HORS-class stream-order bypass (fresh#158 not yet shipped)
#   - BULK SK multi-lake (fresh#190 parked)
#   - lake_rearing/wetland_rearing rollup measurement artifacts (-100% rows)
# These are accepted as known gaps in this baseline.
#
# Run from data-raw/:
#   Rscript wsgs_run_host.R > logs/<TS>_provincial_parity.txt 2>&1 &

suppressPackageStartupMessages({
  library(link); library(fresh); library(dplyr); library(DBI); library(RPostgres)
})

# Relative — script is run from data-raw/, so this works on every host
# (M4, M1, cypher) without path patching.
source("wsg_pipeline_run.R")
source("wsg_compare.R")

# CLI args:
#   --wsgs=<comma-list>  Restrict to a WSG subset (distributed split).
#   --config=<name>      Bundle name (default: "bcfishpass"). Pass "default"
#                        to run the methodology-variant bundle.
#   --schema=<name>      Override cfg$pipeline$schema. Lets you write to
#                        e.g. fresh_default while the bundle config still
#                        says fresh — useful for side-by-side methodology
#                        comparisons without bundle-config edits.
args <- commandArgs(trailingOnly = TRUE)

config_arg <- args[grep("^--config=", args)]
config_name <- if (length(config_arg) > 0) sub("^--config=", "", config_arg[1]) else "bcfishpass"
cfg <- lnk_config(config_name)

# `--with-mapping-code` (no value): pass through to the wrapper so each
# WSG's RDS holds list(rollup, mapping_code) instead of a bare rollup
# tibble. The post-loop annotation step (below) reads either shape.
with_mapping_code <- "--with-mapping-code" %in% args

# `--fail-fast` (no value): the first WSG that errors aborts the loop
# instead of saving an error stub and continuing. Default FALSE
# preserves the resume-safe per-WSG soft-fail behavior for full
# provincial runs (where some WSGs legitimately error for bcfp-not-
# modeled reasons). Smoke runs pass --fail-fast so "WSG #1 failed"
# doesn't waste 30 more WSGs of compute confirming the same failure.
fail_fast <- "--fail-fast" %in% args

# `--force` (no value): bypass both the PG-state and RDS resume checks.
# Re-runs pipeline + compare for every WSG in `wsgs`. Use when external
# state has shifted (fwapg refresh, bcfp tunnel rebuild, config edit)
# and you want a clean rebuild rather than a continuation.
force_run <- "--force" %in% args

schema_arg <- args[grep("^--schema=", args)]
if (length(schema_arg) > 0) {
  cfg$pipeline$schema <- sub("^--schema=", "", schema_arg[1])
}
loaded <- lnk_load_overrides(cfg)

wsgs_arg <- args[grep("^--wsgs=", args)]
# Filter to bundle species only — broader inclusion (e.g. ct/dv/gr/rb) lets
# WSGs through that the bundle can't classify; they error 50-80s in with
# "No species resolved for AOI". See link#157.
spp_cols <- tolower(cfg$species)
wsg_pres <- loaded$wsg_species_presence
has_spp <- apply(wsg_pres[, spp_cols, drop = FALSE], 1, function(r) {
  any(r %in% c("t", "TRUE", TRUE))
})
default_wsgs <- wsg_pres$watershed_group_code[has_spp]

if (length(wsgs_arg) > 0) {
  wsgs <- strsplit(sub("^--wsgs=", "", wsgs_arg[1]), ",")[[1]]
  wsgs <- trimws(wsgs)
  invalid <- setdiff(wsgs, default_wsgs)
  if (length(invalid) > 0) {
    stop("--wsgs contains WSGs not in wsg_species_presence (or with no species we model): ",
         paste(invalid, collapse = ", "), call. = FALSE)
  }
} else {
  wsgs <- default_wsgs
}

# Relative to getwd() so the script works on M4, M1, and cypher (which
# don't share the /Users/airvine/... path). Run from data-raw/.
# RDS dir auto-derived from config name unless overridden via --rds-dir
# (so bcfishpass-bundle and default-bundle rollups don't clobber each
# other when run side-by-side).
rds_dir_arg <- args[grep("^--rds-dir=", args)]
default_rds_dir <- if (config_name == "bcfishpass") "provincial_parity" else paste0("provincial_", config_name)
out_dir_name <- if (length(rds_dir_arg) > 0) sub("^--rds-dir=", "", rds_dir_arg[1]) else default_rds_dir
out_dir <- file.path(getwd(), "logs", out_dir_name)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

cat("=== PROVINCIAL PARITY RUN — link 0.20.0 ===\n")
cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    " (epoch", as.integer(Sys.time()), ")\n", sep = "")
cat("WSGs to run:", length(wsgs), "\n")
cat("Output dir :", out_dir, "\n\n")

t_total <- Sys.time()

# Per-WSG timings CSV (one row appended per WSG completion).
# Drives data-raw/buckets_balance.R for future LPT planning;
# replaces the regex-parse-the-text-log path. Host-tagged via Sys.info()
# so multi-host trifecta runs produce comparable rows.
host_id <- Sys.info()[["nodename"]]
times_csv <- file.path(out_dir, sprintf("%s_per_wsg_times.csv",
                                        format(Sys.time(), "%Y%m%d_%H%M")))
write.table(data.frame(wsg = character(), host = character(),
                       elapsed_s = numeric(), rows = integer(),
                       status = character(), stringsAsFactors = FALSE),
            times_csv, sep = ",", row.names = FALSE, col.names = TRUE,
            quote = FALSE)
append_time <- function(w, elapsed, rows, status) {
  write.table(data.frame(wsg = w, host = host_id,
                         elapsed_s = round(elapsed, 1), rows = rows,
                         status = status, stringsAsFactors = FALSE),
              times_csv, sep = ",", row.names = FALSE, col.names = FALSE,
              quote = FALSE, append = TRUE)
}

# Pin the bcfp comparison reference (model_run_id + version SHA) for this
# run by appending one row to data-raw/logs/bcfp_baselines.csv. Tuesday
# weekly bcfishpass.* rebuilds shift the comparison reference; un-stamped
# runs are ambiguous after the fact.
#
# Tunnel precondition: same as compare_bcfishpass_wsg() — port 63333
# pre-forwarded to db_newgraph and PG_PASS_SHARE set. If the precondition
# fails the per-WSG comparisons below also fail, so this is not the
# blocker — warn-and-continue keeps the failure surface where it matters.
#
# Idempotent on (host, link_schema, bcfp_model_run_id, run_started_pdt).
# host alias defaults to LNK_HOST_ALIAS env var (set per host in
# ~/.Renviron, e.g. LNK_HOST_ALIAS=m4); falls back to Sys.info()[["nodename"]].
stamp_bcfp_baseline <- function(config_name, link_schema) {
  csv_path <- file.path(getwd(), "logs", "bcfp_baselines.csv")
  host <- Sys.getenv("LNK_HOST_ALIAS", Sys.info()[["nodename"]])
  run_label <- if (config_name == "bcfishpass") "provincial_parity" else paste0("provincial_", config_name)
  run_started <- format(Sys.time(), "%Y-%m-%d %H:%M")

  tryCatch({
    tunnel_pass <- Sys.getenv("PG_PASS_SHARE", "")
    if (!nzchar(tunnel_pass)) {
      message("[bcfp-baseline] WARN: PG_PASS_SHARE not set, skipping stamp")
      return(invisible(NULL))
    }
    conn_ref <- DBI::dbConnect(RPostgres::Postgres(),
      host = "localhost", port = 63333, dbname = "bcfishpass",
      user = Sys.getenv("PG_USER_SHARE", "newgraph"),
      password = tunnel_pass)
    on.exit(try(DBI::dbDisconnect(conn_ref), silent = TRUE), add = TRUE)

    bcfp <- DBI::dbGetQuery(conn_ref, "
      SELECT model_run_id, model_version,
             to_char(date_completed, 'YYYY-MM-DD HH24:MI') AS date_completed
      FROM bcfishpass.log
      ORDER BY model_run_id DESC LIMIT 1")
    if (nrow(bcfp) == 0L) {
      message("[bcfp-baseline] WARN: bcfishpass.log empty, skipping stamp")
      return(invisible(NULL))
    }

    if (file.exists(csv_path)) {
      existing <- utils::read.csv(csv_path, stringsAsFactors = FALSE,
                                   check.names = FALSE)
      hit <- existing$host == host &
             existing$link_schema == link_schema &
             as.character(existing$bcfp_model_run_id) == as.character(bcfp$model_run_id) &
             existing$run_started_pdt == run_started
      if (any(hit, na.rm = TRUE)) {
        cat(sprintf("[bcfp-baseline] skip: already stamped (host=%s link_schema=%s model_run_id=%s)\n",
                    host, link_schema, bcfp$model_run_id))
        return(invisible(NULL))
      }
    }

    row <- data.frame(
      run_started_pdt = run_started,
      host = host,
      run_label = run_label,
      link_schema = link_schema,
      bcfp_model_run_id = bcfp$model_run_id,
      bcfp_model_version = bcfp$model_version,
      bcfp_date_completed = bcfp$date_completed,
      notes = "auto-stamped at wsgs_run_host.R start",
      stringsAsFactors = FALSE)
    write.table(row, csv_path, sep = ",", row.names = FALSE,
                col.names = FALSE, quote = FALSE, append = TRUE)
    cat(sprintf("[bcfp-baseline] stamped: model_run_id=%s host=%s -> %s\n",
                bcfp$model_run_id, host, csv_path))
  }, error = function(e) {
    message("[bcfp-baseline] WARN: ", conditionMessage(e))
  })
  invisible(NULL)
}

stamp_bcfp_baseline(config_name, cfg$pipeline$schema)

# Script-level conn for the resume-state probe. PG is the canonical
# state — the RDS file is a diagnostic side-artifact, not the source
# of truth for whether the modelling pipeline ran. The per-WSG
# functions wsg_pipeline_run / wsg_compare each open their own
# short-lived conns, so this is only for resume checks here.
probe_conn <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 5432, dbname = "fwapg",
  user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(probe_conn), silent = TRUE), add = TRUE)

# RDS files saved when a WSG errors are stubs of shape
# list(error = "<message>", elapsed_s = <numeric>). These do NOT
# represent a successful comparison; resume logic must treat them
# as if no rollup is cached so the WSG re-runs on next dispatch.
.is_error_stub <- function(rds_path) {
  if (!file.exists(rds_path)) return(FALSE)
  x <- tryCatch(readRDS(rds_path), error = function(e) NULL)
  is.list(x) && !is.data.frame(x) && "error" %in% names(x)
}

# Mapping_code path: PG-state resume doesn't capture mapping_code
# output, so when --with-mapping-code is set we force a re-run unless
# the RDS already holds a list with $mapping_code present.
.rollup_has_mapping_code <- function(rds_path) {
  if (!file.exists(rds_path)) return(FALSE)
  x <- tryCatch(readRDS(rds_path), error = function(e) NULL)
  is.list(x) && !is.data.frame(x) && "mapping_code" %in% names(x) &&
    !is.null(x$mapping_code)
}

for (w in wsgs) {
  out_rds <- file.path(out_dir, paste0(w, ".rds"))

  # Resume gate. Four states:
  #   force        → always re-run pipeline + compare.
  #   fully cached → PG has rows AND a non-stub RDS exists.
  #                  Skip; nothing to do.
  #   compare only → PG has rows but RDS is missing or is an error
  #                  stub. Skip pipeline, re-run compare only (~1-2s).
  #   missing      → PG empty for this WSG. Run pipeline + compare.
  pipeline_done <- link:::.lnk_wsg_persisted(probe_conn, cfg, w)
  rollup_ok <- file.exists(out_rds) && !.is_error_stub(out_rds) &&
    (!isTRUE(with_mapping_code) || .rollup_has_mapping_code(out_rds))

  if (!isTRUE(force_run) && pipeline_done && rollup_ok) {
    cat(format(Sys.time(), "%H:%M:%S"), "  ", w,
        " (cached, skip)\n", sep = "")
    next
  }

  do_pipeline <- isTRUE(force_run) || !pipeline_done ||
    isTRUE(with_mapping_code)  # mapping_code path drives its own pipeline

  cat(format(Sys.time(), "%H:%M:%S"), "  ", w, " ... ",
      if (!do_pipeline) "[compare-only] " else "", sep = "")
  t0 <- Sys.time()
  tryCatch({
    out <- if (isTRUE(with_mapping_code)) {
      # Mapping_code lens stays bundled via the lnk_compare_wsg wrapper
      # — decoupling deferred per #168 scope. Wrapped in an anonymous
      # function so `on.exit` has a frame to attach to (top-level script
      # `on.exit` binds to globalenv and leaks conns over the loop).
      (function() {
        conn_local <- DBI::dbConnect(RPostgres::Postgres(),
          host = "localhost", port = 5432, dbname = "fwapg",
          user = "postgres", password = "postgres")
        on.exit(try(DBI::dbDisconnect(conn_local), silent = TRUE), add = TRUE)
        conn_ref <- DBI::dbConnect(RPostgres::Postgres(),
          host = "localhost", port = 63333, dbname = "bcfishpass",
          user = Sys.getenv("PG_USER_SHARE", "newgraph"),
          password = Sys.getenv("PG_PASS_SHARE"))
        on.exit(try(DBI::dbDisconnect(conn_ref), silent = TRUE), add = TRUE)
        message(format(link::lnk_stamp(cfg, conn = conn_local, aoi = w),
                       "markdown"))
        res <- link::lnk_compare_wsg(
          conn = conn_local, aoi = w, cfg = cfg,
          loaded = loaded, reference = "bcfishpass",
          conn_ref = conn_ref, with_mapping_code = TRUE
        )
        names(res$rollup)[names(res$rollup) == "ref_value"] <-
          "bcfishpass_value"
        res
      })()
    } else {
      if (do_pipeline) wsg_pipeline_run(wsg = w, config = cfg)
      wsg_compare(wsg = w, config = cfg)
    }
    saveRDS(out, out_rds)
    # `out` is either a tibble (rollup-only) or list(rollup, mapping_code).
    # Use the rollup tibble for the timing CSV's `rows` column either way.
    rollup_for_time <- if (is.data.frame(out)) out else out$rollup
    elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    cat("done ", round(elapsed, 1), "s, rows ",
        nrow(rollup_for_time), "\n", sep = "")
    append_time(w, elapsed, nrow(rollup_for_time), "ok")
  }, error = function(e) {
    elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    saveRDS(list(error = conditionMessage(e),
                 elapsed_s = elapsed),
            out_rds)
    cat("ERROR (", round(elapsed, 1), "s): ",
        conditionMessage(e), "\n", sep = "")
    append_time(w, elapsed, NA_integer_, "error")
    if (isTRUE(fail_fast)) {
      # Bubble the error up so the host process exits non-zero. The
      # orchestrator's `wait` will see this and the smoke runner's
      # post-dispatch assertion will flag it. Saves ~30 WSGs of
      # confirm-the-same-failure compute on the bcfp-not-modeled set
      # or a snapshot DDL drift.
      stop(sprintf("[fail-fast] aborting on %s: %s",
                   w, conditionMessage(e)), call. = FALSE)
    }
  })
}

t_total_s <- as.numeric(difftime(Sys.time(), t_total, units = "secs"))
cat("\n=== DONE ===\n")
cat("Ended:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), "\n")
cat("Total wall time:", round(t_total_s / 60, 1), "min  (",
    round(t_total_s, 1), "s)\n", sep = "")
cat("WSGs completed:", length(list.files(out_dir, pattern = "\\.rds$")), "\n")

# ---------------------------------------------------------------------------
# Post-loop annotation: bind all per-WSG RDS rollups, annotate against
# the bcfp divergence taxonomy, write `<TS>_<host>_annotated.csv`.
# Each host writes its own bucket's annotated CSV. The orchestrator
# (wsgs_dispatch.sh) does the province-wide aggregate after the
# RDS pull-back step.
#
# Skipped if the taxonomy YAML doesn't exist relative to the script's
# working dir (e.g. running from a host without the research/ tree).
# ---------------------------------------------------------------------------
taxonomy_path <- normalizePath(
  file.path("..", "research", "bcfp_divergence_taxonomy.yml"),
  mustWork = FALSE)
if (file.exists(taxonomy_path)) {
  rds_files <- list.files(out_dir, pattern = "\\.rds$", full.names = TRUE)
  rollup_list <- lapply(rds_files, function(f) {
    x <- tryCatch(readRDS(f), error = function(e) NULL)
    if (is.null(x)) return(NULL)
    # Skip per-WSG error stubs (saved as list(error=..., elapsed_s=...))
    if (is.list(x) && !is.data.frame(x) && "error" %in% names(x)) return(NULL)
    # Phase 2 shape: list(rollup, mapping_code)
    if (is.list(x) && !is.data.frame(x) && "rollup" %in% names(x)) return(x$rollup)
    # Phase 1 shape: bare rollup tibble
    if (is.data.frame(x)) return(x)
    NULL
  })
  rollup_all <- do.call(rbind, Filter(Negate(is.null), rollup_list))
  if (!is.null(rollup_all) && nrow(rollup_all) > 0L) {
    annotated_csv <- file.path(out_dir, sprintf(
      "%s_%s_annotated.csv",
      format(Sys.time(), "%Y%m%d_%H%M"),
      host_id))
    link::lnk_parity_annotate(
      rollup_all, taxonomy = taxonomy_path, to = annotated_csv)
    cat("Annotated CSV: ", annotated_csv, "\n", sep = "")
    cat("  rows: ", nrow(rollup_all), "\n", sep = "")
  }
} else {
  cat("[annotate] taxonomy YAML not found at ", taxonomy_path,
      " - skipping annotation\n", sep = "")
}
