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
- [ ] `prepare.R:592-593`: union raw `barriers_<model>` (gradient ∪ falls) into
      `gradient_barriers_minimal` instead of the `frs_barriers_minimal`-reduced `_min`
      table. Remove the now-unused per-model minimal call/table.
- [ ] Update stale docs (keep table name): `prepare.R` roxygen `:19-20`/`:34`/`:36`,
      `lnk_pipeline_break.R:24` — say it's now the full per-model break set.

## Phase 3 — Validate (no-regression)
- [ ] Re-run `lnk_pipeline_run` for FINA / PARS / PCEA (mapping_code = TRUE).
- [ ] Validation script passes: BT `accessible_km` converges to bcfp; segment 3835 blocked.
- [ ] Salmon `accessible_km` stays ≤0.27%.
- [ ] Habitat + mapping_code parity holds or improves vs the 99.66% baseline.
- [ ] `devtools::test()` + `lintr::lint_package()` clean; `devtools::document()` re-run.

## Phase 4 — Ship + follow-ups
- [ ] `/code-check`; atomic commit(s) (code + checkbox flips).
- [ ] File the separate rename issue (`gradient_barriers_minimal` → `gradient_barriers_break`).
- [ ] `/planning-archive`; `/gh-pr-push` (PR closes #223). NEWS/DESCRIPTION bump as final commit.
- [ ] Rebase 221 on top of merged fix; unblock #221 Phase 3 (wire BT/ST into parity).
- [ ] Return to the accessible_km vignette to demonstrate bcfp equivalence.

## Validation
- `Rscript data-raw/accessible_km_fix_validate.R` exits non-zero if any WSG BT
  `|pct_diff|` exceeds tolerance or segment 3835 is not blocked.
- `Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)"` green.

## Out of scope
- The rename itself (separate issue, per user).
- Wiring BT/ST into `lnk_parity_annotate()` — that's #221 Phase 3, downstream of this fix.
