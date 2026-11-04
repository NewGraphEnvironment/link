# prototype_check.R — #444 acceptance 2: on the four proof groups, does
# fresh_default.streams_parent give each full segment the parent #415's proof
# gave it (data-raw/logs/minimal_breaks_415/parent_<wsg>.csv.gz)?
#
#   Rscript data-raw/logs/streams_parent_444/prototype_check.R
#
# The proof's scratch schemas are gone, so the CSVs carry ids only. They are
# joined to the table on id_segment, which is sound when both builds cut the
# same: .lnk_pipeline_break_reassign_id() numbers segments in
# (blue_line_key, downstream_route_measure) order, so identical cuts give
# identical ids. The length guards prove it here rather than assume it: each
# CSV row's overlap_m + straddle_m must be the full segment's length in
# fresh_default.streams, and its length_minimal the length of the minimal
# segment it names in fresh_default_minimal.streams (the check
# knowledge's knw_parent_join() applies). The groups were built on amd64 cloud
# hosts and arm64 Macs, which #361 measured 3.7e-9 m apart, so lengths compare
# within 1e-3 m and gradients within 1e-6.
#
# Writes prototype_check.csv beside this script; stops on any mismatch.

wsgs <- c("BULK", "SETN", "MORK", "COTR")
here <- "data-raw/logs/streams_parent_444"
proto <- "data-raw/logs/minimal_breaks_415"
tol_len <- 1e-3
tol_grad <- 1e-6

conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")

check <- function(w) {
  csv <- utils::read.csv(gzfile(file.path(proto, sprintf("parent_%s.csv.gz", tolower(w)))))
  sql <- sprintf(
    "SELECT p.id_segment, p.id_segment_minimal, p.gradient_minimal, p.length_minimal,
            p.overlap_m, p.straddle_m, s.length_metre AS length_full
       FROM fresh_default.streams_parent p
       JOIN fresh_default.streams s USING (id_segment, watershed_group_code)
      WHERE p.watershed_group_code = '%s'",
    w
  )
  tbl <- DBI::dbGetQuery(conn, sql)
  lengths <- "SELECT id_segment, length_metre FROM %s.streams WHERE watershed_group_code = '%s'"
  full <- DBI::dbGetQuery(conn, sprintf(lengths, "fresh_default", w))
  mini <- DBI::dbGetQuery(conn, sprintf(lengths, "fresh_default_minimal", w))
  j <- merge(csv, tbl, by = "id_segment", suffixes = c("_csv", "_tbl"))
  csv_full_len <- full$length_metre[match(csv$id_segment, full$id_segment)]
  csv_min_len <- mini$length_metre[match(csv$id_segment_minimal, mini$id_segment)]
  off <- function(a, b, tol) sum(is.na(a) | is.na(b) | abs(a - b) > tol)
  data.frame(
    wsg = w,
    n_csv = nrow(csv),
    n_table = nrow(tbl),
    n_joined = nrow(j),
    n_csv_full_length_off = off(csv$overlap_m + csv$straddle_m, csv_full_len, tol_len),
    n_csv_minimal_length_off = off(csv$length_minimal, csv_min_len, tol_len),
    n_table_full_length_off = off(tbl$overlap_m + tbl$straddle_m, tbl$length_full, tol_len),
    n_id_minimal_differs = sum(j$id_segment_minimal_csv != j$id_segment_minimal_tbl),
    n_gradient_differs = off(j$gradient_minimal_csv, j$gradient_minimal_tbl, tol_grad),
    max_gradient_diff = max(abs(j$gradient_minimal_csv - j$gradient_minimal_tbl)),
    n_length_minimal_differs = off(j$length_minimal_csv, j$length_minimal_tbl, tol_len),
    n_overlap_differs = off(j$overlap_m_csv, j$overlap_m_tbl, tol_len),
    n_straddle_differs = off(j$straddle_m_csv, j$straddle_m_tbl, tol_len),
    max_length_diff = max(abs(c(j$length_minimal_csv - j$length_minimal_tbl,
                                j$overlap_m_csv - j$overlap_m_tbl,
                                j$straddle_m_csv - j$straddle_m_tbl))),
    stringsAsFactors = FALSE
  )
}

res <- do.call(rbind, lapply(wsgs, check))
DBI::dbDisconnect(conn)
utils::write.csv(res, file.path(here, "prototype_check.csv"), row.names = FALSE)
print(res)
bad <- res$n_table != res$n_csv | res$n_joined != res$n_csv |
  rowSums(res[, grep("^n_.*(off|differs)$", names(res))]) > 0
if (any(bad)) stop("the table differs from the prototype in ", paste(res$wsg[bad], collapse = ", "),
                   call. = FALSE)
message("prototype_check: the table equals the prototype in ", paste(wsgs, collapse = ", "))
