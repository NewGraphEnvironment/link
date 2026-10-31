# Observed / unobserved accessible km before and after #401, and the parity
# reading of the split for BULK, PARS and UPCE against the reference view.
#
#   Rscript data-raw/logs/obs_province_401/rollup.R
#
# Reads zz401_{default,bcfishpass}_{pre,post} on the local docker fwapg (run.sh)
# and zz401_obs (build_obs.R). Writes rollup.csv, parity_bcfp.csv,
# parity_pieces.csv and segments.csv beside this script, and appends the
# builds' log rows to stamp.txt.
pkgload::load_all(quiet = TRUE)
# nolint start: indentation_linter, brace_linter
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
dir_out <- "data-raw/logs/obs_province_401"
q <- function(sql) DBI::dbGetQuery(conn, sql)
groups <- list(default = c("LKEL", "BULK", "UPCE", "PARS", "ELKR", "LNTH"),
               bcfishpass = c("BULK", "PARS", "UPCE"))
ident_tol <- 0.0101

# Species a group's access build models: an access_<sp> column with a habitat
# table, and not -9 (absent) on every segment of the group.
modelled <- function(schema, wsg) {
  cols <- q(sprintf(
    "SELECT column_name FROM information_schema.columns
      WHERE table_schema = '%s' AND table_name = 'streams_access'
        AND column_name LIKE 'access\\_%%'", schema))$column_name
  sp <- sub("^access_", "", cols)
  hab <- q(sprintf(
    "SELECT table_name FROM information_schema.tables
      WHERE table_schema = '%s' AND table_name LIKE 'streams\\_habitat\\_%%'",
    schema))$table_name
  sp <- sp[paste0("streams_habitat_", sp) %in% hab]
  keep <- vapply(sp, function(s) q(sprintf(
    "SELECT EXISTS (SELECT 1 FROM %s.streams_access
      WHERE watershed_group_code = '%s' AND access_%s <> -9) AS e",
    schema, wsg, s))$e, logical(1))
  toupper(sort(sp[keep]))
}

rows <- list()
segs <- list()
for (config in names(groups)) for (side in c("pre", "post")) {
  sc <- sprintf("zz401_%s_%s", config, side)
  for (w in groups[[config]]) {
    sp <- modelled(sc, w)
    if (!length(sp)) stop(sc, " ", w, ": no modelled species", call. = FALSE)
    r <- lnk_rollup_wsg(conn, aoi = w, species = sp, schema = sc)
    if (nrow(r) != length(sp)) stop(sc, " ", w, ": a species has no rows",
                                    call. = FALSE)
    rows[[length(rows) + 1L]] <- cbind(config = config, side = side, r)
    segs[[length(segs) + 1L]] <- data.frame(
      config = config, side = side, wsg = w,
      n_segments = q(sprintf("SELECT count(*) AS n FROM %s.streams
                               WHERE watershed_group_code = '%s'", sc, w))$n)
  }
}
out <- do.call(rbind, rows)
out$share_observed <- round(out$accessible_observed_km / out$accessible_km, 4)
has <- !is.na(out$accessible_km)
gap <- abs(out$accessible_observed_km + out$accessible_unobserved_km -
             out$accessible_km)
if (any(gap[has] > ident_tol)) stop("identity fails on ", sum(gap[has] > ident_tol),
                                    " rows", call. = FALSE)
utils::write.csv(out, file.path(dir_out, "rollup.csv"), row.names = FALSE,
                 na = "")
segs <- do.call(rbind, segs)
segs <- stats::reshape(segs, idvar = c("config", "wsg"), timevar = "side",
                       direction = "wide")
segs$identical <- segs$n_segments.pre == segs$n_segments.post
utils::write.csv(segs, file.path(dir_out, "segments.csv"), row.names = FALSE)
if (!all(segs$identical)) stop("segment counts differ between pre and post",
                               call. = FALSE)

# Parity: link's `bcfishpass` builds against the reference view, by code.
ref_sp <- c("BT", "CH", "CM", "CO", "PK", "SK", "ST", "WCT")
par <- list()
pieces <- list()
sql_pieces <- paste(readLines(file.path(dir_out, "parity_pieces.sql")),
                    collapse = "\n")
for (side in c("pre", "post")) {
  sc <- paste0("zz401_bcfishpass_", side)
  for (w in groups$bcfishpass) {
    sp <- intersect(modelled(sc, w), ref_sp)
    lk <- lnk_rollup_wsg(conn, aoi = w, species = sp, schema = sc)
    for (s in sp) {
      bc <- q(sprintf(
        "SELECT round(sum(length_metre) FILTER (WHERE access_%1$s IN (1, 2))::numeric / 1000, 2) AS acc,
                round(sum(length_metre) FILTER (WHERE access_%1$s = 2)::numeric / 1000, 2) AS obs,
                round(sum(length_metre) FILTER (WHERE access_%1$s = 1)::numeric / 1000, 2) AS unobs
           FROM fresh.streams_vw_bcfp WHERE watershed_group_code = '%2$s'",
        tolower(s), w))
      l <- lk[lk$species == s, ]
      par[[length(par) + 1L]] <- data.frame(
        build = side, wsg = w, species = s,
        link_accessible_km = l$accessible_km,
        bcfp_accessible_km = as.numeric(bc$acc),
        link_observed_km = l$accessible_observed_km,
        bcfp_observed_km = as.numeric(bc$obs),
        link_unobserved_km = l$accessible_unobserved_km,
        bcfp_unobserved_km = as.numeric(bc$unobs))
      sql <- gsub(":schema", sc, sql_pieces, fixed = TRUE)
      sql <- gsub(":wsg", w, sql, fixed = TRUE)
      sql <- gsub(":sp", tolower(s), sql, fixed = TRUE)
      # zz401_obs.bcfishpass_<WSG> is unquoted, so Postgres folds it to lower.
      p <- q(sql)
      if (nrow(p)) pieces[[length(pieces) + 1L]] <- cbind(build = side, p)
    }
  }
}
par <- do.call(rbind, par)
par$observed_diff_km <- par$link_observed_km - par$bcfp_observed_km
par$accessible_diff_km <- par$link_accessible_km - par$bcfp_accessible_km
par$observed_diff_km <- round(par$observed_diff_km, 2)
par$accessible_diff_km <- round(par$accessible_diff_km, 2)
utils::write.csv(par, file.path(dir_out, "parity_bcfp.csv"), row.names = FALSE,
                 na = "")
pieces <- if (length(pieces)) do.call(rbind, pieces) else data.frame()
utils::write.csv(pieces, file.path(dir_out, "parity_pieces.csv"),
                 row.names = FALSE)

logs <- do.call(rbind, lapply(names(groups), function(config) {
  do.call(rbind, lapply(c("pre", "post"), function(side) {
    sc <- sprintf("zz401_%s_%s", config, side)
    q(sprintf(
      "SELECT DISTINCT ON (watershed_group_code) '%1$s' AS schema,
              watershed_group_code AS wsg, link_version, left(link_sha, 8) AS link_sha,
              link_dirty, fresh_version, left(replace(config_hash, 'sha256:', ''), 8) AS config_hash,
              token_acc, date_end
         FROM %1$s.log ORDER BY watershed_group_code, date_start DESC", sc))
  }))
}))
cat(c("", "builds read (newest log row per group):",
      utils::capture.output(print(logs, row.names = FALSE))),
    file = file.path(dir_out, "stamp.txt"), sep = "\n", append = TRUE)
print(par)
print(pieces)
DBI::dbDisconnect(conn)
# nolint end
