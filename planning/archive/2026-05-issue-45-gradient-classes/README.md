## Outcome

Two coupled hardcodes in `R/lnk_pipeline_prepare.R` exposed as configurable: the gradient class break vector (`classes` arg + `cfg$pipeline$gradient_classes` knob) and the per-model class filter list (now per-species derivation from `loaded$parameters_fresh$access_gradient_max`). Bit-identical bcfishpass parity preserved by default — verified on ADMS / HARR / BABL / BULK with matching digests against pre-#45 baseline. End-to-end override demonstrated: dropping 0.25 break on ADMS expands BT habitat ~30% (+199 km rearing) as expected, CH/CO/SK at 0.15 unchanged.

Mid-implementation correction: initial Phase 1 used `lnk_pipeline_species()` which intersects `cfg$species` with WSG presence — caused -0.6 km drift on ADMS because WSGs without ST/WCT presence flags lost ST/WCT-class break positions from `gradient_barriers_minimal`. Fix: use `cfg$species %||% loaded$parameters_fresh$species_code` directly. The break network is AOI-agnostic; presence filter applies at classify/connect time. Caught by single-WSG DB regression before scaling up.

Plan-agent review caught 3 fragile findings round 1: empty species set → schema-valid empty table fallback; defensive `sp_amax[1L]` against R 4.3+ length-1 enforcement on `||`; `.lnk_validate_identifier` on lowercased species codes before SQL interpolation.

Closed by: PR [#114](https://github.com/NewGraphEnvironment/link/pull/114) (squash `898c7b4`), v0.27.0. Follow-up filed: [#115](https://github.com/NewGraphEnvironment/link/issues/115) (auto-derive default from `parameters_fresh$access_gradient_max`).
