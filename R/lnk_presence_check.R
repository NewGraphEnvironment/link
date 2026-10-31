#' Judge a presence table against the fish records, cell by cell
#'
#' For every group and species column of `loaded$wsg_species_presence`, counts
#' the records that support the species there and flags the two
#' disagreements: a cell marked present with fewer than `n_min` supporting
#' records (`present_unsupported`), and a cell not marked present with at
#' least `n_min` (`absent_recorded`). The cell is judged as written, the
#' reading the pipeline's observation filter takes; `present_promoted` and
#' `promoted_by` say what [lnk_presence()]'s groups make of it.
#'
#' A supporting record is one that:
#' - is of the species, with cutthroat aliases (`CCT`, `ACT`, `CT/RB`) read as
#'   `CT`, as the pipeline reads them;
#' - is not excluded by `observation_exclusions` (`data_error`,
#'   `release_exclude`; `.lnk_observation_exclusion_keys()`);
#' - is not a release, tagged as bcfishpass tags one
#'   (`smnorris/bcfishpass@620dbe4` `load_observations.sql`): `source` up to
#'   its first colon is `Releases Database:`, `source_ref` contains
#'   `BC RELEASE RECORDS DATABASE` or `STOCKING` (any case), or the record's
#'   `observation_exclusions` row sets `release_include`;
#' - is dated in or after `year_min`. A year before 1850 or after `year_now`
#'   is treated as undated, and an undated record does not count.
#'
#' Records of another species count where the bundle's pooling tracker pools
#' them ([lnk_species_pooling()]), with the row's year limit. The resolver
#' answers only for species a group marks present, so it is asked of a copy
#' of the table with every species present: pooling then reaches an absent
#' cell as it would a present one.
#'
#' @param records Data frame of fish records with `observation_key`,
#'   `watershed_group_code`, `species_code`, `observation_date` (Date),
#'   `source` and `source_ref`.
#' @param loaded Named list from [lnk_load_overrides()]: uses
#'   `wsg_species_presence`, `observation_exclusions`, `species_pooling` and
#'   `species_groups`.
#' @param n_min Records needed to support a cell.
#' @param year_min First year a record counts from.
#' @param year_recent Year from which `n_since_recent` counts.
#' @param year_now Latest valid year.
#' @param regions Passed to [lnk_species_pooling()].
#' @return A data frame, one row per group and species column.
#' @noRd
.lnk_presence_check <- function(records, loaded, n_min = 1L, year_min = 1950L,
                                year_recent = 1990L,
                                year_now = as.integer(format(Sys.Date(), "%Y")),
                                regions = NULL) {
  need <- c("observation_key", "watershed_group_code", "species_code",
            "observation_date", "source", "source_ref")
  miss <- setdiff(need, names(records))
  if (length(miss) > 0L) {
    stop("records lacks columns: ", paste(miss, collapse = ", "), call. = FALSE)
  }
  if (!inherits(records$observation_date, "Date")) {
    stop("records$observation_date must be a Date", call. = FALSE)
  }
  stopifnot(length(n_min) == 1L, !is.na(n_min), n_min >= 1,
            length(year_min) == 1L, !is.na(year_min))
  pres <- loaded$wsg_species_presence
  if (!is.data.frame(pres) || !"watershed_group_code" %in% names(pres)) {
    stop("loaded$wsg_species_presence is required", call. = FALSE)
  }
  if (anyDuplicated(pres$watershed_group_code)) {
    stop("wsg_species_presence has duplicate watershed_group_code rows",
         call. = FALSE)
  }
  cols <- .lnk_presence_species_cols(pres)
  sp_all <- toupper(cols)
  wsgs <- pres$watershed_group_code

  # -- each record's species, status and year -------------------------------
  r <- records[records$watershed_group_code %in% wsgs, need, drop = FALSE]
  r$species_code <- ifelse(r$species_code %in% c("CCT", "ACT", "CT/RB"),
                           "CT", r$species_code)
  other_cols <- c("watershed_group_code", "species_code")
  other <- r[!r$species_code %in% sp_all, other_cols, drop = FALSE]
  other <- if (nrow(other) == 0L) {
    data.frame(watershed_group_code = character(0),
               species_code = character(0), n = integer(0))
  } else {
    stats::aggregate(list(n = rep(1L, nrow(other))), other, length)
  }
  r <- r[r$species_code %in% sp_all, , drop = FALSE]
  excl <- loaded$observation_exclusions
  keys_incl <- character(0)
  if (!is.null(excl) && nrow(excl) > 0L) {
    keys_incl <- excl$observation_key[excl$release_include %in% c(TRUE, "t")]
  }
  r$excluded <- r$observation_key %in% .lnk_observation_exclusion_keys(loaded)
  src_head <- ifelse(is.na(r$source), NA_character_,
                     sub(":.*$", ":", r$source))
  ref_release <- grepl("BC RELEASE RECORDS DATABASE", r$source_ref,
                       ignore.case = TRUE) |
    grepl("STOCKING", r$source_ref, ignore.case = TRUE)
  r$release <- !r$excluded & (src_head %in% "Releases Database:" |
                                ref_release |
                                r$observation_key %in% keys_incl)
  yr <- as.integer(format(r$observation_date, "%Y"))
  yr[!is.na(yr) & (yr < 1850L | yr > year_now)] <- NA_integer_
  r$year <- yr
  r$wild <- !r$excluded & !r$release
  r$kept <- r$wild & !is.na(r$year) & r$year >= year_min
  r$source_name <- ifelse(is.na(r$source), "(no source)",
                          trimws(sub(":.*$", "", r$source)))

  # -- pooling, resolved as if every species were present -------------------
  all_present <- pres
  for (cc in cols) all_present[[cc]] <- "t"
  loaded_all <- loaded
  loaded_all$wsg_species_presence <- all_present
  pool <- lnk_species_pooling(loaded_all, aoi = wsgs, species = sp_all,
                              regions = regions)
  pool <- pool[pool$scope_level != "self", , drop = FALSE]

  # -- evidence: each record against each cell it supports ------------------
  own <- r
  own$target <- own$species_code
  own$pooled <- rep(FALSE, nrow(own))
  pooled <- own[0, , drop = FALSE]
  if (nrow(pool) > 0L) {
    p <- data.frame(watershed_group_code = pool$watershed_group_code,
                    species_code = pool$obs_species,
                    target = pool$species_code,
                    obs_year_max = pool$obs_year_max,
                    stringsAsFactors = FALSE)
    m <- merge(r[r$kept, , drop = FALSE], p,
               by = c("watershed_group_code", "species_code"))
    m <- m[is.na(m$obs_year_max) | m$year <= m$obs_year_max, , drop = FALSE]
    m$pooled <- rep(TRUE, nrow(m))
    pooled <- m[, names(own), drop = FALSE]
  }
  ev <- rbind(own, pooled)
  key <- paste(ev$watershed_group_code, ev$target, sep = "|")

  cells <- expand.grid(species_code = sp_all, watershed_group_code = wsgs,
                       stringsAsFactors = FALSE)[, 2:1]
  ck <- paste(cells$watershed_group_code, cells$species_code, sep = "|")
  tally <- function(keep) {
    as.integer(table(factor(key[keep], levels = ck)))
  }
  is_own <- !ev$pooled
  cells$n_records <- tally(is_own)
  cells$n_excluded <- tally(is_own & ev$excluded)
  cells$n_releases <- tally(is_own & ev$release)
  cells$n_undated <- tally(is_own & ev$wild & is.na(ev$year))
  cells$n_before_floor <- tally(is_own & ev$wild & !is.na(ev$year) &
                                  ev$year < year_min)
  cells$n_kept_own <- tally(is_own & ev$kept)
  cells$n_kept_pooled <- tally(ev$pooled)
  cells$n_kept <- cells$n_kept_own + cells$n_kept_pooled
  cells$n_since_recent <- tally(ev$kept & ev$year >= year_recent)

  yr_by <- function(keep, f) {
    v <- tapply(ev$year[keep], factor(key[keep], levels = ck), f)
    as.integer(unname(v))
  }
  kept <- ev$kept
  cells$year_oldest <- yr_by(kept, min)
  cells$year_newest <- yr_by(kept, max)
  wild_dated <- is_own & ev$wild & !is.na(ev$year)
  cells$year_newest_any <- yr_by(wild_dated, max)
  per_cell <- function(v, keep, f) {
    unname(vapply(split(v[keep], factor(key[keep], levels = ck)), f,
                  character(1)))
  }
  codes <- function(s) {
    if (length(s) == 0L) return(NA_character_)
    paste(sort(unique(s), method = "radix"), collapse = ", ")
  }
  tabled <- function(s) {
    if (length(s) == 0L) return(NA_character_)
    t <- sort(table(s), decreasing = TRUE)
    paste0(names(t), " (", as.integer(t), ")", collapse = "; ")
  }
  cells$pooled_from <- per_cell(ev$species_code, ev$pooled, codes)
  cells$sources <- per_cell(ev$source_name, kept, tabled)

  # -- presence as written and as promoted ----------------------------------
  grp_default <- eval(formals(lnk_presence)$groups)
  raw <- lapply(seq_len(nrow(pres)), function(i) {
    .lnk_wsg_species_present(pres[i, , drop = FALSE])
  })
  names(raw) <- wsgs
  cells$present_raw <- mapply(function(w, s) s %in% raw[[w]],
                              cells$watershed_group_code, cells$species_code,
                              USE.NAMES = FALSE)
  prom <- lapply(wsgs, function(w) toupper(lnk_presence(pres, w)$present))
  names(prom) <- wsgs
  cells$present_promoted <- mapply(function(w, s) s %in% prom[[w]],
                                   cells$watershed_group_code,
                                   cells$species_code, USE.NAMES = FALSE)
  promoter <- function(w, s, rp, pp) {
    if (rp || !pp) return(NA_character_)
    for (g in names(grp_default)) {
      mem <- toupper(grp_default[[g]])
      by <- intersect(mem, raw[[w]])
      if (s %in% mem && length(by) > 0L) {
        return(sprintf("%s (%s)", g, paste(by, collapse = ", ")))
      }
    }
    NA_character_
  }
  cells$promoted_by <- mapply(promoter, cells$watershed_group_code,
                              cells$species_code, cells$present_raw,
                              cells$present_promoted, USE.NAMES = FALSE)

  notes <- pres[["notes"]] %||% rep(NA_character_, length(wsgs))
  notes <- trimws(as.character(notes))
  notes[!is.na(notes) & !nzchar(notes)] <- NA_character_
  cells$group_notes <- notes[match(cells$watershed_group_code, wsgs)]

  pf <- loaded$parameters_fresh
  cells$lift_readers <- NA_character_
  pf_cols <- c("species_code", "observation_species")
  if (is.data.frame(pf) && all(pf_cols %in% names(pf))) {
    obs_sp <- pf$observation_species
    reads <- strsplit(ifelse(is.na(obs_sp), "", obs_sp), ";", fixed = TRUE)
    readers <- vapply(sp_all, function(s) {
      hit <- vapply(reads, function(x) s %in% trimws(x), logical(1))
      codes(pf$species_code[hit])
    }, character(1))
    cells$lift_readers <- unname(readers[cells$species_code])
  }

  cells$flag <- ifelse(cells$present_raw & cells$n_kept < n_min,
                       "present_unsupported",
                       ifelse(!cells$present_raw & cells$n_kept >= n_min,
                              "absent_recorded", NA_character_))
  # The rule rides on every row, so a story or a subset never restates it.
  cells$n_min <- as.integer(n_min)
  cells$year_min <- as.integer(year_min)
  cells$year_recent <- as.integer(year_recent)
  rownames(cells) <- NULL
  attr(cells, "other_codes") <- other
  cells
}


#' The rule `.lnk_presence_check()` judged by, as a sentence for the tracker
#' @noRd
.lnk_presence_rule <- function(n_min = 1L, year_min = 1950L) {
  fmt <- paste0("at least %d record%s dated %d or later; releases and ",
                "excluded records out; pooled per species_pooling.csv")
  sprintf(fmt, as.integer(n_min), if (n_min == 1) "" else "s",
          as.integer(year_min))
}


#' Draft a story for each flagged cell from its evidence
#'
#' One plain sentence group per row of `.lnk_presence_check()` output, for
#' the operator to read and correct in the tracker.
#' @noRd
.lnk_presence_story <- function(x) {
  miss <- setdiff(c("n_min", "year_min", "year_recent"), names(x))
  if (length(miss) > 0L) {
    stop("x lacks the rule columns .lnk_presence_check() writes: ",
         paste(miss, collapse = ", "), call. = FALSE)
  }
  rec <- function(n) sprintf("%d record%s", n, ifelse(n == 1L, "", "s"))
  rel <- function(n) sprintf("%d release%s", n, ifelse(n == 1L, "", "s"))
  vapply(seq_len(nrow(x)), function(i) {
    r <- x[i, , drop = FALSE]
    n_min <- r$n_min
    year_min <- r$year_min
    year_recent <- r$year_recent
    out <- character(0)
    if (identical(r$flag, "present_unsupported")) {
      if (r$n_records == 0L && r$n_kept_pooled == 0L) {
        out <- c(out, sprintf("Marked present with no record of %s in the group.",
                              r$species_code))
      } else {
        before <- sprintf("%d before %d (newest %d)", r$n_before_floor,
                          year_min, r$year_newest_any)
        why <- c(
          if (r$n_releases > 0L) rel(r$n_releases),
          if (r$n_excluded > 0L) sprintf("%d excluded", r$n_excluded),
          if (r$n_undated > 0L) sprintf("%d undated", r$n_undated),
          if (r$n_before_floor > 0L) before
        )
        why <- paste(why, collapse = ", ")
        if (r$n_kept == 0L) {
          out <- c(out, sprintf("Marked present; %s of %s, none counting: %s.",
                                rec(r$n_records), r$species_code, why))
        } else {
          # only when n_min > 1: some records count, too few to support it
          lead <- sprintf("Marked present; %d counting %s, fewer than the %d %s",
                          r$n_kept, if (r$n_kept == 1L) "record" else "records",
                          as.integer(n_min), "the rule asks for")
          if (nzchar(why)) lead <- sprintf("%s (also %s, not counted)", lead, why)
          out <- c(out, paste0(lead, "."))
        }
      }
    } else if (identical(r$flag, "absent_recorded")) {
      if (r$n_kept == 1L) {
        lead <- sprintf("Not marked present; a single record (%d; %s)",
                        r$year_newest, sub(" \\(1\\)$", "", r$sources))
      } else {
        fmt <- "Not marked present; %s since %d, %d to %d, %d since %d (%s)"
        lead <- sprintf(fmt, rec(r$n_kept), year_min, r$year_oldest,
                        r$year_newest, r$n_since_recent,
                        as.integer(year_recent), r$sources)
      }
      if (r$n_kept == 1L && r$n_kept_pooled == 1L) {
        lead <- sprintf("%s, a %s record pooled into %s", lead,
                        r$pooled_from, r$species_code)
      } else if (r$n_kept_pooled > 0L && r$n_kept_own == 0L) {
        lead <- sprintf("%s, all of them %s records pooled into %s", lead,
                        r$pooled_from, r$species_code)
      } else if (r$n_kept_pooled > 0L) {
        lead <- sprintf("%s, %d of them %s records pooled into %s", lead,
                        r$n_kept_pooled, r$pooled_from, r$species_code)
      }
      out <- c(out, paste0(lead, "."))
      # Only the cell's own records are dropped while it reads absent;
      # pooled records belong to a species whose own cell keeps them.
      if (r$n_kept_own > 0L && !is.na(r$lift_readers)) {
        fmt <- paste0("While it reads absent, its own %s records are dropped ",
                      "before the observation breaks and from the barrier ",
                      "lifts of %s.")
        out <- c(out, sprintf(fmt, r$species_code, r$lift_readers))
      }
      if (!is.na(r$promoted_by)) {
        fmt <- paste0("The %s group makes it present, so its barriers and ",
                      "mapping code are built.")
        out <- c(out, sprintf(fmt, r$promoted_by))
      }
      extra <- c(
        if (r$n_releases > 0L) rel(r$n_releases),
        if (r$n_excluded > 0L) sprintf("%d excluded", r$n_excluded)
      )
      if (length(extra) > 0L) {
        out <- c(out, sprintf("Also %s, not counted.",
                              paste(extra, collapse = ", ")))
      }
    }
    if (!is.na(r$group_notes)) {
      out <- c(out, sprintf("Group note: \"%s\".", r$group_notes))
    }
    paste(out, collapse = " ")
  }, character(1))
}


#' Merge the check's flags into the review tracker
#'
#' A flagged cell not in the tracker is added as `pending`. A `pending` row
#' still flagged takes the new flag, rule and story, since its evidence may
#' have moved. A row carrying any other decision is never changed. Rows the
#' check no longer flags are returned in `stale` and left in place.
#'
#' @param tracker Data frame with the tracker's columns (may have no rows).
#' @param flagged `.lnk_presence_check()` rows with a flag, plus `story`.
#' @param rule `.lnk_presence_rule()`.
#' @param issue Issue the check was built under.
#' @return `list(tracker, added, refreshed, stale)`.
#' @noRd
.lnk_presence_review_merge <- function(tracker, flagged, rule, issue = "#402") {
  cols <- c("watershed_group_code", "species_code", "flag", "rule", "story",
            "decision", "reviewer", "review_date", "issue")
  miss <- setdiff(cols, names(tracker))
  if (length(miss) > 0L) {
    stop("tracker lacks columns: ", paste(miss, collapse = ", "), call. = FALSE)
  }
  tracker <- tracker[, cols, drop = FALSE]
  tracker[] <- lapply(tracker, function(v) {
    v <- as.character(v)
    v[is.na(v)] <- ""
    v
  })
  bad <- setdiff(unique(tracker$decision),
                 c("pending", "keep", "add", "remove"))
  if (length(bad) > 0L) {
    stop("tracker decisions must be pending, keep, add or remove; found: ",
         paste(bad, collapse = ", "), call. = FALSE)
  }
  tk <- paste(tracker$watershed_group_code, tracker$species_code, sep = "|")
  if (anyDuplicated(tk)) {
    stop("tracker has duplicate group and species rows: ",
         paste(unique(tk[duplicated(tk)]), collapse = ", "), call. = FALSE)
  }
  fk <- paste(flagged$watershed_group_code, flagged$species_code, sep = "|")

  hit <- match(fk, tk)
  pend <- !is.na(hit) & tracker$decision[hit] == "pending"
  ri <- hit[pend]
  tracker$flag[ri] <- flagged$flag[pend]
  tracker$rule[ri] <- rule
  tracker$story[ri] <- flagged$story[pend]

  new <- is.na(hit)
  add <- data.frame(
    watershed_group_code = flagged$watershed_group_code[new],
    species_code = flagged$species_code[new],
    flag = flagged$flag[new],
    rule = rep(rule, sum(new)),
    story = flagged$story[new],
    decision = rep("pending", sum(new)),
    reviewer = rep("", sum(new)),
    review_date = rep("", sum(new)),
    issue = rep(issue, sum(new)),
    stringsAsFactors = FALSE)
  out <- rbind(tracker, add)
  out <- out[order(out$watershed_group_code, out$species_code,
                   method = "radix"), , drop = FALSE]
  rownames(out) <- NULL
  list(tracker = out,
       added = add,
       refreshed = tracker[ri, , drop = FALSE],
       stale = tracker[!tk %in% fk, , drop = FALSE])
}
