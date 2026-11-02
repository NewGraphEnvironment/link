#!/usr/bin/env Rscript
# summary.R — #440: one row per group and species from a persist schema on the local
# fwapg: segments, km, barrier rows, accessible km (access 1 or 2), spawning and
# rearing km. Run on each host against its own schema, so builds on two machines can
# be set side by side without copying tables.
# Usage: Rscript summary.R <schema> <out.csv> <WSG>,<WSG>,...
a <- commandArgs(trailingOnly = TRUE)
stopifnot(length(a) == 3L, grepl("^[a-z_][a-z0-9_]*$", a[1]))
schema <- a[1]; out <- a[2]; wsgs <- toupper(strsplit(a[3], ",")[[1]])
stopifnot(all(grepl("^[A-Z]{4}$", wsgs)))
suppressPackageStartupMessages(library(DBI))
conn <- dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost", port = 5432L,
                  user = "postgres", password = "postgres")
q <- function(sql, ...) {
  r <- dbGetQuery(conn, sprintf(sql, ...))
  r[] <- lapply(r, function(v) if (inherits(v, "integer64")) as.numeric(v) else v)
  r
}
inl <- paste0("'", wsgs, "'", collapse = ", ")
spp <- sub("^streams_habitat_", "", q(
  "SELECT table_name t FROM information_schema.tables WHERE table_schema = '%s'
      AND table_name ~ '^streams_habitat_[a-z]+$'", schema)$t)
acc_cols <- q("SELECT column_name c FROM information_schema.columns
                WHERE table_schema = '%s' AND table_name = 'streams_access'", schema)$c
base <- q("SELECT s.watershed_group_code wsg, count(*) segments, sum(s.length_metre) / 1000 km
             FROM %s.streams s WHERE s.watershed_group_code IN (%s) GROUP BY 1", schema, inl)
bar <- q("SELECT watershed_group_code wsg, count(*) barrier_rows FROM %s.barriers
           WHERE watershed_group_code IN (%s) GROUP BY 1", schema, inl)
rows <- do.call(rbind, lapply(spp, function(sp) {
  if (!paste0("access_", sp) %in% acc_cols) return(NULL)
  d <- q("SELECT s.watershed_group_code wsg,
                 coalesce(sum(s.length_metre) FILTER (WHERE a.access_%2$s IN (1, 2)), 0) / 1000 accessible_km,
                 coalesce(sum(s.length_metre) FILTER (WHERE h.spawning), 0) / 1000 spawning_km,
                 coalesce(sum(s.length_metre) FILTER (WHERE h.rearing), 0) / 1000 rearing_km,
                 count(h.id_segment) habitat_rows
            FROM %1$s.streams s
            JOIN %1$s.streams_access a USING (id_segment, watershed_group_code)
            LEFT JOIN %1$s.streams_habitat_%2$s h USING (id_segment, watershed_group_code)
           WHERE s.watershed_group_code IN (%3$s) GROUP BY 1", schema, sp, inl)
  if (nrow(d)) cbind(species = toupper(sp), d) else NULL
}))
m <- merge(merge(base, bar, all.x = TRUE), rows, all.x = TRUE)
m$schema <- schema
write.csv(m[order(m$wsg, m$species), ], out, row.names = FALSE)
dbDisconnect(conn)
cat("wrote", nrow(m), "rows to", out, "\n")
