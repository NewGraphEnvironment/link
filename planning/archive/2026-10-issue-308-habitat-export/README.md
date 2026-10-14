## Outcome

link's habitat flags now export per config as Hive-partitioned Parquet with a manifest, on the
pattern wet#7 set for discharge:

- `lnk_scenario_export()` writes one long-form row per segment × config × species, keyed by FWA
  position. Each row carries the flags, the width / discharge / gradient values the build tested,
  their ratios to the build's *logged* thresholds, and `has_barriers_dnstr` from link's access table.
  The export also writes a write-once provenance tree: one entry per build, one per config hash,
  one per recompute, and the bundle files when today's bundle hashes the same.
- `lnk_catalog()` reads the manifest (local, https, or s3:// through the aws CLI, because
  `habitat/` is private).
- `lnk_db_load()` loads parts into `habitat.fwa_v1_segment` in one transaction, after checking md5s.
- `data-raw/habitat_publish.R` builds a tree and publishes it. PUBLISH was **not run**; it waits on
  the operator.

Four decisions departed from the plan, each made on evidence:

- **Provenance is keyed per finished build**, not per dispatch. A dispatch's rows depend on the
  export's width and on later log state.
- **Rows exist only for the species each group's build modelled.** A row of FALSE would conflate
  "not modelled" with "none found".
- **Groups are taken from whichever of a config's schemas holds a finished build.**
- **One judgement, `.lnk_manifest_regressions()`, decides for both BUILD and PUBLISH** whether a
  tree still covers what it would replace. It checks the config, group:species pairs, newer
  builds, recomputes, and newer exports with different parts.

The lesson was the review loop. Rounds 2–5 each found a defect inside the previous round's fix.
Round 3 named the mechanism: what one call or one root can see was stored as a property of the
build or the published config. Round 5 ended the loop by enumerating the 24 places that mechanism
reaches.

## Measurement

- **Pilot BUILD**, local fwapg:
  - Configs: `default` on its 5 logged groups and `bcfishpass` on 39.
  - Output: 22 parts, 9,876,720 rows, 218.9 MB, in about 1 min.
  - Reproducibility: a rebuild two hours and five commits later gave **byte-identical** parts.
- **Against `lnk_rollup_wsg()`**, 150 config × species × group rows:
  - spawning km: 0 differ;
  - rearing-flag km: 0 differ beyond the rollup's 0.01 km rounding;
  - km with no barrier downstream vs the rollup's `accessible_km`: 0 differ.
- **`accessible` and link's access table disagree everywhere**, so both are shipped:
  - All 150 rows have some segments flagged accessible with a barrier downstream: 24,467
    segments, 4,292 km over `accessible_km`.
  - The first diagnosis, staleness after the cross-group recompute (plan review G1), was only
    part of it. DUNC was never recomputed, yet 228 of its 229 such BT segments start exactly at a
    BT-blocking barrier: a boundary convention. Filed as #336.
- **Ratios are mostly NA today.** Only DUNC's build logged thresholds (`fresh_default`), and
  `fresh` has no thresholds log table at all. The manifest records `thresholds_logged`.
- **Position key uniqueness:** `(blue_line_key, downstream_route_measure)` has 0 duplicates in
  1.83 M `fresh_default` and 3.80 M `fresh` segments, so it is the loaded table's PK.
- **Wrong turns kept:**
  - The first BUILD crashed on `fresh.log`, which predates `discharge_fill`.
  - The verify rollups took about 75 min on `fresh`.
  - A verify rerun had its script edited mid-flight and was killed; the summary was redone from
    the completed CSV.
  - Code-check: 7 / 5 / 3 / 4 / 1 findings over five rounds, with a mutation table proving every
    guard (findings.md).

## Evidence

`data-raw/logs/habitat_export_308/` (build log, parts and runs CSVs, `verify.R` and its output).

Follow-ups: #331 (discharge from wet), #332 (GeoPackage), #333 (crate registration), #334 (publish
gates, versioning, public read), #335 (webmap), #336 (access boundary convention).

Closed by: PR for #308 (branch `308-lnk-scenario-export-publish-habitat-per`)
