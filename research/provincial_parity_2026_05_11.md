# Provincial parity — link 0.35.0 (2026-05-11)

**Run**: 2026-05-11 20:10:53 → 22:05:39 PDT (**1h 54min wall**)
**Hardware**: M4 Max (local) + M1 (Allans MacBook Pro via tailnet) + cypher (DigitalOcean droplet via reserved IP 24.144.70.121)
**Software**: link 0.35.0 (sha 8f8c7b6 + #157 dispatch fix), fresh 0.31.0, bcfp reference `bcfishpass@v0.7.14-125-g6e9cf1c` via tunnel `db_newgraph`
**Configuration**: bcfishpass bundle parity only
**Source data**: 232 candidate WSGs filtered → 217 dispatched (link#157), 15 known-empty WSGs excluded from dispatch
**Source log**: `data-raw/logs/202605112010_trifecta_provincial_orchestrator.txt`
**Output**: 232 RDS files in `data-raw/logs/provincial_parity/*.rds` (15 stub-error from this run, 217 OK)
**Aggregate**: 1,647 comparable rollup rows (after dropping `-100%` lake/wetland centerline artifacts and NA-baseline rows)

This run is the post-link#154 + link#152 successor to the 4h 55min single-host baseline in `research/provincial_parity_2026_05_01.md`. Divergence taxonomy from that doc reproduces unchanged — same Class A/B/C WSGs, same magnitudes. **Class D (over-credits) partly closed** by link#152 / link#154. Headline parity holds: median absolute Δ = 0.30%, **98.8% of rows within ±20%**, **97-99% within ±5%** on every species except WCT (91.7%) and SK (88.9%).

## Headline

| metric | 2026-05-01 (link 0.20.0) | 2026-05-11 (link 0.35.0) |
|---|---:|---:|
| Wall clock | 4h 55min (single host) | **1h 54min (3-host LPT)** |
| WSGs dispatched | 232 | **217** (link#157 filter) |
| WSGs OK | 217 | 217 |
| WSGs error | 15 | 15 (same, now skipped pre-dispatch) |
| Rollup rows | 4,739 | 4,739 |
| Real comparable rows | ~2,087 | **1,647** |
| Rows within ±1% | 28% of all | **63% of comparable** |
| Rows within ±5% | 76% of non-NA | **97-99% per species (BT/CH/CM/CO/PK/ST)** |
| Real divergences >5% | 56 rows / 28 WSGs | **42 rows / ~22 WSGs** |

The "within X%" denominators shifted between runs because 2026-05-01 counted all rows including NA-baseline + -100% artifacts; this run pre-filters. Apples-to-apples: same hotspot WSGs reproduce, with Class D shrinking.

## Per-species parity

| species | n | median \|Δ\| | within ±1% | within ±5% |
|---|---:|---:|---:|---:|
| BT  | 366 | 0.50% | 78.1% | **99.5%** |
| CH  | 374 | 0.30% | 85.3% | **98.1%** |
| CM  | 55  | 0.30% | 90.9% | **98.2%** |
| CO  | 300 | 0.30% | 87.7% | **98.0%** |
| PK  | 60  | 0.20% | 93.3% | **98.3%** |
| SK  | 207 | 0.00% | 79.2% | 88.9% |
| ST  | 237 | 0.20% | 86.1% | **98.7%** |
| WCT | 48  | 1.10% | 47.9% | 91.7% |

WCT lower coverage is small-sample (48 rows, only in 6 WSGs); SK pulled down by Class C new-geographies (below). All other species at ≥98% within ±5%.

## Distributed dispatch — LPT-balanced 3-host

Single-host baseline (2026-05-01): 4h 55min. 3-host LPT split saved **~3 hours** (61% reduction).

| Host | Hardware | Speed factor | WSGs | Wall | Median per-WSG |
|---|---|---:|---:|---:|---:|
| M4 | Apple M4 Max (this machine) | 1.00 | 79 (84 dispatched − 5 errors) | 110.9 min | 79s |
| M1 | Allans MacBook Pro (tailnet) | 0.83 (faster!) | 100 (102 − 7 errors) | 114.7 min | 64s |
| cypher | DO droplet (g-8vcpu-32gb) | 1.83 | 46 | 88.6 min | 97s |

LPT (Longest Processing Time first) bin-packing in `data-raw/balance_provincial_buckets.R` weights each WSG by its `m4_equiv` time, then assigns to the host whose projected finish time would be shortest. Cypher gets the fewest WSGs because its per-WSG cost is 1.83× M4's; M1 gets the most because it's slightly faster than M4 per-WSG. Predicted wall was 155.5 min vs actual 114.7 min — predictions tracked within 25%.

**Operational notes:**
- `data-raw/trifecta_provincial.sh` orchestrates dispatch via SSH + tailnet (`m1`) + reserved-IP SSH (`cypher@24.144.70.121`). cypher gets its bcfp-tunnel via in-script SSH local-forward `-L 63333:127.0.0.1:5432 db_newgraph`.
- M1 + cypher needed a one-time data sync of `cabd.dams` (1.9 MB), `whse_fish.pscis_assessment_svw` (18 MB), `fresh.modelled_stream_crossings` (380 MB) from M4 via `pg_dump | ssh docker exec psql`. `snapshot_bcfp.sh` is the canonical loader but those hosts didn't have it configured.
- cypher's fresh+link install required `R CMD INSTALL --no-test-load` because pak tried to upgrade `sf` and conflicted with the host's conda-managed GDAL; downgrading to `R CMD INSTALL` kept the existing `sf 1.1.0` intact.

## How bcfp parity works (recipe)

For a deeper canonical reference see `research/bcfishpass_methodology.md`. The summary recipe link follows for every provincial WSG:

1. **Inputs**: BCDC PSCIS assessments (via bcdata), bchamp `modelled_stream_crossings` (via curl), CABD dams, whse_basemapping FWA, falls + barriers_definite CSVs. All loaded LOCALLY (post-link#137 self-sufficiency).
2. **Per-WSG working schema**: `lnk_pipeline_setup` creates `working_<wsg>`. `lnk_pipeline_load` stages override CSVs. `lnk_pipeline_prepare` builds gradient barriers, falls, subsurface-flow.
3. **Crossings** (post link#154): `lnk_pipeline_crossings` reproduces bcfp's `02_pscis_streams_150m.sql` + `04_pscis.sql` byte-identically — multi-stream snap → enrich + score → b-side dedup → per-PSCIS pick → DBSCAN 5m cluster + UNIQUE(blk,drm) dedup → xref-driven INSERT.
4. **Breaks** (`lnk_pipeline_break`): sequential `frs_break_apply` for observations → gradient_minimal → barriers_definite → habitat endpoints → crossings.
5. **Classify** (`lnk_pipeline_classify`): `frs_habitat_classify` consumes `rules.yaml` derived from `dimensions.csv` via `lnk_rules_build`. Per-species habitat labels emerge.
6. **Connect** (`lnk_pipeline_connect`): per-species cluster + connected_waterbody.
7. **Persist** (post link#152): `lnk_pipeline_persist` writes `streams`, `streams_habitat_<sp>`, AND the new `<persist_schema>.barriers` (unified province-wide) into `fresh` schema via idempotent DELETE-WHERE-WSG + INSERT.
8. **Per-WSG rollup** (`compare_bcfishpass_wsg`): sums per-species spawning + rearing + lake_rearing + wetland_rearing + rearing_stream + rearing_lake_centerline + rearing_wetland_centerline. Compares vs `bcfishpass.habitat_linear_<sp>` on the tunnel.

bcfp's parity reference for this run: tunnel `bcfishpass@v0.7.14-125-g6e9cf1c` (commit pinned via `bcfishpass.log.model_version`).

## Divergence taxonomy — where parity isn't perfect

Inherited from `research/provincial_parity_2026_05_01.md` Class A/B/C/D. Each class is annotated below with **2026-05-11 status** vs the prior baseline.

### Class A — bcfp-side staleness (link is correct, bcfp is wrong)

**SETN — all 14 over-25% rows. Status: stable, identical to 2026-05-01.**

Mechanism: bcfp's `barriers_subsurfaceflow` table has stale entries that should have been excluded by `user_barriers_definite_control` rows (`barrier_ind = FALSE`). The stale subsurfaceflow propagates into bcfp's anadromous-species `barriers_<sp>_dnstr` for 95% of SETN segments, causing bcfp to under-credit. Link's rebuild correctly applies the control overrides. Filed upstream (Simon hasn't refreshed yet).

| sp | metric | link | bcfp (stale) | "diff_pct" |
|---|---|---:|---:|---:|
| CO | rearing_stream | 457 | 157 | +192% |
| CH | rearing_stream | 388 | 133 | +192% |
| ... | 14 rows total | | | |

**Subtract from divergence count** — link is correct.

### Class B — fresh#158 stream-order bypass (intentional, known gap)

bcfp's per-species rear rule has an inline `(stream_order_parent >= 5 AND stream_order = 1)` clause that credits direct order-1 tributaries of order-5+ mainstems as rearing even when channel_width < rear_min. fresh has no implementation; `dimensions.csv::rear_stream_order_bypass = no` for all species in the bcfishpass bundle.

**Status: stable. 9 rows in 2026-05-01 → 11 rows in 2026-05-11 (HORS/CLRH/COLR/KHOR), max diff 8.8% under-credit.**

| WSG | sp | metric | diff_pct |
|---|---|---|---:|
| CLRH | WCT | rearing_stream | -8.8 |
| HORS | BT | rearing_stream | -7.7 |
| COLR | WCT | rearing_stream | -7.3 |
| HORS | CH | rearing_stream | -6.8 |
| HORS | CO | rearing_stream | -5.9 |
| ... | 11 rows total | | |

**Intentional divergence.** Not shipping for parity (fresh#158 deferred). Default-bundle methodology will likely choose differently anyway. Document by referencing `research/bcfishpass_methodology.md:108`.

### Class C — SK new-geographies (lake clustering / multi-lake / adjacency)

Three open fresh mechanisms: fresh#190 (multi-lake topology, parked), fresh#191 (lake-adjacency knob, filed, default-only), and the bcfp upstream-spawn cluster gate.

**Status: stable + minor expansion. 12 rows in same WSGs (BULK, CHWK, KUMR, LRDO, NASC, NASR, NEVI, QUES, TOBA) — magnitudes unchanged. 4 minor new SK rows (THOM, OWIK, STIR, SQAM, NECR, NECL, ATNA, KNIG) at 5-19% — same mechanism class.**

| WSG | metric | link | bcfp | diff_pct |
|---|---|---:|---:|---:|
| NASR | SK spawning | 5.55 | 3.00 | **+85** |
| LRDO | SK lake_rearing (ha) | 4809 | 2645 | **+82** |
| LRDO | SK rearing | 211 | 121 | **+74** |
| TOBA | SK rearing | 8.6 | 16.8 | -49 |
| NASC | SK rearing | 15.0 | 23.7 | -37 |
| LRDO | SK spawning | 14.6 | 12.0 | +22 |
| THOM | SK spawning | 25.9 | 21.7 | +19 (new this run) |
| OWIK | SK spawning | 31.7 | 27.2 | +16 (new this run) |
| ... | | | | |

**Each row needs individual inspection** — some are stale-bcfp class, some genuine link methodology, some fresh-side bugs. Tracked under fresh#190 / fresh#191 + an open link/research follow-up.

### Class D — over-credits TBD

**Status: PARTLY CLOSED.** In 2026-05-01: TWAC BT (+24-30%), STHM BT (+14%), BULL BT (+5-6%), BBAR CH/CO (+12%), COWN BT (+5.5%). In 2026-05-11: **only BBAR CH/CO (+12%) remain >5%.** TWAC/STHM/BULL/COWN dropped below 5% threshold.

Likely cause of the closure: link#154 (PSCIS-to-modelled snap shipped DBSCAN dedup + xref precedence — bcfp-parity primitives for the crossings step) and link#152 (unified barriers with `blocks_species` predicate + cross-WSG `dam_dnstr_ind` resolution). Both shipped between 2026-05-01 and 2026-05-11.

| WSG | sp | metric | link | bcfp | diff_pct | Status |
|---|---|---|---:|---:|---:|---|
| TWAC | BT | rearing_stream | — | — | <5% | **closed** |
| STHM | BT | rearing_stream | — | — | <5% | **closed** |
| BULL | BT | spawning/rear | — | — | <5% | **closed** |
| COWN | BT | rearing_stream | — | — | <5% | **closed** |
| BBAR | CH | rearing | 168 | 150 | +12 | open — investigate next |
| BBAR | CO | rearing | 171 | 153 | +12 | open — investigate next |

### Unexplained divergences from this run (new, small)

Outside the prior taxonomy, 4 small (<8%) rows that need investigation:

| WSG | sp | metric | link | bcfp | diff_pct |
|---|---|---|---:|---:|---:|
| THOM | CH | rearing | 209.5 | 195.5 | +7.2 |
| THOM | CO | rearing | 215.1 | 201.0 | +7.0 |
| MFRA | CH | rearing | 104.1 | 98.0 | +6.2 |
| REVL | WCT | rearing_stream | 221.3 | 235.3 | -5.9 |

These are within the range where bcfp-side staleness is plausible — bcfp tunnel rebuilds Tuesdays around 19:00-23:00 PDT, so the reference may not have picked up recent override changes for these WSGs. Not yet traced. **Open follow-up.**

## link#152 closure — PARS BT cross-WSG specifically

The link#152 acceptance bar was PARS BT mapping_code parity ≥99% (was 60.64% pre-152). Validated 2026-05-11: PARS BT mapping_code parity now **98.63%** (linked to PCEA + UPCE dam barriers via FWA-topology walks across WSG boundaries).

In this provincial-rollup view, PARS BT habitat rollup shows BT spawning +0.8%, rearing -0.9%, rearing_stream -1.3% — within the normal spread of any WSG. The cross-WSG fix held under provincial-scale exercise; no novel PARS-specific divergence emerged.

## link#157 — known-empty WSGs no longer dispatched

15 WSGs carry only ct/dv/gr/rb species (Yukon/Mackenzie-bound or coastal-cutthroat-only). bcfishpass bundle classifies only BT/CH/CM/CO/PK/SK/ST/WCT — so these WSGs error out 30-80s into the run with `No species resolved for AOI`. Filed 2026-05-11 as **link#157**, fixed in 8f8c7b6 (dispatch filter narrowed to `cfg$species`).

Excluded from provincial dispatch:

| WSG | Flagged species | Note |
|---|---|---|
| ATLL | dv, gr, rb | |
| BRID | ct, rb | Falls 20807 |
| CHUK | dv | No target species observations |
| GRNL | rb | No target species observations |
| KAKC | rb | Not accessible to target species |
| KUSR | dv, gr | No target species observations |
| LEUT | rb | Kenny Dam |
| LFRT | gr, rb | Mackenzie basin |
| LKEC | dv, gr | Mackenzie basin |
| LNRS | ct, rb | |
| MURT | rb | |
| MUSK | dv, rb | |
| PITR | dv, rb | No target species observations |
| UISR | dv, rb | Forrest Kerr Generating Station |
| UPET | gr, rb | Mackenzie basin |

These WSGs would be dispatched and classified correctly by the **default bundle** (which models ct/dv/gr/rb).

## Intentional divergences — enumerated

For clarity, the divergences below are choices, not defects:

1. **`rear_stream_order_bypass = no` for all bcfp-bundle species.** bcfp credits order-1 tribs of order-5+ mainstems as rearing without channel-width check. fresh has no clean implementation (fresh#158 deferred); link's bundle correctly declines to fake it. Cost: -5 to -9% rearing_stream on HORS/CLRH/COLR/KHOR.
2. **SK lake clustering uses fresh's current single-lake gate.** fresh#190 (multi-lake topology) parked, fresh#191 (lake-adjacency knob) filed. Cost: 8-85% divergence on SK-bearing WSGs (Class C).
3. **Lake / wetland rearing measurement asymmetry.** link credits centerline km (`rearing_lake_centerline`, `rearing_wetland_centerline`) AND polygon ha (`lake_rearing`, `wetland_rearing`) as SEPARATE outputs; bcfp credits only one or the other depending on species rule. The `-100%` rows in rollup output are this asymmetry. See `research/default_vs_bcfishpass.md`.
4. **bcfp `subsurfaceflow` table assumed current.** If bcfp's tunnel hasn't refreshed since override updates, link looks "wrong" but is correct (Class A).
5. **15 known-empty WSGs skipped (link#157).** Dispatch-time filter; no classification attempt for WSGs without bundle species.

## Unexplained divergences — open follow-ups

1. **BBAR CH/CO +12% rearing** (Class D survivor). Needs segment-level trace.
2. **THOM CH/CO +7% rearing, MFRA CH +6% rearing, REVL WCT -6% rearing_stream.** New since 2026-05-01. Investigate whether bcfp tunnel is stale on these.
3. **Class C SK new-geographies** — each WSG still needs individual stale-bcfp vs link-methodology-divergence classification.

## Reproduction recipe

```bash
# 1. Bring up cypher (if down)
cd ~/Projects/repo/rtj/scripts/cypher
./cypher_up.sh
./cypher_restore-fwapg.sh fwapg-<latest>.dump

# 2. Verify M1 + cypher have link + fresh installed at expected versions
ssh m1 'Rscript -e "packageVersion(\"link\"); packageVersion(\"fresh\")"'
ssh cypher 'Rscript -e "packageVersion(\"link\"); packageVersion(\"fresh\")"'

# 3. Ship local-only datasets to M1 + cypher (one-time per snapshot refresh)
for HOST in m1 cypher@24.144.70.121; do
  pg_dump "postgresql://postgres:postgres@localhost:5432/fwapg" --schema=cabd --no-owner --no-privileges \
    | ssh "$HOST" "docker exec -i fresh-db psql -U postgres fwapg"
  pg_dump "postgresql://postgres:postgres@localhost:5432/fwapg" --table=whse_fish.pscis_assessment_svw --no-owner --no-privileges \
    | ssh "$HOST" "docker exec -i fresh-db psql -U postgres fwapg"
  pg_dump "postgresql://postgres:postgres@localhost:5432/fwapg" --table=fresh.modelled_stream_crossings --no-owner --no-privileges \
    | ssh "$HOST" "docker exec -i fresh-db psql -U postgres fwapg"
done

# 4. Compute LPT-balanced buckets
Rscript data-raw/balance_provincial_buckets.R
# Copy the --m4-bucket= / --m1-bucket= / --cy-bucket= overrides into the next step

# 5. Dispatch
cd data-raw && ./trifecta_provincial.sh --m4-bucket=... --m1-bucket=... --cy-bucket=...

# 6. After completion: consolidate per-host RDS files (auto-pulled by trifecta script)
# 7. Aggregate: source /tmp/summary.R-style script over data-raw/logs/provincial_parity/*.rds
```

Wall: ~2 hours with current LPT factors (M4=1.0, M1=0.83, cy=1.83). Each provincial run produces this doc's headline numbers — drift from these stats is the diagnostic signal for changes in link, fresh, or bcfp.

## Files

- Trifecta orchestrator log: `data-raw/logs/202605112010_trifecta_provincial_orchestrator.txt`
- Per-host run logs: `data-raw/logs/202605112010_trifecta_provincial_{m4,m1,cypher}.txt`
- Per-WSG timing CSVs: `data-raw/logs/provincial_parity/20260511_2010_{m4,m1,cy}_per_wsg_times.csv`
- Per-WSG rollup RDS: `data-raw/logs/provincial_parity/<WSG>.rds`
- Aggregate summary: `/tmp/provincial_summary.rds` (regenerate via `/tmp/summary.R`)

## Cross-refs

- `research/provincial_parity_2026_05_01.md` — prior single-host baseline; Class A/B/C/D taxonomy
- `research/bcfishpass_methodology.md` — canonical bcfp methodology reference
- `research/bcfp_compare_mapping_code.md` — per-segment mapping_code parity (cross-WSG #152 closure detail)
- `research/default_vs_bcfishpass.md` — bundle methodology differences
- `research/dimensions_audit.md` — per-column dimensions audit
- link#152 (closed, v0.35.0) — unified province-wide barriers
- link#154 (closed, v0.34.0) — PSCIS-to-modelled crossings bcfp-shape composition
- link#157 (open, fixed in 8f8c7b6 on main) — dispatch-filter bundle species
- link#53 (open) — distributed work coordination (this run beat the 4h55m baseline by 3h)
- link#152 / link#154 likely closed Class D over-credits on TWAC/STHM/BULL/COWN — confirmed in this run
- fresh#158 (deferred) — stream_order_parent rear bypass
- fresh#190 (parked) — multi-lake topology
- fresh#191 (filed) — lake-adjacency knob

## Next

1. **BBAR CH/CO +12%** — only un-closed Class D row. Segment-level trace.
2. **New small divergences (THOM CH/CO, MFRA CH, REVL WCT)** — check bcfp tunnel refresh status for these WSGs.
3. **Class C SK rows** — individual WSG classification (stale-bcfp vs methodology vs fresh-bug).
4. **link#53 (distributed work)** — current run already at ~2 hr; further gains would require cypher swap to a faster droplet class or co-locating closer to S3.

## Addendum (2026-05-11, 23:30 PDT) — link#158 closure of token2 NONE→MODELLED

Segment-level trace of BBAR + THOM (after the headline rollup above) revealed the dominant residual divergence across the province: link's `<schema>.barriers_anthropogenic_unified` set under-emits **modelled crossings** by 3.7% in BBAR / 12.6% in THOM vs bcfp's `barriers_anthropogenic`. Mechanism: `.lnk_crossings_union`'s Phase 1.5 modelled-branch filter `(cf.structure IS NULL OR cf.structure = 'OBS')` dropped rows where `crossing_fixes.structure = ''` (empty string from CSV load), because `IS NULL` returns FALSE for empty strings.

This explained the consistent `ACCESS;NONE | ACCESS;MODELLED` pattern in mapping_code parity (link sees no downstream barrier where bcfp sees a modelled crossing).

**MODELLED is informational** — it tells you "there's a modelled crossing downstream — field-verify whether it's a barrier" — not a passability claim. Losing it loses operational signal even when access classification stays right.

Fix shipped on main as `4ca6970` (link#158, `NULLIF(cf.structure, '') IS NULL OR cf.structure = 'OBS'`). Verified BBAR + THOM segment-level parity:

| WSG | sp | Pre-#158 | Post-#158 |
|---|---|---:|---:|
| BBAR | bt | 99.79% | **99.97%** |
| BBAR | ch/cm/co/pk/sk | 99.90-99.91% | **99.99-100%** |
| THOM | bt | **95.10%** | **99.97%** (closed 1106/1112 diffs) |
| THOM | st | 97.44% | **99.98%** (closed 575/581) |
| THOM | ch/cm/co/pk/sk | 99.47-99.55% | **99.93-100%** |

Full provincial mapping_code re-run not yet executed but the pattern was uniform across the 10 WSGs of the Phase A run plus BBAR + THOM, so expect similar gap-closure on every WSG that has modelled crossings with `''` structure-fix entries. Provincial rollup-level numbers in this doc's headline table are unchanged because token2 NONE↔MODELLED swaps don't affect linear-sum aggregates.

**Unexplained-divergences list now empty for token2 mechanism.** Remaining residual divergences (Class C SK new-geographies, fresh#158 stream-order bypass, BBAR CH/CO +12% rearing) are still open per the prior taxonomy, but the mapping_code-level signal is now ≥99.9% on every species in BBAR + THOM.
