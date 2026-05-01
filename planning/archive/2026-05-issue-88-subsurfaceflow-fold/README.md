## Outcome

Folded `prep_subsurfaceflow` into `prep_natural` so subsurfaceflow positions enter the per-species observation/habitat lift via `<schema>.natural_barriers` (gated on `cfg$pipeline$break_order`). Restores bcfp parity for blkey 356286055 BT rearing on HARR (0 → 6.509 km). HARR full-WSG diffs collapsed: rearing_stream −10.4% → −4.19%, rearing −1.84%, spawning −1.6%. 15-WSG `tar_make` 33/33 across both bundles, 53m. Reproducibility verified — second `tar_make` byte-identical (`link_value` digest `5a641892b82604259b0ba168ea093661`, 0/1057 rows differ). Default-bundle bit-identical vs pre-fix (0/581 rows changed). HORS −7.68% BT residual confirmed as a separate mechanism (parent-stream-order/child-order rearing bypass — fresh#158 / link#96).

Closed by: PR #89 (merged into link v0.20.0 release commit `d8566d2`).
