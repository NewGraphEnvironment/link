# Review — #286 phases 2-3, round 2

Reviewed: staged diff (`diff_p23.patch`) against the working tree, fresh v0.36.2
(installed, RemoteSha e3a37f0) and fresh source at c341a59, db_newgraph @ 88bb47c.

## Findings

- **[severity: bug]** `inst/extdata/configs/bcfishpass/config.yaml:137-143` (and the
  identical entry in `default/config.yaml:147-153`) — the new provenance entry declares
  `source: https://github.com/smnorris/bcfishpass`, which enrolls the "frozen" method
  table in the weekly csv-sync, and that sync auto-merges.
  - `data-raw/sync_bcfishpass_csvs.R:120-122,149-150` picks every bcfishpass-bundle
    provenance entry whose `source` is exactly that URL, then fetches
    `csvs/<basename(path)>` = `csvs/parameters_habitat_method.csv` from s3://fresh-bc.
  - That key exists and is refreshed weekly: `db_newgraph/jobs/dump_bcfishpass_csvs`
    (`PARAM_CSVS=( parameters_habitat_method.csv … )`, from
    `parameters/example_newgraph/` at the latest ng-prod SHA). I fetched it with curl:
    HTTP 200, sha256 `9802bb71…`. That is byte-identical to the shipped copy today, so
    nothing happens yet.
  - The first time upstream edits example_newgraph's method table (other
    `parameters/example_*` dirs already carry `mad` rows, e.g. HORS and LNIC), the sync:
    - writes the new bytes into **both** `bcfishpass/` and `default/` (`:251-264`, which
      writes `BUNDLE_BCFP` and `BUNDLE_DEF` unconditionally) and rewrites both
      provenance blocks. The drift is byte drift (the shape is unchanged), so
      `sync-bcfishpass-csvs.yml:143` runs `gh pr merge` without review or R CMD check.
    - Effects:
      - `default`, which `default_tuned` inherits, silently moves groups to `mad`. Under
        fresh's mad semantics, BT/GR/KO/RB get no stream habitat in those groups.
      - `default_extrabreaks` and `default_rearbreaks` are not touched, so they quietly
        diverge from `default`.
      - `config_hash` moves for the bundles that changed.
      - `test-lnk_pipeline_classify.R` ("passes a shipped bundle's own method table",
        `expect_true(all(pm$model == "cw"))`) goes red on main after the fact.
  - This contradicts the stated decision that each base bundle carries a **frozen**
    copy. The thresholds entry avoided this by declaring
    `source: https://github.com/NewGraphEnvironment/fresh` with the bcfishpass origin in
    `derived_from:`.
  - Fix: give the method entries a non-matching `source:` (e.g. `link (frozen copy;
    link#286)`) plus `derived_from: smnorris/bcfishpass@f8db4b9
    parameters/example_newgraph/parameters_habitat_method.csv`, in all four bundles.
    Changing `bcfishpass/config.yaml` alone stops the sync, because the script reads only
    that bundle's provenance. The alternative is to decide that the bcfishpass bundle
    tracks upstream for parity, but then the sync script must stop writing `default`.

## Checked and clean

1. **mad_m3s leak from the working streams table.**
   - `lnk_pipeline_persist.R:55` inserts with the explicit `cols_streams` list, so the
     new column is never persisted.
   - `frs_break_apply` carries every writable column to split children
     (`fresh/R/frs_break.R:660-700`), so `mad_m3s` survives segmentation, which is what
     the mad path needs.
   - `lnk_access.R:175` `CREATE TABLE … SELECT *` reads the *persist* streams. It is
     harmless either way.
   - The `habitat_variants_build.R` digests hash `streams_habitat` rows and
     `streams(id_segment, length_metre)`, not working-streams columns, so they are
     unaffected.
   - Old kept working schemas without `mad_m3s` re-classify fine while every group is
     `cw`. fresh checks for the column only when a group is `mad`.
2. **Missing discharge table.**
   - Local docker fwapg has `whse_basemapping.fwa_stream_networks_discharge`: a
     table, 2,716,652 rows, a unique pkey on `linear_feature_id`, and `mad_m3s` is
     double precision. So the `UPDATE … FROM` cannot fan out.
   - fresh's docker `load.sh` has loaded discharge since its first commit (README stage
     2), so cyphers built from it carry it as well.
   - If a DB lacked it, `frs_col_join` would add a `text` column (the
     information_schema lookup returns nothing) and the `UPDATE … FROM` would then
     **error**. That is a loud failure, not a silent one.
   - The bcfishpass tunnel is not a modelling target: it lacks the `fresh.*`
     primitives anyway.
3. **Other classify entry points.**
   - The only `frs_habitat_classify` call is in `lnk_pipeline_classify`.
   - `data-raw/compare_adms.R` calls `fresh::frs_habitat()` directly. It is a legacy
     experiment, and fresh's own default (all `cw`) applies.
   - `habitat_variants_build.R`, `exp_gradient_extra_breaks.R` and the two #282 logs
     scripts all go through `lnk_pipeline_classify`. The variant bundles use
     `extends: default`, so they inherit the method table.
4. **config_hash change.**
   - Nothing gates on a stored hash.
   - `.lnk_log_config_snapshot` keys on the hash and simply inserts a new snapshot.
   - `lnk_preflight_parity` compares hosts within one run, all on the same code.
   - The `habitat_variants_build.R` resume gate keys on `link_sha` and `link_dirty`
     (and so rebuilds at a new HEAD regardless), not on the hash.
   - `lnk_config_verify` reports no drift and no missing file for all five bundles,
     `default_tuned` included.
5. **read.csv.**
   - A UTF-8 BOM is stripped on this host and the header comes out clean.
   - CRLF parses.
   - A blank `model` cell comes through as `""`, which fresh rejects loudly.
   - A quoted header (fresh's own copy is fully quoted) parses.
   - A header-only file gives 0 rows, so every group is `cw`, as designed.
   - `"NA"` stays a string.

## Notes (not findings)

- `.lnk_input_primitives()` (`R/lnk_log.R:200`) does not fingerprint
  `whse_basemapping.fwa_stream_networks_discharge`. That is irrelevant while every
  bundle is all-`cw`. Once a bundle puts a group on `mad`, the discharge vintage feeds
  output without a `log_input` row.
- fresh's shipped copy (sha256 `6b5414ac…`, quoted, 187 rows) is not byte-identical to
  the bundles' copies (188 rows). That is fine: it only matters for the fallback path,
  which is hashed by content.
