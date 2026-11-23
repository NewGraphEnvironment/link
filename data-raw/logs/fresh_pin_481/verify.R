#!/usr/bin/env Rscript
# verify.R — #481's checks on the stored column and the validator, after the
# after-arm build (fresh 0.55.1, this branch), on m1's local fwapg.
#
# 1. Every fresh_pin481_after.streams_near_river row carries the
#    linear_feature_id of its streams row at (id_segment, watershed_group_code),
#    and none is NULL.
# 2. The branch's lnk_persist_init() on a copy of fresh_pin481_before's
#    streams and streams_near_river (built at 0.52.0, no column) fills the
#    column with what fresh 0.55.1 wrote in fresh_pin481_after.
# 3. lnk_habitat_validate() on fresh_pin481_after (ADMS, default) gives the
#    same results with the predicates keyed on the parent line
#    (near_river_lfid = TRUE, what the validator passes) and without it
#    (FALSE), over observations on near-river segments.
#
# Usage (from the repo root, R_LIBS holding fresh 0.55.1):
#   Rscript data-raw/logs/fresh_pin_481/verify.R
# Writes verify.txt beside it. Drops its copy schema once check 2 has read it;
# a run that stops before then leaves it, and the next run drops it first.
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
stopifnot(utils::packageVersion("fresh") == "0.55.1")
dir <- "data-raw/logs/fresh_pin_481"
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
q <- function(sql) DBI::dbGetQuery(conn, sql)
ex <- function(sql) invisible(DBI::dbExecute(conn, sql))
lines <- character(0)
say <- function(...) {
  lines <<- c(lines, sprintf(...))
  message(utils::tail(lines, 1))
}

# 1 ---------------------------------------------------------------------------
c1 <- q("
  SELECT nr.watershed_group_code AS wsg, count(*)::int AS n,
         count(*) FILTER (WHERE nr.linear_feature_id IS NULL)::int AS n_null,
         count(*) FILTER (WHERE nr.linear_feature_id IS DISTINCT FROM st.linear_feature_id)::int AS n_differ
    FROM fresh_pin481_after.streams_near_river nr
    LEFT JOIN fresh_pin481_after.streams st
      ON st.id_segment = nr.id_segment
     AND st.watershed_group_code = nr.watershed_group_code
   GROUP BY 1 ORDER BY 1")
stopifnot(nrow(c1) > 0L, sum(c1$n) > 0L, all(c1$n_null == 0L), all(c1$n_differ == 0L))
say("1. fresh_pin481_after.streams_near_river: %s rows, none NULL, every one equal to streams.linear_feature_id",
    paste(sprintf("%s %d", c1$wsg, c1$n), collapse = ", "))

# 2 ---------------------------------------------------------------------------
copy <- "fresh_pin481_backfill"
ex(sprintf("DROP SCHEMA IF EXISTS %s CASCADE", copy))
ex(sprintf("CREATE SCHEMA %s", copy))
before_cols <- q("SELECT column_name FROM information_schema.columns
                   WHERE table_schema = 'fresh_pin481_before'
                     AND table_name = 'streams_near_river'")$column_name
stopifnot(!"linear_feature_id" %in% before_cols)
for (tb in c("streams", "streams_near_river")) {
  ex(sprintf("CREATE TABLE %s.%s AS SELECT * FROM fresh_pin481_before.%s", copy, tb, tb))
}
cfg <- lnk_config("default")
cfg$pipeline$schema <- copy
suppressMessages(lnk_persist_init(conn, cfg, species = cfg$species))
c2 <- q(sprintf("
  SELECT count(*)::int AS n_after,
         count(c.*)::int AS n_copy,
         count(*) FILTER (WHERE c.linear_feature_id IS DISTINCT FROM a.linear_feature_id)::int AS n_differ
    FROM fresh_pin481_after.streams_near_river a
    FULL JOIN %s.streams_near_river c
      ON c.id_segment = a.id_segment AND c.watershed_group_code = a.watershed_group_code
     AND c.measure = a.measure AND c.threshold = a.threshold
     AND c.distance_max = a.distance_max", copy))
# Dropped here, not by on.exit(), which never fires at a script's top level.
ex(sprintf("DROP SCHEMA %s CASCADE", copy))
stopifnot(c2$n_after > 0L, c2$n_after == c2$n_copy, c2$n_differ == 0L)
say(paste("2. lnk_persist_init() on a copy of the 0.52.0 build filled linear_feature_id",
          "on %d rows, equal to fresh 0.55.1's on every row"),
    c2$n_copy)

# 3 ---------------------------------------------------------------------------
loaded <- lnk_load_overrides(lnk_config("default"))
cfg3 <- lnk_config("default")
calls <- c(`TRUE` = 0L, `FALSE` = 0L)
run <- function(lfid) {
  orig <- fresh::frs_habitat_predicates
  testthat::with_mocked_bindings(
    frs_habitat_predicates = function(sp_params, model = "cw",
                                      near_river_table = NULL,
                                      near_river_lfid = NULL) {
      if (!is.null(near_river_table)) {
        calls[[as.character(lfid)]] <<- calls[[as.character(lfid)]] + 1L
      }
      orig(sp_params, model = model, near_river_table = near_river_table,
           near_river_lfid = if (is.null(near_river_table)) NULL else lfid)
    },
    .package = "fresh",
    suppressMessages(lnk_habitat_validate(conn, aoi = "ADMS", cfg = cfg3,
      loaded = loaded, species = c("CH", "CO", "BT"),
      schema = "fresh_pin481_after")))
}
v_true <- run(TRUE)
v_false <- run(FALSE)
# Both runs went through the mock with the near-river table: an identical
# pair from a mock never reached would prove nothing.
stopifnot(all(calls > 0L), identical(v_true, v_false))
o <- v_true$observations
nr_seg <- q("SELECT DISTINCT id_segment FROM fresh_pin481_after.streams_near_river
              WHERE watershed_group_code = 'ADMS'")$id_segment
on_nr <- sum(o$id_segment %in% nr_seg, na.rm = TRUE)
stopifnot(on_nr > 0L)
say(paste("3. lnk_habitat_validate() on ADMS (CH, CO, BT): identical with near_river_lfid",
          "TRUE and FALSE (%d and %d predicate builds on the near-river table);",
          "%d observations, %d on near-river segments"),
    calls[["TRUE"]], calls[["FALSE"]], nrow(o), on_nr)

writeLines(c(sprintf("# verify.R, %s UTC, link %s, fresh %s", format(Sys.time(), tz = "UTC"),
                     system2("git", c("rev-parse", "--short=8", "HEAD"), stdout = TRUE),
                     as.character(utils::packageVersion("fresh"))), "", lines),
           file.path(dir, "verify.txt"))
