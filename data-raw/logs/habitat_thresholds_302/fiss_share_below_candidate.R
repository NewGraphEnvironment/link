# fiss_share_below_candidate.R — share of FISS sites (snapped <= 50 m) whose segment
# mad_m3s sits below each rear MAD candidate, present vs absent (link#302).
# Input: the site rows query_habitat_thresholds_fiss.R writes to LNK_FISS_SITES_OUT
# (knowledge is private; only these aggregates are committed). Run 2026-10-02:
#   LNK_FISS_SITES_OUT=<tmp>/sites.csv Rscript data-raw/query_habitat_thresholds_fiss.R \
#     --species=BT,GR,KO,RB --out=<tmp>
#   Rscript data-raw/logs/habitat_thresholds_302/fiss_share_below_candidate.R <tmp>/sites.csv \
#     data-raw/logs/habitat_thresholds_302/fiss_share_below_candidate.csv
suppressMessages(pkgload::load_all(quiet = TRUE))
s <- read.csv(commandArgs(TRUE)[1])
pr <- read.csv(lnk_config("default")$files$wsg_species_presence$path, colClasses = "character")
cand <- c(BT = 0.027, GR = 0.095, RB = 0.0094)
out <- do.call(rbind, lapply(names(cand), function(sp) {
  col <- tolower(sp); inr <- toupper(pr$watershed_group_code[pr[[col]] %in% "t"])
  d <- s[toupper(s$watershed_group_code) %in% inr & (s$sampled | s[[col]]) & !is.na(s$seg_mad_m3s) & s$dist_m <= 50, ]
  d$outcome <- ifelse(d[[col]], "present", "absent")
  a <- aggregate(seg_mad_m3s ~ outcome, d, function(x) c(n = length(x), share_below = mean(x < cand[[sp]])))
  data.frame(species_code = sp, candidate_rear_mad_min = cand[[sp]], outcome = a$outcome, n = a$seg_mad_m3s[, "n"], share_below_candidate = round(a$seg_mad_m3s[, "share_below"], 3))
}))
print(out)
write.csv(out, commandArgs(TRUE)[2], row.names = FALSE)
