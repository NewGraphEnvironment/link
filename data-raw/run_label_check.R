# run_label_check.R: the label rule for a standalone run (link#281).
#
# A run the driver dispatches carries LNK_RUN_UID, which says which dispatch it
# belongs to. A standalone wsg_run_one.R / wsg_recompute_one.R has none, and
# its run_uid stays NULL on purpose: run_uid means one dispatch across hosts,
# and PUBLISH refuses a build without one unless LNK_PUBLISH_ALLOW gives a
# reason (R/lnk_publish.R). So the label is what says what the run was for, and
# a standalone run must carry one.
#
# Returns NULL when the run may go on, else the message to print.
# Sourced by wsg_run_one.R and wsg_recompute_one.R; needs no database.
run_label_check <- function(uid = Sys.getenv("LNK_RUN_UID"),
                            label = Sys.getenv("LNK_RUN_LABEL")) {
  if (nzchar(uid)) return(NULL)
  if (!nzchar(label)) {
    return(paste0("a standalone run needs LNK_RUN_LABEL=<what this run is for> ",
                  "(it has no LNK_RUN_UID, so the label is its only record of why it ran)."))
  }
  if (!grepl("^[A-Za-z0-9._-]+$", label)) {
    return(sprintf("LNK_RUN_LABEL accepts only A-Z a-z 0-9 . _ - (got '%s').", label))
  }
  NULL
}

# Refuse (exit 2) a standalone run with no usable label.
run_label_require <- function(script) {
  msg <- run_label_check()
  if (!is.null(msg)) {
    message(script, ": ", msg)
    quit(status = 2)
  }
}
