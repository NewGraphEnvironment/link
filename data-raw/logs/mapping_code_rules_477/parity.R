# data-raw/logs/mapping_code_rules_477/parity.R
#
# Rebuilds the mapping codes of five groups from persisted access and habitat,
# the inputs `.lnk_mapping_code_persist()` reads, and writes one md5 per group,
# species and schema. Nothing is written to the database: `lnk_mapping_code()`
# runs with `table_to = NULL` and the codes are hashed in R.
#
# Run once at the base commit (a git worktree of main) and once at the branch:
#
#   Rscript data-raw/logs/mapping_code_rules_477/parity.R \
#     --repo=<checkout> --label=before --out=data-raw/logs/mapping_code_rules_477
#
# then compare.R reports any group, species or schema whose md5 differs.

args <- commandArgs(trailingOnly = TRUE)
arg <- function(k) {
  v <- sub(paste0("^--", k, "="), "", grep(paste0("^--", k, "="), args, value = TRUE))
  if (length(v) != 1L || !nzchar(v)) stop("--", k, "= is required", call. = FALSE)
  v
}
repo  <- arg("repo")
label <- arg("label")
out   <- arg("out")

pkgload::load_all(repo, quiet = TRUE)
ns <- asNamespace("link")

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
on.exit(DBI::dbDisconnect(conn), add = TRUE)

runs <- list(
  list(config = "default",    schema = "fresh_default",
       wsgs = c("ADMS", "BULK", "ELKR", "HORS", "PARS")),
  list(config = "bcfishpass", schema = "fresh",
       wsgs = c("BULK", "ELKR", "PARS")))

rows <- list()
for (r in runs) {
  cfg <- lnk_config(r$config)
  loaded <- lnk_load_overrides(cfg)
  groups <- get(".lnk_presence_groups", ns)(loaded)
  for (w in r$wsgs) {
    active <- lnk_pipeline_species(cfg, loaded, w)
    pres <- lnk_presence(loaded$wsg_species_presence, w, groups = groups)
    res <- get(".lnk_species_residence", ns)(cfg, tolower(active))
    a <- list(conn,
      table_access  = paste0(r$schema, ".streams_access"),
      table_habitat = paste0(r$schema, ".streams_habitat_long_vw"),
      table_streams = paste0(r$schema, ".streams"),
      aoi = w, table_to = NULL, presence = pres,
      species_resident = res$resident, species_anadromous = res$anadromous,
      species_spawn_only = res$spawn_only)
    # The branch's build also reads the bundle's rules through `cfg`.
    if ("cfg" %in% names(formals(lnk_mapping_code))) a$cfg <- cfg
    mc <- as.data.frame(do.call(lnk_mapping_code, a))
    mc <- mc[order(mc$id_segment), , drop = FALSE]
    for (col in setdiff(names(mc), "id_segment")) {
      rows[[length(rows) + 1L]] <- data.frame(
        config = r$config, schema = r$schema, wsg = w, column = col,
        n = nrow(mc),
        md5 = digest::digest(list(mc$id_segment, mc[[col]]), algo = "md5"),
        stringsAsFactors = FALSE)
    }
    cat(sprintf("[parity] %s %s %s: %d segments, %d columns\n",
                label, r$schema, w, nrow(mc), ncol(mc) - 1L))
  }
}

res <- do.call(rbind, rows)
sha <- tryCatch(system2("git", c("-C", repo, "rev-parse", "--short", "HEAD"),
                        stdout = TRUE), error = function(e) NA_character_)
res$label <- label
res$link_sha <- sha
dir.create(out, showWarnings = FALSE, recursive = TRUE)
f <- file.path(out, paste0("digests_", label, ".csv"))
utils::write.csv(res, f, row.names = FALSE)
cat(sprintf("[parity] wrote %s (%d rows) at %s\n", f, nrow(res), sha))
