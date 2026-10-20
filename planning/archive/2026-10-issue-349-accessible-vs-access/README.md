# #349 — `streams_habitat_<sp>.accessible` vs `streams_access.access_<sp>`

## Outcome

fresh's `accessible` (classify time, gating spawning and rearing) and link's `access_<sp>`
(province-wide) disagreed for four reasons: metre-rounded breaks (A), a 0–5 mm near-equal case
fresh's exact `<=` misses (A′), barriers in another group that fresh's AOI-filtered breaks cannot see
(B), and observation lifts counted inside one group only (C, why B's barriers stayed un-lifted).
`streams_access` is now authoritative: the new `lnk_habitat_gate()` settles the persisted habitat
flags on it (overlay rows keep spawning / rearing), after the persist in `lnk_pipeline_run()` and
after `lnk_access(merge = TRUE)` in the recompute; on a dispatch only the recompute gates, because the
gate is one-way. Lifts count every group's observations, and `default`'s RB row has BT's resident
rule. Learned the hard way, by review: the recompute used to be repeatable and could repair model
time; once it writes habitat one-way, every path and doc that assumed otherwise has to change.
Round 3 caught that the plan's own order for settling `fresh_default` (re-gate, then re-model the
holders) would have lost habitat for good. The plan also named the wrong script for the re-gate,
and its "KO records are all in groups where KO is present" was wrong. Write-up:
[`research/access_columns.md`](../../../research/access_columns.md).

## Measurement

- `fresh_default`, 241 groups: forward classes sum to the issue's totals (BT 48,728; RB 481,275;
  KO 55,989 …). A and A′ ≈ halves of 0.25–1 % per species; B: RB 457,912, KO 55,498, BT 33,739,
  GR 20,319 segments; residual small (RB's is ELKR's Flathead).
- Row-level: DUNC's classify breaks hold 6,506 / 6,507 and 588 / 592 of the nearby BT gradient
  barriers at their rounded positions, so #336 is one barrier set read through two predicates
  (corrects its body and the 2026-10-14 CLAUDE.md fact).
- Province-wide counting: ~4 s per group, override step no slower (DUNC 27.6 → 18.6 s).
- Verification build (UPCE, CARP, DUNC in scratch `fresh_349`): forward disagreement 0 after the
  recompute; no lift lost; CARP KO 3,694.8 km, CARP RB 4,419.7 km, UPCE RB 843.4 km open;
  `accessible_km` moves by exactly those km; DUNC BT habitat toward bcfishpass by 0.15 km (#336's
  85 km were accessible km, not habitat). Gate counts UPCE 396 / CARP 77 / DUNC 694 segments.
- `recompute_parity.sh` with the habitat tables in the digest: A == B == C on UPCE + CARP.

## Evidence

`data-raw/logs/access_disagree_349/` (`README.md` indexes it: province-wide, `baseline/`,
`before/`, `after/`, `overrides_scope_time.csv`, `verify_build_349.sh`);
`data-raw/logs/recompute_parity/20261020_045953_*`. Review rounds: `review-round*.md` here.

## Owed

- Settle `fresh_default` (decision 4) — operator's call. **Re-model first, then gate** — a full
  re-model (its recompute settles), or re-model the groups whose lifts change with
  `LNK_HABITAT_GATE=0` and then `bash data-raw/study_area_run.sh --recompute-only
  --run-uid=20261017_004619-3f4c713b --config=default --schema=fresh_default`.
- Re-score the 48/50 bcfishpass parity baseline (ADMS, BULK, BABL, ELKR) after that
- File the fresh-tolerance follow-up after body review (`draft_issue_fresh_tolerance.md`); note the duplicate-persisted
  barrier rows (1,863) as a candidate issue.

Closed by: PR (link#349, link#336)
