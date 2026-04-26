# PR #58 — v0.10.0 spawn edge_types tightening

**Outcome:** default config switched from categorical `[stream, canal]`
edge types (which expanded to FWA codes `1000/1050/1100/1150/2000/2100/2300`)
to explicit `[1000, 1100, 2000, 2300]`, matching bcfishpass's 20-year-validated
convention. Drops `1050/1150` (stream-thru-wetland) and `2100`
(rare double-line canal) from spawn AND rear-stream rules. Dedicated
wetland-rearing rule (`edge_types_explicit: [1050, 1150]` with
`thresholds: false`) unchanged — `wetland_rearing` flag still captures
stream-thru-wetland segments for species with `rear_wetland = yes`.

**Verification:** 5-WSG run (18m 25s on M1, fresh 0.21.0) confirmed
spawning Δ = 0 km between default and bcfishpass bundles on every parity
species × WSG. ADMS spawn drops 4-7% across BT/CH/CO/SK/RB. Rearing flag
preserved for `rear_wetland=yes` species.

**Closing commit:** `4894046` (merge of PR #58)
**Tag:** `v0.10.0`
