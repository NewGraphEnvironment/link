#!/usr/bin/env Rscript
# wsg_species_presence_check.R — judge default's wsg_species_presence.csv
# against the fish records, cell by cell, and list every disagreement for
# review (link#402).
#
# Read-only against docker fwapg (:5432): session temp tables only. Never
# writes wsg_species_presence.csv; with --seed-tracker it merges the flags
# into configs/default/wsg_species_presence_review.csv (new flags pending,
# pending rows refreshed, decided rows untouched).
#
#   Rscript data-raw/wsg_species_presence_check.R [--n-min=1] [--year-min=1950]
#     [--seed-tracker] [--out=data-raw/logs/presence_check_402]
#
# The rule and its counting are .lnk_presence_check() (R/lnk_presence_check.R).
# Three groups (PARS, ADMS, ALBN: Mackenzie, Fraser, west Vancouver Island)
# are counted again in SQL, independently of R, and the script stops unless
# every cell agrees.
#
# Writes to --out:
#   disagreements.csv  every flagged cell: counts, years, sources, presence as
#                      written and promoted, the drafted story
#   cells.csv          every group x species cell, flagged or not
#   groups.csv         per group: region, note, flags, records under codes
#                      the table has no column for
#   summary.csv        flags by species
#   alias_sensitivity.csv  cells whose flag would differ if the records under
#                      codes naming a table species (summer and winter
#                      steelhead, anadromous char, uncertain BT/DV and RB/CT
#                      calls) counted toward it. Not used for any flag: the
#                      pipeline drops those codes, and the check judges what
#                      the model reads.
#   stamp.txt

pkgload::load_all(quiet = TRUE)
suppressPackageStartupMessages(library(DBI))

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit) == 0L) default else sub(paste0("^--", name, "="), "", hit[1])
}
known <- c("--n-min", "--year-min", "--seed-tracker", "--out", "--config")
bad <- args[!sub("=.*$", "", args) %in% known]
if (length(bad) > 0L) stop("unknown arguments: ", paste(bad, collapse = " "))
config <- arg("config", "default")
# Only default carries a tracker; the other bundles' presence tables differ.
if (!identical(config, "default")) stop("--config must be default (#402)")
n_min <- as.integer(arg("n-min", "1"))
year_min <- as.integer(arg("year-min", "1950"))
if (is.na(n_min) || n_min < 1L) stop("--n-min must be a whole number >= 1")
if (is.na(year_min)) stop("--year-min must be a year")
seed <- "--seed-tracker" %in% args
dir_out <- arg("out", file.path("data-raw", "logs", "presence_check_402"))
fs::dir_create(dir_out)
year_now <- as.integer(format(Sys.Date(), "%Y"))

cfg <- lnk_config(config)
loaded <- lnk_load_overrides(cfg)
regions <- utils::read.csv(.lnk_wsg_regions_path(), stringsAsFactors = FALSE,
                           na.strings = "")
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")

records <- dbGetQuery(conn, "
  SELECT observation_key, watershed_group_code, species_code,
         observation_date, source, source_ref
  FROM bcfishobs.observations")
stopifnot(inherits(records$observation_date, "Date"))

res <- .lnk_presence_check(records, loaded, n_min = n_min, year_min = year_min,
                           year_now = year_now, regions = regions,
                           species_modelled = cfg$species)
other <- attr(res, "other_codes")
fl <- res[!is.na(res$flag), , drop = FALSE]
fl$story <- .lnk_presence_story(fl)
rule <- .lnk_presence_rule(res$n_min[1], res$year_min[1])

# -- independent count in SQL for three groups -------------------------------
check_wsgs <- c("PARS", "ADMS", "ALBN")
excl <- loaded$observation_exclusions
dbWriteTable(conn, "pc_excl",
             data.frame(observation_key = .lnk_observation_exclusion_keys(loaded)),
             temporary = TRUE, overwrite = TRUE)
dbWriteTable(conn, "pc_incl",
             data.frame(observation_key = excl$observation_key[
               excl$release_include %in% c(TRUE, "t")]),
             temporary = TRUE, overwrite = TRUE)
sql <- dbGetQuery(conn, sprintf("
  WITH o AS (
    SELECT o.watershed_group_code,
           CASE WHEN o.species_code IN ('CCT', 'ACT', 'CT/RB') THEN 'CT'
                ELSE o.species_code END AS species_code,
           (x.observation_key IS NOT NULL) AS excluded,
           (x.observation_key IS NULL AND (
              coalesce(substring(o.source FROM 1 FOR position(':' IN o.source)), '')
                = 'Releases Database:'
              OR coalesce(o.source_ref ILIKE '%%BC RELEASE RECORDS DATABASE%%', false)
              OR coalesce(o.source_ref ILIKE '%%STOCKING%%', false)
              OR i.observation_key IS NOT NULL)) AS release,
           extract(year FROM o.observation_date)::int AS yr
    FROM bcfishobs.observations o
    LEFT JOIN pg_temp.pc_excl x ON x.observation_key = o.observation_key
    LEFT JOIN (SELECT DISTINCT observation_key FROM pg_temp.pc_incl) i
      ON i.observation_key = o.observation_key
    WHERE o.watershed_group_code IN (%s))
  SELECT watershed_group_code, species_code,
         count(*)::int AS n_records,
         count(*) FILTER (WHERE excluded)::int AS n_excluded,
         count(*) FILTER (WHERE release)::int AS n_releases,
         count(*) FILTER (WHERE NOT excluded AND NOT release
                            AND yr BETWEEN %d AND %d)::int AS n_kept_own
  FROM o GROUP BY 1, 2",
  paste(sprintf("'%s'", check_wsgs), collapse = ", "), year_min, year_now))
mine <- res[res$watershed_group_code %in% check_wsgs,
            c("watershed_group_code", "species_code", "n_records",
              "n_excluded", "n_releases", "n_kept_own")]
cmp <- merge(mine, sql, by = c("watershed_group_code", "species_code"),
             all.x = TRUE, suffixes = c("", "_sql"))
for (v in c("n_records", "n_excluded", "n_releases", "n_kept_own")) {
  s <- cmp[[paste0(v, "_sql")]]
  s[is.na(s)] <- 0L
  if (!identical(as.integer(cmp[[v]]), as.integer(s))) {
    print(cmp[cmp[[v]] != s, ])
    stop("SQL cross-check disagrees on ", v)
  }
}
n_cmp_cells <- nrow(cmp)
n_cmp_records <- sum(cmp$n_records)

# -- sensitivity: codes that name a table species -----------------------------
# Diagnostic only, never a flag: the pipeline's observation filter matches
# codes exactly, so these records reach no break, lift or code 2 today.
alias <- c(SST = "ST", WST = "ST", ADV = "DV", "DV/BT" = "DV", ABT = "BT",
           "BT/DV" = "BT", "RB/CT" = "RB", " RB" = "RB")
rec_alias <- records
hit_alias <- rec_alias$species_code %in% names(alias)
rec_alias$species_code[hit_alias] <- unname(alias[rec_alias$species_code[hit_alias]])
res_alias <- .lnk_presence_check(rec_alias, loaded, n_min = n_min,
                                 year_min = year_min, year_now = year_now,
                                 regions = regions,
                                 species_modelled = cfg$species)
sens <- merge(res[, c("watershed_group_code", "species_code", "flag", "n_kept")],
              res_alias[, c("watershed_group_code", "species_code", "flag", "n_kept")],
              by = c("watershed_group_code", "species_code"),
              suffixes = c("", "_with_aliases"))
same_flag <- (is.na(sens$flag) & is.na(sens$flag_with_aliases)) |
  (!is.na(sens$flag) & !is.na(sens$flag_with_aliases) &
     sens$flag == sens$flag_with_aliases)
sens <- sens[!same_flag, , drop = FALSE]
sens <- sens[order(sens$watershed_group_code, sens$species_code,
                   method = "radix"), , drop = FALSE]
utils::write.csv(sens, file.path(dir_out, "alias_sensitivity.csv"),
                 row.names = FALSE, na = "")

# -- outputs ------------------------------------------------------------------
ord <- function(d) {
  d[order(d$watershed_group_code, d$species_code, method = "radix"), ,
    drop = FALSE]
}
reg <- regions[, c("watershed_group_code", "region", "subregion")]
cols_out <- c("watershed_group_code", "species_code", "flag", "region",
              "subregion", "present_raw", "present_promoted", "promoted_by",
              "n_kept", "n_kept_own", "n_kept_pooled", "pooled_from",
              "n_since_recent", "year_oldest", "year_newest", "sources",
              "n_records", "n_releases", "n_excluded", "n_undated",
              "n_before_floor", "year_newest_any", "year_newest_before",
              "modelled", "lift_readers",
              "group_notes", "story")
fl <- merge(fl, reg, by = "watershed_group_code", all.x = TRUE)
utils::write.csv(ord(fl)[, cols_out], file.path(dir_out, "disagreements.csv"),
                 row.names = FALSE, na = "")
cells <- merge(res, reg, by = "watershed_group_code", all.x = TRUE)
utils::write.csv(ord(cells)[, setdiff(cols_out, "story")],
                 file.path(dir_out, "cells.csv"), row.names = FALSE, na = "")

pres <- loaded$wsg_species_presence
grp <- data.frame(watershed_group_code = pres$watershed_group_code,
                  stringsAsFactors = FALSE)
grp <- merge(grp, reg, by = "watershed_group_code", all.x = TRUE)
per <- function(f) {
  vapply(grp$watershed_group_code, function(w) {
    s <- fl$species_code[fl$watershed_group_code == w & fl$flag == f]
    paste(sort(s, method = "radix"), collapse = " ")
  }, character(1))
}
grp$present_unsupported <- unname(per("present_unsupported"))
grp$absent_recorded <- unname(per("absent_recorded"))
grp$n_flags <- vapply(grp$watershed_group_code,
                      function(w) sum(fl$watershed_group_code == w), integer(1))
grp$n_other_codes <- vapply(grp$watershed_group_code, function(w) {
  as.integer(sum(other$n[other$watershed_group_code == w]))
}, integer(1))
grp$other_codes <- vapply(grp$watershed_group_code, function(w) {
  o <- other[other$watershed_group_code == w, , drop = FALSE]
  o <- o[order(-o$n, o$species_code, method = "radix"), , drop = FALSE]
  paste0(o$species_code, " (", o$n, ")", collapse = "; ")
}, character(1))
grp$other_codes[grp$n_other_codes == 0L] <- ""
notes <- trimws(as.character(pres$notes))
grp$notes <- notes[match(grp$watershed_group_code, pres$watershed_group_code)]
utils::write.csv(grp[order(grp$watershed_group_code, method = "radix"), ],
                 file.path(dir_out, "groups.csv"), row.names = FALSE, na = "")

sp_all <- sort(unique(res$species_code), method = "radix")
n_by_species <- function(keep) {
  vapply(sp_all, function(s) sum(fl$species_code == s & keep), integer(1))
}
ar <- fl$flag == "absent_recorded"
summ <- data.frame(
  species_code = sp_all,
  cells_present = vapply(sp_all, function(s) {
    sum(res$present_raw[res$species_code == s])
  }, integer(1)),
  present_unsupported = n_by_species(fl$flag == "present_unsupported"),
  absent_recorded = n_by_species(ar),
  absent_recorded_single = n_by_species(ar & fl$n_kept == 1L),
  absent_recorded_promoted = n_by_species(ar & fl$present_promoted),
  absent_recorded_pooled_only = n_by_species(ar & fl$n_kept_own == 0L),
  stringsAsFactors = FALSE)
stopifnot(sum(summ$present_unsupported) + sum(summ$absent_recorded) == nrow(fl))
utils::write.csv(summ, file.path(dir_out, "summary.csv"), row.names = FALSE)

# -- tracker -----------------------------------------------------------------
tracker_path <- file.path("inst", "extdata", "configs", "default",
                          "wsg_species_presence_review.csv")
merged <- NULL
if (seed) {
  tracker <- utils::read.csv(tracker_path, colClasses = "character",
                             na.strings = character(0))
  merged <- .lnk_presence_review_merge(tracker, ord(fl), rule = rule)
  utils::write.csv(merged$tracker, tracker_path, row.names = FALSE)
  if (nrow(merged$stale) > 0L) {
    message("tracker rows the check no longer flags: ",
            paste(merged$stale$watershed_group_code, merged$stale$species_code,
                  collapse = ", "))
  }
}

all_other <- stats::aggregate(list(n = other$n), other["species_code"], sum)
named <- all_other[all_other$species_code %in% names(alias), , drop = FALSE]
named <- named[order(-named$n, method = "radix"), , drop = FALSE]
valid_dates <- records$observation_date[!is.na(records$observation_date) &
                                          records$observation_date <= Sys.Date()]
writeLines(c(
  sprintf("date: %s", format(Sys.time(), "%Y-%m-%d %H:%M %Z", tz = "UTC")),
  sprintf("link: %s @ %s", utils::packageVersion("link"),
          system("git rev-parse --short HEAD", intern = TRUE)),
  sprintf("config: %s; presence table %s", config,
          cfg$files$wsg_species_presence$path),
  "db: docker fwapg localhost:5432",
  sprintf("bcfishobs.observations rows: %d; newest observation_date not after today %s",
          nrow(records), format(max(valid_dates))),
  sprintf("rule: %s", rule),
  sprintf("groups: %d; cells: %d; flagged: %d (present_unsupported %d, absent_recorded %d)",
          nrow(pres), nrow(res), nrow(fl), sum(fl$flag == "present_unsupported"),
          sum(fl$flag == "absent_recorded")),
  sprintf(paste0("records under codes the table has no column for (not counted, ",
                 "as in the pipeline): %d records, %d codes (per group in groups.csv); ",
                 "of them, codes naming a table species: %s"),
          sum(all_other$n), nrow(all_other),
          paste0(trimws(named$species_code), " ", named$n, " -> ",
                 alias[named$species_code], collapse = "; ")),
  sprintf("alias sensitivity: %d cells would change flag if those codes counted (alias_sensitivity.csv)",
          nrow(sens)),
  sprintf("SQL cross-check: %s, %d cells, %d records, all counts agree",
          paste(check_wsgs, collapse = ", "), n_cmp_cells, n_cmp_records),
  sprintf("tracker: %s", if (is.null(merged)) "not seeded" else sprintf(
    "%d added, %d pending refreshed, %d no longer flagged",
    nrow(merged$added), nrow(merged$refreshed), nrow(merged$stale)))),
  file.path(dir_out, "stamp.txt"))
DBI::dbDisconnect(conn)
message("wrote ", dir_out, ": ", nrow(fl), " flagged cells")
