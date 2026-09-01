# Run-provenance log on the persist schema (link#127).
#
# `<persist_schema>.streams` and friends accumulate rows across many runs but
# carry no provenance: given a network in the database you cannot say which
# config produced it, what that config actually said at the time, which
# primitive vintage it was built from, or when it was written.
#
# Four sidecar tables answer that, mirroring `bcfishpass.log` and its FK'd
# children (which snapshot actual parameter *values*, not pointers to them):
#
#   <schema>.log                   one row per lnk_pipeline_run() call
#   <schema>.log_parameters_fresh  full parameters_fresh.csv rows per config
#   <schema>.log_dimensions        full dimensions.csv rows per config
#   <schema>.log_input             DB primitive fingerprints per run
#
# Design notes that are load-bearing (see planning/active/findings.md):
#
#   * `run_id` is TEXT, not a serial. `data-raw/schema_consolidate.R` COPYs
#     literal values between hosts whose sequences would both start at 1, so a
#     serial guarantees PK collisions and silent loss of run history. It also
#     avoids a RETURNING round-trip, which would break the `.lnk_db_execute`
#     mocking the tests rely on.
#   * Snapshot values are stored as `text`. These are provenance, not compute
#     inputs; `text` preserves the "" vs NA distinction the CSVs actually use
#     and is immune to type drift.
#   * Column lists come from the config dictionaries (link#233), so adding a
#     parameter updates the dictionary and the log table together.


# ---------------------------------------------------------------------------
# Identity + hashing primitives
# ---------------------------------------------------------------------------

#' Deterministic fingerprint of a config bundle's *observed* bytes.
#'
#' Hashes the resolved file set rather than the declared `provenance:` block.
#' Two reasons this matters:
#'
#'   * `config.yaml` itself is absent from its own `provenance:` block, so a
#'     verify-derived hash would be blind to `pipeline$schema`, `break_order`,
#'     `gradient_classes`, `cluster` and `spawn_connected` — all of which change
#'     model output.
#'   * The declared checksums are declared, not verified ([lnk_config_verify()]
#'     is never called during a run), so copying them could record a lie.
#'
#' Missing files hash to the literal `MISSING` rather than erroring — the hash
#' should describe whatever is actually on disk.
#'
#' @param cfg An `lnk_config` object.
#' @return A single string, `"sha256:<hex>"`.
#' @noRd
.lnk_config_hash <- function(cfg) {
  if (!inherits(cfg, "lnk_config")) {
    stop("cfg must be an lnk_config object", call. = FALSE)
  }

  paths <- c(
    file.path(cfg$dir, "config.yaml"),
    cfg$rules,
    cfg$dimensions,
    unlist(lapply(cfg$files, function(f) f$path), use.names = FALSE),
    if (!is.null(cfg$provenance)) file.path(cfg$dir, names(cfg$provenance))
  )
  paths <- unique(paths[!is.na(paths) & nzchar(paths)])

  rel <- vapply(paths, function(p) {
    r <- sub(paste0("^", .lnk_regex_escape(cfg$dir), "/?"), "", p)
    if (nzchar(r)) r else basename(p)
  }, character(1), USE.NAMES = FALSE)

  digests <- vapply(paths, function(p) {
    if (!file.exists(p)) {
      return("MISSING")
    }
    digest::digest(file = p, algo = "sha256")
  }, character(1), USE.NAMES = FALSE)

  ord <- order(rel)
  payload <- paste(
    c(
      paste0("name=", cfg$name),
      paste0("species=", paste(sort(cfg$species), collapse = ";")),
      paste0(rel[ord], "=", digests[ord])
    ),
    collapse = "\n"
  )

  paste0("sha256:", digest::digest(payload, algo = "sha256", serialize = FALSE))
}


#' Escape a string for literal use inside a regex.
#' @noRd
.lnk_regex_escape <- function(x) {
  gsub("([.\\\\|()\\[\\]{}^$*+?])", "\\\\\\1", x, perl = TRUE)
}


#' Globally unique run identifier.
#'
#' `<host>-<UTC timestamp to ms>-<6 hex>`. Host-prefixed and random-suffixed so
#' that ids minted independently on several cyphers never collide when
#' `schema_consolidate.R` COPYs them into one province-wide schema.
#'
#' Three identity levels, deliberately distinct (link#262):
#'
#'   `run_id`     this, the PK. ONE PER WSG — a 217-WSG dispatch mints 217.
#'   `run_uid`    one per dispatch, shared by every host and every WSG of it.
#'                Minted once by `data-raw/study_area_run.sh` and handed to
#'                every host as `LNK_RUN_UID`, so "everything from that run" is
#'                one equality rather than a time window plus a host list.
#'                NA for an ad-hoc single-WSG call, which is honest: there was
#'                no dispatch to belong to.
#'   `run_label`  operator free text (`--run-label=`). Names the campaign for a
#'                human; never assume it is unique.
#'
#' @return A single string.
#' @noRd
.lnk_run_id <- function() {
  host <- gsub("[^A-Za-z0-9]+", "", .lnk_host())
  if (!nzchar(host)) host <- "host"
  ts <- format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y%m%dT%H%M%OS3", tz = "UTC")
  suffix <- paste(sprintf("%x", sample.int(16L, 6L, replace = TRUE) - 1L),
                  collapse = "")
  paste(host, ts, suffix, sep = "-")
}


#' DB primitives whose vintage determines model output.
#'
#' The pipeline's inputs, in the order they matter. `source` records where the
#' data actually comes from — a fact that lives in the loader scripts, not the
#' database, and which nothing else records.
#'
#' @return A data.frame with `table_name` and `source`.
#' @noRd
.lnk_input_primitives <- function() {
  fwapg <- "fwapg/load.sh <- nrs.objectstore.gov.bc.ca/bchamp/fwapg"
  data.frame(
    table_name = c(
      "whse_basemapping.fwa_stream_networks_sp",
      "whse_basemapping.fwa_stream_networks_channel_width",
      "whse_basemapping.fwa_stream_networks_order_parent",
      "whse_basemapping.fwa_lakes_poly",
      "whse_basemapping.fwa_wetlands_poly",
      "whse_basemapping.fwa_rivers_poly",
      "whse_basemapping.fwa_obstacles_sp",
      "bcfishobs.observations",
      "whse_fish.pscis_assessment_svw",
      "cabd.dams",
      "fresh.modelled_stream_crossings"
    ),
    source = c(
      rep(fwapg, 7L),
      "bcfishobs",
      "bcdata bc2pg",
      "CABD",
      "snapshot_bcfp.sh <- bchamp objectstore"
    ),
    stringsAsFactors = FALSE
  )
}


# ---------------------------------------------------------------------------
# DDL
# ---------------------------------------------------------------------------

# One row per lnk_pipeline_run() call. `run_id` is TEXT (see file header).
# `watershed_group_code` is present so schema_consolidate.R auto-discovers the
# table — it keys off "has a watershed_group_code column".
cols_log <- c(
  run_id                 = "text NOT NULL",
  watershed_group_code   = "varchar(4) NOT NULL",
  date_start             = "timestamptz NOT NULL",
  date_end               = "timestamptz",
  run_uid                = "text",
  run_label              = "text",
  host                   = "text",
  config_name            = "text",
  config_hash            = "text",
  config_drift           = "boolean",
  link_version           = "text",
  link_sha               = "text",
  link_dirty             = "boolean",
  fresh_version          = "text",
  fresh_sha              = "text",
  fresh_dirty            = "boolean",
  crate_version          = "text",
  fwapg_sha              = "text",
  arg_dams               = "boolean",
  arg_mapping_code       = "boolean",
  arg_cleanup_working    = "boolean",
  schema_persist         = "text",
  species                = "text[]",
  wsg_upstream           = "text[]",
  bcfp_model_run_id      = "integer",
  bcfp_model_version     = "text",
  bcfp_pin_source        = "text",
  notes                  = "text"
)

# One row per data-raw/wsg_recompute_one.R invocation (link#262).
#
# A SEPARATE TABLE, not a `phase` column on `log`. The recompute rewrites
# <persist>.streams_access and <persist>.streams_mapping_code — the output that
# actually ships — so it needs a record; but folding it into `log` would:
#
#   * make lnk_log_read()'s `DISTINCT ON (watershed_group_code) ORDER BY
#     date_start DESC` return the recompute row as "what produced this
#     network", which it did not;
#   * change what count(*) means for every existing consumer, including
#     data-raw/study_area_verify.sql;
#   * leave arg_dams / arg_mapping_code / wsg_upstream / config_drift NULL or
#     misleading, since those are facts about a modelling run.
#
# Deliberately NO log_input FK: the recompute reads the already-persisted
# streams / habitat / barriers, not the DB primitives, so a primitive
# fingerprint here would describe inputs it never touched.
#
# `watershed_group_code` is present so schema_consolidate.R auto-discovers the
# table — it keys off "is a BASE TABLE with a watershed_group_code column"
# (data-raw/schema_consolidate.R), so a cypher's recompute rows travel home
# with no list for anyone to maintain.
cols_log_recompute <- c(
  recompute_id           = "text NOT NULL",
  watershed_group_code   = "varchar(4) NOT NULL",
  date_start             = "timestamptz NOT NULL",
  date_end               = "timestamptz",
  run_uid                = "text",
  run_label              = "text",
  host                   = "text",
  config_name            = "text",
  config_hash            = "text",
  link_version           = "text",
  link_sha               = "text",
  link_dirty             = "boolean",
  fresh_version          = "text",
  fresh_sha              = "text",
  fresh_dirty            = "boolean",
  crate_version          = "text",
  fwapg_sha              = "text",
  schema_persist         = "text",
  species                = "text[]",
  views_prebuilt         = "boolean",
  notes                  = "text"
)

# Per-primitive fingerprints. Carries watershed_group_code for the same
# auto-discovery reason as `log`.
cols_log_input <- c(
  run_id                 = "text NOT NULL",
  watershed_group_code   = "varchar(4)",
  table_name             = "text NOT NULL",
  row_count              = "bigint",
  row_count_estimated    = "boolean",
  size_bytes             = "bigint",
  last_analyze           = "timestamptz",
  source                 = "text",
  source_at              = "timestamptz"
)


#' Column vectors for the config-snapshot tables, driven by the dictionaries.
#'
#' `dictionary_parameters_fresh.csv` and `dictionary_dimensions.csv` (link#233)
#' are the canonical column lists, and they cover the *union* of all bundles —
#' which matters because bundles carry different subsets (bcfishpass's
#' `dimensions.csv` has 30 columns to the `default*` bundles' 32). Generating
#' DDL from them means adding a parameter updates the dictionary and the log
#' table together, by construction.
#'
#' Every value column is `text`: these are provenance snapshots, not compute
#' inputs, so `text` is lossless (it preserves the `""` vs `NA` distinction the
#' CSVs actually use) and immune to type drift.
#'
#' @noRd
.lnk_dictionary_columns <- function(which) {
  path <- system.file("extdata", "configs",
                      paste0("dictionary_", which, ".csv"), package = "link")
  if (!nzchar(path) || !file.exists(path)) {
    stop("dictionary_", which, ".csv not found in the installed package",
         call. = FALSE)
  }
  as.character(utils::read.csv(path, check.names = FALSE)$column)
}

#' @noRd
.lnk_cols_log_parameters_fresh <- function() {
  cols <- .lnk_dictionary_columns("parameters_fresh")
  out <- stats::setNames(rep("text", length(cols)), cols)
  out[["species_code"]] <- "text NOT NULL"
  c(config_hash = "text NOT NULL", out)
}

#' @noRd
.lnk_cols_log_dimensions <- function() {
  cols <- .lnk_dictionary_columns("dimensions")
  out <- stats::setNames(rep("text", length(cols)), cols)
  out[["species"]] <- "text NOT NULL"
  c(config_hash = "text NOT NULL", out)
}


#' Bring an existing log table up to the expected column set.
#'
#' `CREATE TABLE IF NOT EXISTS` is a no-op against a table that already exists,
#' even with a drifted shape — so on its own it can never ship a *new* config
#' column, and config columns are the entire point of these tables. A new
#' parameter would be silently never logged, reintroducing the exact
#' silent-drift failure this issue exists to prevent.
#'
#' `ADD COLUMN IF NOT EXISTS` is Postgres-native and idempotent, so this is
#' cheap to run on every init.
#'
#' @noRd
.lnk_log_align_columns <- function(conn, schema, table, cols) {
  for (nm in names(cols)) {
    # Drop NOT NULL when back-filling: an existing table may already hold rows.
    type <- sub("\\s+NOT NULL$", "", cols[[nm]])
    .lnk_db_execute(conn, sprintf(
      "ALTER TABLE %s.%s ADD COLUMN IF NOT EXISTS %s %s",
      schema, table, nm, type))
  }
  invisible(conn)
}


#' Create the four provenance tables. Idempotent.
#'
#' Called from [lnk_persist_init()] so a standalone init produces a complete
#' schema, and again from the run-start path so a run never fails for want of
#' a table.
#'
#' @noRd
.lnk_log_create_tables <- function(conn, schema) {
  # The log is opened BEFORE lnk_persist_init runs (the open row must predate
  # any write, so wsg_upstream reflects the state the run started from), so on
  # a brand-new persist schema nothing has created it yet.
  .lnk_db_execute(conn, sprintf("CREATE SCHEMA IF NOT EXISTS %s", schema))

  specs <- list(
    list(table = "log", cols = cols_log, pk = "run_id"),
    list(table = "log_recompute", cols = cols_log_recompute,
         pk = "recompute_id"),
    list(table = "log_input", cols = cols_log_input,
         pk = c("run_id", "table_name")),
    list(table = "log_parameters_fresh", cols = .lnk_cols_log_parameters_fresh(),
         pk = c("config_hash", "species_code")),
    list(table = "log_dimensions", cols = .lnk_cols_log_dimensions(),
         pk = c("config_hash", "species"))
  )

  for (s in specs) {
    .lnk_db_execute(conn, sprintf(
      "CREATE TABLE IF NOT EXISTS %s.%s (\n  %s\n)",
      schema, s$table, .lnk_cols_clause(s$cols, s$pk)))
    .lnk_log_align_columns(conn, schema, s$table, s$cols)
  }

  idx <- c(
    log_wsg_date    = "log (watershed_group_code, date_start DESC)",
    log_config      = "log (config_hash)",
    log_input_rn    = "log_input (run_id)",
    log_run_uid     = "log (run_uid)",
    log_rc_run_uid  = "log_recompute (run_uid)",
    log_rc_wsg_date = "log_recompute (watershed_group_code, date_start DESC)"
  )
  for (nm in names(idx)) {
    .lnk_db_execute(conn, sprintf(
      "CREATE INDEX IF NOT EXISTS %s_idx ON %s.%s", nm, schema, idx[[nm]]))
  }

  invisible(conn)
}


#' Read the run-provenance log from a persist schema
#'
#' Answers "which config produced this network, and when" without
#' hand-written SQL. One row per `lnk_pipeline_run()` call; by default only
#' the most recent run per watershed group.
#'
#' A watershed group present in `<persist_schema>.streams` but absent here was
#' modelled before provenance logging existed (link#127) — absence means
#' pre-provenance vintage, not an error. Rows are never backfilled, because
#' the config and code state that produced them is not recoverable and a
#' synthetic row would be fabricated provenance.
#'
#' @param conn DBI connection to the pipeline database.
#' @param cfg An `lnk_config` object — supplies the persist schema.
#' @param aoi Optional watershed group code to filter to.
#' @param latest Logical. When `TRUE` (default), return only the newest run
#'   per watershed group. `FALSE` returns the full history. **Ignored when
#'   `run_uid` is supplied** — see below.
#' @param run_uid Optional dispatch identifier (link#262). One dispatch of
#'   `data-raw/study_area_run.sh` stamps the same `run_uid` on every host and
#'   every watershed group, so this is what answers "everything from that run"
#'   without a time window. Supplying it forces `latest = FALSE`: the question
#'   is "every row of this run", and `DISTINCT ON` would silently drop a WSG
#'   that was re-run within the same dispatch.
#' @param phase Which log to read. `"model"` (default) reads `<schema>.log`,
#'   one row per [lnk_pipeline_run()] call. `"recompute"` reads
#'   `<schema>.log_recompute`, one row per `wsg_recompute_one.R` invocation —
#'   the post-consolidate pass that rewrites `streams_access` and
#'   `streams_mapping_code`, which is the output that ships.
#' @return A tibble, newest first.
#' @family compare
#' @export
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' cfg  <- lnk_config("default")
#'
#' # What produced the current PINE network?
#' lnk_log_read(conn, cfg, aoi = "PINE")
#'
#' # Every run, newest first.
#' lnk_log_read(conn, cfg, latest = FALSE)
#'
#' # Everything from one dispatch, across every host — no time window.
#' lnk_log_read(conn, cfg, run_uid = "20260901T184455-3f9ac1")
#'
#' # Was each of those WSGs also recomputed?
#' lnk_log_read(conn, cfg, run_uid = "20260901T184455-3f9ac1",
#'              phase = "recompute")
#' }
lnk_log_read <- function(conn, cfg, aoi = NULL, latest = TRUE,
                         run_uid = NULL, phase = c("model", "recompute")) {
  phase <- match.arg(phase)
  stopifnot(
    inherits(conn, "DBIConnection"),
    inherits(cfg, "lnk_config"),
    is.logical(latest), length(latest) == 1L
  )
  if (!is.null(aoi) &&
      (!is.character(aoi) || length(aoi) != 1L || !nzchar(aoi))) {
    stop("aoi must be NULL or a single non-empty WSG code", call. = FALSE)
  }
  if (!is.null(run_uid) &&
      (!is.character(run_uid) || length(run_uid) != 1L || !nzchar(run_uid))) {
    stop("run_uid must be NULL or a single non-empty string", call. = FALSE)
  }

  schema <- .lnk_table_names(cfg)$schema
  table <- if (identical(phase, "recompute")) "log_recompute" else "log"

  preds <- c(
    if (!is.null(aoi)) sprintf("watershed_group_code = %s",
                               DBI::dbQuoteLiteral(conn, aoi)),
    if (!is.null(run_uid)) sprintf("run_uid = %s",
                                   DBI::dbQuoteLiteral(conn, run_uid))
  )
  where <- if (length(preds) == 0L) {
    ""
  } else {
    paste0(" WHERE ", paste(preds, collapse = " AND "))
  }

  # A run_uid filter is a question about a whole dispatch, so it overrides
  # `latest` rather than composing with it. Composing would return one row per
  # WSG and hide a WSG re-run inside the same dispatch — the case the identifier
  # exists to make visible.
  if (isTRUE(latest) && is.null(run_uid)) {
    sql <- sprintf(
      "SELECT DISTINCT ON (watershed_group_code) * FROM %s.%s%s
        ORDER BY watershed_group_code, date_start DESC",
      schema, table, where)
  } else {
    sql <- sprintf("SELECT * FROM %s.%s%s ORDER BY date_start DESC",
                   schema, table, where)
  }

  tibble::as_tibble(DBI::dbGetQuery(conn, sql))
}


# ---------------------------------------------------------------------------
# Write path
# ---------------------------------------------------------------------------

#' Quote an R value as a SQL literal, NA -> NULL.
#' @noRd
.lnk_log_lit <- function(conn, x) {
  if (length(x) == 0L || all(is.na(x))) {
    return("NULL")
  }
  as.character(DBI::dbQuoteLiteral(conn, x[[1]]))
}

#' Normalise an env-sourced identifier: blank is absent, not a value.
#'
#' `Sys.getenv("X", NA_character_)` returns `NA` only when X is **unset**. A
#' set-but-empty var — `export LNK_RUN_UID=""`, or an orchestrator interpolating
#' a variable that never got assigned — yields `""`, which `.lnk_log_lit()` would
#' faithfully quote as `''`. An empty-string run_uid is worse than a NULL one:
#' it joins to every other empty-string row, so two unlabelled dispatches would
#' merge into one "run".
#'
#' This is the "empty is not unset" trap in one line, applied where the value
#' crosses into SQL so every caller is covered rather than each remembering.
#'
#' @noRd
.lnk_blank_to_na <- function(x) {
  if (length(x) != 1L || is.na(x) || !nzchar(trimws(as.character(x)))) {
    return(NA_character_)
  }
  as.character(x)
}

#' Quote a character vector as a Postgres text[] literal.
#' @noRd
.lnk_log_arr <- function(conn, x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) {
    return("ARRAY[]::text[]")
  }
  paste0("ARRAY[",
         paste(vapply(x, function(v) as.character(DBI::dbQuoteLiteral(conn, v)),
                      character(1)), collapse = ", "),
         "]::text[]")
}


#' Record fingerprints of the DB primitives this run read.
#'
#' Reads provenance that already exists rather than recomputing it. Three
#' sources with very different coverage, so the query LEFT JOINs all of them
#' and lets absent facts stay NULL:
#'
#'   * `bcdata.log` — authoritative download times, but only for `bc2pg`
#'     downloads. It does **not** cover FWA.
#'   * `pg_class` — `reltuples` (estimated) and total relation size, free.
#'   * `pg_stat_user_tables.last_autoanalyze` — a good load-date proxy, but
#'     empty for bulk-restored tables (notably `fwa_stream_networks_sp`).
#'
#' Deliberately no `count(*)`: exact counts on a 4.9M-row, 9.8 GB table
#' multiplied across a provincial pass would add hours, and an estimate plus an
#' explicit `row_count_estimated` flag is the honest trade. Honest absence beats
#' fabricated precision — hence NULLs rather than invented values.
#'
#' Soft-fails: provenance logging must never kill a modelling run.
#'
#' @noRd
.lnk_log_inputs <- function(conn, schema, run_id, aoi) {
  tryCatch({
    prims <- .lnk_input_primitives()

    has_bcdata <- nrow(DBI::dbGetQuery(conn,
      "SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'bcdata' AND table_name = 'log' LIMIT 1")) > 0L

    values <- paste(vapply(seq_len(nrow(prims)), function(i) {
      sprintf("(%s, %s)",
              DBI::dbQuoteLiteral(conn, prims$table_name[i]),
              DBI::dbQuoteLiteral(conn, prims$source[i]))
    }, character(1)), collapse = ", ")

    src_at <- if (has_bcdata) {
      "(SELECT b.latest_download FROM bcdata.log b WHERE b.table_name = p.tbl)"
    } else {
      "NULL::timestamptz"
    }

    # nolint start: indentation_linter
    sql <- sprintf(
      "INSERT INTO %s.log_input
         (run_id, watershed_group_code, table_name, row_count,
          row_count_estimated, size_bytes, last_analyze, source, source_at)
       SELECT %s, %s, p.tbl,
              c.reltuples::bigint,
              TRUE,
              pg_total_relation_size(c.oid),
              s.last_autoanalyze,
              p.src,
              %s
         FROM (VALUES %s) AS p(tbl, src)
         LEFT JOIN pg_class c
           ON c.oid = to_regclass(p.tbl)
         LEFT JOIN pg_stat_user_tables s
           ON s.relid = c.oid
       ON CONFLICT (run_id, table_name) DO NOTHING",
      schema,
      DBI::dbQuoteLiteral(conn, run_id),
      DBI::dbQuoteLiteral(conn, aoi),
      src_at, values)
    # nolint end: indentation_linter

    .lnk_db_execute(conn, sql)
    invisible(TRUE)
  }, error = function(e) {
    warning("log_input not recorded: ", conditionMessage(e), call. = FALSE)
    invisible(FALSE)
  })
}


#' Snapshot the config's full parameter rows, once per distinct config_hash.
#'
#' This is what makes a network self-describing: `observation_species = BT;DV`
#' at threshold 1 with no date floor is recorded *in the database*, so a
#' scenario run stays identifiable after the config file moves on. Mirrors
#' bcfp's `log_parameters_habitat_thresholds`.
#'
#' Keyed on `config_hash` rather than `run_id`, so a 246-WSG provincial pass
#' stores one parameter set rather than 246 copies.
#'
#' Shape guard: if a bundle carries a column the dictionary doesn't know about,
#' warn and insert the intersection rather than failing the run.
#'
#' @noRd
.lnk_log_config_snapshot <- function(conn, schema, cfg, loaded, config_hash) {
  tryCatch({
    already <- nrow(DBI::dbGetQuery(conn, sprintf(
      "SELECT 1 FROM %s.log_parameters_fresh WHERE config_hash = %s LIMIT 1",
      schema, DBI::dbQuoteLiteral(conn, config_hash)))) > 0L
    if (already) {
      return(invisible(TRUE))
    }

    specs <- list(
      list(table = "log_parameters_fresh",
           cols = .lnk_cols_log_parameters_fresh(),
           data = loaded$parameters_fresh),
      list(table = "log_dimensions",
           cols = .lnk_cols_log_dimensions(),
           data = tryCatch(utils::read.csv(cfg$dimensions, check.names = FALSE,
                                           colClasses = "character"),
                           error = function(e) NULL))
    )

    for (s in specs) {
      df <- s$data
      if (is.null(df) || nrow(df) == 0L) next

      expected <- setdiff(names(s$cols), "config_hash")
      extra <- setdiff(names(df), expected)
      if (length(extra) > 0L) {
        warning(s$table, ": bundle carries column(s) absent from the ",
                "dictionary, inserting the intersection: ",
                paste(extra, collapse = ", "), call. = FALSE)
      }
      use <- intersect(expected, names(df))
      if (length(use) == 0L) next

      rows <- vapply(seq_len(nrow(df)), function(i) {
        vals <- vapply(use, function(nm) {
          v <- df[[nm]][i]
          if (is.na(v)) "NULL" else
            as.character(DBI::dbQuoteLiteral(conn, as.character(v)))
        }, character(1))
        paste0("(", DBI::dbQuoteLiteral(conn, config_hash), ", ",
               paste(vals, collapse = ", "), ")")
      }, character(1))

      .lnk_db_execute(conn, sprintf(
        "INSERT INTO %s.%s (config_hash, %s) VALUES %s
         ON CONFLICT DO NOTHING",
        schema, s$table, paste(use, collapse = ", "),
        paste(rows, collapse = ", ")))
    }
    invisible(TRUE)
  }, error = function(e) {
    warning("config snapshot not recorded: ", conditionMessage(e), call. = FALSE)
    invisible(FALSE)
  })
}


#' Open a run-log row. Loud by design.
#'
#' Runs in the first second and costs nothing, so a failure here means the
#' schema is broken — better to know before 80 minutes of modelling than after.
#' Everything downstream of the open row is soft.
#'
#' `wsg_upstream` is captured **before** any write touches the schema, because
#' link accumulates cross-WSG state: a WSG's downstream barrier tokens depend on
#' which other WSGs were persisted first (RUNBOOK §5). The current AOI is kept
#' in the set if present — its presence is the "this is a re-run over existing
#' state" signal, which is itself provenance.
#'
#' @return A list with `run_id`, `config_hash`, `date_start`.
#' @noRd
.lnk_log_run_start <- function(conn, cfg, aoi, schema_working,
                               dams = TRUE, cleanup_working = TRUE,
                               mapping_code = FALSE,
                               run_uid = NA_character_,
                               run_label = NA_character_,
                               notes = NA_character_) {
  schema <- .lnk_table_names(cfg)$schema
  .lnk_log_create_tables(conn, schema)

  run_uid <- .lnk_blank_to_na(run_uid)
  run_label <- .lnk_blank_to_na(run_label)

  upstream <- tryCatch(.lnk_wsg_persisted_all(conn, cfg),
                       error = function(e) character(0))

  stamp <- lnk_stamp(cfg, conn = NULL, aoi = aoi)
  run_id <- .lnk_run_id()
  bcfp <- .lnk_bcfp_log_current(conn)

  cols <- c("run_id", "watershed_group_code", "date_start",
            "run_uid", "run_label", "host",
            "config_name", "config_hash", "config_drift",
            "link_version", "link_sha", "link_dirty",
            "fresh_version", "fresh_sha", "fresh_dirty",
            "crate_version", "fwapg_sha",
            "arg_dams", "arg_mapping_code", "arg_cleanup_working",
            "schema_persist", "wsg_upstream",
            "bcfp_model_run_id", "bcfp_model_version", "bcfp_pin_source",
            "notes")

  vals <- c(
    DBI::dbQuoteLiteral(conn, run_id),
    DBI::dbQuoteLiteral(conn, aoi),
    "now()",
    .lnk_log_lit(conn, run_uid),
    .lnk_log_lit(conn, run_label),
    .lnk_log_lit(conn, stamp$host),
    .lnk_log_lit(conn, cfg$name),
    .lnk_log_lit(conn, stamp$config_hash),
    .lnk_log_lit(conn, stamp$config_drift),
    .lnk_log_lit(conn, stamp$software$link$version),
    .lnk_log_lit(conn, stamp$software$link$git_sha),
    .lnk_log_lit(conn, stamp$software$link$dirty),
    .lnk_log_lit(conn, stamp$software$fresh$version),
    .lnk_log_lit(conn, stamp$software$fresh$git_sha),
    .lnk_log_lit(conn, stamp$software$fresh$dirty),
    .lnk_log_lit(conn, .lnk_pkg_version_or_na("crate")),
    .lnk_log_lit(conn, stamp$fwapg_sha),
    .lnk_log_lit(conn, dams),
    .lnk_log_lit(conn, mapping_code),
    .lnk_log_lit(conn, cleanup_working),
    .lnk_log_lit(conn, schema),
    .lnk_log_arr(conn, upstream),
    .lnk_log_lit(conn, if (is.null(bcfp)) NA else bcfp$model_run_id),
    .lnk_log_lit(conn, if (is.null(bcfp)) NA else bcfp$model_version),
    .lnk_log_lit(conn, if (is.null(bcfp)) NA else bcfp$source),
    .lnk_log_lit(conn, notes)
  )

  .lnk_db_execute(conn, sprintf(
    "INSERT INTO %s.log (%s) VALUES (%s)",
    schema, paste(cols, collapse = ", "), paste(vals, collapse = ", ")))

  list(run_id = run_id, config_hash = stamp$config_hash,
       schema = schema, schema_working = schema_working)
}


#' Close a run-log row on success. Soft.
#' @noRd
.lnk_log_run_finish <- function(conn, cfg, run_id, species = character(0)) {
  tryCatch({
    schema <- .lnk_table_names(cfg)$schema
    .lnk_db_execute(conn, sprintf(
      "UPDATE %s.log SET date_end = now(), species = %s WHERE run_id = %s",
      schema, .lnk_log_arr(conn, species),
      DBI::dbQuoteLiteral(conn, run_id)))
    invisible(TRUE)
  }, error = function(e) {
    warning("run log not finalized: ", conditionMessage(e), call. = FALSE)
    invisible(FALSE)
  })
}


#' Mark a run-log row failed. Soft, and never touches `date_end`.
#'
#' Leaving `date_end` NULL gives a three-state signal:
#'   date_end set                -> success
#'   date_end NULL + notes set   -> R error or interrupt (this ran)
#'   date_end NULL + notes NULL  -> SIGKILL / OOM / reboot (nothing ran)
#'
#' @noRd
.lnk_log_run_fail <- function(conn, cfg, run_id,
                              message = "run failed or interrupted") {
  tryCatch({
    schema <- .lnk_table_names(cfg)$schema
    .lnk_db_execute(conn, sprintf(
      "UPDATE %s.log SET notes = concat_ws('; ', notes, %s) WHERE run_id = %s",
      schema, DBI::dbQuoteLiteral(conn, message),
      DBI::dbQuoteLiteral(conn, run_id)))
    invisible(TRUE)
  }, error = function(e) {
    invisible(FALSE)
  })
}


#' Latest bcfishpass build the comparison reference was taken from.
#'
#' Two tiers, and the second is the one that fires on a real run (link#262).
#'
#' **Tier 1 — `bcfishpass.log`.** Right whenever the connection actually reaches
#' a bcfp database (the `:63333` tunnel). Carries `model_run_id`, which nothing
#' else does.
#'
#' **Tier 2 — the local baseline ledger.** `data-raw/study_area_run.sh` is
#' deliberately tunnel-free, so the pipeline connection is local docker fwapg,
#' which holds **zero** `bcfishpass` tables — measured 2026-09-01:
#' `information_schema.tables WHERE table_schema = 'bcfishpass'` returns 0. Tier
#' 1 therefore returns NULL on every WSG of every study-area run, which is why
#' `bcfp_model_run_id` and `bcfp_model_version` were NULL on all 37 rows of the
#' 2026-08-31 field run.
#'
#' The reference those runs compare against is not the tunnel either: it is
#' `fresh.streams_vw_bcfp`, a local snapshot `ogr2ogr`'d from the newgraph
#' bucket by `data-raw/snapshot_bcfp.sh`, whose step 6 already stamps the build
#' it loaded into `data-raw/logs/bcfp_baselines.csv` via [lnk_baseline_append()].
#' So the deterministic ref exists locally, and querying a live `bcfishpass.log`
#' at compare time would name the build the tunnel is at *now* — it rebuilds
#' weekly — rather than the one the numbers were computed against. That is a
#' wrong pin, not a missing one.
#'
#' **`model_run_id` is NULL on tier 2 and that is correct.** `log.json` carries
#' no such key ([lnk_bucket_log()] requires only `model_version`,
#' `date_completed`, `head_sha`) and [lnk_baseline_append()] writes `""` for it.
#' Honest absence beats a fabricated id.
#'
#' Ledger path: `LNK_BCFP_BASELINE`, else `data-raw/logs/bcfp_baselines.csv`
#' relative to the working directory. Both hosts run the drivers from the repo
#' root — the dispatcher via `cd "$REPO_ROOT"`, cyphers via
#' `cd ~/Projects/repo/link` inside the ssh string — so cwd resolves on both.
#' A miss returns NULL rather than erroring; provenance must never kill a run.
#'
#' **Tier 0 — `LNK_BCFP_MODEL_VERSION`.** Every host of one run must pin the
#' **same** reference, and tier 2 cannot guarantee that: the ledger is a per-host
#' record, so each cypher would record whatever *it* last snapshotted. The
#' compare runs on the dispatcher against the dispatcher's
#' `fresh.streams_vw_bcfp`, so the dispatcher's build is the one every row should
#' name. `study_area_run.sh` resolves it once in `preflight_local()` and exports
#' it to both legs — exactly what it already does with `FWAPG_GIT_SHA`. Tier 0
#' also removes the working-directory dependence tier 2 would otherwise put on a
#' persisted value.
#'
#' (An earlier version of this comment said a cypher has *no* ledger row. That
#' is wrong: `cypher_prep.sh` runs `snapshot_bcfp.sh`, whose stamp is not gated
#' on `--with-bcfp-views`, so a cypher does write its own honest row. The reason
#' tier 0 exists is agreement across hosts, not absence on one.)
#'
#' `bcfp_pin_source` records which tier answered, so "not pinned" is
#' distinguishable from "pinned, from the ledger" without inferring it from a
#' NULL id.
#'
#' @return A list with `model_run_id`, `model_version` and `source`, or NULL.
#' @noRd
.lnk_bcfp_log_current <- function(conn) {
  env_version <- .lnk_blank_to_na(Sys.getenv("LNK_BCFP_MODEL_VERSION", ""))
  if (!is.na(env_version)) {
    env_id <- suppressWarnings(
      as.integer(.lnk_blank_to_na(Sys.getenv("LNK_BCFP_MODEL_RUN_ID", ""))))
    return(list(model_run_id = env_id, model_version = env_version,
                source = "env"))
  }

  from_db <- tryCatch({
    present <- nrow(DBI::dbGetQuery(conn,
      "SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'bcfishpass' AND table_name = 'log' LIMIT 1")) > 0L
    if (!present) {
      NULL
    } else {
      res <- DBI::dbGetQuery(conn,
        "SELECT model_run_id, model_version FROM bcfishpass.log
          ORDER BY model_run_id DESC LIMIT 1")
      if (nrow(res) == 0L) NULL else c(as.list(res[1L, ]), list(source = "db"))
    }
  }, error = function(e) NULL)

  if (!is.null(from_db)) {
    return(from_db)
  }
  .lnk_bcfp_log_ledger()
}


#' Tier 2 of [.lnk_bcfp_log_current()] — the local snapshot ledger.
#'
#' Scoped to THIS host's rows for the same reason [lnk_baseline_current()] is:
#' each host snapshots into its own local Postgres, so another host's stamp says
#' nothing about what this one loaded. Recency by `run_started_pdt`, whose
#' `YYYY-MM-DD HH:MM` format makes lexicographic ordering chronological — the
#' rule is [lnk_baseline_current()]'s, reused rather than re-derived.
#'
#' @noRd
.lnk_bcfp_log_ledger <- function() {
  tryCatch({
    path <- Sys.getenv("LNK_BCFP_BASELINE", "")
    if (!nzchar(path)) path <- "data-raw/logs/bcfp_baselines.csv"
    if (!file.exists(path)) {
      return(NULL)
    }

    ledger <- lnk_baseline_read(path = path)
    rows <- ledger[ledger$host == .lnk_host(), , drop = FALSE]
    if (nrow(rows) == 0L) {
      return(NULL)
    }

    latest <- rows[order(rows$run_started_pdt, decreasing = TRUE), ,
                   drop = FALSE][1L, , drop = FALSE]
    version <- latest$bcfp_model_version
    if (length(version) != 1L || is.na(version) || !nzchar(version)) {
      return(NULL)
    }

    # "" is what lnk_baseline_append() writes when log.json has no
    # model_run_id, which is every tunnel-free stamp. Carry it as NA rather
    # than inserting an empty string into an integer column.
    id <- latest$bcfp_model_run_id
    id <- if (length(id) != 1L || is.na(id) || !nzchar(as.character(id))) {
      NA_integer_
    } else {
      suppressWarnings(as.integer(id))
    }

    list(model_run_id = id, model_version = version, source = "ledger")
  }, error = function(e) NULL)
}


#' Open a recompute-log row. Loud by design; the rest of the trio is soft.
#'
#' `data-raw/wsg_recompute_one.R` rewrites `<persist>.streams_access` and
#' `<persist>.streams_mapping_code` — the values that actually ship — and until
#' link#262 recorded nothing at all, so `fresh.log` said when a WSG was
#' *modelled* and nothing about when its persisted access last *changed*.
#'
#' **This never runs DDL.** `study_area_run.sh` drives the recompute through a
#' pool up to 16 wide (`--recompute-jobs`), and schema DDL belongs at
#' initialisation rather than in N concurrent jobs: creation should happen once,
#' where a failure is one loud error instead of N attributed to individual WSGs.
#'
#' Not claimed as a measured lock convoy. link#250's convoy was
#' `CREATE OR REPLACE VIEW` against views every sibling holds a long
#' `AccessShareLock` on *for the duration of the network walk*; an
#' `ADD COLUMN IF NOT EXISTS` on a table these jobs only INSERT into takes
#' AccessExclusive for microseconds with no long readers queued behind it. The
#' shapes are related but not the same, and stating the stronger version as
#' fact would teach a future reader "never DDL under any pool", which is not
#' what #250 measured.
#'
#' So the table is created by [lnk_persist_init()], by every modelling run (both
#' via `.lnk_log_create_tables()`), and once by `study_area_run.sh` immediately
#' before the pool — that last one covers the case where every dispatcher WSG
#' species-skips and no modelling run ever happens. This asserts presence.
#'
#'
#' `run_uid` / `run_label` default from the environment, exactly as
#' [lnk_pipeline_run()] does. They must: the whole point of the identifier is
#' that a WSG's modelling row and its recompute row carry the SAME one, and the
#' recompute has no other route to it — `study_area_run.sh` invokes this script
#' per WSG, not through R. Caught by an end-to-end run rather than by the unit
#' tests, which passed the value explicitly and so never exercised the default.
#'
#' @return A list with `recompute_id` and `schema`.
#' @noRd
.lnk_log_recompute_start <- function(conn, cfg, aoi,
                                     run_uid = Sys.getenv("LNK_RUN_UID",
                                                          NA_character_),
                                     run_label = Sys.getenv("LNK_RUN_LABEL",
                                                            NA_character_),
                                     views_prebuilt = NA,
                                     notes = NA_character_) {
  schema <- .lnk_table_names(cfg)$schema
  run_uid <- .lnk_blank_to_na(run_uid)
  run_label <- .lnk_blank_to_na(run_label)

  present <- nrow(DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM information_schema.tables
      WHERE table_schema = %s AND table_name = 'log_recompute' LIMIT 1",
    DBI::dbQuoteLiteral(conn, schema)))) > 0L
  if (!present) {
    stop(sprintf(
      paste0("%s.log_recompute is missing. It is created by lnk_persist_init() ",
             "and by every lnk_pipeline_run(), and is deliberately NOT created ",
             "here: this runs inside a pool up to 16 wide, where DDL is a lock ",
             "convoy (link#250, link#262). Initialise the schema first:\n",
             "  lnk_persist_init(conn, cfg)"),
      schema), call. = FALSE)
  }

  stamp <- lnk_stamp(cfg, conn = NULL, aoi = aoi)
  recompute_id <- .lnk_run_id()

  cols <- c("recompute_id", "watershed_group_code", "date_start",
            "run_uid", "run_label", "host", "config_name", "config_hash",
            "link_version", "link_sha", "link_dirty",
            "fresh_version", "fresh_sha", "fresh_dirty",
            "crate_version", "fwapg_sha", "schema_persist",
            "views_prebuilt", "notes")

  vals <- c(
    DBI::dbQuoteLiteral(conn, recompute_id),
    DBI::dbQuoteLiteral(conn, aoi),
    "now()",
    .lnk_log_lit(conn, run_uid),
    .lnk_log_lit(conn, run_label),
    .lnk_log_lit(conn, stamp$host),
    .lnk_log_lit(conn, cfg$name),
    .lnk_log_lit(conn, stamp$config_hash),
    .lnk_log_lit(conn, stamp$software$link$version),
    .lnk_log_lit(conn, stamp$software$link$git_sha),
    .lnk_log_lit(conn, stamp$software$link$dirty),
    .lnk_log_lit(conn, stamp$software$fresh$version),
    .lnk_log_lit(conn, stamp$software$fresh$git_sha),
    .lnk_log_lit(conn, stamp$software$fresh$dirty),
    .lnk_log_lit(conn, .lnk_pkg_version_or_na("crate")),
    .lnk_log_lit(conn, stamp$fwapg_sha),
    .lnk_log_lit(conn, schema),
    .lnk_log_lit(conn, views_prebuilt),
    .lnk_log_lit(conn, notes)
  )

  .lnk_db_execute(conn, sprintf(
    "INSERT INTO %s.log_recompute (%s) VALUES (%s)",
    schema, paste(cols, collapse = ", "), paste(vals, collapse = ", ")))

  list(recompute_id = recompute_id, schema = schema)
}


#' Close a recompute-log row on success. Soft.
#' @noRd
.lnk_log_recompute_finish <- function(conn, cfg, recompute_id,
                                      species = character(0)) {
  tryCatch({
    schema <- .lnk_table_names(cfg)$schema
    .lnk_db_execute(conn, sprintf(
      "UPDATE %s.log_recompute SET date_end = now(), species = %s
        WHERE recompute_id = %s",
      schema, .lnk_log_arr(conn, species),
      DBI::dbQuoteLiteral(conn, recompute_id)))
    invisible(TRUE)
  }, error = function(e) {
    warning("recompute log not finalized: ", conditionMessage(e), call. = FALSE)
    invisible(FALSE)
  })
}


#' Mark a recompute-log row failed. Soft, and never touches `date_end`.
#'
#' Same three-state signal as [.lnk_log_run_fail()]: `date_end` set means
#' success, NULL with notes means it ran and errored, NULL with no notes means
#' the process died without running anything.
#'
#' @noRd
.lnk_log_recompute_fail <- function(conn, cfg, recompute_id,
                                    message = "recompute failed or interrupted") {
  tryCatch({
    schema <- .lnk_table_names(cfg)$schema
    .lnk_db_execute(conn, sprintf(
      "UPDATE %s.log_recompute SET notes = concat_ws('; ', notes, %s)
        WHERE recompute_id = %s",
      schema, DBI::dbQuoteLiteral(conn, message),
      DBI::dbQuoteLiteral(conn, recompute_id)))
    invisible(TRUE)
  }, error = function(e) {
    invisible(FALSE)
  })
}


#' git SHA of the fwapg checkout that loaded the FWA primitives.
#'
#' The stream network is the most load-bearing input the pipeline has and it
#' carries **no** provenance in the database: `bcdata.log` records only `bc2pg`
#' downloads (which FWA is not), and `pg_stat_user_tables` for
#' `fwa_stream_networks_sp` is empty because it is bulk-restored and never
#' analyzed. It is loaded by fwapg's own `load.sh` from
#' `nrs.objectstore.gov.bc.ca/bchamp/fwapg/...parquet`, so the fwapg checkout's
#' commit is the closest thing to a version for it.
#'
#' Three-tier, mirroring [.lnk_pkg_git_sha()]: `FWAPG_GIT_SHA` env var, then a
#' `.git` walk of `FWAPG_DIR` (or the conventional `../../fwapg` sibling
#' checkout), then `NA`.
#'
#' @return A single string or `NA_character_`.
#' @noRd
.lnk_fwapg_sha <- function() {
  v <- Sys.getenv("FWAPG_GIT_SHA", "")
  if (nzchar(v)) return(v)

  candidates <- c(
    Sys.getenv("FWAPG_DIR", ""),
    file.path(path.expand("~"), "Projects", "repo", "fwapg")
  )
  for (d in candidates[nzchar(candidates)]) {
    git <- file.path(d, ".git")
    if (file.exists(git)) {
      sha <- .lnk_read_git_head(git)
      if (!is.null(sha)) return(sha)
    }
  }
  NA_character_
}
