# Usage: Rscript validate_run.R <repo> <schema> <method_csv|-> <species,..> <out_rds>
# Runs lnk_habitat_validate() on ADMS with the `default` bundle from <repo>
# (branch or a main worktree), optionally with the method table swapped on
# the same cfg object, and saves the result.
args <- commandArgs(trailingOnly = TRUE)
repo <- args[1]; schema <- args[2]; method_csv <- args[3]
species <- strsplit(args[4], ",")[[1]]; out <- args[5]
suppressMessages(devtools::load_all(repo, quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config("default")
if (method_csv != "-") {
  cfg$files$parameters_habitat_method <- list(path = normalizePath(method_csv))
}
loaded <- suppressWarnings(lnk_load_overrides(cfg))
pool <- lnk_species_pooling(loaded, aoi = "ADMS", species = species)
t0 <- Sys.time()
v <- lnk_habitat_validate(conn, aoi = "ADMS", cfg = cfg, loaded = loaded,
                          species = species, schema = schema,
                          species_obs = pool)
v$stamp <- list(repo = repo, sha = system2("git", c("-C", repo, "rev-parse",
                                                   "--short", "HEAD"),
                                           stdout = TRUE),
                link = as.character(utils::packageVersion("link")),
                fresh = as.character(utils::packageVersion("fresh")),
                schema = schema, method_csv = method_csv,
                secs = as.numeric(difftime(Sys.time(), t0, units = "secs")))
saveRDS(v, out)
cat(sprintf("## validate %s %s method=%s sha=%s fresh=%s %.0f s, %d locations\n",
            schema, paste(species, collapse = ","), basename(method_csv),
            v$stamp$sha, v$stamp$fresh, v$stamp$secs, nrow(v$observations)))
DBI::dbDisconnect(conn)
