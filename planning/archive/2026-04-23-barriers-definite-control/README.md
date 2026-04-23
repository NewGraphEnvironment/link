# #44 — barriers_definite_control wiring (closed)

PR #47 merged 2026-04-23 as link 0.6.0 (squash commit `8eda3fb`).

Wired `user_barriers_definite_control.csv` through `lnk_barrier_overrides()` at the observation-override step: TRUE control rows block observation-based overrides; habitat-path bypasses the filter (bcfishpass parity); per-species gate via new `observation_control_apply` column in `parameters_fresh.csv` (TRUE for CH/CM/CO/PK/SK/ST, FALSE for BT/WCT). Added DEAD (Deadman River) as end-to-end test WSG — single TRUE control row at FALLS (356361749, 45743) with 6 anadromous obs upstream and zero habitat coverage. Reproducibility verified: two consecutive `tar_destroy + tar_make` produce bit-identical 46-row rollups (digest `210c3f8254c47ac88573a80d96a2701e`).

## Follow-ups filed

- #46 — Migrate remaining `information_schema` probes to manifest-driven gating
- #48 — `user_barriers_definite` should bypass override per bcfishpass (same family as #44)
