# Study-area mapping_code parity — 2026-05-25

First tunnel-free, M1-dispatch, per-segment `mapping_code` parity across the 3
FWCP study areas (link#175). Run via `data-raw/study_area_run.sh`; procedure +
methodology in `research/study_area_run.md`.

## Run metadata

- **Scope:** 50 WSGs (29 focal + drainage closure, species-filtered) across
  Peace / Fraser / Skeena.
- **Hosts:** dispatcher = M1 (Fraser bucket), cy1 = Peace, cy2 = Skeena (2 DO
  cyphers, burned at end — confirmed 0 tofu resources / no droplets).
- **Reference:** local bcfp snapshot `fresh.streams_vw_bcfp` (tunnel-free);
  compare = `lnk_compare_mapping_code` per WSG-active species.
- **link:** branch `175-promote-with-mapping-code-flag-to-stand` @ `34b0cd3`.
- **Numbers are post-recompute** (see methodology) — M1's `fresh` holds the
  full consolidated + recomputed state; full table `/tmp/authoritative.csv`.

## Headline

| Metric | Value |
|---|---|
| Rows (WSG × active species) | 150 (50 WSGs × ~3 sp avg) |
| **Median match** | **99.66%** |
| Mean match | 99.11% |
| Rows ≥ 99% | 130 / 148 (88%) |
| Median BT | 99.57% |

## Genuine divergences (recompute-stable → taxonomy)

These did NOT improve on re-modelling against the full consolidated barrier set,
so they're real methodology departures (not cross-WSG accumulation gaps) — the
kind tracked in `research/bcfp_divergence_taxonomy.yml`:

| WSG | species | match% | likely class |
|---|---|---|---|
| UNRS | BT | 61.8% | Kenney reservoir / dam-override (CABD dam passability) |
| SETN | CH/CM/CO/PK/SK/ST | 93.7–94.8% | SK-geography / salmon class |

Next: `lnk_parity_annotate` against the taxonomy; the acceptance bar is 0
UNEXPLAINED at |diff|≥2% after annotation.

## Methodology finding (the load-bearing result)

Per-segment access (hence `mapping_code` token1/token2) depends on barriers
**downstream**, possibly in a different WSG (provincial-accumulation, RUNBOOK
§5). Distributed hosts see only their own bucket's barriers mid-run.

**Drainage-closed + DS-first per-host is NOT sufficient** — it reduces but
doesn't eliminate the gap (downstream barriers can be cross-bucket or arrive
late in DS-first order). Per-host this run produced FINA 75.5% / PARA 68.6% /
LFRA & LKEL low; all → 99%+ after **re-modelling on the full consolidated
barrier set**. So the correct, machine/WSG-agnostic methodology is:

**distribute (any bucketing) → consolidate → POST-CONSOLIDATE RECOMPUTE →
compare.** The recompute is the correctness guarantee; bucketing is only a
speed knob.

### Open efficiency issue (#205)

Today the recompute re-runs the **full pipeline** on diverged WSGs — ~2× cost
on those WSGs (re-derives streams/habitat just to redo the cheap access step),
and recompute-ALL would be ~2× overall (defeating distribution). **#205** is the
cheap access-only recompute (reuse persisted streams/habitat) that makes
recompute-ALL bulletproof and ~1×. Build it before the next run, then one clean
driver-automated run that is both validated and fast.
