# Task: BT/ST accessible_km over-credit — access segmentation drops the frontier (#223)

The shared segmentation break network `gradient_barriers_minimal` is fed the
**minimal-reduced** per-model barriers (`lnk_pipeline_prepare.R:592-593` runs
`fresh::frs_barriers_minimal()`, which keeps only the downstream-most barrier per
flow path). Correct for an access *decision*, wrong as a *segmentation* source: it
strips interior breaks, so a link segment straddles the accessibility frontier and
the whole reach (incl. the blocked part above the barrier) is credited accessible.
Over-credit: BT `accessible_km` +23.6% (FINA), +40% (PCEA). Root-caused in
`research/accessible_km_divergence.md`; filed as #223.

The author already applies the correct "break at every position" rule to the
**orphan** sub-threshold classes (`prepare.R:606-611`); the bug is the real
access-threshold classes don't get the same treatment.

## Verified facts (no assumptions)
- `frs_barriers_minimal` is used **exactly once** in link (`prepare.R:592`) — only
  for the per-model segmentation source.
- `gradient_barriers_minimal`'s **only** consumer is `lnk_pipeline_break.R:110`
  (the `gradient_minimal` break source) — segmentation-only.
- `barriers_<sp>_access` (the access **decision**) is built by a separate path:
  `lnk_barriers_unify()` → `lnk_barriers_views.R:171` (anti-join over unified
  post-override barriers). It does NOT derive from `gradient_barriers_minimal` or
  the `_min` tables — so changing the segmentation source cannot disturb the access
  decision, which already holds the frontier barrier.
- Design decision (user): keep the table name `gradient_barriers_minimal` + add a
  clarifying comment now; file a **separate** rename issue once the fix is confirmed.

## Phase 1 — Reproduce (tests-first)
- [x] Add `data-raw/accessible_km_fix_validate.R`: (a) assert `gradient_barriers_minimal`
      contains the FINA/BT interior frontier (blk 359209845, ~3835); (b) assert the
      segment at measure 3835 has `access_bt = 0`; (c) sum BT `accessible_km`
      FINA/PARS/PCEA vs `fresh.streams_vw_bcfp` (`barriers_bt_dnstr = ''`) and assert
      convergence; (d) assert salmon (CO) stays ≤ tolerance.
- [x] Run against current (pre-fix) persisted state → confirm it FAILS (bug reproduces).

**Phase 1 result (2026-07-03):** script fails pre-fix, exit 1, 7 checks. Parity:
FINA-BT +23.59%, PARS-BT +3.43%, PCEA-BT +40.36%. Structural (blk 359209845):
gradient_barriers_minimal empty, 1 segment straddles 3834.78, no break at frontier,
accessible reach runs to 7998.1 (over-credit 4163 m — matches issue exactly).
- **Validation-set refinement:** FINA/PARS/PCEA are Peace WSGs above the Bennett dam —
  BT-only, **no salmon/ST** (all 0 km), so item (d) is vacuous there. Added **LKEL**
  (smallest persisted WSG with ST + salmon; pre-fix already clean BT +0.7% / ST,CO 0%)
  as the no-regression sentinel. This fulfills (d), not scope creep.
- **One-sided-presence gate:** both-present → assert tolerance; a species present on only
  one side FAILs by default (catches a link collapse-to-zero regression) EXCEPT the
  allowlisted #189 residence cases (`residence_exclude = "LKEL:sk"` — link models CO/CH/CM/PK
  not SK; bcfp lumps all salmon into one barrier group). Keeps the gate scoped to #223
  segmentation parity without masking a real regression in the exit code.
- **Code-check (2 rounds, fresh-eyes agents):** fixed 2 findings — (1) `isTRUE(all(...))`
  on the S3 access_bt check so a hypothetical NULL records a clean FAIL instead of crashing;
  (2) the one-sided-presence gate above (was a silent `n/a`, could have exit-0'd a regression).
  Lint clean (snake_case constants) bar the shared data-raw SQL hanging-indent style.
- Reference predicate `barriers_<group>_dnstr = ''` verified identical to bcfp
  `access_<sp> IN (1,2)`. Tolerance `TOL_PCT = 1.0` (tunable in Phase 3 from post-fix numbers).
- Local fwapg is `:5432` (`postgres`/`postgres`/`fwapg`); `:63333` is the bcfp `bcfishpass`
  tunnel (no `fresh.*`). Script uses the `:5432` recipe per `wsg_run_one.R`.

## Phase 2 — Fix
- [x] `prepare.R:566-594`: union raw `barriers_<model>` (gradient ∪ falls) into
      `gradient_barriers_minimal` instead of the `frs_barriers_minimal`-reduced `_min`
      table. Removed the per-model minimal call + `min_tbl`. Verified `frs_barriers_minimal`
      now unused in link and no other consumer of the `_min` tables (grep).
- [x] Update stale docs (keep table name): `prepare.R` roxygen + `lnk_pipeline_break.R:24`
      — now describe the FULL per-model break set. `devtools::document()` re-run.

**LKEL canary (2026-07-03) — fix validated end-to-end, downstream fallout assessed:**
- **accessible_km converges:** LKEL BT +0.72% → **−0.00%** (exact); ST/CO/CH/CM/PK stay exact.
  Segments 3,376 → 7,446 (~2.2×). Ran in 1.3 min.
- **Downstream outputs safe.** Proven by a pre-fix baseline re-run (stash → run → measure → pop):
  habitat spawning/rearing km are BYTE-IDENTICAL pre-fix and post-fix (ST spawning 108.0, CO 139.2
  both runs) — the fix is neutral on habitat. mapping_code *improves* (mapping_code_bt 711.3 → 714.1
  vs bcfp 714.4).
- **Habitat parity vs bcfp is clean** (corrected measurement — see below): BT spawning +0.0%,
  ST −2.6%, CO −8.7%; rearing all ~+1%.
  - MEASUREMENT-BUG CORRECTION: an earlier note here claimed ST/CO spawning +42%/+24%. That was a
    bad reference predicate — `fresh.streams_vw_bcfp.spawning_<sp>` is coded **0/1/2/3**, and filtering
    `spawning_st = 1` dropped the 2/3 km, undercounting bcfp. Correct predicate is `spawning_<sp> > 0`.
    No such divergence exists; the fix does not touch habitat.
- **Downstream fallout verdict:** no correctness regressions from the denser break set — fresh's
  break machinery dedups + drops sub-1m coincident breaks (no zero-length segments), habitat
  length is conserved, and classify already gated on the FULL gradient set. The only real cost is
  the 2–3.5× segment/storage/runtime increase (inherent to bcfp-matching; intersects perf issue #205).

## Phase 3 — Validate (no-regression)
- [x] Re-ran `lnk_pipeline_run(mapping_code = TRUE)` for FINA / PARS / PCEA / LKEL. Fast:
      1.9 / 2.6 / 3.1 / 1.3 min (segments 26k→70k, 48k→97k, 34k→106k, 3.4k→7.4k). No perf blowup.
- [x] **Validation script ALL CHECKS PASS.** BT accessible_km: FINA +23.59%→**−0.02%**,
      PARS +3.43%→**−0.01%**, PCEA +40.36%→**−0.01%**, LKEL exact. Structural: FINA blk 359209845
      breaks at 3835, segment above is BT-blocked, accessible reach tops at the frontier.
      (Fixed validator S2: breaks round to integer via `measure_precision=0L` so the break lands
      at round(3834.78)=3835 like bcfp — S2 now uses the eps window; still catches the pre-fix straddle.)
- [x] Salmon/ST no-regression (LKEL): accessible_km exact for BT/ST/CO/CH/CM/PK.
- [x] **Habitat + mapping_code parity holds** (corrected `>0` predicate): BT spawning/rearing within
      ~1% on all 4 WSGs; LKEL ST spawning −2.6%, CO spawning −8.7% (modest, link-under, PRE-EXISTING
      + fix-neutral); mapping_code improves. No regression from the denser segmentation.
- [x] `devtools::test()` green (`FAIL 1 | PASS 1254`; the 1 FAIL is the pre-existing
      environmental `public.wsg_outlet` missing-table in test-lnk_wsg_resolve, unrelated).
      Updated the 4 `.lnk_pipeline_prep_minimal` unit tests to the new contract (no
      `frs_barriers_minimal`; raw `barriers_<sp>` in the union). `devtools::document()` re-run.
      No new non-indentation lints on touched files.

**Note — LKEL CO spawning −8.7%** is the one non-trivial habitat gap; it is pre-existing (identical
pre/post fix), link-conservative, and unrelated to #223 (likely the connected-waterbody spawning
nuance documented in `research/bcfishpass_methodology.md`). Out of scope; flag if it recurs broadly.

## Phase 4 — Ship + follow-ups
- [x] `/code-check`; atomic commit (`c86f103`).
- [ ] File the separate rename issue (`gradient_barriers_minimal` → `gradient_barriers_break`).
- [x] Filed #224 — bcfp `dam_dnstr_ind` reservoir-inflow propagation (surfaced in PARS validation, out of scope).

## Phase 5 — COMBINED #221 + #223: provincial accessible+habitat parity (one PR)
Decision (user): merge #221 (`lnk_compare_rollup` accessible_km column + `lnk_rollup_wsg`)
into #223 → **one PR closing both**. #221 surfaced #223; #223 makes #221's accessible
parity pass — inseparable for the proof. Merged 221→223 (PWF conflicts only; R/tests/research clean).
- [x] Merge `origin/221-per-wsg-habitat-access-km-rollup` into the #223 branch.
- [ ] Verify combined package loads + `devtools::test()` green (221 rollup tests + 223 pipeline tests).
- [ ] Re-run 11-WSG cross-section with the fix (done: FINA/PARS/PCEA/LKEL; new: BULK/MORR/KISP/
      LFRA/USKE all-7-species + ELKR/KOTR WCT). ~40 min local, no cyphers (2–3 min/WSG measured).
- [ ] Run `lnk_compare_rollup` across them → per-species per-WSG table: **accessible + spawn + rear**
      parity vs bcfp (tunnel-free `streams_vw_bcfp`). Prove equivalence before PR.
- [ ] Update `research/provincial_parity_*.md` with the accessible columns + the combined result.
- [ ] `/planning-archive`; `/gh-pr-push` (PR closes #221 + #223). NEWS/DESCRIPTION bump as final commit.
- [ ] Return to the accessible_km vignette to demonstrate bcfp equivalence.

## Validation
- `Rscript data-raw/accessible_km_fix_validate.R` exits non-zero if any WSG BT
  `|pct_diff|` exceeds tolerance or segment 3835 is not blocked.
- `Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)"` green.

## Out of scope
- The rename itself (separate issue, per user).
- Wiring BT/ST into `lnk_parity_annotate()` — that's #221 Phase 3, downstream of this fix.
