# data-raw/accessible_km_proof_co.R
#
# Phase-1 proof for link#221: link's coho `accessible_km` per WSG matches a
# tunnel-free bcfp reference within +/- 5%.
#
#   link side: sum(streams.length_metre)/1000 where streams_access.access_co
#              IN (1,2), joined on the full PK (id_segment, watershed_group_code)
#              (#203 discipline; length lives on streams, not streams_access).
#   ref  side: sum(fresh.streams_vw_bcfp.length_metre)/1000 where
#              barriers_ch_cm_co_pk_sk_dnstr = '' (empty = no barrier downstream).
#
# The snapshot stores barriers_<group>_dnstr as comma-joined TEXT, so the
# accessible predicate is `= ''`, NOT `= array[]::text[]` (which errors:
# "operator does not exist: character varying = text[]").
#
# Runs for every WSG present in BOTH fresh.streams_access and
# fresh.streams_vw_bcfp. Prints the per-WSG table and stops non-zero if any
# UNEXPECTED WSG exceeds |pct_diff| > 5. Validated 2026-07-01 on local docker
# fwapg: 19/20 WSGs within +/-5% (most < 1%; MORR 0.09%, BULK 0.27%).
#
# Known divergences (excluded from the hard-fail, still printed + flagged):
#   SETN — bcfp `barriers_subsurfaceflow` is stale for ~95% of SETN segments,
#   propagating into bcfp's `barriers_ch_cm_co_pk_sk_dnstr` so bcfp UNDER-credits
#   accessible habitat; link correctly applies user_barriers_definite_control.
#   link > ref here is the expected direction. Taxonomy: setn-anadr-*-stale in
#   research/bcfp_divergence_taxonomy.yml. Not a link defect (bcfp-side stale).
#
# Usage: Rscript data-raw/accessible_km_proof_co.R

main <- function() {
  conn <- link::lnk_db_conn(
    dbname = "fwapg", host = "localhost", port = 5432L,
    user = "postgres", password = "postgres")
  on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

  tolerance_pct <- 5
  known_divergence <- c("SETN")

  # Comparison universe = coho-PRESENT WSGs: those with >= 1 coho-accessible
  # segment (the `lnk` CTE). This is deliberate. link models access per species
  # (`access_co`), so coho-absent WSGs have access_co = -9 everywhere and 0
  # accessible km; bcfp models CO inside the salmon group `barriers_ch_cm_co_pk_sk`,
  # which is accessible wherever ANY of CH/CM/CO/PK/SK reaches. Including
  # coho-absent WSGs would compare link's 0 against bcfp's other-salmon km -> false
  # -100% divergence. Scoping to `lnk` compares only where a coho km number is
  # meaningful. LEFT JOIN ref still surfaces the dangerous case (link has coho km,
  # bcfp shows none) as a NULL ref_km caught by the null_ref guard below.
  sql <- "
WITH lnk AS (
  SELECT s.watershed_group_code AS wsg,
         sum(s.length_metre) / 1000.0 AS link_km
  FROM fresh.streams s
  JOIN fresh.streams_access a
    ON s.id_segment = a.id_segment
   AND s.watershed_group_code = a.watershed_group_code
  WHERE a.access_co IN (1, 2)
  GROUP BY s.watershed_group_code
),
ref AS (
  SELECT watershed_group_code AS wsg,
         sum(length_metre) / 1000.0 AS ref_km
  FROM fresh.streams_vw_bcfp
  WHERE barriers_ch_cm_co_pk_sk_dnstr = ''
  GROUP BY watershed_group_code
)
SELECT lnk.wsg,
       round(lnk.link_km::numeric, 2) AS link_km,
       round(ref.ref_km::numeric, 2)  AS ref_km,
       round((100.0 * (lnk.link_km - ref.ref_km)
              / nullif(ref.ref_km, 0))::numeric, 2) AS pct_diff
FROM lnk
LEFT JOIN ref USING (wsg)
ORDER BY lnk.wsg;
"

  res <- DBI::dbGetQuery(conn, sql)

  if (nrow(res) == 0L) {
    stop("No WSGs present in both fresh.streams_access and fresh.streams_vw_bcfp - ",
         "nothing to prove. Persist at least one WSG first.", call. = FALSE)
  }

  res$known_divergence <- res$wsg %in% known_divergence

  cat("\nCoho accessible_km parity (link vs tunnel-free bcfp snapshot)\n")
  print(res, row.names = FALSE)

  # ref_km NULL -> nullif(0) -> NA pct_diff: bcfp reports no accessible km for a
  # WSG link DID build (link_km may be > 0). Either a data problem (missing
  # snapshot rows) or a genuine 0-vs-nonzero divergence. Fail loud before the
  # tolerance check, where an NA index would otherwise slip through as exit 0.
  null_ref <- res[is.na(res$pct_diff), , drop = FALSE]
  if (nrow(null_ref) > 0L) {
    stop(sprintf("bcfp ref_km is 0/NULL for WSG(s) link built: %s - check ",
                 paste(null_ref$wsg, collapse = ", ")),
         "streams_vw_bcfp populate or investigate as divergence.", call. = FALSE)
  }

  over <- res[abs(res$pct_diff) > tolerance_pct, , drop = FALSE]
  flagged_known <- over[over$known_divergence, , drop = FALSE]
  if (nrow(flagged_known) > 0L) {
    cat(sprintf("\nKnown divergence(s) over +/-%g%% (expected, bcfp-side):\n",
                tolerance_pct))
    print(flagged_known[, c("wsg", "link_km", "ref_km", "pct_diff")],
          row.names = FALSE)
  }

  unexpected <- over[!over$known_divergence, , drop = FALSE]
  if (nrow(unexpected) > 0L) {
    stop(sprintf("%d UNEXPECTED WSG(s) exceed +/-%g%%: %s",
                 nrow(unexpected), tolerance_pct,
                 paste(unexpected$wsg, collapse = ", ")), call. = FALSE)
  }

  n_ok <- sum(!res$known_divergence)
  cat(sprintf("\nPASS: all %d non-divergence WSG(s) within +/-%g%%.\n",
              n_ok, tolerance_pct))
}

main()
