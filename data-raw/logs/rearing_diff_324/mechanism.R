#!/usr/bin/env Rscript
# mechanism.R — attribute every piece where link's BT rearing flag and bcfishpass's
# disagree to one mechanism (#324). Reads the pieces written by
# data-raw/habitat_diff_segments.R (rearing and spawning) and the bcfishpass
# bundle's thresholds; writes <wsg>_<sp>_mechanism.csv beside them.
#
# Mechanisms, first match wins:
#   cw_order_bypass   bcfp-only, bcfp segment fails the width minimum but is order 1
#                     with parent order >= 5: bcfishpass's rearing exception
#                     (load_habitat_linear_bt.sql), which the bcfishpass bundle
#                     declines (dimensions.csv rear_stream_order_bypass = no)
#   rear_gradient     the two sides' segment gradients fall on opposite sides of
#                     rear_gradient_max: same reach, different segment
#   access            link's own access code is 0 on the piece
#   connectivity      both segments pass the rearing thresholds; the flags differ
#                     through cluster connectivity to spawning. Split by whether the
#                     same blue_line_key also carries a gradient split (a rear_gradient
#                     piece, or a spawning disagreement): the split joins or cuts the
#                     cluster there
#   other
#
# Usage: Rscript data-raw/logs/rearing_diff_324/mechanism.R [wsg] [sp]

args <- commandArgs(trailingOnly = TRUE)
wsg  <- tolower(if (length(args) >= 1) args[1] else "pcea")
sp   <- tolower(if (length(args) >= 2) args[2] else "bt")
dir  <- "data-raw/logs/rearing_diff_324"

thr <- utils::read.csv("inst/extdata/configs/bcfishpass/parameters_habitat_thresholds.csv")
thr <- thr[thr$species_code == toupper(sp), ]
stopifnot(nrow(thr) == 1)
rg <- thr$rear_gradient_max
rc <- thr$rear_channel_width_min

p <- utils::read.csv(file.path(dir, sprintf("%s_%s_pieces.csv", wsg, sp)))
s <- utils::read.csv(file.path(dir, sprintf("%s_%s_spawning_pieces.csv", wsg, sp)))
pass_g <- function(g) !is.na(g) & g <= rg
pass_c <- function(w) !is.na(w) & w >= rc

bypass <- p$class == "bcfp_only" & !pass_c(p$b_cw) &
  !is.na(p$b_order) & p$b_order == 1 & !is.na(p$b_order_parent) & p$b_order_parent >= 5
grad   <- pass_g(p$l_gradient) != pass_g(p$b_gradient)
acc    <- !is.na(p$l_access) & p$l_access == 0
conn   <- pass_g(p$l_gradient) & pass_g(p$b_gradient) & pass_c(p$l_cw) &
  (pass_c(p$b_cw) | bypass)
split_blk <- p$blk %in% unique(c(s$blk, p$blk[grad & !bypass]))

p$mechanism <- ifelse(bypass, "cw_order_bypass",
               ifelse(grad, "rear_gradient",
               ifelse(acc, "access",
               ifelse(conn & split_blk, "connectivity_split_on_blk",
               ifelse(conn, "connectivity_other", "other")))))

out <- stats::aggregate(len ~ class + mechanism, p, function(v) round(sum(v) / 1000, 2))
names(out)[names(out) == "len"] <- "km"
n <- stats::aggregate(blk ~ class + mechanism, p, function(v) length(unique(v)))
names(n)[names(n) == "blk"] <- "n_blk"
out <- merge(out, n)
out <- out[order(out$class, -out$km), ]

# spawning disagreement: share explained by the spawn gradient threshold alone
sg <- thr$spawn_gradient_max
s_grad <- (!is.na(s$l_gradient) & s$l_gradient <= sg) != (!is.na(s$b_gradient) & s$b_gradient <= sg)
spawn <- stats::aggregate(len ~ class + s_grad, transform(s, s_grad = s_grad),
                          function(v) round(sum(v) / 1000, 2))
names(spawn) <- c("class", "spawn_gradient_split", "km")

utils::write.csv(out, file.path(dir, sprintf("%s_%s_mechanism.csv", wsg, sp)), row.names = FALSE)
utils::write.csv(spawn, file.path(dir, sprintf("%s_%s_spawning_mechanism.csv", wsg, sp)),
                 row.names = FALSE)
cat(sprintf("%s %s rearing disagreement by mechanism (km):\n", toupper(wsg), toupper(sp)))
print(out, row.names = FALSE)
cat("\nspawning disagreement, split by the spawn gradient threshold (km):\n")
print(spawn, row.names = FALSE)
