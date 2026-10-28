#!/usr/bin/env Rscript
# pretest_reach_fresh.R — which fresh files link's modelling path reaches
# (link#372), at a fresh checkout. The pick runs the same walk
# (pretest_reach_fresh_at() in pretest.R) on every gate whose range changes a
# fresh file the map marks `none`; this prints it, to set the map's rows:
#
#   git -C ../fresh worktree add <dir> <tag>
#   Rscript data-raw/pretest_reach_fresh.R <dir>

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L || !dir.exists(file.path(args[1], "R"))) {
  stop("usage: pretest_reach_fresh.R <fresh checkout at the tag to judge>", call. = FALSE)
}
script_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))))
source(file.path(script_dir, "pretest.R"))
on <- pretest_reach_fresh(normalizePath(file.path(script_dir, "..")), args[1])
cat("REACHED:", on, "\n")
cat("NOT REACHED:", setdiff(sort(list.files(file.path(args[1], "R"), pattern = "\\.R$")), on), "\n")
