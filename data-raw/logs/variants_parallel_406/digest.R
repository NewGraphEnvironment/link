#!/usr/bin/env Rscript
# digest.R — md5 of every table a variants build leaves, per group (link#406).
#
#   Rscript data-raw/logs/variants_parallel_406/digest.R <out.csv> \
#     [--prefix=score404_] [--variant=bt_rear_wet_p10] [--species=bt] \
#     [--wsgs=REVL,ELKR,...]
#
# One row per schema x table x group: the variant schema's persisted streams,
# streams_access and streams_habitat_<species>, each group's working
# streams_habitat (what the last pass classified), and, as the control the
# comparison must be able to tell apart, the base schema's
# streams_habitat_<species>. Rows are ordered by their key inside the md5, so
# the digest reads the content, not the physical order.
args <- commandArgs(TRUE)
opt <- function(name, default) {
  a <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(a) == 0L) default else sub(paste0("^--", name, "="), "", a[length(a)])
}
out <- args[!startsWith(args, "--")][1]
if (is.na(out)) stop("usage: digest.R <out.csv> [--prefix=] [--variant=] [--species=] [--wsgs=]")
prefix <- opt("prefix", "score404_")
variant <- opt("variant", "bt_rear_wet_p10")
sp <- tolower(opt("species", "bt"))
wsgs <- strsplit(opt("wsgs", "REVL,ELKR,KOTR,UARL,MURR,UBTN,LHAF,PARS,KOTL"), ",")[[1]]
stopifnot(grepl("^[a-z][a-z0-9_]*_$", prefix), grepl("^[a-z][a-z0-9_]*$", variant),
          grepl("^[a-z]{2,3}$", sp), all(grepl("^[A-Z]{4}$", wsgs)))
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")
sch_v <- paste0(prefix, variant)
sch_b <- paste0(prefix, "default")
hab <- paste0("streams_habitat_", sp)
persisted <- function(schema, table, w) {
  DBI::dbGetQuery(conn, sprintf(
    "SELECT md5(string_agg(t::text, '|' ORDER BY t.id_segment)),
            count(*)::int AS n
       FROM (SELECT * FROM %s.%s WHERE watershed_group_code = $1) t",
    schema, table), params = list(w))
}
rows <- list()
for (w in wsgs) {
  for (tb in c("streams", "streams_access", hab)) {
    d <- persisted(sch_v, tb, w)
    rows[[length(rows) + 1L]] <- data.frame(schema = sch_v, table = tb,
      watershed_group_code = w, md5 = d[[1]], n = d$n)
  }
  d <- persisted(sch_b, hab, w)
  rows[[length(rows) + 1L]] <- data.frame(schema = sch_b, table = hab,
    watershed_group_code = w, md5 = d[[1]], n = d$n)
  wk <- paste0("working_", prefix, tolower(w))
  d <- DBI::dbGetQuery(conn, sprintf(
    "SELECT md5(string_agg(t::text, '|' ORDER BY id_segment, species_code)),
            count(*)::int AS n FROM %s.streams_habitat t", wk))
  rows[[length(rows) + 1L]] <- data.frame(schema = wk, table = "streams_habitat",
    watershed_group_code = w, md5 = d[[1]], n = d$n)
}
res <- do.call(rbind, rows)
if (anyNA(res$md5)) stop("a table holds no rows for a group: ",
                         paste(unique(res$watershed_group_code[is.na(res$md5)]), collapse = ","))
utils::write.csv(res, out, row.names = FALSE)
DBI::dbDisconnect(conn)
cat(sprintf("%d digests to %s\n", nrow(res), out))
