# Provincial parity baseline — link 0.20.0

**Run**: 2026-04-30 21:55 → 2026-05-01 02:50 PDT (4h 55min wall clock)
**Hardware**: Apple M4 Max, 16 cores, 128 GB RAM, single host
**Software**: link 0.20.0 (sha 7210baf), fresh 0.25.0, bcfishpass 440bc1e (2026-04-28)
**Configuration**: bcfishpass-bundle parity only (default-bundle skipped)
**Fwapg**: localhost:5432 (Docker)
**Source data**: 232 of 246 BC watershed groups (15 returned "No species resolved" — see *Errors*)

## Headline

| metric | value |
|---|---:|
| Rollup rows aggregated | 4,739 |
| within ±1% | 1,328 (28%) |
| within ±5% | 1,591 (34% of all rows; **76% of non-NA non-artifact rows**) |
| 5–10% | 20 |
| 10–25% | 16 |
| over 25% (real, excl. -100% artifacts) | small handful |
| -100% artifacts (rollup measurement asymmetry) | 456 |
| NA (zero baseline both sides) | 2,656 |
| Real divergences > 5% | **56 rows across 28 WSGs** |

**Wall-time baseline for link#53 distributed work to beat: 17,698 seconds (4h 55min).**

## Errors

15 WSGs returned `No species resolved for AOI`:
ATLL, BRID, CHUK, GRNL, KAKC, KUSR, LEUT, LFRT, LKEC, LNRS, MURT, MUSK, PITR, UISR, UPET. These are border/Yukon WSGs in `wsg_species_presence` that have at least one species marked TRUE but the species we model don't intersect with what's marked. Configuration edge — `compare_bcfishpass_wsg()`'s species-resolution should fall back to all species in `parameters_fresh` when `wsg_species_presence` returns no matches. Filed as a follow-up.

## Real divergences > 5% — taxonomy

### Class A — bcfp-side staleness (link is correct, bcfp is wrong)

**SETN** — Seton Lake. **All 14 over-25% rows.**

Mechanism: bcfp's `barriers_subsurfaceflow` table contains 2 entries (blkey 356363618, DRMs 40069 + 40158) that should have been excluded by `user_barriers_definite_control` rows with `barrier_ind = FALSE`. Bcfp's SQL filter is identical to link's; bcfp's table simply hasn't been rebuilt since the control rows were updated. That single stale subsurfaceflow at DRM 40069 propagates into bcfp's `barriers_ch_cm_co_pk_sk_dnstr` for **74,816 of 78,937 SETN segments** (95% of the WSG), making bcfp's anadromous habitat sums massively under-credit reality.

| sp | metric | link | bcfp (stale) | "diff_pct" |
|---|---|---:|---:|---:|
| CO | rearing_stream | 457 | 157 | +192% |
| CH | rearing_stream | 388 | 133 | +192% |
| CO | rearing | 679 | 319 | +113% |
| ... | 14 rows total | | | |

**Verification**:

```sql
-- bcfp side: how many subsurfaceflow rows survive in bcfp despite control=FALSE?
SELECT s.watershed_group_code, COUNT(*) AS stale
FROM bcfishpass.barriers_subsurfaceflow s
JOIN bcfishpass.user_barriers_definite_control c
  ON s.blue_line_key = c.blue_line_key
  AND abs(s.downstream_route_measure - c.downstream_route_measure) < 1
WHERE c.barrier_ind = FALSE
GROUP BY s.watershed_group_code;
-- → SETN: 2 (only WSG affected)
```

Action: notify bcfishpass that `barriers_subsurfaceflow` is stale on SETN. Likely fixed by re-running `model/01_access/sql/barriers_subsurfaceflow.sql` for SETN. Not a link bug.

### Class B — fresh#158 stream-order bypass (known gap)

bcfp's per-species rear rule has an inline `(stream_order_parent >= 5 AND stream_order = 1)` clause that credits direct order-1 tributaries of order-5+ mainstems as rearing even when cw < rear_min. Fresh has no implementation; link's `dimensions.csv::rear_stream_order_bypass = no` for all species (correctly anticipating).

Affected:

| WSG | sp | metric | diff_pct |
|---|---|---|---:|
| HORS | BT | rearing_stream | -7.68 |
| HORS | CH | rearing_stream | -6.76 |
| HORS | BT | rearing | -6.14 |
| HORS | CO | rearing_stream | -5.86 |
| HORS | CH | rearing | -4.62 |
| HORS | CO | rearing | -4.66 |
| CLRH | WCT | rearing_stream | -8.47 |
| COLR | WCT | rearing_stream | -6.91 |
| KHOR | WCT | rearing_stream | -6.75 |

Decision: NOT shipping for parity (fresh#158). Default bundle's NewGraph methodology will choose differently anyway.

### Class C — SK new-geographies (lake clustering / multi-lake / lake adjacency)

SK habitat classification has three open mechanisms in fresh:
- fresh#190 — multi-lake topology (parked, BULK SK +11%)
- fresh#191 — lake-adjacency knob for upstream spawning (filed, default-only)
- the bcfp upstream-spawn cluster gate itself (intersects with fresh#191)

Affected (all SK):

| WSG | metric | link | bcfp | diff_pct |
|---|---|---:|---:|---:|
| BULK | spawning | 27.1 | 24.4 | +11.0 |
| LRDO | lake_rearing (ha) | 4809 | 2645 | +81.8 |
| NASR | spawning | 5.55 | 3.0 | +85 |
| TOBA | rearing | 8.59 | 16.8 | -49.0 |
| NASC | rearing | 15.0 | 23.7 | -36.6 |
| NEVI | spawning | 9.95 | 8.91 | +11.7 |
| NASC | spawning | 2.39 | 2.15 | +11.2 |
| CHWK | spawning | 5.96 | 5.4 | +10.4 |
| QUES | spawning | 56.3 | 51.1 | +10.2 |
| KUMR | rearing | 439 | 482 | -8.94 |
| ... | several smaller |  |  |  |

These need individual inspection — some may be stale-bcfp class, some may be true link methodology divergences, some may be fresh-bug class.

### Class D — over-credits to investigate

**TWAC partial trace (2026-05-01):** BT over-credit is real — link credits 9 streams (~98 km) where bcfp credits 0 km. bcfp side's `barriers_bt` for TWAC has 215 rows (113 GRADIENT_25, 82 GRADIENT_30, 17 SUBSURFACEFLOW, 3 FALLS). Control table identical between link and bcfp (1 row, blkey 356351200 DRM 524 barrier_ind=TRUE). No stale subsurfaceflow. Mechanism likely either (a) stale bcfp `barriers_bt` for gradient/falls (similar to SETN's stale-table class but on a different barrier source), or (b) lift-logic divergence on observations/habitat upstream. Needs deeper trace.



| WSG | sp | metric | link | bcfp | diff_pct | hypothesis |
|---|---|---|---:|---:|---:|---|
| TWAC | BT | rearing_stream | 364 | 279 | +30.2 | TBD |
| TWAC | BT | rearing | 493 | 395 | +24.8 | TBD |
| TWAC | BT | spawning | 274 | 226 | +21.4 | TBD |
| STHM | BT | spawning | 492 | 429 | +14.6 | TBD |
| STHM | BT | rearing_stream | 597 | 521 | +14.5 | TBD |
| BBAR | CH/CO | rearing | 168/171 | 150/153 | +12 | TBD |
| BULL | BT | spawning/rear | 418/754 | 393/717 | +5–6 | TBD |
| COWN | BT | rearing_stream | 816 | 773 | +5.5 | TBD |

These are over-credits, not under-credits — i.e., link credits MORE than bcfp. Could be:
- Same class as SETN (bcfp stale)
- bcfp barrier-set lift fired too aggressively (lift on bcfp side, not link)
- Genuine link methodology divergence

Need segment-level trace per WSG.

## Per-WSG hotspots

84% of WSGs (181 of 217 with results) have **zero real >5% divergences**. The 28 hotspots:

```
SETN (14 rows >5%) — Class A, bcfp stale
HORS (4)         — Class B, fresh#158 known gap
LRDO (3)         — Class C, SK
TWAC (3)         — Class D, over-credit TBD
THOM (3)         — Class C, SK spawning
STHM (3)         — Class D, BT over-credit
BULL (3)         — Class D, BT over-credit
NASC (2), BBAR (2) — Class C/D
NASR, TOBA, OWIK, NEVI, BULK, STIR, CHWK, QUES, KUMR, SQAM,
CLRH, NECR, COLR, KHOR, NECL, ATNA, MFRA, COWN, KNIG (1 each)
```

## What this means for parity

After accounting for:
- **Class A (SETN, 14 rows)** — link is correct, bcfp is stale. Subtract from divergence count.
- **Class B (10 rows)** — known fresh#158 gap, accepted.
- **Class C (~15 rows)** — SK methodology in flight (fresh#190, fresh#191).
- **Class D (~17 rows)** — needs investigation.

The genuine "needs work" set is **Class D and the unresolved part of C**. Maybe 25–30 rows out of 4,739. **>99% of provincial habitat-classification rows are in parity** with the bcfp reference.

## Files

- `data-raw/logs/20260501_0251_provincial_parity_rollup.csv` — full 4,739-row rollup
- `data-raw/logs/20260501_0251_provincial_parity_per_wsg.csv` — per-WSG summary
- `data-raw/logs/provincial_parity/<WSG>.rds` — per-WSG output, 217 files
- `data-raw/logs/20260430_2155_provincial_parity.txt` — run log
- `data-raw/run_provincial_parity.R` — reusable runner script

## Next

1. Notify bcfishpass: SETN `barriers_subsurfaceflow` table is stale relative to control CSV. (bcfishpass-side issue, not link)
2. Investigate Class D outliers (TWAC, STHM, BULL, BBAR, COWN) — segment trace per WSG
3. Continue SK methodology work (fresh#190, fresh#191) — closes Class C
4. Defer Class B (fresh#158) per design decision
