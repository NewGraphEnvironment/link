# data-raw/rule_flexibility_render.R
#
# Phase 3 of link#69: render the proof artifact tables into
# `research/rule_flexibility.md` from the data captured by
# `rule_flexibility_demo.R`.
#
# Run from the link repo root:
#   Rscript data-raw/rule_flexibility_render.R

suppressMessages(library(yaml))

data_rds <- "research/rule_flexibility_data.rds"
md_path <- "research/rule_flexibility.md"

if (!file.exists(data_rds)) {
  stop("Run data-raw/rule_flexibility_demo.R first to generate ", data_rds)
}

x <- readRDS(data_rds)
species <- x$species
wsg <- x$wsg

# -----------------------------------------------------------------------------
# Build rollup table — one row per habitat_type, one column per config.
# -----------------------------------------------------------------------------
slice_rollup <- function(rollup, species_code) {
  r <- rollup[rollup$species == species_code, ]
  rownames(r) <- NULL
  r
}

rollups <- lapply(x$results, function(r) slice_rollup(r$rollup, species))

# Build markdown table.
habitat_types <- c("spawning", "rearing", "lake_rearing", "wetland_rearing")
units <- c("km", "km", "ha", "ha")

# header
hdr_cells <- c("habitat", "unit",
               vapply(x$results, function(r) r$name, character(1)))
hdr <- paste0("| ", paste(hdr_cells, collapse = " | "), " |")
sep <- paste0("| ", paste(rep("---", length(hdr_cells)),
                          collapse = " | "), " |")
rows <- character(0)
for (i in seq_along(habitat_types)) {
  ht <- habitat_types[i]
  vals <- vapply(rollups, function(r) {
    row <- r[r$habitat_type == ht, ]
    if (nrow(row) == 0) return("—")
    sprintf("%.2f", row$link_value)
  }, character(1))
  rows <- c(rows, paste0("| ", paste(c(ht, units[i], vals),
                                      collapse = " | "), " |"))
}
# Add bcfp diff_pct row for parity context (only the bcfishpass run has it
# meaningful; the rollup carries the bcfp reference for any config).
rows <- c(rows, "")
rows <- c(rows, "**bcfishpass parity** (bcfishpass.habitat_linear_co reference, identical for all configs):")
rows <- c(rows, "")
parity_hdr <- "| habitat | bcfp_value (km) | uc1 diff_pct | uc2 diff_pct | bcfp diff_pct |"
parity_sep <- "| --- | --- | --- | --- | --- |"
parity_rows <- character(0)
for (ht in c("spawning", "rearing")) {
  bcfp_val <- NA
  diffs <- vapply(rollups, function(r) {
    row <- r[r$habitat_type == ht, ]
    if (nrow(row) == 0) return("—")
    sprintf("%+.1f%%", row$diff_pct)
  }, character(1))
  bcfp_val <- rollups[[1]][rollups[[1]]$habitat_type == ht, "bcfishpass_value"]
  parity_rows <- c(parity_rows,
    sprintf("| %s | %.2f | %s | %s | %s |",
      ht, bcfp_val,
      diffs["use_case_1"],
      diffs["use_case_2"],
      diffs["bcfishpass"]))
}

rollup_block <- paste(c(hdr, sep, rows, "",
                         parity_hdr, parity_sep, parity_rows),
                      collapse = "\n")

# -----------------------------------------------------------------------------
# Build rules.yaml diff block — render each config's CO rear: list as YAML.
# -----------------------------------------------------------------------------
yaml_block <- function(name, rules_co) {
  # Re-render just the rear block for this species
  txt <- yaml::as.yaml(list(CO = list(rear = rules_co$rear)),
                        indent = 2)
  paste0("**", name, "**\n\n```yaml\n", txt, "```\n")
}

rules_block <- paste(vapply(x$results, function(r) {
  yaml_block(r$name, r$rules_co)
}, character(1)), collapse = "\n")

# -----------------------------------------------------------------------------
# Substitute placeholders in the markdown.
# -----------------------------------------------------------------------------
md <- readLines(md_path)
md <- sub("<!-- ROLLUP_TABLE -->", "<!-- ROLLUP_TABLE -->", md, fixed = TRUE)

idx_roll <- which(grepl("<!-- ROLLUP_TABLE -->", md, fixed = TRUE))
idx_rules <- which(grepl("<!-- RULES_DIFF -->", md, fixed = TRUE))
stopifnot(length(idx_roll) == 1, length(idx_rules) == 1)

new_md <- c(
  md[seq_len(idx_roll - 1)],
  rollup_block,
  md[seq(idx_roll + 1, idx_rules - 1)],
  rules_block,
  md[seq(idx_rules + 1, length(md))]
)

writeLines(new_md, md_path)
message("Updated ", md_path, " (", length(new_md), " lines)")

cat("\n=== Rollup snapshot ===\n")
cat(rollup_block, sep = "\n")
