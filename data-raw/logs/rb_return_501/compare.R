# Phase 5 of link#501: compare the three-state builds (build.sh) group by group.
#
#   Rscript data-raw/logs/rb_return_501/compare.R
#
# Writes beside it:
#   km.csv        per state, group and species: segments, accessible km by code
#                 (1, 2), spawning and rearing km
#   same_seg.csv  per state pair, group and species: segments identical in both
#                 states (line, start and length to the millimetre) whose access
#                 code, spawning or rearing differs. Re-segmentation cannot
#                 explain a difference there.
#   lifts.csv     per state and group: RB lifts, and those resting on records
#                 coded ST, SST or WST
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
dir_out <- file.path("data-raw", "logs", "rb_return_501")
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
q <- function(sql) DBI::dbGetQuery(conn, sql)
states <- c("main", "paused", "ship")
wsgs <- c("LKEL", "GRNL", "NBNK")
schema <- function(s) paste0("fresh_rb501_", s)

seg <- function(s, w) {
  sc <- schema(s)
  sp <- sub("^streams_habitat_", "", q(sprintf(
    "SELECT table_name FROM information_schema.tables
     WHERE table_schema = '%s' AND table_name LIKE 'streams_habitat\\_%%'
       AND table_type = 'BASE TABLE'", sc))$table_name)
  acc_cols <- q(sprintf(
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = '%s' AND table_name = 'streams_access'
       AND column_name LIKE 'access\\_%%'", sc))$column_name
  base <- q(sprintf(
    "SELECT s.id_segment, s.blue_line_key,
            round(s.downstream_route_measure::numeric, 3) AS drm,
            round(s.length_metre::numeric, 3) AS len, %s
     FROM %s.streams s
     LEFT JOIN %s.streams_access a
       ON a.id_segment = s.id_segment
      AND a.watershed_group_code = s.watershed_group_code
     WHERE s.watershed_group_code = '%s'",
    paste0("a.", acc_cols, collapse = ", "), sc, sc, w))
  for (x in sp) {
    h <- q(sprintf(
      "SELECT id_segment, coalesce(spawning, false) AS spawning_%s,
              coalesce(rearing, false) AS rearing_%s
       FROM %s.streams_habitat_%s WHERE watershed_group_code = '%s'",
      x, x, sc, x, w))
    base <- merge(base, h, by = "id_segment", all.x = TRUE)
  }
  base
}

d <- list()
km <- list()
for (s in states) for (w in wsgs) {
  x <- seg(s, w)
  d[[paste(s, w)]] <- x
  sps <- sub("^access_", "", grep("^access_", names(x), value = TRUE))
  for (sp in sps) {
    a <- x[[paste0("access_", sp)]]
    sw <- x[[paste0("spawning_", sp)]] %||% rep(NA, nrow(x))
    rr <- x[[paste0("rearing_", sp)]] %||% rep(NA, nrow(x))
    km[[length(km) + 1L]] <- data.frame(
      state = s, wsg = w, species = sp, segments = nrow(x),
      access_1_km = round(sum(x$len[a %in% 1]) / 1000, 2),
      access_2_km = round(sum(x$len[a %in% 2]) / 1000, 2),
      spawning_km = round(sum(x$len[sw %in% TRUE]) / 1000, 2),
      rearing_km = round(sum(x$len[rr %in% TRUE]) / 1000, 2))
  }
}
km <- do.call(rbind, km)
utils::write.csv(km, file.path(dir_out, "km.csv"), row.names = FALSE)

ss <- list()
for (pair in list(c("main", "paused"), c("paused", "ship"))) for (w in wsgs) {
  a <- d[[paste(pair[1], w)]]
  b <- d[[paste(pair[2], w)]]
  m <- merge(a, b, by = c("blue_line_key", "drm", "len"),
             suffixes = c(".a", ".b"))
  cols <- intersect(setdiff(names(a), c("id_segment", "blue_line_key", "drm", "len")),
                    names(b))
  for (cc in cols) {
    va <- m[[paste0(cc, ".a")]]
    vb <- m[[paste0(cc, ".b")]]
    diff <- !((is.na(va) & is.na(vb)) | (!is.na(va) & !is.na(vb) & va == vb))
    ss[[length(ss) + 1L]] <- data.frame(
      from = pair[1], to = pair[2], wsg = w, column = cc,
      segments_a = nrow(a), segments_b = nrow(b), identical_segments = nrow(m),
      differ = sum(diff), differ_km = round(sum(m$len[diff]) / 1000, 3))
  }
}
ss <- do.call(rbind, ss)
utils::write.csv(ss, file.path(dir_out, "same_seg.csv"), row.names = FALSE)

lf <- do.call(rbind, lapply(states, function(s) {
  sc <- schema(s)
  has_ev <- nrow(q(sprintf(
    "SELECT 1 FROM information_schema.tables WHERE table_schema = '%s'
       AND table_name = 'barrier_override_evidence'", sc))) > 0
  do.call(rbind, lapply(wsgs, function(w) {
    n <- q(sprintf("SELECT count(*)::int AS n FROM %s.barrier_overrides
                    WHERE species_code = 'RB' AND watershed_group_code = '%s'",
                   sc, w))$n
    st <- if (has_ev) q(sprintf(
      "SELECT count(DISTINCT (blue_line_key, downstream_route_measure))::int AS n
       FROM %s.barrier_override_evidence
       WHERE species_code = 'RB' AND watershed_group_code = '%s'
         AND species_code_recorded IN ('ST', 'SST', 'WST')", sc, w))$n else NA
    data.frame(state = s, wsg = w, rb_lifts = n, rb_lifts_on_steelhead = st)
  }))
}))
utils::write.csv(lf, file.path(dir_out, "lifts.csv"), row.names = FALSE)
print(lf)
print(km[km$species %in% c("rb", "st", "bt"), ])
print(ss[ss$differ > 0, ])
DBI::dbDisconnect(conn)
