# Plan review (Plan agent, 2026-10-02) — triage

Full findings were returned in the agent reply; triaged here.

| Finding | Verdict | Action |
|---|---|---|
| `no_mad_threshold` relaxes gradient too, contradicting "only that stands in the way" (o9 at 20 % would read it) | **Real** | nomad relaxes size only; a miss passing only with gradient also relaxed reads `fails_gradient_and_width` (cw's "both" label) via `pred_<st>_nomad_g` |
| CSV path (no rules YAML): CM/PK rear would read `no_mad_threshold` | Real, latent | no-range = cw range present and MAD range absent |
| Rule-level `mad:` on a cw group → `s.mad_m3s` missing → SQL error | Real, latent | predicate query joins discharge whenever an expression references `s.mad_m3s` |
| Rule-level window can't be reached by relaxing to the stage min | Real, latent (same as cw) | comment extended; test asserts no bundled rules.yaml sets rule-level `gradient`/`mad` |
| Discharge join written twice | Real | one helper for the source table |
| Fail loud when a mad group's prerequisites are missing | Real | check discharge table + `streams.linear_feature_id` up front |
| Preflight: `frs_habitat_predicates(model)` not asserted | Real | added to required formals |
| Existing tests break on renames | Already handled in working tree | — |
| Parity test that mad exprs wrap `frs_habitat_predicates(spp, "mad")` | Real | added |
| CO on a mad group never exercised in SQL | Real | fixture adds CO (c1/c2) |
| Live discharge values make fixture data-dependent | Accepted | ids picked by `mad_m3s` range, deterministic order; skip if table absent |
| Driver: mad misses unbinned | Real | `width_bin = "mad"` on mad rows, `model` column carried |
| `size_above_max` label | Not taken | documented: `mad_m3s` lets a reader split; maxima bind for CH/CO/ST/WCT rear |
| Warn on `config_hash` mismatch | Scope | documented caveat only |
| Phase 5 must mutate `cfg` and pass the same object to the validator | Noted | Phase 5 does exactly that |
| Phase 5 metric not valid for SK/KO (`spawn_connected`) | Noted | Phase 5 scores CH/CO/BT only |
