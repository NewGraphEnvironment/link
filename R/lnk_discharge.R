#' Mean annual discharge per FWA line, as every consumer reads it
#'
#' One subquery, `(linear_feature_id, mad_m3s, mad_m3s_source)`, read by
#' prepare (onto the working streams), the validator and the scoring harness,
#' so a filled value cannot differ between classify and the score (#305).
#'
#' Read from the bundle's source (`.lnk_discharge_source()`, #331). fwapg's
#' `whse_basemapping.fwa_stream_networks_discharge` has no value on part of
#' the main flow through double-line river polygons (edge type 1250): in the
#' WSGs it covers, 22 % of edge 1250 km, almost all of it order 4+. Under the
#' `mad` model a NULL fails every size test, so those reaches leave stream
#' habitat. With `fill = TRUE`, an edge 1250 line with no value takes, in
#' order:
#' 1. `fill_upstream`: the nearest valued line upstream on the same
#'    `blue_line_key` (higher `downstream_route_measure`). Discharge grows
#'    downstream, so this is a lower bound on the line's own.
#' 2. `fill_downstream`: else the nearest valued line downstream on the same
#'    `blue_line_key`, an upper bound.
#' 3. `fill_tributary_max`: else, for a river with no value anywhere on its
#'    `blue_line_key` (the Beatton in UBTN), the largest value on any line
#'    upstream of it (`fwa_upstream()`), a lower bound. A downstream line is
#'    never used: it is the receiving river, which can be orders of magnitude
#'    larger.
#'
#' A lower bound is safe against a MAD minimum (a filled value that clears it
#' means the true one does), and can be wrong against a maximum. Other edge
#' types are never filled, and a line no tier reaches stays NULL. Nor is a
#' line in a watershed group the discharge table does not cover (no valued
#' row): there a stray upstream line would hand an order-9 main stem a
#' headwater's value, and "no discharge" would read as "below the minimum".
#'
#' `mad_m3s_source` is `modelled` (the table's own value), one of the three
#' tiers, or NULL where `mad_m3s` is NULL.
#'
#' @param wsg Character. Watershed groups (FWA's `watershed_group_code`) whose
#'   lines the subquery returns.
#' @param fill Logical. Fill edge 1250 lines along their `blue_line_key`.
#' @param lines Optional SQL subquery returning `linear_feature_id`s, scoping
#'   the lines instead of (or as well as) `wsg`. The validator scopes by the
#'   lines of the schema it scores, not by FWA's group.
#' @param source Character. Where the discharge is read from:
#'   `.lnk_discharge_source()`'s values. The fill reads the same source.
#'
#' With `fill = TRUE`, `wsg` or `lines` is required (the fill is a per-line
#' lateral lookup); with `fill = FALSE` both are ignored and the subquery is
#' the whole table. A neighbour or tributary is looked up across every group
#' either way, so a line's filled value does not depend on the scope.
#' @return A parenthesised SQL subquery, usable as `FROM <it> d`.
#' @noRd
.lnk_discharge_sql <- function(wsg = NULL, fill = FALSE, lines = NULL,
                              source = "fwapg") {
  tbl <- .lnk_discharge_rel(source)
  if (!isTRUE(fill)) {
    return(sprintf(
      "(SELECT linear_feature_id, mad_m3s,
               CASE WHEN mad_m3s IS NOT NULL THEN 'modelled' END
                 AS mad_m3s_source
          FROM %s)", tbl))
  }
  sprintf(
    "(SELECT c.linear_feature_id,
             coalesce(c.mad_m3s, c.mad_m3s_up, c.mad_m3s_dn,
                      c.mad_m3s_trib) AS mad_m3s,
             CASE WHEN c.mad_m3s IS NOT NULL THEN 'modelled'
                  WHEN c.mad_m3s_up IS NOT NULL THEN 'fill_upstream'
                  WHEN c.mad_m3s_dn IS NOT NULL THEN 'fill_downstream'
                  WHEN c.mad_m3s_trib IS NOT NULL THEN 'fill_tributary_max'
             END AS mad_m3s_source
        FROM %s c)",
    .lnk_discharge_candidates_sql(wsg, targets = "null", lines = lines,
                                  source = source))
}

#' Fill candidates per line: the table's value and both neighbours
#'
#' The lateral lookups behind `.lnk_discharge_sql(fill = TRUE)`, exposed so
#' the fill can be measured with the SQL that ships
#' (`data-raw/discharge_fill_count.R`). `targets = "null"` runs each lookup
#' only where the fill needs it: edge 1250 lines with no value, and the
#' tributary lookup only where neither same-line neighbour exists.
#' `targets = "all"` runs every lookup for every edge 1250 line, so a valued
#' line can be masked and its true value compared with what each tier would
#' give; the tributary lookup costs about a quarter of a second per line, so
#' pair `"all"` with a sampling `where`. A neighbour is never the line itself
#' (strict measure inequalities), and the tributary lookup never reads the
#' line's own `blue_line_key`. `gap_up_m` / `gap_dn_m` are the distances to
#' the neighbour along the `blue_line_key`, in metres.
#'
#' Every line of `wsg` is returned (the fill coalesces over them all); the
#' lookups are NULL where they did not run.
#'
#' @param wsg,lines Scope, as in `.lnk_discharge_sql()`; one is required.
#' @param targets `"null"` or `"all"`.
#' @param where Optional extra SQL predicate on the outer line `s`.
#' @param tributary Logical. Run the tributary lookup at all; `FALSE` skips it
#'   (its column is NULL), for a measurement over every line.
#' @return A parenthesised SQL subquery.
#' @noRd
.lnk_discharge_candidates_sql <- function(wsg = NULL,
                                          targets = c("null", "all"),
                                          where = NULL, tributary = TRUE,
                                          lines = NULL, source = "fwapg") {
  targets <- match.arg(targets)
  if (!is.null(wsg) && (length(wsg) == 0L || anyNA(wsg) ||
                          !all(nzchar(wsg)))) {
    stop("wsg must name at least one watershed group to fill discharge for",
         call. = FALSE)
  }
  if (is.null(wsg) && is.null(lines)) {
    stop("wsg or lines must scope the lines to fill discharge for",
         call. = FALSE)
  }
  scope <- c(
    if (!is.null(wsg)) sprintf("s.watershed_group_code IN (%s)",
      paste(vapply(wsg, .lnk_quote_literal, ""), collapse = ", ")),
    if (!is.null(lines)) sprintf("s.linear_feature_id IN (%s)", lines),
    if (!is.null(where)) sprintf("(%s)", where))
  tbl <- .lnk_discharge_rel(source)
  gate <- if (identical(targets, "null")) {
    "s.edge_type = 1250 AND cov.covered AND d.mad_m3s IS NULL"
  } else {
    "s.edge_type = 1250 AND cov.covered"
  }
  gate_trib <- if (!isTRUE(tributary)) {
    "FALSE"
  } else if (identical(targets, "null")) {
    paste(gate, "AND up.mad_m3s IS NULL AND dn.mad_m3s IS NULL")
  } else {
    gate
  }
  # The gate sits inside each lateral, where it references only the outer row
  # and so runs as a one-time filter: no lookup for lines the fill skips.
  # Ties on measure are broken on linear_feature_id so the pick is fixed.
  sprintf(
    "(SELECT s.linear_feature_id, s.watershed_group_code, s.edge_type,
             s.stream_order, s.blue_line_key, s.length_metre,
             d.linear_feature_id IS NOT NULL AS in_table,
             coalesce(cov.covered, false) AS group_covered,
             d.mad_m3s,
             up.mad_m3s AS mad_m3s_up, up.gap_m AS gap_up_m,
             dn.mad_m3s AS mad_m3s_dn, dn.gap_m AS gap_dn_m,
             trib.mad_m3s AS mad_m3s_trib
        FROM whse_basemapping.fwa_stream_networks_sp s
        LEFT JOIN %1$s d ON d.linear_feature_id = s.linear_feature_id
        LEFT JOIN (SELECT DISTINCT watershed_group_code, true AS covered
                     FROM %1$s WHERE mad_m3s IS NOT NULL) cov
          ON cov.watershed_group_code = s.watershed_group_code
        LEFT JOIN LATERAL (
          SELECT d2.mad_m3s,
                 s2.downstream_route_measure - s.upstream_route_measure AS gap_m
            FROM whse_basemapping.fwa_stream_networks_sp s2
            JOIN %1$s d2 ON d2.linear_feature_id = s2.linear_feature_id
           WHERE %2$s
             AND s2.blue_line_key = s.blue_line_key
             AND s2.downstream_route_measure > s.downstream_route_measure
             AND d2.mad_m3s IS NOT NULL
           ORDER BY s2.downstream_route_measure, s2.linear_feature_id
           LIMIT 1) up ON TRUE
        LEFT JOIN LATERAL (
          SELECT d2.mad_m3s,
                 s.downstream_route_measure - s2.upstream_route_measure AS gap_m
            FROM whse_basemapping.fwa_stream_networks_sp s2
            JOIN %1$s d2 ON d2.linear_feature_id = s2.linear_feature_id
           WHERE %2$s
             AND s2.blue_line_key = s.blue_line_key
             AND s2.downstream_route_measure < s.downstream_route_measure
             AND d2.mad_m3s IS NOT NULL
           ORDER BY s2.downstream_route_measure DESC, s2.linear_feature_id
           LIMIT 1) dn ON TRUE
        LEFT JOIN LATERAL (
          SELECT max(d2.mad_m3s) AS mad_m3s
            FROM whse_basemapping.fwa_stream_networks_sp s2
            JOIN %1$s d2 ON d2.linear_feature_id = s2.linear_feature_id
           WHERE %4$s
             AND s2.wscode_ltree <@ s.wscode_ltree
             AND whse_basemapping.fwa_upstream(
                   s.wscode_ltree, s.localcode_ltree,
                   s2.wscode_ltree, s2.localcode_ltree)
             AND s2.blue_line_key <> s.blue_line_key
             AND d2.mad_m3s IS NOT NULL) trib ON TRUE
       WHERE %3$s)",
    tbl, gate, paste(scope, collapse = "\n         AND "), gate_trib)
}

#' Where a bundle reads discharge from (`cfg$pipeline$discharge_source`, #331)
#'
#' `fwapg` is `whse_basemapping.fwa_stream_networks_discharge`, which every
#' run before #331 read. `wet` is the annual pick of wet's published
#' `discharge.fwa_v1_segment_monthly` (`historical`, `month = 0`, `pick`),
#' loaded with `wet::wet_db_load()`. Absent means `fwapg`, so a bundle that
#' says nothing reads what it always read.
#'
#' wet's annual value is 0 on about 29,500 lines (mostly its water balance,
#' where evaporation takes all the runoff). link reads a 0 as no value
#' (operator, 2026-10-15): a line the model calls dry has no discharge to
#' size habitat by, a 0 at a fish location would floor an observed minimum
#' to no minimum at all, and an edge 1250 line at 0 can then be filled.
#'
#' @param cfg An `lnk_config`.
#' @return `"fwapg"` or `"wet"`.
#' @noRd
.lnk_discharge_source <- function(cfg) {
  v <- cfg$pipeline$discharge_source
  if (is.null(v)) return("fwapg")
  .lnk_discharge_source_check(v, paste0("cfg '", cfg$name, "'"))
}

#' Validate a discharge source value
#' @noRd
.lnk_discharge_source_check <- function(v, what = "discharge_source") {
  ok <- names(.lnk_discharge_sources())
  if (!is.character(v) || length(v) != 1L || is.na(v) || !v %in% ok) {
    stop(what, ": discharge_source must be one of ",
         paste(ok, collapse = ", "), call. = FALSE)
  }
  v
}

#' The discharge sources: the table each reads, and the relation over it
#'
#' Each relation has fwapg's shape, `(linear_feature_id,
#' watershed_group_code, mad_m3s)` with one row per line, so it can stand
#' wherever the table name stood (`FROM <rel> d`, `JOIN <rel> d2`). wet's
#' predicate is its partial index's (`month = 0 AND pick`), so a lookup by
#' `linear_feature_id` uses it.
#' @noRd
.lnk_discharge_sources <- function() {
  list(
    fwapg = list(
      table = "whse_basemapping.fwa_stream_networks_discharge",
      rel = "whse_basemapping.fwa_stream_networks_discharge"),
    wet = list(
      table = "discharge.fwa_v1_segment_monthly",
      rel = paste0(
        "(SELECT linear_feature_id, watershed_group_code,",
        " nullif(q_m3s, 0) AS mad_m3s",
        " FROM discharge.fwa_v1_segment_monthly",
        " WHERE scenario = 'historical' AND month = 0 AND pick)")))
}

#' Which published load of wet's discharge a table comment names
#'
#' wet's loader writes `... last loaded from <manifest> (built <time>, wet
#' <commit>)` into the table comment, and appends `; subset ...` to a partial
#' load (`months` / `pick_only`). The load is the comment without that
#' suffix: an annual-pick load and a full one of the same build hold the same
#' annual values.
#' @noRd
.lnk_discharge_wet_load_id <- function(comment) {
  sub("; subset .*$", "", comment)
}

#' The table a discharge source is stored in (to check, fingerprint, record)
#' @noRd
.lnk_discharge_tbl <- function(source = "fwapg") {
  .lnk_discharge_sources()[[.lnk_discharge_source_check(source)]]$table
}

#' The relation a discharge source is read through
#' @noRd
.lnk_discharge_rel <- function(source = "fwapg") {
  .lnk_discharge_sources()[[.lnk_discharge_source_check(source)]]$rel
}

#' Whether a bundle fills discharge (`cfg$pipeline$discharge_fill`, #305)
#'
#' Absent means `FALSE`: only `default_tuned` sets it, so `default`,
#' `bcfishpass` and the bundles with `extends: ~` keep the raw table.
#' @noRd
.lnk_discharge_fill <- function(cfg) {
  isTRUE(cfg$pipeline$discharge_fill)
}

#' Whether the fill is applied to a watershed group's lines
#'
#' The knob, and something that reads discharge there: `cfg`'s method table
#' puts the group on `mad`, or the rules carry a rule-level `mad:` (which
#' reaches `s.mad_m3s` on a `cw` group too). A `cw` group under a filling
#' bundle is not filled, so an all-`cw` run neither pays for the lookups nor
#' depends on them. prepare, the run log, the validator's log check and the
#' variants harness all decide with this, so they cannot disagree. The
#' method table is `cfg`'s; `lnk_pipeline_classify(method_csv =)` is
#' invisible here, as it is to the validator.
#'
#' @param cfg An `lnk_config`.
#' @param aoi Character. Watershed groups; `TRUE` when any of them applies.
#' @noRd
.lnk_discharge_fill_applied <- function(cfg, aoi) {
  .lnk_discharge_fill(cfg) && .lnk_discharge_read(cfg, aoi)
}

#' Whether classification reads discharge in any of these watershed groups
#'
#' `cfg`'s method table puts one on `mad`, or the rules read discharge on
#' a `cw` group too: a rule-level `mad:`, or a near_river pair measured by
#' discharge (`.lnk_discharge_read_rules()`). Where none does, neither the
#' fill nor the source can move a habitat flag, so the validator's log
#' checks skip those groups.
#' @noRd
.lnk_discharge_read <- function(cfg, aoi) {
  any(.lnk_discharge_read_each(cfg, aoi))
}

#' `.lnk_discharge_read()` per watershed group, reading the rules and the
#' method table once
#' @noRd
.lnk_discharge_read_each <- function(cfg, aoi) {
  if (length(aoi) == 0L) return(logical(0))
  if (.lnk_discharge_read_rules(cfg)) return(rep(TRUE, length(aoi)))
  meth <- suppressMessages(.lnk_habitat_method_csv(cfg))
  .lnk_wsg_model(.lnk_habitat_method_read(meth), aoi) == "mad"
}

#' Write `mad_m3s` and `mad_m3s_source` onto a streams table
#'
#' The columns are added as `double precision` and `text` here, not by
#' `fresh::frs_col_join()`, which types a subquery's columns `text`; fresh's
#' `mad` predicate (`s.mad_m3s BETWEEN ...`) has no operator for text.
#' Re-runnable: both columns are rewritten in full, so a working table built
#' on one fill state can be moved to the other (the variants harness does).
#'
#' @param conn A DBI connection.
#' @param table Schema-qualified streams table carrying `linear_feature_id`
#'   and `watershed_group_code`.
#' @param aoi Character. Watershed groups of `table` to write.
#' @param fill,source See `.lnk_discharge_sql()`.
#' @noRd
.lnk_discharge_join <- function(conn, table, aoi, fill = FALSE,
                                source = "fwapg") {
  .lnk_validate_identifier(table, "table")
  # Fail with the way to load it, not with a missing-relation error (#331).
  chk <- lnk_preflight_discharge(
    conn, list(pipeline = list(discharge_source = source)), quiet = TRUE)
  if (!chk$ok) stop(chk$message, call. = FALSE)
  .lnk_db_execute(conn, sprintf(
    "ALTER TABLE %s
       ADD COLUMN IF NOT EXISTS mad_m3s double precision,
       ADD COLUMN IF NOT EXISTS mad_m3s_source text", table))
  aoi_sql <- paste(vapply(aoi, .lnk_quote_literal, ""), collapse = ", ")
  .lnk_db_execute(conn, sprintf(
    "UPDATE %s t SET mad_m3s = NULL, mad_m3s_source = NULL
      WHERE t.watershed_group_code IN (%s)", table, aoi_sql))
  .lnk_db_execute(conn, sprintf(
    "UPDATE %s t SET mad_m3s = d.mad_m3s, mad_m3s_source = d.mad_m3s_source
       FROM %s d
      WHERE d.linear_feature_id = t.linear_feature_id
        AND t.watershed_group_code IN (%s)",
    table, .lnk_discharge_sql(aoi, fill = fill, source = source), aoi_sql))
  invisible(NULL)
}

#' Whether a bundle's rules read discharge on a `cw` group
#'
#' True when a rule carries a rule-level `mad:` (which reaches `s.mad_m3s`
#' under either model), or when any near_river pair a species of `cfg`
#' would walk under `cw` measures by discharge (an explicit `discharge`
#' measure; `model` resolves to channel width under `cw`). The pairs come
#' from fresh's own resolver (`.lnk_near_river_pairs()`), so a
#' `near_river: false` never counts and link never re-derives inheritance.
#' A `mad` group reads discharge through the method table anyway.
#' Read from the rules as fresh parses them (`fresh::frs_params()`), not
#' from the YAML text, so a flow-style or quoted key counts exactly when
#' fresh applies it. Bundle-level: every caller passes `cfg` only, and a
#' needless fill where a species is absent moves no flag.
#' @noRd
.lnk_discharge_read_rules <- function(cfg) {
  params <- .lnk_frs_params(cfg)
  # names(), not `$` or `[[`: `$` partial-matches and `[[` errors on an
  # atomic element.
  mad_rule <- any(vapply(params, function(sp) {
    if (!is.list(sp) || !is.list(sp$rules)) return(FALSE)
    any(vapply(sp$rules, function(stage) {
      any(vapply(stage, function(r) is.list(r) && "mad" %in% names(r),
                 logical(1)))
    }, logical(1)))
  }, logical(1)))
  mad_rule || any(.lnk_near_river_pairs(cfg, "cw", params)$measure ==
                    "discharge")
}

#' fresh's parameters for a bundle: its thresholds CSV and its rules
#' @noRd
.lnk_frs_params <- function(cfg) {
  suppressMessages(fresh::frs_params(
    csv = .lnk_habitat_thresholds_csv(cfg), rules_yaml = cfg$rules))
}

#' The near_river pairs a bundle's rules read, from fresh's resolver
#'
#' `fresh:::.frs_near_river_specs()`, the function `frs_habitat_classify()`
#' collects its walks with: each rule's own mapping, or the pair it
#' inherits from the thresholds CSV when it has a size test, never a
#' `near_river: false`. Species are `cfg$species` (all of the bundle's
#' when unset); `models` the size models to resolve under (`model`
#' measures by width under `cw` and discharge under `mad`).
#'
#' @param cfg An `lnk_config`.
#' @param models Character, `"cw"` and / or `"mad"`.
#' @param params Optional, `.lnk_frs_params(cfg)` already read.
#' @param species Optional, the species to resolve for; default every
#'   species of `cfg`.
#' @return A data frame of `measure`, `threshold`, `distance_max`, one row
#'   per distinct pair; zero rows when no rule reads one.
#' @noRd
.lnk_near_river_pairs <- function(cfg, models = "cw", params = NULL,
                                  species = NULL) {
  if (is.null(params)) params <- .lnk_frs_params(cfg)
  species <- species %||% cfg[["species"]] %||% names(params)
  specs <- utils::getFromNamespace(".frs_near_river_specs", "fresh")
  specs(params, intersect(species, names(params)), unique(models))
}

#' A near_river pair set as one text value, for the run log
#'
#' `measure:threshold:distance_max`, sorted in byte order, joined with `;`; `""` when
#' there is none, so a logged "no pair" is distinct from a pre-#364 NULL.
#' Numbers go through `format(digits = 15)` so the text round-trips.
#' @noRd
.lnk_near_river_text <- function(pairs) {
  if (is.null(pairs) || nrow(pairs) == 0) return("")
  x <- sprintf("%s:%s:%s", pairs$measure,
               format(pairs$threshold, digits = 15, trim = TRUE),
               format(pairs$distance_max, digits = 15, trim = TRUE))
  # radix: byte order on every host, whatever LC_COLLATE says, because the
  # text is written on the build host and compared on the validating one.
  paste(sort(unique(x), method = "radix"), collapse = ";")
}

#' The near_river pairs `cfg` resolves for watershed groups, as log text
#'
#' Under the size model each group is on in `cfg`'s method table; one
#' text value for the set of groups.
#' @noRd
.lnk_near_river_logged <- function(cfg, aoi) {
  meth <- suppressMessages(.lnk_habitat_method_csv(cfg))
  models <- unique(.lnk_wsg_model(.lnk_habitat_method_read(meth), aoi))
  if (length(models) == 0) models <- "cw"
  .lnk_near_river_text(.lnk_near_river_pairs(cfg, models))
}
