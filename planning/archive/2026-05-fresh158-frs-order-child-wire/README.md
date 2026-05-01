## Outcome

Wired `fresh::frs_order_child` (fresh#158) into the link pipeline as parametric link methodology — small streams plugging directly into large rivers can be credited as rearing despite low/missing FWA channel-width estimates. Four new per-species columns in `dimensions.csv` (`rear_stream_order_bypass`, `rear_stream_order_parent_min`, `rear_stream_order_child_min`, `rear_stream_order_child_max`, `rear_stream_order_distance_max`); rules.yaml emission; pipeline call gated on bypass=yes; xref doc updated. Both bundles ship `bypass: no` — infrastructure is parametric and tested but disabled by default.

Verified 4-WSG regression (HARR/HORS/LFRA/BABL) byte-identical to pre-wire baseline with bypass=off — wiring is purely additive when disabled.

**Methodology decision parked.** Whether to enable bypass-on as link's default (and at what dimensions, e.g. `child_max=1` for bcfp parity vs `child_max=5` for biology widening), and what `distance_max` value to ship — pending wider WSG sample inspection (BABL per fresh#158) before any user-facing rollout.

Closed by: PR #97 → link v0.22.0 (commit 73712ce). fresh patches: 0.27.1, 0.27.3, 0.27.4, 0.27.5. Canonical design: [fresh#158](https://github.com/NewGraphEnvironment/fresh/issues/158).
