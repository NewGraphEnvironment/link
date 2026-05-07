## Outcome

`lnk_pipeline_access()` computes `dam_dnstr_ind` and (optionally, via `crossings_table`) `remediated_dnstr_ind` from the same primitives that drive the per-species access codes. This eliminates the bcfp pre-computed-indicator merge-in step that 0.30.0 needed for full BT/WCT mapping_code parity. ADMS validation: `dam_dnstr_ind` byte-identical to bcfp (11803/3960, zero off-diagonal); `mapping_code_<sp>` 100% on absent/anadromous species, divergence on BT/CH/CM/CO/PK/SK is exclusively the documented bcfp v0.7.0 REMEDIATED regression. Filed [smnorris/bcfishpass#891](https://github.com/smnorris/bcfishpass/issues/891) + [smnorris/bcfishpass#892](https://github.com/smnorris/bcfishpass/pull/892) one-line upstream fix. Once that lands, both outputs reconverge.

Closed by: PR #136 (TBD), tag v0.30.1.
