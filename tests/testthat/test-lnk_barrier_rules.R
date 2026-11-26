# Which crossings are human-made barriers, as rules (link#341).

rules_df <- function(...) {
  rows <- list(...)
  do.call(rbind, lapply(rows, function(r) {
    d <- data.frame(rule_id = "status", applies_to = "*",
                    source_table = "crossings", column_name = "barrier_status",
                    operator = "in", value = "BARRIER;POTENTIAL", species = "*",
                    outcome = "barrier", date = "2026-11-24", source = "test",
                    notes = "", stringsAsFactors = FALSE)
    for (k in names(r)) d[[k]] <- r[[k]]
    d
  }))
}

test_that("a bundle with no rules table runs the built-in status rule", {
  r <- .lnk_barrier_rules(list(), list())
  expect_equal(r$rule_id, "status")
  expect_equal(r$value, "BARRIER;POTENTIAL")
})

test_that("default and bcfishpass ship the one reproducing row", {
  for (b in c("default", "bcfishpass", "default_tuned")) {
    cfg <- lnk_config(b)
    r <- .lnk_barrier_rules(cfg, lnk_load_overrides(cfg))
    expect_equal(nrow(r), 1L, info = b)
    for (k in c("rule_id", "applies_to", "source_table", "column_name", "operator",
                "value", "species", "outcome")) {
      expect_identical(r[[k]], .lnk_barrier_rules_builtin[[k]], info = paste(b, k))
    }
  }
})

test_that("a bad rule is refused at load", {
  ld <- function(...) list(parameters_barrier_rules = rules_df(list(...)))
  expect_error(.lnk_barrier_rules(list(), ld(source_table = "dams")),
               "unknown source_table: dams")
  expect_error(.lnk_barrier_rules(list(), ld(operator = "like")),
               "unknown operator: like")
  expect_error(.lnk_barrier_rules(list(), ld(species = "BT")),
               "species must be '\\*'")
  expect_error(.lnk_barrier_rules(list(), ld(outcome = "blocks")),
               "outcome must be 'barrier'")
  expect_error(.lnk_barrier_rules(list(), ld(applies_to = "PSCIS;FOO")),
               "applies_to")
  expect_error(.lnk_barrier_rules(list(), ld(value = "")),
               "a value is needed")
  expect_error(.lnk_barrier_rules(list(), ld(column_name = "x; DROP")),
               "column_name must be a lower-case name")
  expect_error(.lnk_barrier_rules(list(), ld(rule_id = "1x")), "rule_id")
  expect_error(.lnk_barrier_rules(list(), list(parameters_barrier_rules =
                                                 rules_df(list())[0, ])),
               "no rows")
})

# A scratch crossings table: three real PSCIS crossings (49: outlet drop 1.3 m,
# BARRIER; 433: no measurements, PASSABLE; 99: no drop, slope x length 260,
# POTENTIAL), a modelled crossing (POTENTIAL) and a dam (PASSABLE).
local_crossings <- function(conn, env = parent.frame()) {
  s <- paste0("zz_lnk_t341_", Sys.getpid(), "_", sample.int(1e6, 1))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", s))
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s)),
               envir = env)
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.crossings AS
     SELECT * FROM (VALUES
       ('49', 'PSCIS', 'BARRIER', 'ASSESSED'),
       ('433', 'PSCIS', 'PASSABLE', 'ASSESSED'),
       ('99', 'PSCIS', 'POTENTIAL', 'ASSESSED'),
       ('1000000001', 'MODELLED_CROSSINGS', 'POTENTIAL', NULL),
       ('d1', 'CABD', 'PASSABLE', NULL))
       v(aggregated_crossings_id, crossing_source, barrier_status, pscis_status)", s))
  DBI::dbExecute(conn, sprintf(
    "ALTER TABLE %1$s.crossings
       ADD COLUMN crossing_feature_type text, ADD COLUMN dam_name text,
       ADD COLUMN linear_feature_id bigint, ADD COLUMN blue_line_key integer,
       ADD COLUMN watershed_key integer,
       ADD COLUMN downstream_route_measure double precision,
       ADD COLUMN wscode_ltree ltree, ADD COLUMN localcode_ltree ltree,
       ADD COLUMN watershed_group_code text,
       ADD COLUMN geom geometry(PointZ, 3005)", s))
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.crossings SET blue_line_key = 1, watershed_key = 1,
            downstream_route_measure = 10, watershed_group_code = 'TEST',
            geom = ST_SetSRID(ST_MakePoint(1, 1, 0), 3005)", s))
  s
}

rule_ids <- function(conn, s) {
  d <- DBI::dbGetQuery(conn, sprintf(
    "SELECT aggregated_crossings_id AS id, barrier_rule_id AS r
       FROM %s.crossings ORDER BY 1", s))
  stats::setNames(d$r, d$id)
}

test_that("the reproducing row selects exactly the status set (DB)", {
  conn <- skip_if_no_db()
  s <- local_crossings(conn)
  .lnk_barrier_rules_apply(conn, s, .lnk_barrier_rules_builtin)
  r <- rule_ids(conn, s)
  expect_equal(names(r)[!is.na(r)], c("1000000001", "49", "99"))
  expect_true(all(r[!is.na(r)] == "status"))
})

test_that("AND within a rule_id, OR across, scoped by source, NULL only by is_null (DB)", {
  conn <- skip_if_no_db()
  s <- local_crossings(conn)
  rules <- rules_df(
    # measured: outlet drop over 0.6 m, or slope x length over 120, PSCIS only
    list(rule_id = "drop", applies_to = "PSCIS", source_table = "pscis_assessment",
         column_name = "outlet_drop", operator = ">", value = "0.6"),
    list(rule_id = "slope", applies_to = "PSCIS", source_table = "pscis_assessment",
         column_name = "slope_length", operator = ">", value = "120"),
    # unassessed in the view: keep the province's result (both rows of one rule)
    list(rule_id = "unmeasured", applies_to = "PSCIS",
         source_table = "pscis_assessment", column_name = "outlet_drop",
         operator = "is_null", value = NA),
    list(rule_id = "unmeasured", applies_to = "PSCIS"),
    # the rest keep the modelled or dam status
    list(rule_id = "status", applies_to = "MODELLED_CROSSINGS;CABD"))
  .lnk_barrier_rules_apply(conn, s, rules)
  r <- rule_ids(conn, s)
  expect_identical(r[["49"]], "drop")        # drop 1.3; slope x length 22
  expect_identical(r[["99"]], "slope")       # drop 0, slope x length 260
  expect_true(is.na(r[["433"]]))             # no measurements, and PASSABLE
  expect_identical(r[["1000000001"]], "status")
  expect_true(is.na(r[["d1"]]))              # a passable dam
  # order of rows means nothing, and a crossing matching two rules names both
  both <- rules_df(
    list(rule_id = "zz", applies_to = "PSCIS", source_table = "pscis_assessment",
         column_name = "outlet_drop", operator = ">=", value = "1"),
    list(rule_id = "aa"))
  .lnk_barrier_rules_apply(conn, s, both[2:1, ])
  r1 <- rule_ids(conn, s)
  .lnk_barrier_rules_apply(conn, s, both)
  expect_identical(rule_ids(conn, s), r1)
  expect_identical(r1[["49"]], "aa;zz")
})

test_that("a rule cannot reach a column its source lacks, nor inject SQL (DB)", {
  conn <- skip_if_no_db()
  s <- local_crossings(conn)
  expect_error(.lnk_barrier_rules_apply(conn, s, rules_df(list(column_name = "nope"))),
               "crossings has no column nope")
  expect_error(.lnk_barrier_rules_apply(conn, s, rules_df(list(
    source_table = "pscis_assessment", column_name = "outlet_drop", operator = ">",
    value = "0; DROP TABLE x"))), "not a number")
  # a text value is quoted, so it is compared, never run
  .lnk_barrier_rules_apply(conn, s, rules_df(list(
    operator = "=", value = "BARRIER'; DROP TABLE crossings; --")))
  expect_true(all(is.na(rule_ids(conn, s))))
})

test_that("a non-reproducing rule file moves the four barrier sets alike (DB)", {
  conn <- skip_if_no_db()
  s <- local_crossings(conn)
  # Only crossing 49 is a barrier under this file; under status 49, 99 and the
  # modelled crossing are.
  .lnk_barrier_rules_apply(conn, s, rules_df(list(
    rule_id = "drop", applies_to = "PSCIS", source_table = "pscis_assessment",
    column_name = "outlet_drop", operator = ">", value = "0.6")))
  lnk_barriers_emit(conn, s)
  ids <- function(t, col) DBI::dbGetQuery(conn, sprintf(
    "SELECT %s AS id FROM %s.%s ORDER BY 1", col, s, t))$id
  expect_equal(ids("barriers_anthropogenic", "barriers_anthropogenic_id"), "49")
  expect_equal(ids("barriers_pscis", "barriers_pscis_id"), "49")
  expect_equal(ids("barriers_dams", "barriers_dams_id"), character(0))
  # unify's anthropogenic source reads the same predicate
  expect_identical(.lnk_sql_barrier_selected(conn, s),
                   "barrier_rule_id IS NOT NULL")
})

test_that("a caller's crossings with no barrier_rule_id falls back to status (DB)", {
  conn <- skip_if_no_db()
  s <- local_crossings(conn)
  expect_identical(.lnk_sql_barrier_selected(conn, s, alias = "c"),
                   "c.barrier_status IN ('BARRIER', 'POTENTIAL')")
  lnk_barriers_emit(conn, s)
  expect_equal(nrow(DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM %s.barriers_anthropogenic", s))), 3L)
})

test_that("a pscis_assessment row must be scoped to PSCIS (round 1)", {
  ld <- list(parameters_barrier_rules = rules_df(list(
    source_table = "pscis_assessment", column_name = "outlet_drop",
    operator = "is_null", value = NA, applies_to = "*")))
  expect_error(.lnk_barrier_rules(list(), ld), "must have applies_to PSCIS")
  ld$parameters_barrier_rules$applies_to <- "PSCIS;CABD"
  expect_error(.lnk_barrier_rules(list(), ld), "must have applies_to PSCIS")
  ld$parameters_barrier_rules$applies_to <- "PSCIS"
  expect_no_error(.lnk_barrier_rules(list(), ld))
})
