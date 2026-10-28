#!/usr/bin/env Rscript
# study_area_buckets.R — partition the focal watershed groups into
# drainage-INDEPENDENT components, then pack those components onto hosts.
#
# Why components rather than study areas (link#246):
#
#   Cross-WSG `;DAM` requires a host's bucket to be drainage-closed and run
#   downstream-first. If two hosts' closures overlap, the overlapping WSGs
#   are modelled twice and `schema_consolidate` resolves the collision
#   last-writer-wins — so which host finished last silently decides the
#   answer. Partitioning into components whose closures are disjoint makes
#   that impossible by construction.
#
#   Do NOT partition by `wscode_ltree` root. That reproduces the sliver
#   misclassification RUNBOOK section 8b documents: NATR files under Fraser
#   though it drains to the Peace, and SPAT under Skeena though it drains
#   the Stikine. Closure is measure-aware; a wscode root is not.
#
# Method: union-find over per-WSG `fresh::frs_wsg_drainage()` closures. Two
# focal WSGs share a component iff their closures intersect. Each component
# is then resolved through `lnk_wsg_resolve()` for the species filter and
# the downstream-first order, and the components are packed onto hosts by
# greedy LPT (longest processing time first) — the same algorithm
# wsgs_dispatch.sh uses, with a component rather than a single WSG as the
# indivisible atom.
#
# The atom (link#361): a component, or a single group.
#
#   The component rule was written for cross-WSG `;DAM` and access at MODEL
#   time. Since link#175 the post-consolidate recompute settles access, mapping
#   code and (link#349) the gated habitat flags from every group's persisted
#   barriers, and the driver models both legs with LNK_GUARD_DOWNSTREAM=warn
#   and LNK_HABITAT_GATE=0. The split test of 2026-10-23 modelled the Peace's
#   26 groups on two hosts in the worst order and found nothing the order can
#   reach that differs from the one-host build
#   (data-raw/logs/provincial_361/split_verdict.md). So `--atom=group` packs
#   single modelable groups, which lets the modelling finish before the
#   largest component would (the Fraser: 205 of 873 host-minutes on the 2026-10-17
#   minutes, 231 of 1,077 on 2026-10-23's). Each host's
#   list keeps the global downstream-first order, so a group still follows
#   whatever downstream of it the same host holds and the guard warns less;
#   the recompute is the guarantee either way. The drainage-closed assertion
#   is skipped in group mode (a host's list is not a closure by design); the
#   within-host order assertion still runs. The report prints the makespan
#   under both atoms. `--write` refuses `--atom=group`: research/study_areas.md
#   describes the components. A group-atom split needs `study_area_run.sh
#   --buckets-exact`, which resolves each `--focal=` list exactly instead of
#   expanding it to its closure.
#
# Usage:
#   [LNK_LOAD=loadall] Rscript data-raw/study_area_buckets.R \
#     [--hosts=4] [--config=bcfishpass] [--focal=A,B,C] [--atom=component|group] \
#     [--minutes-schema=<persist schema>] [--host-speeds=1,1,1,1] [--workers=0]
#     [--host-names=m4,cloud,cloud,cloud] [--speeds-state=<tsv>] [--plan-out=<tsv>] [--write]
#
#   --hosts=N            number of hosts to pack onto (default 4: dispatcher + 3)
#   --focal=             override the focal set (default: the baked-in 96)
#   --atom=              what is packed whole: `component` (default) or `group`
#   --minutes-schema=S   weight each group by its measured modelling minutes,
#                        from the newest finished row per group in S.log
#                        (link#361). Without it, by stream-segment count.
#   --host-speeds=       relative throughput per host, dispatcher first, then
#                        workers, then cloud hosts. Wins over the learned state
#   --host-names=        each host's name in the same order (default: this
#                        machine's short name, worker1..N, `cloud` for each
#                        cloud host). Aliases only: they key the committed
#                        learned-speed state, so never an ssh target or address
#   --speeds-state=      learned speeds (default data-raw/logs/host_speeds.tsv;
#                        empty for none). A name it does not hold takes the
#                        median of those it does. RUNBOOK section 8d
#   --plan-out=          write one row per group (host, name, speed, weight) for
#                        host_speeds_calibrate.R after the run (link#259)
#   --workers=N          how many of the hosts are persistent workers (link#376;
#                        default 0). They are hosts 2..N+1, labelled worker1..N,
#                        and the printed --focal= lists follow the driver's order:
#                        dispatcher, workers, cloud hosts. A worker's speed is
#                        measured, not assumed: its minutes per group against the
#                        dispatcher's on the same groups (RUNBOOK section 8d).
#   --write              rewrite research/study_areas.md from this run's output
#                        (component atoms only)
#
# Stdout is the report. Nothing is written unless --write or --plan-out is passed.

args <- commandArgs(trailingOnly = TRUE)
arg_val <- function(flag, default) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (!length(hit)) return(default)
  sub(paste0("^", flag, "="), "", hit[1])
}
n_hosts <- as.integer(arg_val("--hosts", "4"))
config  <- arg_val("--config", "bcfishpass")
minutes_schema <- arg_val("--minutes-schema", "")
atom <- arg_val("--atom", "component")
n_workers <- suppressWarnings(as.integer(arg_val("--workers", "0")))
do_write <- "--write" %in% args
# pack(), host speeds and their learned state (link#259), shared with
# host_speeds_calibrate.R and the tests.
script_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_file, mustWork = FALSE))
source(file.path(script_dir, "study_area_packing.R"))
if (!atom %in% c("component", "group")) {
  stop("--atom must be component or group, got '", atom, "'", call. = FALSE)
}
if (do_write && atom == "group") {
  stop("--write describes the drainage-independent components (research/study_areas.md); ",
       "run --atom=group without --write and keep its report with the run's logs",
       call. = FALSE)
}
if (nzchar(minutes_schema) && !grepl("^[A-Za-z_][A-Za-z0-9_]*$", minutes_schema)) {
  stop("--minutes-schema must be a bare schema name, got '", minutes_schema, "'",
       call. = FALSE)
}
if (is.na(n_hosts) || n_hosts < 1L) {
  stop("--hosts must be a positive integer", call. = FALSE)
}
if (is.na(n_workers) || n_workers < 0L || n_workers > n_hosts - 1L) {
  stop("--workers must be a whole number from 0 to --hosts - 1 (the dispatcher ",
       "is host 1)", call. = FALSE)
}

# Relative throughput per host, dispatcher first, and where each came from
# (link#259): --host-speeds wins; else the learned state (--speeds-state,
# default data-raw/logs/host_speeds.tsv, written by host_speeds_calibrate.R),
# where a host the state does not hold takes the median of those it does;
# else equal. Equal was the default from link#361 (the 241-group run of
# 2026-10-17 measured cloud hosts at about the dispatcher's rate over whole
# buckets, `research/study_area_run.md`, "Equal packing was right"), and the
# state is seeded equal: 2026-10-23 could not tell the classes apart ("How
# hosts are packed").
#
# A speed is keyed by host NAME (--host-names, the operator's aliases in the
# driver's order), never by the driver's role key: the dispatcher moved from
# m1 to m4. Every cloud host is the one class `cloud`.
host_key <- function(h) {
  if (h == 1L) return("dispatcher")
  if (h <= n_workers + 1L) return(sprintf("worker%d", h - 1L))
  sprintf("job%d", h - 1L - n_workers)
}
# The name this machine's own log rows carry (LNK_HOST_ALIAS, else its node
# name, as .lnk_host() decides: an empty alias falls back too), so its measured
# minutes and its learned speed meet.
own_host <- Sys.getenv("LNK_HOST_ALIAS")
if (!nzchar(own_host)) own_host <- Sys.info()[["nodename"]]
names_arg <- arg_val("--host-names", "")
host_names <- if (nzchar(names_arg)) {
  trimws(strsplit(names_arg, ",")[[1]])
} else {
  c(host_class(own_host),
    if (n_workers > 0L) sprintf("worker%d", seq_len(n_workers)),
    rep("cloud", n_hosts - 1L - n_workers))
}
if (length(host_names) != n_hosts) {
  stop("--host-names needs ", n_hosts, " names (dispatcher, workers, cloud hosts), got ",
       length(host_names), call. = FALSE)
}
host_names_check(host_names)
# Cloud hosts are the class `cloud` wherever a speed is looked up (host_class()
# maps their log rows there), so a cloud host named anything else would be
# learned under a name nothing normalizes by.
n_cloud <- n_hosts - 1L - n_workers
if (n_cloud > 0L && any(host_names[(n_workers + 2L):n_hosts] != "cloud")) {
  stop("--host-names: every cloud host is named `cloud` (got: ",
       paste(host_names[(n_workers + 2L):n_hosts], collapse = ", "), ")", call. = FALSE)
}
state_path <- arg_val("--speeds-state", file.path(script_dir, "logs", "host_speeds.tsv"))
speed_state <- speeds_state_read(state_path)
speeds_arg <- arg_val("--host-speeds", "")
speeds_cli <- if (nzchar(speeds_arg)) {
  suppressWarnings(as.numeric(trimws(strsplit(speeds_arg, ",")[[1]])))
}
speeds <- speeds_resolve(host_names, cli = speeds_cli, state = speed_state)
host_speeds <- speeds$speed
# One name, one speed: the calibrator learns per name and refuses a plan that
# packed one name at two speeds, so refuse it here, before the run is paid for.
per_name <- tapply(host_speeds, host_names, function(x) length(unique(x)))
if (any(per_name > 1L)) {
  stop("--host-speeds gives ", paste(names(per_name)[per_name > 1L], collapse = ", "),
       " more than one speed; every cloud host is one class at one speed", call. = FALSE)
}
plan_out <- arg_val("--plan-out", "")

if (identical(Sys.getenv("LNK_LOAD"), "loadall")) {
  suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
} else {
  suppressPackageStartupMessages(library(link))
}
suppressPackageStartupMessages({
  library(DBI); library(RPostgres)
})

# The focal set, baked in rather than derived from whatever is currently
# persisted. A default that reads `fresh.streams` would give a different
# answer before and after the Phase 3 wipe, which is the opposite of what a
# reproducible derivation is for. These are the 93 groups persisted as of
# 2026-08-30 plus Columbia's KOTL / LARL / SLOC
# (rtj/scripts/gis/projects/nelson/project.yml).
FOCAL_DEFAULT <- c(
  "ALBN", "BBAR", "BONP", "BRKS", "BULK", "CARP", "CARR", "CHES", "CHIR",
  "CHWK", "CLRH", "COAL", "COTR", "COWN", "CRKD", "DOGC", "DUNC", "ELKR",
  "FINA", "FINL", "FIRE", "FONT", "FOXR", "FRAN", "FRCN", "GATA", "GOLD",
  "HARR", "HOMA", "INGR", "KETL", "KISP", "KITL", "KITR", "KLUM", "KOTR",
  "KTSU", "LBTN", "LCHL", "LCHR", "LDEN", "LFRA", "LILL", "LKEL", "LNTH",
  "LOMI", "LPCE", "LPRO", "LSAL", "LSKE", "LSTR", "MDEA", "MESI", "MFRA",
  "MORK", "MORR", "MSKE", "MSTR", "NARC", "NASR", "NATR", "NECR", "NICL",
  "OSPK", "PARA", "PARS", "PCEA", "QUES", "SAJR", "SALR", "SETN", "SHER",
  "SMAR", "SPAT", "SUST", "TABR", "TAKL", "TATR", "TOOD", "TSIT", "TWAC",
  "UBTN", "UFRA", "UJER", "UKEC", "UNRS", "UNUR", "UOMI", "UPCE", "USKE",
  "UTRE", "WILL", "ZYMO",
  # Columbia
  "KOTL", "LARL", "SLOC")

focal_arg <- arg_val("--focal", "")
focal <- if (nzchar(focal_arg)) {
  toupper(trimws(strsplit(focal_arg, ",")[[1]]))
} else {
  FOCAL_DEFAULT
}
focal <- sort(unique(focal[nzchar(focal)]))

# Explicit local docker fwapg — lnk_db_conn()'s env defaults land on the
# :63333 bcfp tunnel, a different database with a different load state
# (#222). Same reasoning as study_area_wsgs.R.
conn <- DBI::dbConnect(RPostgres::Postgres(), host = "localhost", port = 5432,
                       dbname = "fwapg", user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

cfg    <- lnk_config(config)
loaded <- lnk_load_overrides(cfg)

message(sprintf("focal: %d WSGs | config: %s | hosts: %d",
                length(focal), config, n_hosts))

# --- 1. per-focal drainage closures ---------------------------------------
message("resolving per-WSG drainage closures ...")
closures <- stats::setNames(
  lapply(focal, function(w) fresh::frs_wsg_drainage(conn, w)), focal)

bad <- names(closures)[vapply(closures, length, integer(1)) == 0L]
if (length(bad)) {
  stop("frs_wsg_drainage returned nothing for: ", paste(bad, collapse = ", "),
       " - an empty closure is a failure, not an isolated component",
       call. = FALSE)
}

# --- 2. union-find ---------------------------------------------------------
parent <- stats::setNames(seq_along(focal), focal)
find <- function(i) {
  while (parent[[i]] != i) {
    parent[[i]] <<- parent[[parent[[i]]]]
    i <- parent[[i]]
  }
  i
}
union2 <- function(a, b) {
  ra <- find(a); rb <- find(b)
  if (ra != rb) parent[[ra]] <<- rb
  invisible(NULL)
}

# Index every closure member back to the focal WSGs that reach it; any two
# focal WSGs sharing a member belong to one component.
seen <- new.env(parent = emptyenv())
for (i in seq_along(focal)) {
  for (m in closures[[i]]) {
    prev <- seen[[m]]
    if (is.null(prev)) seen[[m]] <- i else union2(i, prev)
  }
}

comp_id <- vapply(seq_along(focal), find, integer(1))
components <- split(focal, comp_id)
names(components) <- NULL
# Largest first, ties broken alphabetically so the output is deterministic.
components <- components[order(-lengths(components),
                               vapply(components, `[`, character(1), 1))]

message(sprintf("union-find: %d focal WSGs -> %d drainage-independent components",
                length(focal), length(components)))

# --- 3. resolve each component: closure + species filter + DS-first --------
message("resolving modelable DS-first sets per component ...")
resolved <- lapply(components, function(f) {
  suppressMessages(lnk_wsg_resolve(cfg, loaded, wsgs = f, conn = conn))
})

# Disjointness is the whole point of the partition, so assert it rather than
# trusting the algorithm. An overlap means consolidate would be
# last-writer-wins on the shared WSGs.
flat <- unlist(resolved)
dup <- unique(flat[duplicated(flat)])
if (length(dup)) {
  stop("components overlap on: ", paste(dup, collapse = ", "),
       " - the partition is not drainage-independent", call. = FALSE)
}

# --- 4. weights ------------------------------------------------------------
# Two weightings, and the report says which one was used.
#
# Measured minutes (--minutes-schema, link#361): each group's newest finished
# `log` row, `date_end - date_start`. Segment count explains modelling time
# only loosely (R^2 0.64 over 104 WSGs, study_area_run.sh's recompute_order
# note), and it is what packed the 2026-10-17 run at 165 / 205 / 272 / 231
# host-minutes against an even 218.
#
# Measured minutes win out of sample (link#259, data-raw/logs/packing_259/):
# fitted on 2026-10-17 and scored on 2026-10-23's legs with KTSU's and OKAN's
# stalls left out, segments set a leg's share of the mean leg up to 28.9 points
# wrong, minutes 3.6 (28.5 and 16.4 as logged). Every leg ran 12 to 20 % over
# the minutes estimate because the same groups took 13 to 16 % longer on 10-23
# (drift between builds), which costs the estimate, not the balance. Pack a
# provincial run on --minutes-schema; research/study_area_run.md, "How hosts
# are packed", has the table.
#
# Segment count otherwise: one query, no prior run needed. Either way a group
# with no value takes the median rather than zero, so an unknown never packs
# as free, and the count of such groups is printed.
if (nzchar(minutes_schema)) {
  w <- DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT ON (watershed_group_code)
            watershed_group_code AS wsg, host,
            extract(epoch FROM (date_end - date_start)) / 60 AS n
       FROM %s.log
      WHERE date_end IS NOT NULL AND date_start IS NOT NULL
      ORDER BY watershed_group_code, date_start DESC", minutes_schema))
  if (!nrow(w)) {
    stop("--minutes-schema=", minutes_schema, ": no finished log rows",
         call. = FALSE)
  }
  # Raw minutes and who measured them go into the plan, so the calibrator can
  # re-normalize at whatever state it reads (code-check round 3, link#259).
  raw_min <- stats::setNames(as.numeric(w$n), w$wsg)
  raw_cls <- stats::setNames(host_class(w$host), w$wsg)
  # Dispatcher-equivalent: each group's minutes times the learned speed of the
  # class that measured them (link#259; equal state, no change).
  w$n <- weights_normalize(as.numeric(w$n), w$host, speed_state)
  # Which speed normalized whose minutes: a log host the state does not hold
  # takes the median, and that is said here rather than silently.
  if (!is.null(speed_state)) {
    norm_src <- speeds_resolve(host_class(w$host), state = speed_state)
    norm_tab <- table(paste0(host_class(w$host), " (", norm_src$source, ")"))
    message("minutes normalized by: ",
            paste(sprintf("%s %d groups", names(norm_tab), as.integer(norm_tab)), collapse = "; "))
  }
  weight_unit <- "min"
  weight_desc <- sprintf(paste0("measured modelling minutes (newest finished row per group in %s.log, ",
                                "normalized by the learned speed of the host that measured them)"),
                         minutes_schema)
} else {
  w <- DBI::dbGetQuery(conn,
    "SELECT watershed_group_code AS wsg, count(*)::numeric AS n
       FROM whse_basemapping.fwa_stream_networks_sp GROUP BY 1")
  raw_min <- NULL
  raw_cls <- NULL
  weight_unit <- "segments"
  weight_desc <- "stream-segment count (fwa_stream_networks_sp)"
}
wmap <- stats::setNames(as.numeric(w$n), w$wsg)
med <- stats::median(wmap)
weight_of <- function(wsgs) {
  v <- wmap[wsgs]
  v[is.na(v)] <- med
  sum(v)
}
comp_weight <- vapply(resolved, weight_of, numeric(1))
n_unweighted <- sum(!flat %in% names(wmap))
message(sprintf("weights: %s; %d of %d groups have no value and take the median (%.3g %s)",
                weight_desc, n_unweighted, length(flat), med, weight_unit))
# Every group on the median is an unweighted split by another name: the
# failure the median fill exists to prevent (link#259; 2026-05-14's "no timing
# CSVs found; using deterministic split").
if (n_unweighted == length(flat)) {
  stop("none of the ", length(flat), " groups has a weight in ", weight_desc,
       ": packing would be an unweighted split", call. = FALSE)
}

# --- 5. greedy LPT pack, speed-aware ---------------------------------------
# The hosts are NOT interchangeable. Measured 2026-08-31 on identical work,
# per 1000 persisted segments: dispatcher 0.0391 min, cypher 0.0872 min — the
# cyphers are **2.23x slower**. Packing by raw segment count therefore
# balances WORK and unbalances TIME: a cypher handed half the dispatcher's
# segments still finishes later, and the makespan is set by a host that was
# given less to do.
#
# So each component goes to the host that would COMPLETE it earliest, which is
# LPT for heterogeneous machines. Load is accumulated in dispatcher-equivalent
# weight units (minutes under --minutes-schema), not raw segments.
#
# There is deliberately no relabelling step any more. The previous version
# packed into anonymous equal-speed bins and then renamed them by descending
# load so host 1 held the most — which is meaningless once the hosts differ,
# because host 1 IS the dispatcher and cannot be swapped for a cypher. The
# fast host now ends up with more work on its own, because it finishes sooner.
#
# One packer for both atoms (link#361; data-raw/study_area_packing.R since #259):
# `pack()` takes the atoms' weights and the hosts' speeds, and returns each
# atom's host and each host's load. The component packing is
# always computed, so the report can print the makespan under both atoms for
# the same hosts; the group packing only when --atom=group.
comp_pack <- pack(comp_weight, host_speeds)

# The global downstream-first order: each component's resolved list is
# DS-first and the components are drainage-independent, so their
# concatenation is DS-first over the whole run. Group mode filters it per
# host, so a host still models a group after whatever downstream of it the
# same host holds.
global_order <- unlist(resolved, use.names = FALSE)

if (atom == "component") {
  assign_h <- comp_pack$assign; load_h <- comp_pack$load; seg_h <- comp_pack$seg
  host_focal <- lapply(seq_len(n_hosts), function(h) {
    unlist(components[assign_h == h], use.names = FALSE)
  })
  host_wsgs <- lapply(seq_len(n_hosts), function(h) {
    unlist(resolved[assign_h == h], use.names = FALSE)
  })
} else {
  group_weight <- vapply(global_order, weight_of, numeric(1))
  group_pack <- pack(group_weight, host_speeds)
  assign_h <- comp_pack$assign     # the Components table still names each component's host under component atoms
  load_h <- group_pack$load; seg_h <- group_pack$seg
  host_wsgs <- lapply(seq_len(n_hosts), function(h) {
    global_order[group_pack$assign == h]
  })
  # Under group atoms the `--focal=` string IS the host's list: the driver
  # takes it exactly (--buckets-exact), with no closure expansion.
  host_focal <- host_wsgs
}

# --- assert the property the whole partition exists to provide -------------
# Each host's bucket must be drainage-CLOSED: for every WSG it models, every
# modelable WSG downstream of that one must also be on the same host. That is
# what lets accessibility read already-persisted downstream barriers, and it
# is the precondition lnk_wsg_downstream_check() enforces per WSG at run time.
#
# It does follow from packing whole components whose closures are disjoint —
# but "follows by construction" is a claim, and a cheap one to check against
# the closures already in hand. Asserted rather than reasoned about.
#
# Skipped under group atoms: a host's list is not a closure by design, and the
# post-consolidate recompute settles what the closure used to protect
# (data-raw/logs/provincial_361/split_verdict.md).
if (atom == "component") {
  for (h in seq_len(n_hosts)) {
    if (!length(host_focal[[h]])) next
    need <- intersect(unique(unlist(closures[host_focal[[h]]])), flat)
    miss <- setdiff(need, host_wsgs[[h]])
    if (length(miss)) {
      stop(sprintf(
        "host %d bucket is not drainage-closed - missing %s. A WSG would be modelled before its downstream barriers exist.",
        h, paste(sort(miss), collapse = ", ")), call. = FALSE)
    }
  }
} else {
  message("group atoms: the drainage-closed assertion is skipped; the recompute settles access")
}

# And the DS-first order has to hold WITHIN each host: a WSG must appear
# after everything downstream of it that the same host models. Concatenating
# several components is safe precisely because they are drainage-independent,
# so no flow path crosses a component boundary — but that is the claim, so
# check it against real closures rather than restating it.
#
# `closures` is keyed by FOCAL WSG only; a bucket also holds closure members
# that were never focal, so their closures are resolved here.
message("verifying DS-first order within each host ...")
closure_of <- new.env(parent = emptyenv())
for (nm in names(closures)) assign(nm, closures[[nm]], envir = closure_of)
for (x in flat) {
  if (!exists(x, envir = closure_of, inherits = FALSE)) {
    assign(x, fresh::frs_wsg_drainage(conn, x), envir = closure_of)
  }
}
for (h in seq_len(n_hosts)) {
  b <- host_wsgs[[h]]
  if (length(b) < 2L) next
  pos <- stats::setNames(seq_along(b), b)
  for (x in b) {
    ds <- intersect(setdiff(get(x, envir = closure_of), x), b)
    late <- ds[pos[ds] > pos[[x]]]
    if (length(late)) {
      stop(sprintf("host %d: %s is ordered before its downstream %s", h, x,
                   paste(late, collapse = ", ")), call. = FALSE)
    }
  }
}

# --- 6. report -------------------------------------------------------------
# Hosts in the driver's order: the dispatcher, then workers, then cloud hosts.
host_label <- function(h) {
  if (h == 1L) return(sprintf("dispatcher (%s)", host_names[1]))
  if (h <= n_workers + 1L) return(sprintf("worker%d", h - 1L))
  sprintf("job%d", h - 1L - n_workers)
}
n_jobs <- n_hosts - 1L - n_workers
# The driver flags that name the hosts, in its order (a worker's ssh target is
# the operator's to fill in).
host_flags <- c(
  if (n_workers > 0L) sprintf("--workers=%s", paste(sprintf("<worker%d target>", seq_len(n_workers)),
                                                    collapse = ",")),
  if (n_jobs > 0L) sprintf("--cy-workspaces=%s", paste(sprintf("job%d", seq_len(n_jobs)),
                                                       collapse = ","))
)

cat("\n## Components\n\n")
cat(sprintf("%d focal WSGs -> %d drainage-independent components\n\n",
            length(focal), length(components)))
cat("| # | focal | modelable | host | focal WSGs |\n")
cat("|---|---|---|---|---|\n")
for (i in seq_along(components)) {
  cat(sprintf("| %d | %d | %d | %s | %s |\n", i,
              length(components[[i]]), length(resolved[[i]]),
              host_label(assign_h[i]),
              paste(components[[i]], collapse = " ")))
}

cat("\n## Host buckets\n\n")
cat(sprintf("Weights: %s. %d of %d groups took the median.\n\n",
            weight_desc, n_unweighted, length(flat)))
speed_lines <- sprintf("%s %s %.3f (%s)", vapply(seq_len(n_hosts), host_key, ""),
                       host_names, host_speeds, speeds$source)
cat(sprintf("Speeds: %s.\n\n", paste(speed_lines, collapse = "; ")))
cat(sprintf("Atom: %s.%s\n\n", atom,
            if (atom == "group") " Single modelable groups, each host's list in the global downstream-first order; the post-consolidate recompute settles access (data-raw/logs/provincial_361/split_verdict.md)." else ""))
cat(sprintf("| host | speed | atoms | focal | modelable | %s | est. load | est. share |\n",
            weight_unit))
cat("|---|---|---|---|---|---|---|---|\n")
for (h in seq_len(n_hosts)) {
  n_atoms <- if (atom == "component") sum(assign_h == h) else length(host_wsgs[[h]])
  cat(sprintf("| %s | %.2fx | %d | %d | %d | %s | %s | %.2f |\n", host_label(h),
              host_speeds[h], n_atoms, length(host_focal[[h]]),
              length(host_wsgs[[h]]), format(round(seg_h[h]), big.mark = ","),
              format(round(load_h[h]), big.mark = ","),
              load_h[h] / max(load_h)))
}
unit_label <- if (weight_unit == "min") "dispatcher-equivalent min" else "weight units"
cat(sprintf("\nmakespan is set by %s at %s %s of load; balance = %.0f%% (100%% = every host finishes together)\n",
            host_label(which.max(load_h)), format(round(max(load_h)), big.mark = ","),
            unit_label, 100 * mean(load_h) / max(load_h)))
# Both atoms for the same hosts, so the gain from splitting components is a
# number in the report rather than a claim (link#361).
cat(sprintf("makespan under component atoms: %s %s; under group atoms: %s %s\n",
            format(round(max(comp_pack$load)), big.mark = ","), unit_label,
            format(round(max(pack(vapply(global_order, weight_of, numeric(1)), host_speeds)$load)), big.mark = ","),
            unit_label))
if (weight_unit == "min") {
  cat(sprintf("largest component is %s %s; an even split of the %s total over %d hosts would be %s\n",
              format(round(max(comp_weight)), big.mark = ","), weight_unit,
              format(round(sum(comp_weight)), big.mark = ","), n_hosts,
              format(round(sum(comp_weight) / sum(host_speeds)), big.mark = ",")))
}
cat(sprintf("\ntotal modelable: %d | dropped by species presence: %d\n",
            length(flat),
            length(unique(unlist(closures))) - length(flat)))

cat("\n## --focal= strings\n\n")
if (atom == "group") {
  cat("Exact lists (downstream-first), one per host: run with `--buckets-exact`, which resolves\n")
  cat("each list as given instead of expanding it to its drainage closure.\n\n")
}
cat("```\n")
for (f in host_flags) cat(sprintf("  %s \\\n", f))
if (atom == "group") cat("  --buckets-exact \\\n")
for (h in seq_len(n_hosts)) {
  # Component atoms: the focal groups, sorted (the driver expands them).
  # Group atoms: the host's exact list, in its downstream-first order.
  f <- if (atom == "component") sort(host_focal[[h]]) else host_focal[[h]]
  cat(sprintf("  --focal=%s \\\n", paste(f, collapse = ",")))
}
cat("```\n")

cat("\n## DS-first order per host\n\n")
for (h in seq_len(n_hosts)) {
  cat(sprintf("- **%s** (%d): %s\n", host_label(h), length(host_wsgs[[h]]),
              paste(host_wsgs[[h]], collapse = ", ")))
}

# --- the plan: one row per group, for host_speeds_calibrate.R (link#259) -----
# A host's predicted leg is the sum of its rows' weight over its speed. The
# calibrator checks these groups against the run's <TS>_run_wsgs.tsv, so a
# plan edited by hand after it was written is refused, not trusted.
if (nzchar(plan_out)) {
  g_host <- if (atom == "component") {
    rep(assign_h, lengths(resolved))
  } else {
    group_pack$assign
  }
  g_wsg <- if (atom == "component") unlist(resolved, use.names = FALSE) else global_order
  plan <- data.frame(wsg = g_wsg,
                     host_key = vapply(g_host, host_key, character(1)),
                     name = host_names[g_host],
                     speed = host_speeds[g_host],
                     speed_source = speeds$source[g_host],
                     weight_unit = weight_unit,
                     weight = vapply(g_wsg, weight_of, numeric(1)),
                     minutes = if (is.null(raw_min)) NA_real_ else unname(raw_min[g_wsg]),
                     measured_by = if (is.null(raw_cls)) NA_character_ else unname(raw_cls[g_wsg]))
  utils::write.table(plan, plan_out, sep = "\t", quote = FALSE, row.names = FALSE, na = "")
  message(sprintf("wrote the plan (%d groups, %s) to %s", nrow(plan), weight_unit, plan_out))
}

# --- 7. optionally rewrite the research doc --------------------------------
if (do_write) {
  out <- file.path(dirname(dirname(normalizePath(
    sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]),
    mustWork = FALSE))), "research", "study_areas.md")
  if (!dir.exists(dirname(out))) {
    stop("cannot locate research/ from the script path", call. = FALSE)
  }
  con <- file(out, open = "wt")
  on.exit(close(con), add = TRUE)
  wr <- function(...) cat(..., "\n", sep = "", file = con)

  wr("# Study areas — drainage-independent components and host buckets")
  wr("")
  wr("<!-- GENERATED by data-raw/study_area_buckets.R --write. Do not hand-edit:")
  wr("     re-run the script instead, so the numbers stay derivable. -->")
  wr("")
  wr(sprintf("Generated from %d focal watershed groups, config `%s`, %d hosts.",
             length(focal), config, n_hosts))
  wr("")
  wr("## Scope, and who funds what")
  wr("")
  wr("Two scopes exist and are easy to conflate — it cost an hour on 2026-08-31.")
  wr("**Field scope** is the WSGs a GIS/Mergin project's AOI covers, recorded in")
  wr("`rtj/scripts/gis/projects/<name>/project.yml`. **Model scope** is the WSGs a")
  wr("report analyses, recorded as `wsg_code` in the reporting repo. They")
  wr("legitimately differ: the entire FWCP Peace region is modelled, while only")
  wr("the project WSGs go into the GIS.")
  wr("")
  wr("| area | funder | field (rtj) | model (reporting repo) |")
  wr("|---|---|---|---|")
  wr("| Peace | **FWCP** | 8 | 16 |")
  wr("| Fraser | **HCTF** (provincial) | 10 | 8 (may be stale) |")
  wr("| Skeena | **HCTF** (provincial) | not yet in rtj | 5 |")
  wr("| Columbia / nelson | - | 3 | - |")
  wr("")
  wr("Only Peace is FWCP. Calling all three \"the FWCP study areas\" was an error")
  wr("carried in several docs until 2026-08-31.")
  wr("")
  # Computed, not typed: the modelable count depends on the config's species
  # (217 under `bcfishpass`, 241 under `default`, link#246).
  n_all <- nrow(fresh::frs_wsg_outlets())
  if (setequal(focal, fresh::frs_wsg_outlets()$watershed_group_code)) {
    wr(sprintf("The focal set is all %d BC watershed groups; %d are modelable under",
               n_all, length(flat)))
    wr(sprintf("config `%s`.", config))
  } else {
    wr(sprintf("Note this file's focal set is **not** all of BC: %d watershed groups exist,",
               n_all))
    wr(sprintf("and the set below is the drainage closure of the focal groups, %d of",
               length(flat)))
    wr(sprintf("them modelable under config `%s`.", config))
  }
  wr("")
  wr("## Why components, not study areas")
  wr("")
  wr("Cross-WSG `;DAM` needs each host's bucket drainage-closed and run")
  wr("downstream-first. Where two hosts' closures overlap, the shared WSGs are")
  wr("modelled twice and `schema_consolidate` resolves the collision")
  wr("last-writer-wins — so whichever host finished last silently decides the")
  wr("answer. Partitioning into components whose closures are disjoint removes")
  wr("that ambiguity by construction, and the derivation asserts disjointness")
  wr("rather than assuming it.")
  wr("")
  wr("Partitioning by `wscode_ltree` root does **not** work: it reproduces the")
  wr("sliver misclassification RUNBOOK section 8b documents — NATR filed under")
  wr("Fraser though it drains to the Peace, SPAT under Skeena though it drains")
  wr("the Stikine. Closure is measure-aware; a wscode root is not.")
  wr("")
  wr("## Host buckets")
  wr("")
  wr(sprintf("Weights: %s.", weight_desc))
  wr("")
  wr(sprintf("| host | speed | components | focal | modelable | %s | est. share |", weight_unit))
  wr("|---|---|---|---|---|---|---|")
  for (h in seq_len(n_hosts)) {
    wr(sprintf("| %s | %.2fx | %d | %d | %d | %s | %.2f |", host_label(h),
               host_speeds[h], sum(assign_h == h), length(host_focal[[h]]),
               length(host_wsgs[[h]]), format(round(seg_h[h]), big.mark = ","),
               load_h[h] / max(load_h)))
  }
  wr("")
  wr(sprintf("%d focal WSGs resolve to %d components and %d modelable WSGs.",
             length(focal), length(components), length(flat)))
  wr("")
  wr("Components are indivisible, so the packing is a greedy LPT over")
  wr("component weights, not over WSGs. Weight is measured modelling minutes")
  wr("when `--minutes-schema=` names a persist schema with log rows, else")
  wr("stream-segment count from `fwa_stream_networks_sp` — a one-WSG component")
  wr("can outweigh a three-WSG one. Each component goes to the host that would")
  wr("finish it earliest at the given `--host-speeds` (equal by default).")
  wr("")
  wr("The component decomposition is a property of the drainage network and is")
  wr("stable; the host assignment is only as stable as the weights, so expect")
  wr("it to shift if the network table is reloaded.")
  wr("")
  wr("## `--focal=` strings")
  wr("")
  wr("```")
  wr("bash data-raw/study_area_run.sh \\")
  for (f in host_flags) wr(sprintf("  %s \\", f))
  for (h in seq_len(n_hosts)) {
    wr(sprintf("  --focal=%s \\", paste(sort(host_focal[[h]]), collapse = ",")))
  }
  # The config this split was derived for. Any config but bcfishpass also
  # needs --schema= (the driver's guard); a pasted bcfishpass line would
  # overwrite `fresh` (link#246).
  if (identical(config, "bcfishpass")) {
    wr("  --config=bcfishpass")
  } else {
    wr(sprintf("  --config=%s --schema=<persist schema>", config))
  }
  wr("```")
  wr("")
  wr("## Downstream-first order per host")
  wr("")
  for (h in seq_len(n_hosts)) {
    wr(sprintf("**%s** (%d WSGs)", host_label(h), length(host_wsgs[[h]])))
    wr("")
    wr(sprintf("    %s", paste(host_wsgs[[h]], collapse = ", ")))
    wr("")
  }
  wr("## Components")
  wr("")
  wr("| # | focal | modelable | host | focal WSGs |")
  wr("|---|---|---|---|---|")
  for (i in seq_along(components)) {
    wr(sprintf("| %d | %d | %d | %s | %s |", i,
               length(components[[i]]), length(resolved[[i]]),
               host_label(assign_h[i]),
               paste(components[[i]], collapse = " ")))
  }
  message("wrote ", out)
}
