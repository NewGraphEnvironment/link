# habitat_validate_inputs.R — inputs shared by the observation-validation
# drivers (data-raw/habitat_validate.R, link#283; data-raw/habitat_variants_score.R,
# link#284 step 5). Sourced, not run: each function takes what it needs, so both
# drivers resolve absences and pooling through one code path.
#
#   hv_fiss_absences()  FISS data-submission sites (private `knowledge` repo,
#                       LNK_KNOWLEDGE_DIR) as absences of each species, by the
#                       taxa rules in data-raw/fiss_absence_taxa.csv
#   hv_pooling()        which observation species count as each model species,
#                       resolved once from one bundle's species_pooling.csv

# -- absences from FISS sites (optional) --------------------------------------
# Returns NULL when LNK_KNOWLEDGE_DIR is unset, or an empty list carrying a
# `reason` attribute when no species in `species` has an absence rule.
hv_fiss_absences <- function(conn, species,
                             taxa_csv = file.path("data-raw", "fiss_absence_taxa.csv")) {
  dir_k <- Sys.getenv("LNK_KNOWLEDGE_DIR", "")
  if (!nzchar(dir_k)) return(NULL)
  files <- Sys.glob(file.path(dir_k, "data", "*", "fiss_sites_*_all.csv"))
  if (length(files) == 0L) {
    stop("LNK_KNOWLEDGE_DIR set but no fiss_sites_*_all.csv under ", dir_k,
         call. = FALSE)
  }
  num <- function(x) suppressWarnings(as.numeric(x))
  sites <- do.call(rbind, lapply(files, function(f) {
    d <- utils::read.csv(f, colClasses = "character", na.strings = c("", "NA"))
    data.frame(site_key = d$site_key,
               utm_zone = num(d$utm_zone), utm_easting = num(d$utm_easting),
               utm_northing = num(d$utm_northing),
               sampled = d$effort_recorded %in% "TRUE" | d$nfc %in% "TRUE",
               nfc = d$nfc %in% "TRUE",
               species_list = ifelse(is.na(d$species_list), "",
                                     d$species_list),
               stringsAsFactors = FALSE)
  }))
  sites <- sites[sites$sampled & !is.na(sites$utm_zone) &
                   !is.na(sites$utm_easting) & !is.na(sites$utm_northing), ]
  # A report spanning two groups appears in both snapshots under one key.
  sites <- sites[!duplicated(sites$site_key), ]
  dbWriteTable(conn, "hv_fiss", sites[, c("site_key", "utm_zone",
                                          "utm_easting", "utm_northing")],
               temporary = TRUE, overwrite = TRUE)
  snap <- dbGetQuery(conn, "
    WITH p AS (
      SELECT site_key,
             st_transform(st_setsrid(st_makepoint(utm_easting, utm_northing),
                                     26900 + utm_zone::int), 3005) AS geom
        FROM pg_temp.hv_fiss)
    SELECT p.site_key, f.watershed_group_code, f.blue_line_key,
           f.downstream_route_measure
             + st_linelocatepoint(st_force2d(f.geom), p.geom) * f.length_metre
             AS downstream_route_measure
      FROM p
      JOIN LATERAL (
        SELECT f.watershed_group_code, f.blue_line_key,
               f.downstream_route_measure, f.length_metre, f.geom
          FROM whse_basemapping.fwa_stream_networks_sp f
         WHERE st_dwithin(f.geom, p.geom, 100)
           AND f.edge_type <> 1425
         ORDER BY f.geom <-> p.geom
         LIMIT 1) f ON true")
  sites <- merge(sites, snap, by = "site_key")
  # Only the snapshot WSGs were surveyed; a site snapping across a boundary
  # would give its neighbour a partial count that reads as coverage.
  covered <- toupper(basename(dirname(files)))
  sites <- sites[sites$watershed_group_code %in% covered, ]
  listed <- nzchar(trimws(sites$species_list))
  no_fish <- sites$nfc & !listed
  # Which listed taxa mean the species was caught, or might have been, is
  # data (fiss_absence_taxa.csv): one regex per row, OR-ed per species x
  # role and matched case-insensitively. A species with no `caught` row has
  # no absence rule.
  taxa <- utils::read.csv(taxa_csv, stringsAsFactors = FALSE,
                          colClasses = "character")
  stopifnot(identical(names(taxa), c("species_code", "role", "pattern")),
            all(taxa$role %in% c("caught", "maybe")),
            all(nzchar(taxa$pattern)))
  rule <- function(sp, role) {
    p <- taxa$pattern[taxa$species_code == sp & taxa$role == role]
    if (length(p) == 0L) return(rep(FALSE, nrow(sites)))
    grepl(paste(p, collapse = "|"), sites$species_list, ignore.case = TRUE)
  }
  sp_rule <- unique(taxa$species_code[taxa$role == "caught"])
  caught <- stats::setNames(lapply(sp_rule, rule, role = "caught"), sp_rule)
  maybe <- stats::setNames(lapply(sp_rule, rule, role = "maybe"), sp_rule)
  sp_abs <- intersect(species, names(caught))
  if (length(setdiff(species, sp_abs)) > 0L) {
    message("no FISS absence rule for: ",
            paste(setdiff(species, sp_abs), collapse = ", "),
            "; not assessed")
  }
  if (length(sp_abs) == 0L) {
    return(structure(list(), reason = "no FISS absence rule for the species"))
  }
  is_abs_of <- function(sp) no_fish | (listed & !caught[[sp]] & !maybe[[sp]])
  n_abs <- vapply(sp_abs, function(sp) sum(is_abs_of(sp)), integer(1))
  out <- do.call(rbind, lapply(sp_abs, function(sp) {
    s <- sites[is_abs_of(sp), ]
    data.frame(watershed_group_code = s$watershed_group_code,
               blue_line_key = s$blue_line_key,
               downstream_route_measure = s$downstream_route_measure,
               species_code = rep(sp, nrow(s)), stringsAsFactors = FALSE)
  }))
  attr(out, "n_sites_sampled") <- nrow(sites)
  attr(out, "n_absence_sites") <- n_abs
  attr(out, "covered") <- sort(unique(covered))
  sha <- suppressWarnings(tryCatch(
    system2("git", c("-C", shQuote(dir_k), "rev-parse", "--short", "HEAD"),
            stdout = TRUE, stderr = FALSE),
    error = function(e) character(0)))
  attr(out, "knowledge_sha") <- if (length(sha) == 1L) sha else "not a git repo"
  out
}

# -- pooling: resolved once, from one bundle -----------------------------------
# `bundles` is a data frame with a `config` column; `bundle_wsgs` the list of
# each bundle's WSGs. Returns list(args = <extra lnk_habitat_validate() args>,
# note = <one stamp line>).
hv_pooling <- function(bundles, bundle_wsgs, species, pooling_cfg = NULL) {
  if (is.null(pooling_cfg)) {
    declares <- vapply(bundles$config, function(b) {
      !is.null(lnk_config(b)$files$species_pooling)
    }, logical(1))
    pooling_cfg <- if (any(declares)) bundles$config[which(declares)[1]] else NULL
  }
  loaded_pool <- if (is.null(pooling_cfg)) list() else
    suppressWarnings(lnk_load_overrides(lnk_config(pooling_cfg)))
  args_pool <- list()
  pooling_note <- "no bundle declares a species_pooling tracker: lnk_habitat_validate() default"
  if (!is.null(pooling_cfg) && is.null(loaded_pool$species_pooling)) {
    stop("--pooling=", pooling_cfg, " declares no species_pooling tracker",
         call. = FALSE)
  }
  if (!is.null(loaded_pool$species_pooling)) {
    # The pooling table is resolved against the pooling bundle's presence, and
    # each bundle is then scored against its own. If they disagree on a species
    # in play, pooled records drop silently in the WSGs where they differ.
    presence_flags <- function(p, w) {
      p <- as.data.frame(p)
      names(p) <- tolower(names(p))
      p <- p[match(w, toupper(p$watershed_group_code)), tolower(species), drop = FALSE]
      vapply(p, function(x) as.character(x) %in% "t", logical(length(w)))
    }
    for (i in seq_len(nrow(bundles))) {
      lp <- suppressWarnings(lnk_load_overrides(lnk_config(bundles$config[i])))
      w <- bundle_wsgs[[i]]
      if (!identical(presence_flags(lp$wsg_species_presence, w),
                     presence_flags(loaded_pool$wsg_species_presence, w))) {
        stop("bundle ", bundles$config[i], "'s wsg_species_presence differs ",
             "from --pooling=", pooling_cfg, "'s for ",
             paste(species, collapse = ", "), " in its WSGs", call. = FALSE)
      }
    }
    args_pool$species_obs <- lnk_species_pooling(
      loaded_pool, aoi = sort(unique(unlist(bundle_wsgs))), species = species)
    pooled <- args_pool$species_obs[args_pool$species_obs$scope_level != "self", ]
    pooling_note <- sprintf("%s species_pooling.csv (sha256 %s): %d WSG x species pairs pooled (%s)",
                            pooling_cfg,
                            substr(digest::digest(
                              file = lnk_config(pooling_cfg)$files$species_pooling$path,
                              algo = "sha256"), 1, 12), nrow(unique(pooled[c("watershed_group_code",
                                                              "species_code")])),
                            if (nrow(pooled) == 0L) "none" else
                              paste(unique(paste0(pooled$species_code, "<-",
                                                  pooled$obs_species)),
                                    collapse = ", "))
  }

  list(args = args_pool, note = pooling_note)
}
