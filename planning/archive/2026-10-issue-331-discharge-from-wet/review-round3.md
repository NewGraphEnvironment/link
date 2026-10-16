# Code-check round 3: branch 331-phase5 (HEAD 2f6375b1, plus the uncommitted phase-5 edits)

## The mechanism

The rule "a config that reads wet needs wet's table on the host, and the same load on every host" belongs to the **config**. But it is enforced by **the one orchestrator that was taught about it** (study_area_run.sh). That orchestrator passes it downward in optional signals, and each signal fails open when it is missing:

- `CYPHER_PREP_DISCHARGE:-fwapg` in cypher_prep.sh
- `--expect-load` absent, which becomes `NA`, which means no check (discharge_wet_load.R)
- `WET_LOAD` from `2>/dev/null || true`, where empty meant no check before round 2
- wsgs_run_host.R / wsgs_dispatch.sh / wsgs_run_m4_offline.sh, which never receive the source at all

The only check that reads the requirement from the cfg itself is prepare's preflight in `.lnk_discharge_join()` (R/lnk_discharge.R:322-325). It has two limits:

1. **It fires per WSG.** Every multi-WSG runner soft-fails per WSG by design: study_area_run.sh:1043/1066 `|| echo WARN`, wsgs_run_host.R:322-339 writes an error stub RDS and carries on, trifecta. So the check cannot stop a run; it turns into N error rows.
2. **It checks presence, not identity.** Load consistency across hosts exists only where study_area_run.sh threads the id.

Round 2's three findings are all this one shape: a caller that does not send the signal gets the permissive default. Round 2's fixes closed it for study_area_run.sh, cypher_prep.sh and wsgs_run_pipeline.sh. They did not close it for the layer every other runner shares, `wsgs_run_host.R` (finding 1).

The remedy at the level of the mechanism: derive the requirement from the cfg once per host, before the first WSG. That means `lnk_preflight_discharge(conn, cfg)` at the top of wsgs_run_host.R, stopping non-zero. Add the load identity wherever more than one host or database is involved. Do not rely on each orchestrator remembering to pass a flag.

## Every entry point that reaches prepare, for a config reading wet

Found by grep: `lnk_pipeline_run|lnk_pipeline_prepare|wsg_run_one|wsgs_run_host|habitat_variants_build|lnk_compare_wsg(` plus every data-raw/*.sh and scripts/*.sh.

Key: (a) checked before any work. (b) fails loud at prepare with the load hint, per WSG, exit ≠ 0. (c) silent, or a per-WSG error a run can mask.

| Entry point | Path to prepare | Wet table missing | Hosts on different wet loads |
|---|---|---|---|
| data-raw/study_area_run.sh | wsg_run_one.R on dispatcher + cyphers | **(a)**: the dispatcher probe (:281-297) and gate (:659-675) run before spend. Each cypher's cypher_prep loads wet and checks the load id before any write (prep FATAL leads to burn). | **(a)**: `--expect-load` on every cypher, now required non-empty |
| data-raw/wsg_run_one.R (direct) | lnk_pipeline_run | **(b)**: prepare stops with the hint, exit 1. `.lnk_log_inputs` before it is soft and records NULL for the missing table (R/lnk_log.R:748-839), so the hint is the error the user sees. | not checked (single host). Additive runs over time can leave one persist schema holding mixed loads, recorded only in log_input. |
| data-raw/wsgs_run_pipeline.sh | wsgs_dispatch.sh → wsgs_run_host.R | **(a)**: refuses any config that does not resolve to fwapg (:101-117). It fails toward refusal: an empty or failed resolve also refuses (verified in a copy: bcfishpass → `fwapg`, default → `fwapg`, default_tuned → `wet`). | n/a (refused) |
| data-raw/wsgs_dispatch.sh (direct) | wsgs_run_host.R on M4 / M1 / cyphers | **(c)**: no gate, and nothing loads wet on any host. Each WSG is an `ERROR` line plus an error-stub RDS, and every host exits 0 (finding 1). | **(c)**: no load-id check even when every host has wet |
| data-raw/trifecta_smoke.sh | wsgs_dispatch.sh `--fail-fast` | (b) at the first WSG; the smoke assertion reports it. Loud, but after spin. | not checked |
| data-raw/wsgs_run_m4_offline.sh | wsgs_run_host.R on one host | **(c)**: every WSG writes an error stub; `RC` is 0, so the `FATAL: wsgs_run_host.R exited` check (:117-121) never fires and it prints "complete" (finding 1) | n/a (one host) |
| data-raw/wsgs_run_host.R (direct) | wsg_pipeline_run.R / lnk_compare_wsg → lnk_pipeline_run | **(c)** without `--fail-fast` (finding 1) | n/a |
| data-raw/wsg_pipeline_run.R, lnk_compare_wsg() (direct) | lnk_pipeline_run | (b) | n/a |
| data-raw/habitat_variants_build.R | base: lnk_pipeline_run, not wrapped. Variants: `.lnk_discharge_join` | (b): the script stops (local only) | n/a (one DB) |
| data-raw/wsg_recompute_one.R, recompute_parity.sh, recompute_sweep.sh | lnk_access / lnk_mapping_code only, no prepare | n/a: reads the persisted streams, no discharge | n/a |
| data-raw/exp_gradient_extra_breaks.R | lnk_pipeline_prepare with `default` hard-coded | n/a (fwapg) | n/a |
| data-raw/wsg_vignette_data.R, buckets_balance.R | `bcfishpass` hard-coded | n/a | n/a |
| data-raw/trifecta_15wsg.sh | sources data-raw/compare_bcfishpass_wsg.R, which no longer exists | dead before this branch | n/a |
| data-raw/logs/*/reclassify.R, verify_classify.R, run.R (cfg by argument) | classify/connect on an already-prepared schema; no re-join | see finding 2 (classify reads whatever prepare wrote, whatever `cfg` now says) | n/a |
| data-raw/cypher_prep.sh, snapshot_bcfp.sh, scripts/update_hosts.sh, host_stamp.R, host_vintage.R | none (host prep and stamps). `host_vintage.R` passes no cfg, so wet is not re-checked post-prep; cypher_prep has already checked it. | n/a | n/a |

## Consumers of the logged source, comment and load

- **Validator** `.lnk_hv_check_log` (R/lnk_habitat_validate.R:478-490): warns, by design, only where `cfg` reads discharge. Run on `cfg = default_tuned` (now wet) against any cw build, it raises no warning, and that is correct (the source moves no flag).
- **Export** (R/lnk_scenario_export.R:933-990, 1171-1210): `source` per WSG, and `wet_load` {logged, current, matches}. `matches` is **recorded only**. No code reads it (grep: no reader in R/, habitat_publish.R, or the report). That is the stated design ("flags a mismatch"). While every group is on cw, it moves only the exported `mad_m3s` / `*_ratio_mad`, not a flag. Not reported.
  - Note: discharge_wet_load.R's new remedy ("reload the dispatcher with `wet_db_load(conn, wet_catalog())`") is the one action that produces `matches = FALSE` for every earlier wet build on the dispatcher, including the score331_* evidence. Following it should come with re-stamping or rebuilding those.
- **habitat_publish.R** (:271-273): passes the value through to runs.csv; NULL reads as fwapg.
- **Score** (habitat_variants_score.R:304-331): reads built.csv and **overrides** each cfg's fill and source with it, base included. So a re-resolved `default_tuned` cannot leak into a score.
- **schema_consolidate.R** (:107-113): brings the destination log tables up to the source's columns first, so `discharge_source` / `table_comment` are not dropped on the way home.

## Re-resolved cfgs, and bundles that `extends: default_tuned`

- **inst/extdata/configs:** none extends default_tuned. `default` / `bcfishpass` / `default_extrabreaks` / `default_rearbreaks` resolve fwapg; the new test asserts the first two.
- **Committed, `extends: default_tuned` with no pinned source** (8): `data-raw/logs/habitat_score_300/bundles/{bt,gr,rb,ko}_mad` and `habitat_score_305/bundles/{bt,gr,rb,ko}_mad_fill`. Loaded now, they resolve to **wet**. Their only reader is the score, which overrides the source from built.csv (no source column, so fwapg). A re-score of #300 / #305 is therefore unchanged.
- **data-raw/habitat_score/variants_300.csv, variants_305.csv:** rows with an empty `discharge_source` inherit the base's. A rebuild with `--base=default_tuned` at post-phase HEAD now builds every model-only variant on **wet**, and the base needs wet on the host. The bundle's config.yaml and built.csv record it, so it is not silent. But those result directories no longer reproduce (#305 already did the same through the fill). Not reported. If they should stay rebuildable as published, set `discharge_source=fwapg` on their non-base rows.
- **habitat_variants_build.R:** writes the resolved source into each variant bundle (:391-405), never inherits it. Base resume (:524-536) keys on `link_sha = HEAD` and a clean tree, so a base built before the switch is rebuilt after the commit and is never reused across it.
- **The MAD producers** (query_habitat_thresholds_mad.R, query_width_mad_equivalent.R): default `--discharge-source=fwapg` and build their cfg from `default`. They do not move.
- **No fresh_default_tuned schema exists locally** (queried), so no persist schema is mixed-source today.

## Findings

- **[severity: fragile]** data-raw/wsgs_run_host.R (whole loop, :282-339). This is the shared host runner behind wsgs_dispatch.sh, trifecta_smoke.sh and wsgs_run_m4_offline.sh, and it has no discharge preflight.
  - The round 2 fix refuses wet in wsgs_run_pipeline.sh only. That is one of the three scripts reaching it, and the mechanism above in its plainest form.
  - With `--config=default_tuned` (wet after this phase) on a host without `discharge.fwa_v1_segment_monthly`, every WSG errors at prepare and the error is caught at :322. The script writes `list(error = ...)` stubs and exits 0.
  - wsgs_run_m4_offline.sh then passes its `RC` check and prints "complete". Its own header shows `--config=default` usage, so a non-bcfishpass config is an intended input.
  - wsgs_dispatch.sh multi-host, run directly, also has no load-identity check across M4 / M1 / cyphers.
  - Fix in one place: at the top of wsgs_run_host.R, `res <- lnk_preflight_discharge(conn, cfg); if (!res$ok) quit(status = 1)` before the loop. For a wet cfg in wsgs_dispatch.sh, either refuse (as wsgs_run_pipeline.sh does) or thread the dispatcher's load id. A guard in wsgs_run_host.R would also make wsgs_run_pipeline.sh's refusal redundant rather than load-bearing.

- **[severity: fragile, planned verification]** planning/active/task_plan.md Phase 5 plans to check that `cw` classification does not move by preparing once and re-classifying on the same schema under both sources, with `habitat_thresholds_282/reclassify.R`'s method. That check cannot fail.
  - reclassify.R runs only `lnk_pipeline_classify` + `lnk_pipeline_connect`. `mad_m3s` is written by prepare (`.lnk_discharge_join`, R/lnk_pipeline_prepare.R:704), so both "sources" classify on whatever prepare joined.
  - It is the verification-reads-its-own-output shape. It would also stay green if `discharge_source` were ignored entirely.
  - Re-join between the two classifies with `link:::.lnk_discharge_join(conn, paste0(schema, ".streams"), aoi, fill = .lnk_discharge_fill_applied(cfg, aoi), source = .lnk_discharge_source(cfg))`, as habitat_variants_build.R's run_variant does. Also assert that `mad_m3s` actually differs between the two passes, so the control can go red.

- **[severity: claim]** inst/extdata/configs/default_tuned/config.yaml (uncommitted). The description says "with BT's MAD minima re-tuned on it" and the new comment says "BT's MAD minima were re-tuned on it". But the bundle's `parameters_habitat_thresholds.csv` still carries BT `spawn_mad_min` / `rear_mad_min` 0.078, which is #302's fwapg P10.
  - The phase 4 score that would decide them has not landed: Phase 4 boxes are open, and only `score331_default` exists in the DB. Wet's ladder P10s are 0.012 spawn and 0.043 rear (variants_331.csv).
  - Committed as is, the shipped bundle states a tuning that did not happen, and it would read wet with minima fitted to fwapg.
  - Commit the source switch together with the CSV values (and the regenerated rules diff), or word the comment for what is true at that commit.

## Verified, not findings

- Round 2's fixes are correct:
  - cypher_prep.sh's empty-load guard fails toward stop.
  - study_area_run.sh's empty `WET_LOAD` is now FATAL before spend.
  - wsgs_run_pipeline.sh's refusal fails toward refusal.
  - I ran the dispatcher probe in a copy against local fwapg with the phase-5 `default_tuned`. It prints exactly `wet_db_load(): … (built 2026-10-15T02:06:57Z, wet acb820f)`, with nothing else on stdout. With `--expect-load`, a host holding `comment = NA` reloads and then fails, so it fails toward stop.
- The uncommitted test edits pass against the code paths they name:
  - `.lnk_hv_discharge_src` with no filled group returns the raw relation without touching the DB.
  - `default` → fwapg, `default_tuned` → wet.
- prepare's hint is the error a user sees: `.lnk_log_inputs` (which runs before prepare) LEFT JOINs a missing table to NULL and is soft.
- snapshot_bcfp.sh never touches the `discharge` schema, so `--refresh-primitives` after the `WET_LOAD` probe cannot change the dispatcher's load under the run.
- The `--auto-install` re-prep (`CYPHER_PREP_STAGE=install`) exits before the wet section, so it does not reload wet without `--expect-load`.
