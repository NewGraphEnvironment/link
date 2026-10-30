# Observed / unobserved accessible km (#403) for #396's five groups, in the
# two `default` builds #396 made (before and after `top_per_species`), and a
# parity reading of the split for BULK and PARS against bcfishpass.
#
# Run from a worktree of link at the commit to be measured, so load_all()
# loads that commit, with the database host in the environment:
#
#   git worktree add <wt> <sha>
#   cd <wt> && LNK_DB_HOST=<host> Rscript <link>/data-raw/logs/known_suspected_403/rollup.R
#
# Writes rollup.csv, parity_bcfp.csv and stamp.txt beside this script.
pkgload::load_all(quiet = TRUE)
# nolint start: indentation_linter
host <- Sys.getenv("LNK_DB_HOST")
if (!nzchar(host)) stop("set LNK_DB_HOST", call. = FALSE)
conn <- lnk_db_conn(dbname = "fwapg", host = host, port = 5432L,
                    user = "postgres", password = "postgres")
f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
dir_out <- dirname(normalizePath(sub("^--file=", "", f)))
sha <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE)
dirty <- length(system2("git", c("status", "--porcelain", "--", "R"),
                        stdout = TRUE)) > 0L
if (dirty) stop("the worktree's R/ is dirty", call. = FALSE)

wsgs <- c("BULK", "ELKR", "LKEL", "PARS", "UPCE")
schemas <- c("zz396_default_pre", "zz396_default_post")
ident_tol <- 0.0101

# Species a group's access build models: an access_<sp> column with a habitat
# table, and not -9 (absent) on every segment of the group.
modelled <- function(schema, wsg) {
  cols <- DBI::dbGetQuery(conn, sprintf(
    "SELECT column_name FROM information_schema.columns
      WHERE table_schema = '%s' AND table_name = 'streams_access'
        AND column_name LIKE 'access\\_%%'", schema))$column_name
  sp <- sub("^access_", "", cols)
  hab <- DBI::dbGetQuery(conn, sprintf(
    "SELECT table_name FROM information_schema.tables
      WHERE table_schema = '%s' AND table_name LIKE 'streams\\_habitat\\_%%'",
    schema))$table_name
  sp <- sp[paste0("streams_habitat_", sp) %in% hab]
  keep <- vapply(sp, function(s) {
    DBI::dbGetQuery(conn, sprintf(
      "SELECT EXISTS (SELECT 1 FROM %s.streams_access
        WHERE watershed_group_code = '%s' AND access_%s <> -9) AS e",
      schema, wsg, s))$e
  }, logical(1))
  toupper(sort(sp[keep]))
}

rows <- list()
for (sc in schemas) for (w in wsgs) {
  sp <- modelled(sc, w)
  if (!length(sp)) stop(sc, " ", w, ": no modelled species", call. = FALSE)
  r <- lnk_rollup_wsg(conn, aoi = w, species = sp, schema = sc)
  if (nrow(r) != length(sp)) stop(sc, " ", w, ": a species has no rows",
                                  call. = FALSE)
  rows[[length(rows) + 1L]] <- cbind(schema = sc, r)
}
out <- do.call(rbind, rows)
out$share_observed <- round(out$accessible_observed_km / out$accessible_km, 4)

# The identity on every row where access is built and some is accessible.
has <- !is.na(out$accessible_km)
gap <- abs(out$accessible_observed_km + out$accessible_unobserved_km -
             out$accessible_km)
if (any(gap[has] > ident_tol)) stop("identity fails on ", sum(gap[has] > ident_tol),
                                    " rows", call. = FALSE)
if (any(!is.na(out$accessible_observed_km[!has])) ||
      any(!is.na(out$accessible_unobserved_km[!has]))) {
  stop("a part is not NA where accessible_km is", call. = FALSE)
}
message(sum(has), " rows hold the identity (max gap ", max(gap[has]), " km); ",
        sum(!has), " rows have no accessible km (all three NA)")
utils::write.csv(out, file.path(dir_out, "rollup.csv"), row.names = FALSE,
                 na = "")

# Parity reading: link's `bcfishpass` builds (persisted in `fresh`) against
# the reference view, by access code. The view sums every segment; the
# rollup inner-joins habitat, which holds a row per segment.
ref_sp <- c("BT", "CH", "CM", "CO", "PK", "SK", "ST", "WCT")
par <- list()
for (w in c("BULK", "PARS")) {
  sp <- intersect(modelled("fresh", w), ref_sp)
  lk <- lnk_rollup_wsg(conn, aoi = w, species = sp, schema = "fresh")
  for (s in sp) {
    bc <- DBI::dbGetQuery(conn, sprintf(
      "SELECT round(sum(length_metre) FILTER (WHERE access_%1$s IN (1, 2))::numeric / 1000, 2) AS acc,
              round(sum(length_metre) FILTER (WHERE access_%1$s = 2)::numeric / 1000, 2) AS obs,
              round(sum(length_metre) FILTER (WHERE access_%1$s = 1)::numeric / 1000, 2) AS unobs
         FROM fresh.streams_vw_bcfp WHERE watershed_group_code = '%2$s'",
      tolower(s), w))
    l <- lk[lk$species == s, ]
    par[[length(par) + 1L]] <- data.frame(
      wsg = w, species = s,
      link_accessible_km = l$accessible_km,
      bcfp_accessible_km = as.numeric(bc$acc),
      link_observed_km = l$accessible_observed_km,
      bcfp_observed_km = as.numeric(bc$obs),
      link_unobserved_km = l$accessible_unobserved_km,
      bcfp_unobserved_km = as.numeric(bc$unobs))
  }
}
par <- do.call(rbind, par)
par$observed_diff_km <- par$link_observed_km - par$bcfp_observed_km
par$accessible_diff_km <- par$link_accessible_km - par$bcfp_accessible_km
utils::write.csv(par, file.path(dir_out, "parity_bcfp.csv"), row.names = FALSE,
                 na = "")

logs <- do.call(rbind, lapply(c(schemas, "fresh"), function(sc) {
  DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT ON (watershed_group_code) '%1$s' AS schema,
            watershed_group_code, link_version, link_sha, link_dirty,
            fresh_version, config_name, config_hash, date_end
       FROM %1$s.log WHERE watershed_group_code IN (%2$s)
      ORDER BY watershed_group_code, date_start DESC", sc,
    paste0("'", if (sc == "fresh") c("BULK", "PARS") else wsgs, "'",
           collapse = ", ")))
}))
writeLines(c(
  paste("link commit run:", sha),
  paste("run at (UTC):", format(Sys.time(), tz = "UTC")),
  "builds read (newest log row per group):",
  utils::capture.output(print(logs, row.names = FALSE))),
  file.path(dir_out, "stamp.txt"))
DBI::dbDisconnect(conn)
# nolint end: indentation_linter
