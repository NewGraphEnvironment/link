# Usage: Rscript compare.R <dir>
# 1. cw no-change: branch vs main on fresh_default, new columns dropped.
# 2. mad: where the persisted flag is TRUE but the re-built predicate is
#    FALSE, outside the UHC overlay. Classify's own predicate cannot
#    disagree that way, so a non-zero count means the validator re-built a
#    different predicate. Branch vs main on the same mad-classified schema.
# 3. Reasons on the mad run, branch vs main.
d <- commandArgs(trailingOnly = TRUE)[1]
rd <- function(f) readRDS(file.path(d, f))
new_obs <- c("model", "mad_m3s", "pred_spawn_nomad", "pred_spawn_nomad_g",
             "pred_rear_nomad", "pred_rear_nomad_g")
strip <- function(x, drop) {
  x <- x[, setdiff(names(x), drop), drop = FALSE]
  rownames(x) <- NULL
  x
}
bc <- rd("branch_cw.rds"); mc <- rd("main_cw.rds")
cat("## 1. cw no-change (fresh_default, ADMS)\n")
cat("observations identical apart from new columns:",
    isTRUE(all.equal(strip(bc$observations, new_obs),
                     strip(mc$observations, character(0)))), "\n")
cat("summary identical apart from `model`:",
    isTRUE(all.equal(strip(bc$summary, "model"),
                     strip(mc$summary, character(0)))), "\n")
cat("branch model column:", unique(bc$observations$model), "\n")
cat("observations:", nrow(bc$observations), "\n\n")

disagree <- function(o) {
  data.frame(
    species_code = sort(unique(o$species_code)),
    n = as.vector(table(o$species_code)[sort(unique(o$species_code))]),
    spawn_true_pred_false = vapply(sort(unique(o$species_code)), function(sp) {
      k <- o$species_code == sp
      sum(o$spawning[k] %in% TRUE & o$pred_spawn[k] %in% FALSE &
            !o$in_uhc_spawn[k])
    }, integer(1)),
    rear_true_pred_false = vapply(sort(unique(o$species_code)), function(sp) {
      k <- o$species_code == sp
      sum(o$rearing_any[k] %in% TRUE & o$pred_rear[k] %in% FALSE &
            !o$in_uhc_rear[k])
    }, integer(1)), row.names = NULL)
}
bm <- rd("branch_mad.rds"); mm <- rd("main_mad.rds")
cat("## 2. persisted TRUE, re-built predicate FALSE (zz299_mad, ADMS on mad)\n")
cat("branch:\n"); print(disagree(bm$observations), row.names = FALSE)
cat("main (cw predicates on a mad run):\n")
print(disagree(mm$observations), row.names = FALSE)
cat("\n## 3. miss reasons on the mad run (locations)\n")
# `all`: every location, against that stage's predicate. `staged`: only
# locations whose records carry the stage, as the summary's stage rows and
# the driver's misses.csv count them.
tab <- function(o, col, keep) {
  o <- o[keep(o), , drop = FALSE]
  as.data.frame(table(species = o$species_code,
                      reason = ifelse(is.na(o[[col]]), "captured", o[[col]])),
                stringsAsFactors = FALSE)
}
sets <- list(
  spawn_all = list("miss_reason_spawn", function(o) rep(TRUE, nrow(o))),
  spawn_staged = list("miss_reason_spawn", function(o) o$is_spawn %in% TRUE),
  rear_all = list("miss_reason_rear", function(o) rep(TRUE, nrow(o))),
  rear_staged = list("miss_reason_rear", function(o) o$is_rear %in% TRUE))
for (nm in names(sets)) {
  col <- sets[[nm]][[1]]; keep <- sets[[nm]][[2]]
  m <- merge(tab(bm$observations, col, keep), tab(mm$observations, col, keep),
             by = c("species", "reason"), all = TRUE,
             suffixes = c("_branch", "_main"))
  m[is.na(m)] <- 0L
  m <- m[m$Freq_branch > 0 | m$Freq_main > 0, ]
  cat(nm, "\n"); print(m, row.names = FALSE)
}
cat("\nmad_m3s present on", sum(!is.na(bm$observations$mad_m3s)), "of",
    nrow(bm$observations), "mad-group locations\n")
cat("validate seconds: branch cw", round(bc$stamp$secs), "main cw",
    round(mc$stamp$secs), "branch mad", round(bm$stamp$secs), "main mad",
    round(mm$stamp$secs), "\n")
