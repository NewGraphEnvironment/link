# species_pooling_290: DV and BT naming, and the pooling sensitivity (link#290)

Produced by `data-raw/species_pooling_evidence.R --validate` on local docker fwapg (bcfishobs 373,050 rows). The write-up is [`research/species_pooling.md`](../../../../research/species_pooling.md).

| File | What it holds |
|---|---|
| `decade_region.csv` | BT and DV records (releases removed) by region x decade |
| `dv_streams_resampled.csv` | Streams with a DV record, and what happened to each: later recorded as BT, not sampled after 1995, or sampled after 1995 with DV only |
| `wsg_dv_share.csv` | BT and DV records per WSG, before 1995 and from 1995 on |
| `scenarios.csv` | The #284 BT thresholds under S0 (current tracker), S1 (Skeena above Hazelton only), S2 (no Skeena), S3 (interior, pre-1995 DV only) and BT records only |
| `scenarios_dropped.csv` | DV evidence rows each scenario drops, by WSG |
| `validate_scenarios.csv` | BT capture under S0 (the committed #283 baseline), S1 and S2 |
| `fig_*.png` | The figures and maps used in the research doc and the walkthrough page |

S0–S2 run through `query_habitat_thresholds_obs.R` with scratch bundles. S3 is computed from the S0 evidence by the same rule, and the script stops unless that computation reproduces the producer for S0–S2.
