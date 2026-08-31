#!/usr/bin/env Rscript
# host_stamp.R — emit this host's parity stamp as one tab-separated line.
#
# Byte-identical on the dispatcher and every cypher; consumed by
# study_area_run.sh's preflight_hosts(), which rbinds the lines and hands
# them to lnk_preflight_parity() (link#246, absorbing #183).
#
# A driver script rather than an inline `Rscript -e` over ssh for the same
# reason wsg_run_one.R exists: the ssh leg's nested quoting is where these
# things rot, and the cyphers already carry data-raw/* from their
# `git reset --hard origin/$BRANCH`.
#
# `repo = getwd()` is the point of the whole exercise — the stamp reports
# the git state of the checkout THIS host installed from, observed here.
# See lnk_preflight_stamp() for why that is the honest key and link_sha is
# not.
#
# Usage: [LNK_LOAD=loadall] Rscript data-raw/host_stamp.R [config]

args   <- commandArgs(trailingOnly = TRUE)
config <- if (length(args) >= 1L && nzchar(args[1])) args[1] else "bcfishpass"

if (identical(Sys.getenv("LNK_LOAD"), "loadall")) {
  suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
} else {
  suppressPackageStartupMessages(library(link))
}

cat(paste(lnk_preflight_stamp(lnk_config(config), repo = getwd()),
          collapse = "\t"), "\n", sep = "")
