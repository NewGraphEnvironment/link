# Provincial parity — link 0.36.0 (2026-05-12 → 13)

**Run**: 2026-05-12 22:22 PDT → 2026-05-12 23:55 PDT (resume after Phase 7 bcfp-not-modeled fix). Wall 1h 32m 16s.
**Hardware**: M4 Max (local) + M1 (Allans MacBook Pro via tailnet) + 3× cypher droplets (job1/job2/job3 via DO + tofu workspaces)
**Software**: link 0.36.0 (link#162 Phases 1–7 + hardening; sha 531e881), fresh 0.31.0, bcfp reference `bcfishpass@v0.7.14-141-g05057f9` (`model_run_id 122`, rebuilt 2026-05-12 20:28 PDT)
**Configuration**: bcfishpass bundle, `--with-mapping-code` enabled (Phase 2 mapping_code lens)
**Source data**: 232 candidate WSGs → 217 dispatched (link#157 filter still in place)
**Outputs**:
- Per-WSG RDS: `data-raw/logs/provincial_parity/*.rds`
- Per-WSG mapping_code stats embedded in each list-shape RDS
- Aggregate annotated CSV: `data-raw/logs/provincial_parity/__TS___annotated.csv` (output of `lnk_parity_annotate()` against `research/bcfp_divergence_taxonomy.yml`)
- Per-host run logs: `data-raw/logs/202605122221_trifecta_provincial_*.txt`
- Orchestrator log: `data-raw/logs/202605122221_trifecta_provincial_orchestrator.txt`

This is the **first run that exercises link#162's full machinery**: inline LPT bucket allocation (Phase 5), N-cypher dispatch via tofu workspaces, post-pull `lnk_parity_annotate()` against the divergence taxonomy YAML, the `lnk_compare_wsg` library function (replacing the inline `compare_bcfishpass_wsg.R` SQL), and the `mapping_code` branch (per-segment per-species token-level parity).

## Headline

| Metric | 2026-05-11 (link 0.35.0) | 2026-05-12 (link 0.36.0) |
|---|---:|---:|
| bcfp tunnel | model_run_id 121 (`v0.7.14-125-g6e9cf1c`) | **122 (`v0.7.14-141-g05057f9`)** |
| Wall clock | 1h 54min (3-host LPT) | **1h 32min (5-host LPT + mapping_code)** |
| WSGs dispatched | 217 | **217** |
| WSGs OK (rollup) | 217 | **114** (M4 47 + M1 67; cyphers 0 — DDL drift, see Phase 7 hardening) |
| WSGs that errored | 15 (pre-dispatch filter caught later via link#157) | **103** (10 M4 = pre-fix library load; 93 cypher = `fresh.streams.gradient` GENERATED) |
| WSGs bcfp doesn't model (rollup NA, mapping_code warn) | n/a | **36** (BEAV/BLUR/COAL/DEAL/DEAR/DUNE/FONT/FROG/GATA/ISKR/KISK/KLAR/LBTN/LHAF/LIAR/LMUS/LPCE/LPRO/LRAN/MDEA/MMUS/MPRO/MURR/PINE/SMOK/SPAT/TOAD/TURN/TUYR/UBTN/UHAF/UKEC/ULRD/UMUS/UPRO/USIK) |
| Aggregate annotated rows | n/a | **2,527** |
| `UNEXPLAINED` rows at `|diff_pct| ≥ 2%` | n/a | **56** (acceptance bar NOT MET — investigation queue) |

## Acceptance bar (link#162)

**Zero rows with `class == UNEXPLAINED` AND `|diff_pct| >= 2%`** in the
annotated CSV. Surviving UNEXPLAINED rows are the investigation queue.

## Distributed dispatch — 5-host LPT

bcfp tunnel rebuilt 2026-05-12 20:28 PDT (model 122). The Phase 5 orchestrator dispatched across 5 hosts via tofu workspaces (rtj#116/#118):

| Host | Workspace | Speed factor | WSGs (LPT) | Wall | Median per-WSG |
|---|---|---:|---:|---:|---:|
| M4 (local) | n/a | 1.00 | __TBD__ | __TBD__ | __TBD__ |
| M1 (ssh) | n/a | 0.83 | __TBD__ | __TBD__ | __TBD__ |
| cypher-job1 | `job1` | 1.83 | __TBD__ | __TBD__ | __TBD__ |
| cypher-job2 | `job2` | 1.83 | __TBD__ | __TBD__ | __TBD__ |
| cypher-job3 | `job3` | 1.83 | __TBD__ | __TBD__ | __TBD__ |

LPT projection at dispatch: each host ~95 min finish (balanced).

## Divergence taxonomy — annotation results

The annotated CSV applies `research/bcfp_divergence_taxonomy.yml` to every rollup row. Categories observed:

| Class | Count | Description | Acceptance |
|---|---:|---|---|
| `A` (SETN stale) | 13 | bcfp barriers_subsurfaceflow stale; link applies user_barriers_definite_control overrides | INTENTIONAL |
| `B` (HORS-class) | 7 | fresh#158 stream_order_parent rear bypass deferred | INTENTIONAL_FRESH_DEFERRED |
| `C` (SK new-geographies) | 7 | SK lake clustering / fresh#190 / #191 | INTENTIONAL_FRESH_DEFERRED |
| `D` (over-credits) | 0 | (no entries matched this run — Class D BBAR taxonomy may need re-tuning vs bcfp 122 baseline) | NEEDS_INVESTIGATION |
| `MEASUREMENT_ASYMMETRY` | 243 | link credits centerline km AND polygon ha; bcfp credits one | INTENTIONAL |
| `NOT_APPLICABLE` | 1,380 | NA diff_pct (bcfp doesn't model species, or ref_value==0) | NA |
| `WITHIN_TOLERANCE` | 821 | unmatched residuals with `\|diff_pct\| < 2%` | CLOSED |
| **`UNEXPLAINED`** | **56** | unmatched, `\|diff_pct\| ≥ 2%` — investigation queue | **NEEDS_INVESTIGATION** |

## Unexplained divergences — investigation queue

After annotation, every `UNEXPLAINED` row at `|diff_pct| >= 2%` is investigated here. Common patterns and their likely root causes:

| WSG | Species | Habitat | link | bcfp | diff_pct | Hypothesis | Action |
|---|---|---|---:|---:|---:|---|---|
| __TBD__ | | | | | | | |

### Investigation toolkit (pre-canned)

For each UNEXPLAINED row, run the appropriate diagnostic from `research/bcfp_divergence_investigation.md`:

1. **bcfp-stale check** (Class A pattern on a new WSG): query `bcfishpass.barriers_subsurfaceflow` for control-list intersection
2. **fresh#158 propagation check** (Class B on a new WSG): is the divergence in rearing_stream only? Stream-order-parent dependency?
3. **Class C SK pattern**: lake_rearing or rearing magnitudes? Does fresh#190 / #191 apply?
4. **Class D survivor**: trace mapping_code diff for the WSG-species; look for residual barrier/observation mismatches
5. **Bcfp tunnel staleness**: re-query `bcfishpass.log` — model_run_id at dispatch time vs now; tunnel rebuild can shift baseline

## mapping_code parity (per-segment)

New in this run via Phase 2 mapping_code branch. Per-WSG per-species summary:

| WSG | Species | total_segs | match_pct | n_diffs | top_pattern |
|---|---|---:|---:|---:|---|
| __TBD__ | | | | | |

WSGs with `total_segs = 0` (bcfp doesn't model) — handled as warning via Phase 7 fix:

| WSG | n_diffs (link side) | Notes |
|---|---:|---|
| __TBD__ | | |

## Upstream bcfp changes (v0.7.14-125 → v0.7.14-141)

16 commits landed in `smnorris/bcfishpass` between our 2026-05-11 baseline (run 121) and tonight's run (122). Categorized to pre-empt ghost-chasing:

### Methodology (1 commit, affects all WSGs)

- **#892** [`146353e`] `Fix contradictory pscis_status check in remediated_dnstr_ind` (co-authored by us, May 6) — bcfp's `JOIN` clause `pscis_status = 'REMEDIATED' AND pscis_status = 'PASSABLE'` was always FALSE, suppressing `remediated_dnstr_ind` everywhere. Fix: use `barrier_status = 'PASSABLE'`. Province-wide: ~150 segments now correctly emit `REMEDIATED` mapping_code tokens. **Predicted effect on this run: less divergence on REMEDIATED token2 patterns vs 2026-05-11**, not more.

### Per-WSG override fixes (12 commits)

These edit `bcfishpass/data/*.csv` files. Link's CSV-sync state at the time of this run vs bcfp@v0.7.14-141:

| CSV | bcfp | link | Status |
|---|---:|---:|---|
| `user_modelled_crossing_fixes.csv` | 21852 | 21852 | ✓ synced |
| `user_pscis_barrier_status.csv` | 1381 | 1381 | ✓ synced |
| `user_barriers_definite.csv` | 228 | 228 | ✓ synced |
| `user_barriers_definite_control.csv` | 238 | 238 | ✓ synced |
| **`user_habitat_classification.csv`** | **15678** | **15669** | **9 rows behind** |
| **`pscis_modelledcrossings_streams_xref.csv`** | **3652** | **3641** | **11 rows behind** |

Commits that wrote to the stale CSVs:

- `user_habitat_classification.csv`: LNIC ×5 (`4abb73d`, `c57bff1`, `e9cb3c0`, `880af53`#896, `665a72c`), HORS (`4e47469`#893), Ulkatcho (`d0a08af`#889), small follow-ups
- `pscis_modelledcrossings_streams_xref.csv`: HORS Horsefly dedup (`e0765de`#890)

### Predicted ghost divergences

WSGs likely to see new UNEXPLAINED rows in this run **due to CSV-sync lag, not real methodology**:

- **LNIC** — link runs against 5-commit-stale habitat_classification; bcfp 122 has the new rows
- **HORS** — both csvs stale (habitat + xref); HORS already has Class B fresh#158 signature; sync-lag stacks on top
- **Ulkatcho area** — likely ULKA or nearby; habitat_classification stale
- **BONP** — 1 row removed from `user_modelled_crossing_fixes.csv` (`b05f2f0`); link's csv matches bcfp head, so this should be OK

### Diagnostic before tagging

Before classifying any UNEXPLAINED row in LNIC/HORS/Ulkatcho as a real methodology divergence:

```bash
# Pull bcfp at v0.7.14-141 head, diff the relevant CSV
cd ~/Projects/repo/clones/bcfishpass
git checkout 05057f9
diff <(sort data/user_habitat_classification.csv) \
     <(sort ~/Projects/repo/link/inst/extdata/configs/bcfishpass/overrides/user_habitat_classification.csv) \
  | head -30
# Look for rows in the suspect WSG only
```

If the diff rows sit in the suspect WSG, the divergence is **CSV-sync lag** (`INTENTIONAL_CSV_LAG` status; ref this section). Fix forward by syncing the CSVs (manually `cp` from bcfp v0.7.14-141 head; the daily sync workflow will catch up by next morning), then re-annotate.

## Primitive-source consistency check

Cross-host parity check confirmed _3 of 4_ upstream primitives byte-identical across all 5 link hosts AND the bcfp tunnel (model 122):

| Primitive | M4 | M1 | cy1/2/3 | bcfp 122 |
|---|---:|---:|---:|---:|
| PSCIS assessments | 19,903 | 19,903 | 19,903 | 19,903 ✓ |
| CABD dams | 2,594 | 2,594 | 2,594 | 2,594 ✓ |
| modelled_stream_crossings | 532,166 | 532,166 | 532,166 | 532,166 ✓ |
| bcfishobs observations | **372,561** | **372,420** | **372,627** | **372,627** |

The cyphers got fresh `snapshot_bcfp.sh` runs at 22:30 PDT (after bcfp 122 built at 20:28) — their primitives match bcfp exactly. M4 last refreshed 2026-05-09 (-66 obs vs bcfp), M1 even older (-207 obs).

**Net drift on the parity comparison**: 0.018% (M4) and 0.056% (M1) of the observation set. Will surface as a small set of UNEXPLAINED rows in the annotated CSV — segments where access/spawn/rear status flipped because of an observation that M4/M1 hasn't pulled but bcfp now has. Mapping_code-level mostly; rollup-level should be sub-1%.

**Diagnostic recipe** for an UNEXPLAINED row on an M4 or M1 WSG:
```sql
-- Did bcfp pick up new observations in this WSG that we don't have?
SELECT count(*) AS missing_on_our_side FROM (
  SELECT blue_line_key, downstream_route_measure FROM bcfishobs.observations  -- on bcfp tunnel
  WHERE watershed_group_code = '<WSG>'
EXCEPT
  SELECT blue_line_key, downstream_route_measure FROM bcfishobs.observations  -- on M4/M1 local
  WHERE watershed_group_code = '<WSG>'
) diff;
```

If the diff count is non-zero AND those segments appear in the WSG's mapping_code diffs, the divergence is **observation snapshot lag** (not methodology). Tag as `INTENTIONAL_OBSERVATION_LAG` with `refs: research/provincial_parity_2026_05_12.md#primitive-source-consistency-check`. Fix forward by running `snapshot_bcfp.sh` on M4 + M1 before the next provincial run.

## Phase 7 operational lessons

This run surfaced several gotchas worth codifying for the wrapper script (`data-raw/run_phase7.sh` follow-up):

1. **Cross-host archival before run.** `archive_provincial_runs.sh` ran on M4 only initially; M1's stale RDS got SCP-pulled back during the post-pull step, polluting the aggregate annotation. Fix: archive on ALL hosts (M4 + M1 + all cyphers) before dispatch. Now codified in the recommended cadence in `data-raw/README.md`.

2. **bcfp coverage gap is real, not a bug.** bcfp's 2026-05-12 build models 187 WSGs; we dispatch 217. The 36-WSG delta caused `with_mapping_code = TRUE` to stop loudly when it should have warned + returned NA. Fix (commit __TBD__): `.lnk_compare_wsg_mapping_code_diff` distinguishes (a) bcfp 0 rows → warn + NA fill, (b) bcfp has rows but no merge → stop loud (real misalignment).

3. **Reinstall on every host that runs the new code.** Phase 7 fix was pushed and `pak::local_install`'d on M1 + 3 cyphers, but NOT on M4 — M4's running R session loaded the OLD library at dispatch start. Result: 10 of M4's 57 bucket WSGs errored under the old code. Cleanup: post-main-run M4-only re-dispatch with fix installed locally.

4. **bcfp tunnel rebuild cadence.** This run kicked off 53 min after the Tuesday 20:28 PDT rebuild of model_run_id 122. Comparison reference is the new model. Drift from 2026-05-11 numbers reflects bcfp's own changes between v0.7.14-125 and v0.7.14-141 (~16 commits of bcfp evolution), not just our link changes. Taxonomy entries tuned to 121-era staleness may not match 122-era data — re-tune iteratively.

## Files

- Orchestrator log: `data-raw/logs/202605122221_trifecta_provincial_orchestrator.txt`
- Per-host run logs: `data-raw/logs/202605122221_trifecta_provincial_{m4,m1,cypher_job1,cypher_job2,cypher_job3}.txt`
- Per-host timing CSVs: `data-raw/logs/provincial_parity/__TS___{m4,m1,cy}_per_wsg_times.csv`
- Per-WSG rollup RDS: `data-raw/logs/provincial_parity/*.rds`
- Aggregate annotated CSV: `data-raw/logs/provincial_parity/__TS___annotated.csv`
- Phase 7 timing log: `data-raw/logs/202605122116_phase7_timing.log`

## Cross-refs

- link#162 (this work)
- Prior parity run: `research/provincial_parity_2026_05_11.md`
- Divergence taxonomy: `research/bcfp_divergence_taxonomy.yml`
- Phase 5 orchestrator + LPT: `data-raw/README.md#provincial-dispatch`

## Next

After UNEXPLAINED investigation: update `research/bcfp_divergence_taxonomy.yml` for any newly-classified patterns (commit + re-annotate; don't rerun the full pipeline). Then close link#162 with the v0.36.0 release in Phase 8.
