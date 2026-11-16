#' Which fish records count, as which species (the record rule)
#'
#' One rule decides which bcfishobs records a build reads, and as which model
#' species, wherever records are read: the observation breaks, code 2 of the
#' access walk ("accessible, a record of the species upstream") and the
#' barrier lifts (link#470; #400, #398, #425). For each watershed group in
#' `wsgs`, each species the group's presence row marks present, and each code
#' records are filed under that counts as it:
#'
#' - **Codes.** The species' own code always counts. Where the bundle declares
#'   a pooling tracker (`species_pooling.csv`), [lnk_species_pooling()]
#'   adds what it pools: another species' records (DV as BT where the tracker
#'   says the two names mean one species) and alias codes that are no species
#'   column (`SST` and `WST` as ST, `CCT` as CT, `BT/DV` as BT where DV pools
#'   into BT). A bundle with no tracker counts each species' own code only,
#'   as bcfishpass does: its `load_observations.sql` tests the recorded code
#'   against the presence table's codes, so alias records never reach
#'   `bcfishpass.observations` (`smnorris/bcfishpass@3bd2824`).
#' - **Dates.** `pipeline: observation_record_date:` `any` (when absent) counts
#'   every record whatever its date. `lift_floor` holds each target species'
#'   records to its own lift floor (`parameters_fresh.csv`
#'   `observation_date_min`): a record on or after the floor counts, an
#'   undated one does not; a species with no floor counts every record,
#'   undated included.
#' - **Year limits.** A tracker row's `obs_year_max` limits that pooled code
#'   to records dated in or before the year; an undated record does not meet
#'   it.
#'
#' Presence is the record's own group's, as before: a record counts only as a
#' species its own group marks present.
#'
#' @param cfg A config from [lnk_config()].
#' @param loaded Named list from [lnk_load_overrides()].
#' @param wsgs Character vector of watershed group codes.
#' @return Data frame, one row per group, target species and recorded code:
#'   `watershed_group_code`, `species_obs` (the recorded code),
#'   `species_code` (the model species it counts as), `date_min` (Date, NA
#'   for no floor) and `year_max` (integer, NA for no limit).
#' @noRd
.lnk_observation_species_map <- function(cfg, loaded, wsgs) {
  pres <- loaded$wsg_species_presence
  if (is.null(pres)) {
    stop("loaded$wsg_species_presence is required for the record rule",
         call. = FALSE)
  }
  empty <- data.frame(watershed_group_code = character(0),
                      species_obs = character(0), species_code = character(0),
                      date_min = as.Date(character(0)),
                      year_max = integer(0), stringsAsFactors = FALSE)
  wsgs <- intersect(unique(toupper(trimws(wsgs))),
                    toupper(trimws(pres$watershed_group_code)))
  if (length(wsgs) == 0L) return(empty)

  if (!is.null(loaded$species_pooling)) {
    sp_all <- toupper(.lnk_presence_species_cols(pres))
    p <- lnk_species_pooling(loaded, aoi = wsgs, species = sp_all)
    m <- data.frame(watershed_group_code = p$watershed_group_code,
                    species_obs = p$obs_species,
                    species_code = p$species_code,
                    year_max = as.integer(p$obs_year_max),
                    stringsAsFactors = FALSE)
  } else {
    rows <- lapply(wsgs, function(w) {
      row <- pres[toupper(trimws(pres$watershed_group_code)) == w, ,
                  drop = FALSE]
      sp <- toupper(.lnk_wsg_species_present(row))
      if (length(sp) == 0L) return(NULL)
      data.frame(watershed_group_code = w, species_obs = sp,
                 species_code = sp, year_max = NA_integer_,
                 stringsAsFactors = FALSE)
    })
    m <- do.call(rbind, rows)
    if (is.null(m)) return(empty)
  }

  m$date_min <- as.Date(NA)
  if (identical(.lnk_observation_record_date(cfg), "lift_floor")) {
    pf <- loaded$parameters_fresh
    if (is.null(pf) || !all(c("species_code", "observation_date_min") %in%
                            names(pf))) {
      stop("observation_record_date: lift_floor needs parameters_fresh ",
           "with species_code and observation_date_min", call. = FALSE)
    }
    key <- toupper(trimws(pf$species_code))
    raw <- trimws(as.character(pf$observation_date_min))
    raw[raw %in% c("", "NA")] <- NA
    floor <- as.Date(raw)
    if (any(!is.na(raw) & is.na(floor))) {
      stop("parameters_fresh observation_date_min is not a date: ",
           paste(raw[!is.na(raw) & is.na(floor)], collapse = ", "),
           call. = FALSE)
    }
    # A lift counts the rows of every species its list names, each already
    # held to its own floor, and then applies its own floor again
    # (lnk_barrier_overrides()). A list mixing floors would silently take the
    # stricter one, so it is refused.
    thr <- suppressWarnings(as.numeric(pf$observation_threshold %||%
                                         rep(NA, nrow(pf))))
    for (i in which(!is.na(thr) & thr > 0)) {
      lst <- as.character(pf$observation_species[i])
      lst <- if (is.na(lst)) key[i] else toupper(trimws(strsplit(lst, ";")[[1]]))
      f <- floor[match(lst, key)]
      own <- floor[i]
      same <- (is.na(f) & is.na(own)) | (!is.na(f) & !is.na(own) & f == own)
      if (!all(same)) {
        stop("observation_record_date: lift_floor: ", key[i], "'s lift counts ",
             paste(lst[!same], collapse = ", "), ", whose date floor differs ",
             "from its own; give them one floor", call. = FALSE)
      }
    }
    # first row per species, as the pipeline reads parameters_fresh
    m$date_min <- floor[match(m$species_code, key)]
  }
  m <- m[, c("watershed_group_code", "species_obs", "species_code",
             "date_min", "year_max")]
  m <- m[order(m$watershed_group_code, m$species_code, m$species_obs,
               method = "radix"), , drop = FALSE]
  rownames(m) <- NULL
  m
}


#' The species map as a SQL `VALUES` list
#'
#' Columns `(watershed_group_code, species_obs, species_code, date_min,
#' year_max)`, each value typed so an all-NULL column still casts.
#' @noRd
.lnk_obs_species_values <- function(map) {
  lit <- function(x) vapply(x, .lnk_quote_literal, character(1))
  ds <- format(map$date_min, "%Y-%m-%d")
  ds[is.na(map$date_min)] <- ""
  d <- ifelse(is.na(map$date_min), "NULL::date", paste0(lit(ds), "::date"))
  y <- ifelse(is.na(map$year_max), "NULL::integer",
              paste0(as.integer(map$year_max), "::integer"))
  paste(sprintf("(%s, %s, %s, %s, %s)", lit(map$watershed_group_code),
                lit(map$species_obs), lit(map$species_code), d, y),
        collapse = ", ")
}


#' Build an observation table under the record rule
#'
#' One row per record and model species it counts as: `species_code` is the
#' model species, `species_code_recorded` the code the record is filed under.
#' A record counting as two species (DV where DV pools into BT and DV is
#' present) has two rows with one `observation_key`; every reader keys on the
#' species or counts distinct keys.
#' @noRd
.lnk_observation_table_build <- function(conn, to, observations, map,
                                         where = "", excl_filter = "") {
  .lnk_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", to))
  if (nrow(map) == 0L) {
    .lnk_db_execute(conn, sprintf(
      "CREATE TABLE %s AS SELECT o.*, o.species_code AS species_code_model
       FROM %s o WHERE FALSE", to, observations))
  } else {
    .lnk_db_execute(conn, sprintf(
      "CREATE TABLE %s AS
       SELECT o.*, m.species_code AS species_code_model
       FROM %s o
       JOIN (VALUES %s) m (watershed_group_code, species_obs, species_code,
                           date_min, year_max)
         ON m.watershed_group_code = o.watershed_group_code
        AND m.species_obs = o.species_code
       WHERE (m.date_min IS NULL OR o.observation_date >= m.date_min)
         AND (m.year_max IS NULL
              OR extract(year FROM o.observation_date) <= m.year_max)
       %s
       %s",
      to, observations, .lnk_obs_species_values(map), where,
      excl_filter))
  }
  .lnk_db_execute(conn, sprintf(
    "ALTER TABLE %s RENAME COLUMN species_code TO species_code_recorded", to))
  .lnk_db_execute(conn, sprintf(
    "ALTER TABLE %s RENAME COLUMN species_code_model TO species_code", to))
  invisible(NULL)
}


#' Which dates a record needs to count
#'
#' The bundle's `pipeline: observation_record_date:` value, `any` when absent
#' (see `.lnk_observation_species_map()`).
#' @noRd
.lnk_observation_record_date <- function(cfg) {
  v <- cfg$pipeline[["observation_record_date"]] %||% "any"
  .lnk_record_date_check(v, paste0("cfg '", cfg$name %||% "", "'"))
}

#' Validate an observation_record_date value
#' @noRd
.lnk_record_date_check <- function(v, what = "observation_record_date") {
  ok <- c("any", "lift_floor")
  if (!is.character(v) || length(v) != 1L || is.na(v) || !v %in% ok) {
    stop(what, ": observation_record_date must be one of ",
         paste(ok, collapse = ", "), call. = FALSE)
  }
  v
}


#' The alias codes a bundle's tracker counts as a species, per group
#'
#' The rows of the record rule whose recorded code is no species column of
#' the presence table (`SST` as ST, `CCT` as CT, `BT/DV` as BT where DV pools
#' into BT), resolved as if every species were present, so a check of an
#' absent cell reads aliases as a present one would. Empty without a tracker.
#' One alias code counts as at most one species in a group.
#' @return Data frame `watershed_group_code`, `species_obs`, `species_code`,
#'   `obs_year_max`.
#' @noRd
.lnk_record_aliases <- function(loaded, wsgs, regions = NULL) {
  empty <- data.frame(watershed_group_code = character(0),
                      species_obs = character(0), species_code = character(0),
                      obs_year_max = integer(0), stringsAsFactors = FALSE)
  pres <- loaded$wsg_species_presence
  if (is.null(loaded$species_pooling) || is.null(pres)) return(empty)
  cols <- .lnk_presence_species_cols(pres)
  sp_all <- toupper(cols)
  all_present <- pres
  for (cc in cols) all_present[[cc]] <- "t"
  loaded$wsg_species_presence <- all_present
  p <- lnk_species_pooling(loaded, aoi = wsgs, species = sp_all,
                           regions = regions)
  p <- p[!p$obs_species %in% sp_all, , drop = FALSE]
  if (nrow(p) == 0L) return(empty)
  dup <- duplicated(p[, c("watershed_group_code", "obs_species")])
  if (any(dup)) {
    stop("species_pooling counts alias code ", p$obs_species[dup][1],
         " as more than one species in ", p$watershed_group_code[dup][1],
         call. = FALSE)
  }
  data.frame(watershed_group_code = p$watershed_group_code,
             species_obs = p$obs_species, species_code = p$species_code,
             obs_year_max = as.integer(p$obs_year_max),
             stringsAsFactors = FALSE)
}


#' The alias codes that count as one species in every group listing them
#'
#' For data with no group (the historical distribution zones): an alias is
#' folded there only where it means one species everywhere it is listed (the
#' tracker's province rows), never a regional one such as `BT/DV`.
#' @param aliases Data frame from `.lnk_record_aliases()`.
#' @return Data frame `species_obs`, `species_code`.
#' @noRd
.lnk_record_aliases_everywhere <- function(aliases) {
  pairs <- unique(aliases[, c("species_obs", "species_code")])
  one <- pairs[!pairs$species_obs %in%
                 pairs$species_obs[duplicated(pairs$species_obs)], ,
               drop = FALSE]
  n_all <- length(unique(aliases$watershed_group_code))
  keep <- vapply(one$species_obs, function(a) {
    length(unique(aliases$watershed_group_code[aliases$species_obs == a])) ==
      n_all
  }, logical(1))
  out <- one[keep, , drop = FALSE]
  rownames(out) <- NULL
  out
}


#' The record rule alone, as a digest for the cut spec
#'
#' Which codes count as which species, with their date floors and year
#' limits, resolved as if every species were present in every group, so the
#' digest moves with the tracker, its species groups, the region lookup,
#' `pipeline: observation_record_date` and the lift floors, and not with the
#' presence table (which the acc spec carries). It decides which records cut
#' streams where observations are a break source (link#470).
#' @noRd
.lnk_record_rule_digest <- function(cfg, loaded) {
  pres <- loaded$wsg_species_presence
  if (is.null(pres)) {
    stop("the record rule needs wsg_species_presence", call. = FALSE)
  }
  for (cc in .lnk_presence_species_cols(pres)) pres[[cc]] <- "t"
  loaded$wsg_species_presence <- pres
  m <- .lnk_observation_species_map(cfg, loaded, pres$watershed_group_code)
  paste0("sha256:", digest::digest(.lnk_vocabulary_canonical(m),
                                   algo = "sha256", serialize = FALSE))
}
