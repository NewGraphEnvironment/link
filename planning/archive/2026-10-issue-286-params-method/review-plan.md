# Plan review — #286 (Plan agent, 2026-10-01)

Read-only agent; findings arrived as reply text and are recorded here by the parent.
Triage and dispositions are in findings.md, "Plan review triage".

- **B1 (Blocker):** the provenance `source: https://github.com/smnorris/bcfishpass` puts the method CSV under weekly csv-sync (`data-raw/sync_bcfishpass_csvs.R:121-122`, an exact match on source). Byte drift auto-merges, so a ng-prod `cw`→`mad` flip would land unreviewed, and only in `bcfishpass` + `default` (`:251-260`). Freeze it the way the thresholds are frozen (non-bcfp `source` + `derived_from`). upstream_sha should be `1fae4ea` (last touch) vs the HEAD `f8db4b9` that was recorded.
- **G1:** stale docs once mad is live: `dictionary_parameters_habitat_thresholds.csv` `*_mad_*` rows ("no effect on link runs"); RUNBOOK §7; CLAUDE.md:78-79; bundle README file tables.
- **G2:** `.lnk_input_primitives()` (`R/lnk_log.R:186-216`) does not fingerprint `fwa_stream_networks_discharge`.
- **G3:** the `frs_order_child` stream-order bypass in classify runs regardless of model; bcfp applies it only in the cw branch (`load_habitat_linear_co.sql:97-110`). Latent: all shipped bundles have `rear_stream_order_bypass = no`.
- **G4:** connect: `.frs_connected_waterbody` phase 3 reads `s.channel_width >= spawn_connected$channel_width_min` (fresh `R/frs_habitat.R:1643-1646`). Inert (0 for SK/KO everywhere); conclusion holds but the reason needs to be precise.
- **G5:** no test pins the discharge join args, or that `cols_streams` excludes `mad_m3s`.
- **G6:** no cross-package test of dictionary columns vs fresh's method CSV header.
- **G7:** `audit_configs.R` has no method-table section.
- **G8:** follow-up draft should note that persist has no `mad_m3s`, and the stale v0.33.0 rationale (already fixed in Phase 1).
- **O1:** the no-change proof isolates neither the mad_m3s column nor the fresh 0.33.0→0.36.2 bump. Run HEAD classify under fresh 0.33.0 (separate libpath) and 0.36.2, then branch: A0 = A = B.
- **O2:** a thin bundle extending `default` inherits `pipeline.schema: fresh`; do the mad check via `method_csv` on a scratch schema. No-change before mad on the same schema.
- **O3:** Phase 1 checkboxes. Already flipped in commit bd2f8ff (the review read a pre-commit tree).
- **O4:** cyphers need re-prep onto fresh >= 0.35 before the next dispatch; the preflight hard-fails otherwise. Put this in NEWS + RUNBOOK.
- **A1–A8:** checked. 188 vs 187 (PINE plus quoting); discharge 150 groups by row presence vs 123 in fresh NEWS (pick a WSG by non-NULL share); `loaded$parameters_habitat_method` is read but unused, while classify re-reads the path (document); the join fails on a DB without the discharge table (cw groups too); mad_m3s survives breaks and does not leak to persist; verify requires `checksum`; every base bundle's config_hash changes; no existing tests break.
- **S1–S3:** no other call site needs params_method (`data-raw/compare_adms.R` frs_habitat is legacy all-cw); the validate follow-up is correctly deferred; no `.lnk_fresh_required()` change.
- **AC1:** the overlay contaminates "BT gets no stream habitat"; measure before overlay/connect, overlay off, stream segments only.
- **AC2:** replace "differs from cw" with invariants: every stream spawn/rear segment has mad_m3s within [min, max]; no NULL-mad segment is stream habitat.
- **AC3:** BULK mad: zero stream spawn/rear for every species, overlay off; lake/wetland may be non-zero.
- **AC4:** loop test asserting `lnk_config_verify` is clean for every shipped bundle.
- **AC5:** a per-species digest after connect, with the same query on both sides.
