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
