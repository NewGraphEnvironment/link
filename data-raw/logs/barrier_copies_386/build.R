#!/usr/bin/env Rscript
# build.R — one proof build for link#479 (#386, #236, #341): a set of groups
# modelled under one bundle into their own persist schema, each group in its
# own working schema (`<prefix><wsg>`), so no build reads another's working
# tables and another session's run of the same group cannot replace them
# (plan D9). Then the recompute pass over every group, from the same code, so
# each group's access reads every other group's landed rows whatever order
# they were built in.
#
# Usage: Rscript build.R <code dir> <config> <persist schema> <working prefix>
#                        <run_uid> <WSG,WSG,...>
#   code dir   a git worktree at the commit to build (load_all()ed)
# Writes a line per group to stdout; the log rows carry <run_uid> and the label
# `link479-proof`.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 6L) {
  stop("usage: build.R <code dir> <config> <persist schema> <working prefix> ",
       "<run_uid> <WSGS>", call. = FALSE)
}
code <- normalizePath(args[[1]], mustWork = TRUE)
config <- args[[2]]; persist <- args[[3]]; prefix <- args[[4]]
run_uid <- args[[5]]; wsgs <- strsplit(args[[6]], ",")[[1]]
stopifnot(grepl("^[a-z_][a-z0-9_]*$", persist), grepl("^[a-z_][a-z0-9_]*$", prefix))

suppressPackageStartupMessages(pkgload::load_all(code, quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config(config)
cfg$pipeline$schema <- persist
loaded <- lnk_load_overrides(cfg)
sha <- system2("git", c("-C", code, "rev-parse", "--short", "HEAD"), stdout = TRUE)
cat(sprintf("[build] %s %s -> %s at %s (%s)\n", config, run_uid, persist, sha,
            format(Sys.time(), tz = "UTC", usetz = TRUE)))

# A statement bound, because fresh's near-river walk can stall CPU-bound while
# other sessions load the database (link#487): a stalled group is retried
# once. A group this run_uid already finished is not rebuilt, so a stopped
# build resumes.
DBI::dbExecute(conn, "SET statement_timeout = '20min'")
done_here <- function(w) {
  if (!.lnk_table_exists(conn, paste0(persist, ".log"))) return(FALSE)
  nrow(DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM %s.log WHERE run_uid = %s AND watershed_group_code = %s
        AND date_end IS NOT NULL", persist,
    DBI::dbQuoteString(conn, run_uid), DBI::dbQuoteString(conn, w)))) > 0L
}
for (w in wsgs) {
  if (done_here(w)) {
    cat(sprintf("[build] %s model already finished under %s\n", w, run_uid))
    next
  }
  for (attempt in 1:2) {
    t0 <- Sys.time()
    ok <- tryCatch({
      lnk_pipeline_run(conn, aoi = w, cfg = cfg, loaded = loaded,
                       schema = paste0(prefix, tolower(w)),
                       mapping_code = TRUE, cleanup_working = FALSE,
                       habitat_gate = FALSE, run_uid = run_uid,
                       run_label = "link479-proof")
      TRUE
    }, error = function(e) {
      cat(sprintf("[build] %s attempt %d failed: %s\n", w, attempt,
                  conditionMessage(e)))
      FALSE
    })
    if (ok) break
    if (attempt == 2) stop("model failed twice for ", w, call. = FALSE)
  }
  cat(sprintf("[build] %s model done in %.1f min\n", w,
              as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}
DBI::dbDisconnect(conn)

# wsg_recompute_one.R load_all()s the working directory, so it runs from the
# worktree.
rc <- file.path(code, "data-raw", "wsg_recompute_one.R")
for (w in wsgs) {
  st <- withr::with_dir(code, system2("Rscript", c(rc, w, config),
                env = c("LNK_LOAD=loadall", paste0("LNK_SCHEMA=", persist),
                        paste0("LNK_RUN_UID=", run_uid),
                        "LNK_RUN_LABEL=link479-proof"),
                stdout = TRUE, stderr = TRUE))
  ok <- is.null(attr(st, "status"))
  # The downstream-state check runs after the recompute has committed
  # (wsg_recompute_one.R's post-condition). A proof set that leaves a group's
  # downstream groups out fails it by design; the recompute itself landed.
  post <- !ok && any(grepl("Model the downstream WSGs first", st, fixed = TRUE))
  cat(sprintf("[build] %s recompute %s\n", w,
              if (ok) "done" else if (post) {
                "done (downstream post-condition failed: groups outside the set)"
              } else "FAILED"))
  if (!ok && !post) {
    cat(tail(st, 20), sep = "\n")
    stop("recompute failed for ", w, call. = FALSE)
  }
}
cat(sprintf("[build] all done %s\n", format(Sys.time(), tz = "UTC", usetz = TRUE)))
