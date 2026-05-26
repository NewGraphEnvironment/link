#' Compare one watershed group's persisted mapping_code tokens against a reference
#'
#' Segment-level QA counterpart to [lnk_compare_rollup()]. Reads the
#' per-segment `mapping_code_<sp>` tokens that [lnk_pipeline_run()] (with
#' `mapping_code = TRUE`) persisted to `<persist_schema>.streams_mapping_code`,
#' diffs them against a reference's tokens for the same segments, and returns
#' a per-species match tibble.
#'
#' Reads only — no writes, no working schema.
#'
#' ## Tunnel-free by default
#'
#' The reference is the **local** snapshot `fresh.streams_vw_bcfp` (loaded by
#' `data-raw/snapshot_bcfp.sh --with-bcfp-views` from bcfp's published S3
#' output — no SSH, no `:63333`). With `conn_ref = NULL` (default) the compare
#' is a single local join on `conn`: no second connection, no `PG_PASS_SHARE`,
#' no tunnel. Pass `conn_ref` (a DBI connection to the live bcfp tunnel) to
#' diff against `bcfishpass.streams_mapping_code` instead — the legacy path,
#' kept for back-compat.
#'
#' ## Join
#'
#' link's `streams_mapping_code.id_segment` is a local surrogate, distinct from
#' bcfp's `segmented_stream_id`, so the join is on FWA segment-start position:
#' `blue_line_key` + `downstream_route_measure` (rounded to 3 decimals — robust
#' to ULP drift on the PostGIS-computed doubles, deterministic across runs that
#' share the same fwapg segmentation). link's position columns come from
#' `<persist_schema>.streams`, joined on the full PK
#' `(id_segment, watershed_group_code)` — `id_segment` alone is not unique
#' across WSGs. The snapshot view carries the position columns inline.
#'
#' ## Species resolution
#'
#' `species = NULL` (default) compares every species present as a
#' `mapping_code_<sp>` column on BOTH sides (link's persisted table and the
#' reference), with rows for the WSG. Pass `species` to restrict; caller-passed
#' species absent on either side drop out (no error).
#'
#' @param conn DBI connection to the local pipeline database (where
#'   `<persist_schema>` and `fresh.streams_vw_bcfp` live).
#' @param aoi Watershed group code (e.g. `"PARS"`).
#' @param cfg An `lnk_config` object (resolves `cfg$pipeline$schema`).
#' @param reference Character scalar identifying the reference. Only
#'   `"bcfishpass"` is supported.
#' @param conn_ref Optional DBI connection to the bcfp tunnel
#'   (`localhost:63333`). Default `NULL` → tunnel-free local-snapshot compare.
#' @param species Optional character vector of species codes to restrict to.
#'   Default `NULL` discovers the set from the mapping_code columns.
#' @param ref_table Reference table name for the tunnel-free path. Default
#'   `"fresh.streams_vw_bcfp"` (where `snapshot_bcfp.sh` loads bcfp's output).
#'
#' @return A tibble, one row per species: `wsg`, `species`, `total_segs`,
#'   `match_pct`, `n_diffs`, `top_pattern` (most common `link | bcfp` token
#'   mismatch), `top_pattern_count`.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' cfg <- lnk_config("bcfishpass")
#'
#' # Tunnel-free: diff persisted tokens vs the local fresh.streams_vw_bcfp snapshot.
#' lnk_compare_mapping_code(conn, aoi = "PARS", cfg = cfg)
#'
#' # Legacy tunnel path (requires the bcfp tunnel up):
#' conn_ref <- DBI::dbConnect(RPostgres::Postgres(),
#'   host = "localhost", port = 63333, dbname = "bcfishpass",
#'   user = "newgraph", password = Sys.getenv("PG_PASS_SHARE"))
#' lnk_compare_mapping_code(conn, "PARS", cfg, conn_ref = conn_ref)
#' }
#'
#' @family compare
#' @seealso [lnk_compare_rollup()], [lnk_compare_wsg()], [lnk_pipeline_run()]
#' @export
lnk_compare_mapping_code <- function(conn, aoi, cfg,
                                     reference = "bcfishpass",
                                     conn_ref = NULL,
                                     species = NULL,
                                     ref_table = "fresh.streams_vw_bcfp") {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(aoi), length(aoi) == 1L, nzchar(aoi),
    grepl("^[A-Z]{3,5}$", aoi),
    inherits(cfg, "lnk_config"),
    is.character(reference), length(reference) == 1L, nzchar(reference),
    is.null(conn_ref) || inherits(conn_ref, "DBIConnection"),
    is.null(species) || is.character(species),
    is.character(ref_table), length(ref_table) == 1L, nzchar(ref_table)
  )

  supported_references <- c("bcfishpass")
  if (!reference %in% supported_references) {
    stop("Unsupported reference '", reference, "'. Supported: ",
         paste(supported_references, collapse = ", "), ".", call. = FALSE)
  }

  tunnel_free <- is.null(conn_ref)
  ref_conn <- if (tunnel_free) conn else conn_ref
  # Tunnel-free reads the local snapshot view; tunnel path reads bcfp's live
  # streams_mapping_code (joined to bcfishpass.streams for position columns).
  ref_from <- if (tunnel_free) {
    sprintf("%s", ref_table)
  } else {
    "bcfishpass.streams_mapping_code bmc
       JOIN bcfishpass.streams bs ON bs.segmented_stream_id = bmc.segmented_stream_id"
  }

  tn <- .lnk_table_names(cfg)
  persist_schema <- tn$schema

  # Resolve the species compared: mapping_code_<sp> columns present on the
  # reference AND **active** on the link side for this WSG (≥1 non-empty token).
  # Restricting to WSG-active link species avoids spurious 0%-match rows for
  # species the WSG doesn't model — link emits "" for absent species while the
  # reference emits NULL, which would otherwise count as all-mismatch. "salmon"
  # is a bcfp-only aggregate with no link counterpart and drops out.
  link_cols <- .lnk_mc_species_cols(conn, persist_schema, "streams_mapping_code")
  link_sp <- .lnk_mc_active_species(conn, persist_schema, "streams_mapping_code",
                                    aoi, link_cols)
  ref_schema_table <- if (tunnel_free) {
    strsplit(ref_table, ".", fixed = TRUE)[[1]]
  } else {
    c("bcfishpass", "streams_mapping_code")
  }
  ref_sp <- .lnk_mc_species_cols(ref_conn, ref_schema_table[1], ref_schema_table[2])
  cmp_species <- intersect(link_sp, ref_sp)
  if (!is.null(species)) {
    cmp_species <- intersect(cmp_species, toupper(species))
  }
  if (length(cmp_species) == 0L) {
    stop("no shared mapping_code_<sp> columns to compare for ", aoi,
         " (link: ", paste(link_sp, collapse = ","),
         "; ref: ", paste(ref_sp, collapse = ","), ").", call. = FALSE)
  }

  aoi_lit_link <- DBI::dbQuoteLiteral(conn, aoi)
  aoi_lit_ref  <- DBI::dbQuoteLiteral(ref_conn, aoi)

  # link side: persisted tokens + FWA position from <persist>.streams.
  # JOIN on BOTH (id_segment, watershed_group_code): id_segment is not globally
  # unique in the persist tables (PK is the pair), so joining on id_segment
  # alone fans a WSG's segments out across every other WSG sharing that id —
  # a cartesian blow-up that wrecks the match. (This was latent in the old
  # tunnel helper too.)
  link_mc <- DBI::dbGetQuery(conn, sprintf("
    SELECT lmc.*, ls.blue_line_key,
           round(ls.downstream_route_measure::numeric, 3) AS downstream_route_measure
      FROM %1$s.streams_mapping_code lmc
      JOIN %1$s.streams ls
        ON ls.id_segment = lmc.id_segment
       AND ls.watershed_group_code = lmc.watershed_group_code
     WHERE ls.watershed_group_code = %2$s",
    persist_schema, aoi_lit_link))

  # reference side: local snapshot view (tunnel-free) carries the position
  # columns inline; tunnel path joins bcfishpass.streams for them.
  if (tunnel_free) {
    bcfp_mc <- DBI::dbGetQuery(ref_conn, sprintf("
      SELECT blue_line_key,
             round(downstream_route_measure::numeric, 3) AS downstream_route_measure,
             %2$s
        FROM %1$s
       WHERE watershed_group_code = %3$s",
      ref_from,
      paste(sprintf("mapping_code_%s", tolower(cmp_species)), collapse = ", "),
      aoi_lit_ref))
  } else {
    bcfp_mc <- DBI::dbGetQuery(ref_conn, sprintf("
      SELECT bmc.*, bs.blue_line_key,
             round(bs.downstream_route_measure::numeric, 3) AS downstream_route_measure
        FROM %s
       WHERE bs.watershed_group_code = %s",
      ref_from, aoi_lit_ref))
  }

  .lnk_mc_diff(link_mc, bcfp_mc, aoi = aoi, species = cmp_species,
               ref_empty_is_na = TRUE)
}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

#' Species codes (uppercase) that have a `mapping_code_<sp>` column on a table.
#' Excludes the bcfp-only `salmon` aggregate (no link counterpart).
#' @noRd
.lnk_mc_species_cols <- function(conn, schema, table) {
  cols <- DBI::dbGetQuery(conn, sprintf(
    "SELECT column_name FROM information_schema.columns
      WHERE table_schema = %s AND table_name = %s
        AND column_name LIKE 'mapping_code\\_%%' ESCAPE '\\'",
    DBI::dbQuoteLiteral(conn, schema),
    DBI::dbQuoteLiteral(conn, table)))$column_name
  sp <- sub("^mapping_code_", "", cols)
  sp <- sp[grepl("^[a-z]+$", sp) & sp != "salmon"]
  toupper(sp)
}


#' Subset of candidate species that are ACTIVE in a WSG — i.e. have at least
#' one non-empty `mapping_code_<sp>` token in `<schema>.<table>` for the AOI.
#' Restricts the compare to species the WSG actually models (link emits "" for
#' absent species; the reference emits NULL — comparing them is meaningless).
#' @noRd
.lnk_mc_active_species <- function(conn, schema, table, aoi, candidates) {
  if (length(candidates) == 0L) return(character(0))
  checks <- paste(sprintf(
    "bool_or(mapping_code_%1$s IS NOT NULL AND mapping_code_%1$s <> '') AS %1$s",
    tolower(candidates)), collapse = ", ")
  r <- DBI::dbGetQuery(conn, sprintf(
    "SELECT %s FROM %s.%s WHERE watershed_group_code = %s",
    checks, schema, table, DBI::dbQuoteLiteral(conn, aoi)))
  if (nrow(r) == 0L) return(character(0))
  flags <- as.logical(unlist(r[1, , drop = TRUE]))
  candidates[!is.na(flags) & flags]
}


#' Per-segment token diff (shared by tunnel-free + tunnel paths).
#'
#' Merges link + reference frames on FWA position and computes per-species
#' match stats. `ref_empty_is_na = TRUE` returns NA-filled stats (with a
#' warning) when the reference has no rows for the WSG (bcfp doesn't model it);
#' a non-empty reference with no key overlap is a hard error (snapshot
#' misalignment).
#' @noRd
.lnk_mc_diff <- function(link_mc, bcfp_mc, aoi, species,
                         ref_empty_is_na = TRUE) {
  joined <- merge(
    link_mc, bcfp_mc,
    by = c("blue_line_key", "downstream_route_measure"),
    suffixes = c("_link", "_bcfp"))

  if (nrow(joined) == 0L) {
    if (isTRUE(ref_empty_is_na) && nrow(bcfp_mc) == 0L) {
      warning(sprintf(
        "reference has 0 rows for %s — not modelled there; returning NA stats.",
        aoi), call. = FALSE)
      return(do.call(rbind, lapply(species, function(sp) {
        tibble::tibble(wsg = aoi, species = sp, total_segs = 0L,
                       match_pct = NA_real_, n_diffs = NA_integer_,
                       top_pattern = NA_character_, top_pattern_count = NA_integer_)
      })))
    }
    stop(sprintf(
      "no position overlap between link + reference streams_mapping_code for %s ",
      aoi),
      "(link rows: ", nrow(link_mc), ", ref rows: ", nrow(bcfp_mc),
      "). Check fwapg snapshot alignment.", call. = FALSE)
  }

  rows <- lapply(species, function(sp) {
    link_col <- paste0("mapping_code_", tolower(sp), "_link")
    bcfp_col <- paste0("mapping_code_", tolower(sp), "_bcfp")
    if (!(link_col %in% names(joined)) || !(bcfp_col %in% names(joined))) {
      return(tibble::tibble(wsg = aoi, species = sp,
        total_segs = nrow(joined), match_pct = NA_real_, n_diffs = NA_integer_,
        top_pattern = NA_character_, top_pattern_count = NA_integer_))
    }
    l <- joined[[link_col]]
    b <- joined[[bcfp_col]]
    matches <- (is.na(l) & is.na(b)) | (!is.na(l) & !is.na(b) & l == b)
    n_match <- sum(matches)
    n_total <- nrow(joined)
    diff_idx <- which(!matches)
    top_pattern <- NA_character_
    top_pattern_count <- NA_integer_
    if (length(diff_idx) > 0L) {
      patt <- paste0(ifelse(is.na(l[diff_idx]), "<NA>", l[diff_idx]), " | ",
                     ifelse(is.na(b[diff_idx]), "<NA>", b[diff_idx]))
      tab <- sort(table(patt), decreasing = TRUE)
      top_pattern <- names(tab)[1]
      top_pattern_count <- as.integer(tab[1])
    }
    tibble::tibble(wsg = aoi, species = sp, total_segs = n_total,
      match_pct = round(100 * n_match / n_total, 2),
      n_diffs = as.integer(n_total - n_match),
      top_pattern = top_pattern, top_pattern_count = top_pattern_count)
  })
  do.call(rbind, rows)
}
