# data-raw/study_area_packing.R — how groups are packed onto hosts, and how
# host speeds are learned from a run (link#259, folding in #163). Sourced by
# study_area_buckets.R, host_speeds_calibrate.R and
# tests/testthat/test-study_area_packing.R. Sourcing defines functions only.
#
# A host's predicted model leg is the sum of its groups' weights over its
# speed. Weights are dispatcher-equivalent minutes (a group's measured minutes
# times the speed of the host that measured them) or FWA segments; speeds are
# relative throughput, larger is faster.
#
# Speeds are keyed by host NAME, the operator's alias for a machine (`m1`,
# `m4`), never by the driver's role key (`dispatcher`, `job1`, `worker1`): the
# dispatcher moved from m1 to m4, and a factor learned on one is wrong on the
# other. Every cloud host is one class, `cloud`: they are one droplet size, so
# a run gives that class three legs of evidence (operator, 2026-10-27).
#
# Why the calibration reads whole legs and takes out the run's drift
# (research/study_area_run.md, "How hosts are packed"):
#   - #163: a per-group mean speed is bucket mix times slowness, and feeds
#     back into the packing that chose the mix. A leg's summed time against
#     its summed prediction does not.
#   - A host packed on minutes it measured itself predicts itself, whatever
#     its speed; only groups that moved host carry evidence. Weights are
#     normalized by the current estimate, so a mover is predicted with the
#     estimated ratio and the estimate's error drives a damped correction.
#   - The same groups on the same class took 13 to 16 % longer, summed per
#     class, on 2026-10-23 than on 2026-10-17. That drift is common to every
#     leg, so each correction is divided by the run's pooled one, and the
#     run-wide ratio is reported beside it rather than booked as any host's
#     speed.

PACK_STATE_COLS <- c("name", "factor", "last_updated", "n_runs", "source_run_uid")
PACK_HISTORY_COLS <- c("run_uid", "date_utc", "name", "packed", "old", "correction", "observed",
                       "damped", "clamped", "new", "run_ratio", "action")
# The driver's role keys. A speed learned under one would follow the role onto
# whichever machine holds it next (the dispatcher moved from m1 to m4), so the
# calibrator never learns one: a worker is learned only under an alias.
PACK_ROLE_KEY <- "^(dispatcher|worker[0-9]+|job[0-9]+)$"
PACK_DAMPING <- 0.3     # weight of the new observation (#163: 0.7 old + 0.3 observed)
# A run moves a factor at most this far, as a multiple of old; at 0.3 damping
# only the upper bound can bind (#163's bounds).
PACK_CLAMP <- c(0.5, 2)

# Greedy LPT for unequal machines: each atom, largest first, goes to the host
# that would finish it earliest. `load` is in weight units at speed 1 divided
# by speed (dispatcher-equivalent minutes under minute weights); `seg` is the
# raw weight each host holds.
pack <- function(weights, host_speeds) {
  n_hosts <- length(host_speeds)
  load_h <- rep(0, n_hosts)
  seg_h <- rep(0, n_hosts)
  assign_h <- integer(length(weights))
  for (i in order(-weights)) {
    finish <- load_h + weights[i] / host_speeds
    pick <- which.min(finish)
    assign_h[i] <- pick
    load_h[pick] <- finish[pick]
    seg_h[pick] <- seg_h[pick] + weights[i]
  }
  list(assign = assign_h, load = load_h, seg = seg_h)
}

# The speed class a logged host name belongs to: every cloud host is `cloud`,
# and a name loses any domain (`x.local` logs as itself where LNK_HOST_ALIAS is
# unset, and the packer's default name for it is `x`).
host_class <- function(host) {
  host <- sub("\\..*$", "", host)
  ifelse(grepl("^cypher-", host) | grepl("^job[0-9]+$", host), "cloud", host)
}

# A name goes into a committed file, so it must be an alias, never an ssh
# target or an address (RUNBOOK section 8d keeps those out of the repo).
host_names_check <- function(names) {
  bad <- names[is.na(names) | !nzchar(names) | grepl("[@:/\\s]", names, perl = TRUE) |
               grepl("^[0-9]+(\\.[0-9]+){3}$", names) | grepl("\\.", names)]
  if (length(bad)) {
    stop("host names are aliases written to a committed file: no ssh target, address, ",
         "domain or blank (got: ", paste(sQuote(bad, FALSE), collapse = ", "), ")",
         call. = FALSE)
  }
  invisible(names)
}

# The learned-speed state, or NULL when there is none yet.
speeds_state_read <- function(path) {
  if (!nzchar(path) || !file.exists(path)) return(NULL)
  s <- utils::read.delim(path, colClasses = "character", na.strings = character(),
                         quote = "", comment.char = "")
  if (!identical(names(s), PACK_STATE_COLS)) {
    stop(path, ": expected columns ", paste(PACK_STATE_COLS, collapse = ", "),
         call. = FALSE)
  }
  s$factor <- suppressWarnings(as.numeric(s$factor))
  s$n_runs <- suppressWarnings(as.integer(s$n_runs))
  if (anyNA(s$factor) || any(s$factor <= 0) || anyDuplicated(s$name)) {
    stop(path, ": every factor must be a positive number, one row per name", call. = FALSE)
  }
  s
}

# Each host's speed and where it came from. --host-speeds wins; then the
# learned state, where a name the state does not hold takes the median of the
# names it does (the rule a group with no weight follows) and says so; then
# equal.
speeds_resolve <- function(names, cli = NULL, state = NULL) {
  if (length(cli)) {
    if (length(cli) != length(names) || anyNA(cli) || any(cli <= 0)) {
      stop("--host-speeds needs ", length(names), " positive numbers (dispatcher first), got: ",
           paste(cli, collapse = ", "), call. = FALSE)
    }
    return(data.frame(name = names, speed = cli, source = "--host-speeds"))
  }
  if (is.null(state) || !nrow(state)) {
    return(data.frame(name = names, speed = 1, source = "equal (no learned state)"))
  }
  known <- stats::setNames(state$factor, state$name)
  hit <- names %in% names(known)
  data.frame(name = names,
             speed = ifelse(hit, known[names], stats::median(known)),
             source = ifelse(hit, "learned", "median (no learned speed)"))
}

# Measured minutes in dispatcher-equivalent units: each times the speed of the
# class that measured it, at the current state (see the header).
weights_normalize <- function(minutes, host, state = NULL) {
  if (is.null(state) || !nrow(state)) return(minutes)
  cls <- host_class(host)
  minutes * speeds_resolve(cls, state = state)$speed
}

# One calibration step from a run's legs.
#
#   legs: one row per leg, columns name, speed (the speed the packing used),
#         projected (sum of the leg's group weights over that speed, minutes),
#         actual (the leg's model minutes), skip (NA, or the reason it is left
#         out)
#
# Each leg is first re-projected at the STORED factor (old: the state's, its
# median for a name it lacks, 1 with no state): projected_old = projected x
# packed / old. Per name: correction = (sum actual / sum projected_old) /
# run_ratio, where run_ratio is the same over every leg not skipped, and
# observed = old / correction, new = 0.7 old + 0.3 observed, clamped to
# [0.5, 2] x old. So the speed a run was packed at (--host-speeds, an older
# state) decides only which groups a host got, never what is learned. A role key is never learned. Returns the
# new state and the history rows.
speeds_calibrate <- function(legs, state = NULL, run_uid, date_utc) {
  need <- c("name", "speed", "projected", "actual", "skip")
  if (!all(need %in% names(legs))) {
    stop("legs need columns ", paste(need, collapse = ", "), call. = FALSE)
  }
  if (!nrow(legs)) stop("no legs to calibrate", call. = FALSE)
  spd <- tapply(legs$speed, legs$name, function(x) length(unique(x)))
  if (any(spd > 1)) {
    stop("one name packed at two speeds (", paste(names(spd)[spd > 1], collapse = ", "),
         "): a class shares one speed", call. = FALSE)
  }
  times <- c(legs$projected, legs$actual)
  if (anyNA(times) || any(times <= 0)) {
    stop("every leg needs a positive projected and actual time", call. = FALSE)
  }
  # Re-project every leg at the stored speed (old), not the speed it was packed
  # at: then the observation measures the host against the state, and a run
  # packed with --host-speeds or from an older state moves nothing the truth
  # does not (code-check round 2, link#259).
  legs$old <- speeds_resolve(legs$name, state = state)$speed
  legs$projected_old <- legs$projected * legs$speed / legs$old
  use <- legs[is.na(legs$skip), ]
  if (!nrow(use)) stop("every leg is skipped: nothing to calibrate", call. = FALSE)
  run_ratio <- sum(use$actual) / sum(use$projected_old)

  hist <- list()
  state_new <- if (is.null(state)) {
    data.frame(name = character(), factor = numeric(), last_updated = character(),
               n_runs = integer(), source_run_uid = character())
  } else {
    state
  }
  hist_row <- function(nm, packed, old, correction = NA, observed = NA, damped = NA,
                       clamped = NA, new = NA, action) {
    data.frame(run_uid = run_uid, date_utc = date_utc, name = nm, packed = packed, old = old,
               correction = correction, observed = observed, damped = damped,
               clamped = clamped, new = new, run_ratio = run_ratio, action = action)
  }
  for (nm in unique(legs$name)) {
    l <- legs[legs$name == nm, ]
    packed <- l$speed[1]
    old <- l$old[1]
    u <- l[is.na(l$skip), ]
    if (!nrow(u)) {
      why <- paste0("skipped: ", paste(unique(l$skip), collapse = "; "))
      hist[[length(hist) + 1]] <- hist_row(nm, packed, old, action = why)
      next
    }
    correction <- (sum(u$actual) / sum(u$projected_old)) / run_ratio
    observed <- old / correction
    if (grepl(PACK_ROLE_KEY, nm)) {
      why <- paste0("not learned: ", nm, " is a driver role key; name the host in --host-names")
      hist[[length(hist) + 1]] <- hist_row(nm, packed, old, correction, observed, action = why)
      next
    }
    damped <- (1 - PACK_DAMPING) * old + PACK_DAMPING * observed
    new <- min(max(damped, PACK_CLAMP[1] * old), PACK_CLAMP[2] * old)
    hist[[length(hist) + 1]] <- hist_row(nm, packed, old, correction, observed, damped,
                                         clamped = new != damped, new = new, action = "updated")
    i <- match(nm, state_new$name)
    if (is.na(i)) {
      state_new[nrow(state_new) + 1, ] <- list(nm, new, date_utc, 1L, run_uid)
    } else {
      state_new$factor[i] <- new
      state_new$last_updated[i] <- date_utc
      state_new$n_runs[i] <- state_new$n_runs[i] + 1L
      state_new$source_run_uid[i] <- run_uid
    }
  }
  state_new <- state_new[order(state_new$name), PACK_STATE_COLS]
  rownames(state_new) <- NULL
  list(state = state_new, history = do.call(rbind, hist)[, PACK_HISTORY_COLS],
       run_ratio = run_ratio)
}

# A plan's weights at a given state: each measured group's raw minutes times
# the speed `state` gives the class that measured them; a group with no
# measurement (it took the median) keeps its packed weight. The calibrator
# calls this at the state it reads, so a plan packed on an older state, or with
# another --speeds-state, is projected as if packed on this one (code-check
# round 3, link#259).
plan_weights_at <- function(weight, minutes, measured_by, state = NULL) {
  hit <- !is.na(minutes)
  out <- weight
  if (any(hit)) out[hit] <- weights_normalize(minutes[hit], measured_by[hit], state)
  out
}
