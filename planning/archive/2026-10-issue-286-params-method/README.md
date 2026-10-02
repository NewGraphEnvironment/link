## Outcome

Every shipped bundle now declares `parameters_habitat_method.csv`, a per-watershed-group
`cw`/`mad` table. `lnk_pipeline_classify()` hands it to
`fresh::frs_habitat_classify(params_method =)`, so a config can put a group on
bcfishpass's discharge model and have it take effect.
- **The table:** a frozen copy of bcfishpass `example_newgraph`, all `cw`.
- **`mad_m3s`:** joined onto the working streams only; the persist shape is unchanged.
- **Provenance:** `config_hash` carries it, plus a `log_input` fingerprint of the
  discharge table.
- **Pin and preflight:** fresh is pinned at v0.36.2 (floor 0.35.0), and the preflight
  now asserts the `params_method` argument rather than a version.
- **Stream-order rearing bypass:** a `mad` group skips it, as bcfishpass does.
- **The near-miss:** recording the copy's provenance `source:` as the bcfishpass URL
  would have enrolled it in the weekly csv-sync, which auto-merges. An upstream
  `cw`→`mad` flip would then have changed `default` with no review. The plan review and
  code-check round 2 both found it independently.
- **Behaviour change from the bump:** fresh 0.36.0 reversed `frs_db_conn()`'s env
  precedence, which moved one data-raw script off the tunnel on this machine. That script
  now uses `lnk_db_conn()`.
- **Follow-up:** `lnk_habitat_validate()` is still cw-only. The issue body is drafted in
  `findings.md` and not filed.

## Measurement

- **No change.** On ADMS (5 species) and BULK (7 species), the per-species
  `streams_habitat` digests after connect are identical across: branch, main + fresh
  0.36.2, and main + fresh 0.33.0. ADMS also matches main with `mad_m3s` dropped.
  Neither the pin jump, the extra column, nor the all-`cw` table moves output.
- **ADMS on `mad`**, stream (non-waterbody) km, cw → mad:

  | species | spawn | rear |
  |---|---|---|
  | BT | 214.5 → 0 | 346.2 → 0 |
  | CH | 128.3 → 106.4 | 169.8 → 132.4 |
  | CO | 162.1 → 140.1 | 169.8 → 172.3 |

  No CH/CO/SK stream segment falls outside its MAD range. BT keeps 63.5 km of rearing in
  waterbody rules, which inherit no thresholds under either model.
- **A wrong turn, kept:** I first reported zero out-of-range rearing from a truncated
  `grep`. The full output shows 222 CH and 128 CO segments, all inside waterbodies.
- **BULK on `mad`:** no discharge coverage, so 0 km of stream habitat for every species,
  and no error. This is why coverage has to be checked before a group is moved.

## Evidence

`data-raw/logs/params_method_286/*` (harnesses + per-run outputs, 2026-10-02 UTC).
Reviews: `review-plan.md`, `review-p1-round1.md`, `review-p23-round2.md`, `review-round3.md`.
Mechanics: RUNBOOK §7 "Channel width or discharge, per watershed group".

Closed by: PR for #286 (branch `286-thread-fresh-params-method-per-wsg-cw-ma`)
