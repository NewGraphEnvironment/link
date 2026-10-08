#' Build habitat eligibility rules YAML from dimensions CSV
#'
#' Transforms a species habitat dimensions CSV into the rules YAML format
#' consumed by [fresh::frs_habitat()]. The CSV is the human-edited source
#' of truth; the YAML is the derived artifact.
#'
#' @param csv Path to a dimensions CSV with columns: `species`,
#'   `spawn_lake`, `spawn_stream`, `rear_lake`, `rear_lake_only`,
#'   `rear_no_fw`, `rear_stream`, `rear_wetland`. Optional columns:
#'   `river_skip_cw_min` (yes/no — skip channel_width_min on river
#'   polygon segments), `notes`. `rear_lake_connected_distance_max` /
#'   `rear_wetland_connected_distance_max` (metres) keep a species' lake /
#'   wetland rearing bucket only where same-species spawning lies within
#'   that distance (`requires_connected: spawning` on its first rear L / W
#'   rule). The additive lake rule admits lake centrelines (FWA
#'   construction lines) with no channel-width test. See
#'   `configs/dictionary_dimensions.csv` for every column.
#' @param to Path to write the output YAML.
#' @param thresholds Path to the habitat thresholds CSV (from fresh).
#'   Used to look up `rear_lake_ha_min` per species. Default uses the
#'   copy shipped with fresh.
#' @param edge_types Character. How to express stream edge types in rules:
#'   `"categories"` (default) uses fresh categories (`stream`, `canal`).
#'   `"explicit"` uses integer FWA edge_type codes (`1000, 1100, 2000, 2300`).
#'
#' @return Invisible path to the written YAML file.
#'
#' @examples
#' \dontrun{
#' # NGE defaults
#' lnk_rules_build(
#'   csv = system.file("extdata", "parameters_habitat_dimensions.csv", package = "link"),
#'   to = "inst/extdata/parameters_habitat_rules.yaml"
#' )
#'
#' # bcfishpass comparison variant
#' lnk_rules_build(
#'   csv = system.file("extdata", "configs", "bcfishpass", "dimensions.csv",
#'                     package = "link"),
#'   to = "inst/extdata/configs/bcfishpass/rules.yaml",
#'   edge_types = "explicit"
#' )
#' }
#'
#' @export
lnk_rules_build <- function(csv,
                             to,
                             thresholds = system.file("extdata",
                               "parameters_habitat_thresholds.csv",
                               package = "fresh"),
                             edge_types = c("categories", "explicit")) {
  stopifnot(requireNamespace("yaml", quietly = TRUE))
  edge_types <- match.arg(edge_types)

  if (!file.exists(csv)) stop("Dimensions CSV not found: ", csv)
  if (thresholds == "") stop("fresh package not installed or thresholds CSV missing")

  dimensions <- utils::read.csv(csv, stringsAsFactors = FALSE)
  thresh_df <- utils::read.csv(thresholds, stringsAsFactors = FALSE)

  # --- Validate ---
  required <- c("species", "spawn_lake", "spawn_stream",
                 "rear_lake", "rear_lake_only", "rear_no_fw",
                 "rear_stream", "rear_wetland")
  missing <- setdiff(required, names(dimensions))
  if (length(missing) > 0) {
    stop("Dimensions CSV missing columns: ", paste(missing, collapse = ", "))
  }

  # Coerce yes/no to logical
  yn_cols <- setdiff(required, "species")
  for (col in yn_cols) {
    dimensions[[col]] <- tolower(trimws(dimensions[[col]])) == "yes"
  }

  # Optional columns
  has_river_skip <- "river_skip_cw_min" %in% names(dimensions)
  if (has_river_skip) {
    dimensions$river_skip_cw_min <-
      tolower(trimws(dimensions$river_skip_cw_min)) == "yes"
  }

  has_all_edges <- "rear_all_edges" %in% names(dimensions)
  if (has_all_edges) {
    dimensions$rear_all_edges <-
      tolower(trimws(dimensions$rear_all_edges)) == "yes"
  }

  has_soe <- "rear_stream_order_bypass" %in% names(dimensions)
  if (has_soe) {
    dimensions$rear_stream_order_bypass <-
      tolower(trimws(dimensions$rear_stream_order_bypass)) == "yes"
  }

  # Optional: per-species `stream_order_parent_min` for the bypass.
  # Default 5L matches bcfishpass's hard-coded predicate; the column lets
  # callers tune the threshold without editing the rules YAML by hand.
  has_sopm <- "rear_stream_order_parent_min" %in% names(dimensions)

  # Optional: per-species child-order range for the bypass. Both default to
  # 1L (matches bcfp). `_min` and `_max` map to fresh's frs_order_child
  # `child_order_min` and `child_order_max` arguments.
  has_csmin <- "rear_stream_order_child_min" %in% names(dimensions)
  has_csmax <- "rear_stream_order_child_max" %in% names(dimensions)

  # Optional: per-species `distance_max` for the bypass — caps the bypass
  # to the lower N metres of each direct-trib BLK (segment's
  # downstream_route_measure <= distance_max). Empty → no cap (whole BLK).
  has_sodm <- "rear_stream_order_distance_max" %in% names(dimensions)

  # Optional: requires_connected columns (value is the habitat type, not yes/no)
  has_spawn_rc <- "spawn_requires_connected" %in% names(dimensions)
  has_spawn_cdm <- "spawn_connected_distance_max" %in% names(dimensions)

  # Retired (#310): one rear connection test stamped on every rear rule,
  # which fresh >= 0.37.0 refuses everywhere but the first rear L / W rule.
  # Empty columns are ignored so older bundles still build; a value stops.
  cols_rear_rc_legacy <- c("rear_requires_connected",
                           "rear_connected_distance_max")
  cols_rear_rc_legacy <- intersect(cols_rear_rc_legacy, names(dimensions))
  for (col in cols_rear_rc_legacy) {
    v <- trimws(as.character(dimensions[[col]]))
    if (any(!is.na(v) & nzchar(v))) {
      stop(col, " is retired (#310): connect lake / wetland rearing to ",
           "spawning with rear_lake_connected_distance_max / ",
           "rear_wetland_connected_distance_max instead", call. = FALSE)
    }
  }

  # Optional: lake / wetland rearing connected to same-species spawning
  # (#310, fresh#240). A distance (m) puts `requires_connected: spawning`
  # + `connected_distance_max` on the species' first rear L / W rule,
  # which is the one fresh's lake_rearing / wetland_rearing bucket reads.
  read_cdm <- function(col) {
    if (!col %in% names(dimensions)) return(rep(NA_real_, nrow(dimensions)))
    raw <- trimws(as.character(dimensions[[col]]))
    raw[is.na(raw)] <- ""
    n <- suppressWarnings(as.numeric(raw))
    bad <- nzchar(raw) & (is.na(n) | !is.finite(n) | n <= 0)
    if (any(bad)) {
      stop(col, " must be a number > 0 (metres) or blank; got '",
           paste(raw[bad], collapse = "', '"), "' for ",
           paste(dimensions$species[bad], collapse = ", "), call. = FALSE)
    }
    n
  }
  rear_lake_cdm_all    <- read_cdm("rear_lake_connected_distance_max")
  rear_wetland_cdm_all <- read_cdm("rear_wetland_connected_distance_max")

  # Optional: rear_lake_ha_min in dimensions overrides the shared thresholds CSV
  has_rlhm <- "rear_lake_ha_min" %in% names(dimensions)
  has_rwhm <- "rear_wetland_ha_min" %in% names(dimensions)

  # Optional: rear_wetland_polygon — gate emission of the W waterbody rule
  # (which sets the `wetland_rearing` flag from fwa_wetlands_poly polygons).
  # When the flag is absent or yes, both the 1050/1150 stream-flow carve-out
  # AND the W polygon rule are emitted (legacy behavior). When set to no,
  # only the carve-out is emitted — matches bcfishpass's per-species access
  # SQL which uses the carve-out but not a wetland-polygon predicate. The
  # bcfishpass bundle sets this no for CO; default bundle leaves it yes.
  has_rwp <- "rear_wetland_polygon" %in% names(dimensions)
  if (has_rwp) {
    dimensions$rear_wetland_polygon <-
      tolower(trimws(dimensions$rear_wetland_polygon)) == "yes"
  }

  # Per-species control over whether stream-edge spawn / rear rules
  # match segments INSIDE waterbody polygons (where waterbody_key is
  # non-null). The column is yes/no:
  #   yes   → emit no `in_waterbody` field; rule matches segments
  #           inside AND outside polygons (today's permissive
  #           default — polygon-mainlines count too).
  #   no    → emit `in_waterbody: false`; rule matches outside
  #           polygons only (strict partition that pairs cleanly
  #           with the polygon rules `waterbody_type: R/L/W`).
  #   absent → no field; same as yes (backward compat).
  # The third semantic state in the grammar (`in_waterbody: true` =
  # inside polygons only) has no biological use case for stream
  # rules and is not emitted by lnk_rules_build.
  has_ssiw <- "spawn_stream_in_waterbody" %in% names(dimensions)
  if (has_ssiw) {
    dimensions$spawn_stream_in_waterbody <-
      tolower(trimws(dimensions$spawn_stream_in_waterbody)) == "yes"
  }
  has_rsiw <- "rear_stream_in_waterbody" %in% names(dimensions)
  if (has_rsiw) {
    dimensions$rear_stream_in_waterbody <-
      tolower(trimws(dimensions$rear_stream_in_waterbody)) == "yes"
  }

  # Per-species control over whether rear-side L / W polygon rules
  # contribute to the main `rearing` predicate or only to the
  # `lake_rearing` / `wetland_rearing` bucket-flag derivation. When
  # `yes`, the emitted rule carries `area_only: true` (fresh excludes
  # it from the rear OR-chain; the lake_ha_min / wetland_ha_min still
  # drives the bucket pred so polygon area still rolls up). When `no`
  # or absent, the rule contributes to both (today's behaviour).
  has_rlao <- "rear_lake_area_only" %in% names(dimensions)
  if (has_rlao) {
    dimensions$rear_lake_area_only <-
      tolower(trimws(dimensions$rear_lake_area_only)) == "yes"
  }
  has_rwao <- "rear_wetland_area_only" %in% names(dimensions)
  if (has_rwao) {
    dimensions$rear_wetland_area_only <-
      tolower(trimws(dimensions$rear_wetland_area_only)) == "yes"
  }

  # --- Edge type helpers ---
  stream_edges <- if (edge_types == "categories") {
    list(edge_types = c("stream", "canal"))
  } else {
    list(edge_types_explicit = c(1000L, 1100L, 2000L, 2300L))
  }
  # Lines inside a lake or reservoir polygon (#310). Lakes carry FWA
  # construction lines, not mainlines. Province-wide (2026-10-07), lake
  # polygons hold 1200 (main flow, 54,402 km), 1450 (connection, 44,528),
  # 1400 (inferred connection, 6,225), 1475 (lake arm, 2,127) and 1300
  # (secondary flow, 478); reservoirs add 1250 / 1350 (double-line river
  # flow, 24 km). 1000 / 1100 are kept for the odd mainline. 1410
  # (network connector) and 1425 (subsurface) are left out. Codes in
  # either mode: fresh's categories cannot express this set ("connector"
  # holds 1410, "construction" 1550 lakeshore lines and delimiters), and
  # the W polygon rule already uses explicit codes in both modes.
  lake_edges <- list(edge_types_explicit = c(1000L, 1100L, 1200L, 1250L,
                                             1300L, 1350L, 1400L, 1450L,
                                             1475L))

  # --- Build rules per species ---
  species_rules <- list()

  for (i in seq_len(nrow(dimensions))) {
    d <- dimensions[i, ]
    sp <- d$species

    th <- thresh_df[thresh_df$species_code == sp, ]
    if (nrow(th) == 0) {
      message("Skipping ", sp, ": no thresholds in fresh CSV")
      next
    }

    spawn_rules <- list()
    rear_rules <- list()

    # River polygon rule — optionally skip cw_min
    river_rule <- list(waterbody_type = "R")
    if (has_river_skip && d$river_skip_cw_min) {
      river_rule$channel_width <- c(0, 9999)
    }

    # requires_connected values for this species (empty string or NA = none)
    spawn_rc <- if (has_spawn_rc) trimws(as.character(d$spawn_requires_connected)) else ""
    if (is.na(spawn_rc)) spawn_rc <- ""
    spawn_cdm <- if (has_spawn_cdm) as.numeric(d$spawn_connected_distance_max) else NA_real_
    rear_lake_cdm    <- rear_lake_cdm_all[i]
    rear_wetland_cdm <- rear_wetland_cdm_all[i]

    # A species whose spawning requires connected rearing (SK, KO) anchors
    # spawning on its lake rearing. Lake rearing that in turn required
    # spawning would be circular (#310 decision 6). The area_only half of
    # the rule is checked once the rear rules exist, below.
    if (identical(spawn_rc, "rearing")) {
      if (!is.na(rear_lake_cdm) || !is.na(rear_wetland_cdm)) {
        stop(sp, ": spawn_requires_connected = rearing, so its lake / ",
             "wetland rearing cannot also require connected spawning ",
             "(circular); blank its rear_*_connected_distance_max",
             call. = FALSE)
      }
    }

    # Helper: annotate a spawn rule with requires_connected and optional
    # distance max (rear connection is stamped once, after the rules exist)
    add_rc <- function(rule, rc_value, cdm_value = NA_real_) {
      if (nchar(rc_value) > 0) {
        rule$requires_connected <- rc_value
        if (!is.na(cdm_value)) rule$connected_distance_max <- cdm_value
      }
      rule
    }

    # Helper: stamp `in_waterbody: false` onto a stream-edge rule when
    # the per-species column says `no` (strict partition). When the
    # column is `yes` or absent, emit no field — rule matches both
    # inside and outside polygons. Only applied to the main stream-
    # edge rule (the [1000, 1100, 2000, 2300] family) — not to the
    # river polygon rule (waterbody_type: R already implies
    # IS NOT NULL) and not to the 1050/1150 wetland-flow carve-out
    # (those edges are by-definition through wetlands).
    add_iw <- function(rule, in_wb_logical_or_na) {
      if (!is.na(in_wb_logical_or_na) && !isTRUE(in_wb_logical_or_na)) {
        rule$in_waterbody <- FALSE
      }
      rule
    }
    spawn_iw <- if (has_ssiw) d$spawn_stream_in_waterbody else NA
    rear_iw  <- if (has_rsiw) d$rear_stream_in_waterbody  else NA

    # Helper: stamp `area_only: true` on an L / W polygon rule when
    # the per-species column is yes. Decouples bucket-flag derivation
    # (lake_rearing / wetland_rearing — drives area rollups) from the
    # main rear predicate (linear rearing_km). Only applied to rules
    # in the additive rear branch — NOT to the `rear_lake_only` branch
    # where the L rule IS the rear classification.
    add_ao <- function(rule, area_only_logical_or_na) {
      if (!is.na(area_only_logical_or_na) &&
          isTRUE(area_only_logical_or_na)) {
        rule$area_only <- TRUE
      }
      rule
    }
    rear_lao <- if (has_rlao) d$rear_lake_area_only    else NA
    rear_wao <- if (has_rwao) d$rear_wetland_area_only else NA

    # --- Spawning ---
    if (d$spawn_stream) {
      spawn_rules[[length(spawn_rules) + 1]] <-
        add_rc(add_iw(stream_edges, spawn_iw), spawn_rc, spawn_cdm)
      spawn_rules[[length(spawn_rules) + 1]] <- add_rc(river_rule, spawn_rc, spawn_cdm)
    }
    if (d$spawn_lake) {
      spawn_rules[[length(spawn_rules) + 1]] <- add_rc(
        list(waterbody_type = "L"), spawn_rc, spawn_cdm)
    }

    # Resolve ha_min with dimensions-override + fresh-thresholds fallback.
    # Dimensions value wins ONLY when present AND numeric — non-numeric
    # garbage falls through to the fallback rather than silently
    # disabling it.
    resolve_ha_min <- function(dim_val, fresh_val) {
      if (!is.null(dim_val) && !is.na(dim_val) &&
          nchar(trimws(as.character(dim_val))) > 0) {
        n <- suppressWarnings(as.numeric(dim_val))
        if (!is.na(n)) return(n)
      }
      if (!is.null(fresh_val) && !is.na(fresh_val)) return(fresh_val)
      NA_real_
    }

    # --- Rearing (precedence: no_fw > lake_only > additive) ---
    if (d$rear_no_fw) {
      rear_rules <- list()
    } else if (d$rear_lake_only) {
      lake_rule <- list(waterbody_type = "L")
      rlhm <- resolve_ha_min(
        if (has_rlhm) d$rear_lake_ha_min else NULL,
        th$rear_lake_ha_min)
      if (!is.na(rlhm)) lake_rule$lake_ha_min <- rlhm
      rear_rules[[1]] <- lake_rule
    } else {
      # Stream order bypass: first-order streams with parent order
      # >= stream_order_parent_min bypass rearing channel_width_min.
      # Threshold defaults to 5L (bcfishpass parity); per-species
      # `rear_stream_order_parent_min` column overrides when present
      # and numeric.
      soe_bypass <- if (has_soe && d$rear_stream_order_bypass) {
        # Helper: read a positive integer column with default fallback
        read_pos_int <- function(raw, default) {
          if (is.null(raw) || is.na(raw) ||
              nchar(trimws(as.character(raw))) == 0L) return(default)
          n <- suppressWarnings(as.integer(raw))
          if (is.na(n) || n < 1L) return(default)
          n
        }
        pom    <- read_pos_int(if (has_sopm)  d$rear_stream_order_parent_min else NULL, 5L)
        cs_min <- read_pos_int(if (has_csmin) d$rear_stream_order_child_min  else NULL, 1L)
        cs_max <- read_pos_int(if (has_csmax) d$rear_stream_order_child_max  else NULL, 1L)
        out <- list(stream_order_min = cs_min,
                    stream_order_max = cs_max,
                    stream_order_parent_min = pom)
        if (has_sodm) {
          raw_dm <- d$rear_stream_order_distance_max
          if (!is.null(raw_dm) && !is.na(raw_dm) &&
              nchar(trimws(as.character(raw_dm))) > 0) {
            dm <- suppressWarnings(as.numeric(raw_dm))
            if (!is.na(dm) && dm > 0) out$distance_max <- dm
          }
        }
        out
      } else {
        NULL
      }

      if (has_all_edges && d$rear_all_edges) {
        rule <- list()
        if (!is.null(soe_bypass)) rule$channel_width_min_bypass <- soe_bypass
        rear_rules[[length(rear_rules) + 1]] <- rule
      } else if (d$rear_stream) {
        stream_rule <- add_iw(stream_edges, rear_iw)
        if (!is.null(soe_bypass)) stream_rule$channel_width_min_bypass <- soe_bypass
        rear_rules[[length(rear_rules) + 1]] <- stream_rule
        river_rule_r <- river_rule
        if (!is.null(soe_bypass)) river_rule_r$channel_width_min_bypass <- soe_bypass
        rear_rules[[length(rear_rules) + 1]] <- river_rule_r
      }
      if (d$rear_wetland) {
        rwhm <- resolve_ha_min(
          if (has_rwhm) d$rear_wetland_ha_min else NULL,
          NA_real_)
        # Edge-type rule: include wetland-flow streams / shoreline segments
        # in the `rearing` flag (rearing km total).
        carve_rule <- if (edge_types == "categories") {
          list(edge_types = c("wetland"), thresholds = FALSE)
        } else {
          list(edge_types_explicit = c(1050L, 1150L), thresholds = FALSE)
        }
        # Waterbody rule: sets the separate `wetland_rearing` flag in
        # fresh.streams_habitat so polygon-area rollups (ha) can be
        # computed. Mirrors the L pattern below. Gated on
        # rear_wetland_polygon (default yes when column absent).
        # bcfishpass bundle sets this no for CO so the rule output
        # matches bcfishpass's per-species access SQL (which has the
        # 1050/1150 carve-out but no wetland-polygon predicate).
        emit_polygon <- !has_rwp || isTRUE(d$rear_wetland_polygon)
        # A declared rear_wetland_ha_min bounds this rule too (#311), as a
        # W rule with the floor (fresh >= 0.38.0 gates `rearing` on it,
        # fresh#237). Only alongside the polygon rule: without it the
        # floored carve-out would be the only W rule, so fresh would make
        # it the wetland_rearing bucket rule and rear_wetland_polygon = no
        # would stop meaning "no W rule". The type also drops the few 1050
        # lines with no waterbody_key (40 province-wide, 2026-10-07).
        # Unfloored, the carve-out keeps its place.
        carve_floored <- !is.na(rwhm) && emit_polygon
        if (!carve_floored) {
          rear_rules[[length(rear_rules) + 1]] <- carve_rule
        }
        if (emit_polygon) {
          # Polygon rule restricted to mainlines (1000 main flow,
          # 1100 secondary flow). Without the edge filter the rule
          # matches every segment in the polygon (shorelines 1700,
          # construction lines, etc.) and credits them all to linear
          # `rearing` — wider than the fish-bearing channel. With the
          # filter, only the mainlines-through-wetland count for
          # linear; the bucket pred (wetland_rearing) still rolls up
          # the polygon area regardless of which segments are tagged.
          wetland_rule <- list(
            waterbody_type = "W",
            edge_types_explicit = c(1000L, 1100L))
          if (!is.na(rwhm)) wetland_rule$wetland_ha_min <- rwhm
          wetland_rule <- add_ao(wetland_rule, rear_wao)
          rear_rules[[length(rear_rules) + 1]] <- wetland_rule
        }
        # The floored carve-out goes after the polygon rule: fresh takes
        # the FIRST W rule as the wetland_rearing bucket rule and as the
        # requires_connected anchor (.frs_find_waterbody_rule()), and the
        # first L or W rule for waterbody-connected spawning.
        if (carve_floored) {
          carve_rule <- c(list(waterbody_type = "W"), carve_rule,
                          list(wetland_ha_min = rwhm))
          rear_rules[[length(rear_rules) + 1]] <- carve_rule
        }
      }
      if (d$rear_lake) {
        # Lake centrelines count toward `rearing` (#310), with no
        # channel-width or discharge test: lake lines often have no
        # width, and the polygon is the habitat. fresh already skips
        # threshold inheritance on L / W rules; `thresholds: false` states
        # it in the rules. area_only keeps the rule out of `rearing`.
        lake_rule <- c(list(waterbody_type = "L"), lake_edges,
                       list(thresholds = FALSE))
        rlhm <- resolve_ha_min(
          if (has_rlhm) d$rear_lake_ha_min else NULL,
          th$rear_lake_ha_min)
        if (!is.na(rlhm)) lake_rule$lake_ha_min <- rlhm
        lake_rule <- add_ao(lake_rule, rear_lao)
        rear_rules[[length(rear_rules) + 1]] <- lake_rule
      }
    }

    # Connected lake / wetland rearing (#310): only the first rear rule of
    # each waterbody type, which fresh reads for the bucket and refuses
    # `requires_connected` on any later one (.frs_validate_rear_connected).
    for (wt in c("L", "W")) {
      cdm <- if (wt == "L") rear_lake_cdm else rear_wetland_cdm
      if (is.na(cdm)) next
      is_wt <- vapply(rear_rules, function(r) {
        identical(r[["waterbody_type"]], wt)
      }, logical(1))
      idx <- which(is_wt)
      if (length(idx) == 0L) {
        stop(sp, ": ", if (wt == "L") "rear_lake" else "rear_wetland",
             "_connected_distance_max is set but the species has no rear ",
             "waterbody_type: ", wt, " rule to carry it", call. = FALSE)
      }
      rear_rules[[idx[1]]]$requires_connected <- "spawning"
      rear_rules[[idx[1]]]$connected_distance_max <- cdm
    }

    # fresh anchors waterbody-connected spawning on the species' first
    # rear L or W rule (.frs_run_connectivity()) and reads `rearing` there.
    # An area_only anchor is not `rearing`, so spawning would lose it.
    # Read the anchor the way fresh does rather than assume it is the lake.
    if (identical(spawn_rc, "rearing")) {
      is_anchor <- vapply(rear_rules, function(r) {
        isTRUE(r[["waterbody_type"]] %in% c("L", "W"))
      }, logical(1))
      anchor <- rear_rules[which(is_anchor)[1]][[1]]
      if (!is.null(anchor) && isTRUE(anchor[["area_only"]])) {
        stop(sp, ": rear_", if (anchor$waterbody_type == "L") "lake" else
               "wetland", "_area_only = yes would take its spawning anchor ",
             "(the first rear waterbody_type: ", anchor$waterbody_type,
             " rule) out of rearing (spawn_requires_connected = rearing)",
             call. = FALSE)
      }
    }

    # --- spawn_connected (permissive rules for waterbody-adjacent spawning) ---
    spawn_conn <- NULL
    if ("spawn_connected_direction" %in% names(d) &&
        !is.na(d$spawn_connected_direction) &&
        nchar(trimws(d$spawn_connected_direction)) > 0) {
      spawn_conn <- list(
        direction = trimws(d$spawn_connected_direction))
      # waterbody_type from spawn_requires_connected target's rearing rules
      # (SK requires_connected = rearing, rearing is waterbody_type L → L)
      rear_wb <- NULL
      for (rr in rear_rules) {
        if (!is.null(rr[["waterbody_type"]])) { rear_wb <- rr[["waterbody_type"]]; break }
      }
      if (!is.null(rear_wb)) spawn_conn$waterbody_type <- rear_wb
      if ("spawn_connected_gradient_max" %in% names(d) && !is.na(d$spawn_connected_gradient_max))
        spawn_conn$gradient_max <- as.numeric(d$spawn_connected_gradient_max)
      if ("spawn_connected_cw_min" %in% names(d) && !is.na(d$spawn_connected_cw_min))
        spawn_conn$channel_width_min <- as.numeric(d$spawn_connected_cw_min)
      if ("spawn_connected_distance_max" %in% names(d) && !is.na(d$spawn_connected_distance_max))
        spawn_conn$distance_max <- as.numeric(d$spawn_connected_distance_max)
      # bridge_gradient = gradient_max (the trace stops at this gradient)
      spawn_conn$bridge_gradient <- spawn_conn$gradient_max
      # edge_types: null = no filter, otherwise parse semicolon-separated
      if ("spawn_connected_edge_types" %in% names(d) && !is.na(d$spawn_connected_edge_types) &&
          nchar(trimws(d$spawn_connected_edge_types)) > 0) {
        spawn_conn$edge_types <- as.integer(strsplit(trimws(d$spawn_connected_edge_types), ";")[[1]])
      }
      # lake_adjacent: TRUE/FALSE per fresh#191. Default at fresh side is TRUE
      # (bcfp parity — Phase 2 cluster + lake-adjacency gate fires). Setting
      # FALSE relaxes the cluster gate, crediting any spawn-eligible segment
      # upstream of and accessible from the qualifying rearing waterbody.
      # Only emit when the dimension is non-empty so older rules.yaml files
      # without the key remain valid.
      if ("spawn_connected_lake_adjacent" %in% names(d) &&
          !is.na(d$spawn_connected_lake_adjacent) &&
          nchar(trimws(d$spawn_connected_lake_adjacent)) > 0) {
        spawn_conn$lake_adjacent <-
          tolower(trimws(d$spawn_connected_lake_adjacent)) == "yes"
      }
    }

    sp_entry <- list(spawn = spawn_rules, rear = rear_rules)
    if (!is.null(spawn_conn)) sp_entry$spawn_connected <- spawn_conn
    species_rules[[sp]] <- sp_entry
  }

  # --- Write YAML ---
  header <- c(
    sprintf("# Generated from %s", basename(csv)),
    sprintf("# Generated: %s", format(Sys.Date(), "%Y-%m-%d")),
    sprintf("# Edge types: %s", edge_types),
    "#",
    "# DO NOT EDIT — edit the CSV and re-run lnk_rules_build()",
    ""
  )

  yaml_body <- yaml::as.yaml(species_rules,
    indent = 2,
    handlers = list(
      logical = function(x) {
        v <- ifelse(x, "true", "false")
        class(v) <- "verbatim"
        v
      }
    )
  )

  writeLines(c(header, yaml_body), to)
  message("Wrote ", to, " (", length(species_rules), " species, ", edge_types, " edge types)")
  invisible(to)
}
