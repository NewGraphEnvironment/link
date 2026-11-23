# Rainbow trout and steelhead records, by code and by place (link#501, #497)
#
# Phase 1 of backlog move 16. Before rainbow trout (RB) comes back to the
# `default` bundle, this measures how its records sit against steelhead's: which
# RB records lie in water steelhead can reach, which ST records lie above a
# barrier steelhead cannot pass (likely rainbow), and what each way of telling
# the two apart would change. It judges nothing; the owner picks the rule.
#
# Options counted (task_plan.md, Open decision 1):
#   a  code alone: an RB record counts as RB, an ST record as ST.
#   b  one way: an ST record (code `ST` only) also counts as RB where RB is
#      marked present; an RB record never counts as ST.
#   c  by place: an ST record above an unlifted ST-blocking natural barrier
#      counts as RB instead of ST; an RB record in steelhead-reachable water of
#      a group where ST is present counts as neither.
#
# Reads, on local fwapg: bcfishobs.observations, FWA, and the persisted
# `<schema>.barriers` and `<schema>.barrier_overrides` of a province-wide
# `default` build. That build's lifts are its own record rule's (named in the
# stamp), not this branch's.
#
# Usage:
#   Rscript data-raw/rb_st_records_check.R --schema=fresh_default \
#     --out=data-raw/logs/rb_st_497
#
# Writes into --out: records.csv.gz (one row per RB/ST-coded record), groups.csv
# (classes and option counts per group), options.csv (province totals per
# option), independent.csv (the SQL check for three groups) and stamp.txt.

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit) == 0L) return(NA_character_)
  sub(paste0("^--", name, "="), "", hit[1])
}
schema <- arg("schema")
dir_out <- arg("out")
if (is.na(schema) || is.na(dir_out)) {
  stop("usage: rb_st_records_check.R --schema=<persist schema> --out=<dir>",
       call. = FALSE)
}
if (!grepl("^[a-z_][a-z0-9_]*$", schema)) stop("schema is not a plain name")

pkgload::load_all(quiet = TRUE)
dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config("default")
loaded <- lnk_load_overrides(cfg)
cat("config: default (link's own); schema:", schema, "\n")

q <- function(sql) DBI::dbGetQuery(conn, sql)
x <- function(sql) invisible(DBI::dbExecute(conn, sql))
t0 <- Sys.time()

# -- the build read -------------------------------------------------------------
build <- q(sprintf("
  SELECT run_uid, token_cut, token_acc, link_sha, count(*)::int AS n_groups,
         min(date_end) AS first_end, max(date_end) AS last_end
  FROM (SELECT DISTINCT ON (watershed_group_code) *
        FROM %s.log WHERE date_end IS NOT NULL
        ORDER BY watershed_group_code, date_end DESC) l
  GROUP BY 1, 2, 3, 4 ORDER BY n_groups DESC", schema))
print(build)

# -- presence, regions ------------------------------------------------------------
pres <- loaded$wsg_species_presence
pres$wsg <- toupper(trimws(pres$watershed_group_code))
rb_present <- pres$wsg[pres$rb %in% c("t", TRUE)]
st_present <- pres$wsg[pres$st %in% c("t", TRUE)]
regions <- utils::read.csv(system.file("extdata", "wsg_regions.csv",
                                       package = "link"),
                           colClasses = "character")

# -- record measures: the nearest ST-blocking natural barrier below ------------
st_pool <- loaded$parameters_fresh$observation_species[
  loaded$parameters_fresh$species_code == "ST"]
st_pool <- trimws(strsplit(st_pool, ";")[[1]])
aliases <- .lnk_record_aliases(loaded, pres$wsg)
zones <- data.frame(species_code = character(0), code50 = character(0))
excl <- .lnk_observation_exclusion_keys(loaded)
meas <- .lnk_presence_measures(
  conn, zones, species_barrier = "ST", lift_pools = list(ST = st_pool),
  sockeye_lakes = numeric(0), excl_keys = excl,
  incl_keys = .lnk_observation_release_include_keys(loaded),
  aliases = aliases, barrier_species = c(RB = "ST"))
cat("measures:", length(unique(meas$observation_key)), "records,", nrow(meas),
    "rows (one per record and species) in",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min\n")

# -- lifts and "any unlifted ST barrier below" -----------------------------------
# The nearest ST barrier below may be lifted for ST with another below it, so
# reachability asks for any unlifted ST-blocking natural barrier below. A lift
# sits within 1 m of its barrier (RUNBOOK §6d): match by line and a 1 m window.
codes <- c("RB", "ST", "SST", "WST", "RB/CT", "CT/RB", " RB")
lit <- function(v) paste0("'", gsub("'", "''", v), "'", collapse = ", ")
x("DROP TABLE IF EXISTS pg_temp.rs_rec")
x(sprintf("
  CREATE TEMP TABLE rs_rec AS
  SELECT o.observation_key, o.watershed_group_code, o.species_code AS code_raw,
         o.observation_date, o.source, o.waterbody_type,
         o.blue_line_key, o.downstream_route_measure, o.wscode, o.localcode
  FROM bcfishobs.observations o
  WHERE o.species_code IN (%s)", lit(codes)))
x("CREATE INDEX ON pg_temp.rs_rec USING gist (wscode)")
x("ANALYZE pg_temp.rs_rec")
x("DROP TABLE IF EXISTS pg_temp.rs_stlift")
x(sprintf("
  CREATE TEMP TABLE rs_stlift AS
  SELECT DISTINCT blue_line_key, downstream_route_measure
  FROM %s.barrier_overrides WHERE species_code = 'ST'", schema))
x("CREATE INDEX ON pg_temp.rs_stlift (blue_line_key, downstream_route_measure)")
x("ANALYZE pg_temp.rs_stlift")
x("DROP TABLE IF EXISTS pg_temp.rs_block")
x(sprintf("
  CREATE TEMP TABLE rs_block AS
  SELECT r.observation_key,
         EXISTS (
           SELECT 1 FROM %s.barriers b
           WHERE b.barrier_source IN ('FALLS', 'GRADIENT', 'USER_DEFINITE')
             AND 'ST' = ANY (b.blocks_species)
             AND b.wscode_ltree @> r.wscode
             AND whse_basemapping.fwa_downstream(
                   r.blue_line_key, r.downstream_route_measure, r.wscode, r.localcode,
                   b.blue_line_key, b.downstream_route_measure, b.wscode_ltree,
                   b.localcode_ltree)
             AND NOT EXISTS (
               SELECT 1 FROM pg_temp.rs_stlift l
               WHERE l.blue_line_key = b.blue_line_key
                 AND l.downstream_route_measure
                     BETWEEN b.downstream_route_measure - 1
                         AND b.downstream_route_measure + 1)) AS st_blocked
  FROM pg_temp.rs_rec r
  WHERE r.wscode IS NOT NULL", schema))
cat("blocked test done at",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min\n")

rec <- q("
  SELECT r.observation_key, r.watershed_group_code, r.code_raw,
         r.observation_date, split_part(r.source, ':', 1) AS source,
         r.waterbody_type, r.blue_line_key,
         r.downstream_route_measure AS drm, k.st_blocked
  FROM pg_temp.rs_rec r
  LEFT JOIN pg_temp.rs_block k USING (observation_key)")
# One row per record: an alias counting as two species (SST as ST and RB)
# has a measures row per species. Keep its ST row, the species the
# steelhead barrier test is about; both rows carry that barrier.
m <- .lnk_measures_per_record(meas, prefer = "ST")[
  , c("observation_key", "species_code", "counting", "yr", "elevation_m",
      "barrier_below", "major_drainage")]
names(m)[names(m) == "species_code"] <- "species_read"
rec <- merge(rec, m, by = "observation_key", all.x = TRUE)
stopifnot(!anyNA(rec$species_read), !anyDuplicated(rec$observation_key))
rec$wsg <- rec$watershed_group_code
rec$region <- regions$region[match(rec$wsg, regions$watershed_group_code)]
rec$subregion <- regions$subregion[match(rec$wsg, regions$watershed_group_code)]
rec$rb_present <- rec$wsg %in% rb_present
rec$st_present <- rec$wsg %in% st_present
rec$excluded <- rec$observation_key %in% excl
rec$dated <- !is.na(rec$observation_date)
rec$counting[is.na(rec$counting)] <- FALSE
rec <- rec[order(rec$wsg, rec$code_raw, rec$observation_key,
                 method = "radix"), ]

# -- classes ---------------------------------------------------------------------
# Every class is over records the pipeline would read (not excluded) with a
# watershed code; `st_blocked` NA (no code) falls outside every class.
is_rb <- rec$code_raw == "RB"
is_st <- rec$code_raw %in% c("ST", "SST", "WST")
use <- !rec$excluded & !is.na(rec$st_blocked)
rec$class <- NA_character_
rec$class[use & is_rb & !rec$st_blocked] <- "rb_reachable"
rec$class[use & is_rb & rec$st_blocked] <- "rb_above"
rec$class[use & is_st & rec$st_blocked] <- "st_above"
rec$class[use & is_st & !rec$st_blocked] <- "st_reachable"

# -- what counts as RB under each option -----------------------------------------
# The pipeline's record rule: excluded records out, the record's own group
# marks RB present, RB has no date floor (every record, undated included).
base <- !rec$excluded & rec$rb_present
rec$rb_a <- base & is_rb
rec$rb_b <- base & (is_rb | rec$code_raw == "ST")
rec$rb_c <- base & ((is_rb & !(rec$st_present & rec$st_blocked %in% FALSE)) |
                      (is_st & rec$st_blocked %in% TRUE))
gz <- gzfile(file.path(dir_out, "records.csv.gz"), "w")
utils::write.csv(rec, gz, row.names = FALSE, na = "")
close(gz)

# Top record per line per group, as the cuts read it.
top_key <- function(flag) {
  r <- rec[flag, c("wsg", "blue_line_key", "drm")]
  if (nrow(r) == 0L) return(character(0))
  a <- stats::aggregate(drm ~ wsg + blue_line_key, r, max)
  paste(a$wsg, a$blue_line_key, round(a$drm))
}
top_a <- top_key(rec$rb_a)
groups_top_moved <- function(flag) {
  t <- top_key(flag)
  d <- union(setdiff(t, top_a), setdiff(top_a, t))
  sort(unique(sub(" .*", "", d)))
}

# Presence check flags: a group with no RB cell and a counting record that
# would count as RB (1950 or later, not a release, not excluded).
pc <- !rec$excluded & rec$counting & !rec$rb_present
flag_a <- sort(unique(rec$wsg[pc & is_rb]))
flag_b <- sort(unique(rec$wsg[pc & (is_rb | rec$code_raw == "ST")]))
flag_c <- sort(unique(rec$wsg[pc & ((is_rb & !(rec$st_present &
                                               rec$st_blocked %in% FALSE)) |
                                      (is_st & rec$st_blocked %in% TRUE))]))

# -- RB lift positions each option would open -------------------------------------
# A natural barrier blocking RB in a group that marks RB present lifts on one
# dated record counting as RB above it (RB: threshold 1, no floor; an undated
# record never lifts). Records from every group count, each by its own group.
lifts <- rec[(rec$rb_a | rec$rb_b | rec$rb_c) & rec$dated,
             c("observation_key", "rb_a", "rb_b", "rb_c")]
DBI::dbWriteTable(conn, "rs_lift_rec", lifts, temporary = TRUE, overwrite = TRUE)
x("DROP TABLE IF EXISTS pg_temp.rs_lift")
x(sprintf("
  CREATE TEMP TABLE rs_lift AS
  SELECT b.blue_line_key, round(b.downstream_route_measure)::bigint AS m,
         bool_or(l.rb_a) AS a, bool_or(l.rb_b) AS b, bool_or(l.rb_c) AS c,
         min(b.watershed_group_code) AS wsg
  FROM pg_temp.rs_lift_rec l
  JOIN pg_temp.rs_rec r USING (observation_key)
  JOIN %s.barriers b
    ON b.barrier_source IN ('FALLS', 'GRADIENT', 'USER_DEFINITE')
   AND 'RB' = ANY (b.blocks_species)
   AND b.watershed_group_code IN (%s)
   AND b.wscode_ltree @> r.wscode
   AND whse_basemapping.fwa_downstream(
         r.blue_line_key, r.downstream_route_measure, r.wscode, r.localcode,
         b.blue_line_key, b.downstream_route_measure, b.wscode_ltree,
         b.localcode_ltree)
  GROUP BY 1, 2", schema, lit(rb_present)))
lift <- q("SELECT * FROM pg_temp.rs_lift")
cat("lift positions done at",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min\n")

# -- per group and province --------------------------------------------------------
cls <- c("rb_reachable", "rb_above", "st_above", "st_reachable")
g <- as.data.frame.matrix(table(factor(rec$wsg[!is.na(rec$class)],
                                       levels = sort(unique(rec$wsg))),
                                factor(rec$class[!is.na(rec$class)],
                                       levels = cls)))
g <- cbind(watershed_group_code = rownames(g), g)
rownames(g) <- NULL
for (o in c("a", "b", "c")) {
  f <- rec[[paste0("rb_", o)]]
  g[[paste0("n_rb_", o)]] <- as.integer(table(factor(rec$wsg[f],
                                                     levels = g$watershed_group_code)))
  g[[paste0("lifts_", o)]] <- as.integer(table(factor(lift$wsg[lift[[o]]],
                                                      levels = g$watershed_group_code)))
}
g$rb_present <- g$watershed_group_code %in% rb_present
g$st_present <- g$watershed_group_code %in% st_present
g$region <- regions$region[match(g$watershed_group_code, regions$watershed_group_code)]
g$top_moves_b <- g$watershed_group_code %in% groups_top_moved(rec$rb_b)
g$top_moves_c <- g$watershed_group_code %in% groups_top_moved(rec$rb_c)
g$new_flag_b <- g$watershed_group_code %in% setdiff(flag_b, flag_a)
g$new_flag_c <- g$watershed_group_code %in% setdiff(flag_c, flag_a)
utils::write.csv(g, file.path(dir_out, "groups.csv"), row.names = FALSE)

opt <- data.frame(
  option = c("a", "b", "c"),
  records_as_rb = c(sum(rec$rb_a), sum(rec$rb_b), sum(rec$rb_c)),
  undated_as_rb = c(sum(rec$rb_a & !rec$dated), sum(rec$rb_b & !rec$dated),
                    sum(rec$rb_c & !rec$dated)),
  st_records_as_rb = c(0L, sum(rec$rb_b & is_st), sum(rec$rb_c & is_st)),
  rb_lift_positions = c(sum(lift$a), sum(lift$b), sum(lift$c)),
  groups_top_moves = c(0L, length(groups_top_moved(rec$rb_b)),
                       length(groups_top_moved(rec$rb_c))),
  presence_flags_rb = c(length(flag_a), length(flag_b), length(flag_c)),
  new_presence_flags_rb = c(0L, length(setdiff(flag_b, flag_a)),
                            length(setdiff(flag_c, flag_a))))
utils::write.csv(opt, file.path(dir_out, "options.csv"), row.names = FALSE)
print(opt)
cls_tot <- table(rec$class, useNA = "ifany")
print(cls_tot)

# -- independent count for three groups ----------------------------------------
# From the barrier side: records with fwa_upstream of an unlifted ST-blocking
# natural barrier, against the record-side `st_blocked` above.
three <- c("BULK", "LFRA", "OKAN")
ind <- q(sprintf("
  WITH bar AS (
    SELECT DISTINCT b.blue_line_key, b.downstream_route_measure,
           b.wscode_ltree, b.localcode_ltree
    FROM %s.barriers b
    WHERE b.barrier_source IN ('FALLS', 'GRADIENT', 'USER_DEFINITE')
      AND 'ST' = ANY (b.blocks_species)
      AND NOT EXISTS (
        SELECT 1 FROM pg_temp.rs_stlift l
        WHERE l.blue_line_key = b.blue_line_key
          AND abs(l.downstream_route_measure - b.downstream_route_measure) <= 1))
  SELECT r.watershed_group_code AS wsg, r.code_raw,
         count(DISTINCT r.observation_key) FILTER (WHERE EXISTS (
           SELECT 1 FROM bar
           WHERE r.wscode <@ bar.wscode_ltree
             AND whse_basemapping.fwa_upstream(
                   bar.blue_line_key, bar.downstream_route_measure,
                   bar.wscode_ltree, bar.localcode_ltree,
                   r.blue_line_key, r.downstream_route_measure,
                   r.wscode, r.localcode)))::int AS n_above_sql
  FROM pg_temp.rs_rec r
  WHERE r.watershed_group_code IN (%s) AND r.wscode IS NOT NULL
    AND r.code_raw IN ('RB', 'ST')
  GROUP BY 1, 2", schema, lit(three)))
rr <- rec[rec$wsg %in% three & rec$code_raw %in% c("RB", "ST") &
            !is.na(rec$st_blocked), ]
r_side <- stats::aggregate(st_blocked ~ wsg + code_raw, rr, sum)
names(r_side)[3] <- "n_above_r"
ind <- merge(ind, r_side, by = c("wsg", "code_raw"), all = TRUE)
ind$agree <- ind$n_above_sql == ind$n_above_r
print(ind)
utils::write.csv(ind, file.path(dir_out, "independent.csv"), row.names = FALSE)
if (!all(ind$agree %in% TRUE)) stop("the two counts disagree")

# -- stamp ---------------------------------------------------------------------------
obs <- q("SELECT count(*)::bigint AS n, max(observation_date) AS newest
          FROM bcfishobs.observations")
st <- lnk_stamp(cfg, conn = conn, db_snapshot = FALSE)
writeLines(c(
  paste("date_utc:", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  paste("host:", Sys.info()[["nodename"]]),
  paste("schema:", schema),
  paste("build:", paste(utils::capture.output(print(build)), collapse = "\n")),
  paste("bcfishobs.observations rows:", format(obs$n), "newest:", obs$newest),
  paste("minutes:", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)),
  utils::capture.output(print(st))),
  file.path(dir_out, "stamp.txt"))
DBI::dbDisconnect(conn)
cat("done\n")
