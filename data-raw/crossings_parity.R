# Link's crossings against bcfishpass's crossings table (link#232).
#
#   LNK_REF_PGHOST=... LNK_REF_PGPORT=... LNK_REF_PGDATABASE=... \
#   LNK_REF_PGUSER=... LNK_REF_PGPASSWORD=... \
#   Rscript data-raw/crossings_parity.R --wsgs=ADMS,BULK --out=<dir>
#
# Link's side is each group's working schema (`working_<wsg>.crossings`, left
# by `data-raw/wsg_run_one.R`, which keeps its working schema), on the local
# docker fwapg. bcfishpass's side is `bcfishpass.crossings` on the reference
# database, whose connection comes only from the LNK_REF_PG* variables. Joined
# on `aggregated_crossings_id`, which both build the same way (a PSCIS id, a
# CABD dam id, or a modelled crossing id plus 1e9).
#
# Writes to <dir>:
#   crossings_parity_summary.csv  per group and crossing_source: rows on each
#     side and on both, barrier_status agreeing, blue_line_key agreeing, and
#     measures within 1 m;
#   crossings_parity_rows.csv     every crossing found on one side only or
#     disagreeing on status, stream or measure;
#   crossings_parity_stamp.csv    link's HEAD and dirty flag, the reference's
#     newest bcfishpass.log row, and when this ran.
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) {
  a <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(a) != 1L) stop("--", name, "= is required", call. = FALSE)
  sub(paste0("^--", name, "="), "", a)
}
wsgs <- toupper(strsplit(opt("wsgs"), ",", fixed = TRUE)[[1]])
stopifnot(length(wsgs) > 0L, all(grepl("^[A-Z]{3,5}$", wsgs)))
out <- opt("out")
dir.create(out, showWarnings = FALSE, recursive = TRUE)

env <- function(k) {
  v <- Sys.getenv(k)
  if (!nzchar(v)) stop(k, " is not set", call. = FALSE)
  v
}
ref <- DBI::dbConnect(RPostgres::Postgres(), host = env("LNK_REF_PGHOST"),
                      port = as.integer(env("LNK_REF_PGPORT")),
                      dbname = env("LNK_REF_PGDATABASE"),
                      user = env("LNK_REF_PGUSER"),
                      password = env("LNK_REF_PGPASSWORD"))
lnk <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                      port = 5432L, user = "postgres", password = "postgres")

cols <- c("aggregated_crossings_id", "crossing_source", "barrier_status",
          "blue_line_key", "downstream_route_measure", "watershed_group_code")
num64 <- function(d) {
  d[] <- lapply(d, function(x) if (inherits(x, "integer64")) as.numeric(x) else x)
  d
}

rows <- list()
summ <- list()
for (w in wsgs) {
  s <- paste0("working_", tolower(w))
  l <- num64(DBI::dbGetQuery(lnk, sprintf(
    "SELECT %s FROM %s.crossings WHERE watershed_group_code = $1",
    paste(cols, collapse = ", "), s), params = list(w)))
  r <- num64(DBI::dbGetQuery(ref, sprintf(
    "SELECT %s FROM bcfishpass.crossings WHERE watershed_group_code = $1",
    paste(cols, collapse = ", ")), params = list(w)))
  l$aggregated_crossings_id <- as.character(l$aggregated_crossings_id)
  r$aggregated_crossings_id <- as.character(r$aggregated_crossings_id)
  m <- merge(l, r, by = "aggregated_crossings_id", all = TRUE,
             suffixes = c("_link", "_bcfp"))
  m$wsg <- w
  m$source <- ifelse(is.na(m$crossing_source_link), m$crossing_source_bcfp,
                     m$crossing_source_link)
  both <- !is.na(m$crossing_source_link) & !is.na(m$crossing_source_bcfp)
  m$side <- ifelse(both, "both", ifelse(is.na(m$crossing_source_bcfp), "link_only", "bcfp_only"))
  m$status_agree <- both & m$barrier_status_link == m$barrier_status_bcfp
  m$stream_agree <- both & m$blue_line_key_link == m$blue_line_key_bcfp
  m$measure_diff_m <- ifelse(m$stream_agree,
                             abs(m$downstream_route_measure_link - m$downstream_route_measure_bcfp),
                             NA_real_)
  m$measure_within_1m <- m$stream_agree & m$measure_diff_m <= 1
  summ[[w]] <- do.call(rbind, lapply(split(m, m$source), function(g) {
    b <- g$side == "both"
    data.frame(wsg = w, crossing_source = g$source[1],
               n_link = sum(g$side != "bcfp_only"), n_bcfp = sum(g$side != "link_only"),
               n_both = sum(b), n_link_only = sum(g$side == "link_only"),
               n_bcfp_only = sum(g$side == "bcfp_only"),
               n_status_agree = sum(g$status_agree), n_stream_agree = sum(g$stream_agree),
               n_measure_within_1m = sum(g$measure_within_1m),
               max_measure_diff_m = if (any(g$stream_agree))
                 round(max(g$measure_diff_m, na.rm = TRUE), 3) else NA_real_)
  }))
  bad <- m$side != "both" | !m$status_agree | !m$stream_agree | !m$measure_within_1m
  rows[[w]] <- m[bad, c("wsg", "aggregated_crossings_id", "source", "side",
                        "barrier_status_link", "barrier_status_bcfp",
                        "blue_line_key_link", "blue_line_key_bcfp",
                        "downstream_route_measure_link", "downstream_route_measure_bcfp",
                        "measure_diff_m")]
}
summary <- do.call(rbind, summ)
rownames(summary) <- NULL
diffs <- do.call(rbind, rows)
diffs <- diffs[order(diffs$wsg, diffs$source, diffs$side, diffs$aggregated_crossings_id,
                     method = "radix"), ]

stamp <- data.frame(
  link_sha = system2("git", c("rev-parse", "--short=8", "HEAD"), stdout = TRUE),
  link_dirty = length(system2("git", c("status", "--porcelain", "--untracked-files=no",
                                       "--", "R", "inst", "DESCRIPTION"), stdout = TRUE)) > 0L,
  num64(DBI::dbGetQuery(ref, "SELECT model_run_id, date_completed::text AS date_completed,
                                     model_version
                                FROM bcfishpass.log ORDER BY model_run_id DESC LIMIT 1")),
  run_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
DBI::dbDisconnect(ref)
DBI::dbDisconnect(lnk)

utils::write.csv(summary, file.path(out, "crossings_parity_summary.csv"), row.names = FALSE)
utils::write.csv(diffs, file.path(out, "crossings_parity_rows.csv"), row.names = FALSE)
utils::write.csv(stamp, file.path(out, "crossings_parity_stamp.csv"), row.names = FALSE)
print(summary)
print(stamp)
