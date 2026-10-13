# Code-check round 3 (#265) — mechanism + enumeration

## Mechanism

All five earlier findings are one shape: **one fact (a row's identity, a table set, a frame's
columns/types, a log table's column set) produced or consumed in two places that agree only
because someone kept them in step by hand**. There was no single source and no guard comparing
the two. R1 had a newer probe and an older probe writing one row with no rule between them, and
a hardcoded table set beside `.lnk_vintage_primitives()`. R1/R2 had a real read and an empty
frame built separately (columns, then `integer64` vs `numeric`). R2 had dispatcher and cypher
`log_input` column sets that only match when both ran this link.

## Enumeration (place | holds? | why)

| place | holds? | why |
|---|---|---|
| Object URLs: dictionary `.lnk_input_primitives()$url` vs snapshot_bcfp.sh literals (PSCIS, CABD_URL, MSC_URL, OBS_URL) | holds | `lnk_artifact_record()` anchors a regex built from the dictionary (`.lnk_regex_escape` escapes `{}?.`; the `{wsg}` swap matches the escaped `\{wsg\}` with `fixed = TRUE`) and stops on a mismatch. Fails loud |
| Snapshot table set: manifest rows vs `.lnk_vintage_primitives()` | holds | `setequal` in artifact_record.R; `artifact_row` is called exactly once per table, so no duplicates reach the single-statement upsert |
| `--clear` set vs gate set vs record set | holds | All three now come from `.lnk_vintage_primitives()` |
| Probe set (`startsWith(source,"fwapg/")`) vs gate set (`!startsWith`) | holds | Complementary filters on one column; loader and probe never touch the same table, so loader-vs-probe precedence is never tested by real data, only by the tests |
| Host label: writer (`artifact_record.R`, `.lnk_host()`) vs readers (`.lnk_log_inputs`, `.lnk_vintage_stamp`, `--clear`) | holds | One function. On cyphers, cypher_prep rewrites `~/.Renviron` before the snapshot step, and neither study_area_run.sh nor wsg_run_one sets `LNK_HOST_ALIAS` per process, so snapshot and run resolve the same label. Live: m1 judged by 4 stamps |
| URL key for `{wsg}`: probe expands with DISTINCT `watershed_group_code` vs run expands with `aoi` | holds | Same template, same `sub(fixed=TRUE)`; WSG codes are `[A-Z]{4}`, which matches the guard regex and the count regex |
| `lnk_artifact_read()` real vs empty frame (columns and types) | holds | `n_rows::float8` on the real path; the empty frame has the same 10 columns and types. Verified against the local DB: n_rows is num and the times are POSIXct UTC |
| `.lnk_vintage_stamp()` real vs empty frame | holds | Both are `(table_name chr, loaded_at POSIXct)`; `max(timestamptz)` comes back as POSIXct |
| HEAD row shapes: `.lnk_artifact_head` success / `na_row` / `.lnk_artifact_head_na` | holds | Same 5 columns, same order and types (status integer / NA_integer_, last_modified POSIXct UTC), so `do.call(rbind)` + `cbind` is safe |
| Identity spelling: bash HEAD (loader) vs httr HEAD (probe) | holds | ETag quotes are stripped on both sides and again by `.lnk_etag_normalise`; header names go through `tolower` in awk and httr's case-insensitive list; Last-Modified is parsed by one function (`httr::parse_http_date` sets the C locale itself) |
| bash -> TSV -> R (manifest) | holds | No tabs in any field. `read.delim(quote="", na.strings="")` turns empty fields into NA; `loaded_at` is written as `date -u ...Z` and parsed with the matching format in UTC; the anyNA guard |
| R -> SQL literals in `lnk_artifact_record` (`lit()`) | holds | POSIXct is formatted in UTC with `+00`, numerics with `%.0f` (no `1e+06`), NA becomes NULL, and every value carries an explicit cast |
| `cols_source_artifact` vs the hand-written INSERT column list / VALUES / `set_cols` | holds (today) | 12 = 12 and in the same order. They are hand-kept rather than derived from the vector. Not a bug now |
| `cols_log_input` artifact_* (7) vs `.lnk_log_inputs` INSERT list (7) vs SELECT (`p.url, p.kind` + 5) | holds | Both `art_cols` branches give 5 expressions in the same order and types; the join on the full PK gives at most 1 row |
| kind / recorded_by values vs the table's CHECK | holds | Dictionary values are in `object/api/derived`; `match.arg` |
| Existence probes for the artifact table: information_schema (`.lnk_log_inputs`, `.lnk_vintage_stamp`) vs `to_regclass` (`lnk_artifact_read`) | holds | They agree for the owning role; they diverge only for a role without privileges, which this stack does not use |
| Dispatcher vs cypher `log_input` column set — study_area_run.sh consolidate | holds | R2 fix: `.lnk_log_create_tables()` on the destination before `schema_consolidate()` |
| Dispatcher vs source `log_input` column set — **wsgs_run_pipeline.sh consolidate** | **does not hold** | See finding 1 |
| `fresh.log_source_artifact` vs the `force_recreate` drops in cypher_prep's `lnk_persist_init` | holds | Only tables with GENERATED-column drift are dropped, by name |
| `fresh.log_source_artifact` vs schema_consolidate DELETE+COPY | holds | It has no `watershed_group_code`, so it is never in `wgc_tables` and is never touched; per-host identity reaches home through log_input |

## Findings (only non-holding places)

- **[severity: fragile]** data-raw/wsgs_run_pipeline.sh:427-433 — R2's fix landed in only one of
  the two `schema_consolidate()` callers. The legacy M4-centric driver still consolidates without
  first bringing the destination's log tables up to this link's columns
  (`link:::.lnk_log_create_tables(<dest>, schema)`). In that flow the destination (M4) is not one
  of the sources (m1 and the cyphers are), so the destination's `log_input` only has the
  `artifact_*` columns if M4 itself ran a model at this link version. That is the R2 scenario, and
  in this driver it is the normal case rather than an edge case. `schema_consolidate` copies only
  the shared columns, so every source's `artifact_version_id` / `etag` / `last_modified` /
  `loaded_at` / `recorded_by` / `url` / `kind` would be dropped without a message, and the cyphers
  are burned afterwards. It also loads the *installed* link (`library(link)`). The impact is lower
  because study_area_run.sh replaced this driver (its header, line 7), but the file still works and
  has no deprecation note. Fix: run the same `.lnk_log_create_tables()` call there, or retire the
  driver.

Nothing else in the enumeration fails.
