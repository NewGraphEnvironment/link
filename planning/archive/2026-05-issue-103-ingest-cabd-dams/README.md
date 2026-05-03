## Outcome

Ingested CABD dams as a parallel reporting dimension (replicated bcfp's `load_dams.sql` against the `cabd.dams` source over the db_newgraph tunnel; output `<schema>.dams` mirroring `bcfishpass.dams` column-for-column). Architectural intent: link is sibling-of-bcfp under CABD, not downstream of bcfp's processed output. Habitat output is provably unchanged — HARR dams-ON / dams-OFF rollup is byte-identical to fp precision.

LFRA verification confirmed all 15 named dams (Stave Falls, Alouette, Ruskin, Coquitlam, Northwest Stave + Upper Stave variants, Cariboo, Sam Hill, Sparrow, Sharpe, Lamont, Cannell, Alam) match `bcfishpass.dams` byte-for-byte within fp precision.

Closed by: PR #105 (commit 3c062c6) → v0.24.0
