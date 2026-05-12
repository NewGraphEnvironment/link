# Findings — lnk_compare_wsg + provincial parity annotated CSV (#162)

## Issue context

## Problem

Today we have three disjoint sources of "why does this WSG-species-metric diverge from bcfp":

1. `research/provincial_parity_2026_05_01.md` (Class A/B/C/D taxonomy, narrative)
2. `research/bcfp_compare_mapping_code.md` (Phase A per-segment, 4-WSG sample)
3. ~12 PR bodies + issue threads + commit messages (closing each class)

Every time a divergence surfaces during a provincial run, we manually re-derive whether it's already known. The next-WSG investigation often duplicates the BBAR/THOM trace from #158 just to find the same answer.

There is no single artifact a future-us (or anyone) can look at and say: "this BBAR CH +12% rearing — what class is it, what's known, where's the next step." We rediscover.

## Goal

One CSV per provincial run: every (wsg, species, metric) row annotated against a canonical taxonomy. Zero rows ≥2% divergence end up "unexplained" — either they map to a known class with a citation, or they're flagged "needs investigation" with a clear hand-off.

## Output shape

`data-raw/logs/provincial_parity/<TS>_annotated.csv`:

```
wsg, species, metric, unit,
  link_value, bcfp_value, diff_pct,           # rollup lens
  mc_match_pct, mc_n_diffs, mc_top_pattern,   # mapping_code lens (NULL if not run)
  class,                                       # A | B | C | D | MEASUREMENT_ASYMMETRY |
                                               # TOKEN2_RESIDUAL | INTENTIONAL | UNEXPLAINED
  mechanism_ref,                               # link#158, fresh#158, research/<doc>.md, ...
  status,                                      # CLOSED | INTENTIONAL | OPEN | NEEDS_INVESTIGATION
  notes
```

## Single source of truth

`research/bcfp_divergence_taxonomy.yml` — a keyed lookup of every known divergence pattern. Each PR / issue that surfaces a new pattern updates THIS file. The annotation script joins provincial-run output to it.

Example entries:

```yaml
SETN:
  species: all-anadromous
  metric: rearing_stream
  pattern: link > bcfp by 50-200%
  class: A
  mechanism: bcfp barriers_subsurfaceflow stale
  refs: [research/provincial_parity_2026_05_01.md#class-a]
  status: INTENTIONAL  # link correct; awaiting upstream refresh

HORS:
  species: BT
  metric: rearing_stream
  pattern: link < bcfp by 5-9%
  class: B
  mechanism: fresh#158 stream_order_parent rear bypass not implemented
  refs: [fresh#158, research/dimensions_audit.md]
  status: INTENTIONAL  # methodology choice

"*":
  species: "*"
  metric: lake_rearing | wetland_rearing
  pattern: link == 0, bcfp > 0 (diff_pct == -100)
  class: MEASUREMENT_ASYMMETRY
  mechanism: link credits centerline km vs bcfp polygon ha
  refs: [research/default_vs_bcfishpass.md]
  status: INTENTIONAL
```

## Scope — what gets built

1. **`R/lnk_compare_wsg.R` — NEW exported function.** Signature: `lnk_compare_wsg(conn, aoi, cfg, loaded, reference = "bcfishpass", with_mapping_code = FALSE)`. Per-WSG convenience wrapper around the `lnk_pipeline_*` phases + reference queries. Returns a list with `rollup` (linear sums per species) AND optionally `mapping_code` (per-species segment match stats). The `reference` arg leaves room for future non-bcfp comparisons (default-bundle parity, regression detection, federal sources). Initial implementation handles `reference = "bcfishpass"` only.

2. **`data-raw/compare_bcfishpass_wsg.R` — refactor.** Becomes a thin per-WSG orchestrator that calls `lnk_compare_wsg(reference = "bcfishpass")` and persists the RDS. New optional arg `--with-mapping-code`.

3. **`data-raw/compare_bcfp_mapping_code.R` — DELETE.** Its logic moves into `lnk_compare_wsg()` (gated by `with_mapping_code = TRUE`).

4. **`research/bcfp_divergence_taxonomy.yml` — NEW.** Initial population captures every Class A/B/C/D row from `research/provincial_parity_2026_05_01.md` plus MEASUREMENT_ASYMMETRY + TOKEN2_RESIDUAL patterns from `research/provincial_parity_2026_05_11.md`.

5. **`data-raw/annotate_provincial_parity.R` — NEW.** Reads `data-raw/logs/provincial_parity/<TS>*.rds` + the taxonomy, emits the annotated CSV.

6. **`data-raw/trifecta_provincial.sh` — extended.** New `--with-mapping-code` flag (default off for fast runs). Pre-flight check that all 5 hosts (3 cyphers + M4 + M1) are ready. Support `--workspace job1,job2,job3` style for the 3-cypher fan-out.

## Cleanups bundled

- `data-raw/balance_provincial_buckets.R` — dedup bug (yesterday I worked around by writing inline LPT; should land in the canonical script)
- `data-raw/consolidate_schema.R` — `ok=FALSE` false-positive on cypher restores; also need bucket-aware destination cleanup so `streams_habitat_<sp>` pg_restore doesn't dup-key collide. See 2026-05-12 addendum in `research/provincial_parity_2026_05_11.md`.
- Stale `_per_wsg_times.csv` discovery pattern — currently picks up old logs from 2026-05-08 unless you manually rename. Move to an archive convention so only the latest run feeds the LPT.

## Out of scope (separate issues if they come up)

- fresh-side changes (fresh#158 stream-order bypass, fresh#190/191 SK new-geographies) — bake them into the taxonomy with `status: INTENTIONAL_FRESH_DEFERRED` for now.
- Cypher infra (rtj#129 closed; if a different infra issue surfaces, file separately in rtj).
- Default bundle parity — same machinery should work but defer to a follow-up after bcfishpass bundle reaches "zero unexplained".

## Acceptance

- [ ] Provincial run with `--with-mapping-code` finishes in ≤90 min on 5 hosts (3 cyphers + M4 + M1)
- [ ] Annotated CSV contains all 217 WSGs × 8 species × N metrics
- [ ] **Zero rows with `abs(diff_pct) >= 2` AND `class == UNEXPLAINED`** (every ≥2% divergence has either a class label or a "needs_investigation" hand-off)
- [ ] `research/bcfp_divergence_taxonomy.yml` is the only place we record new patterns going forward
- [ ] Runbook (`research/provincial_run_runbook.md`) updated: the CSV is the primary deliverable; existing rollup/mapping_code compare outputs become diagnostic detail

