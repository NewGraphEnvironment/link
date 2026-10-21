#!/usr/bin/env Rscript
# query_mad_width_equivalent.R — the modelled channel width at which streams
# persisted in `fresh_default` reach a mean annual discharge, the reverse of
# query_width_mad_equivalent.R (link#364).
#
# `default`'s near-river rule for CH rearing (#364) finds "a river of at least
# 3 m3/s within 1 km". Under the `model` measure a `cw` group finds rivers by
# channel width, so the discharge is converted to the width streams carry at
# it, the same relation #307 used the other way.
#
# Method: query_width_mad_equivalent.R's segments and bins, over a ladder of
# widths:
#   - segments: `schema`.streams on stream edges (1000/1100/2000/2300) outside
#     any waterbody, with MODELLED channel_width;
#   - bins: channel_width within +/- 0.1 m of each width on the ladder;
#   - mad_m3s from the discharge source, segments with none left out;
#   - the converted width is the narrowest bin holding at least --min-n
#     segments (default 100) whose median mad_m3s is at or above the
#     discharge, floored to two significant figures (#307's rule). Wider than
#     about 20 m, stream lines outside a polygon with a modelled width get
#     rare (large rivers are polygons), and their bins' medians swing both
#     ways (first run: 19 m 3.63, 20 m 2.77 m3/s, n 157 and 187), so a rule
#     that asked the median to stay above the target in every wider bin read
#     noise and gave 44 m. The near-river ladder (#364 Phase 4) tests the
#     value.
#
#   Rscript data-raw/query_mad_width_equivalent.R \
#     [--mad=3] [--schema=fresh_default] [--discharge-source=fwapg|wet]
#     [--widths=2:60] [--min-n=100] [--out=data-raw/logs/wetland_door_364]
#
# Writes to --out:
#   mad_width_bins.csv        n, q25, median, q75 of mad_m3s per width bin
#   mad_width_conversion.csv  the discharge, the width it converts to
#   mad_width_stamp.txt       environment stamp
#
# Read-only against docker fwapg (:5432).

suppressPackageStartupMessages({
  pkgload::load_all(quiet = TRUE)
  library(DBI)
})

opt <- function(name, default = NULL) {
  a <- grep(paste0("^--", name, "="), commandArgs(trailingOnly = TRUE),
            value = TRUE)
  if (length(a) == 0L) return(default)
  sub(paste0("^--", name, "="), "", a[length(a)])
}

mad_target <- as.numeric(opt("mad", "3"))
schema <- opt("schema", "fresh_default")
widths <- eval(parse(text = opt("widths", "2:60")))
min_n <- as.integer(opt("min-n", "100"))
dir_out <- opt("out", file.path("data-raw", "logs", "wetland_door_364"))
src <- .lnk_discharge_source_check(opt("discharge-source", "fwapg"),
                                   "--discharge-source")
stopifnot(is.finite(mad_target), mad_target > 0, is.numeric(widths),
          length(widths) > 1L)
.lnk_validate_identifier(schema, "schema")
rel <- .lnk_discharge_rel(src)
fs::dir_create(dir_out)
half_bin <- 0.1
edges_stream <- c(1000L, 1100L, 2000L, 2300L)

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")

floor_signif2 <- function(x) {
  if (is.na(x) || x <= 0) return(if (is.na(x)) NA_real_ else 0)
  e <- 10^(floor(log10(x)) - 1)
  signif(floor(round(x / e, 9)) * e, 2)
}

bins <- dbGetQuery(conn, sprintf("
  WITH bins(w_bin) AS (VALUES %s)
  SELECT b.w_bin, count(*) AS n,
         percentile_cont(0.25) WITHIN GROUP (ORDER BY d.mad_m3s) AS q25,
         percentile_cont(0.50) WITHIN GROUP (ORDER BY d.mad_m3s) AS median,
         percentile_cont(0.75) WITHIN GROUP (ORDER BY d.mad_m3s) AS q75
    FROM bins b
    JOIN %s.streams s
      ON s.channel_width BETWEEN b.w_bin - %s AND b.w_bin + %s
    JOIN %s d
      ON d.linear_feature_id = s.linear_feature_id
   WHERE s.edge_type IN (%s)
     AND s.waterbody_key IS NULL
     AND s.channel_width_source = 'MODELLED'
     AND d.mad_m3s IS NOT NULL
   GROUP BY b.w_bin ORDER BY b.w_bin",
  paste0("(", widths, "::double precision)", collapse = ", "), schema,
  half_bin, half_bin, rel, paste(edges_stream, collapse = ", ")))
bins$n <- as.integer(bins$n)

hit <- bins$n >= min_n & bins$median >= mad_target
w_hit <- if (any(hit)) bins$w_bin[which(hit)[1]] else NA_real_
conversion <- data.frame(
  mad_m3s = mad_target, discharge_source = src, schema = schema,
  width_bin = w_hit,
  median_at_bin = if (is.na(w_hit)) NA_real_ else bins$median[bins$w_bin == w_hit],
  n_at_bin = if (is.na(w_hit)) NA_integer_ else bins$n[bins$w_bin == w_hit],
  min_n = min_n,
  channel_width_min = floor_signif2(w_hit))

utils::write.csv(bins, file.path(dir_out, "mad_width_bins.csv"),
                 row.names = FALSE)
utils::write.csv(conversion, file.path(dir_out, "mad_width_conversion.csv"),
                 row.names = FALSE)
st <- lnk_stamp(lnk_config("default"), conn = conn)
writeLines(c(
  sprintf("date_utc: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
  sprintf("link: %s @ %s", st$software$link$version, st$software$link$git_sha),
  sprintf("fresh: %s", st$software$fresh$version),
  sprintf("args: mad=%s schema=%s source=%s widths=%s..%s min_n=%s",
          mad_target, schema, src, min(widths), max(widths), min_n)),
  file.path(dir_out, "mad_width_stamp.txt"))
print(bins)
print(conversion)
if (is.na(w_hit)) stop("no width bin with ", min_n, " or more segments reaches ",
                       mad_target, " m3/s", call. = FALSE)
