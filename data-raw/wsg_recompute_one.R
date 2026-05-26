#!/usr/bin/env Rscript
# wsg_recompute_one.R — CHEAP post-consolidate recompute of access +
# mapping_code for ONE WSG, against PERSIST (link#205). Reuses the already-
# persisted streams / streams_habitat / barriers / barrier_overrides — does
# NOT re-run the full pipeline (no streams segmentation, no habitat classify).
# Run on the dispatcher AFTER consolidate to settle cross-WSG access/;DAM.
# Sibling of wsg_run_one.R (same LNK_LOAD + species-skip contract).
#
#   lnk_access(merge=TRUE)  -> surgically updates <persist>.streams_access
#                              (cross-WSG flags; preserves remediated + obs)
#   lnk_mapping_code        -> rebuilds mapping_code from the updated access,
#                              written into <persist>.streams_mapping_code via
#                              scratch + DELETE-WHERE-WSG + INSERT (JOIN streams
#                              for watershed_group_code; mirrors
#                              lnk_pipeline_persist).
#
# Usage: [LNK_LOAD=loadall] Rscript wsg_recompute_one.R <WSG> [config]

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) stop("usage: wsg_recompute_one.R <WSG> [config]", call. = FALSE)
wsg    <- toupper(args[1])
config <- if (length(args) >= 2L && nzchar(args[2])) args[2] else "bcfishpass"

if (identical(Sys.getenv("LNK_LOAD"), "loadall")) {
  suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
} else {
  suppressPackageStartupMessages(library(link))
}
suppressPackageStartupMessages({
  library(DBI); library(RPostgres)
})

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

# Fail fast, never hang silently (link#205 / RUNBOOK.md §6): a runaway access
# walk cancels server-side (no orphaned backend to wedge later recomputes), and
# a DROP VIEW (lnk_barriers_views) blocked behind a zombie lock gives up rather
# than blocking forever. A clean error -> a completion/failure signal, not a
# silent hang that needs manual `pg_terminate_backend`.
DBI::dbExecute(conn, "SET statement_timeout = '600000'")  # 10 min / statement
DBI::dbExecute(conn, "SET lock_timeout = '60000'")        # 1 min on lock waits

cfg    <- lnk_config(config)
loaded <- lnk_load_overrides(cfg)

active <- lnk_pipeline_species(cfg, loaded, wsg)
if (length(active) == 0L) {
  cat(sprintf("[wsg_recompute_one] %s SKIP - no modeled species\n", wsg))
  quit(status = 0)
}
pres <- lnk_presence(loaded$wsg_species_presence, wsg)
sch  <- cfg$pipeline$schema
t0   <- Sys.time()

# 1. Surgically recompute streams_access (cross-WSG cols) in place.
lnk_access(conn, cfg, aoi = wsg,
  table_streams  = paste0(sch, ".streams"),
  table_barriers = paste0(sch, ".barriers"),
  table_to       = paste0(sch, ".streams_access"),
  merge = TRUE, presence = pres, species = active)

# 2. Rebuild mapping_code from the updated access -> scratch -> persist.
sp_set <- tolower(active)
sp_resident   <- union(intersect(sp_set, c("bt", "wct")),
                       setdiff(sp_set, c("bt", "wct", "ch", "cm", "co", "pk", "sk", "st")))
sp_anadromous <- intersect(sp_set, c("ch", "cm", "co", "pk", "sk", "st"))
sp_spawn_only <- intersect(sp_set, c("cm", "pk"))

mc_name    <- paste0("zz_lnk_mc_scratch_", tolower(wsg))
mc_scratch <- paste0(sch, ".", mc_name)
on.exit(try(DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", mc_scratch)),
            silent = TRUE), add = TRUE)

lnk_mapping_code(conn,
  table_access  = paste0(sch, ".streams_access"),
  table_habitat = paste0(sch, ".streams_habitat_long_vw"),
  table_streams = paste0(sch, ".streams"),
  aoi           = wsg,
  table_to      = mc_scratch,
  presence      = pres,
  species_resident   = sp_resident,
  species_anadromous = sp_anadromous,
  species_spawn_only = sp_spawn_only)

# Persist write: DELETE-WHERE-WSG + INSERT (JOIN streams for WSG), mirroring
# lnk_pipeline_persist's mapping_code branch. Scratch has id_segment +
# mapping_code_<sp> only; watershed_group_code comes from streams.
mc_cols <- DBI::dbGetQuery(conn, sprintf(
  "SELECT column_name FROM information_schema.columns
   WHERE table_schema = %s AND table_name = %s AND column_name <> 'id_segment'
   ORDER BY ordinal_position",
  DBI::dbQuoteString(conn, sch), DBI::dbQuoteString(conn, mc_name)))$column_name
ins_cols <- paste(c("id_segment", "watershed_group_code", mc_cols), collapse = ", ")
sel_cols <- paste(c("m.id_segment", "s.watershed_group_code",
                    paste0("m.", mc_cols)), collapse = ", ")
wsg_lit  <- DBI::dbQuoteLiteral(conn, wsg)
DBI::dbExecute(conn, sprintf(
  "DELETE FROM %s.streams_mapping_code WHERE watershed_group_code = %s", sch, wsg_lit))
DBI::dbExecute(conn, sprintf(
  "INSERT INTO %s.streams_mapping_code (%s)
   SELECT %s FROM %s m JOIN %s.streams s USING (id_segment)
   WHERE s.watershed_group_code = %s",
  sch, ins_cols, sel_cols, mc_scratch, sch, wsg_lit))

cat(sprintf("[wsg_recompute_one] %s recomputed in %.2f min (persist=%s)\n",
            wsg, as.numeric(difftime(Sys.time(), t0, units = "mins")), sch))
