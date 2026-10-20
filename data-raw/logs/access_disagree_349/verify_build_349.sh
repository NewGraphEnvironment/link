#!/usr/bin/env bash
# verify_build_349.sh — link#349 Phase 4: build UPCE, CARP and DUNC under
# `default` into scratch schema fresh_349 with the habitat gate OFF, measure,
# recompute (which settles), measure again.
set -euo pipefail
cd ~/Projects/repo/link
LOG=data-raw/logs/access_disagree_349
export PGPASSWORD=postgres LNK_SCHEMA=fresh_349 LNK_LOAD=loadall
PSQL=(psql -h localhost -p 5432 -U postgres -d fwapg -v ON_ERROR_STOP=1 -q)

# 1. Seed: persist tables, then fresh_default's barriers + overrides, so the
#    three groups see every other group's barriers as the province-wide run did.
Rscript -e 'suppressMessages(pkgload::load_all(quiet = TRUE))
  conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "postgres")
  cfg <- lnk_config("default"); cfg$pipeline$schema <- "fresh_349"
  lnk_persist_init(conn, cfg, species = cfg$species)
  DBI::dbExecute(conn, "INSERT INTO fresh_349.barriers SELECT * FROM fresh_default.barriers")
  DBI::dbExecute(conn, "INSERT INTO fresh_349.barrier_overrides SELECT * FROM fresh_default.barrier_overrides")
  DBI::dbExecute(conn, "ANALYZE fresh_349.barriers")
  DBI::dbExecute(conn, "ANALYZE fresh_349.barrier_overrides")'

# 2. Build, downstream first, gate off.
for w in UPCE CARP DUNC; do
  LNK_HABITAT_GATE=0 Rscript data-raw/wsg_run_one.R "$w" default
done

# 3. Classify-time state: views over fresh_349 (the recompute builds them;
#    nothing has yet), then the Phase 1 classes.
Rscript -e 'suppressMessages(pkgload::load_all(quiet = TRUE))
  conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "postgres")
  cfg <- lnk_config("default"); cfg$pipeline$schema <- "fresh_349"
  lnk_barriers_views(conn, schema = "fresh_349", cfg = cfg, species = cfg$species,
                     barriers_table = "fresh_349.barriers")'
Rscript data-raw/access_disagree_349.R --schema=fresh_349 --wsgs=UPCE,CARP,DUNC --out=$LOG/before

# 4. Recompute (settles), downstream first, then measure again.
for w in UPCE CARP DUNC; do
  Rscript data-raw/wsg_recompute_one.R "$w" default
done
Rscript data-raw/access_disagree_349.R --schema=fresh_349 --wsgs=UPCE,CARP,DUNC --out=$LOG/after
echo VERIFY_BUILD_DONE
