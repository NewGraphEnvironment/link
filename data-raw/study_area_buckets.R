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
# Usage:
#   [LNK_LOAD=loadall] Rscript data-raw/study_area_buckets.R \
#     [--hosts=4] [--config=bcfishpass] [--focal=A,B,C] [--write]
#
#   --hosts=N   number of hosts to pack onto (default 4: dispatcher + 3)
#   --focal=    override the focal set (default: the baked-in 96)
#   --write     rewrite research/study_areas.md from this run's output
#
# Stdout is the report. Nothing is written unless --write is passed.

args <- commandArgs(trailingOnly = TRUE)
arg_val <- function(flag, default) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (!length(hit)) return(default)
  sub(paste0("^", flag, "="), "", hit[1])
}
n_hosts <- as.integer(arg_val("--hosts", "4"))
config  <- arg_val("--config", "bcfishpass")
do_write <- "--write" %in% args
if (is.na(n_hosts) || n_hosts < 1L) {
  stop("--hosts must be a positive integer", call. = FALSE)
}

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
# Stream-segment count per WSG is a far better proxy for modelling work than
# a WSG count, and it is one query. Groups absent from the network table get
# the median rather than zero, so an unknown never packs as free.
w <- DBI::dbGetQuery(conn,
  "SELECT watershed_group_code AS wsg, count(*)::numeric AS n
     FROM whse_basemapping.fwa_stream_networks_sp GROUP BY 1")
wmap <- stats::setNames(w$n, w$wsg)
med <- stats::median(w$n)
weight_of <- function(wsgs) {
  v <- wmap[wsgs]
  v[is.na(v)] <- med
  sum(v)
}
comp_weight <- vapply(resolved, weight_of, numeric(1))

# --- 5. greedy LPT pack ----------------------------------------------------
ord <- order(-comp_weight)
load_h <- rep(0, n_hosts)
assign_h <- integer(length(resolved))
for (i in ord) {
  pick <- which.min(load_h)
  assign_h[i] <- pick
  load_h[pick] <- load_h[pick] + comp_weight[i]
}

# Host 1 is the dispatcher: free and fast, so it should carry the most.
# Reorder host labels by descending load so that is true by construction.
host_order <- order(-load_h)
relabel <- stats::setNames(seq_along(host_order), host_order)
assign_h <- as.integer(relabel[as.character(assign_h)])
load_h <- load_h[host_order]

host_focal <- lapply(seq_len(n_hosts), function(h) {
  unlist(components[assign_h == h], use.names = FALSE)
})
host_wsgs <- lapply(seq_len(n_hosts), function(h) {
  unlist(resolved[assign_h == h], use.names = FALSE)
})

# --- 6. report -------------------------------------------------------------
host_label <- function(h) if (h == 1L) "dispatcher (m1)" else sprintf("job%d", h - 1L)

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
cat("| host | components | focal | modelable | weight (segments) |\n")
cat("|---|---|---|---|---|\n")
for (h in seq_len(n_hosts)) {
  cat(sprintf("| %s | %d | %d | %d | %s |\n", host_label(h),
              sum(assign_h == h), length(host_focal[[h]]),
              length(host_wsgs[[h]]), format(load_h[h], big.mark = ",")))
}
cat(sprintf("\ntotal modelable: %d | dropped by species presence: %d\n",
            length(flat),
            length(unique(unlist(closures))) - length(flat)))

cat("\n## --focal= strings\n\n")
cat("```\n")
for (h in seq_len(n_hosts)) {
  cat(sprintf("  --focal=%s \\\n", paste(sort(host_focal[[h]]), collapse = ",")))
}
cat("```\n")

cat("\n## DS-first order per host\n\n")
for (h in seq_len(n_hosts)) {
  cat(sprintf("- **%s** (%d): %s\n", host_label(h), length(host_wsgs[[h]]),
              paste(host_wsgs[[h]], collapse = ", ")))
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
  wr("| host | components | focal | modelable | weight (segments) |")
  wr("|---|---|---|---|---|")
  for (h in seq_len(n_hosts)) {
    wr(sprintf("| %s | %d | %d | %d | %s |", host_label(h),
               sum(assign_h == h), length(host_focal[[h]]),
               length(host_wsgs[[h]]), format(load_h[h], big.mark = ",")))
  }
  wr("")
  wr(sprintf("%d focal WSGs resolve to %d components and %d modelable WSGs.",
             length(focal), length(components), length(flat)))
  wr("")
  wr("Components are indivisible, so the packing is a greedy LPT over")
  wr("component weights, not over WSGs. Weight is stream-segment count from")
  wr("`fwa_stream_networks_sp`, which tracks modelling work far better than a")
  wr("WSG count does — a one-WSG component can outweigh a three-WSG one. The")
  wr("dispatcher is relabelled to whichever host draws the heaviest load,")
  wr("since it is the free, fast local machine while the cyphers are paid.")
  wr("")
  wr("The component decomposition is a property of the drainage network and is")
  wr("stable; the host assignment is only as stable as the weights, so expect")
  wr("it to shift if the network table is reloaded.")
  wr("")
  wr("## `--focal=` strings")
  wr("")
  wr("```")
  wr("bash data-raw/study_area_run.sh \\")
  wr(sprintf("  --cy-workspaces=%s \\",
             paste(sprintf("job%d", seq_len(n_hosts - 1L)), collapse = ",")))
  for (h in seq_len(n_hosts)) {
    wr(sprintf("  --focal=%s \\", paste(sort(host_focal[[h]]), collapse = ",")))
  }
  wr("  --config=bcfishpass")
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
