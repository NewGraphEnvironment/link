#!/usr/bin/env Rscript
# mechanism.R — attribute every piece where link's BT rearing flag and bcfishpass's
# disagree to one mechanism (#324). Reads the pieces written by
# data-raw/habitat_diff_segments.R (rearing and spawning) and the bcfishpass
# bundle's thresholds; writes <wsg>_<sp>_mechanism.csv, _mechanism_net.csv and
# _spawning_mechanism.csv beside them.
#
# Mechanisms, first match wins:
#   cw_order_bypass   bcfp-only, bcfp segment has a known width below the minimum but
#                     is order 1 with parent order >= 5: bcfishpass's rearing exception
#                     (a NULL width fails its `channel_width <= max` test, so it is never
#                     admitted)
#                     (load_habitat_linear_bt.sql), which the bcfishpass bundle
#                     declines (dimensions.csv rear_stream_order_bypass = no)
#   rear_gradient     the two sides' segment gradients fall on opposite sides of
#                     rear_gradient_max: same reach, different segment
#   access            link's own access code is 0 on the piece
#   connectivity      both segments pass the rearing thresholds; the flags differ
#                     through cluster connectivity to spawning. Split by whether the
#                     same blue_line_key also carries a gradient split (a rear_gradient
#                     piece, or a spawn_gradient piece): the split joins or cuts the
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

bypass <- p$class == "bcfp_only" & !is.na(p$b_cw) & p$b_cw < rc &
  !is.na(p$b_order) & p$b_order == 1 & !is.na(p$b_order_parent) & p$b_order_parent >= 5
grad   <- pass_g(p$l_gradient) != pass_g(p$b_gradient)
acc    <- !is.na(p$l_access) & p$l_access == 0
conn   <- pass_g(p$l_gradient) & pass_g(p$b_gradient) & pass_c(p$l_cw) &
  (pass_c(p$b_cw) | bypass)
sg <- thr$spawn_gradient_max
s_grad <- (!is.na(s$l_gradient) & s$l_gradient <= sg) != (!is.na(s$b_gradient) & s$b_gradient <= sg)
split_blk <- p$blk %in% unique(c(s$blk[s_grad], p$blk[grad & !bypass]))

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

# net km per mechanism family (link - bcfp) from unrounded lengths: the table
# research/bcfp_segmentation_parity.md quotes
fam <- sub("^connectivity_.*", "connectivity", p$mechanism)
sgn <- ifelse(p$class == "link_only", 1, -1) * p$len
net <- data.frame(
  wsg = toupper(wsg),
  rear_gradient = sum(sgn[fam == "rear_gradient"]),
  connectivity = sum(sgn[fam == "connectivity"]),
  connectivity_other_gross = sum(p$len[p$mechanism == "connectivity_other"]),
  cw_order_bypass = sum(sgn[fam == "cw_order_bypass"]),
  access = sum(sgn[fam == "access"]),
  other = sum(sgn[fam == "other"]),
  net = sum(sgn), gross = sum(p$len),
  segmentation_net = sum(sgn[fam %in% c("rear_gradient", "connectivity")]),
  segmentation_gross = sum(p$len[fam %in% c("rear_gradient", "connectivity")]))
net[-1] <- lapply(net[-1], function(v) round(v / 1000, 2))

# spawning disagreement, first match wins:
#   spawn_gradient   the two segments' gradients sit either side of spawn_gradient_max
#   spawn_width_min  bcfp's width is exactly spawn_channel_width_min: bcfishpass spawns
#                    on width > min (load_habitat_linear_bt.sql), fresh on >= min
#   access           link's own access code is 0
#   other
sw <- thr$spawn_channel_width_min
s_width <- !is.na(s$b_cw) & abs(s$b_cw - sw) < 1e-9
s_acc <- !is.na(s$l_access) & s$l_access == 0
s$mechanism <- ifelse(s_grad, "spawn_gradient", ifelse(s_width, "spawn_width_min",
                ifelse(s_acc, "access", "other")))
spawn <- stats::aggregate(len ~ class + mechanism, s, function(v) round(sum(v) / 1000, 2))
names(spawn)[names(spawn) == "len"] <- "km"
spawn <- spawn[order(spawn$class, -spawn$km), ]

utils::write.csv(out, file.path(dir, sprintf("%s_%s_mechanism.csv", wsg, sp)), row.names = FALSE)
utils::write.csv(spawn, file.path(dir, sprintf("%s_%s_spawning_mechanism.csv", wsg, sp)),
                 row.names = FALSE)
utils::write.csv(net, file.path(dir, sprintf("%s_%s_mechanism_net.csv", wsg, sp)), row.names = FALSE)
cat(sprintf("%s %s rearing disagreement by mechanism (km):\n", toupper(wsg), toupper(sp)))
print(out, row.names = FALSE)
cat("\nspawning disagreement by mechanism (km):\n")
print(spawn, row.names = FALSE)
cat("\nnet km by mechanism family (link - bcfp):\n")
print(net, row.names = FALSE)
