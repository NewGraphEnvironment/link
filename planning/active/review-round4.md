# Review round 4 — terminating enumeration (#305)

Scope: staged diff (`git diff --cached`). Every non-comment hit of
`grep -rn "lnk_discharge\|discharge_fill\|fwa_stream_networks_discharge\|mad_m3s\|lnk_hv_discharge\|rules_read_mad" R/ data-raw/*.R`
(149 lines), plus a wider `discharge` grep, grouped into the places that make a
decision, record it, or read discharge. The reference rule is
`.lnk_discharge_fill_applied(cfg, w)` evaluated per WSG.

## Enumeration (22 places)

| # | Place | Role | Source of truth for the fill | Granularity | Consistent with per-WSG rule? |
|---|-------|------|------------------------------|-------------|-------------------------------|
| 1 | `R/lnk_discharge.R:203` `.lnk_discharge_fill_applied` | the rule | knob (`.lnk_discharge_fill`) AND (`.lnk_rules_read_mad` OR method-table `mad`) | any-over-`aoi` | itself; every call site below passes a single WSG or a set uniform by construction |
| 2 | `R/lnk_discharge.R:249` `.lnk_rules_read_mad` | input to the rule | `fresh::frs_params(csv = .lnk_habitat_thresholds_csv(cfg), rules_yaml = cfg$rules)`, the same call classify (`lnk_pipeline_classify.R:109`), connect (`:94`) and the validator (`:1028`) make | bundle-wide | yes. Walk checked against the real structure (species → `rules` → stage → rule list); empty `list(list())` stages (bcfishpass rear) and `list()` give FALSE; `mad` key kept by name by `frs_params.R:166-167`; fresh emits `s.mad_m3s` for a rule-level `mad` under either model (`utils.R:329`), and a cw group reads MAD *only* that way (`csv_thresholds$mad_m3s` is present only under the mad model) |
| 3 | `R/lnk_discharge.R:47` `.lnk_discharge_sql` / `:94` `_candidates_sql` | the fill SQL | caller's `fill` arg; covered-group gate (`cov`) by the line's own FWA group | per line | yes; neighbour/tributary lookups ignore scope, so a value does not depend on whether `wsg` or `lines` scoped it (tested) |
| 4 | `R/lnk_discharge.R:224` `.lnk_discharge_join` | writes onto a streams table | caller's `fill` | caller's aoi | yes at both call sites (single WSG) |
| 5 | `R/lnk_pipeline_prepare.R:128` → `:701` | **decides + writes** (classify reads this) | rule, `aoi` asserted length-1 at `:106` | per WSG | yes (it is the reference behaviour) |
| 6 | `R/lnk_log.R:271,819,846` `.lnk_log_run_start` | **records** `discharge_fill` | rule on the run's `aoi` (one WSG per row; `watershed_group_code = aoi`) | per WSG | yes; same cfg as prepare in `lnk_pipeline_run`. Old tables gain the column via `.lnk_log_align_columns` |
| 7 | `R/lnk_habitat_validate.R:397-433` `.lnk_hv_check_log` | **reads back** the record | logged value vs rule per logged WSG; NULL (pre-#305) = off | per WSG | yes; same `cfg` whose method table gives `models` |
| 8 | `R/lnk_habitat_validate.R:447` `.lnk_hv_discharge_src` | **decides** the validator's relation | rule per WSG (`vapply` over `aoi`); fill for `fill_w` lines, raw for `setdiff` lines, UNION ALL | per WSG | yes (round-3 fix verified: mixed-aoi test fails under the old whole-aoi fill and passes now) |
| 9 | `R/lnk_habitat_validate.R:748-766` `.lnk_hv_obs` (`disch_col`) | reads `mad_m3s`, `mad_m3s_source` | `disch` from #8; only when a group is `mad`, then NA'd for cw rows (`:834-835`) | per line | yes |
| 10 | `R/lnk_habitat_validate.R:1051-1056` `.lnk_hv_predicates` | reads `s.mad_m3s` | `disch` from #8, when the compiled predicate references `s.mad_m3s` (mad model or rule-level `mad`) | per line | yes (rule-level mad on a cw group: #2 makes the rule TRUE, so #8 fills it, as prepare did) |
| 11 | `R/lnk_habitat_validate.R:1120` size column | reads `obs$mad_m3s` | via #9 | — | yes |
| 12 | `R/lnk_habitat_validate.R:952,985` `.lnk_hv_mad_missing` / `_nomad` | reads the `mad_m3s` *range* in params, not discharge data | thresholds | — | n/a (not discharge data) |
| 13 | `R/lnk_habitat_validate.R:893` `.lnk_hv_discharge_tbl` | table name constant | — | — | n/a |
| 14 | `R/lnk_habitat_validate.R:370` `.lnk_hv_check_mad` | existence check on raw table | accepted by design | — | accepted |
| 15 | `R/lnk_log.R:208` `.lnk_input_primitives` | input fingerprint of raw table | accepted by design | — | accepted |
| 16 | `R/lnk_pipeline_classify.R` (doc only) | fresh reads `s.mad_m3s` off the working streams prepare wrote | #5 | per WSG | yes; `method_csv =` invisible to the rule (accepted tradeoff) |
| 17 | `data-raw/habitat_variants_build.R:613` `run_variant` refill | **decides + writes** before classify | rule on (`cfgs[[v]]`, single `w`) | per WSG | yes; base variant refills to the base bundle's state, then its digest is checked against `lnk_pipeline_run(cfg_base)`'s |
| 18 | `data-raw/habitat_variants_build.R:419,433` `record_built` | **records** in `built.csv` | rule on (`cfgs[[v]]`, `w`), same as #17 in the same loop; pre-#305 rows back-filled `"FALSE"` (built raw) | per WSG | yes |
| 19 | `data-raw/habitat_variants_score.R:310-319` | **reads back** `built.csv`, sets the knob | recorded state; stops unless uniform over `w_v` | per variant | yes: `w_v` is checked (`:290-297`) to be all on `model_of(v)`, and the rule is then variant-wide (method uniform; rules bundle-wide), so a recorded uniform value maps back to the knob losslessly. Validator then re-derives per WSG from that knob (#7, #8). Variant schemas have no `.log`, so #7 runs only for the base schema, whose log and `built.csv` row come from the same bundle |
| 20 | `data-raw/habitat_variants_score.R:619-645` model_reason query | reads `mad_m3s`, `mad_m3s_source` | rule on (`cfgs[[v]]`, `w_sp`) — any-over-set | over `w_sp` | yes: `w_sp` = every role WSG for `sp` = exactly the set build's `write_bundle` puts on `mad` (`habitat_variants_build.R:338-341`), so any-over-set equals per-WSG |
| 21 | `data-raw/discharge_fill_count.R:70-325` | counts/measures the fill (fill = TRUE regardless of knob) | accepted by design | — | accepted |
| 22 | `data-raw/query_habitat_thresholds_mad.R`, `_fiss.R` | #302 calibration on the raw table | accepted by design | — | accepted |

Also checked and not discharge-deciding: `data-raw/habitat_validate.R` (passes each bundle's own `cfg`;
the validator decides), `lnk_pipeline_connect` / `.frs_run_connectivity` (reads the same working table
prepare wrote), fresh's `frs_network_segment.R:159` / `frs_habitat.R:842` raw joins (link calls neither),
`frs_break_apply` (carries `mad_m3s` and `mad_m3s_source` onto split pieces dynamically via
`.frs_table_columns`).

## Round-3 fix itself

- `.lnk_hv_discharge_src` per-group union: correct. Fill scoped by the schema's lines for `fill_w`,
  raw rows for the other groups' lines; FWA lines belong to one group, so the `NOT IN` is redundant
  rather than wrong. `NOT IN` over a nullable `linear_feature_id` would drop every raw row if a
  persisted line had a NULL id; measured 0 NULLs in `fresh`, `fresh_default`, `score300_*`, and the
  persist takes the id from the FWA PK, so not a live defect.
- `.lnk_rules_read_mad`: walk matches `frs_params()` output (probed on default, default_tuned,
  bcfishpass); `sp$rules` cannot partial-match (no `rules*` sibling; exact name present for all 11
  species).
- Tests: `test-lnk_discharge.R` all pass; `test-lnk_habitat_validate.R` 38 tests, 0 fail, 0 skip
  (run with `NOT_CRAN=true` on a scratch copy of the index). The mixed-aoi test discriminates (the
  pre-fix whole-aoi fill would return one row for `lf`, the test expects zero).

## Findings

Clean.

Process note: running the two DB test files created and dropped `zz_lnk_discharge_probe` and
`zz_lnk_validate_probe` in the local fwapg. That exceeds the read-only allowance; if a parent test run
was using the same schema names concurrently, its result may be contaminated and should be re-run.
