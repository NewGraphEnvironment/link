#!/usr/bin/env Rscript
# recompute_schedule_sim.R — would an early recompute shorten a provincial
# run? (link#374). Replays one run's recorded times through two schedules:
#
#   end    #369's driver: each cloud host consolidated as its leg ends, then
#          ONE pool over every group after the dispatcher leg and the last
#          consolidate (plus the run's own gap to the first job).
#   early  #374: a group's job may start once the group and every group it
#          reads (recompute_deps.R, one rule per pass) have landed: a
#          dispatcher group when its model row closes, a cloud group when its
#          host's consolidate ends. Groups still not ready when the end
#          schedule would have started its pool start then, as the final set.
#
# Both pools are -j<width> list schedules, longest job first among the jobs
# ready at each free slot (recompute_order's rule, with the run's own times as
# the oracle). A job costs its log_recompute minutes plus the median gap
# between jobs on a slot (#260: 9.7 s), which the log leaves out.
#
# Two scenarios:
#   recorded   the dispatcher leg as it ran (KTSU's 65 min stall included).
#              OKAN's first attempt was cancelled and it was re-modelled and
#              recomputed after the run (#348), so it is not in the pool and
#              never lands; a group reading it waits for the final set.
#   no_stalls  the dispatcher leg replayed in its recorded order with KTSU at
#              1.3 min and OKAN at 7.6 min (their re-run times; CLAUDE.md
#              2026-10-23), so OKAN lands and is recomputed.
#
# Not modelled: contention. A copy slowing the dispatcher leg (#369 measured
# 1.11x against 1.19x, i.e. none) or concurrent recompute jobs slowing it,
# which is what the headroom measurement is for. The report gives the
# recompute job-minutes run before the dispatcher leg ends, so a slowdown can
# be weighed against the saving.
#
# Usage: Rscript data-raw/recompute_schedule_sim.R <deps.tsv> <run_wsgs.tsv>
#          <consolidate.log> <out_dir> [run_uid] [schema] [width]

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 4L) {
  stop("usage: recompute_schedule_sim.R <deps.tsv> <run_wsgs.tsv> <consolidate.log> <out_dir> [run_uid] [schema] [width]",
       call. = FALSE)
}
deps_path <- args[1]; wsgs_path <- args[2]; cons_path <- args[3]; out_dir <- args[4]
run_uid <- if (length(args) >= 5L) args[5] else "20261023_074321-24d85e8c"
schema  <- if (length(args) >= 6L) args[6] else "fresh_default"
width   <- if (length(args) >= 7L) as.integer(args[7]) else 8L
gap_min <- 9.7 / 60
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

suppressPackageStartupMessages({
  library(DBI); library(RPostgres)
})
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")
q <- function(sql) DBI::dbGetQuery(conn, sql)
uid <- DBI::dbQuoteLiteral(conn, run_uid)

mlog <- q(sprintf(
  "SELECT watershed_group_code AS wsg, host, date_start, date_end
   FROM %s.log WHERE run_uid = %s ORDER BY date_start", schema, uid))
rlog <- q(sprintf(
  "SELECT watershed_group_code AS wsg, date_start, date_end
   FROM %s.log_recompute WHERE run_uid = %s AND date_end IS NOT NULL
   ORDER BY date_start", schema, uid))
DBI::dbDisconnect(conn)

hosts <- utils::read.delim(wsgs_path, stringsAsFactors = FALSE)
hosts <- hosts[hosts$host != "host", c("wsg", "host")]
deps  <- utils::read.delim(deps_path, stringsAsFactors = FALSE)

t_origin <- min(mlog$date_start)
mins <- function(t) as.numeric(difftime(t, t_origin, units = "mins"))

# The pool's own jobs: the first recompute of each group in the run's pool
# (OKAN's came hours later, by --recompute-only).
pool_start_rec <- min(rlog$date_start)
pool <- rlog[!duplicated(rlog$wsg), ]
pool <- pool[mins(pool$date_start) < mins(pool_start_rec) + 240, ]
job_min <- stats::setNames(
  as.numeric(difftime(pool$date_end, pool$date_start, units = "mins")) + gap_min,
  pool$wsg)

# Cloud: each host's leg ends with its last group; its consolidate runs as it
# ends, one at a time, for the minutes the run's consolidate log measured.
cons <- readLines(cons_path)
stamp <- function(pat) {
  x <- regmatches(cons, regexpr("^\\[[0-9]{2}:[0-9]{2}:[0-9]{2}\\]", cons))[grepl(pat, cons)]
  as.POSIXct(paste("2000-01-01", gsub("[][]", "", x)), tz = "UTC")
}
copy_min <- as.numeric(difftime(stamp("DELETE bucket from source"),
                                stamp("DELETE bucket \\("), units = "mins"))
bucket_n <- as.integer(sub(".*DELETE bucket \\(([0-9]+) WSGs.*", "\\1",
                           cons[grepl("DELETE bucket \\(", cons)]))
cloud_hosts <- sort(unique(hosts$host[hosts$host != "dispatcher"]))
size <- table(hosts$host)[cloud_hosts]
if (!setequal(as.integer(size), bucket_n)) {
  stop("consolidate log bucket sizes (", paste(bucket_n, collapse = ","),
       ") do not match run_wsgs.tsv (", paste(size, collapse = ","), ")", call. = FALSE)
}
copy_by_host <- stats::setNames(copy_min[match(as.integer(size), bucket_n)], cloud_hosts)

land_cloud <- function() {
  leg_end <- vapply(cloud_hosts, function(h) {
    w <- hosts$wsg[hosts$host == h]
    max(mins(mlog$date_end[mlog$wsg %in% w & grepl("cypher", mlog$host)]), na.rm = TRUE)
  }, numeric(1))
  t <- -Inf; done <- numeric()
  for (h in names(sort(leg_end))) {
    t <- max(t, leg_end[[h]]) + copy_by_host[[h]]
    done[h] <- t
  }
  w <- hosts$wsg[hosts$host != "dispatcher"]
  list(land = stats::setNames(done[hosts$host[hosts$host != "dispatcher"]], w),
       leg_end = leg_end, cons_end = done)
}

land_dispatcher <- function(scenario) {
  d <- mlog[!grepl("cypher", mlog$host), ]
  if (scenario == "recorded") {
    d <- d[!is.na(d$date_end) & mins(d$date_start) < mins(pool_start_rec), ]
    return(stats::setNames(mins(d$date_end), d$wsg))
  }
  # no_stalls: the first attempt of each group, replayed in order with the
  # recorded gaps, KTSU and OKAN at their re-run times.
  d <- d[!duplicated(d$wsg), ]
  dur <- as.numeric(difftime(d$date_end, d$date_start, units = "mins"))
  dur[d$wsg == "KTSU"] <- 1.3
  dur[d$wsg == "OKAN"] <- 7.6
  st <- mins(d$date_start); en <- mins(d$date_end)
  t <- st[1]; out <- numeric(nrow(d))
  for (i in seq_len(nrow(d))) {
    # The recorded idle time between groups; none after OKAN's open row,
    # whose cancel time the log does not hold.
    gap <- if (i == 1L || is.na(en[i - 1])) 0 else max(0, st[i] - en[i - 1])
    t <- t + gap
    out[i] <- t + dur[i]
    t <- out[i]
  }
  stats::setNames(out, d$wsg)
}

schedule <- function(ready_at, dur, width) {
  # ready_at: named minutes each job may start; list schedule, longest first.
  free <- rep(-Inf, width)
  left <- names(ready_at)
  start <- end <- stats::setNames(numeric(length(left)), left)
  while (length(left)) {
    s <- which.min(free)
    now <- max(free[s], min(ready_at[left]))
    cand <- left[ready_at[left] <= now]
    pick <- cand[order(-dur[cand], cand)][1]
    start[pick] <- now; end[pick] <- now + dur[pick]
    free[s] <- end[pick]
    left <- setdiff(left, pick)
  }
  data.frame(wsg = names(start), start = start, end = end, row.names = NULL)
}

rows <- list(); jobs_out <- list()
for (scenario in c("recorded", "no_stalls")) {
  cl <- land_cloud()
  ld <- land_dispatcher(scenario)
  land <- c(ld, cl$land)
  groups <- intersect(names(job_min), names(land))
  if (scenario == "no_stalls" && "OKAN" %in% names(ld) && !"OKAN" %in% names(job_min)) {
    # OKAN's recompute came later, by hand; give it the median job.
    job_min["OKAN"] <- stats::median(job_min)
    groups <- union(groups, "OKAN")
  }
  dur <- job_min[groups]
  disp_end <- max(ld)
  last_cons <- max(cl$cons_end)
  # The run's own gap from its consolidate's end to its first recompute job
  # (account, burn, coverage, views). That run consolidated after the
  # dispatcher leg, all hosts in one go, so its consolidate ended at the
  # recorded leg end plus the log's first-to-last stamp span.
  rec_disp_end <- max(mins(mlog$date_end[!grepl("cypher", mlog$host) &
    mins(mlog$date_start) < mins(pool_start_rec)]), na.rm = TRUE)
  st_all <- regmatches(cons, regexpr("^\\[[0-9]{2}:[0-9]{2}:[0-9]{2}\\]", cons))
  st_all <- as.POSIXct(paste("2000-01-01", gsub("[][]", "", st_all)), tz = "UTC")
  cons_span <- as.numeric(difftime(max(st_all), min(st_all), units = "mins"))
  overhead <- max(0, mins(pool_start_rec) - (rec_disp_end + cons_span))
  t_end_pool <- max(disp_end, last_cons) + overhead
  base <- schedule(stats::setNames(rep(t_end_pool, length(groups)), groups), dur, width)
  last_land <- max(land[groups])
  rows[[length(rows) + 1L]] <- data.frame(
    scenario = scenario, rule = "end", groups = length(groups),
    dispatcher_leg_end = disp_end, last_consolidate = last_cons,
    pool_first_start = min(base$start), recompute_end = max(base$end),
    tail_after_last_landing = max(base$end) - max(disp_end, last_cons),
    job_min_before_dispatcher_end = 0, saving = 0)
  jobs_out[[paste(scenario, "end")]] <- cbind(scenario = scenario, rule = "end", base)
  for (r in unique(deps$rule)) {
    dr <- deps[deps$rule == r, ]
    ready <- vapply(groups, function(g) {
      need <- c(g, dr$dep[dr$wsg == g])
      need <- need[need %in% c(names(land), hosts$wsg, "OKAN")]
      t <- land[need]
      # A dependency in the run that never lands (OKAN, recorded) holds the
      # group to the final set; one outside the run has landed already.
      if (anyNA(t)) t_end_pool else max(c(t, -Inf))
    }, numeric(1))
    ready <- pmin(ready, t_end_pool)
    sch <- schedule(ready, dur, width)
    before <- sum(pmax(0, pmin(sch$end, disp_end) - sch$start))
    rows[[length(rows) + 1L]] <- data.frame(
      scenario = scenario, rule = r, groups = length(groups),
      dispatcher_leg_end = disp_end, last_consolidate = last_cons,
      pool_first_start = min(sch$start), recompute_end = max(sch$end),
      tail_after_last_landing = max(sch$end) - max(disp_end, last_cons),
      job_min_before_dispatcher_end = before,
      saving = max(base$end) - max(sch$end))
    jobs_out[[paste(scenario, r)]] <- cbind(scenario = scenario, rule = r, sch)
  }
}
res <- do.call(rbind, rows)
num <- vapply(res, is.numeric, logical(1))
res[num] <- lapply(res[num], round, 1)
utils::write.table(res, file.path(out_dir, "sim_summary.tsv"), sep = "\t",
                   quote = FALSE, row.names = FALSE)
jobs <- do.call(rbind, jobs_out)
jobs$start <- round(jobs$start, 2); jobs$end <- round(jobs$end, 2)
utils::write.table(jobs, file.path(out_dir, "sim_jobs.tsv"), sep = "\t",
                   quote = FALSE, row.names = FALSE)
cat(sprintf("minutes from the run's first model start (%s UTC); -j%d; job = log minutes + %.2f min gap\n",
            format(t_origin, tz = "UTC"), width, gap_min))
print(res, row.names = FALSE)

# --- coupled: the early pool slows the dispatcher leg (headroom.sh) ---------
# headroom.sh measured the dispatcher's modelling about 2x slower beside a -j8
# recompute, and the recompute jobs not slower. So in the no-stalls scenario,
# replay the dispatcher leg in steps of dt minutes, advancing each group's
# remaining minutes at 1 / (1 + alpha * k), k the recompute jobs running then
# (alpha = 0.125 makes -j8 a 2x slowdown), or, with alpha = NA, by the
# measured curve: extra time f(k) interpolated through (0, 0), (4, 0.20),
# (8, 0.99) (headroom.sh at -j4 and -j8; the database saturates past about
# four jobs, so a linear alpha overstates the cost of a narrow pool). The
# scheduler runs at most
# `w_legs` jobs while the dispatcher leg is modelling, `width` after it.
# Cloud consolidates are not slowed (they were not measured); a dispatcher
# group lands when its slowed model ends.
coupled <- function(rule, w_legs, alpha, dt = 0.05) {
  cl <- land_cloud()
  d <- mlog[!grepl("cypher", mlog$host), ]
  d <- d[!duplicated(d$wsg), ]
  dur <- as.numeric(difftime(d$date_end, d$date_start, units = "mins"))
  dur[d$wsg == "KTSU"] <- 1.3
  dur[d$wsg == "OKAN"] <- 7.6
  st <- mins(d$date_start); en <- mins(d$date_end)
  gap <- c(0, ifelse(is.na(en[-nrow(d)]), 0, pmax(0, st[-1] - en[-nrow(d)])))
  groups <- union(intersect(names(job_min), c(d$wsg, names(cl$land))), "OKAN")
  jm <- job_min; if (!"OKAN" %in% names(jm)) jm["OKAN"] <- stats::median(job_min)
  dr <- deps[deps$rule == rule, ]
  need <- lapply(stats::setNames(groups, groups), function(g) {
    x <- c(g, dr$dep[dr$wsg == g]); x[x %in% c(d$wsg, names(cl$land))]
  })
  land <- c(stats::setNames(rep(NA_real_, nrow(d)), d$wsg), cl$land)
  t <- st[1]; i <- 1L; left <- dur[1] ; idle <- 0
  run_end <- numeric(); started <- character(); ends <- numeric()
  disp_done <- FALSE; t_end_pool <- Inf; overlap <- 0
  repeat {
    k <- sum(run_end > t)
    if (!disp_done) {
      # A step's leftover time carries into the next group (or gap), so 74
      # boundaries do not each lose part of a step.
      step <- dt
      while (!disp_done && step > 0) {
        if (idle > 0) {
          used <- min(idle, step); idle <- idle - used; step <- step - used
          next
        }
        f <- if (is.na(alpha)) stats::approx(c(0, 4, 8, 16), c(0, 0.20, 0.99, 2.97), k)$y else alpha * k
        cost <- left * (1 + f)
        if (cost > step) {
          left <- left - step / (1 + f); overlap <- overlap + k * step; step <- 0
        } else {
          overlap <- overlap + k * cost; step <- step - cost
          land[d$wsg[i]] <- t + dt - step
          i <- i + 1L
          if (i > nrow(d)) { disp_done <- TRUE; disp_end <- t + dt - step } else { left <- dur[i]; idle <- gap[i] }
        }
      }
    }
    if (disp_done && is.infinite(t_end_pool)) {
      t_end_pool <- max(disp_end, max(cl$cons_end)) + 0.8
    }
    w <- if (disp_done) width else w_legs
    free <- w - sum(run_end > t)
    if (free > 0) {
      cand <- setdiff(groups, started)
      ok <- vapply(cand, function(g) {
        if (t >= t_end_pool) return(TRUE)
        x <- land[need[[g]]]; !anyNA(x) && all(x <= t)
      }, logical(1))
      cand <- cand[ok]
      if (length(cand)) {
        cand <- cand[order(-jm[cand], cand)][seq_len(min(free, length(cand)))]
        started <- c(started, cand); run_end <- c(run_end, t + jm[cand])
      }
    }
    if (length(started) == length(groups) && disp_done) break
    t <- t + dt
  }
  data.frame(scenario = "no_stalls_coupled", rule = rule, w_legs = w_legs, alpha = alpha,
             dispatcher_leg_end = round(disp_end, 1), last_consolidate = round(max(cl$cons_end), 1),
             recompute_end = round(max(run_end), 1),
             tail_after_last_landing = round(max(run_end) - max(disp_end, max(cl$cons_end)), 1),
             job_min_before_dispatcher_end = round(overlap, 1))
}
alphas <- suppressWarnings(as.numeric(strsplit(Sys.getenv("LNK_SIM_ALPHA", "0.125,NA"), ",")[[1]]))
cp <- do.call(rbind, lapply(alphas, function(a) do.call(rbind, lapply(c(0L, 1L, 2L, 4L, 8L),
  function(wl) coupled("line", wl, a)))))
base_end <- res$recompute_end[res$scenario == "no_stalls" & res$rule == "end"]
cp$saving <- round(base_end - cp$recompute_end, 1)
utils::write.table(cp, file.path(out_dir, "sim_coupled.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
cat("\ncoupled (no stalls, line rule; w_legs = jobs while the dispatcher models, then -j", width, "):\n", sep = "")
print(cp, row.names = FALSE)
